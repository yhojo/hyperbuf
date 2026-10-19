# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project status

HyperBuf is in **active implementation. v0.1.1 was released on 2026-10-14 (tag `v0.1.1`; Developer ID signed + notarized Universal build; v0.1.0 on 2026-10-12) and is in private initial distribution to a few acquaintances to collect feedback.** Migration plan M0–M7b are done and merged (M7b: the no-project design — absolute-path buffers, `default-directory`, allow/warn paths, multiple frames — `docs/dev/buffer-model.md` and `docs/dev/file-access.md`); M8 (distribution) is in progress: signing/notarization/.zip/.dmg are done, while public release preparation (source publication, GitHub Releases, Homebrew cask, SECURITY/CONTRIBUTING, git-history cleanup, trademark search) remains. The PoCs are finished and live on `poc/*` branches (not merged). The repository is mirrored to a private GitHub repo (`yhojo/hyperbuf`); CI runs on pushes to `main`. Progress, decisions and the order of work: `docs/history/migration-plan.md`. README.md (Japanese) is the product vision.

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
| `core/` (`npm run check` also verifies `docs/user/keybindings.md` and `docs/user/syntax-highlighting.md` are up to date: regenerate with `npm run keybindings` / `npm run languages`; TypeScript, Node >= 22.18, no test runner dependency; tests run TS directly via type stripping, so avoid TS-only syntax such as constructor parameter properties and enums — `erasableSyntaxOnly` enforces it) | `npm run check` (typecheck + prettier + tests); `npm run build`; `npm run dev` (build + dev server on :8765 serving `fixtures/sample-project`, or `node scripts/dev-server.mjs <project-dir> <port>`) | `node --test test/<file>.test.ts` |
| `app/macos/`, `cli/` (SwiftPM, Swift 6, macOS 14+) | `swift build && swift test && swift format lint --strict --recursive Sources Tests --configuration .swift-format` | `swift test --filter <TestName>` |
| `emacs/` | `scripts/check.sh emacs` (byte-compile with warnings as errors, then ERT) | `emacs -Q --batch -L emacs -l ert -l emacs/test/hyperbuf-test.el --eval '(ert-run-tests-batch-and-exit "<test-name-regexp>")'` |

Licensing: HyperBuf is Apache-2.0 (`LICENSE`, `NOTICE`); `emacs/` is GPL-3.0-or-later (`emacs/LICENSE`). Every source file (`.ts .mjs .js .swift .sh .css .el`) starts with an `SPDX-License-Identifier` line (`scripts/check-license-headers.sh`, run by `scripts/check.sh license` and CI) — add it to new files. Third-party licenses (what is actually bundled in the Web core): `node core/scripts/licenses.mjs check` (part of `npm run check`: allowed licenses only, license texts present, `docs/user/third-party-licenses.md` up to date; regenerate with `npm run licenses` in `core/`). `make-app.sh` writes the full `THIRD-PARTY-NOTICES.txt` into the app bundle. Manual entries (KaTeX fonts, overrides) live in `legal/extra-licenses.json`.

