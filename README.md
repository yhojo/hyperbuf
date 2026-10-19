# HyperBuf

> **Read like a hacker.**
>
> **No tabs. Just buffers.**

HyperBufは、大量のMarkdownドキュメントを、キーボード主体で自在に読み進めるためのmacOS向けドキュメントビューアです(エディタではありません)。

単なるMarkdownプレビューアではありません。Emacsに由来する **buffer / window / frame** の考え方と、Webブラウザのような参照履歴を組み合わせ、ドキュメントを「一枚ずつ開く」のではなく、**横断し、比較し、行き来する**ための道具です。

**状態:** v0.1.2(2026-10-19)。関係者への非公開の配布の段階で、フィードバックを集めています。Developer ID署名・公証済みのUniversal(arm64 + x86_64)ビルドで、macOS 14以上が対象です。ソースの公開と一般向けの配布は、これからです。

## 名前の由来

**HyperBuf** は、**Hyper**text(相互にリンクされた文書)と、(Emacs の)**Buf**fer を合わせた名前です。リンクでつながったたくさんの文書を、Emacs の buffer のように、気軽に開き、切り替え、行き来する、という意味を込めています。

## Why HyperBuf?

Markdownビューアは数多く存在します。しかし、技術者が数十〜数百の相互参照された設計文書を読む際の操作性、拡張記法の再現性、キーボードでの自在な移動を一貫して重視した製品には、まだ挑戦の余地があります。

HyperBufは、ハッカー文化に根差した **使い込める道具** を目指します。表面的なレトロ趣味ではなく、予測可能な操作、透明性、構成可能性、既存のツールとの共存を重視します。

## Principles

- **Keyboard first. Mouse optional.** — 主要な閲覧操作はキーボードで完結する。マウス操作も排除しない。
- **No tabs. Just buffers.** — ドキュメントの実体（buffer）と表示領域（window）を分離する。
- **Navigation is a first-class feature.** — 文書間の参照、戻る／進む、見出しジャンプ、検索を中心機能として設計する。
- **Files are yours.** — プレーンなMarkdownと既存のディレクトリ構造を尊重し、独自形式への移行を要求しない。
- **Render what engineers write.** — GFM、SVG、数式、図表、コードなど、実務で使われる表現への対応を重視する。
- **Extensible by design.** — 拡張しやすく、設定や動作が理解できる構造を目指す。
- **Local first.** — 基本的な閲覧はオフラインで完結し、意図しない外部通信を行わない。
- **Mac outside, Emacs inside.** — メニューバーやダイアログは macOS の流儀、フレームの中（キー操作・モードライン・ミニバッファ）はEmacsの流儀で作る。アプリ自身の文言は英語に固定し（ローカライズしない）、扱う文書やファイル名は国際化されている。詳細は [docs/dev/ui-conventions.md](docs/dev/ui-conventions.md)。

## Features

### 閲覧とナビゲーション

- **buffer / window / frame。** 開いた文書（buffer）と表示領域（window）を分け、同じbufferを複数windowに表示して、それぞれ独立した閲覧位置を持てる。frame（macOSのウィンドウ）は独立した作業場で、`Cmd-1`〜`Cmd-9` で切り替える。詳細は [docs/dev/buffer-model.md](docs/dev/buffer-model.md)、[docs/dev/interaction-model.md](docs/dev/interaction-model.md)。
- **参照履歴。** Back / Forward（`C-b` / `C-f`）は参照履歴の前後移動で、リンクや見出しジャンプ、`C-x b` によるbuffer切替も履歴に積まれる。履歴はwindowごとで、window分割時に複製される。
- **プロジェクトを選ばない。** 現在のbufferのディレクトリ（Emacsの `default-directory`）を基準に、ファイルを開き、そのディレクトリ以下を一覧・全文検索する。`.git` などのあるディレクトリ（プロジェクト・ルート）以下を対象にするコマンドもある。
- ファイル一覧、ファイル名の絞り込み、見出しナビゲーション、文書内検索、全文検索。検索結果は仮想bufferに出る。
- 検索やbuffer選択などの入力は、ダイアログではなくframe下部のミニバッファで行う。キー割り当ては `config.json` で変更できる。
- セッション（分割配置、参照履歴、閲覧位置）をframeごとに保存し、次回の起動で復元する。詳細は [docs/dev/session-restore.md](docs/dev/session-restore.md)。

### レンダリング

- GitHub Flavored Markdown（GFM）とGitHubに準じた表示スタイル。
- ローカルの画像（SVGを含む）、KaTeXによる数式、Mermaidの図、約90言語のシンタックスハイライト（[docs/user/syntax-highlighting.md](docs/user/syntax-highlighting.md)）。
- 図のエラーは文書全体を止めず、その場所に表示する。

### 開発ワークフローとの連携

- Emacsやコーディングエージェントが更新したファイルを再読み込みし、閲覧位置を保つ。
- `hyperbuf` コマンドと、Emacs連携（`emacs/`）から、ファイル・行・見出しを指定して開ける。ビューアで指した場所を、Emacsで正確に編集する連携もある（誤った場所を黙って編集させないよう、照合してから移動する）。仕様は [docs/dev/integration-protocol.md](docs/dev/integration-protocol.md)、[docs/dev/edit-location.md](docs/dev/edit-location.md)。

## はじめかた

