# PoC から本実装への移行計画

状態: **合意済み(2026-10-08)。M0 から着手する** — 「提案」は合意前。合意した項目は「合意済み」と明記する。

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

## 3. 構成(合意済み、2026-10-08)

```
/
├── core/          共通の Web コア(TypeScript。model, keys, fuzzy, pipeline, host の契約, UI)
├── app/
│   └── macos/     macOS アプリ(SwiftUI + WKWebView のシェル)。他OSは app/linux/、app/windows/ などを並べる
├── cli/           hyperbuf コマンド
├── emacs/         Emacs 連携(hyperbuf.el)
├── protocol/      連携プロトコルの定義と適合テスト用のデータ
├── fixtures/      検証用の文書集、コーパスの生成スクリプト
└── docs/          設計文書、PoC の結果、計画変更ログ
```

- **`app/<プラットフォーム>/`:** 他OSを足すとき(Linux、Windows)は、`app/linux/`、`app/windows/` を並べる。各ディレクトリは、そのOSに最適なフレームワークで書く(「プラットフォームごとに最適なフレームワーク」の方針)。**最初から `app/macos/` とし、あとでのディレクトリの付け替えを避ける。**
- **`core/`:** 他OS のシェルが再利用する単位なので、`app/` の中には置かない。
- **`protocol/`:** URL・ソケットの契約を、機械可読な形(JSON Schema と、要求・応答の例)で持つ。Swift のサーバー、CLI、Emacs Lisp のクライアントが、同じ例で適合テストを行う。
- **`fixtures/`:** 現在の `poc/sample` と `poc/bench`。テストと、性能の測定の両方で使う。
- **`cli/`:** 当面は、1 つの実装を平らに置く。他OS の CLI が必要になった時点で、構成を見直す(§4 の CLI の言語を参照)。

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
| Swift 側のビルド(合意済み) | **SwiftPM + スクリプト**(`.app` の組み立て、署名、公証は `codesign` / `notarytool` のスクリプト)。Xcode プロジェクトは、必要になるまで作らない | PoC で動いている。CI で再現しやすく、プロジェクトファイルのマージの手間がない。アセットカタログなどが必要になったら Xcode プロジェクトへ移る |
| Web コアのビルド(合意済み) | **TypeScript**。`tsc` で型検査し、esbuild で変換する。成果物は `app` のバンドルに同梱。UI のフレームワークは使わない(React は不使用) | PoC で素の DOM で足りた。型は公開リポジトリの保守性と貢献しやすさのため |
| CLI(提案、§8 で確認) | **当面は Swift の単一バイナリ**(`cli/`)。アプリのバンドルに同梱し、インストール用のコマンドで `/usr/local/bin` などにリンク | 追加のツールチェーンが要らず、アプリのビルドに載る。Homebrew の cask でも `binary` として扱える。他OS向けは、そのOSに合う形で書き直す(CLI は数百行で、プロトコルだけが結合点) |
| Swift の言語モード | Swift 6 の厳密な並行性(PoC は 5 モード) | 新規コードで早めに合わせるほうが安い。移行時に判断 |
| 配備先の最小バージョン | **macOS 14(Sonoma)以上**(提案、§8) | Apple がセキュリティ更新を続けている世代を対象にする方針(下記) |
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

### 進捗