Formatters: Prettier (core), `swift format` (Swift; 4-space indent, config in each package's `.swift-format`). Fix with `npm run format` / `swift format format --in-place --recursive Sources Tests --configuration .swift-format`.

Running the macOS app (needs `core/dist`, so build the core first):

```bash
(cd core && npm run build)
(cd app/macos && swift run HyperBuf ../../README.md)  # opens a file (a directory opens its index.md / README.md; no argument → restores the last session)
app/macos/scripts/make-app.sh [debug|release]         # builds app/macos/.build/HyperBuf.app (ad-hoc signed, Web core + CLI + licenses bundled)
swift app/macos/scripts/icon-from-image.swift app/macos/Resources/source/hyperbuf-icon-original.icns app/macos/Resources  # regenerates the default app icon ("H") from the original artwork; commit the results (the alternative split-window design: swift app/macos/scripts/make-icon.swift)
# the original artwork is full-bleed (opaque corners, no margin); icon-from-image.swift makes a proper macOS icon (transparent corners, margin, shadow). HYPERBUF_ICON=<.icns> swaps the icon in make-app.sh / release.sh
scripts/release.sh [--dry-run]                        # (release builds are Universal arm64+x86_64) Developer ID sign + notarize + staple + .zip/.dmg + SHA256SUMS into dist/release (see docs/dev/release.md; --dry-run = ad-hoc, no notarization)
scripts/integration-test.sh [dir]                     # needs a GUI session: opens every document under dir in a debug HyperBuf and checks rendering, CSP, search, images
scripts/integration-test-ui.sh                        # needs a GUI session: C-s / outline navigation / keymap config / describe-bindings / minibuffer / kill-buffer in a real WKWebView (synthetic key events; native key path is checked by hand)
scripts/integration-test-session.sh                   # needs a GUI session: quit → relaunch restores frames / window layout / history / scroll / selection (session v2, restoreSession setting, broken/missing data, closing frames)
scripts/integration-test-project.sh                   # needs a GUI session: project roots in a real WKWebView (C-x p f / g / b / k: VCS marker ascent, default-directory fallback, projectIgnorePaths, per-project buffers; M-s g stays on the buffer's directory)
scripts/integration-test-ipc.sh                       # needs a GUI session: real .app + socket client + `hyperbuf` CLI + hyperbuf:// URL (open / warn-path confirm / URL-scheme confirm / timeout / errors)
(cd cli && swift run hyperbuf docs/history/migration-plan.md:20)   # opens a file at a line in a running HyperBuf (launches it if needed)
```

Debug builds only: `HYPERBUF_*` environment variables redirect the config path, socket, trusted-roots / remembered-sites / session stores and the Web core log so tests never touch the user's real state, and drive the WebView for the integration tests (`HYPERBUF_TEST_COMMANDS`, `HYPERBUF_TEST_SCRIPT`, `HYPERBUF_TEST_OPEN_LOG`). Release-build variables (`HYPERBUF_WEB_ROOT`; `HYPERBUF_SOCKET_PATH` / `HYPERBUF_APP` for the `hyperbuf` CLI) and the build-script ones are listed with all the others in `docs/dev/debug-environment.md`.

Build outputs (`dist/`, `.build/`, `node_modules/`, `*.app`) are never committed.

## What the product is

A keyboard-driven macOS viewer (not an editor) for browsing many cross-referenced Markdown documents. There is no "project" concept: buffers are identified by absolute path and everything is relative to the current buffer's directory (Emacs `default-directory`); see `docs/dev/buffer-model.md` and `docs/dev/file-access.md`. Tagline: "Read like a hacker. No tabs. Just buffers."

## Key design concepts (from README.md)

- **buffer / window / frame model** borrowed from Emacs: a buffer (document) is separate from a window (view); a frame (macOS window, `Cmd-1`…`Cmd-9`, `C-x 5 …`) is an independent workspace with its own buffers/history/splits, persisted as `session.json` (version 2). The same buffer can be shown in multiple windows, each keeping its own scroll position. Splitting is expected to use a split tree (`C-x 2/3/0/1/o`, `C-x b`, `C-x C-f`, `M-x`).
- **Back/Forward is reference history** (documents, anchors, positions per window). Buffer switches (`C-x b`) are also pushed onto it; the `C-x b` MRU order is managed separately. Splitting a window copies its history. Granularity and key binding are still open. Details: `docs/dev/interaction-model.md`.
- The README is a living vision document and may be changed freely, but every change to its stated plan/policy must be logged with a timestamp in `docs/history/plan-change-log.md`.
- **Rendering engine must stay loosely coupled** from the viewing/navigation core, so renderer choices can change after PoCs.
- Planned PoC order: Interaction → Rendering → Project navigation → Integration/hardening.

## Constraints to respect in any design or code

- Non-goals: Markdown editing (delegate to Emacs etc.), proprietary note format/sync/cloud accounts, full IDE/Git features, Emacs look without Emacs interaction semantics.
- Local-first: no unintended network access.
- Security baseline: treat all Markdown as untrusted (including AI-agent-generated); restrict script execution/external references in HTML/SVG/diagram engines; explicit file-access scope and external-command permissions; diagram render errors must be shown in place without breaking the whole document.
- File watching should reload externally-updated files while preserving reading position.
- **Decided:** the macOS shell is SwiftUI + WKWebView. The renderer/navigation core is a shell-independent web bundle; the only boundary is the `hyperbufHost` contract (`listFiles` / `readFile` / `onFileChanged`). Other OSes are expected to get their own native shell, not a shared cross-platform one. See `docs/history/poc-interaction-results.md`.
- **Decided (rendering):** unified/remark/rehype with remark-gfm, remark-math + KaTeX, starry-night, Mermaid (strict, lazy-loaded, layout fixed to dagre; `elkjs`/EPL-2.0 is stubbed out, see `docs/history/license-options.md`), rehype-sanitize, github-markdown-css. Keep rehype-sanitize's `user-content-` id prefix; images only via `<img>`; no external network (starry-night's default CDN WASM fetch is disabled by bundling). See `docs/history/poc-rendering-results.md`.
- **Decided (no project, access):** file access is judged by `warnPaths` / `allowPaths` (longest match wins; typed/chosen paths in `C-x C-f` / `C-x p f` are not judged; the URL scheme additionally confirms anything outside `allowPaths`; images are re-judged by the scheme handler at load time). Recursive listing/search starts at the buffer's directory and refuses `~` and `/`. Files displayed in windows are watched with non-recursive kqueue (not FSEvents). See `docs/dev/buffer-model.md` and `docs/dev/file-access.md`.
- **Decided (navigation):** (superseded where it mentions projects or FSEvents — see above) file watching uses FSEvents (no polling); project search starts as an in-process Swift implementation behind the `host.search` contract (ripgrep to be re-evaluated when regex/ignore rules are needed; never pass queries as `Process` arguments — macOS decomposes voiced kana, pipe via stdin). File list/search covers `*.md` and directories only; excluded by default: hidden entries and `node_modules`; `.gitignore` is not interpreted. Virtual buffers (`*search: …*`) and line anchors (`path#line:N`) are part of the interaction model. Memory profiling is deferred to the later phase. See `docs/history/poc-navigation-results.md`.
- **Decided (UI language, menus):** all UI text the app itself shows (menus, mode line, echo area, minibuffer prompts, command descriptions, error messages, CLI output, the `emacs/` package messages and docstrings) is **fixed to English and not localized** — no `.lproj` / `.strings` / `NSLocalizedString`; write new strings in English from the start. Content (documents, file names, anchors, IME input) stays fully international. The menu bar and dialogs follow macOS conventions (standard menus and `Cmd` shortcuts; the Window menu lists open frames with `Cmd-1`…`Cmd-9`, no separate Frame menu; item labels stay `HyperBuf [N]` for now); everything inside the frame follows Emacs conventions (`C-x …`, mode line, echo area style). Design docs and code comments stay Japanese until the source-publication work (M8); `emacs/` is already English. User-facing docs/tutorial: English first, locale translations possible later (undecided). See `docs/dev/ui-conventions.md`.
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
- 利用者に見える変更(機能・挙動の変更・不具合の修正)は、マージのときに `CHANGELOG.md` の `[Unreleased]` に英語で書く(リリースの手順は `docs/dev/release.md`)。

