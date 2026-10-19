# Edit location handoff (viewer to editor)

The mechanism that hands the place being viewed in the viewer to the editor (Emacs) as an edit location, **accurately**. The socket contract as a whole is in [integration-protocol.md](integration-protocol.md). The background and a comparison of approaches are in [poc-integration-results.md](../history/poc-integration-results.md) §5.

## 1. Purpose

When a user finds a mistake in a document in the viewer and goes to fix it in the editor, this prevents **fixing the wrong place**. In a huge document where the same wording appears several times, the position that was being viewed and the position reached by a search in the editor can disagree. So instead of merely taking the user near the place, the editor **verifies** that the position is correct before moving to it.

## 2. Requirements

| #   | Requirement                                 | Meaning                                                                                                                                                                                                                  |
| --- | ------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| R1  | **Point to an exact position.**             | Without relying on a text search, the viewer identifies the position in the original Markdown (line and column, or a range) and hands it over                                                                            |
| R2  | **Never let a mismatch pass silently.**     | Along with the position, the viewer passes "the string that should be at that position", and the editor verifies it. If it does not match, the editor warns and does not jump                                            |
| R3  | **Detect a stale view.**                    | The viewer passes the identity of the file at the time it rendered (content hash, modification time and size). If the file on the editor side has changed, the editor warns                                              |
| R4  | **Let the user confirm where they landed.** | On the editor side, the target range is temporarily highlighted and "the string the viewer pointed at" is shown in a message                                                                                             |
| R5  | **Do not hide ambiguity.**                  | When the position cannot be determined uniquely (no selection and the same string appears several times in the block, for example), only the certain range (the whole block) is passed, explicitly marked as "ambiguous" |

## 3. Overall flow

The approach is "**the editor comes to fetch it**". The app only records the pointed position and waits; it does not push values to the editor.

1. In the viewer, the user selects a string (or only right-clicks, or selects nothing) and chooses **`Edit in <editorName>`** from the context menu (key `C-c e`, `M-x edit-in-editor`). `editorName` is a setting (default `Emacs`). If no command is configured, the item becomes `Record Location for Editor`.
2. The Web core **turns the pointed place into a position in the original Markdown** (§4).
3. The app adds the absolute path and **the identity of the file version the viewer rendered** (SHA-256, modification time, size), and records it. If a fixed command is configured, it runs it (§7).
4. The editor fetches it with the socket's `get-location`, **verifies it**, and then moves (§6).

A virtual buffer (search results, for example) cannot be an edit target (there is no file the editor could open). The pointed position stays unchanged. Positions in files the viewer has not read, or in files under a warn path that are not remembered, are not handed to the editor.

## 4. Pointed place to original position (R1, R5)

- At render time, block elements (paragraphs, headings, list items, code, tables, quotes, and so on) keep the start and end offsets and the lines of the original Markdown (`data-source-start`, `data-source-end`, `data-source-line`, `data-source-end-line`).
- Only when the selected string is found at **exactly one place in the block's original text**, the precision is **`exact`** (that range).
- In any of the following cases, the precision is **`block`** (the whole block, or the whole of the blocks when the selection spans several), and the ambiguity is also shown on screen. **The position is never decided by guessing.**
  - Not found (because of emphasis, links or escapes, the visible string differs from the original).
  - Found in several places.
  - No selection (a right-click only, or the block at the top edge of the screen).
  - The selection spans several blocks.
- Columns are counted in **Unicode code points** (the same as Emacs character counts; unaffected by UTF-16 differences such as emoji). Lines are counted for CRLF, CR and LF alike. `expect` and the context have their line breaks normalized to LF.
- `expect` is limited to the first 500 code points (`expectTruncated`). The surrounding context is about 40 characters (it may cross lines).
- **The file identity is computed from the bytes handed to the viewer** (before conversion to a string, so a file containing invalid UTF-8 also matches the disk). Even after the file changes and the viewer reloads it, the identity of an already pointed position stays old (so the editor can tell the position is based on a stale view).
- Implementation: on the Web core side, `core/src/locate.ts`; on the app side, `FileFingerprint` and `LocationBuilder` in `app/macos/Sources/HyperBufKit`.

## 5. Location payload

