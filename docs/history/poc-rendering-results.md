# Rendering PoC 結果

> **当時の記録(Rendering PoC)。** 書き換えない。現行の構成とセキュリティは [architecture.md](../dev/architecture.md) §3〜4。

状態: **結果報告・決定済み** — 実施日 2026-10-08。ブランチ: `poc/rendering`(`78860be`、`8f3cf5a`)。§7 の構成を採用(ユーザー合意、2026-10-08)。

## 1. 目的と範囲

README の「High-fidelity rendering」の要件(GFM、SVG・画像、数式、Mermaid、シンタックスハイライト、図表エラーの局所化、セキュリティ)を、決定済みのシェル(SwiftUI + WKWebView、`poc-interaction-results.md`)の上で検証した。

構成(Web コア `poc/web`):

| 役割 | 使ったもの |
| --- | --- |
| Markdown → HTML | unified / remark-parse / remark-gfm / remark-math / remark-rehype / rehype-raw / rehype-stringify |
| サニタイズ | rehype-sanitize(GitHub 準拠の既定スキーマ) |
| 数式 | KaTeX(rehype-katex) |
| シンタックスハイライト | starry-night(GitHub と同じ文法・クラス名)。Shiki と比較 |
| 図 | Mermaid(`securityLevel: strict`、動的 import で遅延ロード) |
| 見た目 | github-markdown-css(ライト/ダーク自動)、starry-night のスタイル |
| バンドル | esbuild(コード分割) |

検証文書は `poc/sample/rendering/` に機能別に用意した(GFM、コード、数式、Mermaid、画像と SVG、HTML とセキュリティ、大きな文書)。

## 2. 結果の要約

- **表示の正しさ:** ユーザーが GitHub の表示と見比べて確認し、違和感・気づきなし(2026-10-08)。
- **セキュリティ:** 不信任な HTML・SVG を含む文書で、`alert` の発火、CSP 違反、実行時エラーはいずれも 0 件。アプリの DOM との `id` の衝突も起きなかった。
- **エラーの局所化:** Mermaid の構文エラーと不正な数式は、その場にエラーを表示するだけで、文書全体は止まらなかった。
- **性能:** 通常の文書は描画 約 7〜23 ms。約 2800 行の大きな文書でも描画 135 ms。いずれも debug ビルド。

## 3. 検証結果の詳細

自動チェック(WKWebView 上で全文書を開いて DOM を集計)と、ユニットテスト 22 件(Node)による。

| 項目 | 結果 |
| --- | --- |
| GFM(表、タスクリスト、取り消し線、自動リンク、脚注、折りたたみ) | 描画された |
| GitHub アラート(`> [!NOTE]` 等 5 種) | 描画された(自前の変換。sanitize の後段) |
| コードのハイライト | 13 言語以上で着色(Python、JS、TS、Swift、Rust、Go、Emacs Lisp、Shell、diff、JSON、YAML、HTML、CSS)。言語指定なし・未知の言語は素通し |
| 数式 | インライン・ブロック・行列・日本語を含む式が描画された。不正な式はエラー表示 |
| Mermaid | flowchart、sequence、class、state、gantt、日本語ラベルが描画された(7 図中 6、残り 1 は意図した構文エラー) |
| ローカル画像・SVG | `<img>` 経由で表示された |
| 悪意のある SVG(script、onload) | `<img>` 内では実行されず無害 |
| 外部画像 | 読み込まず、代替表示にした |
| script、イベントハンドラ、`javascript:`、iframe、object、form、`<style>`、`<meta refresh>`、`<base>` | すべて除去された |

## 4. 性能(debug ビルド、WKWebView)

| 文書 | 描画 | 開いてから表示完了まで |
| --- | --- | --- |
| GFM(短い) | 23 ms | 258 ms |
| コード(約 20 ブロック) | 141 ms | 345 ms |
| 数式 | 20 ms | 242 ms |
| Mermaid(7 図) | 3 ms + 図 240 ms(初回に Mermaid を読み込む) | 545 ms |
| 画像と SVG | 7 ms | 214 ms |
| HTML とセキュリティ | 9 ms | 215 ms |
| 大きな文書(約 2800 行、表 100、数式 100、コード 5600 トークン) | 135 ms | 385 ms |

「開いてから表示完了まで」には、ファイル読み込み、DOM 反映、レイアウト、Mermaid の待機、計測用の待ち時間(約 200 ms の固定待ち)が含まれ、実際の体感より大きめに出る。

### バンドルサイズ

| 項目 | サイズ |
| --- | --- |
| 起動時に読む JS(`app.js`、starry-night の文法・KaTeX・unified 群を含む) | 約 1.95 MB |
| CSS | 約 58 KB |
| Oniguruma の WASM(starry-night 用) | 約 462 KB |
| KaTeX のフォント(woff2、使用時に読み込み) | 約 296 KB |
| Mermaid と図種別のチャンク(遅延ロード、図がある文書だけ) | 約 5 MB(最大の ELK チャンクが約 1.5 MB) |

