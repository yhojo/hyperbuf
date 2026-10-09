#!/bin/bash
# 統合テスト: Web コアをビルドし、HyperBuf.app(デバッグビルド)で、プロジェクトの全文書を開いて検査する。
# GUI セッションが要る(WebView を起動するため)。CI の macOS ランナーでも動く想定だが、未確認。
# 使い方: scripts/integration-test.sh [プロジェクトのディレクトリ]   (既定: fixtures/sample-project)
set -euo pipefail
cd "$(dirname "$0")/.."

project="${1:-fixtures/sample-project}"
script="$(pwd)/app/macos/IntegrationTests/smoke.js"

(cd core && npm ci --silent && npm run build >/dev/null)
(cd app/macos && swift build >/dev/null)

log="$(mktemp)"
trap 'rm -f "$log"' EXIT
HYPERBUF_SESSION_DIR="$(mktemp -d)" HYPERBUF_TEST_SCRIPT="$script" app/macos/.build/debug/HyperBuf "$project" >"$log" 2>&1 &
pid=$!
for _ in $(seq 1 90); do
  if grep -qE '^(RESULT|ERROR):' "$log"; then break; fi
  if ! kill -0 "$pid" 2>/dev/null; then break; fi
  sleep 1
done
kill "$pid" 2>/dev/null || true

if ! grep -q '^RESULT: ' "$log"; then
  echo "統合テストの結果が得られませんでした:" >&2
  cat "$log" >&2
  exit 1
fi

python3 - "$log" "$project" <<'PY'
import json, re, sys
text = open(sys.argv[1], encoding="utf-8").read()
r = json.loads(re.search(r"^RESULT: (.*)$", text, re.M).group(1))
problems = []
if r["host"] != "macos": problems.append(f"host が macos ではない: {r['host']}")
if r["files"] == 0: problems.append("Markdown が 0 件")
if r["alerts"]: problems.append(f"alert が発火した: {r['alerts']}")
if r["violations"]: problems.append(f"CSP 違反: {r['violations']}")
if r["errors"]: problems.append(f"実行時エラー: {r['errors']}")
for name, d in r["docs"].items():
    if d["dangerous"] or d["inlineHandlers"]:
        problems.append(f"{name}: 危険な要素が残っている ({d['dangerous']}, {d['inlineHandlers']})")
    if d["chars"] == 0:
        problems.append(f"{name}: 空に描画された")
# 検証用の文書集(fixtures/sample-project)なら、期待する値も確かめる
if "sample-project" in sys.argv[2]:
    images = r["docs"].get("rendering/05-images.md", {})
    if images.get("brokenImages") != 1: problems.append(f"存在しない画像だけが読めないはず: {images}")
    if images.get("blockedImages") != 1: problems.append(f"外部画像だけがブロックされるはず: {images}")
    if sum(d["mermaid"] for d in r["docs"].values()) != 6: problems.append("Mermaid は 6 図が描画されるはず")
    mer = r["docs"].get("rendering/04-mermaid.md", {})
    if mer.get("renderErrors") != 1: problems.append(f"Mermaid の構文エラーは 1 件のはず: {mer}")
if not r["search"] or r["search"]["items"] == 0:
    problems.append(f"検索の結果が空: {r['search']}")
total = sum(d["ms"] for d in r["docs"].values())
print(f"host={r['host']} files={r['files']} 合計 {total} ms / 検索 '{r['search']['word']}' → {r['search']['items']} 件 / 画像 {sum(d['images'] for d in r['docs'].values())} 枚(読めない {sum(d['brokenImages'] for d in r['docs'].values())}) / Mermaid {sum(d['mermaid'] for d in r['docs'].values())} 図")
if problems:
    print("NG:"); [print("  -", p) for p in problems]; sys.exit(1)
print("OK")
PY
