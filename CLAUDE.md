# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project status

HyperBuf is in **active implementation**. v0.1.2 was released on 2026-10-19 (tag `v0.1.2`; Developer ID signed + notarized Universal build) and is in private initial distribution to a few acquaintances to collect feedback. Migration plan M0–M7b are done; M8 (distribution) is in progress: signing, notarization, the `.zip` / `.dmg`, SECURITY/CONTRIBUTING, the secret scan and the git-history cleanup are done. A trademark search (2026-10-19) found registrations of the same name (`HYPER-BUF` in the US, `HYPERBUF` in Brazil, both CA, Inc.), so **the project will not be made public**: it is distributed only to people who ask for it. The remaining publication work (English translation of the documents, recreating the GitHub repository, GitHub settings, GitHub Releases) is still carried out to learn the process. The Homebrew cask is not supported for now. The PoCs are finished and live on `poc/*` branches (not merged). The repository is mirrored to a private GitHub repo (`yhojo/hyperbuf`); CI runs on pushes to `main`.

Progress, decisions and the order of work: `docs/history/migration-plan.md`. The product vision and feature overview: `README.md`.

## Commands

Everything runs from the repo root through one script (same as CI, `.github/workflows/ci.yml`; the GUI integration tests below are not run in CI):

```bash
scripts/check.sh            # all: license, version, core, protocol, app, cli, emacs
scripts/check.sh core       # or: license | version | protocol | app | cli | emacs
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
swift app/macos/scripts/icon-from-image.swift app/macos/Resources/source/hyperbuf-icon-original.icns app/macos/Resources  # regenerates the default app icon ("H") from the original artwork; commit the results (details: docs/dev/distribution.md)
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

A keyboard-driven macOS viewer (not an editor) for browsing many cross-referenced Markdown documents. Tagline: "Read like a hacker. No tabs. Just buffers."

- **buffer / window / frame model**, borrowed from Emacs: a buffer (document) is separate from a window (view); a frame (macOS window, `Cmd-1`…`Cmd-9`, `C-x 5 …`) is an independent workspace with its own buffers, history and window splits. The same buffer can be shown in multiple windows, each keeping its own scroll position. See `docs/dev/buffer-model.md` and `docs/dev/interaction-model.md`.
- **There is no "project" concept.** Buffers are identified by absolute path and everything is relative to the current buffer's directory (Emacs `default-directory`). A project root is only computed from a buffer when needed (`C-x p …`). See `docs/dev/buffer-model.md`.
- **Back/Forward is reference history** (documents, anchors, positions per window). Buffer switches (`C-x b`) are also pushed onto it; the `C-x b` MRU order is managed separately.
- **The renderer/navigation core is a shell-independent web bundle.** The only boundary to a shell is the `hyperbufHost` contract (`core/src/host.ts`). Other OSes are expected to get their own native shell, not a shared cross-platform one. See `docs/dev/architecture.md`.

## Constraints to respect in any design or code

The rationale and details live in the documents listed in "Documentation"; these are the rules not to break.

- Non-goals: Markdown editing (delegate to Emacs etc.), proprietary note format/sync/cloud accounts, full IDE/Git features, Emacs look without Emacs interaction semantics.
- Local-first: no unintended network access.
- Treat all Markdown as untrusted (including AI-agent-generated): restrict script execution and external references in HTML/SVG/diagram engines; manage file-access scope and external-command permissions explicitly; diagram render errors must be shown in place without breaking the whole document. See `docs/dev/architecture.md` §4 and `docs/dev/file-access.md`.
- Keep rehype-sanitize's `user-content-` id prefix; images only via `<img>`, judged by the scheme handler at every load; no external network (starry-night's default CDN WASM fetch is disabled by bundling).
- File access is judged by `warnPaths` / `allowPaths` in the shell (`FileAccess`), never by the Web core. Paths typed or chosen by the user are not judged. Recursive listing/search refuses `~` and `/`.
- Never pass search queries as `Process` arguments (macOS decomposes voiced kana); pipe them via stdin.
- Files displayed in windows are watched with non-recursive kqueue (not FSEvents); a file can be reloaded while preserving the reading position.
- The Web core stays loosely coupled from the shell, and the rendering engine from the viewing/navigation core, so choices can change.
- **UI language:** all text the app itself shows (menus, mode line, echo area, minibuffer prompts, command descriptions, error messages, CLI output, the `emacs/` package messages and docstrings) is **fixed to English and not localized** — no `.lproj` / `.strings` / `NSLocalizedString`; write new strings in English from the start. Content (documents, file names, anchors, IME input) stays fully international. Menu bar and dialogs follow macOS conventions, everything inside the frame follows Emacs conventions. See `docs/dev/ui-conventions.md`.
- **Integration:** the main path for the CLI and Emacs is the Unix domain socket (JSON Lines, same user only); the `hyperbuf://` URL scheme is only for launching the app and for external links. Files under a warn path are confirmed on both routes. The reverse direction (viewer → editor) is pull-based, verifies the location before moving and never offers a way to continue on a mismatch. See `docs/dev/integration-protocol.md` and `docs/dev/edit-location.md`.
- Distribution is open source (GitHub) plus Developer ID signed and notarized direct distribution; the Mac App Store is out of scope (no sandbox).
- The remaining candidates (MathJax, Graphviz/PlantUML/WaveDrom/D2, ripgrep) are **candidates to evaluate, not decisions**. Don't treat any as adopted without the user's confirmation (`docs/dev/architecture.md` §3).

