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

### 4.1 Structure

- Each **window** has a "list + current position", like a browser history.
- An entry is `{buffer, anchor, scroll offset}`.
- If a new reference is made after Back, the entries beyond the current position are discarded (as in a browser).
- A reference identical to the current entry (the same anchor of the same document) is not pushed again.
- The history is saved in the session up to 100 entries per window (when there are more, it is cut on the older side, keeping the newer side that includes the current position).

### 4.2 Operations that push an entry

| Operation                                                 | Pushed onto history                                       |
| --------------------------------------------------------- | --------------------------------------------------------- |
| Following an in-document or cross-document link           | Pushed                                                    |
| Jumping to a heading chosen with `C-c j` (`goto-heading`) | Pushed                                                    |
| Moving between headings, such as `C-c C-n`                | Not pushed (only the current entry's position is updated) |
| Opening from a full-text search result                    | Pushed                                                    |
| Showing another buffer with `C-x b` / `C-x C-f`           | Pushed                                                    |
| Normal scrolling                                          | Not pushed (only the current entry's position is updated) |
| In-document search (`C-s`)                                | Not pushed                                                |

#### 4.2.1 Principle: moving around inside one document does not disturb the history

The history records **references** (a link followed, a heading or line chosen by name, a buffer shown), not **reading movements**. Scrolling, `C-s` / `C-r`, and heading movement with `C-c C-n` and friends can be done freely inside a document, in any amount, and the history stays exactly as it was: no entry is added, the entries after the current one are not discarded, and `[History N/M]` does not change.

This is a deliberate part of the model, because it makes Back / Forward simple to predict:

- One `C-b` always means "return to the previous reference", no matter how far the reader scrolled or how many searches were made in between.
- Searching a long document for a word is safe: it cannot bury the reference the reader came from, or throw away the entries they could go Forward to.
- The reader only has to know one rule to know what is in the history: **a place the document itself pointed to, or the reader named, is an entry; everything else is just reading.**

Anything that would record positions inside a document (a second, finer tier of history) breaks this simplicity, and was considered and not adopted ([two-tier-history-considered.md](../history/two-tier-history-considered.md)). New navigation features should follow the same principle: if a movement is a continuous reading action within the current document, it does not push an entry.

### 4.3 When a window is split

The history of the original window is copied to the new window (similar to duplicating a browser tab). After that, the history is independent per window.

### 4.4 Back / Forward keys

- **`C-b` / `C-f`** are Back / Forward. Just as `C-f` / `C-b` in editing move through the "flow of characters", HyperBuf reuses them to move through the "flow of references".
- **`C-a` / `C-e`** move to the first / last entry of the history (`beginning-of-history` / `end-of-history`). They extend `C-b` / `C-f` the way beginning / end of line extend them; if already at the first / last entry, the minibuffer says so.
- `Cmd+[` / `Cmd+]` are also available as macOS aliases.
- The cursor keys `←` / `→` are also assigned as aliases (for users unfamiliar with Emacs; combinations with modifier keys are not assigned).
- **Gestures** (`gestureNavigation`, default on): a two-finger horizontal swipe (right = Back, left = Forward) and the mouse back / forward buttons run the same `back` / `forward` commands on the window under the pointer. They are implemented in the Web core (`core/src/ui/gesture.ts`) from `wheel` / `mouseup` events, not with WebKit's `allowsBackForwardNavigationGestures`, because the reference history is the Web core's. Only the last 250 ms of movement is judged, and vertical movement in it counts against the swipe (a tilted vertical scroll does not navigate). A swipe fires once: its inertia tail stays locked until the wheel events stop (200 ms), unless the movement speeds up again or turns around inside the tail, which is taken as a new swipe (so swipes can be repeated quickly to walk through the history). A swipe that starts over horizontally scrollable content is left to that content. The direction assumes "Natural scrolling"; JS cannot see the system setting.
- Vertical movement (`C-n` / `C-p` / `C-v` / `M-v`) is within the document (space), and `C-f` / `C-b` is the flow of references (time).
- The `C-c` prefix is assigned to markdown-mode's outline-mode-style heading movement (`C-c C-n` / `C-c C-p` / `C-c C-f` / `C-c C-b` / `C-c C-u`), and is not used for Back / Forward.
- **`M-f` / `M-b` are intentionally unassigned.** A two-tier history (`C-f` / `C-b` for positions inside a document, `M-f` / `M-b` for references) was considered and not adopted, because the model became too complex for readers to predict ([two-tier-history-considered.md](../history/two-tier-history-considered.md)).

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

- The granularity of the history: whether to merge consecutive anchor movements within the same document into one entry (currently, one entry per anchor).
- Extension mechanisms.
