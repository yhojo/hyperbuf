# 開発・テスト用の環境変数

テストが利用者の実際の状態(設定・ソケット・記憶したパス・セッション)を使わないように、保存先などを環境変数で差し替える。ここに一覧を置く。

利用者が書く設定(`config.json`)は [configuration.md](../user/configuration.md)。

## 1. デバッグビルドだけで有効なもの

リリースビルドでは、読まない(利用者の環境変数で、保存先を差し替えられないようにするため)。

| 環境変数                 | 差し替えるもの・動作                                                                                                                  |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------- |
| `HYPERBUF_CONFIG`        | 設定ファイル(`config.json`)の場所                                                                                                     |
| `HYPERBUF_SOCKET_PATH`   | アプリのソケットの場所                                                                                                                |
| `HYPERBUF_TRUSTED_ROOTS` | 記憶したパスの保存先(`trusted-roots.json`。[file-access.md](file-access.md) §4)                                                       |
| `HYPERBUF_TRUSTED_SITES` | 記憶したサイトの保存先(`trusted-sites.json`)                                                                                          |
| `HYPERBUF_SESSION_DIR`   | セッションの保存先(`session.json` を置くディレクトリ。[session-restore.md](session-restore.md))                                       |
| `HYPERBUF_TEST_LOG`      | Web コアの診断ログを、このファイルに追記する                                                                                          |
| `HYPERBUF_TEST_OPEN_LOG` | ブラウザで開くはずだった URL を、実際には開かず、このファイルに追記する                                                               |
| `HYPERBUF_TEST_COMMANDS` | このディレクトリに置かれた `N.js` を、WebView の中で順に実行し、結果を `N.result` に書く(`scripts/integration-test-ipc.sh` が使う)    |
| `HYPERBUF_TEST_SCRIPT`   | 起動後に、WebView の中でこの JavaScript を実行し、`RESULT: …` を出力する。スクリプトは、解決する必要がある(保留の Promise は返さない) |

## 2. すべてのビルドで有効なもの

| 環境変数               | 対象       | 意味                                                                                                                      |
| ---------------------- | ---------- | ------------------------------------------------------------------------------------------------------------------------- |
| `HYPERBUF_WEB_ROOT`    | アプリ     | Web コアの読み込み元。優先順は、この環境変数、アプリのバンドル(`Contents/Resources/web`)、(デバッグビルドのみ)`core/dist` |
| `HYPERBUF_SOCKET_PATH` | CLI・Emacs | 接続するソケットの場所(Emacs は、`hyperbuf-socket-path` が nil のとき)。アプリ側の差し替えは、デバッグビルドのみ(§1)      |
| `HYPERBUF_APP`         | CLI        | 起動する `.app` のパス。指定がなければ、URL スキームに登録されたアプリを起動する                                          |

## 3. ビルド・リリースのスクリプト

| 環境変数                  | 対象                        | 意味                                              |
| ------------------------- | --------------------------- | ------------------------------------------------- |
| `HYPERBUF_ICON`           | `make-app.sh`、`release.sh` | アプリのアイコン(`.icns`)を差し替える             |
| `HYPERBUF_SIGN_IDENTITY`  | `release.sh`                | 署名に使う証明書(「Developer ID Application: …」) |
| `HYPERBUF_NOTARY_PROFILE` | `release.sh`                | 公証の認証情報の保存名                            |
| `HYPERBUF_RELEASE_DIR`    | `release.sh`                | 成果物の置き場所(既定は `dist/release`)           |

手順の全体は [release.md](release.md)。

## 4. 変えたときの注意

- 一覧は、コードの読み取り箇所(`ProcessInfo.processInfo.environment[...]`、`getenv`、シェルスクリプトの `$HYPERBUF_…`)と合わせる。新しい環境変数を足したら、この表も直す。
