# Interaction model (window / frame / reference history / input)

The mechanisms for displaying and moving between buffers: windows, frames, reference history and input. This is a logical model independent of the UI and of implementation technology, and the Web core (`core/`) implements it.

Related documents:

- Definition of a buffer (the document itself), its name, the base directory, and buffers per frame: [buffer-model.md](buffer-model.md)
- List of key bindings (generated): [keybindings.md](../user/keybindings.md)
- Session restore: [session-restore.md](session-restore.md)
- UI language and conventions: [ui-conventions.md](ui-conventions.md)

## 1. Terms and model

| Concept | Definition                                                                                                                                                      |
| ------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Buffer  | An open document. It holds no view position ([buffer-model.md](buffer-model.md)). There are also **virtual buffers** that have no file (§5).                    |
| Window  | A leaf of the split tree. It **shows one buffer** and holds the viewing position (scroll, anchor) and the **reference history**.                                |
| Frame   | Corresponds to one macOS window. An independent workspace with a list of buffers, a split tree and a "selected window" ([buffer-model.md](buffer-model.md) §7). |

Relationships:

```
Frame* ─┬─ Buffer* (one per open document)
        └─ split tree ── Window* ──→ Buffer (reference)
                           └─ viewing position + reference history (per window)
```

- The same buffer can be shown in multiple windows. The viewing position is independent per window.
- Viewing involves no editing, so there is no point / mark / modified state like an Emacs buffer has.
- Candidates for `C-x b` are ordered by most recently used (MRU). This order is managed separately from the reference history.

## 2. Window splitting and size

- A node of the split tree is either a "split (direction, ratio, children)" or a "window (leaf)".
- `C-x 2` / `C-x 3` replace a leaf with a split, and `C-x 0` / `C-x 1` remove leaves. `C-x o` moves to the next window.
- The size of a window (the split ratio) is changed in one of two ways.
  - `C-x ^` (enlarge vertically), `C-x }` (enlarge horizontally), `C-x {` (shrink horizontally), `C-x -` (`shrink-window-if-larger-than-buffer`: shrinks a window that is larger than its document to the height that just fits the document; does nothing if the document is larger). One operation changes the size by 48px vertically and 80px horizontally; prefix arguments are not supported.
  - Dragging the mode line (the body drags the boundary below it (vertical only), and the right edge drags the boundary on the right (horizontal only), as in Emacs).
- The ratio is saved in the session ([session-restore.md](session-restore.md)).
- When a window is split, the reference history of the original window is copied to the new window (§4.3).

## 3. Viewing position

A window represents its position in one of the following ways.

- **Anchor**: a semantic position in the document, such as a heading ID. `path#heading`, `path#line:N` (line anchor; §5).
- **Scroll offset**: a position relative to an anchor.

When a document is re-rendered because the file was updated, the viewing position is kept relative to an element with an id near the top edge of the screen and the offset from it ([buffer-model.md](buffer-model.md) §8).

When an `open` with a position from an external integration (CLI, Emacs) points to the document already shown, it does not push onto the reference history and only replaces the position (the same as Emacs `goto-line`). If it points to a different document, it is pushed onto the history as usual. The mode line shows only the buffer name (not the anchor).

## 4. Reference history (Back / Forward)

Back / Forward move backward and forward through the reference history. A buffer switch is also pushed onto the history as a reference.

The history has **two tiers**, like Emacs widens the unit of a motion with a modifier key (`C-f` → `M-f`):

- **Entry** (coarse): a reference to a place, made by following a link, jumping to a heading, switching buffers, and so on. Moved with `M-b` / `M-f`.
- **Stop** (fine): a position inside one entry that the reader left with a large jump (the way Emacs pushes the mark before a jump). Moved with `C-b` / `C-f`, which cross over to the neighboring entry when the stops of the current entry run out.

### 4.1 Structure

- Each **window** has a "list + current position", like a browser history.
- An entry is `{buffer, anchor, stops, current stop}`. `stops` is a list of positions inside the entry (§4.1.1), and the entry remembers which stop is current.
- If a new reference is made after Back, the entries beyond the current position are discarded (as in a browser).
- A reference identical to the current entry (the same anchor of the same document) is not pushed again.
- The history is saved in the session up to 100 entries per window (when there are more, it is cut on the older side, keeping the newer side that includes the current position).

