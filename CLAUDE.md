# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project status

HyperBuf is in **active implementation: migration plan M0–M6 are done and merged; M7 (session restore) is implemented on `feat/session-restore` and awaiting manual verification**; M8 (distribution) remains. How "which project opens at launch" works is still to be discussed with the user. The PoCs are finished and live on `poc/*` branches (not merged). The repository is mirrored to a private GitHub repo (`yhojo/hyperbuf`); CI runs on pushes to `main`. Progress, decisions and the order of work: `docs/migration-plan.md`. README.md (Japanese) is the product vision.

When adding documents, follow the README's language (Japanese) unless told otherwise.

## Commands

Everything runs from the repo root through one script (same as CI, `.github/workflows/ci.yml`; the GUI integration tests below are not run in CI):

```bash
scripts/check.sh            # all: core, protocol, app, cli, emacs
scripts/check.sh core       # or: protocol | app | cli | emacs
```

Per component (run in the component directory):

| Component | Check | Single test |
| --- | --- | --- |
| `core/` (`npm run check` also verifies `docs/keybindings.md` is up to date: regenerate with `npm run keybindings`; TypeScript, Node >= 22.18, no test runner dependency; tests run TS directly via type stripping, so avoid TS-only syntax such as constructor parameter properties and enums — `erasableSyntaxOnly` enforces it) | `npm run check` (typecheck + prettier + tests); `npm run build`; `npm run dev` (build + dev server on :8765 serving `fixtures/sample-project`, or `node scripts/dev-server.mjs <project-dir> <port>`) | `node --test test/<file>.test.ts` |
| `app/macos/`, `cli/` (SwiftPM, Swift 6, macOS 14+) | `swift build && swift test && swift format lint --strict --recursive Sources Tests --configuration .swift-format` | `swift test --filter <TestName>` |
| `emacs/` | `scripts/check.sh emacs` (byte-compile with warnings as errors, then ERT) | `emacs -Q --batch -L emacs -l ert -l emacs/test/hyperbuf-test.el --eval '(ert-run-tests-batch-and-exit "<test-name-regexp>")'` |

