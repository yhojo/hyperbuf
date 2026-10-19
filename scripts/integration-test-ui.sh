#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Yasuo Hojo
# Integration test (UI): checks the M3 operations with the real HyperBuf.app (debug build, WKWebView).
#   Incremental search in a document (C-s / C-r), outline-style heading navigation, scroll completion,
#   keymap configuration (keybindings in config.json) and describe-bindings (C-h b).
# Key input fires KeyboardEvent inside the page (the native key path is checked by hand).
# Needs a GUI session. Does not use the user's real socket, config or trusted roots.
set -euo pipefail
cd "$(dirname "$0")/.."
root="$(pwd)"

app/macos/scripts/make-app.sh debug >/dev/null
app="$root/app/macos/.build/HyperBuf.app"
project="$(cd "$root/fixtures/sample-project" && pwd -P)"

tmp="$(mktemp -d)"
cleanup() {
  pkill -f "$app/Contents/MacOS/HyperBuf" 2>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT
mkdir -p "$tmp/cmd" "$tmp/sock"
# User settings: assign back to M-p, remove C-f, put in 3 invalid settings (they should be ignored and listed)
cat > "$tmp/config.json" <<'JSON'
{
  "keybindings": {
    "M-p": "back",
    "C-f": null,
    "C-x 9": "no-such-command",
    "Ctrl-y": "back",
    "C-g": "forward"
  },
  "trustedUrls": ["https://trusted.example/*"]
}
JSON

export TMP_DIR="$tmp" PROJECT_DIR="$project"
open -a "$app" \
  --env "HYPERBUF_SOCKET_PATH=$tmp/sock/hb.sock" \
  --env "HYPERBUF_TRUSTED_ROOTS=$tmp/trusted.json" \
  --env "HYPERBUF_SESSION_DIR=$tmp/sessions" \
  --env "HYPERBUF_TEST_OPEN_LOG=$tmp/open.log" \
  --env "HYPERBUF_TRUSTED_SITES=$tmp/sites.json" \
  --env "HYPERBUF_CONFIG=$tmp/config.json" \
  --env "HYPERBUF_TEST_COMMANDS=$tmp/cmd" \
  --args "$project"

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
            raise RuntimeError("No response from the page: " + js[:80])
        time.sleep(0.05)
    text = open(f"{cmd_dir}/{name}.result", encoding="utf-8").read()
    if text.startswith("ERROR"):
        raise RuntimeError(text)
    return text.removeprefix("RESULT: ")

# Helpers used in the page (key input, state). Prepended to each page()
HELPERS = """
const P = %s;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const hb = window.__hyperbuf;
const press = async (...keys) => {
  for (const [k, code, mods] of keys) window.dispatchEvent(new KeyboardEvent('keydown', { key: k, code, bubbles: true, cancelable: true, ...(mods ?? {}) }));
  await hb.keyboard.idle(); await sleep(80);
};
// C-s is a command that does not finish until confirmed or cancelled, so fire it without waiting for
// completion
const fire = async (k, code, mods = {}) => { window.dispatchEvent(new KeyboardEvent('keydown', { key: k, code, bubbles: true, cancelable: true, ...mods })); await sleep(80); };
const input = () => document.getElementById('prompt-input');
const typeIn = (t) => { input().value = t; input().dispatchEvent(new Event('input')); };
const pressIn = (k, code, mods = {}) => input().dispatchEvent(new KeyboardEvent('keydown', { key: k, code, bubbles: true, cancelable: true, ...mods }));
const content = () => document.querySelector('.win.selected .content');
const heading = () => { let b = null; for (const h of content().querySelectorAll('h1,h2,h3,h4,h5,h6')) if (h.offsetTop <= content().scrollTop + 9) b = h.textContent; return b; };
const mini = () => ({ label: document.getElementById('prompt-label').textContent, count: document.getElementById('prompt-count').textContent, hidden: document.getElementById('minibuffer').hidden });
const C = (k, code) => [['c', 'KeyC', { ctrlKey: true }], [k, code, { ctrlKey: true }]];
"""
def run(body):
    return json.loads(page(HELPERS % json.dumps(os.environ["PROJECT_DIR"]) + body))

# Wait for startup (Web core ready)
t0 = time.time()
while time.time() - t0 < 60:
    try:
        if page("return String(!!window.__hyperbuf)", timeout=5) == "true":
            break
    except RuntimeError:
        pass
    time.sleep(0.3)
else:
    sys.exit("The app did not start")

print("WKWebView features")
r = run("return JSON.stringify({ highlights: !!(window.CSS && CSS.highlights && window.Highlight) })")
check("The CSS Custom Highlight API is available (otherwise only the current match is selected)", r["highlights"], r)

print("Incremental search in the document (C-s / C-r)")
r = run("""
await hb.open(P + '/long.md'); await sleep(300);
await fire('s','KeyS',{ctrlKey:true});
const opened = mini();
typeIn('セクション 3'); await sleep(100);
const typed = { ...mini(), sel: String(getSelection()), hl: CSS.highlights.get('hb-search')?.size, cur: CSS.highlights.get('hb-search-current')?.size, focus: document.activeElement?.id };
pressIn('s','KeyS',{ctrlKey:true}); await sleep(80); const next = mini();
pressIn('r','KeyR',{ctrlKey:true}); await sleep(80); const prev = mini();
typeIn('存在しない語zzz'); await sleep(80); const failing = mini();
pressIn('g','KeyG',{ctrlKey:true}); await sleep(80);
const cancelled = { hidden: mini().hidden, top: content().scrollTop, sel: String(getSelection()), hl: CSS.highlights.has('hb-search') };
await fire('s','KeyS',{ctrlKey:true}); typeIn('セクション 20'); await sleep(80);
pressIn('Enter','Enter'); await sleep(80);
const accepted = { hidden: mini().hidden, sel: String(getSelection()), top: Math.round(content().scrollTop), hl: CSS.highlights.has('hb-search') };
return JSON.stringify({ opened, typed, next, prev, failing, cancelled, accepted });
""")
check("C-s starts a search", r["opened"]["label"] == "I-search: " and not r["opened"]["hidden"], r["opened"])
check("Each keystroke counts matches and selects/highlights", r["typed"]["count"].startswith("[1/") and r["typed"]["cur"] == 1 and r["typed"]["hl"] >= 2, r["typed"])
check("While typing, no selection is made in the document and focus stays in the input (if it were taken, further input would not arrive)", r["typed"]["sel"] == "" and r["typed"]["focus"] == "prompt-input", r["typed"])
check("C-s goes to the next match, C-r to the previous", r["next"]["count"].startswith("[2/") and r["prev"]["count"].startswith("[1/") and "backward" in r["prev"]["label"], (r["next"], r["prev"]))
check("No match shows Failing", r["failing"]["count"] == "Failing" and r["failing"]["label"].startswith("Failing"), r["failing"])
check("C-g returns to the starting position and clears selection/highlight", r["cancelled"]["hidden"] and r["cancelled"]["top"] == 0 and r["cancelled"]["sel"] == "" and not r["cancelled"]["hl"], r["cancelled"])
check("RET stays at that position and keeps the match selected (the highlight disappears)", r["accepted"]["hidden"] and r["accepted"]["sel"] == "セクション 20" and r["accepted"]["top"] > 1000 and not r["accepted"]["hl"], r["accepted"])
r = run("""
content().scrollTop = 0; await sleep(50);
await fire('s','KeyS',{ctrlKey:true}); pressIn('s','KeyS',{ctrlKey:true}); await sleep(100);
const reuse = { text: input().value, count: mini().count };
pressIn('g','KeyG',{ctrlKey:true}); await sleep(50);
await hb.open(P + '/index.md'); await sleep(300);
await fire('s','KeyS',{ctrlKey:true}); typeIn('buffer'); await sleep(80); const lower = mini().count;
typeIn('Buffer'); await sleep(80); const upper = mini().count;
pressIn('g','KeyG',{ctrlKey:true});
return JSON.stringify({ reuse, lower, upper });
""")
check("C-s on an empty input reuses the previous search term", r["reuse"]["text"] == "セクション 20" and r["reuse"]["count"].startswith("["), r["reuse"])
r3 = run("""
await hb.open(P + '/long.md'); await sleep(300);
await fire('s','KeyS',{ctrlKey:true}); typeIn('セクション'); await sleep(80);
pressIn('Process','Enter',{keyCode:229}); await sleep(80);
const duringIme = { hidden: mini().hidden };
pressIn('Enter','Enter'); await sleep(80);
return JSON.stringify({ duringIme, after: mini().hidden });
""")
check("The Enter that confirms Japanese input (keyCode 229) does not end the search; the next Enter does", r3["duringIme"]["hidden"] is False and r3["after"] is True, r3)
r4 = run("""
await hb.open(P + '/long.md'); await sleep(300); content().scrollTop = 0; await sleep(50);
await fire('s','KeyS',{ctrlKey:true}); typeIn('セクション'); await sleep(80);
pressIn('s','KeyS',{ctrlKey:true}); await sleep(50); pressIn('s','KeyS',{ctrlKey:true}); await sleep(80);
typeIn(''); typeIn('セクション'); await sleep(80);
const count = mini().count;
pressIn('g','KeyG',{ctrlKey:true});
return JSON.stringify({ count });
""")
check("Even if the search term becomes empty and is restored (Japanese input confirmation), the chosen match does not move", r4["count"].startswith("[3/"), r4)
r5 = run("""
await hb.open(P + '/long.md'); await sleep(300); content().scrollTop = 0; await sleep(50);
const comp = (t) => { input().value = t; input().dispatchEvent(new InputEvent('input', { isComposing: true })); };
await fire('s','KeyS',{ctrlKey:true});
comp('ｓ'); await sleep(50); comp('セ'); await sleep(50); comp('セクション 7'); await sleep(50);
const during = mini().count;
typeIn(''); typeIn('セクション 7'); await sleep(80);
const after = mini().count;
const selTop = Math.round(content().scrollTop);
pressIn('g','KeyG',{ctrlKey:true});
return JSON.stringify({ during, after });
""")
check("The baseline is not dragged by matches during Japanese composition; the confirmed term is searched from where composition started", r5["during"].startswith("[1/") and r5["after"].startswith("[1/"), r5)
r6 = run("""
await hb.open(P + '/long.md'); await sleep(300);
await fire('x','KeyX',{ctrlKey:true}); await fire('b','KeyB');
const before = input().value;
typeIn('ab'); pressIn('Dead','KeyN',{altKey:true}); input().value = 'ab˜';
input().dispatchEvent(new CompositionEvent('compositionstart')); await sleep(100);
const restored = input().value;
pressIn('g','KeyG',{ctrlKey:true}); await sleep(50);
return JSON.stringify({ restored });
""")
check("Composition started by an Option dead key (such as ˜ of M-n) is cancelled and the input is restored", r6["restored"] == "ab", r6)
r2 = run("""
await hb.open(P + '/long.md'); await sleep(300); content().scrollTop = 0; await sleep(50);
await fire('s','KeyS',{ctrlKey:true}); typeIn('セクション'); await sleep(80);
pressIn('s','KeyS',{ctrlKey:true}); await sleep(50); pressIn('s','KeyS',{ctrlKey:true}); await sleep(80);
const before = mini().count;
pressIn('Enter','Enter'); await sleep(100);
const sel = String(getSelection());
const rg = getSelection().rangeCount ? getSelection().getRangeAt(0) : null;
const where = rg ? Math.round(rg.getBoundingClientRect().top) : null;
const first = (() => { const w = document.createTreeWalker(content(), NodeFilter.SHOW_TEXT); for (let n = w.nextNode(); n; n = w.nextNode()) { const i = n.data.indexOf('セクション'); if (i >= 0) { const q = document.createRange(); q.setStart(n, i); q.setEnd(n, i + 5); return Math.round(q.getBoundingClientRect().top); } } return null; })();
await fire('s','KeyS',{ctrlKey:true}); typeIn('参照'); await sleep(80);
pressIn('g','KeyG',{ctrlKey:true}); await sleep(80);
await fire('s','KeyS',{ctrlKey:true}); pressIn('s','KeyS',{ctrlKey:true}); await sleep(100);
const reused = { text: input().value, count: mini().count };
pressIn('g','KeyG',{ctrlKey:true});
return JSON.stringify({ before, sel, where, first, reused });
""")
check("C-s repeated then RET: the highlighted match stays selected (it does not jump back to the first match)", r2["before"].startswith("[3/") and r2["sel"] == "セクション" and r2["where"] != r2["first"], r2)
check("Even after leaving with C-g, the next C-s C-s uses that search term", r2["reused"]["text"] == "参照", r2["reused"])
check("Only search terms containing uppercase are case-sensitive", r["lower"].startswith("[1/") and r["upper"] == "Failing", r)

print("Outline-style heading navigation and scrolling")
r = run("""
await hb.open(P + '/long.md'); await sleep(300);
const hist = document.querySelector('.mode-line .ml-hist').textContent;
const seq = [];
await press(...C('n','KeyN')); seq.push(heading());
await press(...C('n','KeyN')); seq.push(heading());
await press(...C('n','KeyN')); seq.push(heading());
await press(...C('p','KeyP')); seq.push(heading());
await press(...C('f','KeyF')); seq.push(heading());
await press(...C('b','KeyB')); seq.push(heading());
await press(...C('u','KeyU')); seq.push(heading());
await press(...C('u','KeyU')); const none = document.getElementById('echo').textContent;
const sameHistory = document.querySelector('.mode-line .ml-hist').textContent === hist;
await press(['>','Period',{altKey:true,shiftKey:true}]);
const end = Math.abs(content().scrollTop + content().clientHeight - content().scrollHeight) < 4;
await press(['<','Comma',{altKey:true,shiftKey:true}]);
const top = content().scrollTop;
await press([' ','Space']); const down = Math.round(content().scrollTop);
await press(['Backspace','Backspace']); const up = Math.round(content().scrollTop);
return JSON.stringify({ seq, none, sameHistory, end, top, down, up, page: content().clientHeight });
""")
check("C-c C-n / C-p / C-f / C-b / C-u", r["seq"] == ["セクション 1", "セクション 2", "セクション 3", "セクション 2", "セクション 3", "セクション 2", "長い文書"], r["seq"])
check("There is nothing above the top level", "No parent heading" in r["none"], r["none"])
check("Heading navigation is not pushed onto the reference history", r["sameHistory"])
check("M-> / M-<(Option+Shift+. / ,)", r["end"] and r["top"] == 0, r)
check("SPC scrolls down one screen, DEL scrolls back", r["down"] > r["page"] * 0.8 and r["up"] == 0, r)

print("Link selection (TAB / S-TAB): start from the visible range")
links_path = os.path.join(tmp, "links.md")
open(links_path, "w", encoding="utf-8").write(
    "# リンクの選択\n\n先頭の [top](top.md) です。\n\n"
    + "".join(f"段落 {i}\n\n" for i in range(60))
    + "中ほどの [middle](middle.md) です。\n\n"
    + "".join(f"段落 {i}\n\n" for i in range(60, 120))
    + "末尾の [bottom](bottom.md) です。\n\n"
)
r = run("""
const f = %s;
await hb.open(f); await sleep(400);
const c = content();
const focus = () => document.querySelector('.win.selected .content a.link-focus')?.getAttribute('href') ?? null;
const link = (h) => c.querySelector('a[href="' + h + '"]');
// Scroll until the middle link is visible, then TAB: not the first link, but the first visible one
link('middle.md').scrollIntoView({ block: 'center' }); await sleep(200);
await press(['Tab','Tab']); const first = focus();
await press(['Tab','Tab']); const second = focus();   // next is the last
// If the focused link is no longer visible, re-select from the visible range
c.scrollTop = 0; await sleep(200);
await press(['Tab','Tab']); const afterScrollUp = focus();
// S-TAB starts from the last visible link
link('middle.md').scrollIntoView({ block: 'center' }); await sleep(200);
await press(['Tab','Tab',{ shiftKey: true }]); const back = focus();
return JSON.stringify({ first, second, afterScrollUp, back });
""" % json.dumps(links_path))
check("TAB: when viewing the middle, select the first visible link, not the first in the document", r["first"] == "middle.md", r)
check("Continuing TAB moves to the next link", r["second"] == "bottom.md", r)
check("When the selected link leaves the screen, selection restarts from the visible range (the first link of the document)", r["afterScrollUp"] == "top.md", r)
check("S-TAB: starts from the last link in the visible range", r["back"] == "middle.md", r)

print("Following updates (C-x x u): on an external update, move to the first changed place")
follow_path = os.path.join(os.path.realpath(tmp), "follow.md")
follow_lines = ["# 追従\n\n"] + [f"行 {i}\n\n" for i in range(150)]
open(follow_path, "w", encoding="utf-8").write("".join(follow_lines))
r = run("""
await hb.open(%s, null); await sleep(400);
const c = content(); c.scrollTop = 0; await sleep(100);
const before = document.querySelector('.mode-line .ml-hist').textContent;
await fire('x','KeyX',{ctrlKey:true}); await fire('x','KeyX'); await fire('u','KeyU');
return JSON.stringify({ before, after: document.querySelector('.mode-line .ml-hist').textContent, echo: document.getElementById('echo').textContent });
""" % json.dumps(follow_path))
check("C-x x u turns following on and [Follow] appears in the mode line", "[Follow]" in r["after"] and "[Follow]" not in r["before"] and "on" in r["echo"], r)
follow_lines[101] = "行 100 (変更)\n\n"
open(follow_path + ".tmp", "w", encoding="utf-8").write("".join(follow_lines))
os.replace(follow_path + ".tmp", follow_path)  # replace, like an editor's save
time.sleep(2)
r = run("""
const c = content();
const flash = c.querySelector('.changed-flash');
return JSON.stringify({ top: c.scrollTop, flash: flash ? flash.textContent : null });
""")
check("An external update scrolls to the first changed place", r["top"] > 500, r)
check("The changed place is briefly highlighted", r["flash"] is not None and "行 100" in r["flash"], r)

print("External links (open in browser): confirm -> trustedUrls -> always")
ext_path = os.path.join(tmp, "ext.md")
open(ext_path, "w", encoding="utf-8").write(
    "# 外部リンク\n\n"
    "[信頼する](https://trusted.example/page)\n\n"
    "[その他](https://other.example/x)\n\n"
    "[認証情報つき](https://user:pw@evil.example/)\n\n"
    "[メール](mailto:someone@example.com)\n"
)
r = run("""
const f = %s;
await hb.open(f); await sleep(400);
const c = content();
const click = async (h) => { c.querySelector('a[href="' + h + '"]').click(); await sleep(350); };
const prompt = () => ({ hidden: mini().hidden, label: mini().label });
const answer = async (text) => { typeIn(text); pressIn('Enter','Enter'); await sleep(350); };
const out = {};
await click('https://trusted.example/page'); out.trusted = prompt();
await click('https://other.example/x'); out.confirm = prompt(); await answer('no');
await click('https://other.example/x'); out.again = prompt(); await answer('yes');
await click('https://other.example/x'); out.third = prompt(); await answer('always');
await click('https://other.example/x'); out.remembered = prompt();
await click('https://user:pw@evil.example/'); out.denied = { ...prompt(), echo: document.getElementById('echo').textContent };
await click('mailto:someone@example.com'); out.mailto = prompt(); await answer('no');
return JSON.stringify(out);
""" % json.dumps(ext_path))
opened = open(os.path.join(tmp, "open.log"), encoding="utf-8").read().split() if os.path.exists(os.path.join(tmp, "open.log")) else []
check("A URL matching trustedUrls opens in the browser without confirmation", r["trusted"]["hidden"] and "https://trusted.example/page" in opened, (r["trusted"], opened))
check("Others show the whole URL and ask for confirmation", (not r["confirm"]["hidden"]) and "https://other.example/x" in r["confirm"]["label"] and "always" in r["confirm"]["label"], r["confirm"])
check("Answering no does not open it; yes opens it (confirmed every time)", opened.count("https://other.example/x") == 3 and not r["again"]["hidden"] and not r["third"]["hidden"], (r["again"], opened))
check("always remembers the site and stops asking", r["remembered"]["hidden"] and json.load(open(os.path.join(tmp, "sites.json")))["origins"] == ["https://other.example"], (r["remembered"], opened))
check("A URL containing a user name or password is not opened, without even asking", r["denied"]["hidden"] and "evil.example" not in " ".join(opened) and "not opened" in r["denied"]["echo"], (r["denied"], opened))
check("mailto is confirmed every time (no always option)", (not r["mailto"]["hidden"]) and "always" not in r["mailto"]["label"] and "mailto:someone@example.com" not in opened, r["mailto"])

print("Keymap settings and describe-bindings")
r = run("""
await hb.open(P + '/long.md'); await sleep(300);
await hb.open(P + '/index.md'); await sleep(200);
const before = document.querySelector('.mode-line').textContent;
await press(['p','KeyP',{altKey:true}]);               // M-p (the user assigned it to back)
const afterMp = document.querySelector('.mode-line').textContent;
await press(['f','KeyF',{ctrlKey:true}]);              // C-f (the user removed it → nothing happens)
const afterCf = document.querySelector('.mode-line').textContent;
await press(['b','KeyB',{ctrlKey:true}]);              // C-b (still the default back)
const afterCb = document.querySelector('.mode-line').textContent;
await press(['h','KeyH',{ctrlKey:true}], ['b','KeyB']); // C-h b
const header = document.querySelector('.mode-line').textContent;
const text = content().textContent;
const rows = [...content().querySelectorAll('tr')].map((tr) => tr.textContent);
return JSON.stringify({ before, afterMp, afterCf, afterCb, header, text, rows });
""")
check("M-p assigned by the user works as back", "long.md" in r["afterMp"], r)
check("C-f unbound by the user does nothing", r["afterCf"] == r["afterMp"], r)
check("C-b left at the default works", r["afterCb"] != r["afterCf"] or "History" in r["afterCb"], r["afterCb"])
check("C-h b opens the key binding list (a virtual buffer)", "*Help: keybindings*" in r["header"], r["header"])
check("The list shows the user's binding (M-p) and the default bindings", "M-p" in r["text"] and "describe-bindings" in r["text"] and "C-x 2" in r["text"], r["text"][:300])
forward_row = next((row for row in r["rows"] if "`forward`" in row or row.split("forward")[0:1] and "forward" in row), "")
check("The unbound C-f does not appear among forward bindings (only s-])", "s-]" in forward_row and "C-f" not in forward_row, forward_row)
check("M-p added by the user appears among back bindings", any("M-p" in row and "back" in row for row in r["rows"]), [row for row in r["rows"] if "back" in row])
check("Invalid settings (unknown command, bad notation, C-g) are ignored and listed",
      all(s in r["text"] for s in ["Configuration problems", "no-such-command", "Ctrl-y", "C-g"]), r["text"][:600])

print("Opening files (C-x C-f path completion, C-x p f), minibuffer (candidates, history), kill-buffer")
r = run("""
await hb.open(P + '/index.md'); await sleep(200);
await hb.open(P + '/architecture.md'); await sleep(200);
await hb.open(P + '/long.md'); await sleep(200);
const cands = () => [...document.querySelectorAll('#candidates li')];
await fire('x','KeyX',{ctrlKey:true}); await fire('f','KeyF',{ctrlKey:true});       // C-x C-f
await sleep(200);
const initial = input().value;
const empty = { texts: cands().slice(0, 6).map((li) => li.textContent), count: document.getElementById('prompt-count').textContent };
typeIn(initial + 'arch'); await sleep(200);
const typed = { first: cands()[0]?.textContent, marked: [...(cands()[0]?.querySelectorAll('b') ?? [])].map((b) => b.textContent), on: cands()[0]?.className };
pressIn('Enter','Enter'); await hb.keyboard.idle(); await sleep(250);
const opened = document.querySelector('.mode-line').textContent;
// A directory is not confirmed with RET; it is entered
await fire('x','KeyX',{ctrlKey:true}); await fire('f','KeyF',{ctrlKey:true}); await sleep(200);
const initial2 = input().value;
typeIn(initial2 + 'rend'); await sleep(200);
const dirFirst = cands()[0]?.textContent;
pressIn('Enter','Enter'); await sleep(250);
const descended = { value: input().value, texts: cands().slice(0, 4).map((li) => li.textContent), hidden: document.getElementById('minibuffer').hidden };
pressIn('g','KeyG',{ctrlKey:true}); await sleep(80);
// Input history (M-p)
await fire('x','KeyX',{ctrlKey:true}); await fire('f','KeyF',{ctrlKey:true}); await sleep(200);
pressIn('p','KeyP',{altKey:true}); await sleep(80);
const recalled = input().value;
pressIn('g','KeyG',{ctrlKey:true}); await sleep(80);
return JSON.stringify({ initial, empty, typed, opened, dirFirst, descended, recalled });
""")
check("C-x C-f: the input starts from the base directory (~/ form)", r["initial"].startswith("~/") and r["initial"].endswith("fixtures/sample-project/"), r["initial"])
check("Candidates are only inside that directory (directories first, then .md)", r["empty"]["texts"][0] == "rendering/" and "long.md" in r["empty"]["texts"] and "index.md" in r["empty"]["texts"], r["empty"])
check("The candidate count is shown (n/total)", "/" in r["empty"]["count"], r["empty"])
check("The part matching the typed term is highlighted", r["typed"]["first"] == "architecture.md" and r["typed"]["marked"] == ["arch"] and r["typed"]["on"] == "on", r["typed"])
check("RET opens that document", "architecture.md" in r["opened"], r["opened"])
check("RET on a directory descends into it instead of confirming (the input ends with / and candidates update)", r["dirFirst"] == "rendering/" and r["descended"]["value"].endswith("rendering/") and not r["descended"]["hidden"] and "rendering/" not in r["descended"]["texts"], r["descended"])
check("M-p recalls the previously confirmed value (like Emacs history)", r["recalled"].endswith("architecture.md"), r["recalled"])

r = run("""
await hb.open(P + '/long.md'); await sleep(200);
const cands = () => [...document.querySelectorAll('#candidates li')];
await fire('x','KeyX',{ctrlKey:true}); await fire('p','KeyP'); await fire('f','KeyF'); await sleep(400);   // C-x p f
const label = document.getElementById('prompt-label').textContent;
const listed = cands().map((li) => li.textContent);
typeIn('sample-project/long'); await sleep(250);
const narrowed = cands().map((li) => li.textContent);
typeIn('sample-project/rend'); await sleep(250);
const filtered = cands().map((li) => li.textContent);
pressIn('Enter','Enter'); await hb.keyboard.idle(); await sleep(300);
const header = document.querySelector('.mode-line').textContent;
// Switch the base to ../ to reach a file outside the base
await fire('x','KeyX',{ctrlKey:true}); await fire('p','KeyP'); await fire('f','KeyF'); await sleep(300);
typeIn('../'); await sleep(500);
const outer = cands().map((li) => li.textContent);
pressIn('g','KeyG',{ctrlKey:true}); await sleep(80);
const ROOT = P.slice(0, P.lastIndexOf('/fixtures/'));
return JSON.stringify({ label, listed, narrowed, filtered, header, outer, repoName: ROOT.slice(ROOT.lastIndexOf('/') + 1) });
""")
# The sample project is inside the repository (the root with .git is the top of the repository)
sp = "fixtures/sample-project/"
check("C-x p f: lists everything under the project root (the top with .git) recursively (paths relative to the root)", r["label"].startswith("Find file in ~/") and r["label"].endswith(r["repoName"] + "/: ") and "README.md" in r["listed"] and sp + "long.md" in r["narrowed"], (r["label"], r["listed"][:8], r["narrowed"][:5]))
check("Narrow down and open with RET", r["filtered"] and r["filtered"][0].startswith(sp + "rendering/") and "long.md" not in r["header"] and ".md" in r["header"], (r["filtered"], r["header"]))
check("Typing ../ switches the base and lists files outside the old base too", r["outer"] and "README.md" not in r["outer"] and all("/" in x for x in r["outer"]), r["outer"][:8])

print("Buffer name uniquify and the origin of virtual buffers (search results)")
r = run("""
const ROOT = P.slice(0, P.lastIndexOf('/fixtures/'));
await hb.open(ROOT + '/README.md'); await sleep(200);
await hb.open(ROOT + '/emacs/README.md'); await sleep(200);
const headerBoth = document.querySelector('.mode-line').textContent;
await hb.search('Mermaid'); await sleep(500);
const searchHeader = document.querySelector('.mode-line').textContent;
return JSON.stringify({ headerBoth, searchHeader });
""")
check("The parent directory is added only when several share a name (README.md<emacs>)", "README.md<emacs>" in r["headerBoth"], r["headerBoth"])
check("The virtual search-result buffer gets its origin attached (*search: ...*<emacs>)", "*search: Mermaid*<emacs>" in r["searchHeader"], r["searchHeader"])

r = run("""
await hb.open(P + '/interaction.md'); await sleep(200);
const model = hb.ctx.model;
const hasBefore = model.buffers.has(P + '/interaction.md');
await fire('x','KeyX',{ctrlKey:true}); await fire('k','KeyK');                          // C-x k
const label = document.getElementById('prompt-label').textContent;
pressIn('Enter','Enter'); await hb.keyboard.idle(); await sleep(200);
const win = hb.ctx.model.root.win ?? null;
const histories = (function walk(n) { return n.type === 'leaf' ? [n.win.history.map((e) => e.path)] : n.children.flatMap(walk); })(model.root);
return JSON.stringify({ hasBefore, label, hasAfter: model.buffers.has(P + '/interaction.md'), mru: model.mru.slice(0, 3), histories, header: document.querySelector('.mode-line').textContent, echo: document.getElementById('echo').textContent });
""")
check("C-x k: the default is the current buffer", "interaction.md" in r["label"], r["label"])
check("The buffer is closed and no longer referenced from the history", r["hasBefore"] and not r["hasAfter"] and all(not p.endswith("interaction.md") for h in r["histories"] for p in h), r)
check("A window that showed the closed buffer shows the previous reference", "interaction.md" not in r["header"], r["header"])
check("The kill is announced", "Killed buffer" in r["echo"], r["echo"])

if failures:
    print(f"\nNG: {len(failures)} failed")
    sys.exit(1)
print("\nOK")
PY