## Repository layout (monorepo)

HyperBuf.app 本体に加え、CLI と Emacs 連携も同一リポジトリで管理する。

- `core/` — shared web core (TypeScript; model, keys, fuzzy, rendering pipeline, UI). OS-independent; the only boundary to a shell is the `hyperbufHost` contract
- `app/macos/` — HyperBuf.app (SwiftUI + WKWebView shell; SwiftPM + scripts, no Xcode project for now). Other OSes get their own `app/<platform>/` with the best native framework for that platform
- `cli/` — `hyperbuf` command (Swift single binary for now; opens a file/line/anchor in HyperBuf.app via the socket, launching the app through the `hyperbuf://` URL if needed)
- `emacs/` — Emacs integration (`hyperbuf.el`, Emacs 29.1+, see `emacs/README.md`). Talks to the socket directly by default (`hyperbuf-transport` = `socket`); can be switched to call the `hyperbuf` CLI. Keeps its own copy of the input validation, kept in sync through the shared `protocol/examples/`
- `protocol/` — machine-readable protocol definition (JSON Schema, incl. the edit-location payload `location.schema.json`) + shared conformance examples (`examples/*.json`, used by Swift, the CLI and Emacs), and `protocol/swift` (`HyperBufProtocol`: types/validation/URL/framing; `HyperBufIPC`: `SocketServer` + `SocketClient`)
- `fixtures/` — test documents and the corpus generator
- `docs/` — design documents, PoC results, protocol spec, migration plan

Product name: **HyperBuf** (GUI: `HyperBuf.app`, CLI/URL scheme/repo: `hyperbuf`). Minimum macOS: 14 (policy: generations Apple still patches). Migration order and decisions: `docs/history/migration-plan.md`.

App・CLI・Emacs が共有する契約は `docs/dev/integration-protocol.md` に定める。**Decided:** 主経路は Unix ドメインソケット(JSON Lines。`ping` / `open` / `get-location`。同一ユーザーのみ)、URL スキーム `hyperbuf://` はアプリの起動と外部リンク用。Emacs 連携は直接ソケットが標準(設定で CLI 経由に切替可)。範囲外のファイルは URL・ソケットのどちらでも確認する。逆方向(ビューア→Emacs)は「Emacs で編集」メニュー + `get-location` の問い合わせで、位置の照合・警告のみ(続行不可)の方針。配布は OSS(GitHub)+ Developer ID 署名・公証の直接配布で、Mac App Store は対象外(サンドボックスなし)。技術スタック確定までトップレベルの共通ビルドは作らず、各ディレクトリで独立させる。