| # | 状態 | メモ |
| --- | --- | --- |
| M3 | **完了(2026-10-09)** | **ナビゲーション UI**: ミニバッファを作り直し(`live` モード、候補の件数と一致部分の強調、`M-p` / `M-n` の入力の履歴、表示 10 件)。**文書内のインクリメンタル検索(`C-s` / `C-r`)**: 入力のたびに一致を数えて、CSS Custom Highlight API でハイライト(非対応なら、現在の一致だけを選択状態に)、`Wrapped` / `Failing`、`RET` で位置にとどまり(一致は選択状態で残る)、`C-g` で戻り、空のときの `C-s` は前回の語、大文字を含むときだけ区別。**outline 風の見出し移動**(`C-c C-n/p/f/b/u`、参照履歴に積まない)、`M-<` / `M->` / `SPC` / `DEL`。**キーマップの設定**(`config.json` の `keybindings`、コマンド名で足す・置き換える、`null` で外す。不正な設定は無視して `C-h b` に理由を出し、処理順は設定の並びに依存しない)と **`describe-bindings`**(`C-h b`)。**`kill-buffer`**(`C-x k`、どの window の履歴からも参照を取り除く)。`C-x C-f` は最近使った文書が先。`docs/keybindings.md` はコードから自動生成し、`npm run check` が最新かを検査する。macOS の Option で `event.key` が変わる記号(`M-<` など)は、物理キー(`code`)から求める。テスト: `core` 78 件、`app/macos` 58 件、実際の WKWebView の UI 統合テスト 32 項目(`scripts/integration-test-ui.sh`)。WKWebView は、入力欄のフォーカス喪失で選択を解除するため、isearch の確定後に選択し直す。**手動確認で見つけて直したもの**: 検索中に文書の選択を作るとミニバッファがフォーカスを失う、日本語入力(確定の Enter は `keyCode 229`・確定時に入力が一度空になる・変換中の途中の一致に引きずられる。`docs/interaction-model.md` 6.1)、Option つきの Dead キー(`M-n` の `˜`)、起動直後にクリックするまでキーを受け付けない(WKWebView をファーストレスポンダにする)。`C-g` で抜けた検索語も、次の `C-s C-s` で使える |
| M6 | **完了(2026-10-09)** | **ビューアから編集位置へ**(§10 の R1〜R5): ブロック要素に元の位置(開始・終了のオフセットと行)を残し、**選択した文字列が、ブロックの中でちょうど 1 か所のときだけ exact**、見つからない・複数・選択なし・複数ブロックなら **block**(推測しない)。桁はコードポイント。`get-location`(指した位置 + 照合用の file・expect・context)、`get-view`(いまの表示)。ファイルの SHA-256 は、ビューアに渡したバイト列から求め、`FileAccess` が読むたびに記録する。右クリックメニュー「Emacs で編集」(`EditorWebView`)、キー `C-c e`、設定ファイルの**固定コマンド**でエディタを呼び出す(シェルを介さない、絶対パス、位置・パス・選択を引数に含めない、5 秒の期限)。**Emacs: `hyperbuf-visit-location`**(ファイルの版・その位置の文字列・前後の文脈を照合し、失敗したら、移動も続行もせず、`*hyperbuf-mismatch*` に詳細。未保存の編集でずれていても検出)。照合の規則は `protocol/examples/location-check.json` を共有して適合テスト(壊すと失敗することを確認)。**統合テスト 64 項目**(選択 → 記録 → 固定コマンドの実行と引数 → Emacs が 3 行目・5 文字目へ移動 → 曖昧な選択は block で、ブロックの先頭へ → 検索結果は拒否 → ファイル変更後は stale で移動しない)。ネイティブのメニュー項目の実機での操作は、手動で確認済み(2026-10-09) |
| M5 | **完了(2026-10-09)** | `emacs/hyperbuf.el`: 直接ソケットが標準、`hyperbuf-transport` を `cli` にすると CLI 経由。アプリが未起動なら、開く要求の URL で起動。入力の検証を Emacs 側にも持ち、`protocol/examples/` の `open-validation.json`(検証)と `url.json`(URL の組み立て)を、Swift と共有して適合テスト(例を壊すと失敗することを確認)。ERT 18 件(ローカルのソケットサーバーとの往復、日本語のパス、エラー応答、期限切れ、起動、CLI 経由、未保存のバッファ、TRAMP の拒否)。**実際の `.app` に対する統合テスト 43 項目**(うち Emacs 6 項目: 直接ソケット・アンカー・承認済みの範囲外・拒否・CLI 経由)。使い方は `emacs/README.md` |
| M4 | **完了(2026-10-09)** | **`protocol/`**: JSON Schema(要求・応答)、共有の例(`open` の検証 21 件、URL 9 件、JSON Lines 5 件、CLI の引数 18 件)、Swift の `HyperBufProtocol`(型・検証・URL・切り出し・ソケットのパス)と `HyperBufIPC`(`SocketServer`・`SocketClient`)。例を壊すと、Swift・CLI・JSON Schema の適合テストが失敗することを確認。**アプリ**: `OpenFlow`(検証 → 分類 → Web コアへの引き渡し → 結果の返却・期限・期限切れ時の確認の取り消し)、`TrustedRoots`(永続化、0600/0700)、`FileAccess`(相対はプロジェクト内、絶対は信頼するルートの内側だけ)、`ProjectLocator`(`.git` の祖先)、URL スキーム。範囲外は Web コアのミニバッファで確認し、承認されたルート(アプリが提案したものだけ)が信頼するルートに加わる。**CLI**: `hyperbuf`(Swift、終了コード 0〜5、`--wait`・`--print-url` ほか、アプリが起動していなければ、開く要求の URL で起動)。テスト: `protocol/swift` 27 件、`app/macos` 40 件、`cli` 19 件、`core` 36 件。**実際の `.app` + ソケットのクライアント + CLI + URL スキームの統合テスト 36 項目**(`scripts/integration-test-ipc.sh`)。テストで見つけた問題: `try?` が内側の「範囲外」を「読めない」に潰す、`umask` のスレッド間の競合、Foundation の `Operation` との名前の衝突、`callAsyncJavaScript` は解決しない Promise を許さない |
| M2 | **完了(2026-10-08)** | `app/macos/`: `HyperBufKit`(`Project`: 範囲・`realpath` による正規化・除外規則・読み取りの制限、`ProjectSearch`、`FSWatcher`(FSEvents)、`StaticFiles`、`ContentSecurityPolicy`、`MimeType`)と、アプリ本体(`SchemeHandler`、`Bridge`、`ProjectSession`、`WebShell`、`ProjectPicker`、`WebRoot`、デバッグ用の `TestHarness`)。PoC の `Host.swift`(437 行)を責務ごとに分けて作り直した。Swift の単体テスト 26 件。`scripts/integration-test.sh` が、実際の WKWebView で全文書を開き、描画・CSP 違反・検索・画像を検査する(検証用の文書集 12 文書と、`docs/` の 8 文書で通る)。`.app` を作る `app/macos/scripts/make-app.sh`(ad-hoc 署名)。**自分たちの `docs/` を、このアプリで読める(ドッグフーディングの開始)**。IPC・URL スキーム・CLI は M4 |
| M1 | **完了(2026-10-08)** | `core/` に model / keys / fuzzy / pipeline を TypeScript で移し、`app.js`(479 行)を、ミニバッファ・window の描画・コマンド・キー入力・検索・ホストのイベント・起動に分割した。開発用ホストと開発サーバー(`scripts/dev-server.mjs`、127.0.0.1 のみ、プロジェクト外と `.md`・画像以外は返さない)で、ブラウザで PoC と同じ操作ができることを確認した(分割、独立した履歴、Back/Forward、全文書の描画、検索の仮想 buffer、行アンカー、外部更新時の位置の維持)。単体テスト 36 件(PoC の 27 件を引き継ぎ、fixtures のセキュリティ検証文書を使った sanitize のテストなどを追加) |
| M0 | **完了(2026-10-08)** | `core/`(TypeScript、型検査・Prettier・テスト・esbuild)、`app/macos/` と `cli/`(SwiftPM、Swift 6、`swift format`、Swift Testing)、`emacs/`(ERT)、`protocol/`、`fixtures/`(PoC の文書集とコーパス生成)、`scripts/check.sh`、CI の骨組み。`scripts/check.sh` が全体で通り、意図的に壊すと失敗することを確認した。**CI のワークフローは、GitHub に公開する前で、まだ実行していない**(構文のみ確認) |

