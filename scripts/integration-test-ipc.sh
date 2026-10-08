#!/bin/bash
# 統合テスト(IPC・URL スキーム): 実際の HyperBuf.app(デバッグビルド)を起動し、ソケットのクライアントから、
# ping・open(プロジェクト内 / 承認される範囲外 / 拒否される範囲外 / 期限切れ)・get-location・異常系を試す。
# さらに、URL スキーム(open -a <app> hyperbuf://…)での「開く」も試す。
# 利用者の実際のソケット・信頼するルートの保存先は使わない(デバッグビルドの環境変数で差し替える)。
# GUI セッションが要る。
set -euo pipefail
cd "$(dirname "$0")/.."
root="$(pwd)"

app/macos/scripts/make-app.sh debug >/dev/null
(cd cli && swift build >/dev/null)
app="$root/app/macos/.build/HyperBuf.app"
project="$root/fixtures/sample-project"

tmp="$(mktemp -d)"
cleanup() {
  pkill -f "$app/Contents/MacOS/HyperBuf" 2>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT

# プロジェクトの外に、確認の対象になるファイルを作る
mkdir -p "$tmp/approve/repoA/.git" "$tmp/approve/repoA/docs" "$tmp/deny" "$tmp/wait" "$tmp/sock"
echo ref > "$tmp/approve/repoA/.git/HEAD"
printf '# A\n\n本文 A\n' > "$tmp/approve/repoA/docs/a.md"
printf '# B\n\n本文 B\n' > "$tmp/approve/repoA/docs/b.md"
printf '# D\n' > "$tmp/deny/d.md"
printf '# W\n' > "$tmp/wait/w.md"

# エディタ連携(M6): 呼び出されるエディタの代わりのスクリプト(受け取った引数を記録する)と、その設定
mkdir -p "$tmp/cmd"
cat > "$tmp/editor.sh" <<EDITOR
#!/bin/sh
printf '%s\n' "\$@" > "$tmp/editor.args"
touch "$tmp/triggered"
EDITOR
chmod +x "$tmp/editor.sh"
printf '{"editorName": "Emacs", "editorCommand": ["%s/editor.sh", "-n", "-e", "(hyperbuf-edit-here)"]}' "$tmp" > "$tmp/config.json"

export TMP_DIR="$tmp" PROJECT_DIR="$project" APP_PATH="$app" CLI_PATH="$root/cli/.build/debug/hyperbuf" REPO_ROOT="$root"
sock="$tmp/sock/hb.sock"
trusted="$tmp/trusted-roots.json"

open -a "$app" \
  --env "HYPERBUF_SOCKET_PATH=$sock" \
  --env "HYPERBUF_TRUSTED_ROOTS=$trusted" \
  --env "HYPERBUF_TEST_LOG=$tmp/test.log" \
  --env "HYPERBUF_CONFIG=$tmp/config.json" \
  --env "HYPERBUF_TEST_COMMANDS=$tmp/cmd" \
  --env "HYPERBUF_TEST_SCRIPT=$root/app/macos/IntegrationTests/ipc-driver.js" \
  --args "$project"

python3 - "$sock" "$trusted" "$tmp/test.log" <<'PY'
import json, os, shutil, socket, stat, subprocess, sys, time

sock_path, trusted_path, test_log = sys.argv[1], sys.argv[2], sys.argv[3]
tmp, project, app = os.environ["TMP_DIR"], os.environ["PROJECT_DIR"], os.environ["APP_PATH"]
cli = os.environ["CLI_PATH"]
failures = []

def check(name, condition, detail=""):
    print(("  ✔ " if condition else "  ✘ ") + name + ("" if condition else f"  {detail}"))
    if not condition:
        failures.append(name)

def call(request, timeout=10):
    s = socket.socket(socket.AF_UNIX)
    s.settimeout(timeout)
    s.connect(sock_path)
    s.sendall((json.dumps(request, ensure_ascii=False) + "\n").encode())
    buf = b""
    while b"\n" not in buf:
        chunk = s.recv(65536)
        if not chunk:
            break
        buf += chunk
    s.close()
    return json.loads(buf.split(b"\n")[0])

def raw(line, timeout=5):
    s = socket.socket(socket.AF_UNIX)
    s.settimeout(timeout)
    s.connect(sock_path)
    s.sendall(line.encode() + b"\n")
    data = s.recv(65536)
    s.close()
    return json.loads(data.split(b"\n")[0])

# ソケットの出現を待つ(アプリの起動)
t0 = time.time()
while not os.path.exists(sock_path):
    if time.time() - t0 > 30:
        sys.exit("ソケットが現れません(アプリが起動しなかった?)")
    time.sleep(0.05)
time.sleep(1.0)  # Web コアの起動(ready)を待つ
print(f"アプリの起動からソケットまで {time.time() - t0:.2f} 秒")

print("ping")
r = call({"v": 1, "id": "p", "op": "ping"})
check("ping が通る", r.get("ok") and r["result"]["protocol"] == 1 and r["id"] == "p", r)

print("権限")
check("ソケットは 0600", stat.S_IMODE(os.stat(sock_path).st_mode) == 0o600)
check("置き場所のディレクトリは 0700", stat.S_IMODE(os.stat(os.path.dirname(sock_path)).st_mode) == 0o700)

print("open: プロジェクト内")
r = call({"v": 1, "id": "1", "op": "open", "path": f"{project}/rendering/02-code.md", "line": 30})
check("開ける(相対パスで返る)", r.get("ok") and r["result"]["path"] == "rendering/02-code.md", r)
loc = call({"v": 1, "op": "get-view"})["result"]["view"]
check("get-view が、開いた位置を返す", loc and loc["path"] == "rendering/02-code.md" and loc["anchor"] == "line:30", loc)

print("open: 範囲外(承認される)")
a = f"{tmp}/approve/repoA/docs/a.md"
r = call({"v": 1, "id": "2", "op": "open", "path": a, "timeoutMs": 20000}, timeout=25)
check("確認で yes と答えると、開ける", r.get("ok"), r)
loc = call({"v": 1, "op": "get-view"})["result"]["view"]
check("絶対パスの文書が表示されている", loc and loc["path"] == os.path.realpath(a), loc)
trusted = json.load(open(trusted_path))
check("信頼するルートは、.git を含む祖先(repoA)", trusted["roots"] == [os.path.realpath(f"{tmp}/approve/repoA")], trusted)
check("保存先は 0600", stat.S_IMODE(os.stat(trusted_path).st_mode) == 0o600)

print("open: 承認済みのルートの別のファイル(確認なし)")
t = time.time()
r = call({"v": 1, "id": "3", "op": "open", "path": f"{tmp}/approve/repoA/docs/b.md", "timeoutMs": 3000})
check("確認なしで、すぐ開ける", r.get("ok") and time.time() - t < 2, r)

print("open: 範囲外(拒否される)")
r = call({"v": 1, "id": "4", "op": "open", "path": f"{tmp}/deny/d.md", "timeoutMs": 20000}, timeout=25)
check("確認で no と答えると、outside-project", (not r.get("ok")) and r["error"]["code"] == "outside-project", r)
check("拒否したルートは、信頼するルートに入らない", len(json.load(open(trusted_path))["roots"]) == 1)

print("open: 範囲外(期限切れ)")
r = call({"v": 1, "id": "5", "op": "open", "path": f"{tmp}/wait/w.md", "timeoutMs": 700})
check("答えがなければ、timeout", (not r.get("ok")) and r["error"]["code"] == "timeout", r)
time.sleep(1.0)
log = open(test_log).read() if os.path.exists(test_log) else ""
check("期限が切れると、画面の確認(ミニバッファ)も閉じる", "SAW wait prompt" in log and "HIDDEN wait prompt" in log, log)

print("異常系")
def code(r): return (r.get("error") or {}).get("code")
check("相対パス → bad-request", code(call({"v": 1, "op": "open", "path": "docs/a.md"})) == "bad-request")
check(".. を含む → bad-request", code(call({"v": 1, "op": "open", "path": f"{tmp}/approve/../deny/d.md"})) == "bad-request")
check(".md 以外 → not-markdown", code(call({"v": 1, "op": "open", "path": "/etc/hosts"})) == "not-markdown")
check("存在しない → not-found", code(call({"v": 1, "op": "open", "path": f"{project}/nope.md"})) == "not-found")
check("未知の操作 → unknown-op", code(call({"v": 1, "op": "delete", "path": "/tmp/x.md"})) == "unknown-op")
check("未対応のバージョン → unsupported-version", code(call({"v": 2, "op": "ping"})) == "unsupported-version")
check("壊れた JSON → bad-request", code(raw("{broken")) == "bad-request")
r = call({"v": 1, "op": "ping"})
check("異常のあとも、サーバーは動いている", r.get("ok"), r)

print("URL スキーム(open -a <app> hyperbuf://…)")
url = "hyperbuf://open?v=1&path=" + __import__("urllib.parse").parse.quote(f"{project}/index.md", safe="") + "&line=5"
subprocess.run(["open", "-a", app, url], check=True)
time.sleep(1.5)
loc = call({"v": 1, "op": "get-view"})["result"]["view"]
check("URL スキームで開ける", loc and loc["path"] == "index.md" and loc["anchor"] == "line:5", loc)
bad = "hyperbuf://open?v=1&path=" + __import__("urllib.parse").parse.quote("/etc/hosts", safe="")
subprocess.run(["open", "-a", app, bad], check=True)
time.sleep(1.0)
loc2 = call({"v": 1, "op": "get-view"})["result"]["view"]
check("不正な URL は、表示を変えない", loc2 == loc, loc2)

print("hyperbuf CLI")
cli_env = {**os.environ, "HYPERBUF_SOCKET_PATH": sock_path}
def run_cli(*args, cwd=None):
    return subprocess.run([cli, *args], capture_output=True, text=True, env=cli_env, cwd=cwd, timeout=90)

r = run_cli(f"{project}/index.md:9")
check("プロジェクト内を開ける(終了コード 0)", r.returncode == 0, (r.returncode, r.stderr))
loc = call({"v": 1, "op": "get-view"})["result"]["view"]
check("CLI で開いた位置が、get-view に出る", loc and loc["path"] == "index.md" and loc["anchor"] == "line:9", loc)

r = run_cli("--anchor", "参照履歴", "interaction.md", cwd=project)
check("相対パスと --anchor", r.returncode == 0, (r.returncode, r.stderr))
loc = call({"v": 1, "op": "get-view"})["result"]["view"]
check("アンカーで開く", loc and loc["path"] == "interaction.md" and loc["anchor"] == "参照履歴", loc)

r = run_cli("--wait", f"{tmp}/approve/repoA/docs/b.md")
check("承認済みの範囲外は、確認なしで開ける(終了コード 0)", r.returncode == 0, (r.returncode, r.stderr))

r = run_cli("--wait", f"{tmp}/deny/d.md")
check("拒否された範囲外は、終了コード 4", r.returncode == 4, (r.returncode, r.stderr))


r = run_cli(f"{project}/nope.md")
check("存在しないファイルは、終了コード 2", r.returncode == 2, (r.returncode, r.stderr))
r = run_cli("/etc/hosts")
check(".md 以外は、終了コード 2", r.returncode == 2, (r.returncode, r.stderr))
r = run_cli("--line", "0", f"{project}/index.md")
check("使い方の誤りは、終了コード 1", r.returncode == 1, (r.returncode, r.stderr))
before_print = call({"v": 1, "op": "get-view"})["result"]["view"]
r = run_cli("--print-url", f"{project}/index.md:3")
check("--print-url は、開かずに URL を出す", r.returncode == 0 and r.stdout.startswith("hyperbuf://open?v=1&path="), r.stdout)
loc_after = call({"v": 1, "op": "get-view"})["result"]["view"]
check("--print-url は、表示を変えない", loc_after == before_print, (before_print, loc_after))
r = run_cli("--version")
check("--version", r.returncode == 0 and r.stdout.startswith("hyperbuf "), r.stdout)

print("エディタ連携(M6): ビューアで指した位置 → エディタ")
import hashlib
cmd_dir = os.path.join(tmp, "cmd")
cmd_seq = [0]

def page(js, timeout=20):
    """ページ(WebView)の中で JS を実行して、結果を返す(デバッグビルドのテスト用の入口)。"""
    cmd_seq[0] += 1
    name = f"{cmd_seq[0]:03d}"
    open(f"{cmd_dir}/{name}.js.tmp", "w", encoding="utf-8").write(js)
    os.rename(f"{cmd_dir}/{name}.js.tmp", f"{cmd_dir}/{name}.js")
    deadline = time.time() + timeout
    while not os.path.exists(f"{cmd_dir}/{name}.result"):
        if time.time() > deadline:
            raise RuntimeError("ページの応答がありません: " + js[:80])
        time.sleep(0.05)
    return open(f"{cmd_dir}/{name}.result", encoding="utf-8").read()

def select_and_edit(text):
    js = (
        "const root = document.querySelector('.win.selected .content');"
        "const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);"
        "let node; let found = false;"
        f"while ((node = walker.nextNode())) {{ const i = node.textContent.indexOf({json.dumps(text, ensure_ascii=False)});"
        "  if (i >= 0) { const r = document.createRange(); r.setStart(node, i); r.setEnd(node, i + "
        f"{len(text)}); const s = getSelection(); s.removeAllRanges(); s.addRange(r); found = true; break; }} }}"
        "if (!found) return 'NOT FOUND';"
        "await window.__hyperbuf.commands['edit-in-editor']();"
        "return document.getElementById('echo').textContent;"
    )
    return page(js)

edit_dir = f"{tmp}/approve/repoA/docs"
edit_file = f"{edit_dir}/edit.md"
body = "# 編集テスト\n\n一意な語 uniqueword はここにあります。\n\n重複 dup と dup がある段落です。\n"
open(edit_file, "w", encoding="utf-8").write(body)
real_edit = os.path.realpath(edit_file)

r = call({"v": 1, "op": "open", "path": edit_file, "timeoutMs": 5000})
check("信頼するルートの文書を開ける", r.get("ok"), r)
view = call({"v": 1, "op": "get-view"})["result"]["view"]
check("get-view に、絶対パスが付く(相対のときも)", view and view.get("path") == real_edit, view)
r = call({"v": 1, "op": "open", "path": f"{project}/index.md"})
view = call({"v": 1, "op": "get-view"})["result"]["view"]
check("プロジェクト内の文書には、absolutePath が付く", view and view["path"] == "index.md" and view["absolutePath"].endswith("/fixtures/sample-project/index.md"), view)
call({"v": 1, "op": "open", "path": edit_file})

check("指した位置は、まだない", call({"v": 1, "op": "get-location"})["result"]["location"] is None)

echo = select_and_edit("uniqueword")
check("選択して「エディタで編集」→ 呼び出された", "呼び出しました" in echo, echo)
loc = call({"v": 1, "op": "get-location"})["result"]["location"]
raw = open(edit_file, "rb").read()
check("正確(exact)な位置", loc and loc["precision"] == "exact" and loc["expect"] == "uniqueword", loc)
check("行・桁(コードポイント)が、元の Markdown と合う", loc and loc["range"] == {"start": {"line": 3, "column": 6}, "end": {"line": 3, "column": 16}}, loc and loc["range"])
check("描画した版のファイルの SHA-256 が付く", loc and loc["file"]["sha256"] == hashlib.sha256(raw).hexdigest() and loc["file"]["size"] == len(raw), loc and loc["file"])
check("絶対パスが付く", loc and loc["path"] == real_edit, loc and loc["path"])
check("前後の文脈が付く", loc and loc["context"]["before"].endswith("一意な語 ") and loc["context"]["after"].startswith(" はここにあります"), loc and loc["context"])
check("固定のコマンドが実行された", os.path.exists(f"{tmp}/triggered"))
args = open(f"{tmp}/editor.args", encoding="utf-8").read().split("\n")[:-1]
check("コマンドの引数は、設定のとおりで、位置・パス・選択を含まない", args == ["-n", "-e", "(hyperbuf-edit-here)"], args)

emacs_env = {**os.environ, "HYPERBUF_SOCKET_PATH": sock_path, "LC_ALL": "en_US.UTF-8"}
def emacs_visit(extra=""):
    form = '(progn (hyperbuf-visit-location) (princ (format "L%d C%d" (line-number-at-pos) (- (point) (line-beginning-position)))))'
    return subprocess.run(["emacs", "-Q", "--batch", "-L", os.path.join(os.environ["REPO_ROOT"], "emacs"), "-l", "hyperbuf", "--eval", form],
                          capture_output=True, text=True, env=emacs_env, timeout=60)
if shutil.which("emacs"):
    r = emacs_visit()
    check("Emacs が、指した位置(3 行目、行頭から 5 文字目)へ移動する", r.returncode == 0 and r.stdout.strip() == "L3 C5", (r.returncode, r.stdout, r.stderr[-300:]))
    check("ビューアが指していた文字列を表示する", "uniqueword" in r.stderr, r.stderr[-300:])

echo = select_and_edit("dup")
loc = call({"v": 1, "op": "get-location"})["result"]["location"]
check("同じ文言が複数あるときは、block(推測しない)", loc and loc["precision"] == "block" and "dup と dup" in loc["expect"], loc)
check("画面にも、曖昧であることが出る", "曖昧" in echo, echo)
if shutil.which("emacs"):
    r = emacs_visit()
    check("Emacs は、ブロックの先頭へ移動し、曖昧だと知らせる", r.returncode == 0 and r.stdout.strip() == "L5 C0" and "曖昧" in r.stderr, (r.returncode, r.stdout, r.stderr[-300:]))

before = call({"v": 1, "op": "get-location"})["result"]["location"]
echo = page("await window.__hyperbuf.search('uniqueword'); await window.__hyperbuf.commands['edit-in-editor'](); return document.getElementById('echo').textContent;")
check("検索結果(仮想 buffer)は、エディタで編集できない", "ファイルに対応しない" in echo, echo)
check("このとき、指した位置は変わらない", call({"v": 1, "op": "get-location"})["result"]["location"] == before)

call({"v": 1, "op": "open", "path": edit_file})
select_and_edit("uniqueword")
open(edit_file, "w", encoding="utf-8").write("# 書き換え\n\n先頭に 1 行が増えた版です。\n\n" + body.split("\n\n", 1)[1])  # 指したあとに、ファイルが変わる
time.sleep(1.0)
if shutil.which("emacs"):
    r = emacs_visit()
    check("ファイルが変わったら、Emacs は移動せず、警告する(続行の手段はない)", r.returncode != 0 and "移動しません" in r.stderr and "描画した版" in r.stderr, (r.returncode, r.stdout, r.stderr[-400:]))
    check("警告のとき、移動の結果(L… C…)は出ない = 移動していない", not __import__("re").search(r"L\d+ C\d+", r.stdout), r.stdout)

print("Emacs(hyperbuf.el)")
if shutil.which("emacs") is None:
    print("  - emacs が見つからないので、省略")
else:
    emacs_env = {**os.environ, "HYPERBUF_SOCKET_PATH": sock_path, "LC_ALL": "en_US.UTF-8"}
    def run_emacs(form, timeout=90):
        return subprocess.run(
            ["emacs", "-Q", "--batch", "-L", os.path.join(os.environ["REPO_ROOT"], "emacs"), "-l", "hyperbuf", "--eval", form],
            capture_output=True, text=True, env=emacs_env, timeout=timeout)

    r = run_emacs(f'(hyperbuf-open "{project}/index.md" 12)')
    check("Emacs から、直接ソケットで開ける", r.returncode == 0, (r.returncode, r.stderr[-300:]))
    loc = call({"v": 1, "op": "get-view"})["result"]["view"]
    check("開いた位置(行 12)が、ビューアに出る", loc and loc["path"] == "index.md" and loc["anchor"] == "line:12", loc)

    r = run_emacs(f'(hyperbuf-open "{project}/interaction.md" nil "refs")')
    check("アンカーを指定して開ける", r.returncode == 0, (r.returncode, r.stderr[-300:]))

    r = run_emacs(f'(hyperbuf-open "{tmp}/approve/repoA/docs/a.md")')
    check("承認済みの範囲外も、確認なしで開ける", r.returncode == 0, (r.returncode, r.stderr[-300:]))

    r = run_emacs(f'(hyperbuf-open "{tmp}/deny/d.md" nil nil nil t)')
    check("拒否された範囲外は、エラー(outside-project)になる", r.returncode != 0 and "outside-project" in r.stderr, (r.returncode, r.stderr[-300:]))

    r = run_emacs(f'(let ((hyperbuf-transport (quote cli)) (hyperbuf-executable "{cli}")) (hyperbuf-open "{project}/index.md" 4))')
    check("CLI 経由(hyperbuf-transport を cli)でも開ける", r.returncode == 0, (r.returncode, r.stderr[-300:]))
    loc = call({"v": 1, "op": "get-view"})["result"]["view"]
    check("CLI 経由で開いた位置が、ビューアに出る", loc and loc["path"] == "index.md" and loc["anchor"] == "line:4", loc)

if failures:
    print(f"\nNG: {len(failures)} 件")
    sys.exit(1)
print("\nOK")
PY
