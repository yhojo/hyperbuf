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

export TMP_DIR="$tmp" PROJECT_DIR="$project" APP_PATH="$app"
sock="$tmp/sock/hb.sock"
trusted="$tmp/trusted-roots.json"

open -a "$app" \
  --env "HYPERBUF_SOCKET_PATH=$sock" \
  --env "HYPERBUF_TRUSTED_ROOTS=$trusted" \
  --env "HYPERBUF_TEST_SCRIPT=$root/app/macos/IntegrationTests/ipc-driver.js" \
  --args "$project"

python3 - "$sock" "$trusted" <<'PY'
import json, os, socket, stat, subprocess, sys, time

sock_path, trusted_path = sys.argv[1], sys.argv[2]
tmp, project, app = os.environ["TMP_DIR"], os.environ["PROJECT_DIR"], os.environ["APP_PATH"]
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
loc = call({"v": 1, "op": "get-location"})["result"]["location"]
check("get-location が、開いた位置を返す", loc and loc["path"] == "rendering/02-code.md" and loc["anchor"] == "line:30", loc)

print("open: 範囲外(承認される)")
a = f"{tmp}/approve/repoA/docs/a.md"
r = call({"v": 1, "id": "2", "op": "open", "path": a, "timeoutMs": 20000}, timeout=25)
check("確認で yes と答えると、開ける", r.get("ok"), r)
loc = call({"v": 1, "op": "get-location"})["result"]["location"]
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
time.sleep(2.0)  # ドライバが、残った確認を Esc で取り消す

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
loc = call({"v": 1, "op": "get-location"})["result"]["location"]
check("URL スキームで開ける", loc and loc["path"] == "index.md" and loc["anchor"] == "line:5", loc)
bad = "hyperbuf://open?v=1&path=" + __import__("urllib.parse").parse.quote("/etc/hosts", safe="")
subprocess.run(["open", "-a", app, bad], check=True)
time.sleep(1.0)
loc2 = call({"v": 1, "op": "get-location"})["result"]["location"]
check("不正な URL は、表示を変えない", loc2 == loc, loc2)

if failures:
    print(f"\nNG: {len(failures)} 件")
    sys.exit(1)
print("\nOK")
PY
