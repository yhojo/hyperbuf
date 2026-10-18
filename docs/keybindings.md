<!-- 自動生成: core/scripts/gen-keybindings.ts。直接編集しない(コードの変更に合わせて、再生成する) -->

# Key bindings

`C-h b` shows this list. Bindings can be changed with `keybindings` in `config.json` (`null` removes a default binding).
Commands can be run by name with `M-x`.

## Bound commands

| Key | Command | Description |
| --- | --- | --- |
| `C-b`, `left`, `s-[` | `back` | Go back in reference history |
| `C-c C-b` | `backward-same-level` | Go to the previous heading at the same level (does not cross parents) |
| `M-<` | `beginning-of-document` | Go to the beginning of the document |
| `M-=` | `count-words` | Count the lines, words and characters of the selected text (or of the whole document) as displayed |
| `C-x 5 0` | `delete-frame` | Delete this frame (quits the app if it is the last one) |
| `C-x 5 1` | `delete-other-frames` | Delete all other frames |
| `C-x 1` | `delete-other-windows` | Make the selected window fill the frame |
| `C-x 0` | `delete-window` | Delete the selected window |
| `C-h b` | `describe-bindings` | Show the list of key bindings (and configuration problems) |
| `C-c e` | `edit-in-editor` | Record the location at point (selection, right-click or top of the screen) for editing in the editor |
| `M->` | `end-of-document` | Go to the end of the document |
| `C-x ^` | `enlarge-window` | Make the selected window taller (its neighbour shrinks) |
| `C-x }` | `enlarge-window-horizontally` | Make the selected window wider (its neighbour shrinks) |
| `M-x` | `execute-command` | Execute a command chosen by name |
| `C-x C-f` | `find-file` | Visit a file (path completion starting at the base directory; RET enters a directory; ~/, ../ and absolute paths also work) |
| `RET` | `follow-link` | Follow the selected link |
| `C-f`, `right`, `s-]` | `forward` | Go forward in reference history |
| `C-c C-f` | `forward-same-level` | Go to the next heading at the same level (does not cross parents) |
| `C-c j` | `goto-heading` | Go to a heading chosen from a list |
| `M-g g` | `goto-line` | Go to a line number of the source Markdown |
| `C-r` | `isearch-backward` | Search the document incrementally, backward |
| `C-s` | `isearch-forward` | Search the document incrementally (C-s next, C-r previous, RET accept, C-g cancel) |
| `C-g` | `keyboard-quit` | Cancel the key sequence in progress |
| `C-x k` | `kill-buffer` | Kill a buffer (its references are removed from every window's history) |
| `C-x 5 2` | `make-frame` | Make a new frame (a macOS window), numbered with the smallest free number (Cmd-1...) |
| `C-c C-n` | `next-heading` | Go to the next heading (not pushed onto reference history) |
| `TAB` | `next-link` | Select the next link |
| `C-x 5 o` | `other-frame` | Select the next frame |
| `C-x o` | `other-window` | Select the next window |
| `S-TAB` | `prev-link` | Select the previous link |
| `C-c C-p` | `previous-heading` | Go to the previous heading (the current section's heading if in the middle of one) |
| `C-x p f` | `project-find-file` | Visit a Markdown file from a recursive list under the base directory (../, ~/ and absolute paths change the base) |
| `C-x p g` | `project-find-regexp` | Search all files under the project root (the nearest ancestor with .git/.hg/…, or the base directory) and show the results in a virtual buffer (plain text, case-insensitive for ASCII; .gitignore is not read) |
| `C-n` | `scroll-line-down` | Scroll down one line |
| `C-p` | `scroll-line-up` | Scroll up one line |
| `C-v`, `SPC` | `scroll-page-down` | Scroll down one screen |
| `DEL`, `M-v`, `S-SPC` | `scroll-page-up` | Scroll up one screen |
| `M-s g` | `search-project` | Search all files under the base directory and show the results in a virtual buffer |
| `C-x {` | `shrink-window-horizontally` | Make the selected window narrower (its neighbour grows) |
| `C-x -` | `shrink-window-if-larger-than-buffer` | Shrink the selected window to fit its document if it is taller than the document |
| `C-x 2` | `split-below` | Split the window above and below (history is copied) |
| `C-x 3` | `split-right` | Split the window side by side (history is copied) |
| `C-x b` | `switch-buffer` | Switch to a buffer chosen from the open buffers (most recently used first) |
| `C-x x u` | `toggle-follow-updates` | Toggle jumping to the first changed place when a file is updated externally (off by default; [Follow] in the mode line) |
| `C-c C-u` | `up-heading` | Go up to the parent heading |

## Unbound commands (run with `M-x`)

| Command | Description |
| --- | --- |
| `forget-remembered-path` | Forget a location approved and remembered under a warn path (it will be confirmed again) |
| `forget-remembered-site` | Forget a site remembered with "always" for opening in the browser (it will be confirmed again) |

## キーの表記

- `C-x`: Control を押しながら x。`M-x`: Meta(macOS では Option)を押しながら x。`s-[`: Command を押しながら `[`。`S-TAB`: Shift + Tab。
- `C-x 2`: `C-x` を押したあとで、`2` を押す(プレフィックス)。
- 記号は、物理キーで判断する(US 配列)。`M-<` は、Option + Shift + `,`。
- 入力欄(ミニバッファ)の中では、`C-f` / `C-b` / `C-a` / `C-e` は、文字の移動に戻る。確定は `RET`、取消は `C-g`、候補の選択は `C-n` / `C-p`、入力の履歴は `M-p` / `M-n`。

設定で変える方法は、[configuration.md](configuration.md)。
