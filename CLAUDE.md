# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project status

HyperBufis in the **inception / early design** phase. The repository currently contains only `README.md` (written in Japanese) — a product vision document. There is no source code, build system, linter, or test suite yet, so there are no build/test commands to run. Name, specs, architecture, and library choices are all explicitly provisional and expected to change after PoCs.

When adding documents, follow the README's language (Japanese) unless told otherwise.

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

## Repository layout (planned, monorepo)

HyperBuf.app 本体に加え、CLI と Emacs 連携も同一リポジトリで管理する。ディレクトリは実装開始時に作成する(現時点では未作成)。

- `core/` — shared web core (TypeScript; model, keys, fuzzy, rendering pipeline, UI). OS-independent; the only boundary to a shell is the `hyperbufHost` contract
- `app/macos/` — HyperBuf.app (SwiftUI + WKWebView shell; SwiftPM + scripts, no Xcode project for now). Other OSes get their own `app/<platform>/` with the best native framework for that platform
- `cli/` — `hyperbuf` command (Swift single binary for now; opens a file/line/anchor in HyperBuf.app via the socket, launching the app through the `hyperbuf://` URL if needed)
- `emacs/` — Emacs integration (`hyperbuf.el`). Talks to the socket directly by default; can be switched to call the `hyperbuf` CLI
- `protocol/` — machine-readable protocol definition + shared conformance examples (used by the Swift server, the CLI and the Emacs client)
- `fixtures/` — test documents and the corpus generator
- `docs/` — design documents, PoC results, protocol spec, migration plan

Product name: **HyperBuf** (GUI: `HyperBuf.app`, CLI/URL scheme/repo: `hyperbuf`). Minimum macOS: 14 (policy: generations Apple still patches). Migration order and decisions: `docs/migration-plan.md`.

App・CLI・Emacs が共有する契約は `docs/integration-protocol.md` に定める。**Decided:** 主経路は Unix ドメインソケット(JSON Lines。`ping` / `open` / `get-location`。同一ユーザーのみ)、URL スキーム `hyperbuf://` はアプリの起動と外部リンク用。Emacs 連携は直接ソケットが標準(設定で CLI 経由に切替可)。範囲外のファイルは URL・ソケットのどちらでも確認する。逆方向(ビューア→Emacs)は「Emacs で編集」メニュー + `get-location` の問い合わせで、位置の照合・警告のみ(続行不可)の方針。配布は OSS(GitHub)+ Developer ID 署名・公証の直接配布で、Mac App Store は対象外(サンドボックスなし)。技術スタック確定までトップレベルの共通ビルドは作らず、各ディレクトリで独立させる。
