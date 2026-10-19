# Changelog

All notable changes to HyperBuf are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versions are not yet strictly semantic: 0.x releases may change behavior between minor versions.

## [Unreleased]

### Added

- Project roots, as in Emacs `project.el`: `C-x p f` now lists Markdown files under the nearest ancestor directory that has a VCS marker (`.git`, `.hg`, `.svn`, `.bzr`, `_darcs`, `.jj`), or under the buffer's directory if there is none. `~` and `/` are never roots. Directories that must not become a root can be listed in `projectIgnorePaths`.
- `C-x p g` (`project-find-regexp`): search all files under the project root (plain text for now; `.gitignore` is not read). `M-s g` still searches under the buffer's directory.
- `C-x p b` (`project-switch-to-buffer`) and `C-x p k` (`project-kill-buffers`): switch to, or kill after confirming, the buffers of the current frame that belong to the same project root.

### Removed

- The `hyperbuf --project` option. It was already ignored since HyperBuf has no per-window project; passing it is now a usage error.

## [0.1.1] - 2026-10-14

Changes since 0.1.0, mostly from the feedback of the initial private distribution.

### Added

- Window resizing, as in Emacs: `C-x ^` (enlarge window), `C-x -` (`shrink-window-if-larger-than-buffer`), `C-x }` (enlarge window horizontally) and `C-x {` (shrink window horizontally). The sizes are saved in the session.
- Dragging the mode line resizes windows: dragging the mode line moves the border below the window (vertical); dragging its right end moves the border on the right (horizontal).
- The cursor keys `←` / `→` go back / forward in the reference history, in addition to `C-b` / `C-f`.
- A new `appearance` setting in `config.json` (`"system"` by default, `"light"` or `"dark"`) fixes the app to light or dark regardless of the OS setting. See `docs/user/configuration.md`.
- A new `alpha` setting in `config.json`, `[active, inactive]` in percent (for example `[80, 65]`), makes the whole frame translucent, like `(set-frame-parameter nil 'alpha '(80 65))` in Emacs. It is ignored while the macOS accessibility option Reduce Transparency is on. See `docs/user/configuration.md`.
- `M-x count-words` (`M-=`) counts the lines, words and characters of the selected text, or of the whole document, and shows them in the echo area (for example `Region has 3 lines, 42 words, 210 characters (180 without whitespace)`). It counts the displayed text, not the Markdown source. A live count in the mode line is intentionally not planned.

### Changed

- The `.dmg` now includes `CHANGELOG.md`, so you can see what changed in each version.
- **All UI text is now fixed to English** and is not localized: menus, mode line, echo area, minibuffer prompts, command descriptions (`M-x`, `C-h b`), error messages, `hyperbuf` CLI output, and the messages and docstrings of the Emacs package (`emacs/`). Documents, file names and input stay fully international. See `docs/dev/interaction-model.md` §6b.
- The separate Frame menu is merged into the Window menu, following macOS conventions. The Window menu lists the open frames as `HyperBuf [N]` with `Cmd-1`…`Cmd-9`, and the front one is checked. `Cmd-N` for a frame that is not open now does nothing; create a new frame with `File > New Frame` or `C-x 5 2`.
- When the OS appearance (light / dark) changes while the app is running, Mermaid diagrams are now redrawn with the new theme. Before, they kept the old colors and could become unreadable. The reading position is kept.
- The status line at the bottom of the frame no longer wraps; its right side is clipped on narrow windows.
- Opening a file from Emacs or the CLI with a line or anchor no longer adds a history entry when the file is already shown in the selected window; only the position is replaced (like `goto-line`).
- The mode line shows only the buffer name (no `#anchor` suffix).

### Fixed

- Opening the same file repeatedly from Emacs or the CLI piled up reference-history entries such as `FileName.md#line:1`, which looked like separate buffers in the mode line and in Back / Forward.
- Splitting a small window left the contents overflowing onto the windows below, the minibuffer and the status line (the bottom padding of a window acted as its minimum height). This also affected 0.1.0 on small screens.
- `C-x 3` followed by `C-x 1` could leave the remaining window at half width.

## [0.1.0] - 2026-10-12

First release (Developer ID signed and notarized, Universal build), distributed privately to a few people for feedback.
