# emacs/

Emacs から、HyperBuf(macOS の Markdown ビューア)に、ファイルと行を指定して文書を開かせる。
仕様: [`docs/integration-protocol.md`](../docs/integration-protocol.md)。Emacs 29.1 以上。

## 使い方

```elisp
(add-to-list 'load-path "/path/to/hyperbuf/emacs")
(require 'hyperbuf)

;; キーの例(割り当ては、お好みで)
(global-set-key (kbd "C-c h o") #'hyperbuf-open-file)
(global-set-key (kbd "C-c h O") #'hyperbuf-open-other-window)
(global-set-key (kbd "C-c h p") #'hyperbuf-open-project-file)
```

| コマンド | 動作 |
| --- | --- |
| `hyperbuf-open-file` | 現在のバッファのファイルを、**現在行**つきで HyperBuf に開く |
| `hyperbuf-open-other-window` | 同じものを、HyperBuf の別の window(右に分割)に開く |
| `hyperbuf-open-project-file` | プロジェクトの Markdown を選んで開く |
| `hyperbuf-open` | Lisp から。`(hyperbuf-open FILE &optional LINE ANCHOR TARGET WAIT)` |

プレフィックス引数(`C-u`)つきなら、アプリ内の確認(プロジェクトの外のファイルを開くか、など)を、長く待つ。
ビューアは、ディスク上のファイルを読むので、未保存の変更があるときは、開く前に保存するかを尋ねる(`hyperbuf-save-before-open`)。

## 設定

| 変数 | 既定 | 意味 |
| --- | --- | --- |
| `hyperbuf-transport` | `socket` | `socket`: アプリのソケットに直接接続。`cli`: `hyperbuf` コマンドを呼ぶ |
| `hyperbuf-executable` | `"hyperbuf"` | `cli` のときのコマンド |
| `hyperbuf-launch-if-needed` | `t` | アプリが起動していなければ、開く要求の `hyperbuf://` URL で起動する。`nil` なら通知して終わる |
| `hyperbuf-app` | `nil` | 起動する `.app` のパス(開発用) |
| `hyperbuf-default-target` | `nil` | 表示先の既定(`"split-right"` など) |
| `hyperbuf-timeout` / `hyperbuf-wait-timeout` | 3 / 60 | 確認を待つ秒数 |
| `hyperbuf-socket-path` | `nil` | ソケットのパス(環境変数 `HYPERBUF_SOCKET_PATH`、なければ標準の場所) |

## 制限

- リモートのファイル(TRAMP)は開けない(ビューアは、手元のファイルだけを読む)。
- アプリが起動していないとき、アプリを起動して要求を渡すが、結果は、アプリの画面に出る(Emacs には返らない)。
- 編集位置の連携(ビューアから Emacs へ、`hyperbuf-visit-location`)は、M6 で実装する。

## 開発

```bash
scripts/check.sh emacs     # バイトコンパイル(警告をエラー扱い)と ERT
```

テストは、`protocol/examples/`(`open-validation.json`、`url.json`)の共有の例を、Swift と同じく検証する。
