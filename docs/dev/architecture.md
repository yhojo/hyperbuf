# アーキテクチャ

HyperBuf の構成と、技術選定の決定事項。各部の詳細は、リンク先の文書にある。選定に至った検証は [docs/history/](../history/) の PoC の結果。

## 1. 全体の構成

```
┌─────────────────────────── HyperBuf.app (macOS シェル) ───────────────────────────┐
│  SwiftUI + WKWebView   ファイルアクセス・監視・検索・セッション・ソケット・メニュー │
│          │  hyperbufHost の契約                                                      │
│  ┌───────▼─────────────────────────────────────────────────────────────────────┐   │
│  │ Web コア (core/, TypeScript): buffer / window / frame のモデル、キー、UI、   │   │
│  │ Markdown のレンダリング(unified / remark / rehype)                         │   │
│  └─────────────────────────────────────────────────────────────────────────────┘   │
└───────────────▲────────────────────────────────────────────────────────────────────┘
                │ Unix ドメインソケット(JSON Lines)/ hyperbuf:// URL
        hyperbuf CLI (cli/)      Emacs 連携 (emacs/)
```

| 場所         | 役割                                                                                                           |
| ------------ | -------------------------------------------------------------------------------------------------------------- |
| `core/`      | 共通の Web コア(TypeScript)。操作モデル、キー、コマンド、UI、レンダリング。OS に依存しない                     |
| `app/macos/` | HyperBuf.app。SwiftUI + WKWebView のシェル。`HyperBufKit` に、ファイルアクセス・検索・監視・設定などのロジック |
| `cli/`       | `hyperbuf` コマンド(Swift の単一バイナリ)                                                                      |
| `emacs/`     | Emacs 連携(`hyperbuf.el`、Emacs 29.1 以上)                                                                     |
| `protocol/`  | 連携プロトコルの JSON Schema、共有の例、Swift のライブラリ(型・検証・ソケット)                                 |

## 2. Web コアとシェルの境界

- **Web コアは、シェルに依存しない。** シェルは `window.hyperbufHost` として、ファイルの一覧・読み取り・検索・アクセスの判定・設定・セッションの保存などを提供する。Web コアは、これ以外の方法でシェルの機能を使わない。
- 契約の定義は `core/src/host.ts`(型と説明)。主な役割は次のとおり。

  | 役割           | 内容                                                                                                                         |
  | -------------- | ---------------------------------------------------------------------------------------------------------------------------- |
  | ファイル       | `listDirectory`(1 階層)、`listTree`(再帰の一覧)、`projectRoot`、`readFile`、`watch` / `onFileChanged`(変更の通知)            |
  | 検索           | `search`(全文検索)                                                                                                           |
  | アクセスの判定 | `checkAccess`、確認の承認と記憶(`allow`・`listRemembered`・`forget`)、外部 URL の判定と記憶(`checkUrl`・`rememberSite` など) |
  | 設定           | `getConfig`(キー割り当て、各種の設定、設定の問題)                                                                            |
  | セッション     | `loadSession`、`saveSession`                                                                                                 |
  | フレーム       | `frame`(作成、次のフレームへ、削除)                                                                                          |
  | 外部連携       | 外部からの「開く」要求の受け取り(`onOpen`)、問い合わせへの応答(`onQuery`・`respond`)、編集位置の記録(`markLocation`)         |

- 判断は、できるだけ**シェル側**で行う(ファイルシステムのアクセス判定、外部コマンドの実行、URL を開く判断など)。Web コアの判断は信用しない。
- 他の OS に移植するときは、**その OS に最適なフレームワークでシェルを書き、Web コアを再利用する**。クロスプラットフォームのシェルを共有する方針は採らない(各 OS の微妙なバグに悩まされる経験則による)。

## 3. 技術選定

### 3.1 決定したもの

