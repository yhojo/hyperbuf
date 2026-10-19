# HyperBuf

> **Read like a hacker.**
>
> **No tabs. Just buffers.**

HyperBufは、プロジェクト内の大量のMarkdownドキュメントを、キーボード主体で自在に読み進めるためのmacOS向けドキュメントビューアです。

単なるMarkdownプレビューアではありません。Emacsに由来する **buffer / window / frame** の考え方と、Webブラウザのような参照履歴を組み合わせ、ドキュメントを「一枚ずつ開く」のではなく、**横断し、比較し、行き来する**ための道具を目指します。

> [!NOTE]
> 本文書は開発開始時点のプロダクトビジョンです。名称、仕様、アーキテクチャ、ライブラリ選定は今後の検証を通じて更新します。

## 名前の由来

**HyperBuf** は、**Hyper**text(相互にリンクされた文書)と、(Emacs の)**Buf**fer を合わせた名前です。リンクでつながったたくさんの文書を、Emacs の buffer のように、気軽に開き、切り替え、行き来する、という意味を込めています。

## Why HyperBuf?

Markdownビューアは数多く存在します。しかし、技術者が数十〜数百の相互参照された設計文書を読む際の操作性、拡張記法の再現性、キーボードでの自在な移動を一貫して重視した製品には、まだ挑戦の余地があります。

HyperBufは、ハッカー文化に根差した **使い込める道具** を目指します。表面的なレトロ趣味ではなく、予測可能な操作、透明性、構成可能性、既存のツールとの共存を重視します。

## Principles

- **Keyboard first. Mouse optional.** — 主要な閲覧操作はキーボードで完結する。マウス操作も排除しない。
- **No tabs. Just buffers.** — ドキュメントの実体（buffer）と表示領域（window）を分離する。
- **Navigation is a first-class feature.** — 文書間の参照、戻る／進む、見出しジャンプ、検索を中心機能として設計する。
- **Files are yours.** — プレーンなMarkdownと既存のプロジェクト構造を尊重し、独自形式への移行を要求しない。
- **Render what engineers write.** — GFM、SVG、数式、図表、コードなど、実務で使われる表現への対応を重視する。
- **Extensible by design.** — 拡張しやすく、設定や動作が理解できる構造を目指す。
- **Local first.** — 基本的な閲覧はオフラインで完結し、意図しない外部通信を行わない。
- **Mac outside, Emacs inside.** — メニューバーやダイアログは macOS の流儀、フレームの中（キー操作・モードライン・ミニバッファ）はEmacsの流儀で作る。アプリ自身の文言は英語に固定し（ローカライズしない）、扱う文書やファイル名は国際化されている。詳細は `docs/dev/interaction-model.md` §6b。

## Product goals

### 1. Project-oriented reading

- 「プロジェクトを選ぶ」操作はない。バッファのファイルのディレクトリ（Emacsの `default-directory`）を基準に、ファイルを開き、そのディレクトリ以下を一覧・全文検索する。作業ごとにフレーム（ウィンドウ）を分けて、複数の文書群を並行して読める（`Cmd-1`、`Cmd-2`…で切り替え）。詳細は [docs/dev/buffer-model.md](docs/dev/buffer-model.md)。
- ファイル一覧、ファイル名検索、見出しナビゲーション、全文検索を提供する。
- 相対リンク、文書内アンカー、ローカル画像・図表を適切に解決する。
- 多数のファイルを扱っても、閲覧の応答性を維持する。

### 2. Emacs-inspired navigation

- buffer / window / frame を区別して管理する。
- 同じbufferを複数windowに表示し、それぞれ独立した閲覧位置を保持できるようにする。
- `C-x 2`、`C-x 3`、`C-x 0`、`C-x 1`、`C-x o`、`C-x b` などの操作を出発点にする。
- **Back / Forward は参照履歴の前後移動**に割り当てる。リンクや見出しジャンプに加え、`C-x b` などによるbuffer切替も参照として履歴に積む。`C-x b` の候補順（最近使った順）は参照履歴とは別に管理する。
- 参照履歴は、文書だけでなくアンカーや閲覧位置も扱えるようにする。
- 検索やbuffer選択などの入力は、ダイアログではなくframe下部のミニバッファで行う。
- キーバインドは変更可能にする方向で検討する。macOS標準ショートカットとの衝突も検証する。

### 3. High-fidelity rendering

- GitHub Flavored Markdown（GFM）とGitHubに準じた表示スタイルを基本とする。
- SVGを含む画像表示、拡大・縮小、パン操作に対応する。
- Mermaidなどの図表記法、数式、シンタックスハイライトを重視する。
- 図表レンダリングのエラーは文書全体を止めず、問題箇所に表示する。
- レンダラーごとの互換性・セキュリティ・パフォーマンスを検証する。

