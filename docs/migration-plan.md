# PoC から本実装への移行計画

状態: **Draft** — 「提案」は合意前。合意した項目は「合意済み」と明記する。

## 1. 目的と前提

PoC(Interaction、Rendering、Project navigation、連携プロトコル)で、技術選定と主要な設計の検証が済んだ。本計画は、**PoC のコードを、保守できる本実装に移す順序と構成**を定める。

決定済みの前提(`CLAUDE.md`、各結果文書):

- macOS 向けシェルは SwiftUI + WKWebView。他OSは、そのOSに最適なフレームワークで、共通の Web コアを再利用する。
- Web コアはシェルに依存させず、境界は `hyperbufHost` の契約に限る。
- レンダリングは unified / remark / rehype、remark-gfm、KaTeX、starry-night、Mermaid、rehype-sanitize、github-markdown-css。
- ファイル監視は FSEvents。全文検索は Swift 自前実装(`host.search` の契約でエンジンを差し替え可能)。
- 連携の主経路は Unix ドメインソケット(JSON Lines)。URL スキーム `hyperbuf://` は起動と外部リンク用。Emacs 連携は直接ソケットが標準。
- 配布はオープンソース(GitHub)と、Developer ID 署名・公証の直接配布。サンドボックスなし。
- PoC のコードは `poc/*` ブランチに残す。`main` には、設計文書と、本実装だけを入れる。

## 2. PoC の成果物と、本実装での扱い

規模は、`poc/integration`(PoC の最新)の実測。

| PoC の成果物 | 行数 | 本実装での扱い |
| --- | --- | --- |
| `web/model.js` | 168 | **引き継ぐ。** buffer / window / 履歴 / 分割ツリーの純粋なロジック。テストごと移す。見出し解析は、描画後の DOM を正とする(`parseHeadings` の扱いを整理する) |
| `web/keys.js` | 81 | **引き継ぐ。** キー名の変換と、プレフィックスの状態機械。キーマップの設定ファイル対応を足す |
| `web/fuzzy.js` | 47 | **引き継ぐ。** 順位付けの改善は後で(`g3d42` のような飛び飛びの一致) |
| `web/pipeline.js` | 229 | **引き継ぐ。** サニタイズ、行アンカー、アラート、画像、数式の `$` の互換、Mermaid の遅延描画。セキュリティのテストを強化する |
| `web/host.js` | 40 | **契約として引き継ぐ。** `hyperbufHost` を、型付きのインターフェースとして文書化する。開発用の fetch ホストは、テスト用として残す |
| `web/app.js` | 479 | **分割して作り直す。** UI、コマンド、ミニバッファ、描画、ホストのイベント処理が 1 ファイルに混在している(§3) |
| `web/build.mjs`、`style.css`、`index.html` | 約 75 | 引き継ぐ。ビルドの成果物(`dist/`)はコミットしない |
| `swiftui/Host.swift` | 437 | **責務ごとに分割して作り直す**(スキームハンドラ、ブリッジ、プロジェクトのファイルアクセス、検索、URL の検証、ログ)。PoC 用のデバッグ機構(`HYPERBUF_DEBUG*`、`TMPDIR` へのログ)は、テスト用の仕組みに置き換える |
| `swiftui/IPC.swift` | 203 | **引き継ぐ。** 検証済み。プロトコル型を共有ライブラリへ、サーバーを独立した部品にする |
| `swiftui/Watcher.swift` | 50 | 引き継ぐ。ポーリングの旧実装は捨てる |
| `swiftui/App.swift`、`make-app.sh` | 50 + 34 | 作り直す。署名・公証を含むビルドの仕組みにする(§4) |
| `cli/hyperbuf`(bash)、`cli/hyperbuf-ipc`(python) | 44 + 71 | **捨てる(試作)。** 単一バイナリの CLI に作り直す。仕様は `integration-protocol.md` |
| `bench/gen-corpus.py`、`sample/` | 63 + 16 ファイル | **テストの素材として引き継ぐ。** 検証用の文書集と、生成スクリプト |
| Tauri の PoC(`poc/tauri-shell`) | — | 比較の記録として、ブランチを残すだけ |

## 3. 構成(提案)

```
/
├── core/        共通の Web コア(model, keys, fuzzy, pipeline, host の契約、UI)
├── app/         macOS アプリ(SwiftUI + WKWebView のシェル)
├── cli/         hyperbuf コマンド
├── emacs/       Emacs 連携(hyperbuf.el)
├── protocol/    連携プロトコルの定義と適合テスト用のデータ
├── fixtures/    検証用の文書集、コーパスの生成スクリプト
└── docs/        設計文書、PoC の結果、計画変更ログ
```