## 7. PoC の扱い

- PoC のブランチ(`poc/interaction-web`、`poc/swiftui-wkwebview`、`poc/tauri-shell`、`poc/rendering`、`poc/navigation`、`poc/integration`)は、削除せず残す(運用ルール)。
- 本実装は、PoC のコードをそのままマージせず、`main` に新しいコミットとして書く。**コミットメッセージや文書に、元になった PoC のコミットを記録する。**
- 作業ツリーは、PoC ごとの worktree(`../hyperbuf-poc/*`)を引き続き使い、`main` の作業ツリーと分ける。

## 8. 決定事項と、残りの判断

### 合意済み(2026-10-08)

1. **構成(§3)。** `core/`、`protocol/`、`fixtures/` の新設。**`app/` は `app/macos/` とする**(他OS は `app/linux/` などを並べる)。
2. **Web コアは TypeScript。** `tsc` で型検査、esbuild で変換。React は使わない。
3. **Swift のビルドは SwiftPM + スクリプト。** Xcode プロジェクトは、必要になるまで作らない。
4. **CI は M0 で骨組みを入れる。**
5. **ライセンス。** 公開前に確認する。現段階では念頭に置いて進める。**難しい問題があれば、公開・配布を諦めて、個人のツールとして使う。** 依存ライブラリのライセンス一覧は、`core/` と `app/` の依存が固まった時点で作る。
6. **プロダクト名は確定。** GUI は **HyperBuf.app**、CLI は **`hyperbuf`**。表記は「HyperBuf」に統一する(README などの「Hyperbuf(仮称)」を改めた)。下記の名前の確認を参照。
7. **最小の macOS は macOS 14(Sonoma)以上。** 古いものを含めて Apple が保守を続けている世代まで対応する方針。**14 より古い OS への対応は、負担が大きければ行わない**(ユーザー了承)。
8. **CLI の言語は Swift の単一バイナリ。** 追加のライブラリなしで、安全に書けることを重視した。他OS は、そのOS に合う形で書き直す。