## Documentation

Documents are split by audience under `docs/`:

| Directory | Audience | What it holds |
| --- | --- | --- |
| `docs/user/` | users | getting started, key bindings, configuration, syntax highlighting, third-party licenses |
| `docs/dev/` | developers | the current design and specification (architecture, buffer model, interaction model, file access, integration protocol, session, release, …) |
| `docs/history/` | history | PoC results, migration plan, plan change log, past decisions. Records of the time; do not rewrite them to match the present |

- **Language:** `README.md`, `docs/user/` and `docs/dev/` are in English, as are UI text, `emacs/` and `CLAUDE.md`. `docs/history/` stays in Japanese (records of the time) with an English summary in its `README.md`. Source code comments are in English; test names and the output of repo scripts are still partly Japanese, and new ones are written in English. Commit messages are in English. When adding documents, write them in English except under `docs/history/`.
- **Generated files, never edit by hand:** `docs/user/keybindings.md`, `docs/user/syntax-highlighting.md`, `docs/user/third-party-licenses.md` (see "Commands" for how to regenerate; `npm run check` fails when they are stale).
- **Checks that keep documents and code in sync:** the config key list in `docs/user/configuration.md` (`ConfigDocsTests`), the limits table in `docs/dev/session-restore.md` (`core/test/session-docs.test.ts`), the operations and error codes in `docs/dev/integration-protocol.md` (`protocol/test/docs.test.mjs`), and the version strings (`scripts/check-versions.sh`).
- **When you change X, update Y:**
  - a `config.json` key → `docs/user/configuration.md` (the key list table)
  - a socket operation, field or error code → `protocol/schema/`, `protocol/examples/`, `docs/dev/integration-protocol.md`
  - session limits or format → `docs/dev/session-restore.md`
  - a user-visible change (feature, behavior, fix) → `CHANGELOG.md` `[Unreleased]`, in English, when merging
  - the README's plan or policy → `docs/history/plan-change-log.md`, with a timestamp
  - an environment variable → `docs/dev/debug-environment.md`
  - a design decision → the matching document in `docs/dev/` (not here)
- The `.dmg` ships `docs/user/getting-started.md` as its `README.md` (`scripts/release.sh` copies it), so keep that file free of relative links.

## Coding conventions

- Do not use tab characters for indentation (use spaces), except where the language or tool requires them (Go, Makefile, …).
- Follow the standard conventions and formatters of each language.
- Expressiveness may take precedence over conventions, but deviate only when readability or clarity of intent improves.

## Branch workflow

- Pull requests are not used for now. Work on a working branch, and merge into `main` locally once both the user and Claude agree it can go in.
- When there are noteworthy circumstances (a major change of direction, an effect on history, divided opinions, …), agree beforehand before merging.
- Merge with a merge commit (`--no-ff`). No squash, no rebase.
- Branch names are `<type>/<short description>` (for example `feat/split-window`, `fix/scroll-restore`, `docs/branch-rules`). The type follows Conventional Commits (feat, fix, docs, refactor, test, chore).
- Commit messages follow Conventional Commits (`type: summary`) and are written in English (the existing history before 2026-10-19 is in Japanese and is kept as it is).
- PoCs are done on `poc/<theme>` branches. Their code is not merged into `main` in principle; only the design documents that summarize the results are brought in. PoC branches are kept, not deleted.
- Never rewrite the history of `main` (no force push, …). The only exception so far: on 2026-10-19, before the source was published, the author e-mail address of every commit and tag was replaced by the GitHub noreply address (see `docs/history/README.md`).
- User-visible changes (features, behavior changes, fixes) are written in English under `[Unreleased]` in `CHANGELOG.md` when merging (the release procedure is in `docs/dev/release.md`).

## Repository layout (monorepo)

HyperBuf.app, the CLI and the Emacs integration are managed in one repository.

- `core/` — shared web core (TypeScript; model, keys, fuzzy, rendering pipeline, UI). OS-independent; the only boundary to a shell is the `hyperbufHost` contract
- `app/macos/` — HyperBuf.app (SwiftUI + WKWebView shell; SwiftPM + scripts, no Xcode project for now). Other OSes get their own `app/<platform>/` with the best native framework for that platform
- `cli/` — `hyperbuf` command (Swift single binary; opens a file/line/anchor in HyperBuf.app via the socket, launching the app through the `hyperbuf://` URL if needed)
- `emacs/` — Emacs integration (`hyperbuf.el`, Emacs 29.1+, see `emacs/README.md`). Talks to the socket directly by default (`hyperbuf-transport` = `socket`); can be switched to call the `hyperbuf` CLI. Keeps its own copy of the input validation, kept in sync through the shared `protocol/examples/`
- `protocol/` — machine-readable protocol definition (JSON Schema, incl. the edit-location payload `location.schema.json`) + shared conformance examples (`examples/*.json`, used by Swift, the CLI and Emacs), and `protocol/swift` (`HyperBufProtocol`: types/validation/URL/framing; `HyperBufIPC`: `SocketServer` + `SocketClient`)
- `fixtures/` — test documents and the corpus generator
- `docs/` — documentation, split by audience (see "Documentation")
- `legal/` — manual third-party license entries and license text templates
- `scripts/` — repo-wide checks, integration tests and the release script

Product name: **HyperBuf** (GUI: `HyperBuf.app`, CLI/URL scheme/repo: `hyperbuf`). Minimum macOS: 14 (policy: generations Apple still patches). Migration order and decisions: `docs/history/migration-plan.md`.
