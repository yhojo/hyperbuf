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
| `hyperbuf-visit-location` | ビューアで「Emacs で編集」と指した位置へ移動する(照合つき。下記) |
| `hyperbuf-edit-here` | 同じものに加えて、Emacs のフレームを前面に出す(`emacsclient` から呼ぶ用) |

プレフィックス引数(`C-u`)つきなら、アプリ内の確認(警告パスのファイルを開くか、など)を、長く待つ。
ビューアは、ディスク上のファイルを読むので、未保存の変更があるときは、開く前に保存するかを尋ねる(`hyperbuf-save-before-open`)。

## ビューアから、編集位置へ(「Emacs で編集」)

ビューアで、直したい文字列を選択して、右クリックメニューの **「Emacs で編集」**(または、ビューアで `C-c e`)を選ぶ。
Emacs で `M-x hyperbuf-visit-location`(または、ビューアが、設定した `emacsclient` で `hyperbuf-edit-here` を呼び出す)と、その位置へ移動する。

**誤った場所を、黙って編集させない**ために、移動の前に、必ず照合する。

| 照合 | 失敗したとき |
| --- | --- |
| ファイルが、ビューアが描画した版と同じか(SHA-256) | 移動しない。「ビューアで見ている内容と、編集する内容が食い違います」 |
| その位置の文字列と前後の文脈が、ビューアが指していたものと同じか(未保存の編集でずれていても検出) | 移動しない。食い違いの詳細を `*hyperbuf-mismatch*` に出す |

照合に失敗したときは、**続行する手段はない**(何かが根本的におかしいことに、気づいていない可能性が高いため)。
成功したら、範囲を一時的に強調し、ビューアが指していた文字列を、エコー領域に出す。同じ文言が複数あって位置が決められないときは、
ブロックの先頭へ移動し、「位置が曖昧なため、ブロック全体を示しています」と知らせる(推測では、移動しない)。

ビューアから Emacs を呼び出すには、`~/Library/Application Support/HyperBuf/config.json` に、固定のコマンドを書く
(文書の内容・位置は、引数に含まれない。詳細は `docs/integration-protocol.md` §15)。

```json
{
  "editorName": "Emacs",
  "editorCommand": ["/opt/homebrew/bin/emacsclient", "-n", "-e", "(hyperbuf-edit-here)"]
}
```

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
- UTF-8 以外の文字コードのファイルは、ビューアの照合が合わず、移動しない(誤った場所へは、移動しない)。

## 開発

```bash
scripts/check.sh emacs     # バイトコンパイル(警告をエラー扱い)と ERT
```

テストは、`protocol/examples/`(`open-validation.json`、`url.json`)の共有の例を、Swift と同じく検証する。

## ライセンス

この `emacs/` ディレクトリは **GPL-3.0-or-later**(`LICENSE`)。HyperBuf 本体(Apache-2.0)とは、ディレクトリごとにライセンスを分けている(Emacs のパッケージの慣例に合わせた)。
