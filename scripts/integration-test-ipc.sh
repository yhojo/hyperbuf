#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Yasuo Hojo
# Integration test (IPC / URL scheme): launches the real HyperBuf.app (debug build) and, from a socket client,
# tries ping, open (outside warn paths / approved warn path / rejected warn path / expired), get-location and
# error cases.
# It also tries "open" through the URL scheme (open -a <app> hyperbuf://…).
# Does not use the user's real socket or the storage for remembered paths (replaced via debug-build
# environment variables).
# Needs a GUI session.
set -euo pipefail
cd "$(dirname "$0")/.."
root="$(pwd)"

app/macos/scripts/make-app.sh debug >/dev/null
(cd cli && swift build >/dev/null)
app="$root/app/macos/.build/HyperBuf.app"
project="$(cd "$root/fixtures/sample-project" && pwd -P)"

tmp="$(cd "$(mktemp -d)" && pwd -P)"
cleanup() {
  pkill -f "$app/Contents/MacOS/HyperBuf" 2>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT

# Under a warn path (warnPaths in the config), create the files to be confirmed. urlconf is outside the warn
# paths (only the URL scheme confirms it)
mkdir -p "$tmp/approve/repoA/docs" "$tmp/deny" "$tmp/wait" "$tmp/urlconf" "$tmp/sock"
printf '# U\n' > "$tmp/urlconf/u.md"
printf '# U2\n' > "$tmp/urlconf/u2.md"
printf '# A\n\n本文 A\n' > "$tmp/approve/repoA/docs/a.md"
printf '# B\n\n本文 B\n' > "$tmp/approve/repoA/docs/b.md"
printf '# D\n' > "$tmp/deny/d.md"
printf '# W\n' > "$tmp/wait/w.md"

# Editor integration (M6): a script standing in for the editor to be invoked (records the arguments it
# receives), and its settings
mkdir -p "$tmp/cmd"
cat > "$tmp/editor.sh" <<EDITOR
#!/bin/sh
printf '%s\n' "\$@" > "$tmp/editor.args"
touch "$tmp/triggered"
EDITOR
chmod +x "$tmp/editor.sh"
printf '{"editorName": "Emacs", "editorCommand": ["%s/editor.sh", "-n", "-e", "(hyperbuf-edit-here)"], "warnPaths": ["%s/approve", "%s/deny", "%s/wait"], "allowPaths": ["%s"]}' "$tmp" "$tmp" "$tmp" "$tmp" "$project" > "$tmp/config.json"

export TMP_DIR="$tmp" PROJECT_DIR="$project" APP_PATH="$app" CLI_PATH="$root/cli/.build/debug/hyperbuf" REPO_ROOT="$root"
sock="$tmp/sock/hb.sock"
trusted="$tmp/trusted-roots.json"

open -a "$app" \
  --env "HYPERBUF_SOCKET_PATH=$sock" \
  --env "HYPERBUF_TRUSTED_ROOTS=$trusted" \
  --env "HYPERBUF_SESSION_DIR=$tmp/sessions" \
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

# Wait for the socket to appear (app launch)
t0 = time.time()
while not os.path.exists(sock_path):
    if time.time() - t0 > 30:
        sys.exit("The socket did not appear (did the app fail to start?)")
    time.sleep(0.05)
time.sleep(1.0)  # wait for the Web core to start (ready)
print(f"App launch to socket: {time.time() - t0:.2f} s")

print("ping")
r = call({"v": 1, "id": "p", "op": "ping"})
check("ping succeeds", r.get("ok") and r["result"]["protocol"] == 1 and r["id"] == "p", r)

print("Permissions")
check("socket is 0600", stat.S_IMODE(os.stat(sock_path).st_mode) == 0o600)
check("its directory is 0700", stat.S_IMODE(os.stat(os.path.dirname(sock_path)).st_mode) == 0o700)

print("open: outside the warn paths (no confirmation)")
r = call({"v": 1, "id": "1", "op": "open", "path": f"{project}/rendering/02-code.md", "line": 30})
check("opens (returned as an absolute path)", r.get("ok") and r["result"]["path"] == f"{project}/rendering/02-code.md", r)
loc = call({"v": 1, "op": "get-view"})["result"]["view"]
check("get-view returns the opened location", loc and loc["path"] == f"{project}/rendering/02-code.md" and loc["anchor"] == "line:30", loc)

print("open: warn path (approved)")
a = f"{tmp}/approve/repoA/docs/a.md"
r = call({"v": 1, "id": "2", "op": "open", "path": a, "timeoutMs": 20000}, timeout=25)
check("answering yes at the confirmation opens it", r.get("ok"), r)
loc = call({"v": 1, "op": "get-view"})["result"]["view"]
check("the document at the absolute path is shown", loc and loc["path"] == os.path.realpath(a), loc)
trusted = json.load(open(trusted_path))
check("what is remembered is the approved file's directory (docs)", trusted["roots"] == [os.path.realpath(f"{tmp}/approve/repoA/docs")], trusted)
check("the store is 0600", stat.S_IMODE(os.stat(trusted_path).st_mode) == 0o600)

print("open: another file in an approved directory (no confirmation)")
t = time.time()
r = call({"v": 1, "id": "3", "op": "open", "path": f"{tmp}/approve/repoA/docs/b.md", "timeoutMs": 3000})
check("opens immediately without confirmation", r.get("ok") and time.time() - t < 2, r)

print("open: warn path (denied)")
r = call({"v": 1, "id": "4", "op": "open", "path": f"{tmp}/deny/d.md", "timeoutMs": 20000}, timeout=25)
check("answering no at the confirmation gives outside-project", (not r.get("ok")) and r["error"]["code"] == "outside-project", r)
check("a denied path is not remembered", len(json.load(open(trusted_path))["roots"]) == 1)

print("open: warn path (timed out)")
r = call({"v": 1, "id": "5", "op": "open", "path": f"{tmp}/wait/w.md", "timeoutMs": 700})
check("no answer gives timeout", (not r.get("ok")) and r["error"]["code"] == "timeout", r)
time.sleep(1.0)
log = open(test_log).read() if os.path.exists(test_log) else ""
check("on timeout, the on-screen confirmation (minibuffer) is closed too", "SAW wait prompt" in log and "HIDDEN wait prompt" in log, log)

print("Error cases")
def code(r): return (r.get("error") or {}).get("code")
check("relative path → bad-request", code(call({"v": 1, "op": "open", "path": "docs/a.md"})) == "bad-request")
check("contains .. → bad-request", code(call({"v": 1, "op": "open", "path": f"{tmp}/approve/../deny/d.md"})) == "bad-request")
check("non-.md → not-markdown", code(call({"v": 1, "op": "open", "path": "/etc/hosts"})) == "not-markdown")
check("nonexistent → not-found", code(call({"v": 1, "op": "open", "path": f"{project}/nope.md"})) == "not-found")
check("unknown op → unknown-op", code(call({"v": 1, "op": "delete", "path": "/tmp/x.md"})) == "unknown-op")
check("unsupported version → unsupported-version", code(call({"v": 2, "op": "ping"})) == "unsupported-version")
check("broken JSON → bad-request", code(raw("{broken")) == "bad-request")
r = call({"v": 1, "op": "ping"})
check("the server keeps running after the errors", r.get("ok"), r)

print("URL scheme (open -a <app> hyperbuf://…)")
url = "hyperbuf://open?v=1&path=" + __import__("urllib.parse").parse.quote(f"{project}/index.md", safe="") + "&line=5"
subprocess.run(["open", "-a", app, url], check=True)
time.sleep(1.5)
loc = call({"v": 1, "op": "get-view"})["result"]["view"]
check("opens via the URL scheme (no confirmation inside allowed paths)", loc and loc["path"] == f"{project}/index.md" and loc["anchor"] == "line:5", loc)
# The URL scheme is a route whose origin cannot be identified, so files not in the allowed paths are confirmed
# even outside warn paths
url_u = "hyperbuf://open?v=1&path=" + __import__("urllib.parse").parse.quote(f"{tmp}/urlconf/u.md", safe="")
subprocess.run(["open", "-a", app, url_u], check=True)
time.sleep(2.0)
log = open(test_log).read() if os.path.exists(test_log) else ""
check("the URL scheme asks for confirmation on files outside the allowed paths", "ANSWERED" in log and "/urlconf/u.md" in log, log[-300:])
loc_u = call({"v": 1, "op": "get-view"})["result"]["view"]
check("opens once approved", loc_u and loc_u["path"] == f"{tmp}/urlconf/u.md", loc_u)
log_before = open(test_log).read()
r = call({"v": 1, "id": "u2", "op": "open", "path": f"{tmp}/urlconf/u2.md", "timeoutMs": 3000})
check("even for the same kind of file, the socket opens without confirmation", r.get("ok") and "u2.md" not in open(test_log).read().replace(log_before, ""), r)
subprocess.run(["open", "-a", app, url], check=True)
time.sleep(1.5)
loc = call({"v": 1, "op": "get-view"})["result"]["view"]
bad = "hyperbuf://open?v=1&path=" + __import__("urllib.parse").parse.quote("/etc/hosts", safe="")
subprocess.run(["open", "-a", app, bad], check=True)
time.sleep(1.0)
loc2 = call({"v": 1, "op": "get-view"})["result"]["view"]
check("an invalid URL does not change the view", loc2 == loc, loc2)

print("hyperbuf CLI")
cli_env = {**os.environ, "HYPERBUF_SOCKET_PATH": sock_path}
def run_cli(*args, cwd=None):
    return subprocess.run([cli, *args], capture_output=True, text=True, env=cli_env, cwd=cwd, timeout=90)

r = run_cli(f"{project}/index.md:9")
check("opens inside the project (exit code 0)", r.returncode == 0, (r.returncode, r.stderr))
loc = call({"v": 1, "op": "get-view"})["result"]["view"]
check("the location opened by the CLI shows up in get-view", loc and loc["path"] == f"{project}/index.md" and loc["anchor"] == "line:9", loc)

r = run_cli("--anchor", "参照履歴", "interaction.md", cwd=project)
check("relative path and --anchor", r.returncode == 0, (r.returncode, r.stderr))
loc = call({"v": 1, "op": "get-view"})["result"]["view"]
check("opens at the anchor", loc and loc["path"] == f"{project}/interaction.md" and loc["anchor"] == "参照履歴", loc)

r = run_cli(project)
check("passing a directory opens index.md", r.returncode == 0, (r.returncode, r.stderr))
loc = call({"v": 1, "op": "get-view"})["result"]["view"]
check("index.md was opened", loc and loc["path"] == f"{project}/index.md", loc)

r = run_cli("--wait", f"{tmp}/approve/repoA/docs/b.md")
check("an approved directory opens without confirmation (exit code 0)", r.returncode == 0, (r.returncode, r.stderr))

r = run_cli("--wait", f"{tmp}/deny/d.md")
check("a denied warn path gives exit code 4", r.returncode == 4, (r.returncode, r.stderr))


r = run_cli(f"{project}/nope.md")
check("a nonexistent file gives exit code 2", r.returncode == 2, (r.returncode, r.stderr))
r = run_cli("/etc/hosts")
check("a non-.md file gives exit code 2", r.returncode == 2, (r.returncode, r.stderr))
r = run_cli("--line", "0", f"{project}/index.md")
check("a usage error gives exit code 1", r.returncode == 1, (r.returncode, r.stderr))
before_print = call({"v": 1, "op": "get-view"})["result"]["view"]
r = run_cli("--print-url", f"{project}/index.md:3")
check("--print-url prints the URL without opening", r.returncode == 0 and r.stdout.startswith("hyperbuf://open?v=1&path="), r.stdout)
loc_after = call({"v": 1, "op": "get-view"})["result"]["view"]
check("--print-url does not change the view", loc_after == before_print, (before_print, loc_after))
r = run_cli("--version")
check("--version", r.returncode == 0 and r.stdout.startswith("hyperbuf "), r.stdout)

print("Editor integration (M6): location pointed at in the viewer → editor")
import hashlib
cmd_dir = os.path.join(tmp, "cmd")
cmd_seq = [0]

def page(js, timeout=20):
    """Run JS inside the page (WebView) and return the result (entry point for debug-build tests)."""
    cmd_seq[0] += 1
    name = f"{cmd_seq[0]:03d}"
    open(f"{cmd_dir}/{name}.js.tmp", "w", encoding="utf-8").write(js)
    os.rename(f"{cmd_dir}/{name}.js.tmp", f"{cmd_dir}/{name}.js")
    deadline = time.time() + timeout
    while not os.path.exists(f"{cmd_dir}/{name}.result"):
        if time.time() > deadline:
            raise RuntimeError("No response from the page: " + js[:80])
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

print("Confirmation timeout: reported distinctly from a denial")
r = call({"v": 1, "id": "t1", "op": "open", "path": f"{tmp}/wait/w.md", "timeoutMs": 700})
check("a timeout without an answer responds with timeout", (not r.get("ok")) and r["error"]["code"] == "timeout", r)
time.sleep(0.4)
echo = page("return document.getElementById('echo').textContent;")
check("the screen shows a timed-out message (not overwritten by the denial message)", "timed out" in echo and "warn path" not in echo, echo)
hidden = page("return String(document.getElementById('minibuffer').hidden);")
check("the confirmation input is closed", hidden.strip().endswith("true"), hidden)

edit_dir = f"{tmp}/approve/repoA/docs"
edit_file = f"{edit_dir}/edit.md"
body = "# 編集テスト\n\n一意な語 uniqueword はここにあります。\n\n重複 dup と dup がある段落です。\n"
open(edit_file, "w", encoding="utf-8").write(body)
real_edit = os.path.realpath(edit_file)

r = call({"v": 1, "op": "open", "path": edit_file, "timeoutMs": 5000})
check("opens a document in an approved directory", r.get("ok"), r)
view = call({"v": 1, "op": "get-view"})["result"]["view"]
check("get-view includes the absolute path (even when relative)", view and view.get("path") == real_edit, view)
r = call({"v": 1, "op": "open", "path": f"{project}/index.md"})
view = call({"v": 1, "op": "get-view"})["result"]["view"]
check("the document path is absolute (absolutePath is the same)", view and view["path"] == f"{project}/index.md" and view["absolutePath"] == view["path"], view)
call({"v": 1, "op": "open", "path": edit_file})

check("no pointed location yet", call({"v": 1, "op": "get-location"})["result"]["location"] is None)

echo = select_and_edit("uniqueword")
check("select and run Edit in Editor → it was invoked", "Invoked" in echo, echo)
loc = call({"v": 1, "op": "get-location"})["result"]["location"]
raw = open(edit_file, "rb").read()
check("exact location", loc and loc["precision"] == "exact" and loc["expect"] == "uniqueword", loc)
check("line/column (code points) match the original Markdown", loc and loc["range"] == {"start": {"line": 3, "column": 6}, "end": {"line": 3, "column": 16}}, loc and loc["range"])
check("SHA-256 of the rendered version of the file is included", loc and loc["file"]["sha256"] == hashlib.sha256(raw).hexdigest() and loc["file"]["size"] == len(raw), loc and loc["file"])
check("the absolute path is included", loc and loc["path"] == real_edit, loc and loc["path"])
check("surrounding context is included", loc and loc["context"]["before"].endswith("一意な語 ") and loc["context"]["after"].startswith(" はここにあります"), loc and loc["context"])
check("the fixed command was executed", os.path.exists(f"{tmp}/triggered"))
args = open(f"{tmp}/editor.args", encoding="utf-8").read().split("\n")[:-1]
check("the command arguments are as configured and contain no location, path or selection", args == ["-n", "-e", "(hyperbuf-edit-here)"], args)

emacs_env = {**os.environ, "HYPERBUF_SOCKET_PATH": sock_path, "LC_ALL": "en_US.UTF-8"}
def emacs_visit(extra=""):
    form = '(progn (hyperbuf-visit-location) (princ (format "L%d C%d" (line-number-at-pos) (- (point) (line-beginning-position)))))'
    return subprocess.run(["emacs", "-Q", "--batch", "-L", os.path.join(os.environ["REPO_ROOT"], "emacs"), "-l", "hyperbuf", "--eval", form],
                          capture_output=True, text=True, env=emacs_env, timeout=60)
if shutil.which("emacs"):
    r = emacs_visit()
    check("Emacs moves to the pointed location (line 3, 5th character from line start)", r.returncode == 0 and r.stdout.strip() == "L3 C5", (r.returncode, r.stdout, r.stderr[-300:]))
    check("shows the string the viewer pointed at", "uniqueword" in r.stderr, r.stderr[-300:])

echo = select_and_edit("dup")
loc = call({"v": 1, "op": "get-location"})["result"]["location"]
check("when the same text appears several times, block (no guessing)", loc and loc["precision"] == "block" and "dup と dup" in loc["expect"], loc)
check("the screen also shows the ambiguity", "ambiguous" in echo, echo)
if shutil.which("emacs"):
    r = emacs_visit()
    check("Emacs moves to the start of the block and reports the ambiguity", r.returncode == 0 and r.stdout.strip() == "L5 C0" and "ambiguous" in r.stderr, (r.returncode, r.stdout, r.stderr[-300:]))

before = call({"v": 1, "op": "get-location"})["result"]["location"]
echo = page("await window.__hyperbuf.search('uniqueword'); await window.__hyperbuf.commands['edit-in-editor'](); return document.getElementById('echo').textContent;")
check("search results (virtual buffer) cannot be edited in the editor", "without a file" in echo, echo)
check("the pointed location is unchanged in that case", call({"v": 1, "op": "get-location"})["result"]["location"] == before)

call({"v": 1, "op": "open", "path": edit_file})
select_and_edit("uniqueword")
open(edit_file, "w", encoding="utf-8").write("# 書き換え\n\n先頭に 1 行が増えた版です。\n\n" + body.split("\n\n", 1)[1])  # the file changes after pointing
time.sleep(1.0)
if shutil.which("emacs"):
    r = emacs_visit()
    check("if the file changed, Emacs does not move and warns (there is no way to continue)", r.returncode != 0 and "not moving" in r.stderr and "rendered" in r.stderr, (r.returncode, r.stdout, r.stderr[-400:]))
    check("on a warning, no move result (L… C…) is printed = it did not move", not __import__("re").search(r"L\d+ C\d+", r.stdout), r.stdout)

print("Emacs(hyperbuf.el)")
if shutil.which("emacs") is None:
    print("  - emacs not found; skipped")
else:
    emacs_env = {**os.environ, "HYPERBUF_SOCKET_PATH": sock_path, "LC_ALL": "en_US.UTF-8"}
    def run_emacs(form, timeout=90):
        return subprocess.run(
            ["emacs", "-Q", "--batch", "-L", os.path.join(os.environ["REPO_ROOT"], "emacs"), "-l", "hyperbuf", "--eval", form],
            capture_output=True, text=True, env=emacs_env, timeout=timeout)

    r = run_emacs(f'(hyperbuf-open "{project}/index.md" 12)')
    check("opens from Emacs directly over the socket", r.returncode == 0, (r.returncode, r.stderr[-300:]))
    loc = call({"v": 1, "op": "get-view"})["result"]["view"]
    check("the opened location (line 12) shows in the viewer", loc and loc["path"] == f"{project}/index.md" and loc["anchor"] == "line:12", loc)

    r = run_emacs(f'(hyperbuf-open "{project}/interaction.md" nil "refs")')
    check("opens with an anchor specified", r.returncode == 0, (r.returncode, r.stderr[-300:]))

    r = run_emacs(f'(hyperbuf-open "{tmp}/approve/repoA/docs/a.md")')
    check("an approved directory also opens without confirmation", r.returncode == 0, (r.returncode, r.stderr[-300:]))

    r = run_emacs(f'(hyperbuf-open "{tmp}/deny/d.md" nil nil nil t)')
    check("a denied warn path becomes an error (outside-project)", r.returncode != 0 and "outside-project" in r.stderr, (r.returncode, r.stderr[-300:]))

    r = run_emacs(f'(let ((hyperbuf-transport (quote cli)) (hyperbuf-executable "{cli}")) (hyperbuf-open "{project}/index.md" 4))')
    check("also opens via the CLI (hyperbuf-transport set to cli)", r.returncode == 0, (r.returncode, r.stderr[-300:]))
    loc = call({"v": 1, "op": "get-view"})["result"]["view"]
    check("the location opened via the CLI shows in the viewer", loc and loc["path"] == f"{project}/index.md" and loc["anchor"] == "line:4", loc)

print("Emacs launches the app and opens (hyperbuf-launch-if-needed)")
if shutil.which("emacs") is None:
    print("  - emacs not found; skipped")
else:
    # Quit the app (the socket file remains, as after a crash). Wait until connections are no longer possible
    subprocess.run(["pkill", "-f", f"{app}/Contents/MacOS/HyperBuf"])
    def listening():
        try:
            c = socket.socket(socket.AF_UNIX)
            c.settimeout(1)
            c.connect(sock_path)
            c.close()
            return True
        except OSError:
            return False
    deadline = time.time() + 10
    while listening() and time.time() < deadline:
        time.sleep(0.1)
    check("the app quits and the socket no longer accepts connections", not listening())

    # Only the launch is swapped for `open` with test environment variables (isolating socket and config).
    # The launch URL (hyperbuf://ping) and the flow of opening over the socket afterwards stay real
    envs = [f"HYPERBUF_SOCKET_PATH={sock_path}", f"HYPERBUF_TRUSTED_ROOTS={trusted_path}",
            f"HYPERBUF_SESSION_DIR={tmp}/sessions", f"HYPERBUF_TEST_LOG={test_log}",
            f"HYPERBUF_CONFIG={tmp}/config.json"]
    env_args = " ".join(f'"--env" "{e}"' for e in envs)
    form = (f'(cl-letf (((symbol-function (quote hyperbuf--launch)) (lambda () '
            f'(call-process "open" nil nil nil "-a" "{app}" {env_args} hyperbuf--ping-url)))) '
            f'(hyperbuf-open "{project}/index.md" 9))')
    r = subprocess.run(
        ["emacs", "-Q", "--batch", "-L", os.path.join(os.environ["REPO_ROOT"], "emacs"), "-l", "cl-lib", "-l", "hyperbuf", "--eval", form],
        capture_output=True, text=True, env={**os.environ, "HYPERBUF_SOCKET_PATH": sock_path, "LC_ALL": "en_US.UTF-8"}, timeout=90)
    check("even with the app not running, Emacs launches it and opens over the socket", r.returncode == 0, (r.returncode, r.stderr[-300:]))
    check("Emacs reports that it is launching", "Launching HyperBuf" in r.stderr, r.stderr[-300:])
    loc = call({"v": 1, "op": "get-view"})["result"]["view"]
    check("the location opened after launch (line 9) shows in the viewer", loc and loc["path"] == f"{project}/index.md" and loc["anchor"] == "line:9", loc)

if failures:
    print(f"\nNG: {len(failures)} failure(s)")
    sys.exit(1)
print("\nOK")
PY