- **`core/`(新設):** CLAUDE.md の計画(`app/` `cli/` `emacs/` `docs/`)に、共通の Web コアを独立させて足す。他OS のシェルが再利用する単位なので、`app/` の中には置かない。
- **`protocol/`(新設):** URL・ソケットの契約を、機械可読な形(JSON Schema と、要求・応答の例)で持つ。Swift のサーバー、Swift の CLI、Emacs Lisp のクライアントの 3 つが、同じ例で適合テストを行う。
- **`fixtures/`:** 現在の `poc/sample` と `poc/bench`。テストと、性能の測定の両方で使う。

### `core/app.js` の分割(提案)

| モジュール | 責務 |
| --- | --- |
| `commands` | コマンドの登録と実行(直列化したキュー) |
| `minibuffer` | 入力・候補・確認(ダイアログを使わない) |
| `view/windows` | 分割ツリーと window の描画、スクロール位置の管理 |
| `view/document` | 文書の描画、アンカー・行アンカー、Mermaid の後処理、外部更新時の位置維持 |
| `session` | 状態の保存・復元(セッション復元の仕様確定後) |
| `host-events` | ホストからのイベント(ファイル変更、「開く」要求、問い合わせ)の受け口 |
| `config` | キーマップなどの設定の読み込み |

## 4. ビルドと配布の方針(提案)

| 項目 | 提案 | 理由 |
| --- | --- | --- |
| Swift 側のビルド | **SwiftPM + スクリプト**(`.app` の組み立て、署名、公証は `codesign` / `notarytool` のスクリプト)。Xcode プロジェクトは、必要になるまで作らない | PoC で動いている。CI で再現しやすく、プロジェクトファイルのマージの手間がない。アセットカタログなどが必要になったら Xcode プロジェクトへ移る |
| Web コアのビルド | esbuild(PoC のまま)。成果物は `app` のバンドルに同梱 | PoC で検証済み |
| CLI | **Swift の単一バイナリ**(`cli/`)。アプリのバンドルに同梱し、インストール用のコマンドで `/usr/local/bin` などにリンク | 起動が速く、プロトコル型をアプリと共有できる。Homebrew の cask でも `binary` として扱える |
| Swift の言語モード | Swift 6 の厳密な並行性(PoC は 5 モード) | 新規コードで早めに合わせるほうが安い。移行時に判断 |
| 配備先の最小バージョン | PoC は macOS 14。**決める必要あり**(§8) | |
| 署名・公証 | Developer ID、Hardened Runtime、公証。**WASM(`wasm-unsafe-eval`)と WKWebView の組み合わせでの動作確認が必要**(未検証) | starry-night の WASM を使うため |
| 配布物 | `.zip`(または `.dmg`)と Homebrew cask | GitHub の Releases で配布 |

## 5. 品質の仕組み(提案)

| 層 | 内容 |
| --- | --- |
| Web コアの単体テスト | PoC の 27 件を引き継ぎ、拡充する(`node --test`)。サニタイズは、`06-html-security.md` の入力を自動テストにする |
| Swift の単体テスト | パスの検証(絶対パス、`..`、シンボリックリンク、`.md`)、プロジェクトの範囲判定、IPC のフレーミング(1 MiB 上限、不正な JSON、分割して届くメッセージ)、検索(日本語、ASCII の大文字小文字) |
| プロトコル適合テスト | `protocol/` の例を、Swift のサーバー、CLI、Emacs Lisp のクライアントで共有して検証する |
| 統合テスト | 実際の WKWebView でアプリを起動し、PoC の自動チェック(全文書の描画、CSP 違反の有無、`alert` の発火の有無)を、テスト用のフックで再現する |
| 性能の回帰テスト | PoC の測定(5,000 ファイルでの検索、一覧、監視の反応時間、キー入力の遅延)に基準値を設け、回帰を検知する |
| 手動確認 | キー操作(`C-x` 系、`Option` を使う `M-v`)、右クリックメニューなど、自動化しにくいもの。確認の手順を文書化する |
| CI | GitHub Actions の macOS ランナー。利用できる macOS・Xcode のバージョンに依存するため、**早めに確認する** |

## 6. 作業の順序(提案)

各段階の終わりで、「完了の条件」を満たしたら `main` に入れる。

