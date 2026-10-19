#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Yasuo Hojo
# Integration test (session): with the real HyperBuf.app (debug build), checks that the working state comes
# back after quit → relaunch.
#   Multiple frames, window layout, reference history, reading position, selection, the restoreSession
# setting, broken saved data, missing documents.
# Needs a GUI session. Does not use the user's real session, socket, config or trusted roots.
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
# Use a copy of the sample directory for the checks that delete documents (with real paths)
tmp="$(cd "$tmp" && pwd -P)"
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

def page(js, timeout=30, frame=1):
    seq[0] += 1
    name = f"{seq[0]:03d}"
    d = state["cmd"] if frame == 1 else f"{state['cmd']}/frame{frame}"
    deadline0 = time.time() + timeout
    while not os.path.isdir(d):
        if time.time() > deadline0:
            raise RuntimeError(f"No entry point for frame {frame}")
        time.sleep(0.05)
    open(f"{d}/{name}.js.tmp", "w", encoding="utf-8").write(js)
    os.rename(f"{d}/{name}.js.tmp", f"{d}/{name}.js")
    deadline = time.time() + timeout
    while not os.path.exists(f"{d}/{name}.result"):
        if time.time() > deadline:
            raise RuntimeError("No response from the page: " + js[:80])
        time.sleep(0.05)
    text = open(f"{d}/{name}.result", encoding="utf-8").read()
    if text.startswith("ERROR"):
        raise RuntimeError(text)
    return text.removeprefix("RESULT: ")

HELPERS = """
const P = __P__;
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
  wins: wins().map((w) => ({ index: w.index, paths: w.history.map((e) => e.path), scroll: Math.round(w.history[w.index]?.scroll ?? -1) })),
  mru: hb.ctx.model.mru.slice(0, 4),
  echo: document.getElementById('echo').textContent,
});
"""
def run(body, frame=1):
    return json.loads(page(HELPERS.replace("__P__", json.dumps(project)) + body, frame=frame))

def launch(config=None, args=()):
    """Launches the app and waits for the Web core to be ready."""
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
        *(["--args", *args] if args else [])], check=True)
    t0 = time.time()
    while time.time() - t0 < 60:
        try:
            if page("return String(!!window.__hyperbuf)", timeout=5) == "true":
                return
        except RuntimeError:
            pass
        time.sleep(0.3)
    sys.exit("The app did not start")

def quit_app():
    """Normal quit (equivalent to Cmd-Q). The session is saved just before quitting."""
    subprocess.run(["osascript", "-e", f'tell application "{app}" to quit'], check=True, capture_output=True)
    for _ in range(100):
        if subprocess.run(["pgrep", "-f", f"{app}/Contents/MacOS/HyperBuf"], capture_output=True).returncode != 0:
            return True
        time.sleep(0.1)
    return False

print("Building the working state")
launch()
r = run("""
await hb.open(P + '/index.md'); await sleep(200);
await hb.open(P + '/interaction.md'); await sleep(200);
await press(['x','KeyX',{ctrlKey:true}], ['3','Digit3']);
await hb.open(P + '/long.md'); await sleep(300);
const c = document.querySelector('.win.selected .content'); c.scrollTop = 1500; await sleep(300);
// Select part of the body of the left window (the long document)
const body = document.querySelectorAll('.win .content')[0];
const target = [...body.querySelectorAll('p')].find((p) => p.textContent.length > 20);
const r = document.createRange(); r.setStart(target.firstChild, 3); r.setEnd(target.firstChild, 14);
getSelection().removeAllRanges(); getSelection().addRange(r);
window.__picked = String(getSelection());
await sleep(300);
await press(['x','KeyX',{ctrlKey:true}], ['o','KeyO']);
await press(['b','KeyB',{ctrlKey:true}]);
const out = shape(); out.picked = window.__picked;
return JSON.stringify(out);
""")
before = r
check("Split into 2 windows, each with its own history", before["split"] == "row" and len(before["wins"]) == 2, before)
check("The state to restore is ready (left window shows the long document, the right one is selected, history stepped back by one)", before["wins"][0]["paths"][-1].endswith("/long.md") and before["selected"] == 1 and before["wins"][1]["index"] == 0, before)
check("A selection was created", len(before["picked"]) == 11, before["picked"])
check("The normal quit procedure completes on exit", quit_app())
files = glob.glob(os.path.join(sessions, "session.json"))
check("The session is saved as a single file (session.json)", len(files) == 1, files)
if files:
    mode = stat.S_IMODE(os.stat(files[0]).st_mode)
    check("The saved file is readable and writable only by its owner (0600)", mode == 0o600, oct(mode))
    saved = open(files[0], encoding="utf-8").read()
    check("Document content is not saved (only paths and positions)", "セクション 20" not in saved and "Hyperbuf PoC" not in saved, saved[:200])
    doc = json.loads(saved)
    check("Saved as a list of frames (version 2, slots, window rects)", doc["version"] == 2 and [f["slot"] for f in doc["frames"]] == [1] and set(doc["frames"][0]["rect"]) == {"x", "y", "width", "height"}, doc)

