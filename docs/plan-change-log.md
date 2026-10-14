# 計画変更ログ

README.md に記載した方針・計画を変更した際の記録。新しいものを上に追記する。README は自由に更新してよいが、変更理由をここに残す。

## 2026-10-14 — `count-words` を追加し、モードラインの字数のリアルタイム表示はしない(v0.1.0 のフィードバック)

- **変更前**: 文字数・行数を数える手段がなかった。
- **変更後**: `M-x count-words`(`M-=`)で、選択範囲(なければ文書全体)の行・単語・文字(空白を除く数も併記)を、表示されているテキストで数え、エコー領域に出す。元の Markdown の数は Emacs で測る。選択中の字数を、モードラインへリアルタイムで出す機能は、今後も実装しない(最小限の UI で十分、という Emacs の文化に沿う)。
- **理由**: ビューアなので、見た目の状態を優先する。表示を増やさない方針(`docs/project-model.md` §9)と揃える。
- 関連: `docs/interaction-model.md` §6.2。

## 2026-10-14 — UI の文言を英語に固定し、macOS と Emacs の流儀を場所で分ける(v0.1.0 のフィードバック)

- **変更前**(README「Principles」): UI の言語についての方針はなく、メニュー・モードライン・エコー・エラー文などは日本語で書かれていた。メニューは、独自の Frame メニューを持っていた。
- **変更後**: アプリ自身の文言は**英語に固定**する(ローカライズしない)。扱う文書・ファイル名・入力は、引き続き国際化されている。メニューバーとダイアログは macOS の流儀、フレームの中は Emacs の流儀、と場所で分ける。README「Principles」に `Mac outside, Emacs inside.` を追加。利用者向け文書の言語(英語を主、翻訳は後から)は、検討中。
- **理由**: Emacs の語彙は英語で、検索して世界の知見を共有しやすい。二言語の文言を保守しない。macOS 利用者がメニューで混乱しない。日本語の UI への違和感が、初期配布のフィードバックで出た。
- 関連: `docs/interaction-model.md` §6b、`docs/project-model.md` §10、`CLAUDE.md`(Decided: UI language, menus)。

## 2026-10-14 — Frame メニューを Window メニューに統合する(v0.1.0 のフィードバック)

- **変更前**(`docs/project-model.md` §10): 専用の Frame メニューに `Frame 1`〜`Frame 9` が常に並び、`Cmd-N` は、開いていない番号なら、その番号で新しいフレームを作った。
- **変更後**: Frame メニューは持たない。Window メニュー(macOS の流儀)に、開いているフレームの項目(`HyperBuf [N]`、前面のものに印)だけを並べ、`Cmd-N` はそのフレームを前面に出すだけ(開いていない番号では、何も起きない)。新しいフレームは `File > New Frame`(`Cmd-N`)か `C-x 5 2` で、空いている最小の番号になる。項目の表示は、当面、ウィンドウのタイトルと同じ `HyperBuf [N]`(あるべき形は、引き続き検討)。
- **理由**: メニューバーは macOS の流儀で組み、Emacs の世界に属するもの(`C-x 5 …`、フレームという用語)と分ける。
- 関連: `docs/project-model.md` §10。

## 2026-10-12 — v0.1.0 の初期配布（Project status の更新）

- **変更前**（README「Project status」）: 「Inception / Early design — コンセプト定義と技術検証の準備段階」。
- **変更後**: 「v0.1.0 — 関係者への初期配布の段階」。実装は M0〜M7b まで完了、M8（配布）が進行中。ソースの公開と一般向けの配布は、これから。
- **理由**: v0.1.0 の署名・公証済みビルドを、関係者へ非公開で配布し始めたため。公開前に、使い勝手のフィードバックを集める。
- 関連: `docs/migration-plan.md`（M8 の進捗）、`CLAUDE.md`（Project status）。

## 2026-10-12 — 外部リンクをブラウザで開く・数式の互換・更新への追従（v0.1 のフィードバック）

