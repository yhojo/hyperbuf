# UI Language and Conventions

The language of the text the app shows, and how the macOS conventions and the Emacs conventions are divided. For the interaction model, see [interaction-model.md](interaction-model.md).

## 1. UI text is fixed to English

UI text is fixed to English (not localized).

- This covers all text the app shows: menus, the mode line, the echo area, minibuffer prompts, command descriptions (`M-x`, `C-h b`), confirmation and error messages, the CLI's usage and errors, and the messages and docstrings of the Emacs package (`emacs/`).
- Reasons:
  - The Emacs vocabulary (buffer / window / frame / mode line / minibuffer / echo area) is English, and matches the key and command names.
  - It makes it easy to search and to share knowledge from around the world.
  - Two languages of text are not maintained (with a small team, this keeps them from drifting apart).
- **The content handled (document bodies, file names, anchors, search terms, and input in the minibuffer) is internationalized** (including Japanese). Only the app's own text is fixed.
- `.lproj` / `.strings` / `NSLocalizedString` are not used. New text is written in English from the start (Japanese text is not hard-coded).
- The standard UI shown by the OS (such as the open-file panel) follows the system locale.

## 2. Separating the macOS and Emacs conventions by place

| Place                                                             | Convention       | Specifics                                                                                                                                                              |
| ----------------------------------------------------------------- | ---------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Menu bar, dialogs, context menus                                  | macOS            | The standard structure (App / File / Edit / Window) and standard shortcuts (`Cmd-N`, `Cmd-W`, `Cmd-M`, and so on). Text uses macOS English style (Title Case)          |
| Switching frames (macOS windows)                                  | macOS            | There is no dedicated menu; the Window menu lists the open frames with `Cmd-1` to `Cmd-9` (the frontmost is marked). Nothing happens for a number that is not open     |
| Inside a frame (mode line, echo area, minibuffer, key operations) | Emacs            | The `C-x …` / `M-x` keys, command names, and terms (buffer / window / frame). Echo messages follow Emacs style (start with a capital letter, no period at the end)     |
| Integration with the outside (CLI, `hyperbuf://`, Emacs package)  | Both conventions | The CLI follows UNIX conventions (usage, exit codes). The Emacs package follows Emacs conventions (`user-error`; the first line of a docstring is a complete sentence) |

- Rule of thumb: **the menu bar and dialogs are macOS; inside a frame is Emacs.** Cmd-key shortcuts are used for the macOS standard and do not collide with Emacs keys (`C- / M-`).
- **The terminology mismatch is accepted.** An Emacs frame is a "window" on macOS, so what the Window menu lists is frames. Menus use macOS words; help and documents are written in Emacs words.
- The display of Window menu items (`HyperBuf [N]`) is, for the time being, the same as the window title. The ideal form is still under consideration.

## 3. Language of documents

- `README.md`, `docs/user/` and `docs/dev/` are written in English, like the UI text and `emacs/`. A form like Emacs info, with translations following the locale added later, is desirable for the user documents, but no plan has been decided.
- `docs/history/` keeps the records in Japanese, as they were at the time, with an English summary in its `README.md`.
- Source code comments, test names and the output of the repository scripts are still mostly Japanese; new ones may be written in English.