`result.location` of the socket's `get-location`. **The canonical definition is [`protocol/schema/location.schema.json`](../../protocol/schema/location.schema.json)**; representative examples are in `protocol/examples/location*.json`.

| Field       | Content                                                                                                     |
| ----------- | ----------------------------------------------------------------------------------------------------------- |
| `v`         | Contract version (1)                                                                                        |
| `path`      | Absolute path of the file to edit                                                                           |
| `range`     | `start` / `end` (each with `line` and `column`; 1-based; columns are code points)                           |
| `precision` | `exact` or `block` (§4)                                                                                     |
| `expect`    | The original Markdown string that should be in that range. Only the beginning when long (`expectTruncated`) |
| `context`   | The strings immediately before and after the range (`before` / `after`)                                     |
| `file`      | Identity of the version the viewer rendered (`sha256`, `mtime`, `size`)                                     |
| `viewer`    | Viewer state (`selection`: the string that was selected, as displayed; `version`; `readAt`)                 |
| `markedAt`  | Time when "Edit in Emacs" was chosen (milliseconds since the epoch)                                         |

- Because the content includes parts of the document (`expect`, `context`), a query response requires a check of the connection source (same user) ([integration-protocol.md](integration-protocol.md) §3.6).
- `get-location` returns `null` when no position has been recorded yet. When there are several frames, it returns the one from **the frame that recorded the position**.
- The old PoC `get-location` (which returned the current view) is split off into `get-view`. `get-location` returns only the position the user pointed at.

## 6. Verification on the editor side (R2 to R4)

Emacs's `hyperbuf-visit-location` (`emacs/hyperbuf.el`) verifies the following, in this order, before moving. **On failure it neither moves nor offers to continue** (the user often has not noticed that something is fundamentally wrong, so this gives them a chance to assess the situation calmly).

1. **`stale`:** The SHA-256 of the file on disk differs from `file.sha256` (the version the viewer rendered).
2. **`mismatch`:** The position is outside the document, the string at that position differs from `expect` (only the beginning when it is truncated), or the surrounding context differs. **A position shifted by unsaved edits is also detected here** (the buffer contents are verified).
3. On failure: it shows a warning (`user-error`) and the details of the discrepancy (`*hyperbuf-mismatch*`: the string the viewer pointed at, the current string, the SHA-256 difference, what to do).
4. On success: it temporarily highlights the range and shows the string the viewer pointed at. For `block`, it says "the location is ambiguous, so the whole block is shown". When the pointed position is older than 10 minutes (`hyperbuf-location-max-age`), it adds a note to that effect.

The verification rules are shared in `protocol/examples/location-check.json` and checked by the Emacs conformance tests.

A file in a non-UTF-8 encoding (Shift-JIS, for example) is read by the viewer as UTF-8, so `expect` does not match and the result is `mismatch` (it stops with a warning and never moves to a wrong place).

## 7. Invoking the editor (permission design for running an external command)

The app runs only a configured **fixed command** to make the editor come and fetch. The settings are `editorName` and `editorCommand` in `config.json` ([configuration.md](../user/configuration.md)).

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

- The command is **only the fixed one the user wrote**. **No document content, selection, path or position is included in the arguments or the environment** (the editor fetches the position with `get-location`). There is no room for injection.
- It is run **without a shell**, with an argument array. The first element is an existing **absolute path to an executable** (a `PATH` search is not allowed). At most 16 arguments, each at most 1024 characters, without NUL. If these are not satisfied, the setting is ignored (the editor is not invoked).
- Standard input and output are not used. After the deadline (5 seconds) it is terminated.
- Without the setting, the editor is not invoked and the position is only recorded (use `M-x hyperbuf-visit-location` on the editor side).

## 8. Unverified and open items

- Keyboard-only position specification (a mark for selection). `C-c e` points at the block at the top edge of the screen when there is no selection.
- Making selections that span emphasis or links `exact` (currently `block`). Checking how often `block` occurs in real documents.
- Whether a signed, notarized app can run an external command (running a child process is not expected to be restricted even under the Hardened Runtime, but this is unconfirmed).
- Whether to make the payload format a public contract for editors other than Emacs. It is currently defined by `protocol/schema/location.schema.json`, but use with anything other than Emacs is not anticipated.