- **変更前**: 文書の外部リンク（`http(s)`）は開かない（README の「Local-first」「外部参照の制限」）。数式は TeX の規則どおり。外部更新では、閲覧位置を保つだけ。
- **変更後**:
  - 外部リンクは、**確認のうえ**、既定のブラウザで開く（`yes` / `no` / `always`）。`trustedUrls`（設定）と、`always` で記憶したサイトは、確認しない。`mailto:` は毎回確認。それ以外のスキーム、資格情報を含む URL は、開かない。文書の読み込みや表示が、ネットワークにアクセスすることは、ない（開くのは、利用者の操作のあと、ブラウザ）。
  - 数式の中の `\_` を `_` に戻す（Marked 2 などと同じ。`mathUnescapeUnderscore`、既定でオン）。
  - 外部更新で、最初に変わった場所へ移る機能（`followUpdates`、`C-x x u`、既定でオフ）。
  - 画面の見た目: window ごとのモードライン、選択中の window の青い枠を廃止（モードラインの反転で示す）。
  - シンタックスハイライトの言語を、約 50 言語に拡張（Emacs Lisp ほか）。大きな文法は、必要な文書を開いたときだけ読み込む。
- **理由**: 配布先の最初の利用者のフィードバック。外部リンクは、「文書を信頼しない」基準（Markdown は、AI が生成したものを含め、信頼しない）を保つため、利用者の操作と確認を必須にし、判断はアプリ側でもう一度確かめる。数式は、描画の質ではなく、エスケープの解釈の違いが原因だった（MathJax への切り替えは不要）。
- 関連: `docs/configuration.md`、`docs/syntax-highlighting.md`、`docs/keybindings.md`。

## 2026-10-10 — ライセンスの決定（M8）

- **変更前**（README「Project status」）: 「サポート対象OS、ライセンスなどは未確定です」。2026-10-08 の記録では、「ライセンスは公開前に確認し、難しい問題があれば公開・配布を諦めて個人のツールとして使う」。
- **変更後**: HyperBuf 本体は **Apache-2.0**、`emacs/` は **GPL-3.0-or-later**（ディレクトリごとのライセンス）。著作権者の表記は `Copyright 2026 Yasuo Hojo`。README に「License」を追加した。
- **理由**: 同梱するサードパーティのライセンスを洗い出した結果、GPL 系はなく、許容的なライセンスがほとんどだった（EPL-2.0 の `elkjs` は外した）。許容的で、特許の許諾が明示され、商標を許諾しない旨が明記される Apache-2.0 を選んだ。Emacs のパッケージは、Emacs の慣例（GPL と両立するライセンス、将来の ELPA）に合わせて GPL-3.0-or-later にした。
- 関連: `docs/license-options.md`、`docs/third-party-licenses.md`、`LICENSE`、`NOTICE`、`emacs/LICENSE`。

## 2026-10-10 — Mermaid のレイアウトを dagre に固定し、elkjs を同梱しない(M8)

- **変更前**（README「Architecture and technology」）: Diagrams は「Mermaid（決定、遅延ロード・strictモード）」。Mermaid 12.1 の既定のレイアウト（ELK。`elkjs` は EPL-2.0）をそのまま使っていた。
- **変更後**: Mermaid のレイアウトを **dagre に固定**する（Mermaid 11 までの既定で、GitHub の表示と同じ）。`elkjs` は同梱しない。図が `layout: elk` を明示すると、その図だけが、図の位置にエラーとして表示される。
- **理由**: 同梱するサードパーティのライセンスの洗い出し（M8）で、`elkjs` が EPL-2.0（弱いコピーレフト。GPL と結合できない）と分かった。dagre に固定すれば、GitHub の見た目に近づき、EPL の条件（ソースの入手先の表示）も不要になり、将来のライセンスの選択肢（GPL を含む）が広く残る。dist は約 3.6 MB 減る。
- 関連: `docs/license-options.md`、`docs/third-party-licenses.md`。

## 2026-10-10 — プロジェクトを持たない設計と、複数フレーム(M7b)

