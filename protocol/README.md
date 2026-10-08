# protocol/

HyperBuf の連携プロトコル(Unix ドメインソケット・URL スキーム)の、機械可読な定義と、適合テスト用のデータ。
仕様の本文は [`docs/integration-protocol.md`](../docs/integration-protocol.md)。

| 場所        | 内容                                                                                                                                      |
| ----------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `schema/`   | 要求・応答の JSON Schema(2020-12)                                                                                                         |
| `examples/` | **共有の例。** `open` の検証、URL の変換、JSON Lines の切り出し。Swift のライブラリ・`cli/`・`emacs/` が、同じ例で適合テストを行う        |
| `swift/`    | アプリ(サーバー)と `cli/`(クライアント)が共有する Swift のライブラリ `HyperBufProtocol`(型、`open` の検証、URL、切り出し、ソケットのパス) |
| `test/`     | JSON Schema が、`examples/` と食い違っていないかの検査(Node + ajv)                                                                        |

新しい操作・フィールドを足すときは、`schema/`・`examples/`・`docs/integration-protocol.md` を同時に更新する。
検査: `scripts/check.sh protocol`