#### 4.1.1 Stops

- A stop is `{line, heading, headingOffset, context, scroll}`: the source line at the top of the screen (the same value as `L40` in the mode line), the ID of the heading it is under and its distance in lines from that heading, a short **context** (§4.1.2) — both used to find that place again after the file changed — and the pixel scroll offset, used only as a fallback where there is no line mapping (virtual buffers). Lines are preferred because pixel offsets drift when the window is resized.
- A new entry starts with a single stop (the top of its anchor). **The current stop follows the live scroll position**: ordinary scrolling only updates it, so scrolling never creates stops.
- A **jump** (§4.2.1) freezes the current stop at the place the reader left, appends a new stop for the destination and makes it current. Stops after the current one are discarded first, but **only within this entry**; entries after the current entry are kept (so moving around inside a document never destroys the forward entries).
- A jump that lands less than one screen away from the current stop does not create a stop; the current stop is just updated.
- Each entry keeps at most 20 stops; the oldest are dropped first.

#### 4.1.2 Following changes to the file

A line number alone drifts when the file is edited elsewhere (typically in Emacs while it is read here). A stop therefore carries a **context**, and is relocated whenever the buffer's text is replaced.

- **Context:** up to 3 non-blank lines starting at the stop's line, each trimmed to 80 characters. Lines too short to identify a place (fewer than 4 non-space characters, such as `---` or `}`) are skipped. A stop whose line has no usable context keeps only its line and the nearest heading ID (below).
- **When:** in the model, at the moment a buffer's text is replaced with different content (`openBuffer`), for the stops of every window in the frame that refer to that buffer. This covers both a displayed document updated by the watcher and a hidden document re-read when it is shown again ([buffer-model.md](buffer-model.md) §8). The old text is not needed, so it is not kept; only the new text and the stored contexts are compared.
- **How**, in order, per stop:
  1. If the stop's context still matches at its line, nothing changes (the common case, and the cost is one comparison).
  2. Otherwise search the new text for the context and take the match **nearest to the old line**.
  3. If there is none, fall back to the stop's stored heading, keeping the stored distance in lines from it, clamped to the section.
  4. If that heading is gone too, keep the old line clamped to the end of the document.
- A relocation is silent; it never adds or removes a stop and never moves the reader's current view by itself. The currently displayed position of a window keeps being followed by the existing mechanism ([§3](#3-viewing-position)); only the stored stops are relocated, and the current stop's context is refreshed after the re-render.
- **Saved in the session**, so a stop also survives a file edited while the app was not running, which keeping the old text could not do. It costs about 250 bytes per stop (at most 20 stops × 100 entries per window in the worst case).
- **Known limits:** when the same lines repeat (for example a table of identical rows) step 2 can pick a neighbor; the nearest-match rule keeps the error small. A text rewritten wholesale falls to step 3 or 4. Line anchors (`#line:N`, §5) are line numbers by definition and are not relocated.
- **Rejected alternatives:** keeping the previous text per buffer and diffing it (memory grows with every restored buffer, cannot help a hidden buffer edited while the app was closed, and needs a line diff that is more than the current `firstChangedLine`); keeping only the line number (drifts on every edit above the stop).

### 4.2 Operations that push an entry

