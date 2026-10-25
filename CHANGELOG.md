# Changelog

All notable changes to HyperBuf are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versions are not yet strictly semantic: 0.x releases may change behavior between minor versions.

## [Unreleased]

### Added

- The frame title now shows the file name and its directory, relative to the project root when there is one (`README.md — hyperbuf/docs/user`). The new setting `frameTitleFormat` chooses `"default"`, `"simple"` (the old fixed `HyperBuf`) or `"filename"`.

- A two-finger horizontal swipe on the trackpad (right = back, left = forward) and the mouse back / forward buttons now move in the reference history. A swipe over a horizontally scrollable table or code block scrolls it instead. The new setting `gestureNavigation` (default `true`) turns the gestures off.

### Changed

- The About window is now a quiet scrolling story about Emacs, Markdown and hyperbuf, with the icon, the name (`hyperbuf`) and the version on the left and the Apache License 2.0 notice along the bottom. The text scrolls slowly and brakes to a stop at the closing lines. `SPC` starts / stops it, `C-n` / `C-f` and `C-p` / `C-b` (or Down / Up) jump to the next / previous chapter.

### Fixed

- The Up / Down arrow keys now scroll the selected window by a line (like `C-p` / `C-n`). They used to be unbound and relied on native scrolling, which stopped working when focus was not on the document, for example after moving through the history or right after opening a document.

### Security

- Updated KaTeX 0.16.47 → 0.18.11 (fixes GHSA-238p-pmpm-9mq7, a prototype-pollution gadget that could bypass `trust`; HyperBuf already sets `trust: false` and sanitizes the output, so it was not exploitable here) and Mermaid 12.1.0 → 12.2.0.

## [0.1.2] - 2026-10-19

Changes since 0.1.1.

### Added

- Project roots, as in Emacs `project.el`: `C-x p f` now lists Markdown files under the nearest ancestor directory that has a VCS marker (`.git`, `.hg`, `.svn`, `.bzr`, `_darcs`, `.jj`), or under the buffer's directory if there is none. `~` and `/` are never roots. Directories that must not become a root can be listed in `projectIgnorePaths`.
- `C-x p g` (`project-find-regexp`): search all files under the project root (plain text for now; `.gitignore` is not read). `M-s g` still searches under the buffer's directory.
- `C-x p b` (`project-switch-to-buffer`) and `C-x p k` (`project-kill-buffers`): switch to, or kill after confirming, the buffers of the current frame that belong to the same project root.
- The mode line shows the current Git branch (the short hash for a detached HEAD) to the right of `[History N/M]` when the buffer's project root is a Git repository. It reads `.git/HEAD` directly and runs no external command, so the file's modification state is not shown. Set `modeLineVcsBranch` to `false` to hide it.
- `C-a` / `C-e` (`beginning-of-history` / `end-of-history`): jump to the first / last entry of the window's reference history.

### Changed

- The `THIRD-PARTY-NOTICES.txt` shown by `Show Third-Party Licenses` is now written in English, including its header and notes, in line with the rule that all text the app itself shows is English.
- When HyperBuf is not running, `hyperbuf-open` (Emacs) now launches it with `hyperbuf://ping`, waits for the socket (new setting `hyperbuf-launch-timeout`, 15 seconds by default) and sends the open request over the socket, like the `hyperbuf` command. The result (opened, refused, timed out) now comes back to Emacs, and a file outside the allowed paths is judged by the same rules as for the command line instead of asking for the extra URL-scheme confirmation.

### Fixed

- The usage text of `hyperbuf --wait` no longer says "files outside the project" (there are no projects any more); it now says "files under a warn path".
- When a request from the command line or Emacs waits for a confirmation (a warn path) and times out, the app now shows `Integration: request timed out` and closes the prompt. Before, the message was overwritten by `Not opened because it is a warn path`, so a timeout looked like a refusal.

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
