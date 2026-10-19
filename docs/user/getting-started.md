# HyperBuf を使いはじめる

> **Read like a hacker.**
>
> **No tabs. Just buffers.**

HyperBuf は、大量の Markdown ドキュメントを、キーボード主体で自在に読み進めるための macOS 向けドキュメントビューアです(エディタではありません)。

Emacs に由来する **buffer / window / frame** の考え方と、Web ブラウザのような参照履歴を組み合わせ、ドキュメントを「一枚ずつ開く」のではなく、**横断し、比較し、行き来する**ための道具です。

## インストール

1. このディスクイメージの `HyperBuf.app` を、`Applications` フォルダにドラッグします。
2. `HyperBuf.app` を起動します。署名・公証済みなので、そのまま開けます。
3. `C-x C-f`(Control + x、続けて Control + f)で、読みたい Markdown を開きます。

必要な環境: macOS 14(Sonoma)以上(Apple シリコン・Intel のどちらも)。

## 考え方

- **buffer / window / frame。** 開いた文書が buffer、それを表示する領域が window、macOS のウィンドウが frame です。同じ buffer を複数の window に表示でき、それぞれが独立した閲覧位置を持ちます。frame は独立した作業場で、`Cmd-1`〜`Cmd-9` で切り替え、`C-x 5 2` で作ります。
- **戻る / 進む(`C-b` / `C-f`)は、参照履歴の前後移動**です。リンクや見出しジャンプ、buffer の切り替えも、履歴に積まれます。
- **「プロジェクトを選ぶ」操作はありません。** いま見ている文書のディレクトリ(Emacs の `default-directory`)を基準に、ファイルを開き、そのディレクトリ以下を一覧・全文検索します。
- 検索や buffer の選択などの入力は、ダイアログではなく、frame 下部のミニバッファで行います。

## 基本の操作

| キー                                  | 動作                                                               |
| ------------------------------------- | ------------------------------------------------------------------ |
| `C-x C-f`                             | ファイルを開く(パスの補完つき)                                     |
| `C-x p f`                             | いまのディレクトリ(プロジェクトのルート)以下の文書を一覧にして開く |
| `C-x b`                               | 開いている文書(buffer)を切り替える                                 |
| `C-s` / `C-r`                         | 文書内を検索する                                                   |
| `M-s g` / `C-x p g`                   | ディレクトリ以下 / プロジェクトのルート以下を全文検索する          |
| `TAB` / `RET`                         | リンクを選ぶ / たどる                                              |
| `C-b` / `C-f`(または `←` / `→`)       | 戻る / 進む(参照の履歴)                                            |
| `C-a` / `C-e`                         | 履歴の先頭 / 最後へ移る                                            |
| `C-c j`                               | 見出しを選んで移動する                                             |
| `C-x 2` / `C-x 3` / `C-x 0` / `C-x o` | window の分割・閉じる・移動                                        |
| `C-x ^` / `C-x }` / `C-x {` / `C-x -` | window の大きさを変える(モードラインのドラッグでも)                |
| `M-x`                                 | コマンド名で実行                                                   |
| `C-h b`                               | キー割り当ての一覧                                                 |

`M-` は Option キーです。キー割り当ての全一覧は、アプリの中で `C-h b` を押すと見られます。
設定(キー割り当て、ファイルのアクセス範囲、外部リンクなど)は、
`~/Library/Application Support/HyperBuf/config.json` に書きます(アプリメニューの `Show Config File in Finder`から、Finder で開けます)。設定できる項目の一覧は、リポジトリの `docs/user/configuration.md` にあります。

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

`hyperbuf-open-file` は、いま見ているファイルを、現在の行つきで HyperBuf に開きます(Emacs → HyperBuf)。

### ビューアから Emacs で編集する(右クリックの `Edit in Emacs`)

ビューアで読んでいて、直したい箇所を見つけたら、その場所を、Emacs で開けます(HyperBuf → Emacs)。次の準備をします。

1. **Emacs でサーバーを起動する。** `init.el` に、次を足します(すでに使っているなら不要)。

   ```elisp
   (require 'server)
   (unless (server-running-p) (server-start))
   ```

   Emacs を起動したまま、`M-x server-start` でも構いません。

2. **HyperBuf に、呼び出すコマンドを教える。** `~/Library/Application Support/HyperBuf/config.json` に書きます(アプリメニューの `Show Config File in Finder`で、Finder に出せます。ファイルがなければ作ります)。

   ```json
   {
     "editorName": "Emacs",
     "editorCommand": [
       "/opt/homebrew/bin/emacsclient",
       "-n",
       "-e",
       "(hyperbuf-edit-here)"
     ]
   }
   ```

   `emacsclient` のパスは、環境で違います。`which emacsclient` で確かめてください(Homebrew の Emacs なら `/opt/homebrew/bin/emacsclient`(Apple シリコン)か `/usr/local/bin/emacsclient`(Intel)。Emacs.app なら `/Applications/Emacs.app/Contents/MacOS/bin/emacsclient` など)。設定を変えたら、HyperBuf を再起動します。

3. **使う。** ビューアで、直したい文字列を選択して、**右クリック → `Edit in Emacs`**(または `C-c e`)を選びます。Emacs が前面に出て、その位置にカーソルが移ります。

誤った場所を黙って編集させないために、移動の前に、必ず照合します。ファイルが、ビューアで見ていた内容から変わっているとき、位置の文字列が合わないときは、移動せずに知らせます。同じ文言が複数あって位置が決められないときは、ブロックの先頭へ移動して、そのことを知らせます。

詳しくは、`emacs/README.md` を見てください。

## 更新内容

版ごとの変更は、`CHANGELOG.md`(英語)にあります。ディスクイメージの中と、リポジトリのルートにあります。

## ライセンス

- HyperBuf 本体: Apache-2.0(`LICENSE.txt`、`NOTICE.txt`)。同梱するサードパーティのライセンスは、アプリの中(`HyperBuf.app/Contents/Resources/THIRD-PARTY-NOTICES.txt`)にあります。
- `emacs/`(Emacs 連携): GPL-3.0-or-later(`emacs/LICENSE`)。アプリとは別のプログラムとして、同じディスクイメージに入れています。

## フィードバック

不具合や要望は、配布元の方にお知らせください。
