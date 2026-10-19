<!-- 自動生成: core/scripts/licenses.mjs。直接編集しない(`npm run licenses` で再生成する。`npm run check` が、最新かを検査する)。アプリに同梱する全文つきの `THIRD-PARTY-NOTICES.txt` は、`app/macos/scripts/make-app.sh` が、同じスクリプト(`notices`)で生成する -->

# サードパーティのライセンス

HyperBuf が同梱している、サードパーティのソフトウェアのライセンスの一覧です。著作権表示とライセンスの全文は、アプリメニューの `Show Third-Party Licenses` で開く `THIRD-PARTY-NOTICES.txt`(アプリに同梱)で読めます。

対象は、Web コア(`core/dist`)のバンドルに実際に入るものです。Swift 側(アプリ・CLI・プロトコル)は、サードパーティの依存を持ちません。

## 集計(npm のパッケージ 149 件)

| ライセンス | 件数 |
| --- | --- |
| MIT | 116 |
| ISC | 22 |
| Apache-2.0 | 5 |
| BSD-3-Clause | 5 |
| BSD-2-Clause | 1 |

- **MIT / ISC / BSD / Apache-2.0** など許容的なライセンスは、著作権表示とライセンス文を、配布物に含めれば足りる。
- **dompurify**(Apache-2.0): Dual-licensed (MPL-2.0 OR Apache-2.0). Apache-2.0 is chosen (the user may choose).
- **khroma**(MIT): package.json has no license field, but the bundled license file is MIT.
- **rehype-katex**(MIT): The package has no license file. The standard MIT text is supplied from the license in package.json, the author, and "MIT © Junyoung Choi" in the README (no year is written because the package does not state one).
- **remark-math**(MIT): The package has no license file. The standard MIT text is supplied from the license in package.json, the author, and "MIT © Junyoung Choi" in the README (no year is written because the package does not state one).

## starry-night の文法(バンドルに入った 89 件)

| ライセンス(SPDX) | 件数 |
| --- | --- |
| mit | 50 |
| permissive | 22 |
| isc | 6 |
| apache-2.0 | 5 |
| bsd-3-clause | 3 |
| bsd-2-clause | 1 |
| mpl-2.0 | 1 |

文法ごとの出所とライセンス文は、`THIRD-PARTY-NOTICES` に入る(starry-night の `notice` から、バンドルに入ったものだけを取り出す)。コピーレフト(GPL 系)のものは、ない。

## その他の同梱物

- **KaTeX fonts**(OFL-1.1): Follows the license notice embedded in the font files (SIL Open Font License 1.1). The fonts are not sold on their own and are not modified (the Reserved Font Name restriction applies only to modified versions).

## パッケージの一覧