### シンタックスハイライトの比較(Node 上、114 ブロック・約 30K 文字)

| 候補 | 初期化 | 全ブロック | 出力 | バンドル |
| --- | --- | --- | --- | --- |
| starry-night(common 文法) | 20 ms | 28 ms | 179 KB | JS 約 1.3 MB + WASM 約 0.46 MB |
| Shiki(Oniguruma) | 31 ms | 48 ms | 348 KB | — |
| Shiki(JS 正規表現エンジン、13 言語) | 2 ms | 50 ms | 348 KB | JS 約 1.6 MB(WASM なし) |

starry-night は速く、出力が小さい。GitHub と同じ文法・クラス名で、互換性の面でも有利。Shiki の出力が大きいのは、色をインラインの `style` で出すため。

## 5. 見つけた問題と対応

1. **starry-night が、実行時に外部 CDN(esm.sh)から WASM を取得する。** CSP が遮断してアプリが起動しなかったことで発覚した。`getOnigurumaUrlFetch` で同梱した WASM を指すようにして、外部アクセスをなくした。依存ライブラリの既定動作が local first に反しうることを示す事例。CSP による遮断が、この種の問題の検出に有効だった。
2. **脚注のリンクが切れる。** remark-rehype と rehype-sanitize が、それぞれ id に `user-content-` を付けて二重になった。remark-rehype 側の接頭辞を空にし、アプリ側でリンク先を探すときに接頭辞を補う(GitHub と同じ方式)ことで解消した。
3. **`$5 から $10` が数式になる。** GitHub は、閉じの `$` の直後が数字、または内側が空白で始まる/終わるときは数式にしない。remark-math にはこの規則がないため、自前の変換で揃えた。
4. **見出しの id は GitHub 方式(github-slugger)で付くため、正規表現で作る見出し一覧とずれる。** 見出しジャンプは、描画後の DOM から作る。見出し構造は構文木または DOM から得る必要がある。
5. **raw HTML の `id` / `name` がアプリの DOM と衝突しうる。** sanitize の接頭辞(`user-content-`)で防げる。この接頭辞は外してはならない。
6. **Mermaid の描画で高さが変わり、アンカー位置がずれる。** 描画後に、読み手が動かしていなければ位置を取り直す。外部更新時の位置維持も、この取り直しの対象になる。
7. **CSP の緩和が 2 点必要だった。** WASM の実行に `'wasm-unsafe-eval'`、WASM の取得に `connect-src hyperbuf:`(自アプリのスキームのみ)。外部への通信は許可していない。

## 6. セキュリティの設計(PoC で確認した構成)

- raw HTML は構文木にしたうえで GitHub 準拠のスキーマに通す。KaTeX・ハイライト・画像 URL の書き換え・アラートは、sanitize の後段に置く。
- 画像は `<img>` だけで扱う(SVG を直接埋め込まない)。プロジェクトの画像は、`hyperbuf://project/*` を経由して返し、`default-src 'none'` の CSP を付ける。ルート外へのアクセス、画像以外の拡張子は拒否する。
- 外部画像は読み込まない。CSP の `img-src` も自アプリのスキームのみ。
- Mermaid は `securityLevel: strict`。
- 見出し・脚注の id には接頭辞を付け、アプリの DOM と分離する。

## 7. 提案と判断すべき点

**決定(2026-10-08、ユーザー合意): この構成(unified / remark / rehype、remark-gfm、remark-math + KaTeX、starry-night、Mermaid、rehype-sanitize、github-markdown-css)を、レンダリング層として採用する。** 理由は、GitHub との表示差が確認されず、セキュリティの前提を満たし、性能にも問題がないため。

残された点:
- **起動時に読む JS が約 1.95 MB。** 現時点で体感の問題は報告されていないため、このままとする。気になる場合は、starry-night の文法を絞る、言語を遅延ロードするなどの余地がある。
- **Mermaid が約 5 MB。** 遅延ロードなので普段は影響しない。必要な図種別だけに絞る選択肢もある。
- **README に挙げた他の候補(MathJax、Graphviz、PlantUML、WaveDrom、D2)は未評価。** MathJax は KaTeX で要件を満たしたため比較していない。それ以外は、ローカルで動く実装や外部コマンド実行の権限設計が絡むため、必要になった時点で別途扱う(README のセキュリティ方針に従い、権限境界を先に決める)。

## 8. 未検証・次の課題

- release ビルドでの性能。
- 数百ファイル規模のプロジェクトでの、一覧・検索・切替の応答性(Project navigation PoC)。
- 外部更新で、Mermaid や大きな画像を含む文書の位置維持の精度。
- 画像の拡大・縮小・パン操作(README の要件)。
- 図表プラグインの権限境界(Graphviz 等の外部コマンドを使う場合)。
- 実際の GitHub 文書(README など)の大規模な比較。今回の確認は、用意した検証文書集による。
- アクセシビリティ、印刷、テキスト選択とコピー(別途検討としたもの)。
