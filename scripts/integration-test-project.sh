#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Yasuo Hojo
# 統合テスト(プロジェクト・ルート): 実際の HyperBuf.app(デバッグビルド、WKWebView)で、
#   C-x p f / C-x p g / C-x p b / C-x p k と、M-s g(基準のディレクトリ)を検査する。docs/dev/buffer-model.md §6。
#   VCS の目印のさかのぼり(.git ディレクトリ・.git ファイル)、目印がないときの default-directory、
#   projectIgnorePaths、プロジェクトごとのバッファの切替・一括 kill。
# キー入力は、ページ内で KeyboardEvent を発行する。GUI セッションが要る。
# 利用者の実際のソケット・設定・信頼するルートは使わない。
set -euo pipefail
cd "$(dirname "$0")/.."
root="$(pwd)"

app/macos/scripts/make-app.sh debug >/dev/null
app="$root/app/macos/.build/HyperBuf.app"

tmp="$(cd "$(mktemp -d)" && pwd -P)"
cleanup() {
  pkill -f "$app/Contents/MacOS/HyperBuf" 2>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT
mkdir -p "$tmp/cmd" "$tmp/sock"

# 試験用のツリー(テンポラリの下。上位に VCS の目印はない)
w="$tmp/work"
mkdir -p "$w/repoA/.git" "$w/repoA/docs/deep" "$w/repoB" "$w/loose/notes" "$w/wrap/.git" "$w/wrap/sub"
echo "gitdir: /elsewhere" > "$w/repoB/.git"            # worktree / submodule の .git はファイル
printf '# Top\n\nneedle in A top\n' > "$w/repoA/top.md"
printf '# Deep\n\nneedle in A deep\n' > "$w/repoA/docs/deep/a.md"
printf '# B\n\nneedle in A docs\n' > "$w/repoA/docs/b.md"
printf '# R\n\nneedle in B\n' > "$w/repoB/r.md"
printf '# L\n\nneedle in loose\n' > "$w/loose/notes/l.md"
printf '# O\n\nneedle in loose other\n' > "$w/loose/other.md"
printf '# W\n\nneedle in wrap\n' > "$w/wrap/sub/w.md"
cat > "$tmp/config.json" <<JSON
{
  "allowPaths": ["$tmp"],
  "projectIgnorePaths": ["$w/wrap", "relative/bad"]
}
JSON

export TMP_DIR="$tmp" WORK_DIR="$w"
open -a "$app" \
  --env "HYPERBUF_SOCKET_PATH=$tmp/sock/hb.sock" \
  --env "HYPERBUF_TRUSTED_ROOTS=$tmp/trusted.json" \
  --env "HYPERBUF_SESSION_DIR=$tmp/sessions" \
  --env "HYPERBUF_TEST_OPEN_LOG=$tmp/open.log" \
  --env "HYPERBUF_TRUSTED_SITES=$tmp/sites.json" \
  --env "HYPERBUF_CONFIG=$tmp/config.json" \
  --env "HYPERBUF_TEST_COMMANDS=$tmp/cmd" \
  --args "$w/repoA/top.md"

python3 - <<'PY'
import json, os, sys, time

tmp = os.environ["TMP_DIR"]
cmd_dir = os.path.join(tmp, "cmd")
failures = []
seq = [0]

def check(name, condition, detail=""):
    print(("  ✔ " if condition else "  ✘ ") + name + ("" if condition else f"  {detail}"))
    if not condition:
        failures.append(name)

def page(js, timeout=30):
    seq[0] += 1
    name = f"{seq[0]:03d}"
    open(f"{cmd_dir}/{name}.js.tmp", "w", encoding="utf-8").write(js)
    os.rename(f"{cmd_dir}/{name}.js.tmp", f"{cmd_dir}/{name}.js")
    deadline = time.time() + timeout
    while not os.path.exists(f"{cmd_dir}/{name}.result"):
        if time.time() > deadline:
            raise RuntimeError("ページの応答がありません: " + js[:80])
        time.sleep(0.05)
    text = open(f"{cmd_dir}/{name}.result", encoding="utf-8").read()
    if text.startswith("ERROR"):
        raise RuntimeError(text)
    return text.removeprefix("RESULT: ")

HELPERS = """
const W = %s;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const hb = window.__hyperbuf;
const fire = async (k, code, mods = {}) => { window.dispatchEvent(new KeyboardEvent('keydown', { key: k, code, bubbles: true, cancelable: true, ...mods })); await sleep(80); };
const input = () => document.getElementById('prompt-input');
const typeIn = (t) => { input().value = t; input().dispatchEvent(new Event('input')); };
const pressIn = (k, code, mods = {}) => input().dispatchEvent(new KeyboardEvent('keydown', { key: k, code, bubbles: true, cancelable: true, ...mods }));
const cands = () => [...document.querySelectorAll('#candidates li')].map((li) => li.textContent);
const label = () => document.getElementById('prompt-label').textContent;
const cancel = async () => { pressIn('g','KeyG',{ctrlKey:true}); await sleep(80); };
const cx = async (...keys) => { await fire('x','KeyX',{ctrlKey:true}); for (const k of keys) await fire(k, 'Key' + k.toUpperCase()); };
const content = () => document.querySelector('.win.selected .content').textContent;
const echo = () => document.getElementById('echo').textContent;
const keys = () => [...hb.ctx.model.buffers.keys()];
"""
def run(body):
    return json.loads(page(HELPERS % json.dumps(os.environ["WORK_DIR"]) + body))

t0 = time.time()
while time.time() - t0 < 60:
    try:
        if page("return String(!!window.__hyperbuf)", timeout=5) == "true":
            break
    except RuntimeError:
        pass
    time.sleep(0.3)
else:
    sys.exit("アプリが起動しませんでした")

print("C-x p f: VCS の目印をさかのぼってルートを求める")
r = run("""
await hb.open(W + '/repoA/docs/deep/a.md'); await sleep(300);
await cx('p', 'f'); await sleep(500);
const a = { label: label(), listed: cands() };
await cancel();
await hb.open(W + '/repoB/r.md'); await sleep(300);
await cx('p', 'f'); await sleep(500);
const b = { label: label(), listed: cands() };
await cancel();
return JSON.stringify({ a, b });
""")
check("深いディレクトリの文書から、.git のあるディレクトリがルートになる(入力欄にルートを示す)",
      r["a"]["label"].endswith("work/repoA/: "), r["a"]["label"])
check("ルート以下の .md が、ルートからの相対パスで並ぶ(ほかのリポジトリは含まない)",
      sorted(r["a"]["listed"]) == ["docs/b.md", "docs/deep/a.md", "top.md"], r["a"]["listed"])
check(".git がファイル(worktree・submodule)でも、目印になる",
      r["b"]["label"].endswith("work/repoB/: ") and r["b"]["listed"] == ["r.md"], r["b"])

print("C-x p f: 目印がないとき・projectIgnorePaths")
r = run("""
await hb.open(W + '/loose/notes/l.md'); await sleep(300);
await cx('p', 'f'); await sleep(500);
const loose = { label: label(), listed: cands() };
await cancel();
await hb.open(W + '/wrap/sub/w.md'); await sleep(300);
await cx('p', 'f'); await sleep(500);
const ignored = { label: label(), listed: cands() };
await cancel();
return JSON.stringify({ loose, ignored });
""")
check("目印がなければ、default-directory(文書のディレクトリ)自身がルートになる",
      r["loose"]["label"].endswith("work/loose/notes/: ") and r["loose"]["listed"] == ["l.md"], r["loose"])
check("projectIgnorePaths のディレクトリは、目印があってもルートにしない(さらに上にも目印がないので、自身)",
      r["ignored"]["label"].endswith("work/wrap/sub/: ") and r["ignored"]["listed"] == ["w.md"], r["ignored"])

print("C-x p g(ルート以下)と M-s g(default-directory 以下)")
r = run("""
await hb.open(W + '/repoA/docs/deep/a.md'); await sleep(300);
await cx('p', 'g'); await sleep(200);
const prompt = label();
typeIn('needle'); pressIn('Enter','Enter'); await hb.keyboard.idle(); await sleep(800);
const project = { text: content(), echo: echo() };
await hb.open(W + '/repoA/docs/deep/a.md'); await sleep(300);
await fire('s','KeyS',{altKey:true}); await fire('g','KeyG'); await sleep(200);
const dirPrompt = label();
typeIn('needle'); pressIn('Enter','Enter'); await hb.keyboard.idle(); await sleep(800);
const directory = { text: content() };
return JSON.stringify({ prompt, project, dirPrompt, directory });
""")
check("C-x p g: プロンプトにルートを示す", r["prompt"].startswith("Search in ") and r["prompt"].endswith("work/repoA/: "), r["prompt"])
t = r["project"]["text"]
check("C-x p g: ルート以下の全体を検索する(top.md・docs/b.md・docs/deep/a.md。repoB は含まない)",
      "docs/deep/a.md" in t and "docs/b.md" in t and "top.md" in t and "r.md" not in t.replace("docs/b.md", ""), t[:400])
t = r["directory"]["text"]
check("M-s g: 従来どおり default-directory 以下だけを検索する(a.md だけ)",
      r["dirPrompt"] == "Search: " and "a.md" in t and "top.md" not in t and "docs/b.md" not in t, (r["dirPrompt"], t[:300]))

print("C-x p b / C-x p k: 同じプロジェクト・ルートのバッファだけ")
r = run("""
for (const p of ['/repoB/r.md', '/loose/other.md', '/repoA/docs/b.md', '/repoA/top.md']) { await hb.open(W + p); await sleep(200); }
await cx('p', 'b'); await sleep(250);
const switching = { label: label(), listed: cands() };
await cancel();
const before = keys();
// C-x p k: no で何も閉じない
await cx('p', 'k'); await sleep(250);
const killLabel = label();
typeIn('no'); pressIn('Enter','Enter'); await hb.keyboard.idle(); await sleep(250);
const afterNo = keys().length;
// yes で、repoA のバッファだけが閉じる
await cx('p', 'k'); await sleep(250);
typeIn('yes'); pressIn('Enter','Enter'); await hb.keyboard.idle(); await sleep(400);
const after = keys();
return JSON.stringify({ switching, before, killLabel, afterNo, after, echo: echo() });
""")
names = r["switching"]["listed"]
check("C-x p b: プロンプトにルートを示し、同じルートのバッファだけが候補になる",
      r["switching"]["label"].startswith("Switch to buffer in ") and r["switching"]["label"].endswith("work/repoA/: ")
      and "b.md" in names and "top.md" in names and "r.md" not in names and "other.md" not in names, r["switching"])
check("C-x p k: 件数とルートを示して確認する", r["killLabel"].startswith("Kill ") and "work/repoA?" in r["killLabel"] and "buffer" in r["killLabel"], r["killLabel"])
check("C-x p k: no なら、何も閉じない", r["afterNo"] == len(r["before"]), (r["afterNo"], len(r["before"])))
w = os.environ["WORK_DIR"]
check("C-x p k: yes なら、同じルートのバッファだけが閉じ、ほかのプロジェクトのバッファは残る",
      not any(k.startswith(w + "/repoA/") for k in r["after"]) and any(k == w + "/repoB/r.md" for k in r["after"]) and any(k == w + "/loose/other.md" for k in r["after"]),
      r["after"])
check("閉じたことが知らされる", r["echo"].startswith("Killed ") and "buffer" in r["echo"], r["echo"])

print("設定の問題")
r = run("""
await fire('h','KeyH',{ctrlKey:true}); await fire('b','KeyB'); await sleep(500);
return JSON.stringify({ text: content() });
""")
check("projectIgnorePaths の不正な項目(相対パス)は、無視して、設定の問題に出る", "projectIgnorePaths" in r["text"], r["text"][:300])

if failures:
    print(f"\nNG: {len(failures)} 件")
    sys.exit(1)
print("\nOK")
PY