ダウンロードした `.dmg` を開き、`HyperBuf.app` を `Applications` に移します。インストールと基本の操作は [docs/user/getting-started.md](docs/user/getting-started.md)（`.dmg` にも `README.md` として入っています）。

### 主なキー

| Key | Command | Intent |
| --- | --- | --- |
| `C-x C-f` | `find-file` | ファイルを開く（基準のディレクトリから始まるパス補完） |
| `C-x p f` | `project-find-file` | プロジェクト・ルート以下の文書を一覧にして開く |
| `C-x b` | `switch-buffer` | 表示するbufferを切り替える |
| `C-b` / `C-f` | `back` / `forward` | 参照履歴を前後移動 |
| `C-a` / `C-e` | `beginning-of-history` / `end-of-history` | 参照履歴の先頭 / 最後へ移動 |
| `C-s` / `C-r` | `isearch-forward` / `isearch-backward` | 文書内のインクリメンタル検索 |
| `M-s g` / `C-x p g` | `search-project` / `project-find-regexp` | ディレクトリ以下 / プロジェクト・ルート以下の全文検索 |
| `C-x 2` / `C-x 3` / `C-x 0` / `C-x 1` / `C-x o` | `split-below` ほか | windowの分割・閉じる・移動 |
| `C-x 5 2` / `Cmd-1`…`Cmd-9` | `make-frame` ほか | frameの作成・切り替え |
| `M-x` | `execute-command` | 名前からコマンドを実行 |
| `C-h b` | `describe-bindings` | キー割り当ての一覧 |

キー割り当ての全体は [docs/user/keybindings.md](docs/user/keybindings.md)（コードから自動生成）、設定の方法は [docs/user/configuration.md](docs/user/configuration.md)。

## ドキュメント

| 場所 | 対象 | 内容 |
| --- | --- | --- |
| [docs/user/](docs/user/) | 利用者 | はじめかた、キー割り当て、設定、シンタックスハイライトの対応言語、サードパーティのライセンス |
| [docs/dev/](docs/dev/) | 開発者 | 現行の設計と仕様（アーキテクチャ、buffer / window / frame、アクセス判定、連携プロトコル、リリース） |
| [docs/history/](docs/history/) | 開発の経緯 | PoCの結果、移行計画、計画変更ログ |

構成と技術選定は [docs/dev/architecture.md](docs/dev/architecture.md)。変更履歴は [CHANGELOG.md](CHANGELOG.md)。

## Non-goals

- フル機能のMarkdownエディタを作ること。編集はEmacsなど既存のエディタに委ねる。
- 独自のノート保存形式、同期サービス、クラウドアカウントを必須にすること。
- あらゆるMarkdown方言やプラグインを初日から完全サポートすること。
- Gitクライアント、IDE、ナレッジ管理サービスの機能を丸ごと内包すること。
- 見た目だけをEmacs風にして、操作モデルの本質を再現しないこと。

## Architecture

macOS向けのシェル（SwiftUI + WKWebView）と、OSに依存しない共通のWebコア（TypeScript。unified / remark / rehype、KaTeX、Mermaid、starry-night）で構成します。シェルとWebコアの境界は `hyperbufHost` の契約だけです。他OSへ移植するときは、そのOSに最適なフレームワークでシェルを書き、Webコアを再利用します。選定の根拠と未評価の候補は [docs/dev/architecture.md](docs/dev/architecture.md)。

## Security baseline

ローカルMarkdownも、外部リポジトリやAIエージェントが生成したものなら信頼できない入力として扱います。

- HTML/SVGや図表エンジンのスクリプト実行・外部参照を制限する。
- ローカルファイルへのアクセス範囲と、外部コマンドの実行権限を明示的に管理する。
- 外部への通信は原則として無効または利用者が把握できる形にする。
- 拡張機構には権限と信頼境界を設ける。

実現方法は [docs/dev/architecture.md](docs/dev/architecture.md) §4、[docs/dev/file-access.md](docs/dev/file-access.md)。

## Open questions

- 画像（SVGを含む）の拡大・縮小・パン操作。
- 他OSへ移植する場合のシェル（macOSはSwiftUI + WKWebViewに決定済み。他OSは各プラットフォームに最適なフレームワークで、共通のWebコアを再利用する方針）。
- コピーのためのテキスト選択をキーボードでどう行うか（閲覧画面へのカーソル表示は導入しない方向で、別途検討）。
- GitHub互換表示の対象範囲をどう定義するか。
- 図表プラグインをどの権限境界で実行するか（Graphviz等の外部コマンドを使う場合）。
- 大きな文書の部分更新とスクロール位置維持をどう実現するか。
- メモリ使用量の確認（リークの有無と内訳）。
- Back / Forward の履歴粒度（同一文書内の連続したアンカー移動を1エントリにまとめるか）。
- `M-f` / `M-b` の割り当て。

## Contributing and security

バグ報告や要望は Issue で歓迎します。Pull Request は、先に Issue で相談してください。手順は [CONTRIBUTING.md](CONTRIBUTING.md)。脆弱性の報告は、公開の Issue ではなく、[SECURITY.md](SECURITY.md) の窓口へお願いします。

## License

Apache-2.0（[LICENSE](LICENSE)、[NOTICE](NOTICE)）。`emacs/` は GPL-3.0-or-later（[emacs/LICENSE](emacs/LICENSE)）です。

---

**HyperBuf** — *Read like a hacker.*
