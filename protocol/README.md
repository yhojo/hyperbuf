# protocol/

HyperBuf の連携プロトコル(Unix ドメインソケット・URL スキーム)の、機械可読な定義と、適合テスト用のデータ。
仕様の本文は [`docs/dev/integration-protocol.md`](../docs/dev/integration-protocol.md)(逆方向の編集位置の連携は [`docs/dev/edit-location.md`](../docs/dev/edit-location.md))。

| 場所        | 内容                                                                                                                                                                                                    |
| ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `schema/`   | 要求・応答・位置(`location`: エディタ連携)の JSON Schema(2020-12)                                                                                                                                       |
| `examples/` | **共有の例。** 同じ例を、Swift のライブラリ・`cli/`・`emacs/`・JSON Schema のテストが使い、実装どうしの食い違いを検出する(下の表)                                                                       |
| `swift/`    | アプリ(サーバー)と `cli/`(クライアント)が共有する Swift のライブラリ。`HyperBufProtocol`(型、`open` の検証、URL、JSON Lines の切り出し、ソケットのパス)と `HyperBufIPC`(`SocketServer`・`SocketClient`) |
| `test/`     | JSON Schema と `examples/` が食い違っていないか、文書の表がスキーマと一致しているかの検査(Node + ajv)                                                                                                   |

## 共有の例

| ファイル               | 内容                                                                        | 使うもの                                                     |
| ---------------------- | --------------------------------------------------------------------------- | ------------------------------------------------------------ |
| `open-validation.json` | `open` 要求の検証(受け入れる・拒否する)                                     | JSON Schema のテスト、`swift/`(`HyperBufProtocol`)、`emacs/` |
| `url.json`             | 要求と `hyperbuf://` URL の相互変換                                         | JSON Schema のテスト、`swift/`(`HyperBufProtocol`)、`emacs/` |
| `framing.json`         | JSON Lines の切り出し(分割して届く入力、1 回に複数行、空行など)             | `swift/`(`HyperBufProtocol`)                                 |
| `cli-args.json`        | `hyperbuf` CLI の引数の解釈                                                 | `cli/`                                                       |
| `location.json`        | 位置のペイロード(`get-location` の `result.location`)                       | JSON Schema のテスト、`swift/`(`HyperBufProtocol`)           |
| `location-check.json`  | エディタ側の照合の規則([edit-location.md](../docs/dev/edit-location.md) §6) | JSON Schema のテスト、`emacs/`                               |

例を壊すと、使っているすべてのテストが失敗する。

## 変更するとき

新しい操作・フィールド・エラーコードを足すときは、次を同時に更新する。

1. `schema/`(正本)。
2. `examples/`(受け入れる例と拒否する例)。
3. `docs/dev/integration-protocol.md`(操作とエラーコードの表。`test/docs.test.mjs` がスキーマとの一致を検査する)。位置のペイロードなら `docs/dev/edit-location.md`。
4. 実装: `swift/`、`cli/`、`emacs/`(`emacs/` は、検証の規則を自前で持つ)。

## 検査

```bash
scripts/check.sh protocol     # Node(整形・スキーマと例・文書の表)と Swift(protocol/swift)
```