print("Relaunch and restore")
launch()
time.sleep(1.0)
after = run("return JSON.stringify(shape());")
check("The window layout, each window's history and the selection are restored", all(after[k] == before[k] for k in ("split", "selected", "wins")), (before, after))
check("The most-recently-used order is restored", after["mru"] == before["mru"], (before["mru"], after["mru"]))
check("The restore is announced", "restored" in after["echo"], after["echo"])
sel = run("await sleep(300); return JSON.stringify({ text: String(getSelection()) });")
check("The selection is restored", sel["text"] == before["picked"], (sel, before["picked"]))
r = run("""
await sleep(500);
const c = [...document.querySelectorAll('.win .content')];
return JSON.stringify({ scrolls: c.map((e) => Math.round(e.scrollTop)), rendered: c.map((e) => e.querySelector('.markdown-body') !== null) });
""")
shown = r
check("The reading position is restored and the document is rendered", shown["rendered"] == [True, True] and abs(shown["scrolls"][0] - before["wins"][0]["scroll"]) < 5 and before["wins"][0]["scroll"] > 1000, (shown, before["wins"]))
r = run("""
const sel = () => wins().find((w) => w.id === hb.ctx.model.selected);
const start = sel().history[sel().index].path;
await press(['f','KeyF',{ctrlKey:true}]);
const fwd = sel().history[sel().index].path;
await press(['b','KeyB',{ctrlKey:true}]);
return JSON.stringify({ start, fwd, back: sel().history[sel().index].path });
""")
back = r
check("Forward / Back work on the restored history (buffers are loaded)", back["start"] != back["fwd"] and back["back"] == back["start"], back)
# Selections whose range ends are elements (a whole paragraph, triple-click, etc.) can also be saved
para = run("""
const body = document.querySelectorAll('.win .content')[0];
const p = [...body.querySelectorAll('p')].find((x) => x.textContent.length > 20);
const r = document.createRange(); r.selectNodeContents(p);
getSelection().removeAllRanges(); getSelection().addRange(r);
await sleep(200); await hb.flushSession();
return JSON.stringify({ text: p.textContent });
""")
time.sleep(1.0)  # the host writes the sessions of all frames after waiting a little
saved_sel = json.load(open(files[0]))["frames"][0]["snapshot"].get("selection")
check("A whole-paragraph selection (edges are elements) is also saved by position and text", saved_sel is not None and saved_sel["text"].strip() == para["text"].strip(), (saved_sel, para))
check("Second quit", quit_app())

print("When a document is gone, the saved data is broken, or restore is disabled in the settings")
os.remove(os.path.join(project, "interaction.md"))
# Rewrite the selected document (long.md): the position strings no longer match, so the selection is not
# restored
long_path = os.path.join(project, "long.md")
text = open(long_path, encoding="utf-8").read()
open(long_path, "w", encoding="utf-8").write("# 先頭を足した\n\n新しい段落です。\n\n" + text)
launch()
time.sleep(1.0)
gone = run("return JSON.stringify(shape());")
check("A missing document is dropped from the history and the rest is restored", all(not any(p.endswith("interaction.md") for p in w["paths"]) for w in gone["wins"]) and "restored" in gone["echo"], gone)
check("Every restored window has a document to show (no empty windows are left)", all(w["scroll"] >= 0 and w["paths"] for w in gone["wins"]), gone)
sel = run("await sleep(300); return JSON.stringify({ text: String(getSelection()) });")
check("If the document was rewritten, a shifted location is not selected (the selection is not restored)", sel["text"] == "", sel)
check("Third quit", quit_app())

open(files[0], "w").write("{broken")
launch()
time.sleep(1.0)
broken = run("return JSON.stringify(shape());")
check("If the saved data is broken, it is not used and the app starts normally (a screen without buffers)", broken["split"] is None and len(broken["wins"]) == 1 and broken["wins"][0]["paths"] == [], broken)
check("Fourth quit", quit_app())

