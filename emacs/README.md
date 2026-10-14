# emacs/

Open a document in HyperBuf (a Markdown viewer for macOS) from Emacs, at a given file and line.
Specification: [`docs/integration-protocol.md`](../docs/integration-protocol.md) (in Japanese). Requires Emacs 29.1 or later.

## Usage

```elisp
(add-to-list 'load-path "/path/to/hyperbuf/emacs")
(require 'hyperbuf)

;; Example key bindings (assign whatever you like)
(global-set-key (kbd "C-c h o") #'hyperbuf-open-file)
(global-set-key (kbd "C-c h O") #'hyperbuf-open-other-window)
(global-set-key (kbd "C-c h p") #'hyperbuf-open-project-file)
```

| Command | Action |
| --- | --- |
| `hyperbuf-open-file` | Open the current buffer's file in HyperBuf at the **current line** |
| `hyperbuf-open-other-window` | Same, in another HyperBuf window (split right) |
| `hyperbuf-open-project-file` | Pick a Markdown file of the project and open it |
| `hyperbuf-open` | From Lisp: `(hyperbuf-open FILE &optional LINE ANCHOR TARGET WAIT)` |
| `hyperbuf-visit-location` | Move to the location marked with "Edit in Emacs" in the viewer (with verification; see below) |
| `hyperbuf-edit-here` | Same, and also raise the Emacs frame (meant to be called from `emacsclient`) |

With a prefix argument (`C-u`), wait longer for confirmation in the app (e.g. whether to open a warn-path file).
The viewer reads the file on disk, so if the buffer has unsaved changes, Emacs asks whether to save before opening (`hyperbuf-save-before-open`).

## From the viewer to the edit location ("Edit in Emacs")

In the viewer, select the text you want to fix and choose **"Edit in Emacs"** from the context menu (or press `C-c e` in the viewer).
Then run `M-x hyperbuf-visit-location` in Emacs (or let the viewer call `hyperbuf-edit-here` through the configured `emacsclient`) to move to that location.

So that **a wrong place is never edited silently**, Emacs always verifies the location before moving.

| Check | On failure |
| --- | --- |
| Is the file the same version the viewer rendered? (SHA-256) | Does not move. Reports that what you see in the viewer and what you would edit do not match |
| Do the text at the location and its surrounding context match what the viewer pointed at? (also detects shifts caused by unsaved edits) | Does not move. Shows the details of the mismatch in `*hyperbuf-mismatch*` |

When a check fails, there is **no way to continue** (something is likely fundamentally wrong and you may not have noticed).
On success, the range is highlighted briefly and the text the viewer pointed at is shown in the echo area. If the same text appears several times and the position cannot be determined,
Emacs moves to the start of the block and says that the location is ambiguous and the whole block is shown (it never moves on a guess).

To let the viewer call Emacs, write a fixed command in `~/Library/Application Support/HyperBuf/config.json`
(the document content and location are not passed as arguments; see `docs/integration-protocol.md` section 15, in Japanese).

```json
{
  "editorName": "Emacs",
  "editorCommand": ["/opt/homebrew/bin/emacsclient", "-n", "-e", "(hyperbuf-edit-here)"]
}
```

## Settings

| Variable | Default | Meaning |
| --- | --- | --- |
| `hyperbuf-transport` | `socket` | `socket`: connect to the app's socket directly. `cli`: call the `hyperbuf` command |
| `hyperbuf-executable` | `"hyperbuf"` | Command used when the transport is `cli` |
| `hyperbuf-launch-if-needed` | `t` | If the app is not running, launch it with a `hyperbuf://` URL carrying the open request. If `nil`, just report it |
| `hyperbuf-app` | `nil` | Path of the `.app` to launch (for development) |
| `hyperbuf-default-target` | `nil` | Default place to show the document (e.g. `"split-right"`) |
| `hyperbuf-timeout` / `hyperbuf-wait-timeout` | 3 / 60 | Seconds to wait for confirmation |
| `hyperbuf-socket-path` | `nil` | Path of the socket (else the `HYPERBUF_SOCKET_PATH` environment variable, else the default location) |

## Limitations

- Remote files (TRAMP) cannot be opened (the viewer reads only local files).
- If the app is not running, Emacs launches it and hands over the request, but the result appears in the app (it is not returned to Emacs).
- Files in encodings other than UTF-8 fail the viewer's verification and Emacs does not move (it never moves to a wrong place).

## Development

```bash
scripts/check.sh emacs     # byte-compile (warnings as errors) and ERT
```

The tests check the shared examples in `protocol/examples/` (`open-validation.json`, `url.json`) in the same way as the Swift side.

## License

This `emacs/` directory is **GPL-3.0-or-later** (`LICENSE`). The licenses are separated by directory from the HyperBuf core (Apache-2.0), following the convention of Emacs packages.