- **変更前**（README「1. Project-oriented reading」）: 「ディレクトリを単位としてプロジェクトを開き、内部のMarkdownファイルを横断して閲覧する」。ファイルのアクセスの範囲は、プロジェクト(+ 信頼するルート)。セッションは、プロジェクトごと。ウィンドウは 1 つ。
- **変更後**: プロジェクトという単位を持たない。バッファの識別は絶対パスで、基準は現在のバッファのファイルのディレクトリ(Emacs の `default-directory`)。`C-x C-f` は、基準のディレクトリから始まるパス補完、`C-x p f` と全文検索は、基準以下の再帰(`~` と `/` は起点にしない)。アクセスの安全は、許可パス / 警告パスで決める(URL スキーム経由は、許可パス以外を確認)。バッファ名は Emacs の uniquify。セッションは全体で 1 つのファイルに、フレームの並びとして保存する。フレーム(macOS のウィンドウ)を複数持て、`Cmd-1`〜 で切り替える(各フレームは、独立した作業場)。表示は最小限(ヘッダと候補はバッファ名だけ)。
- **理由**: 大量の文書を、プロジェクトの境界を意識せずに、複数の場所(複数のリポジトリ、ダウンロードしたフォルダなど)から並行して読むため。Emacs の流儀(バッファが主役)に合わせ、「どのプロジェクトか」を選ばせない。複数フレームは、後から足すのが大変なので、最初から設計に入れる。VCS のルートまでさかのぼる探索は、将来の拡張として残す。
- 関連: `docs/project-model.md`。

## 2026-10-09 22:30 JST — セッションの復元の方針(M7)

- **変更前**（README「4. Development-workflow integration」）: 「プロジェクト、分割配置、閲覧位置、履歴などのセッション復元を検討する」。
- **変更後**: 分割配置・各 window の参照履歴(文書・アンカー・閲覧位置)・選択中の window・buffer の最近使った順を、プロジェクトごとに保存し、次回の起動で復元する(既定で有効、`config.json` の `restoreSession` で無効にできる)。文書の内容と仮想 buffer は保存しない。起動時にどのプロジェクトを開くかは、この方針に含めず、別途検討する(未決定)。
- **理由**: 範囲は A 案(プロジェクト・配置・閲覧位置)で合意。参照履歴は、window の現在位置と同じデータなので、window ごとにそのまま保存する。保存データは信頼しない入力として検証し、壊れていれば通常の起動にする。
- 関連: `docs/session-restore.md`、`docs/configuration.md`。

## 2026-10-09 01:48 JST — 操作の一覧の更新(M3)

- **変更前**（README「Initial interaction sketch」）: 操作の一覧は、初期案(分割・buffer 切替・ファイルを開く・コマンド・文書内検索・Back/Forward)のみ。
- **変更後**: 実装済みの操作を、一覧に追加した。文書内検索は `C-s` / `C-r`(インクリメンタル)、プロジェクト検索 `M-s g`、outline 風の見出し移動(`C-c C-n/p/f/b/u`。`C-c` 系を、このために取っておく方針の実装)、`C-x k`(buffer を閉じる)、`C-c e`(エディタで編集)、`C-h b`(キー割り当ての一覧)。キー割り当ては、`config.json` の `keybindings` で変えられる。一覧の全体は、`docs/keybindings.md`(コードから自動生成)に置く。
- **理由**: README の一覧は「初期案」で、実装で確定した操作と食い違ってきたため。README では、代表的な操作だけを示し、全体は、コードから生成した文書に任せる(食い違いを防ぐ)。
- 関連: `docs/keybindings.md`、`docs/configuration.md`。

## 2026-10-08 23:34 JST — 構成・名前・言語・対応OSの決定