### 4. Development-workflow integration

- Emacsやコーディングエージェントが更新したファイルを適切に再読み込みする。
- 更新時には閲覧位置を可能な限り維持する。
- 将来的に、CLIやEmacs側の小さな連携機能からファイル・行・見出しを指定して開けるようにする。
- 分割配置、参照履歴、閲覧位置などのセッションを、フレーム（ウィンドウ）ごとに保存し、次回の起動で復元する（既定で有効。`config.json` の `restoreSession` で無効にできる。詳細は [docs/dev/session-restore.md](docs/dev/session-restore.md)）。

## Initial interaction sketch

| Operation | Candidate binding | Intent |
| --- | --- | --- |
| Split below | `C-x 2` | 現在のwindowを上下に分割 |
| Split right | `C-x 3` | 現在のwindowを左右に分割 |
| Close window | `C-x 0` | 現在のwindowを閉じる |
| Only window | `C-x 1` | 現在のwindowだけを残す |
| Other window | `C-x o` | 操作対象のwindowを移動 |
| Count words | `M-=` | 選択範囲（なければ文書全体）の行・単語・文字の数を、表示されているテキストで数える |
| Resize window | `C-x ^` / `C-x }` / `C-x {` / `C-x -` | 縦に広げる・横に広げる・横に狭める・文書がちょうど収まる高さに縮める（モードラインのドラッグでも変更できる） |
| Switch buffer | `C-x b` | 表示するbufferを切り替える |
| Find file | `C-x C-f` | ファイルを開く（基準のディレクトリから始まるパス補完。ディレクトリは `RET` で中へ） |
| Find file (tree) | `C-x p f` | プロジェクト・ルート（`.git` などのあるディレクトリまでさかのぼって求める。なければ基準のディレクトリ）以下の文書を再帰で一覧にして絞り込む（`../`・`~/` で起点を変えられる） |
| Frames | `Cmd-1`…`Cmd-9` / `C-x 5 2` `0` `o` `1` | フレーム（macOSのウィンドウ）の切り替え・作成・削除。各フレームは独立した作業場 |
| Command palette | `M-x` | 名前からコマンドを実行 |
| Search in document | `C-s` / `C-r` | 文書内のインクリメンタル検索（入力のたびに一致を数えてハイライト、`RET` で確定、`C-g` で取消） |
| Search in directory | `M-s g` | 基準のディレクトリ以下の全文検索（結果は仮想bufferに出る） |
| Search in project | `C-x p g` | プロジェクト・ルート以下の全文検索（結果は仮想bufferに出る） |
| Project buffers | `C-x p b` / `C-x p k` | 同じプロジェクト・ルートのbufferだけから切り替える・まとめて閉じる（閉じる前に確認する） |
| Back / Forward | `C-b` / `C-f`（別名 `←` / `→`、`Cmd+[` / `Cmd+]`） | 各windowの参照履歴を前後移動 |
| Outline | `C-c C-n` / `C-p` / `C-f` / `C-b` / `C-u` | 次・前・同じレベルの次・同じレベルの前・上のレベルの見出しへ移動 |
| Kill buffer | `C-x k` | bufferを閉じる |
| Follow updates | `C-x x u` | 外部で更新されたとき、最初に変わった場所へ移る／移らないの切替（既定はオフ） |
| Edit in editor | `C-c e` / 右クリック | 指した場所を、エディタで編集するために記録 |
| Describe bindings | `C-h b` | キー割り当ての一覧（設定は `config.json` の `keybindings`） |

*キー割り当ての全体は [docs/user/keybindings.md](docs/user/keybindings.md)（コードから自動生成）、設定の方法は [docs/user/configuration.md](docs/user/configuration.md)。*

## Non-goals (initially)

- フル機能のMarkdownエディタを作ること。編集はEmacsなど既存のエディタに委ねる。
- 独自のノート保存形式、同期サービス、クラウドアカウントを必須にすること。
- あらゆるMarkdown方言やプラグインを初日から完全サポートすること。
- Gitクライアント、IDE、ナレッジ管理サービスの機能を丸ごと内包すること。
- 見た目だけをEmacs風にして、操作モデルの本質を再現しないこと。

## Architecture and technology: candidates, not decisions

設計とライブラリは開発プロジェクト内で再検討します。以下は**調査・比較・PoCのための候補**であり、採用を決定したものではありません。