| Operation                                                 | Pushed onto history                                       |
| --------------------------------------------------------- | --------------------------------------------------------- |
| Following an in-document or cross-document link           | Pushed                                                    |
| Jumping to a heading chosen with `C-c j` (`goto-heading`) | Pushed                                                    |
| Moving between headings, such as `C-c C-n`                | Not pushed (only the current entry's position is updated) |
| Opening from a full-text search result                    | Pushed                                                    |
| Showing another buffer with `C-x b` / `C-x C-f`           | Pushed                                                    |
| Normal scrolling                                          | Not pushed (only the current entry's position is updated) |
| In-document search (`C-s`)                                | Not pushed as an entry (may create a stop, §4.2.1)        |

#### 4.2.1 Operations that create a stop

Only large movements inside the current document create a stop; the origin of the movement is what is remembered.

| Operation                                                              | Creates a stop                                       |
| ---------------------------------------------------------------------- | ---------------------------------------------------- |
| Leaving `C-s` / `C-r` by accepting the match (`RET`, or any other key) | Yes. `C-g` restores the position and creates nothing |
| `M-<` / `M->`                                                          | Yes                                                  |
| `M-g g` (`goto-line`)                                                  | Yes                                                  |
| Heading movement (`C-c C-n` / `C-p` / `C-u` / `C-f` / `C-b`)           | Yes (still not pushed as an entry)                   |
| `C-v` / `M-v` / `SPC` / `DEL` / `C-n` / `C-p`, wheel, trackpad         | No                                                   |
| Dragging the scroll bar, mouse-driven jumps                            | No (first version; may be added later)               |
| A re-render caused by a file update                                    | No (the position is kept, §3)                        |

### 4.3 When a window is split

The history of the original window is copied to the new window (similar to duplicating a browser tab). After that, the history is independent per window.

### 4.4 Back / Forward keys

As in Emacs, the modifier key widens the unit: `C-f` / `C-b` is the fine unit, `M-f` / `M-b` the meaningful unit.

- **`C-b` / `C-f`** (`back-position` / `forward-position`) move one **stop** back / forward. Just as `C-f` / `C-b` in editing move through the "flow of characters", HyperBuf uses them to move through the finest "flow of references".
  - At the first stop of an entry, `C-b` crosses over to the previous entry and lands on its **last** stop (where the reader left it). At the last stop, `C-f` crosses over to the next entry and lands on its **first** stop. The reader never has to switch keys to get past an entry boundary.
  - At the very beginning / end of the whole history, the echo area says `Beginning of history` / `End of history`.
- **`M-b` / `M-f`** (`back` / `forward`, the existing commands) move one **entry** back / forward, i.e. to the previous / next document or heading reference. The destination entry is shown at the stop it remembers (the one that was current when the reader left it).
- **`C-a` / `C-e`** keep moving to the first / last **entry** of the history (`beginning-of-history` / `end-of-history`); if already there, the minibuffer says so. They extend `M-b` / `M-f` the way beginning / end of line extend a motion.
- `Cmd+[` / `Cmd+]` are the macOS aliases of `M-b` / `M-f` (entry unit, like a browser's Back / Forward).
- The cursor keys `←` / `→` are aliases of `C-b` / `C-f` (stop unit; for users unfamiliar with Emacs; combinations with modifier keys are not assigned).
- Vertical movement (`C-n` / `C-p` / `C-v` / `M-v`) is within the document (space); `C-f` / `C-b` / `M-f` / `M-b` is the flow of references (time). Forward in time is not "down": a `C-f` can land higher in the same document.
- The `C-c` prefix is assigned to markdown-mode's outline-mode-style heading movement (`C-c C-n` / `C-c C-p` / `C-c C-f` / `C-c C-b` / `C-c C-u`), and is not used for Back / Forward.
- Keys bound by name in `config.json` keep their meaning: `back` / `forward` stay the entry-unit commands. Only the default bindings of `C-b` / `C-f` change (they were `back` / `forward`, an incompatible change noted in `CHANGELOG.md`).
- The mode line `[History N/M]` still counts entries. Stops are not shown.

## 5. Virtual buffers and line anchors

### 5.1 Virtual buffers

- **Buffers that do not correspond to a file.** The content is generated by the app. The name is `*…*` (the same convention as Emacs `*grep*` and `*Help*`). Examples: search results `*search: query*`, help `*Help: …*`.
- Treated like normal buffers. They can be shown in a window, are pushed onto the reference history, can be moved through with Back / Forward, and appear in the `C-x b` candidates (MRU). Links in the content can jump to real files.
- Not watched as files. Regenerating with the same name replaces the content (a re-search). Not saved in the session.
- The goal is to fit result screens into the existing interaction model, without building a dedicated mechanism for them.

### 5.2 Line anchors

- `path#line:N` points to line N of the original Markdown (the nearest block at or before it). It is opened through the same route as a heading anchor (`path#heading`).
- It is used for jumping to the matching line from search results, and for "open with a file and line" in the CLI / Emacs integration ([integration-protocol.md](integration-protocol.md)).

## 6. Input and commands

- Every operation is defined as a **named command**, and a keymap is a mapping from key sequences to commands. `M-x` runs a command by name.
- Prefixes (such as `C-x`) are handled by a state machine. While waiting for input, the intermediate state is shown on screen.
- Input for search, `C-x b` candidate selection, `M-x` and the like is done **in the minibuffer at the bottom of the frame, without showing a dialog**.
- When the minibuffer has focus, its input keymap takes priority. `C-f` / `C-b` and the like go back to character movement, so command keys do not conflict with text input (the same behavior as the Emacs minibuffer).
- Users can change the keymap (`keybindings` in `config.json`; [configuration.md](../user/configuration.md)).

### 6.1 The minibuffer and Japanese input (IME)

Notes for using incremental search while converting Japanese in a WKWebView input field (`<input>`). These cannot be reproduced with synthetic events in automated tests and were found on a real device.

- **The confirming Enter arrives with `keyCode 229`** (in WebKit, it comes after the composition has been committed). Treating it as `RET` makes confirmation and exit happen at once. In the minibuffer, Enter / ESC with `isComposing` or `keyCode 229` is ignored (except with Ctrl, Meta or Alt). An Enter during conversion only confirms, and the next Enter exits.
- **On confirmation, the input arrives twice, as "empty → confirmed string"**. If the memory of the "current match" is tied to the search term, it is lost at the empty moment and returns to the first match. The base position for searching again is kept separately from the search term.
- **During composition input (`InputEvent.isComposing`), the base position is not moved.** If it were dragged by the match for an intermediate "さ" in the middle of romaji input, the converted word would be searched from after that position.
- **Creating or clearing a selection in the document takes focus away from the input field** (WKWebView). The highlight during input is drawn only with the CSS Custom Highlight API, and the selection is made after confirmation.

### 6.2 `count-words` (`M-=`)

Shows the number of lines, words and characters of the selection (the whole document if there is none) in the echo area.

- Example: `Region has 3 lines, 42 words, 210 characters (180 without whitespace)` (without a selection, `Buffer has …`).
- **What is counted is the displayed text (after rendering)**, not the original Markdown. As a viewer, appearance takes priority. Markdown symbols, URLs, images and diagrams (SVG) are not counted; code blocks, table cells, link text and math are counted. To measure the original Markdown, use Emacs `count-words`.
- Lines are the number of non-empty lines (a paragraph, a list item, a table row and a line of code each count as one line). Words follow `Intl.Segmenter` word segmentation (dictionary-based for Japanese and similar). Characters are the number of code points, including one newline for each line break between lines and excluding blank lines. The number in parentheses counts the characters with all whitespace (newlines included) removed.
- **Showing the character count of the selection in the mode line in real time is not implemented.** This follows the Emacs culture that a minimal UI is enough. Count with `M-=` when needed.

## 7. Design decisions and open questions

**The direction is not to show a cursor in the viewing screen.** How to select text for copying will be considered separately.

**Undecided:**

- Whether the heading movement of `C-c C-n` and friends should also be reachable as a "chapter" step by `M-f` / `M-b` (currently they only create stops, §4.2.1).
- Whether mouse-driven jumps (scroll bar drag) should create stops.
- The granularity of entries: whether to merge consecutive anchor movements within the same document into one entry (currently, one entry per anchor).
- The session format for stops (a new version with a fallback for old files; the limits go in [session-restore.md](session-restore.md) when implemented).
- The numbers in §4.1.2 (3 context lines, 80 characters, 4-character minimum) are first guesses. Measure the relocation accuracy on `fixtures/` with edited copies, and the cost on a large document, before fixing them.
- Whether the heading ID in step 3 is enough on its own, or the stop should also keep the heading's text (IDs derive from the text, so a renamed heading is lost either way).
- Extension mechanisms.