- **変更前**（README/CLAUDE.md）: 名前は「Hyperbuf（仮称）」。構成は `app/` `cli/` `emacs/` `docs/` の計画。Web コアは素の JavaScript、CLI や最小の macOS は未決。
- **変更後**: 名前は **HyperBuf**（GUI は `HyperBuf.app`、CLI・URL スキーム・リポジトリは `hyperbuf`）に確定（仮称を外す）。構成は `core/` `app/macos/`（他OSは `app/<platform>/`）`cli/` `emacs/` `protocol/` `fixtures/` `docs/`。Web コアは **TypeScript**（React は使わない）。Swift のビルドは SwiftPM + スクリプト。CI は最初の段階（M0）で骨組みを入れる。最小の macOS は、Apple が保守を続けている世代まで対応（提案: macOS 14 以上）。ライセンスは公開前に確認し、難しい問題があれば公開・配布を諦めて個人のツールとして使う。
- **理由**: PoC で素の DOM と JavaScript で足りたが、公開リポジトリの保守性と貢献しやすさのために型を付ける。他OS を追加するとき、ディレクトリを付け替えずに済むよう `app/macos/` とする。名前は、Web 検索・GitHub・npm・Homebrew で同名の製品が見つからなかった（商標とドメインの登録は未確認）。
- 関連: `docs/migration-plan.md`、README、CLAUDE.md を更新。

## 2026-10-08 23:13 JST — 連携プロトコルと配布方式の決定

- **変更前**（README）: 配布、連携の経路は未確定。`hyperbuf` CLI と Emacs 連携は構想のみ。
- **変更後**: 配布は**オープンソース（GitHub）+ Developer ID 署名・公証の直接配布**（Mac App Store は対象外、サンドボックスなし）。連携の主経路は **Unix ドメインソケット**（JSON Lines、同一ユーザーのみ）、`hyperbuf://` URL スキームはアプリの起動と外部リンク用。Emacs 連携は直接ソケットが標準（設定で CLI 経由に切替可）。範囲外のファイルは、URL・ソケットのどちらでもミニバッファで確認。逆方向（ビューアから Emacs で編集）は「Emacs で編集」メニュー + 位置の問い合わせで、照合に失敗したら警告のみ（続行不可）。
- **理由**: URL スキームは起動と受け渡しは標準で済むが一方通行で、結果の応答や位置の問い合わせができない。非サンドボックスの直接配布なら IPC に制約がない。ブラウザは Unix ドメインソケットに接続できないため、Web 由来の要求が混ざらない。逆方向は、巨大な文書で別の場所を編集してしまった経験から、「黙って食い違わない」ことを要件にした。
- **実機確認**: `.app` の URL スキーム登録、コールドスタート約 1.1 秒、起動中の転送約 265〜290 ms、異常系の拒否。登録は確認後に解除した。
- 関連: `docs/integration-protocol.md`、README、CLAUDE.md を更新。

## 2026-10-08 22:40 JST — ファイル監視・全文検索・仮想bufferの決定

- **変更前**（README「Architecture and technology」）: Project search は ripgrep・インデックス方式の候補、File monitoring は OS ネイティブ機構とライブラリの候補で、未決定。
- **変更後**: ファイル監視は **FSEvents**。全文検索は **Swift 自前実装から開始**（`host.search` の契約でエンジンを差し替え可能にし、正規表現や除外規則が必要になった時点で ripgrep を再評価）。一覧・検索の対象は当面 `*.md` とディレクトリのみ（既定の除外: 隠しファイル・隠しディレクトリ、`node_modules`。`.gitignore` は解釈しない）。仮想 buffer（`*search: …*`）と行アンカー（`path#line:N`）を操作モデルに取り込む。メモリ使用量の調査はプロジェクト後半に回す。
- **理由**: 5,000 ファイル（12.7 MB）でも、自前実装の全文検索は約 70 ms、FSEvents の反応は約 12 ms、ファイル名の絞り込みは 1 ms 以下で、いずれも十分。ポーリングは削除を検知できず、ファイル数に比例して重い。ripgrep は同梱と外部コマンドの権限設計が要り、macOS の `Process` 引数で日本語の濃点が分解される落とし穴もあるため、必要になるまで見送る。
- **併せて決定**: メモリは、描画バンドルの導入で約 173 MB から約 380〜410 MB に増えたが、現時点では許容し、後半にリークの有無と内訳をまとめて確認する。
- 関連: `docs/poc-navigation-results.md`、`docs/interaction-model.md` §5b、README の技術表と未決事項、CLAUDE.md を更新。