Formatters: Prettier (core), `swift format` (Swift; 4-space indent, config in each package's `.swift-format`). Fix with `npm run format` / `swift format format --in-place --recursive Sources Tests --configuration .swift-format`.

Running the macOS app (needs `core/dist`, so build the core first):

```bash
(cd core && npm run build)
(cd app/macos && swift run HyperBuf ../../docs)      # opens a project directory (no argument → an Open panel)
app/macos/scripts/make-app.sh [debug|release]         # builds app/macos/.build/HyperBuf.app (ad-hoc signed, Web core bundled)
scripts/integration-test.sh [project-dir]             # needs a GUI session: opens every document in a debug HyperBuf and checks rendering, CSP, search, images
scripts/integration-test-ui.sh                        # needs a GUI session: C-s / outline navigation / keymap config / describe-bindings / minibuffer / kill-buffer in a real WKWebView (synthetic key events; native key path is checked by hand)
scripts/integration-test-session.sh                   # needs a GUI session: quit → relaunch restores window layout / history / scroll (session restore, restoreSession setting, broken/missing data)
scripts/integration-test-ipc.sh                       # needs a GUI session: real .app + socket client + `hyperbuf` CLI + hyperbuf:// URL (open/outside-project confirm/timeout/errors)
(cd cli && swift run hyperbuf docs/migration-plan.md:20)   # opens a file at a line in a running HyperBuf (launches it if needed)
```

Debug builds only: `HYPERBUF_TEST_COMMANDS=<dir>` makes the app run `N.js` files dropped into the directory inside the WebView and write `N.result` (used by `integration-test-ipc.sh` to select text and run `edit-in-editor`); `HYPERBUF_CONFIG` overrides the editor config path; `HYPERBUF_TEST_SCRIPT=<file.js>` runs a script inside the WebView after startup and prints `RESULT: …` (used by the integration tests; the script must resolve, never return a pending Promise); `HYPERBUF_WEB_ROOT` overrides where the Web core is loaded from; `HYPERBUF_SOCKET_PATH`, `HYPERBUF_TRUSTED_ROOTS`, `HYPERBUF_SESSION_DIR` and `HYPERBUF_TEST_LOG` redirect the socket, the trusted-roots store, the session store and the Web core log so tests never touch the user's real state. The `hyperbuf` CLI also honours `HYPERBUF_SOCKET_PATH` and `HYPERBUF_APP` (path of a .app to launch).

Build outputs (`dist/`, `.build/`, `node_modules/`, `*.app`) are never committed.

## What the product is

A keyboard-driven macOS viewer (not an editor) for browsing many cross-referenced Markdown documents in a project. Tagline: "Read like a hacker. No tabs. Just buffers."

## Key design concepts (from README.md)

- **buffer / window / frame model** borrowed from Emacs: a buffer (document) is separate from a window (view). The same buffer can be shown in multiple windows, each keeping its own scroll position. Splitting is expected to use a split tree (`C-x 2/3/0/1/o`, `C-x b`, `C-x C-f`, `M-x`).
- **Back/Forward is reference history** (documents, anchors, positions per window). Buffer switches (`C-x b`) are also pushed onto it; the `C-x b` MRU order is managed separately. Splitting a window copies its history. Granularity and key binding are still open. Details: `docs/interaction-model.md`.
- The README is a living vision document and may be changed freely, but every change to its stated plan/policy must be logged with a timestamp in `docs/plan-change-log.md`.
- **Rendering engine must stay loosely coupled** from the viewing/navigation core, so renderer choices can change after PoCs.
- Planned PoC order: Interaction → Rendering → Project navigation → Integration/hardening.

## Constraints to respect in any design or code

- Non-goals: Markdown editing (delegate to Emacs etc.), proprietary note format/sync/cloud accounts, full IDE/Git features, Emacs look without Emacs interaction semantics.
- Local-first: no unintended network access.
- Security baseline: treat all Markdown as untrusted (including AI-agent-generated); restrict script execution/external references in HTML/SVG/diagram engines; explicit file-access scope and external-command permissions; diagram render errors must be shown in place without breaking the whole document.
- File watching should reload externally-updated files while preserving reading position.
- **Decided:** the macOS shell is SwiftUI + WKWebView. The renderer/navigation core is a shell-independent web bundle; the only boundary is the `hyperbufHost` contract (`listFiles` / `readFile` / `onFileChanged`). Other OSes are expected to get their own native shell, not a shared cross-platform one. See `docs/poc-interaction-results.md`.
- **Decided (rendering):** unified/remark/rehype with remark-gfm, remark-math + KaTeX, starry-night, Mermaid (strict, lazy-loaded), rehype-sanitize, github-markdown-css. Keep rehype-sanitize's `user-content-` id prefix; images only via `<img>`; no external network (starry-night's default CDN WASM fetch is disabled by bundling). See `docs/poc-rendering-results.md`.
- **Decided (navigation):** file watching uses FSEvents (no polling); project search starts as an in-process Swift implementation behind the `host.search` contract (ripgrep to be re-evaluated when regex/ignore rules are needed; never pass queries as `Process` arguments — macOS decomposes voiced kana, pipe via stdin). File list/search covers `*.md` and directories only; excluded by default: hidden entries and `node_modules`; `.gitignore` is not interpreted. Virtual buffers (`*search: …*`) and line anchors (`path#line:N`) are part of the interaction model. Memory profiling is deferred to the later phase. See `docs/poc-navigation-results.md`.
- The remaining candidates in the README (MathJax, Graphviz/PlantUML/WaveDrom/D2) are **candidates to evaluate, not decisions**. Don't treat any as adopted without the user's confirmation.

## Coding conventions

