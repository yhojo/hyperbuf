#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Yasuo Hojo
# Integration test: builds the Web core and opens all the project's documents in HyperBuf.app (debug build) to
# check them.
# Needs a GUI session (to launch the WebView). Expected to work on CI's macOS runners too, but unverified.
# Usage: scripts/integration-test.sh [project directory]   (default: fixtures/sample-project)
set -euo pipefail
cd "$(dirname "$0")/.."

project="$(cd "${1:-fixtures/sample-project}" && pwd -P)"
script="$(mktemp)"
# Pass the directory to check (an absolute path) at the front
{ printf 'const PROJECT = %s;\n' "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$project")"; cat "$(pwd)/app/macos/IntegrationTests/smoke.js"; } >"$script"

(cd core && npm ci --silent && npm run build >/dev/null)
(cd app/macos && swift build >/dev/null)

state=""
log="$(mktemp)"
trap 'rm -rf "$log" "$script" "$state"' EXIT
state="$(mktemp -d)"
# Does not touch the user's real socket, remembered paths or sessions (no conflict even if a HyperBuf is
# running)
HYPERBUF_SOCKET_PATH="$state/hb.sock" HYPERBUF_TRUSTED_ROOTS="$state/trusted.json" HYPERBUF_SESSION_DIR="$state/sessions" \
  HYPERBUF_TEST_SCRIPT="$script" app/macos/.build/debug/HyperBuf "$project" >"$log" 2>&1 &
pid=$!
for _ in $(seq 1 90); do
  if grep -qE '^(RESULT|ERROR):' "$log"; then break; fi
  if ! kill -0 "$pid" 2>/dev/null; then break; fi
  sleep 1
done
kill "$pid" 2>/dev/null || true

if ! grep -q '^RESULT: ' "$log"; then
  echo "No integration test result was obtained:" >&2
  cat "$log" >&2
  exit 1
fi

python3 - "$log" "$project" <<'PY'
import json, re, sys
text = open(sys.argv[1], encoding="utf-8").read()
r = json.loads(re.search(r"^RESULT: (.*)$", text, re.M).group(1))
problems = []
if r["host"] != "macos": problems.append(f"host is not macos: {r['host']}")
if r["files"] == 0: problems.append("No Markdown files")
if r["alerts"]: problems.append(f"alert fired: {r['alerts']}")
if r["violations"]: problems.append(f"CSP violation: {r['violations']}")
if r["errors"]: problems.append(f"runtime error: {r['errors']}")
for name, d in r["docs"].items():
    if d["dangerous"] or d["inlineHandlers"]:
        problems.append(f"{name}: dangerous elements remain ({d['dangerous']}, {d['inlineHandlers']})")
    if d["chars"] == 0:
        problems.append(f"{name}: rendered empty")
# For the verification document set (fixtures/sample-project), also check the expected values
if "sample-project" in sys.argv[2]:
    images = r["docs"].get("rendering/05-images.md", {})
    if images.get("brokenImages") != 1: problems.append(f"only the nonexistent image should fail to load: {images}")
    if images.get("blockedImages") != 1: problems.append(f"only the external image should be blocked: {images}")
    if sum(d["mermaid"] for d in r["docs"].values()) != 7: problems.append("7 Mermaid diagrams should render (excluding the ELK one)")
    elk = r["docs"].get("rendering/08-elk.md", {})
    if elk.get("renderErrors") != 1 or elk.get("mermaid") != 1:
        problems.append(f"the ELK diagram should show as an error while normal diagrams in the same document render: {elk}")
    mer = r["docs"].get("rendering/04-mermaid.md", {})
    if mer.get("renderErrors") != 1: problems.append(f"there should be exactly 1 Mermaid syntax error: {mer}")
if not r["search"] or r["search"]["items"] == 0:
    problems.append(f"search result is empty: {r['search']}")
total = sum(d["ms"] for d in r["docs"].values())
print(f"host={r['host']} files={r['files']} total {total} ms / search '{r['search']['word']}' → {r['search']['items']} hits / images {sum(d['images'] for d in r['docs'].values())} (unreadable {sum(d['brokenImages'] for d in r['docs'].values())}) / Mermaid {sum(d['mermaid'] for d in r['docs'].values())} diagrams")
if problems:
    print("NG:"); [print("  -", p) for p in problems]; sys.exit(1)
print("OK")
PY
