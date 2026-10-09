#!/bin/bash
# 統合テスト(セッション): 実際の HyperBuf.app(デバッグビルド)で、終了 → 再起動のあとに、作業中の状態が戻ることを検査する。
#   window の配置・参照履歴・閲覧位置・選択中の window、restoreSession の設定、壊れた保存データ、なくなった文書。
# GUI セッションが要る。利用者の実際のセッション・ソケット・設定・信頼するルートは使わない。
set -euo pipefail
cd "$(dirname "$0")/.."
root="$(pwd)"

app/macos/scripts/make-app.sh debug >/dev/null
app="$root/app/macos/.build/HyperBuf.app"

tmp="$(mktemp -d)"
cleanup() {
  pkill -f "$app/Contents/MacOS/HyperBuf" 2>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT
# 文書を消す検査のために、サンプルのプロジェクトを複製して使う
cp -R "$root/fixtures/sample-project" "$tmp/project"

export TMP_DIR="$tmp" APP="$app" PROJECT_DIR="$tmp/project"
python3 - <<'PY'
import glob, json, os, stat, subprocess, sys, time

tmp, app, project = os.environ["TMP_DIR"], os.environ["APP"], os.environ["PROJECT_DIR"]
sessions = os.path.join(tmp, "sessions")
failures = []
seq = [0]
state = {"cmd": None}

def check(name, condition, detail=""):
    print(("  ✔ " if condition else "  ✘ ") + name + ("" if condition else f"  {detail}"))
    if not condition:
        failures.append(name)

def page(js, timeout=30):
    seq[0] += 1
    name = f"{seq[0]:03d}"
    d = state["cmd"]
    open(f"{d}/{name}.js.tmp", "w", encoding="utf-8").write(js)
    os.rename(f"{d}/{name}.js.tmp", f"{d}/{name}.js")
    deadline = time.time() + timeout
    while not os.path.exists(f"{d}/{name}.result"):
        if time.time() > deadline:
            raise RuntimeError("ページの応答がありません: " + js[:80])
        time.sleep(0.05)
    text = open(f"{d}/{name}.result", encoding="utf-8").read()
    if text.startswith("ERROR"):
        raise RuntimeError(text)
    return text.removeprefix("RESULT: ")

HELPERS = """
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const hb = window.__hyperbuf;
const press = async (...keys) => {
  for (const [k, code, mods] of keys) window.dispatchEvent(new KeyboardEvent('keydown', { key: k, code, bubbles: true, cancelable: true, ...(mods ?? {}) }));
  await hb.keyboard.idle(); await sleep(80);
};
const wins = () => (function walk(n) { return n.type === 'leaf' ? [n.win] : n.children.flatMap(walk); })(hb.ctx.model.root);
const shape = () => ({
  split: hb.ctx.model.root.type === 'split' ? hb.ctx.model.root.dir : null,
  selected: wins().findIndex((w) => w.id === hb.ctx.model.selected),
  wins: wins().map((w) => ({ index: w.index, paths: w.history.map((e) => e.path), scroll: Math.round(w.history[w.index].scroll) })),
  mru: hb.ctx.model.mru.slice(0, 4),
  echo: document.getElementById('echo').textContent,
});
"""
def run(body):
    return json.loads(page(HELPERS + body))

def launch(config=None):
    """アプリを起動して、Web コアの準備を待つ。"""
    n = len(glob.glob(os.path.join(tmp, "cmd*")))
    state["cmd"] = os.path.join(tmp, f"cmd{n}")
    os.makedirs(state["cmd"])
    cfg = os.path.join(tmp, "config.json")
    open(cfg, "w").write(json.dumps(config or {}))
    subprocess.run(["open", "-n", "-a", app,
        "--env", f"HYPERBUF_SOCKET_PATH={tmp}/sock{n}.sock",
        "--env", f"HYPERBUF_TRUSTED_ROOTS={tmp}/trusted.json",
        "--env", f"HYPERBUF_CONFIG={cfg}",
        "--env", f"HYPERBUF_SESSION_DIR={sessions}",
        "--env", f"HYPERBUF_TEST_COMMANDS={state['cmd']}",
        "--args", project], check=True)
    t0 = time.time()
    while time.time() - t0 < 60:
        try:
            if page("return String(!!window.__hyperbuf)", timeout=5) == "true":
                return
        except RuntimeError:
            pass
        time.sleep(0.3)
    sys.exit("アプリが起動しませんでした")

def quit_app():
    """通常の終了(⌘Q 相当)。終了の直前に、セッションが保存される。"""
    subprocess.run(["osascript", "-e", f'tell application "{app}" to quit'], check=True, capture_output=True)
    for _ in range(100):
        if subprocess.run(["pgrep", "-f", f"{app}/Contents/MacOS/HyperBuf"], capture_output=True).returncode != 0:
            return True
        time.sleep(0.1)
    return False

print("作業の状態を作る")
launch()
r = run("""
await hb.open('index.md'); await sleep(200);
await hb.open('interaction.md'); await sleep(200);
await press(['x','KeyX',{ctrlKey:true}], ['3','Digit3']);
await hb.open('long.md'); await sleep(300);
const c = document.querySelector('.win.selected .content'); c.scrollTop = 1500; await sleep(300);
await press(['x','KeyX',{ctrlKey:true}], ['o','KeyO']);
await press(['b','KeyB',{ctrlKey:true}]);
return JSON.stringify(shape());
""")
before = r
check("2 つの window に分割され、それぞれの履歴がある", before["split"] == "row" and len(before["wins"]) == 2, before)
check("復元の対象の状態ができた(左の window が長い文書、選択は右で、履歴を 1 つ戻してある)", before["wins"][0]["paths"][-1] == "long.md" and before["selected"] == 1 and before["wins"][1]["index"] == 0, before)
check("終了するとき、通常の終了の手順が完了する", quit_app())
files = glob.glob(os.path.join(sessions, "*.json"))
check("セッションが、プロジェクトごとのファイルに保存される", len(files) == 1, files)
if files:
    mode = stat.S_IMODE(os.stat(files[0]).st_mode)
    check("保存ファイルは本人だけが読み書きできる(0600)", mode == 0o600, oct(mode))
    saved = open(files[0], encoding="utf-8").read()
    check("文書の内容は保存しない(パスと位置だけ)", "セクション 20" not in saved and "Hyperbuf PoC" not in saved, saved[:200])

print("再起動して復元する")
launch()
time.sleep(1.0)
after = run("return JSON.stringify(shape());")
check("window の配置・各 window の履歴・選択が戻る", all(after[k] == before[k] for k in ("split", "selected", "wins")), (before, after))
check("最近使った順が戻る", after["mru"] == before["mru"], (before["mru"], after["mru"]))
check("復元したことが知らされる", "復元" in after["echo"], after["echo"])
r = run("""
await sleep(500);
const c = [...document.querySelectorAll('.win .content')];
return JSON.stringify({ scrolls: c.map((e) => Math.round(e.scrollTop)), rendered: c.map((e) => e.querySelector('.markdown-body') !== null) });
""")
shown = r
check("閲覧位置が戻り、文書が描画されている", shown["rendered"] == [True, True] and abs(shown["scrolls"][0] - before["wins"][0]["scroll"]) < 5 and before["wins"][0]["scroll"] > 1000, (shown, before["wins"]))
r = run("""
const sel = () => wins().find((w) => w.id === hb.ctx.model.selected);
const start = sel().history[sel().index].path;
await press(['f','KeyF',{ctrlKey:true}]);
const fwd = sel().history[sel().index].path;
await press(['b','KeyB',{ctrlKey:true}]);
return JSON.stringify({ start, fwd, back: sel().history[sel().index].path });
""")
back = r
check("復元した履歴で、Forward / Back が動く(buffer が読み込まれている)", back["start"] != back["fwd"] and back["back"] == back["start"], back)
check("2 回目の終了", quit_app())

print("文書がなくなった・保存が壊れた・設定で無効にした場合")
os.remove(os.path.join(project, "interaction.md"))
launch()
time.sleep(1.0)
gone = run("return JSON.stringify(shape());")
check("なくなった文書は、履歴から外れ、残りで復元される", all("interaction.md" not in w["paths"] for w in gone["wins"]) and "復元" in gone["echo"], gone)
check("3 回目の終了", quit_app())

open(files[0], "w").write("{broken")
launch()
time.sleep(1.0)
broken = run("return JSON.stringify(shape());")
check("保存が壊れていれば、使わずに、通常どおり起動する", broken["split"] is None and len(broken["wins"]) == 1 and broken["wins"][0]["paths"] == ["index.md"], broken)
check("4 回目の終了", quit_app())

launch()
r = run("""
await hb.open('long.md'); await sleep(200);
await press(['x','KeyX',{ctrlKey:true}], ['3','Digit3']);
return JSON.stringify(shape());
""")
check("壊れていたファイルは、次の保存で作り直される", quit_app() and json.load(open(files[0]))["snapshot"]["version"] == 1)

launch(config={"restoreSession": False})
time.sleep(1.0)
off = run("return JSON.stringify(shape());")
check("restoreSession が false なら、復元しない", off["split"] is None and off["wins"][0]["paths"] == ["index.md"], off)
check("5 回目の終了", quit_app())
saved_after = json.load(open(files[0]))["snapshot"]
check("restoreSession が false の間は、保存もしない(前回の保存が、そのまま残る)", saved_after["root"]["type"] == "split", saved_after["root"]["type"])

if failures:
    print(f"\nNG: {len(failures)} 件")
    sys.exit(1)
print("\nOK")
PY
