# Session Restore

The mechanism that brings back the working state after the app is quit and launched again. What is saved is buffers, windows, and reference history; the concepts follow [buffer-model.md](buffer-model.md) and [interaction-model.md](interaction-model.md).

## 1. Overview

- The session is saved in **one file overall**, as a **sequence of frames (macOS windows)**. It is not saved per project or per buffer.
- At startup, all frames from last time are restored. If there is no saved data or it is broken, an empty screen with a single slot-1 frame shows "open with `C-x C-f`".
- When opening with `hyperbuf <file>`, that file is opened on top of the restored state (the destination frame is described in [buffer-model.md](buffer-model.md) §7).
- The setting is `restoreSession` in `config.json` (default `true`). While it is `false`, nothing is restored or saved ([configuration.md](../user/configuration.md)).

## 2. What is saved

For each frame, the following is saved and restored at the next launch.

- The window split layout (split direction, order of windows, split ratio). The ratio is optional, and omitting it means equal sizes. It brings back sizes changed with `C-x ^` and the like or by dragging the mode line.
- Each window's reference history (documents, anchors, reading positions) and the current position in the history.
- The selected window.
- The most-recently-used order of buffers (the `C-x b` candidate order).
- The **selection** (text selected in a document): the position within the displayed text (start and end) and the selected string, one entry only. It is restored only when the window displays the same document as when it was saved and **the string at that position matches** (if the document has been rewritten, it is not restored, so that a shifted place is not selected). Even if only the selection is broken, everything else is restored. A selection of a whole paragraph (where the ends of the range are elements) can also be saved.
- The window position and size (`rect`). On restore, it is adjusted to fit the current screen.

Not saved:

- **Document contents.** They are re-read from the file at restore (the latest contents are shown).
- Virtual buffers (`*search: …*`, `*Help: …*`). They are removed from the history, and the current position is decided from the rest of the history.
- A minibuffer with input in progress, the search term (the previous term of `C-s`), and the link selection (`TAB`).
- Remembered paths ([file-access.md](file-access.md) §4) are already persisted in a separate location (`trusted-roots.json`).

## 3. Location and format

```
~/Library/Application Support/HyperBuf/session.json
```

The containing directory is 0700 and the file is 0600. It is written to a temporary file and then replaced (so intermediate states are never visible).

### 3.1 File (version 2)

```json
{
  "version": 2,
  "active": 1,
  "frames": [
    {
      "slot": 1,
      "rect": { "x": 0, "y": 0, "width": 1200, "height": 800 },
      "snapshot": { "...": "§3.2" }
    }
  ]
}
```

- `active` is the slot of the frame that was last active.
- `slot` is the frame number (`Cmd-1` … `Cmd-9`). It is 1 to 9; invalid or duplicate frames are discarded.
- `rect` is the position and size of the window.

### 3.2 Snapshot (one frame; version 1)

Produced by the Web core (`core/src/session.ts`).

```json
{
  "version": 1,
  "selected": 1,
  "winSeq": 2,
  "mru": ["/Users/me/notes/a.md"],
  "root": {
    "type": "split",
    "dir": "row",
    "ratio": 0.5,
    "children": [
      {
        "type": "leaf",
        "id": 1,
        "index": 0,
        "history": [
          { "path": "/Users/me/notes/a.md", "anchor": null, "scroll": 120 }
        ]
      },
      { "type": "leaf", "id": 2, "index": 0, "history": ["…"] }
    ]
  },
  "selection": {
    "win": 1,
    "path": "/Users/me/notes/a.md",
    "start": 10,
    "end": 24,
    "text": "…"
  }
}
```

- `root` is the split tree. A node is either a `split` (`dir`: `row` / `col`, `children`: two, `ratio`: optional) or a `leaf` (a window: `id`, history, and the current position in the history `index`).
- `selected` is the `id` of the selected window, and `winSeq` is the number of the last window assigned.
- `selection` is optional.
- When the shape of the snapshot changes, `SESSION_VERSION` is raised.

## 4. Limits

The shape, types, counts, and lengths are limited. The values are defined at the following places in the code. **When you change a value in this table or in the code, always fix both** (`core/test/session-docs.test.ts` checks that the Web core's values match this table).

| Name            | Value   | Meaning                                                                                            | Definition                                         |
| --------------- | ------- | -------------------------------------------------------------------------------------------------- | -------------------------------------------------- |
| `MAX_HISTORY`   | 100     | Number of history entries saved per window (keeping entries before and after the current position) | `core/src/session.ts`                              |
| `MAX_MRU`       | 200     | Number of buffers saved in most-recently-used order                                                | `core/src/session.ts`                              |
| `MAX_WINDOWS`   | 32      | Number of windows per frame                                                                        | `core/src/session.ts`                              |
| `MAX_DEPTH`     | 16      | Depth of the split tree                                                                            | `core/src/session.ts`                              |
| `MAX_STRING`    | 4096    | Length of strings such as paths and anchors                                                        | `core/src/session.ts`                              |
| `MAX_SELECTION` | 4096    | Number of characters of a saved selection (a longer one is not saved)                              | `core/src/session.ts`                              |
| `SAVE_DELAY_MS` | 1000    | Wait, per frame, from a change until the Web core saves (milliseconds)                             | `core/src/ui/session.ts`                           |
| `maxBytes`      | 4000000 | Upper limit on the size of `session.json` (bytes; a larger one is neither saved nor read)          | `app/macos/Sources/HyperBufKit/SessionStore.swift` |
| `maxFrames`     | 9       | Number of frames (slots 1 to 9)                                                                    | `app/macos/Sources/HyperBufKit/SessionStore.swift` |

## 5. Saving and restoring

### 5.1 Saving

- On every display update and scroll, the Web core waits 1 second (consecutive changes are merged into one) and then saves per frame.
- The host collects the snapshots of all frames, waits a further 0.5 seconds, and writes them to one file. If the contents are the same as last time, it does not write.
- When the page becomes hidden, a window is closed, or the app quits, it writes without waiting. Quitting waits until saving finishes (up to 1.5 seconds).
- **When a frame is closed:** if it is not the last one, that frame's session is discarded (the same as Emacs `delete-frame`). When the last one is closed, or the app quits, all frames at that moment are saved.

### 5.2 Restoring

- At startup, all frames from last time are created, and each snapshot is restored. Saving starts after the restore (it does not write before the restore, so the previous state is not erased).
- Whether a document exists is known by trying to read it. **Documents that are gone or can no longer be read (permissions and so on) are removed from the history** (the current position becomes the previous reference). If a window's history becomes empty, that window is folded away (the split is removed). If everything is gone, it becomes a normal startup.

### 5.3 Validation

Saved data is **treated as untrusted input**.

- The Web core strictly validates the shape, types, counts, and lengths with the limits in §4 (`core/src/session.ts`). A broken frame is not used partially; only that frame is discarded and the others are restored. If there is no usable frame, it becomes a normal startup. If only the selection is broken, only the selection is discarded.
- The shell (Swift) checks only that it is readable as JSON, its size, and the rough outline of the slots.
