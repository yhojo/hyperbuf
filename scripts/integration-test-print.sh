#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Yasuo Hojo
# Integration test (printing): checks print-buffer (File > Print…, Cmd-P) with the real HyperBuf.app (debug build,
# WKWebView). The print dialog is not shown: HYPERBUF_TEST_PRINT_PDF makes the app write the print job to a PDF,
# which is read back with PDFKit.
#   What is printed (the whole document of the selected window, nothing of the frame), a dark appearance
#   (diagrams are drawn light while printing), and printing while the minibuffer is open.
# The command is run directly (the menu item runs the same command; the native Cmd-P path is checked by hand).
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
# A dark appearance is the hard case: paper is white whatever the screen looks like
echo '{ "appearance": "dark" }' > "$tmp/config.json"

# Prints the page count and the text of a PDF (PDFKit)
cat > "$tmp/pdf-text.swift" <<'SWIFT'
import Foundation
import PDFKit

guard let document = PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[1])) else {
    print("{}")
    exit(1)
}
let result: [String: Any] = ["pages": document.pageCount, "text": document.string ?? ""]
print(String(data: try! JSONSerialization.data(withJSONObject: result), encoding: .utf8)!)
SWIFT
swiftc -O -o "$tmp/pdf-text" "$tmp/pdf-text.swift"

export TMP_DIR="$tmp" PROJECT_DIR="$project"
# No file argument and an empty session directory: the frame starts without a buffer
open -a "$app" \
  --env "HYPERBUF_SOCKET_PATH=$tmp/sock/hb.sock" \
  --env "HYPERBUF_TRUSTED_ROOTS=$tmp/trusted.json" \
  --env "HYPERBUF_SESSION_DIR=$tmp/sessions" \
  --env "HYPERBUF_TRUSTED_SITES=$tmp/sites.json" \
  --env "HYPERBUF_CONFIG=$tmp/config.json" \
  --env "HYPERBUF_TEST_COMMANDS=$tmp/cmd" \
  --env "HYPERBUF_TEST_PRINT_PDF=$tmp/out.pdf" \
  --env "HYPERBUF_TEST_PASTEBOARD=com.yhojo.hyperbuf.integration-test.$$"

python3 - <<'PY'
import json, os, subprocess, sys, time

tmp = os.environ["TMP_DIR"]
cmd_dir = os.path.join(tmp, "cmd")
pdf_path = os.path.join(tmp, "out.pdf")
failures = []
seq = [0]

def check(name, condition, detail=""):
    print(("  ✔ " if condition else "  ✘ ") + name + ("" if condition else f"  {detail}"))
    if not condition:
        failures.append(name)

def page(js, timeout=60):
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

HELPERS = """
const P = %s;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const hb = window.__hyperbuf;
const run = async (name) => { await hb.commands[name](); hb.ctx.views.refresh(); };
const fire = async (k, code, mods = {}) => { window.dispatchEvent(new KeyboardEvent('keydown', { key: k, code, bubbles: true, cancelable: true, ...mods })); await sleep(80); };
const input = () => document.getElementById('prompt-input');
const typeIn = (t) => { input().value = t; input().dispatchEvent(new Event('input')); };
const pressIn = (k, code, mods = {}) => input().dispatchEvent(new KeyboardEvent('keydown', { key: k, code, bubbles: true, cancelable: true, ...mods }));
const content = () => document.querySelector('.win.selected .content');
const echo = () => document.getElementById('echo').textContent;
const mini = () => ({ label: document.getElementById('prompt-label').textContent, value: input().value, hidden: document.getElementById('minibuffer').hidden, focus: document.activeElement?.id, candidates: document.querySelectorAll('#candidates li').length });
// The fill colour of the first diagram's nodes tells the Mermaid theme it was drawn with
const diagram = () => document.querySelector('.win.selected .mermaid-diagram svg style')?.textContent.match(/fill:(#[0-9a-fA-F]+)/)?.[1] ?? null;
"""
def run(body):
    return json.loads(page(HELPERS % json.dumps(os.environ["PROJECT_DIR"]) + body))

def printed():
    """The PDF of the last print job (None if nothing was printed); removed so the next job is told apart."""
    if not os.path.exists(pdf_path):
        return None
    out = subprocess.run([os.path.join(tmp, "pdf-text"), pdf_path], capture_output=True, text=True).stdout
    os.remove(pdf_path)
    return json.loads(out)

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