| # | 段階 | 内容 | 完了の条件 |
| --- | --- | --- | --- |
| M0 | **足場** | リポジトリの構成(§3)、ライセンス、フォーマッタ・リンタ、CI の骨組み、`fixtures/` の移設 | 空のアプリと、空の `core` のビルドとテストが CI で通る |
| M1 | **Web コア** | `core/` に model / keys / fuzzy / pipeline / host の契約を移し、`app.js` を分割して作り直す。PoC のテストを移す | 開発用ホストで、PoC と同じ操作ができる。単体テストが通る |
| M2 | **macOS シェル** | `app/`: ウィンドウ、スキームハンドラ、ブリッジ、プロジェクトのファイルアクセス、FSEvents、全文検索。Swift の単体テスト | 自分たちの文書(`docs/`)を、アプリで読める(**ドッグフーディングの開始**) |
| M3 | **ナビゲーションの UI** | ミニバッファ、ファイル探索、buffer 切替、検索結果(仮想 buffer)、履歴、キーマップの設定 | README の「Project-oriented reading」の項目を満たす |
| M4 | **IPC・CLI・URL** | ソケットのサーバー、`hyperbuf` CLI、URL スキーム、範囲外の確認、信頼するルート、`protocol/` の適合テスト | `hyperbuf file.md:120` がコールド・ウォームで動く |
| M5 | **Emacs 連携** | `emacs/hyperbuf.el`(直接ソケットが標準、CLI に切替可) | Emacs から「開く」が動く |
| M6 | **逆方向の連携** | 「Emacs で編集」メニュー、選択 → 元の位置の対応、`get-location`、Emacs 側の照合・警告(R1〜R5) | 巨大な文書の、同じ文言が複数ある箇所で、誤った場所に飛ばないことを実証する |
| M7 | **セッション復元・設定** | 保存形式、復元の範囲(分割・履歴・閲覧位置・信頼するルート)、設定ファイル | 再起動後に、作業中の状態が戻る |
| M8 | **配布** | 署名、公証、`.zip` / `.dmg`、Homebrew cask、リリースの自動化、公開に向けた整備(ライセンス、README、セキュリティ報告の窓口、貢献ガイド) | 公証済みのビルドを、まっさらな Mac で起動できる |

- M5・M6 は、M4 のプロトコルが固まれば、M3 と並行できる。
- **ドッグフーディング(M2)を早く始める。** 自分たちの文書を、実際にこのビューアで読みながら改善する。
- 各段階で、PoC で見つけた問題(CSP、Unicode の分解、脚注の ID など)の回帰テストを、先に書く。

## 7. PoC の扱い

- PoC のブランチ(`poc/interaction-web`、`poc/swiftui-wkwebview`、`poc/tauri-shell`、`poc/rendering`、`poc/navigation`、`poc/integration`)は、削除せず残す(運用ルール)。
- 本実装は、PoC のコードをそのままマージせず、`main` に新しいコミットとして書く。**コミットメッセージや文書に、元になった PoC のコミットを記録する。**
- 作業ツリーは、PoC ごとの worktree(`../hyperbuf-poc/*`)を引き続き使い、`main` の作業ツリーと分ける。

## 8. 判断が必要な点

1. **構成(§3)。** `core/` の新設、`protocol/` と `fixtures/` の追加でよいか。ディレクトリの名前は。
2. **Web コアの言語。** 現在は素の JavaScript(型なし、ESM)。**TypeScript にするか。** `tsc` による型検査を CI に入れ、esbuild で変換する形が現実的。公開リポジトリの保守性と、貢献しやすさの点で、TypeScript を推す。README の候補に挙げた React は、PoC で素の DOM で足りたため、**使わない**ことを確認したい。
3. **Swift のビルド。** SwiftPM + スクリプト(提案)でよいか。
4. **CLI の言語。** Swift(提案)でよいか。
5. **ライセンス。** 公開前に決める必要がある(MIT、Apache-2.0、GPL など)。依存ライブラリのライセンスとの整合も確認する。Emacs 連携部分は、Emacs のコミュニティの慣習(GPL)との関係も考える。
6. **最小の macOS バージョン。** 14(PoC の指定)か、新しいものか。
7. **プロダクト名。** 「Hyperbuf(仮称)」を確定するか。Bundle ID、CLI の名前、URL スキーム、ドメインに影響する。
8. **CI を始める時期。** M0 で骨組みを入れる(提案)でよいか。

## 9. 未検証のリスク

- 署名・公証・Hardened Runtime での、WKWebView と WASM(starry-night)の動作。
- GitHub Actions の macOS ランナーで、必要な Xcode・macOS のバージョンが使えるか。
- 別のユーザーからのソケット接続の拒否(`getpeereid`)。
- メモリ使用量(描画バンドルで約 173 MB から約 380〜410 MB へ増加)。後半にまとめて調査する(合意済み)。
- 選択 → 元の位置の対応の精度(強調・リンクをまたぐ選択)。M6 で検証する。
