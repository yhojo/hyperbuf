# Getting started with HyperBuf

> **Read like a hacker.**
>
> **No tabs. Just buffers.**

HyperBuf is a document viewer for macOS (not an editor) for reading through a large number of Markdown documents freely, mainly with the keyboard.

It combines the **buffer / window / frame** model that comes from Emacs with a browser-like reference history. It is a tool for **moving across, comparing and going back and forth between** documents, rather than opening them one at a time.

## Installation

1. Drag `HyperBuf.app` from this disk image to the `Applications` folder.
2. Launch `HyperBuf.app`. It is signed and notarized, so it opens as is.
3. Open the Markdown you want to read with `C-x C-f` (Control + x, then Control + f).

Requirements: macOS 14 (Sonoma) or later (both Apple silicon and Intel).

## Concepts

- **buffer / window / frame.** An opened document is a buffer, the area that displays it is a window, and a macOS window is a frame. The same buffer can be shown in several windows, and each keeps its own reading position. A frame is an independent workspace: switch between them with `Cmd-1` to `Cmd-9`, and create one with `C-x 5 2`.
- **Back / Forward (`C-b` / `C-f`) move through the reference history.** Following links, jumping to headings and switching buffers are all pushed onto the history.
- **There is no "choose a project" step.** The directory of the document you are viewing (Emacs's `default-directory`) is the base: files are opened relative to it, and everything under that directory can be listed and full-text searched.
- Input such as searching or choosing a buffer is done not in dialogs but in the minibuffer at the bottom of the frame.

## Basic operations

| Key                                   | Action                                                                 |
| ------------------------------------- | ---------------------------------------------------------------------- |
| `C-x C-f`                             | Open a file (with path completion)                                     |
| `C-x p f`                             | List and open documents under the current directory (the project root) |
| `C-x b`                               | Switch among open documents (buffers)                                  |
| `C-s` / `C-r`                         | Search within the document                                             |
| `M-s g` / `C-x p g`                   | Full-text search under the directory / under the project root          |
| `TAB` / `RET`                         | Select a link / follow it                                              |
| `C-b` / `C-f` (or `←` / `→`)          | Back / Forward (reference history)                                     |
| `C-a` / `C-e`                         | Go to the start / end of the history                                   |
| `C-c j`                               | Choose a heading and jump to it                                        |
| `C-x 2` / `C-x 3` / `C-x 0` / `C-x o` | Split, close and move between windows                                  |
| `C-x ^` / `C-x }` / `C-x {` / `C-x -` | Resize windows (dragging the mode line also works)                     |
| `M-x`                                 | Run a command by name                                                  |
| `C-h b`                               | List of key bindings                                                   |

`M-` is the Option key. You can see the full list of key bindings by pressing `C-h b` in the app.
Settings (key bindings, file access scope, external links and so on) are written in
`~/Library/Application Support/HyperBuf/config.json` (you can open it in Finder from `Show Config File in Finder` in the app menu). The list of available settings is in `docs/user/configuration.md` in the repository.

## Opening from the command line (`hyperbuf`)

The `hyperbuf` command is inside `HyperBuf.app`. To use it from a terminal, create a link in a directory on your path.

```bash
sudo mkdir -p /usr/local/bin
sudo ln -s /Applications/HyperBuf.app/Contents/Resources/bin/hyperbuf /usr/local/bin/hyperbuf
```

```bash
hyperbuf README.md            # open a document
hyperbuf docs/plan.md:120     # open at line 120
```

## Using it from Emacs (`emacs/`)

Put `hyperbuf.el` from the `emacs/` folder somewhere on Emacs's `load-path` (Emacs 29.1 or later).

```elisp
(add-to-list 'load-path "~/.emacs.d/lisp")   ; where you put hyperbuf.el
(require 'hyperbuf)
(global-set-key (kbd "C-c h o") #'hyperbuf-open-file)
```

`hyperbuf-open-file` opens the file you are viewing in HyperBuf, at the current line (Emacs → HyperBuf).

### Editing in Emacs from the viewer (right-click `Edit in Emacs`)

When you find a place you want to fix while reading in the viewer, you can open that place in Emacs (HyperBuf → Emacs). Set it up as follows.

1. **Start the server in Emacs.** Add the following to `init.el` (not needed if you already use it).

   ```elisp
   (require 'server)
   (unless (server-running-p) (server-start))
   ```

   Running `M-x server-start` in a running Emacs also works.

2. **Tell HyperBuf which command to call.** Write it in `~/Library/Application Support/HyperBuf/config.json` (you can show it in Finder with `Show Config File in Finder` in the app menu; create the file if it does not exist).

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

   The path of `emacsclient` differs by environment. Check it with `which emacsclient` (for Homebrew's Emacs, `/opt/homebrew/bin/emacsclient` (Apple silicon) or `/usr/local/bin/emacsclient` (Intel); for Emacs.app, something like `/Applications/Emacs.app/Contents/MacOS/bin/emacsclient`). After changing the settings, restart HyperBuf.

3. **Use it.** In the viewer, select the string you want to fix and choose **right-click → `Edit in Emacs`** (or `C-c e`). Emacs comes to the front and the cursor moves to that position.

To avoid silently editing the wrong place, the position is always verified before moving. If the file has changed since what you saw in the viewer, or the string at the position does not match, Emacs does not move and tells you. If the same wording appears several times and the position cannot be determined, Emacs moves to the start of the block and tells you so.

For details, see `emacs/README.md`.

## What's changed

Changes for each version are in `CHANGELOG.md` (in English). It is in the disk image and at the root of the repository.

## Licenses

- HyperBuf itself: Apache-2.0 (`LICENSE.txt`, `NOTICE.txt`). The third-party licenses that are bundled are inside the app (`HyperBuf.app/Contents/Resources/THIRD-PARTY-NOTICES.txt`).
- `emacs/` (the Emacs integration): GPL-3.0-or-later (`emacs/LICENSE`). It is included in the same disk image as a program separate from the app.

## Feedback

Please report problems and requests to the person who gave you HyperBuf.