launch()
r = run("""
await hb.open(P + '/long.md'); await sleep(200);
await press(['x','KeyX',{ctrlKey:true}], ['3','Digit3']);
return JSON.stringify(shape());
""")
check("The broken file is recreated on the next save", quit_app() and json.load(open(files[0]))["frames"][0]["snapshot"]["version"] == 1)

launch(config={"restoreSession": False})
time.sleep(1.0)
off = run("return JSON.stringify(shape());")
check("With restoreSession false, nothing is restored", off["split"] is None and off["wins"][0]["paths"] == [], off)
check("Fifth quit", quit_app())
saved_after = json.load(open(files[0]))["frames"][0]["snapshot"]
check("While restoreSession is false, nothing is saved either (the previous save stays as is)", saved_after["root"]["type"] == "split", saved_after["root"]["type"])

print("Multiple frames")
# Start after deleting the saved data (do not carry over the state of the previous scene)
os.remove(files[0])
launch()
run("await hb.open(P + '/index.md'); await sleep(200); await hb.open(P + '/long.md'); await sleep(300); return JSON.stringify(1);")
check("A frame can be created (host.frame)", run("await window.hyperbufHost.frame('make'); return JSON.stringify(1);") == 1)
f2 = run("await hb.open(P + '/architecture.md'); await sleep(300); return JSON.stringify(shape());", frame=2)
check("Frame 2 is an independent workspace (it has only its own buffers)", len(f2["wins"]) == 1 and f2["wins"][0]["paths"] == [project + "/architecture.md"], f2)
f1 = run("return JSON.stringify(shape());")
check("The state of frame 1 is unchanged", f1["wins"][0]["paths"][-1].endswith("/long.md") and not any("architecture" in p for p in f1["wins"][0]["paths"]), f1)
time.sleep(1.2)
doc = json.load(open(files[0]))
check("The session is a list of frames (slots 1 and 2)", [f["slot"] for f in doc["frames"]] == [1, 2] and doc["active"] in (1, 2), doc["frames"])
check("Quit (2 frames)", quit_app())

launch()
time.sleep(1.5)
r1 = run("return JSON.stringify(shape());")
r2 = run("return JSON.stringify(shape());", frame=2)
check("Both frames come back on relaunch", r1["wins"][0]["paths"] == f1["wins"][0]["paths"] and r2["wins"][0]["paths"] == f2["wins"][0]["paths"], (r1, r2))

print("Closing frames")
run("await window.hyperbufHost.frame('delete'); return JSON.stringify(1);", frame=2)
time.sleep(1.5)
doc = json.load(open(files[0]))
check("Closing a non-last frame discards that frame's session", [f["slot"] for f in doc["frames"]] == [1], doc["frames"])
check("Quit (1 frame)", quit_app())
launch()
time.sleep(1.0)
r1 = run("return JSON.stringify(shape());")
check("A closed frame does not come back on relaunch", r1["wins"][0]["paths"] == f1["wins"][0]["paths"], r1)
# Closing the last one = quit: that frame's session remains
try:
    page("await window.hyperbufHost.frame('delete'); return JSON.stringify(1);", timeout=3)
except RuntimeError:
    pass  # the app quits, so a result may not come back
for _ in range(100):
    if subprocess.run(["pgrep", "-f", f"{app}/Contents/MacOS/HyperBuf"], capture_output=True).returncode != 0:
        break
    time.sleep(0.1)
exited = subprocess.run(["pgrep", "-f", f"{app}/Contents/MacOS/HyperBuf"], capture_output=True).returncode != 0
check("Closing the last one quits the app", exited)
doc = json.load(open(files[0]))
check("Closing the last one quits the app and that frame's session is kept", [f["slot"] for f in doc["frames"]] == [1] and doc["frames"][0]["snapshot"]["root"]["type"] in ("leaf", "split"), doc)
launch()
time.sleep(1.0)
r1 = run("return JSON.stringify(shape());")
check("Restore works from the remaining session", r1["wins"][0]["paths"] == f1["wins"][0]["paths"], r1)
ok = quit_app()
check("Quit", ok, subprocess.run(["pgrep", "-fl", f"{app}/Contents/MacOS/HyperBuf"], capture_output=True, text=True).stdout)

if failures:
    print(f"\nNG: {len(failures)} failed")
    sys.exit(1)
print("\nOK")
PY