print("Nothing to print")
r = run("await run('print-buffer'); return JSON.stringify({ echo: echo() });")
check("Without a document the command says so and prints nothing", r["echo"] == "No document to print" and printed() is None, r)

print("What is printed: the whole document of the selected window")
r = run("""
await hb.open(P + '/long.md'); await sleep(300);
await run('split-right'); await run('other-window');
await hb.open(P + '/index.md'); await sleep(300);
await run('other-window'); await sleep(200);
content().scrollTop = 2000; await sleep(100);
const before = { name: document.querySelector('.win.selected .ml-name').textContent, windows: document.querySelectorAll('.win').length, top: content().scrollTop };
await run('print-buffer');
return JSON.stringify({ before, top: content().scrollTop, windows: document.querySelectorAll('.win').length });
""")
pdf = printed()
check("The frame has two windows and long.md is selected", r["before"]["windows"] == 2 and r["before"]["name"] == "long.md", r)
check("A PDF of several pages is written", pdf is not None and pdf["pages"] > 1, pdf and pdf["pages"])
text = (pdf or {}).get("text", "")
check("It holds the document from its first to its last section, not just the visible part", "セクション 1 " in text and "セクション 40 の本文" in text, text[:200])
check("The other window's document is not printed", "サンプルプロジェクト" not in text, text[:200])
check("The mode line and the echo area are not printed", "[History" not in text and "long.md" not in text, text[:200])
check("The screen is left as it was (windows, reading position)", r["windows"] == 2 and r["top"] == r["before"]["top"], r)

print("Dark appearance: diagrams are drawn light while printing")
r = run("""
await run('delete-other-windows');
await hb.open(P + '/rendering/04-mermaid.md'); await sleep(1500);
const dark = matchMedia('(prefers-color-scheme: dark)').matches;
const before = diagram();
let during = null;
const onPrint = () => { during = diagram(); };
window.addEventListener('beforeprint', onPrint);
await run('print-buffer');
window.removeEventListener('beforeprint', onPrint);
const after = diagram(); await sleep(500);
return JSON.stringify({ dark, before, during, after, settled: diagram(), diagrams: document.querySelectorAll('.mermaid-diagram svg').length });
""")
pdf = printed()
check("The app is dark and the diagrams are drawn in the dark theme", r["dark"] and r["before"] is not None and r["diagrams"] > 0, r)
check("While printing they are drawn in another (light) theme", r["during"] is not None and r["during"] != r["before"], r)
check("Afterwards they are back in the dark theme and stay so", r["after"] == r["before"] and r["settled"] == r["before"], r)
check("The document is printed", pdf is not None and pdf["pages"] >= 1 and "フローチャート" in pdf["text"], pdf and pdf["text"][:200])

print("Printing while the minibuffer is open (Cmd-P during a prompt)")
r = run("""
await hb.open(P + '/architecture.md'); await sleep(300);
const title = content().querySelector('h1').textContent;
await fire('x', 'KeyX', { altKey: true });                 // M-x
typeIn('split'); await sleep(100);
const before = mini();
await run('print-buffer'); await sleep(100);
const after = mini();
typeIn('split-b'); await sleep(100);                        // the prompt still works
const narrowed = mini();
pressIn('g', 'KeyG', { ctrlKey: true }); await sleep(100);
return JSON.stringify({ title, before, after, narrowed, closed: mini().hidden, windows: document.querySelectorAll('.win').length });
""")
pdf = printed()
text = (pdf or {}).get("text", "")
check("The prompt is open with input and candidates", not r["before"]["hidden"] and r["before"]["label"] == "M-x " and r["before"]["candidates"] > 1, r["before"])
check("The document of the selected window is printed", pdf is not None and r["title"] in text, text[:200])
check("The minibuffer is not printed", "M-x" not in text and "split-below" not in text, text[:200])
check("The prompt is left as it was: label, input, candidates and focus", r["after"] == r["before"] and r["after"]["focus"] == "prompt-input", (r["before"], r["after"]))
check("It goes on working: typing narrows, C-g closes, and no command ran", r["narrowed"]["candidates"] < r["before"]["candidates"] and r["closed"] and r["windows"] == 1, r)

if failures:
    print(f"\nNG: {len(failures)} failed")
    sys.exit(1)
print("\nOK")
PY