### 名前の確認(2026-10-08)

- **Web 検索:** 同名の製品・企業は見つからなかった。近い名前は、C++ の多次元コンテナ `HyperBuffer`(Sidelobe)、Elixir の `Hyperbuffs`、Linux の `hyper_dmabuf`(ドライバ)で、いずれも領域が異なる。
- **GitHub:** 利用者・組織名 `hyperbuf` は空いている(404)。同名のリポジトリが 2 件あるが、いずれも星 0 の個人の小さなもの(`jrey8343/hyperbuf`:ハイパーメディアのフレームワーク、`tbraun96/HyperBuf`:バッファ管理の alpha)。
- **npm:** `hyperbuf` は空いている(404)。
- **Homebrew:** `hyperbuf` の formula・cask は見つからない。
- **ドメイン:** `hyperbuf.com` / `.dev` / `.app` / `.org` / `.io` は、DNS に存在しない(NXDOMAIN)。ただし、登録されていないとは限らない(WHOIS で未確認)。
- **未確認:** 商標(USPTO、日本の J-PlatPat など)は未調査。公開の前に確認する。
- **Bundle ID:** 慣習として、所有するドメインの逆順(例: `dev.hyperbuf.app`)を使う。ドメインを取得するか、別の形にするかを、公開前に決める。PoC は `dev.hyperbuf.poc` を使っている。

### 最小の macOS(合意済みの方針と、提案)

- **方針(合意済み):** 検証機材などの古い macOS でも読めるよう、**Apple が保守を続けているものを、できるだけ古いものまで**サポートする。
- **提案:** 現在の macOS は 26。Apple は公式にサポート期間を公表していないが、**慣行として、最新とその前の 2 世代(26、15、14)に、セキュリティ更新が出ている。** そのため、**macOS 14(Sonoma)以上**を最小とする。新しい世代が出たら、更新が止まった世代を外す。
- 実装上は、14 に無い API を、必要な理由なしに使わない。JavaScript の対象は、macOS 14 の Safari 17(PoC の esbuild の `target: safari17` と同じ)。
- **要確認:** 検証機材の macOS のバージョン。14 より古い場合は、その機材で動かすことの価値と、下げるための実装・保守の負担を比べて、別に判断する。

### CLI の言語(合意済み)

Swift の単一バイナリとする。C も検討した(起動が速く、移植しやすく、ツールチェーンも要らない)が、他OS では IPC の方式・アプリの起動・パスの扱いが異なり、C で書いても、そのまま移植できるわけではない。追加のライブラリなしで安全に書けること(パスとソケットを扱うため、メモリの安全性が重要)を優先した。

### 残りの判断

なし(公開前に、ライセンスと商標、Bundle ID を確認する)。

## 9. 未検証のリスク

- 署名・公証・Hardened Runtime での、WKWebView と WASM(starry-night)の動作。
- GitHub Actions の macOS ランナーで、必要な Xcode・macOS のバージョンが使えるか。
- 別のユーザーからのソケット接続の拒否(`getpeereid`)。
- メモリ使用量(描画バンドルで約 173 MB から約 380〜410 MB へ増加)。後半にまとめて調査する(合意済み)。
- 選択 → 元の位置の対応の精度(強調・リンクをまたぐ選択)。M6 で検証する。