| 項目                    | 選定                                                                                      | 根拠                                                                                                                                                                                          |
| ----------------------- | ----------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| macOS シェル            | **SwiftUI + WKWebView**                                                                   | macOS 統合(メニュー、ネイティブのウィンドウ、URL スキーム、ソケット)を直接扱える。応答性が同等以上で、ビルドと依存が軽い([poc-interaction-results.md](../history/poc-interaction-results.md)) |
| Markdown のパイプライン | **unified / remark / rehype**、remark-gfm、remark-math、rehype-katex、**rehype-sanitize** | GitHub との表示差が確認されず、セキュリティの前提を満たし、性能に問題がない([poc-rendering-results.md](../history/poc-rendering-results.md))                                                  |
| 表示のスタイル          | **github-markdown-css**。GitHub との差は小さな変換で吸収する(例: 通貨表記の `$`)          | GitHub 互換の見た目                                                                                                                                                                           |
| 数式                    | **KaTeX**。`\_` の解釈(Marked 2 との互換)は設定 `mathUnescapeUnderscore` で切り替える     | 要件を満たす。MathJax は必要になるまで採用しない                                                                                                                                              |
| 図                      | **Mermaid**(遅延ロード、`securityLevel: strict`、レイアウトは dagre に固定)               | `elkjs`(EPL-2.0)は、ライセンスの理由で外している([license-options.md](../history/license-options.md))                                                                                         |
| シンタックスハイライト  | **starry-night**                                                                          | GitHub と同じ文法。Shiki と比べて、速度・出力サイズ・GitHub 互換で優位。対応言語は [syntax-highlighting.md](../user/syntax-highlighting.md)                                                   |
| 全文検索                | **Swift の自前実装**(`TreeSearch`)。`host.search` の契約でエンジンを差し替えられる        | 正規表現や除外規則が必要になった時点で ripgrep を再評価する([poc-navigation-results.md](../history/poc-navigation-results.md))                                                                |
| ファイル監視            | **kqueue**(`DispatchSource`。表示中のファイルと親ディレクトリ、非再帰)                    | ポーリングは削除を検知できず、ファイル数に比例して重い。再帰の FSEvents は雑音が多い([buffer-model.md](buffer-model.md) §8)                                                                   |
| 連携                    | **Unix ドメインソケット**(JSON Lines)+ `hyperbuf://` URL                                  | [integration-protocol.md](integration-protocol.md)                                                                                                                                            |
| ライセンス              | 本体 Apache-2.0、`emacs/` は GPL-3.0-or-later                                             | [license-options.md](../history/license-options.md)                                                                                                                                           |

### 3.2 未評価の候補

次は、必要になった時点で評価する。外部コマンドが絡むものは、権限の境界を先に決める。

- Graphviz、PlantUML、WaveDrom、D2(図表の候補)。
- MathJax(KaTeX で要件を満たしているため、比較していない)。
- 全文検索での ripgrep(正規表現・除外規則が必要になったとき)。
- 画像(SVG を含む)の拡大・縮小・パン操作。

## 4. レンダリングとセキュリティ

信頼しない入力として扱う方針の実現は、次のとおり。

- **HTML:** rehype-sanitize で無害化する。id には接頭辞 `user-content-` を付ける(外してはならない。アプリの DOM との衝突を防ぐ)。スクリプトの実行は許さない。
- **画像:** `<img>` だけを許す。読み込みは、スキームハンドラ(`SchemeHandler`)が、**読み込みのたびにアクセスを判定する**([file-access.md](file-access.md) §5)。
- **CSP:** `ContentSecurityPolicy` で、外部への通信を許さない。starry-night の WASM は同梱し、既定の CDN からの取得は無効にしている。
- **図:** Mermaid は strict モードで描画する。図のエラーは、文書全体を止めず、その場所に表示する。
- **外部リンク:** ブラウザで開く判断は、シェルが行う([configuration.md](../user/configuration.md))。
- **外部コマンド:** 実行は、利用者が設定した固定のコマンドだけ([edit-location.md](edit-location.md) §7)。

## 5. 主要な設計の文書

- 操作モデル: [interaction-model.md](interaction-model.md)
- バッファと frame: [buffer-model.md](buffer-model.md)
- アクセス判定: [file-access.md](file-access.md)
- セッション: [session-restore.md](session-restore.md)
- 連携: [integration-protocol.md](integration-protocol.md)、[edit-location.md](edit-location.md)
- UI の流儀: [ui-conventions.md](ui-conventions.md)
- 配布: [distribution.md](distribution.md)、[release.md](release.md)
