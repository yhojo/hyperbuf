# emacs/

Emacs integration for HyperBuf (a keyboard-driven Markdown viewer for macOS). It works in both directions:

- **Emacs → HyperBuf:** open the file you are editing in HyperBuf, at the current line.
- **HyperBuf → Emacs:** mark a place in the viewer ("Edit in Emacs") and jump to exactly that place in Emacs, after verifying that it is the right one.

Requires Emacs 29.1 or later. Specification (in Japanese): [`docs/dev/integration-protocol.md`](../docs/dev/integration-protocol.md) and [`docs/dev/edit-location.md`](../docs/dev/edit-location.md).

## Installation

The package is a single file, `hyperbuf.el`. Put it in a directory on your `load-path`. It is in this repository (`emacs/`) and also in the `emacs/` folder of the HyperBuf disk image.

```elisp
(add-to-list 'load-path "/path/to/hyperbuf/emacs")
(require 'hyperbuf)

;; Example key bindings (assign whatever you like)
(global-set-key (kbd "C-c h o") #'hyperbuf-open-file)
(global-set-key (kbd "C-c h p") #'hyperbuf-open-project-file)
```

## Commands

| Command | Action |
| --- | --- |
| `hyperbuf-open-file` | Open the current buffer's file in HyperBuf at the **current line** |
| `hyperbuf-open-project-file` | Pick a Markdown file of the current Emacs project (`project.el`) and open it |
| `hyperbuf-open` | From Lisp: `(hyperbuf-open FILE &optional LINE ANCHOR TARGET WAIT)` (`TARGET` is reserved and has no effect yet) |
| `hyperbuf-visit-location` | Move to the location marked with "Edit in Emacs" in the viewer (with verification; see below) |
| `hyperbuf-edit-here` | Same, and also raise the Emacs frame (meant to be called from `emacsclient`) |

With a prefix argument (`C-u`), wait longer for confirmation in the app (for example, whether to open a file under a warn path).
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
(the document content and location are not passed as arguments; see `docs/dev/edit-location.md` section 7, in Japanese).
Emacs must be running a server (`(server-start)`).

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
| `hyperbuf-launch-if-needed` | `t` | If the app is not running, launch it (with `hyperbuf://ping`), wait for its socket and then send the open request, like the `hyperbuf` command. If `nil`, just report it |
| `hyperbuf-launch-timeout` | 15 | Seconds to wait for a launched app to start listening on the socket (`C-g` interrupts the wait) |
| `hyperbuf-app` | `nil` | Path of the `.app` to launch (for development) |
| `hyperbuf-timeout` / `hyperbuf-wait-timeout` | 3 / 60 | Seconds to wait for confirmation (the second one with a prefix argument) |
| `hyperbuf-save-before-open` | `ask` | Whether to save a modified buffer before opening it in the viewer: `ask`, `t` (save without asking) or `nil` |
| `hyperbuf-location-max-age` | 600 | Age in seconds after which a location marked in the viewer is reported as old when you visit it |
| `hyperbuf-socket-path` | `nil` | Path of the socket (else the `HYPERBUF_SOCKET_PATH` environment variable, else the default location) |

## Limitations

- Remote files (TRAMP) cannot be opened (the viewer reads only local files).
- If the app is not running, Emacs launches it and waits for it (`hyperbuf-launch-timeout`); Emacs is blocked while it waits, and `C-g` interrupts the wait.
- Files in encodings other than UTF-8 fail the viewer's verification and Emacs does not move (it never moves to a wrong place).

## Development

```bash
scripts/check.sh emacs     # byte-compile (warnings as errors) and ERT
```

The tests check the shared examples in `protocol/examples/` (`open-validation.json`, `url.json`, `location-check.json`) in the same way as the Swift side.

## License

This `emacs/` directory is **GPL-3.0-or-later** (`LICENSE`). The licenses are separated by directory from the HyperBuf core (Apache-2.0), following the convention of Emacs packages.