| パッケージ | バージョン | ライセンス |
| --- | --- | --- |
| @braintree/sanitize-url | 7.1.2 | MIT |
| @chevrotain/gast | 13.2.0 | Apache-2.0 |
| @chevrotain/regexp-to-ast | 13.2.0 | Apache-2.0 |
| @chevrotain/utils | 13.2.0 | Apache-2.0 |
| @iconify/utils | 3.1.7 | MIT |
| @mermaid-js/parser | 2.0.1 | MIT |
| @ungap/structured-clone | 1.4.0 | ISC |
| @upsetjs/venn.js | 2.0.0 | MIT |
| @wooorm/starry-night | 3.11.0 | MIT |
| bail | 2.0.2 | MIT |
| ccount | 2.0.1 | MIT |
| character-entities-html4 | 2.1.0 | MIT |
| character-entities-legacy | 3.0.0 | MIT |
| chevrotain | 13.2.0 | Apache-2.0 |
| comma-separated-tokens | 2.0.3 | MIT |
| cose-base | 2.2.0 | MIT |
| cose-base | 1.0.3 | MIT |
| cytoscape | 3.34.3 | MIT |
| cytoscape-cose-bilkent | 4.1.0 | MIT |
| cytoscape-fcose | 2.2.0 | MIT |
| d3-array | 2.12.1 | BSD-3-Clause |
| d3-array | 3.2.4 | ISC |
| d3-axis | 3.0.0 | ISC |
| d3-brush | 3.0.0 | ISC |
| d3-color | 3.1.0 | ISC |
| d3-dispatch | 3.0.1 | ISC |
| d3-ease | 3.0.1 | BSD-3-Clause |
| d3-format | 3.1.2 | ISC |
| d3-hierarchy | 3.1.2 | ISC |
| d3-interpolate | 3.0.1 | ISC |
| d3-path | 1.0.9 | BSD-3-Clause |
| d3-path | 3.1.0 | ISC |
| d3-sankey | 0.12.3 | BSD-3-Clause |
| d3-scale | 4.0.2 | ISC |
| d3-scale-chromatic | 3.1.0 | ISC |
| d3-selection | 3.0.0 | ISC |
| d3-shape | 1.3.7 | BSD-3-Clause |
| d3-shape | 3.2.0 | ISC |
| d3-time | 3.1.0 | ISC |
| d3-time-format | 4.1.0 | ISC |
| d3-timer | 3.0.1 | ISC |
| d3-transition | 3.0.1 | ISC |
| d3-zoom | 3.0.0 | ISC |
| dagre-d3-es | 7.0.14 | MIT |
| dayjs | 1.11.23 | MIT |
| decode-named-character-reference | 1.3.0 | MIT |
| dompurify | 3.4.16 | Apache-2.0 |
| entities | 6.0.1 | BSD-2-Clause |
| es-toolkit | 1.52.0 | MIT |
| escape-string-regexp | 5.0.0 | MIT |
| extend | 3.0.2 | MIT |
| github-markdown-css | 5.9.0 | MIT |
| github-slugger | 2.0.0 | ISC |
| hast-util-from-dom | 5.0.1 | ISC |
| hast-util-from-html-isomorphic | 2.0.0 | MIT |
| hast-util-from-parse5 | 8.0.3 | MIT |
| hast-util-is-element | 3.0.0 | MIT |
| hast-util-parse-selector | 4.0.0 | MIT |
| hast-util-raw | 9.1.0 | MIT |
| hast-util-sanitize | 5.0.2 | MIT |
| hast-util-to-html | 9.0.5 | MIT |
| hast-util-to-parse5 | 8.0.1 | MIT |
| hast-util-to-string | 3.0.1 | MIT |
| hast-util-to-text | 4.0.2 | MIT |
| hast-util-whitespace | 3.0.0 | MIT |
| hastscript | 9.0.1 | MIT |
| html-void-elements | 3.0.0 | MIT |
| internmap | 2.0.3 | ISC |
| is-plain-obj | 4.1.0 | MIT |
| katex | 0.16.47 | MIT |
| khroma | 2.1.0 | MIT |
| layout-base | 2.0.1 | MIT |
| layout-base | 1.0.2 | MIT |
| lodash-es | 4.18.1 | MIT |
| longest-streak | 3.1.0 | MIT |
| markdown-table | 3.0.4 | MIT |
| marked | 16.4.2 | MIT |
| mdast-util-find-and-replace | 3.0.3 | MIT |
| mdast-util-from-markdown | 2.1.0 | MIT |
| mdast-util-gfm | 3.1.0 | MIT |
| mdast-util-gfm-autolink-literal | 2.0.1 | MIT |
| mdast-util-gfm-footnote | 2.1.0 | MIT |
| mdast-util-gfm-strikethrough | 2.0.1 | MIT |
| mdast-util-gfm-table | 2.0.0 | MIT |
| mdast-util-gfm-task-list-item | 2.0.0 | MIT |
| mdast-util-math | 3.0.0 | MIT |
| mdast-util-phrasing | 4.1.0 | MIT |
| mdast-util-to-hast | 13.2.1 | MIT |
| mdast-util-to-markdown | 2.2.0 | MIT |
| mdast-util-to-string | 4.0.0 | MIT |
| mermaid | 12.1.0 | MIT |
| micromark | 4.0.3 | MIT |
| micromark-core-commonmark | 2.0.4 | MIT |
| micromark-extension-gfm | 3.0.0 | MIT |
| micromark-extension-gfm-autolink-literal | 2.1.0 | MIT |
| micromark-extension-gfm-footnote | 2.1.0 | MIT |
| micromark-extension-gfm-strikethrough | 2.1.0 | MIT |
| micromark-extension-gfm-table | 2.1.2 | MIT |
| micromark-extension-gfm-task-list-item | 2.1.0 | MIT |
| micromark-extension-math | 3.1.0 | MIT |
| micromark-factory-destination | 2.0.1 | MIT |
| micromark-factory-label | 2.0.1 | MIT |
| micromark-factory-space | 2.1.0 | MIT |
| micromark-factory-title | 2.0.1 | MIT |
| micromark-factory-whitespace | 2.0.1 | MIT |
| micromark-util-character | 2.1.1 | MIT |
| micromark-util-chunked | 2.0.1 | MIT |
| micromark-util-classify-character | 2.0.1 | MIT |
| micromark-util-combine-extensions | 2.0.1 | MIT |
| micromark-util-decode-numeric-character-reference | 2.0.2 | MIT |
| micromark-util-decode-string | 2.0.1 | MIT |
| micromark-util-edit-map | 1.0.0 | MIT |
| micromark-util-html-tag-name | 2.0.1 | MIT |
| micromark-util-normalize-identifier | 2.0.1 | MIT |
| micromark-util-resolve-all | 2.0.1 | MIT |
| micromark-util-sanitize-uri | 2.0.1 | MIT |
| micromark-util-subtokenize | 2.1.0 | MIT |
| parse5 | 7.3.0 | MIT |
| property-information | 7.2.0 | MIT |
| rehype-katex | 7.0.1 | MIT |
| rehype-raw | 7.0.0 | MIT |
| rehype-sanitize | 6.0.0 | MIT |
| rehype-stringify | 10.0.1 | MIT |
| remark-gfm | 4.0.1 | MIT |
| remark-math | 6.0.0 | MIT |
| remark-parse | 11.0.0 | MIT |
| remark-rehype | 11.1.2 | MIT |
| roughjs | 4.6.6 | MIT |
| space-separated-tokens | 2.0.2 | MIT |
| stringify-entities | 4.0.4 | MIT |
| stylis | 4.4.0 | MIT |
| trim-lines | 3.0.1 | MIT |
| trough | 2.2.0 | MIT |
| ts-dedent | 2.3.0 | MIT |
| unified | 11.0.5 | MIT |
| unist-util-find-after | 5.0.0 | MIT |
| unist-util-is | 6.0.1 | MIT |
| unist-util-position | 5.0.0 | MIT |
| unist-util-stringify-position | 4.0.0 | MIT |
| unist-util-visit | 5.1.0 | MIT |
| unist-util-visit-parents | 6.0.2 | MIT |
| uuid | 14.0.2 | MIT |
| vfile | 6.0.3 | MIT |
| vfile-location | 5.0.3 | MIT |
| vfile-message | 4.0.3 | MIT |
| vscode-oniguruma | 2.0.1 | MIT |
| vscode-textmate | 9.3.2 | MIT |
| web-namespaces | 2.0.1 | MIT |
| zwitch | 2.0.4 | MIT |
