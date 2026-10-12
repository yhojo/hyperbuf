# HyperBuf

*Read like a hacker. No tabs. Just buffers.*

キーボードで、たくさんの Markdown 文書を行き来しながら読む、macOS 用のビューアです(エディタではありません)。

## インストール

1. このディスクイメージの `HyperBuf.app` を、`Applications` フォルダにドラッグします。
2. `HyperBuf.app` を起動します。署名・公証済みなので、そのまま開けます。
3. `C-x C-f`(Control + x、続けて Control + f)で、読みたい Markdown を開きます。

必要な環境: macOS 14(Sonoma)以上(Apple シリコン・Intel のどちらも)。

## 基本の操作

| キー | 動作 |
| --- | --- |
| `C-x C-f` | ファイルを開く(パスの補完つき) |
| `C-x b` | 開いている文書(buffer)を切り替える |
| `C-s` / `C-r` | 文書内を検索する |
| `TAB` / `RET` | リンクを選ぶ / たどる |
| `C-b` / `C-f` | 戻る / 進む(参照の履歴) |
| `C-x 2` / `C-x 3` / `C-x 0` / `C-x o` | window の分割・閉じる・移動 |
| `M-x` | コマンド名で実行 |
| `C-h b` | キー割り当ての一覧 |

`M-` は Option キーです。キー割り当ての全一覧は、アプリの中で `C-h b` を押すと見られます。
設定(キー割り当て、ファイルのアクセス範囲、外部リンクなど)は、
`~/Library/Application Support/HyperBuf/config.json` に書きます(アプリメニューの「設定ファイルの場所を表示」から、Finder で開けます)。

## コマンドラインから開く(`hyperbuf`)

`hyperbuf` コマンドは、`HyperBuf.app` の中に入っています。ターミナルから使うには、パスの通ったところにリンクを作ります。

```bash
sudo mkdir -p /usr/local/bin
sudo ln -s /Applications/HyperBuf.app/Contents/Resources/bin/hyperbuf /usr/local/bin/hyperbuf
```

```bash
hyperbuf README.md            # 文書を開く
hyperbuf docs/plan.md:120     # 120 行目を開く
```

## Emacs から使う(`emacs/`)

`emacs/` フォルダの `hyperbuf.el` を、Emacs の `load-path` の通ったところに置きます(Emacs 29.1 以上)。

```elisp
(add-to-list 'load-path "~/.emacs.d/lisp")   ; hyperbuf.el を置いた場所
(require 'hyperbuf)
(global-set-key (kbd "C-c h o") #'hyperbuf-open-file)
```

`hyperbuf-open-file` は、いま見ているファイルを、現在の行つきで HyperBuf に開きます。
ビューアで文字列を選んで、右クリックの「Emacs で編集」を使うと、Emacs の対応する位置に移動できます。
詳しくは、`emacs/README.md` を見てください。

## ライセンス

- HyperBuf 本体: Apache-2.0(`LICENSE.txt`、`NOTICE.txt`)。同梱するサードパーティのライセンスは、アプリの中(`HyperBuf.app/Contents/Resources/THIRD-PARTY-NOTICES.txt`)にあります。
- `emacs/`(Emacs 連携): GPL-3.0-or-later(`emacs/LICENSE`)。アプリとは別のプログラムとして、同じディスクイメージに入れています。

## フィードバック

不具合や要望は、配布元の方にお知らせください。