| Concern | Candidates to evaluate |
| --- | --- |
| macOS application shell | **SwiftUI + WKWebView（決定、`docs/history/poc-interaction-results.md`）**。比較対象: Tauri 2 / Rust、Electron |
| UI implementation | React + TypeScript、ネイティブUIとの分担 |
| Markdown pipeline | **unified / remark / rehype（決定、`docs/history/poc-rendering-results.md`）**。raw HTML は rehype-sanitize で無害化 |
| GFM / appearance | **remark-gfm、github-markdown-css（決定）**。GitHub との差は小さな変換で吸収する（例: 通貨表記の `$`） |
| Mathematics | **KaTeX（決定）**。Marked 2 との差は、描画ではなくエスケープの解釈（`\_`）だったため互換処理で解消。MathJax は必要になるまで採用しない |
| Diagrams | **Mermaid（決定、遅延ロード・strictモード）**。Graphviz、PlantUML、WaveDrom、D2 は未評価（外部コマンドが絡むものは権限境界を先に決める） |
| Syntax highlighting | **starry-night（決定）**。Shiki と比較し、速度・出力サイズ・GitHub互換で優位。対応言語の一覧は `docs/user/syntax-highlighting.md` |
| Project search | **Swift 自前実装から開始（決定、`docs/history/poc-navigation-results.md`）**。`host.search` の契約でエンジンを差し替え可能にし、正規表現や除外規則が必要になった時点で ripgrep を再評価。インデックス方式は規模に応じて検討 |
| File monitoring | **FSEvents（決定）**。ポーリングは削除を検知できず、ファイル数に比例して重いため採用しない |
| State / layout management | 明示的なbuffer・windowモデル、分割ツリーなど |

評価軸には、**表示互換性、操作遅延、メモリ、拡張性、セキュリティ、macOS統合、保守性、配布容易性**を含めます。レンダリングエンジンと閲覧・ナビゲーションのコアは、可能な限り疎結合に保ちます。

## Security baseline

ローカルMarkdownも、外部リポジトリやAIエージェントが生成したものなら信頼できない入力として扱います。

- HTML/SVGや図表エンジンのスクリプト実行・外部参照を制限する。
- ローカルファイルへのアクセス範囲と、外部コマンドの実行権限を明示的に管理する。
- 外部への通信は原則として無効または利用者が把握できる形にする。
- 拡張機構には権限と信頼境界を設ける。

具体的な実現方法はアーキテクチャ検討の中で決定します。

## Development approach

1. **Interaction PoC** — buffer / window / frame、分割、キーボード操作、参照履歴の操作感を検証する。
2. **Rendering PoC** — GFM、SVG、数式、Mermaid、コードブロックの表示と互換性を検証する。
3. **Project navigation** — ファイル探索、見出しジャンプ、全文検索、自動再読み込みを検証する。
4. **Integration and hardening** — セッション復元、外部連携、プラグイン、性能、セキュリティ、配布を検討する。

各段階の詳細な仕様や完了条件は、個別の設計文書と検証結果によって定義します。PoCの結果によって技術選択を変更できることを前提とします。

## Open questions

- 他OSへ移植する場合のシェル（macOSはSwiftUI + WKWebViewに決定済み。他OSは各プラットフォームに最適なフレームワークで、共通のWebコアを再利用する方針）。
- bufferとwindowのライフサイクルをどこまでEmacsに合わせるか。
- コピーのためのテキスト選択をキーボードでどう行うか（閲覧画面へのカーソル表示は導入しない方向で、別途検討）。
- GitHub互換表示の対象範囲をどう定義するか。
- 図表プラグインをどの権限境界で実行するか。
- 大きな文書の部分更新とスクロール位置維持をどう実現するか。
- メモリ使用量の確認（プロジェクト後半にまとめて。描画バンドルで増加、リークの有無と内訳を調べる）。
- Back / Forward の履歴粒度をどう設計するか。window分割時は履歴を複製する方針（詳細は `docs/dev/interaction-model.md`）。

## Project status

**v0.1.1（2026-10-14）— 関係者への初期配布の段階です。** 実装は、移行計画の M0〜M7b（Web コア、macOS シェル、ナビゲーション UI、IPC・CLI・URL、Emacs 連携、セッション復元、プロジェクトを持たない設計・複数フレーム）まで完了し、配布（M8）を進めています。v0.1.1(初版は v0.1.0、2026-10-12)は、Developer ID 署名・公証済みの Universal（arm64 + x86_64）ビルドで、macOS 14 以上が対象です。現在は関係者への非公開の配布で、フィードバックを集めています。ライセンスは Apache-2.0（`emacs/` は GPL-3.0-or-later）。ソースの公開と、一般向けの配布（GitHub Releases・Homebrew cask など）は、これからです。配布は、オープンソース（GitHub）として公開し、Developer ID 署名・公証のビルド済みパッケージを直接配布する方針です（Mac App Store は対象外、サンドボックスなし）。

---

**HyperBuf** — *Read like a hacker.*
