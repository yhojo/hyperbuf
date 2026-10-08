# 計画変更ログ

README.md に記載した方針・計画を変更した際の記録。新しいものを上に追記する。README は自由に更新してよいが、変更理由をここに残す。

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
- **理由**: Emacs では C-f/C-b が「編集対象の流れ」を泳ぐ操作に使われる。Hyperbuf の主な使い方は、大量の文書を参照の流れに沿って前後に読み進めることなので、同じキーの意味を参照の流れに再利用するのが自然。ミニバッファは入力の見た目と操作を全体で揃える。
- **併せて決定**: 閲覧画面にカーソルは表示しない方向。コピーのためのテキスト選択は別途検討する。`M-f` / `M-b` は予約（案は `docs/interaction-model.md`）。
- 関連: README「Open questions」の入力・選択の項目を更新。

## 2026-10-08 20:25 JST — 参照履歴とbuffer切替の関係

- **変更前**（README「2. Emacs-inspired navigation」）: Back / Forward は参照履歴の前後移動に割り当て、単なるbuffer切替履歴とは区別する。
- **変更後**: Back / Forward は参照履歴の前後移動に割り当てる。リンクや見出しジャンプに加え、`C-x b` などによるbuffer切替も参照として履歴に積む。`C-x b` の候補順（最近使った順）は参照履歴とは別に管理する。
- **理由**: 切替を履歴に積めば Back で直前の文書に戻れて直感的であり、「参照」と「切替」を履歴上で分ける利点が小さいと判断した。
- **併せて決定**: window分割時は、新しいwindowに参照履歴を複製する。
- 関連: README「Open questions」の履歴に関する項目を更新。詳細は `docs/interaction-model.md`。
