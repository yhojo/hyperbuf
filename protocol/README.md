# protocol/

HyperBuf の連携プロトコル(URL スキーム・Unix ドメインソケット)の、機械可読な定義と、適合テスト用のデータを置く。
仕様の本文は [`docs/integration-protocol.md`](../docs/integration-protocol.md)。

M4 で、次を置く予定。

- `schema/` — 要求・応答の JSON Schema
- `examples/` — 要求と、期待する応答の組(Swift のサーバー、`cli/`、`emacs/` が同じ例で適合テストを行う)
