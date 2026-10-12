# HyperBuf

> **Read like a hacker.**
>
> **No tabs. Just buffers.**

HyperBufは、大量のMarkdownドキュメントを、キーボード主体で自在に読み進めるためのmacOS向けドキュメントビューアです(エディタではありません)。

単なるMarkdownプレビューアではありません。Emacsに由来する **buffer / window / frame** の考え方と、Webブラウザのような参照履歴を組み合わせ、ドキュメントを「一枚ずつ開く」のではなく、**横断し、比較し、行き来する**ための道具を目指します。

## 名前の由来

**HyperBuf** は、**Hyper**text(相互にリンクされた文書)と、(Emacs の)**Buf**fer を合わせた名前です。リンクでつながったたくさんの文書を、Emacs の buffer のように、気軽に開き、切り替え、行き来する、という意味を込めています。

## Why HyperBuf?

Markdownビューアは数多く存在します。しかし、技術者が数十〜数百の相互参照された設計文書を読む際の操作性、拡張記法の再現性、キーボードでの自在な移動を一貫して重視した製品には、まだ挑戦の余地があります。

HyperBufは、ハッカー文化に根差した **使い込める道具** を目指します。表面的なレトロ趣味ではなく、予測可能な操作、透明性、構成可能性、既存のツールとの共存を重視します。

## Principles

- **Keyboard first. Mouse optional.** — 主要な閲覧操作はキーボードで完結する。マウス操作も排除しない。
- **No tabs. Just buffers.** — ドキュメントの実体(buffer)と表示領域(window)を分離する。
- **Navigation is a first-class feature.** — 文書間の参照、戻る／進む、見出しジャンプ、検索を中心機能として設計する。
- **Files are yours.** — プレーンなMarkdownと既存のディレクトリ構造を尊重し、独自形式への移行を要求しない。
- **Render what engineers write.** — GFM、SVG、数式、図表、コードなど、実務で使われる表現への対応を重視する。
- **Extensible by design.** — 拡張しやすく、設定や動作が理解できる構造を目指す。
- **Local first.** — 基本的な閲覧はオフラインで完結し、意図しない外部通信を行わない。

## Emacs-inspired navigation

- buffer / window / frame を区別して管理します。同じ buffer を複数の window に表示でき、それぞれが独立した閲覧位置を持ちます。frame(macOS のウィンドウ)は、独立した作業場です(`Cmd-1`〜`Cmd-9` で切り替え、`C-x 5 2` で作成)。
- `C-x 2` / `C-x 3` / `C-x 0` / `C-x 1` / `C-x o` / `C-x b` など、Emacs と同じ操作を出発点にしています。
- **戻る / 進む(`C-b` / `C-f`)は、参照履歴の前後移動**です。リンクや見出しジャンプ、buffer の切り替えも、履歴に積まれます。
- 検索や buffer 選択などの入力は、ダイアログではなく、frame 下部のミニバッファで行います。
- 「プロジェクトを選ぶ」操作はありません。いま見ている文書のディレクトリ(Emacs の `default-directory`)を基準に、ファイルを開き、そのディレクトリ以下を一覧・全文検索します。
- キー割り当ては、`config.json` で変えられます。

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

`hyperbuf-open-file` は、いま見ているファイルを、現在の行つきで HyperBuf に開きます(Emacs → HyperBuf)。

### ビューアから Emacs で編集する(右クリックの「Emacs で編集」)

ビューアで読んでいて、直したい箇所を見つけたら、その場所を、Emacs で開けます(HyperBuf → Emacs)。次の準備をします。

1. **Emacs でサーバーを起動する。** `init.el` に、次を足します(すでに使っているなら不要)。

   ```elisp
   (require 'server)
   (unless (server-running-p) (server-start))
   ```

   Emacs を起動したまま、`M-x server-start` でも構いません。

2. **HyperBuf に、呼び出すコマンドを教える。** `~/Library/Application Support/HyperBuf/config.json` に書きます(アプリメニューの「設定ファイルの場所を表示」で、Finder に出せます。ファイルがなければ作ります)。

   ```json
   {
     "editorName": "Emacs",
     "editorCommand": ["/opt/homebrew/bin/emacsclient", "-n", "-e", "(hyperbuf-edit-here)"]
   }
   ```

   `emacsclient` のパスは、環境で違います。`which emacsclient` で確かめてください(Homebrew の Emacs なら `/opt/homebrew/bin/emacsclient`(Apple シリコン)か `/usr/local/bin/emacsclient`(Intel)。Emacs.app なら `/Applications/Emacs.app/Contents/MacOS/bin/emacsclient` など)。設定を変えたら、HyperBuf を再起動します。

3. **使う。** ビューアで、直したい文字列を選択して、**右クリック →「Emacs で編集」**(または `C-c e`)を選びます。Emacs が前面に出て、その位置にカーソルが移ります。

誤った場所を黙って編集させないために、移動の前に、必ず照合します。ファイルが、ビューアで見ていた内容から変わっているとき、位置の文字列が合わないときは、移動せずに知らせます。同じ文言が複数あって位置が決められないときは、ブロックの先頭へ移動して、そのことを知らせます。

詳しくは、`emacs/README.md` を見てください。

## ライセンス

- HyperBuf 本体: Apache-2.0(`LICENSE.txt`、`NOTICE.txt`)。同梱するサードパーティのライセンスは、アプリの中(`HyperBuf.app/Contents/Resources/THIRD-PARTY-NOTICES.txt`)にあります。
- `emacs/`(Emacs 連携): GPL-3.0-or-later(`emacs/LICENSE`)。アプリとは別のプログラムとして、同じディスクイメージに入れています。

## フィードバック

不具合や要望は、配布元の方にお知らせください。
