<!-- 自動生成: core/scripts/gen-keybindings.ts。直接編集しない(コードの変更に合わせて、再生成する) -->

# キー割り当て

`C-h b` で、この一覧を出す。割り当ては、`config.json` の `keybindings` で変えられる(`null` で、標準の割り当てを外す)。
コマンドは、`M-x` から、名前で実行できる。

## 割り当て済み

| キー | コマンド | 説明 |
| --- | --- | --- |
| `C-b`、 `s-[` | `back` | 参照履歴を戻る |
| `C-c C-b` | `backward-same-level` | 同じレベルの、前の見出しへ(親をまたがない) |
| `M-<` | `beginning-of-document` | 文書の先頭へ |
| `C-x 5 0` | `delete-frame` | このフレームを閉じる(最後の 1 つなら、アプリを終了する) |
| `C-x 5 1` | `delete-other-frames` | このフレームだけを残して、ほかのフレームを閉じる |
| `C-x 1` | `delete-other-windows` | 選択中の window だけを残す |
| `C-x 0` | `delete-window` | 選択中の window を閉じる |
| `C-h b` | `describe-bindings` | キー割り当ての一覧を出す(設定の問題も) |
| `C-c e` | `edit-in-editor` | 指した場所(選択・右クリック・画面の上端)を、エディタで編集するために記録する |
| `M->` | `end-of-document` | 文書の末尾へ |
| `M-x` | `execute-command` | コマンドを、名前を選んで実行する |
| `C-x C-f` | `find-file` | ファイルを開く(基準のディレクトリから始まるパス補完。ディレクトリは RET で入る。~/・../・絶対パスも可) |
| `RET` | `follow-link` | 選んでいるリンクをたどる |
| `C-f`、 `s-]` | `forward` | 参照履歴を進む |
| `C-c C-f` | `forward-same-level` | 同じレベルの、次の見出しへ(親をまたがない) |
| `C-c j` | `goto-heading` | 見出しを選んで、そこへ移動する |
| `M-g g` | `goto-line` | 元の Markdown の行番号を指定して、そこへ移動する |
| `C-r` | `isearch-backward` | 文書内を、後ろ向きにインクリメンタル検索する |
| `C-s` | `isearch-forward` | 文書内を、インクリメンタルに検索する(C-s で次、C-r で前、RET で確定、C-g で取消) |
| `C-g` | `keyboard-quit` | 入力途中のキーを取り消す |
| `C-x k` | `kill-buffer` | buffer を閉じる(どの window の履歴からも、その参照を取り除く) |
| `C-x 5 2` | `make-frame` | 新しいフレーム(macOS のウィンドウ)を作る。空いている最小の番号(Cmd-1〜)になる |
| `C-c C-n` | `next-heading` | 次の見出しへ(参照履歴には積まない) |
| `TAB` | `next-link` | 次のリンクを選ぶ |
| `C-x 5 o` | `other-frame` | 次のフレームへ移る |
| `C-x o` | `other-window` | 次の window を選択する |
| `S-TAB` | `prev-link` | 前のリンクを選ぶ |
| `C-c C-p` | `previous-heading` | 前の見出しへ(節の途中なら、その節の見出しへ) |
| `C-x p f` | `project-find-file` | 基準のディレクトリ以下の Markdown を、再帰で一覧にして絞り込み、開く(../・~/・絶対パスで基準を変えられる) |
| `C-n` | `scroll-line-down` | 1 行分、下へスクロールする |
| `C-p` | `scroll-line-up` | 1 行分、上へスクロールする |
| `C-v`、 `SPC` | `scroll-page-down` | 1 画面分、下へスクロールする |
| `DEL`、 `M-v`、 `S-SPC` | `scroll-page-up` | 1 画面分、上へスクロールする |
| `M-s g` | `search-project` | 基準のディレクトリ以下を全文検索して、結果を仮想 buffer に出す |
| `C-x 2` | `split-below` | window を、上下に分割する(履歴は、複製される) |
| `C-x 3` | `split-right` | window を、左右に分割する(履歴は、複製される) |
| `C-x b` | `switch-buffer` | 開いている buffer を、最近使った順の候補から選んで表示する |
| `C-c C-u` | `up-heading` | 上のレベルの見出しへ |

## キーなし(`M-x` で実行)

| コマンド | 説明 |
| --- | --- |
| `forget-remembered-path` | 警告パスの下で、承認して記憶した場所を、選んで取り消す(次から、また確認される) |

## キーの表記

- `C-x`: Control を押しながら x。`M-x`: Meta(macOS では Option)を押しながら x。`s-[`: Command を押しながら `[`。`S-TAB`: Shift + Tab。
- `C-x 2`: `C-x` を押したあとで、`2` を押す(プレフィックス)。
- 記号は、物理キーで判断する(US 配列)。`M-<` は、Option + Shift + `,`。
- 入力欄(ミニバッファ)の中では、`C-f` / `C-b` / `C-a` / `C-e` は、文字の移動に戻る。確定は `RET`、取消は `C-g`、候補の選択は `C-n` / `C-p`、入力の履歴は `M-p` / `M-n`。

設定で変える方法は、[configuration.md](configuration.md)。