- インデントにタブ文字を使わない(スペースを使う)。ただし言語・ツールが要求する場合(Go, Makefile等)は除く。
- 各言語の代表的なコーディング規約・フォーマッタの標準に従う。
- 規約よりコードの表現力を優先してよい。逸脱は、可読性や意図の明確さが上がる場合に限る。

## Branch workflow

- 当面 PR は使わない。作業ブランチで進め、ユーザーと Claude の双方が `main` に入れてよいと判断した時点で、ローカルで `main` にマージする。
- 特筆すべき事情がある場合(大きな方針変更、履歴への影響、判断が割れるとき等)は、事前に合意を取ってからマージする。
- マージ方式は merge commit(`--no-ff`)。squash や rebase はしない。
- ブランチ名は `<type>/<短い説明>`(例: `feat/split-window`, `fix/scroll-restore`, `docs/branch-rules`)。type は Conventional Commits に合わせる(feat, fix, docs, refactor, test, chore)。
- コミットメッセージは Conventional Commits 形式(`type: 要約`)。要約は日本語可。
- PoC は `poc/<テーマ>` ブランチで行う。コードは原則 `main` にマージせず、結果をまとめた設計文書のみ取り込む。PoC ブランチは削除せず残す。
- `main` の履歴を書き換える操作(force push 等)はしない。

## Repository layout (monorepo)

HyperBuf.app 本体に加え、CLI と Emacs 連携も同一リポジトリで管理する。

- `core/` — shared web core (TypeScript; model, keys, fuzzy, rendering pipeline, UI). OS-independent; the only boundary to a shell is the `hyperbufHost` contract
- `app/macos/` — HyperBuf.app (SwiftUI + WKWebView shell; SwiftPM + scripts, no Xcode project for now). Other OSes get their own `app/<platform>/` with the best native framework for that platform
- `cli/` — `hyperbuf` command (Swift single binary for now; opens a file/line/anchor in HyperBuf.app via the socket, launching the app through the `hyperbuf://` URL if needed)
- `emacs/` — Emacs integration (`hyperbuf.el`, Emacs 29.1+, see `emacs/README.md`). Talks to the socket directly by default (`hyperbuf-transport` = `socket`); can be switched to call the `hyperbuf` CLI. Keeps its own copy of the input validation, kept in sync through the shared `protocol/examples/`
- `protocol/` — machine-readable protocol definition (JSON Schema, incl. the edit-location payload `location.schema.json`) + shared conformance examples (`examples/*.json`, used by Swift, the CLI and Emacs), and `protocol/swift` (`HyperBufProtocol`: types/validation/URL/framing; `HyperBufIPC`: `SocketServer` + `SocketClient`)
- `fixtures/` — test documents and the corpus generator
- `docs/` — design documents, PoC results, protocol spec, migration plan

Product name: **HyperBuf** (GUI: `HyperBuf.app`, CLI/URL scheme/repo: `hyperbuf`). Minimum macOS: 14 (policy: generations Apple still patches). Migration order and decisions: `docs/migration-plan.md`.

App・CLI・Emacs が共有する契約は `docs/integration-protocol.md` に定める。**Decided:** 主経路は Unix ドメインソケット(JSON Lines。`ping` / `open` / `get-location`。同一ユーザーのみ)、URL スキーム `hyperbuf://` はアプリの起動と外部リンク用。Emacs 連携は直接ソケットが標準(設定で CLI 経由に切替可)。範囲外のファイルは URL・ソケットのどちらでも確認する。逆方向(ビューア→Emacs)は「Emacs で編集」メニュー + `get-location` の問い合わせで、位置の照合・警告のみ(続行不可)の方針。配布は OSS(GitHub)+ Developer ID 署名・公証の直接配布で、Mac App Store は対象外(サンドボックスなし)。技術スタック確定までトップレベルの共通ビルドは作らず、各ディレクトリで独立させる。