## 2026-10-08 22:21 JST — レンダリング層の決定

- **変更前**（README「Architecture and technology」）: Markdown pipeline、GFM、数式、図、シンタックスハイライトは候補を並べた状態で未決定。
- **変更後**: unified / remark / rehype（remark-gfm、github-markdown-css、rehype-sanitize）、KaTeX、Mermaid、starry-night を採用。MathJax、Graphviz、PlantUML、WaveDrom、D2 は未評価のまま。
- **理由**: SwiftUI + WKWebView 上で検証し、GitHub の表示と比べて違和感がなく、不信任な HTML・SVG でも無害で、描画性能も問題なかった。starry-night は Shiki より速く、出力が小さく、GitHub と同じ文法・クラス名で互換性が高い。
- **併せて決定**: 起動時に読む JS（約 1.95 MB）は、体感の問題がないためこのままとする。
- 関連: `docs/poc-rendering-results.md`、README の技術表、CLAUDE.md を更新。

## 2026-10-08 21:16 JST — macOS 向けシェルの決定

- **変更前**（README「Architecture and technology」）: macOS application shell は Tauri 2 / Rust、SwiftUI + WKWebView、Electron の候補で未決定。未決事項に「macOS統合優先か、Web技術の親和性・移植性優先か」。
- **変更後**: macOS 向けシェルは **SwiftUI + WKWebView** に決定。他OSは各プラットフォームに最適なフレームワークでシェルを書き、共通の Web コアを再利用する。
- **理由**: Interaction PoC で2案を同一の Web コアで比較し、応答性は同等（SwiftUI が数 ms 速い）、macOS 統合・ビルド・依存で SwiftUI が優位だった。他OSでは、クロスプラットフォーム基盤を共有するより、OS ごとに最適なフレームワークを使うほうが、微妙なバグを避けられるという判断。
- 関連: `docs/poc-interaction-results.md`、README の技術表と未決事項、CLAUDE.md を更新。

## 2026-10-08 20:38 JST — Back / Forward のキーとミニバッファ

- **変更前**（README）: Back / Forward のキーは TBD。入力欄の扱いは未定。
- **変更後**: Back / Forward は `C-b` / `C-f`（別名 `Cmd+[` / `Cmd+]`）。検索やbuffer選択などの入力は、ダイアログではなくframe下部のミニバッファで行う。
- **理由**: Emacs では C-f/C-b が「編集対象の流れ」を泳ぐ操作に使われる。HyperBuf の主な使い方は、大量の文書を参照の流れに沿って前後に読み進めることなので、同じキーの意味を参照の流れに再利用するのが自然。ミニバッファは入力の見た目と操作を全体で揃える。
- **併せて決定**: 閲覧画面にカーソルは表示しない方向。コピーのためのテキスト選択は別途検討する。`M-f` / `M-b` は予約（案は `docs/interaction-model.md`）。
- 関連: README「Open questions」の入力・選択の項目を更新。

## 2026-10-08 20:25 JST — 参照履歴とbuffer切替の関係

- **変更前**（README「2. Emacs-inspired navigation」）: Back / Forward は参照履歴の前後移動に割り当て、単なるbuffer切替履歴とは区別する。
- **変更後**: Back / Forward は参照履歴の前後移動に割り当てる。リンクや見出しジャンプに加え、`C-x b` などによるbuffer切替も参照として履歴に積む。`C-x b` の候補順（最近使った順）は参照履歴とは別に管理する。
- **理由**: 切替を履歴に積めば Back で直前の文書に戻れて直感的であり、「参照」と「切替」を履歴上で分ける利点が小さいと判断した。
- **併せて決定**: window分割時は、新しいwindowに参照履歴を複製する。
- 関連: README「Open questions」の履歴に関する項目を更新。詳細は `docs/interaction-model.md`。
