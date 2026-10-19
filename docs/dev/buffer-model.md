# Buffer Model

This document defines the **buffer**, the central concept of HyperBuf, and the mechanisms that follow from it: the base directory, opening files, the scope of listing and search, the project root, the relation to frames, following external changes, and persistence.

Related documents:

- The overall interaction model (window splits, reference history, keys): [interaction-model.md](interaction-model.md)
- Access judgment when opening files (allow paths and warn paths): [file-access.md](file-access.md)
- The list of configuration keys: [configuration.md](../user/configuration.md)
- Session restore: [session-restore.md](session-restore.md)

## 1. Overview

Following Emacs, HyperBuf makes the **buffer** the protagonist.

- A **buffer** is an open document itself. It is separate from the view (window) and from the workspace (frame), and the same buffer can be shown in multiple windows.
- A buffer is identified by its **absolute path**. Regardless of where a document lives, `~/notes/a.md` and `/usr/share/doc/b.md` are opened the same way.
- The base of every operation is the **directory of the current buffer's file** (Emacs `default-directory`). The input field for opening files, listing, and search all start from here.
- There is **no** operation of "choosing a project". A project is merely a "root directory" computed from a buffer (§6).
- There is one session overall. At startup, the previous state is restored.

## 2. Buffers

### 2.1 Identity and kinds

| Kind                       | Identity                                                     | Example               |
| -------------------------- | ------------------------------------------------------------ | --------------------- |
| File buffer                | Absolute path (normalized with `realpath`; judged by target) | `~/notes/a.md`        |
| Virtual buffer (search)    | `*search: …*` (has the search's origin directory)            | `*search: foo*<docs>` |
| Virtual buffer (help etc.) | `*Help: …*` and the like                                     | `*Help: bindings*`    |

- Only `.md` files can be file buffers. Since HyperBuf is a viewer, it never creates a new file that does not exist.
- An anchor (`#heading`, `#line:N`) is not part of a buffer's identity. It is the position of an entry in the reference history.

### 2.2 Opening and closing

A buffer is created by the following operations (if it is already open, the operation switches to that buffer).

- `C-x C-f`, `C-x p f` (§5, §6)
- A link in a document
- "Open" from the CLI, Emacs, or the URL scheme ([integration-protocol.md](integration-protocol.md))
- Session restore (§9)

`C-x k` closes a buffer. The list of buffers is kept per frame (§7).

## 3. Buffer names and display

Identity is the absolute path (§2.1), but the **name** shown on screen follows the same idea as Emacs `uniquify`.

- **By default, the file name (basename)**. Example: `buffer-model.md`.
- **Only when several open buffers share the same name**, parent directories are added to tell them apart. The format follows the Emacs default (`post-forward-angle-brackets`): `name<distinguishing suffix>`. Examples: `README.md<docs>`, `README.md<emacs>`. The suffix is the shortest trailing part of the directory path that makes the names distinguishable (if that is not enough, it extends upward, as in `README.md<a/docs>`).
- Names are **dynamic**: when a buffer is opened or closed (`C-x k`), whether names collide changes, and the names change with it (as in Emacs). Identity is the absolute path, so history, sessions, and selections are not affected.
- There is no project unit, so names do not include one.
- Anchors are not added to names.
- **Virtual buffers** (`*search: …*`) carry the **short path of the search origin**: `*search: foo*<docs>` (the suffix is decided the same way as for files; if the origin is `~`, it is `<~>`). Each hit in the search results is shown as a path relative to the origin. `*Help: …*` is left as is.

### 3.1 Where names are shown

| Place                         | Display                                                                       |
| ----------------------------- | ----------------------------------------------------------------------------- |
| Window mode line              | `buffer-model.md  Top  L1  [History 2/5]`                                     |
| `C-x b` candidates            | Buffer names, most recently used first                                        |
| Echo area, errors             | Buffer name (when indicating a file, the absolute path abbreviated with `~/`) |
| Location (editor integration) | Absolute path                                                                 |

### 3.2 Keep the display minimal

HyperBuf respects the trimmed-down UI aesthetic of UNIX / Emacs and does not add to what is displayed.

- The name in the mode line is the buffer name only (no directory and no anchor attached). The `C-x b` candidates are also buffer names only.
- When you lose track of where you are, do as in Emacs: press `C-x C-f` and check (the input field starts from the base directory). After checking, return with `C-g`.
- For this reason, there are no tooltips and no command that displays the absolute path (`C-h f`).

## 4. Base directory (`default-directory`)

| Buffer                                    | Base directory                                 |
| ----------------------------------------- | ---------------------------------------------- |
| File buffer                               | The directory of that file                     |
| Virtual buffer (`*search: …*`)            | The search's origin directory                  |
| Virtual buffer (`*Help: …*` and the like) | Inherited from the buffer selected just before |
| No buffer (right after startup)           | The host (`~`)                                 |

When the minibuffer is opened, it uses the base of the buffer that was selected at that moment.

## 5. Opening a buffer (`C-x C-f`)

- The input field starts from the base directory (displayed abbreviated in `~/` form).
- The candidates are the **`.md` files and subdirectories** in the directory typed so far (hidden files only when the input starts with `.`).
- Input of `~/`, `../`, and absolute paths is supported. `TAB` completes.
- **A directory is not confirmed with `RET`**. Selecting a directory and pressing `RET` enters it (the input field ends with `/` and the candidates are updated).
- **A file is opened only when a `.md` file is specified**. A non-`.md` file or a nonexistent file is not opened; a message is shown.
- A path the user typed is the user's own intent, so **no access judgment is made** ([file-access.md](file-access.md)).
- Narrowing the candidates (fuzzy matching) covers **only the directory typed so far** (no recursion). Narrowing across levels is `C-x p f` (§6).
- Host contract: for completion in the input field, `listDirectory(dir)` returns a single level. It is separate from the recursive listing (`C-x p f`, search). The count is limited to 2000 entries; when exceeded, the result is cut off and the user is told.

### 5.1 Opening a directory

`hyperbuf <directory>` (the CLI, Finder's "Open With", drag and drop, `swift run HyperBuf <dir>`, and so on) opens that directory's **`index.md`, or `README.md` if there is none**. If neither exists, it opens the `C-x C-f` input field in that directory.

## 6. Scope of listing and search, and the project root

### 6.1 Recursive listing and full-text search

Both cover **only what is under the origin directory**.

- The **recursive listing `C-x p f`** and the **full-text search `M-s g` / `C-x p g`** scan recursively below the origin. The targets are only `*.md` files and directories; hidden files and `node_modules` are excluded. `.gitignore` is not interpreted. Symbolic-link directories are not entered.
- Safeguards:
  - `~` and `/` are **rejected** as recursive origins (a message is shown). In `C-x p f`, it falls back to the same single-level listing as `C-x C-f` and says so.
  - The recursive listing has **limits** of 20000 files and 3 seconds. Search results are limited to 200 entries; when exceeded, the result is cut off and the user is told.
  - It can be **canceled** (`C-g`).
  - On external disks and network volumes, enumeration does not hang, thanks to a **timeout**.
- **Reaching any file:** typing `../`, `~/`, or an absolute path into the `C-x p f` input switches the origin to that directory and lists below it recursively (after switching, it does not go back up). Files outside the origin can also be opened from the same input field. A selected (typed) file is not subject to access judgment, as with `C-x C-f`.
- The listing is displayed as paths relative to the origin.

### 6.2 The idea of the project root

As in Emacs `project.el`, **a project is merely a "root directory" derived from a buffer**. There is no state to select, open, or switch.

- **There is no correspondence with frames.** A frame is an independent workspace and is not tied to a project. The same frame may hold buffers from different projects. A project relates to a frame only through its buffers.
- Nothing that is saved (session, settings) contains a project. The root is computed each time from the buffer's file path. The root is not stored on the buffer and there is no cache (the number of steps up is only the depth of the path).

### 6.3 Finding the root

Starting from the buffer's base directory (§4), go up to parents, and make the **first directory that has a VCS marker** the root.

1. Markers: `.git` (a directory, or a file for worktrees and submodules), `.hg`, `.svn`, `.bzr`, `_darcs`, `.jj`.
2. The upward search **stops when it reaches `~` or `/`** (if there is no marker before that, it counts as not found). Even if `~` itself is a dotfiles repository, the whole host does not become the root. The same applies, as not found, when the base directory is `~` or `/` itself.
3. A directory in the ignore list (§6.4) is not made the root even if it has a marker (it is skipped and the search continues upward).
4. **If nothing is found, the base directory itself becomes the root.** Even in a place with no VCS where a folder was merely created, such as `~/Downloads/notes/`, its contents can be listed and searched.
5. The safeguards of §6.1 (`~` and `/` are not recursive origins; limits on count and time; `C-g`; timeout) **apply to the root as they are**. For example, when `~` is the base and becomes the root, it falls back to a single-level listing and says so.

The root of a virtual buffer is found by the same rules from its base directory (§4).

### 6.4 Ignore list (`projectIgnorePaths`)

For safety, **directories that must not be made the root** can be configured.

```json
{
  "projectIgnorePaths": ["~/work/wrapper"]
}
```

- Written as an absolute path or `~/…`. Symbolic links are resolved before matching. **Exact match** (only that directory itself; it has no effect on directories below it).
- A matching directory is skipped even if it has a marker, and the search continues upward. If nothing is found in the end, the result is the base directory itself, as in item 4 of §6.3.
- **The default is empty** (`~` and `/` are excluded as built-ins by item 2 of §6.3). As with `warnPaths`, when you write it, you specify the entire list.
- Invalid values (relative paths, wrong types) are ignored, and the reason is shown under "Configuration problems" in `C-h b`.

### 6.5 Host contract

Looking at the file system is the shell's role.

- `host.projectRoot(dir): Promise<string>` (returns an absolute path; if none is found, `dir` itself). On the Swift side, a dedicated type (`ProjectRoot`) in `HyperBufKit` is responsible, and it can be tested on its own.
- Checking markers is only a metadata check; file contents are not read (access judgment is not applied).

### 6.6 Commands

| Key       | Command                    | Behavior                                                                                                                                     |
| --------- | -------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| `C-x p f` | `project-find-file`        | Lists `*.md` files **under the root** recursively (§6.1)                                                                                     |
| `C-x p g` | `project-find-regexp`      | Full-text search **under the root** (results go to the virtual buffer `*search: …*`)                                                         |
| `C-x p b` | `project-switch-to-buffer` | Switches like `C-x b`, with only the **buffers of the current frame that have the same root as the current buffer** as candidates            |
| `C-x p k` | `project-kill-buffers`     | Closes the buffers in the same scope all at once. **Shows the number to be closed and asks for confirmation** (`y/n`; confirms even for one) |

- The input field's prompt shows the root (abbreviated in `~/` form). Example: `Find file in ~/work/foo/: `.
- The keys can be changed with the `keybindings` setting (individual assignments). There is no mechanism dedicated to `C-x p`.
- **Not provided:**
  - `C-x p p` (`project-switch-project`) and `C-x p K` (`project-forget-project`). There is no state to switch and no editing work, so the value is small.
  - `C-x p r` (replace), `C-x p c` (compile), `C-x p s` / `C-x p e` / `C-x p !` / `C-x p &` (shell), `C-x p v` (VC), `C-x p D` (Dired). Because of the view-only, no-external-command-execution policy.
  - `C-x p F` / `C-x p G` (including external). Unnecessary because `C-x p f` reaches external directories.
- `C-x p d` (`project-find-dir`) is undecided (§10).

### 6.7 `M-s g` and `C-x p g`

- `M-s g` (`search-project`) searches **under the base directory (`default-directory`)**. It is not pulled up to the root. `C-x p g` searches **under the root**. Both a narrow search and a wide search can be chosen by key.
- They use the same implementation (`host.search`); only the origin differs. Exclusions (hidden files, `node_modules`), limits, and cutoffs are shared.
- The search is a fixed-string search; regular expressions are not supported. It is named `project-find-regexp`, but the `M-x` description says so. The fact that `.gitignore` is not read is also written in the `M-x` description.

### 6.8 Per-buffer roots and frames

- The "same root" for `C-x p b` / `C-x p k` is determined by computing the root from each buffer's path and comparing. If a buffer has been moved or deleted, the parent of its path is examined. The number of buffers is small, so the cost is not a concern.
- **Only the buffers of the current frame are covered.** Buffers are kept per frame (§7). This differs from Emacs `project-kill-buffers`, which looks at all frames.

### 6.9 Branch name in the mode line

- If the buffer's project root (found as in §6.3; `projectIgnorePaths` also applies) has `.git`, the branch name is shown to the right of `[History N/M]` in the mode line. It can be turned off with the setting `modeLineVcsBranch` (default `true`).
- **No external command is executed.** The shell directly reads the first line of `.git/HEAD` (`VCSBranch`). For `ref: refs/heads/<name>`, it is `<name>`; for a 40- or 64-digit hexadecimal string (detached HEAD), it is the first 7 digits. If `.git` is a file (worktree, submodule), it reads the `HEAD` that `gitdir:` points to.
- The repository is treated as untrusted input: only regular files are read, up to the first 4096 bytes; names containing control characters are discarded; names longer than 80 characters are omitted. Display uses `textContent`.
- **Not shown:** a VCS name prefix, the file's modification state (the `-` / `:` / `@` of Emacs `vc-mode`), anything other than Git (`.hg` and so on), buffers without a project root, and virtual buffers. Knowing the modification state would need a computation equivalent to `git status`, which goes against the policy of not executing external commands.
- Updating is re-fetching only; `HEAD` is not watched. The host's `vcsBranch(dir)` is called when a buffer is displayed, switched, or reloaded, and when the app becomes active. A switch made in another tool is reflected when you return to the app.

## 7. Buffers and frames

Multiple Emacs frames (macOS windows) can be held. The intended use is to separate frames per parallel line of work.

- **1 frame = 1 `NSWindow` + 1 WKWebView + 1 Web core.** Each frame is an **independent workspace** with its own buffers, most-recently-used order, reference history, window splits, and minibuffer. The JS model cannot be shared across WebViews, so state is not synchronized between frames.
- Therefore, the `C-x b` candidates are only the buffers opened in that frame. The same file may be opened in several frames (the contents are held separately per frame, and each frame detects file updates).
- **Switching:** `Cmd-1`, `Cmd-2`, `Cmd-3` … bring the **open** frame with the corresponding slot number to the front. It is implemented as the shortcut for items in the Window menu (the macOS way), which lists the open frames (`HyperBuf [N]`, with a mark on the frontmost). It works even when the WebView has focus (it does not collide with Emacs-side keys). Nothing happens for a number that is not open (and the menu has no item for it). There is no dedicated Frame menu.
- **Slot numbers are fixed.** Closing a frame does not change the numbers of the other frames (closing frame 2 leaves frame 3 as `Cmd-3`). A new frame uses the smallest free number, and is created with `File > New Frame` (`Cmd-N`) or `C-x 5 2`.
- Keys matching Emacs operations are provided: `C-x 5 2` (create a frame), `C-x 5 o` (go to the next frame), `C-x 5 0` (close this frame), `C-x 5 1` (close the other frames). The Web core operates through the host contract (`frame`).
- The destination of an **external "open" request** (CLI, Emacs, URL scheme) is the **frame that was last active**.
- **The location recorded by "edit in editor"** (`get-location`) and `get-view` return those of the frame that recorded it, or the frame that was last active.
- **Remembered paths** ([file-access.md](file-access.md) §4) and settings are shared by all frames (managed on the host side).
- Memory: WebContent runs as a separate process per frame and is not shared. In measurements, **each additional frame adds about 140 to 150 MB** (about 190 MB for 1 frame, about 740 MB for 5 frames, about 1.2 GB for 8 frames). This is acceptable for use with 3 to 5 frames, so this configuration is adopted ([poc-frames-results.md](../history/poc-frames-results.md)).

## 8. Following changes to file contents

What needs watching is **only updates to the contents of documents currently displayed in a window**. The `C-x C-f` candidates, the `C-x p f` listing, and search scan when called, so they are not watched.

- **Method:** each displayed file and its parent directory are watched with `DispatchSource` (kqueue). It is **non-recursive**, so no noise reaches even documents directly under a repository that is being built, or documents directly under `~`. There is no load while idle (counting FSEvents under `~` for 20 seconds gave about 9 events per second; directly under a repository, this grows with updates to `.build/` and `node_modules/`).
- **Handling events:** events on the file or its parent directory are batched over a short time (about 50 ms), the path is `stat`-ed again, and compared with the existing `FileFingerprint`. If it changed, the file is re-read and re-rendered while keeping the reading position. If the inode changed because of the save method (writing to a temporary file and replacing, or renaming the original and writing anew), the watch is re-attached to the new file.
- **Buffers that are not displayed are not watched.** The default fd limit for a macOS GUI process is 256, and session restore can load hundreds of documents. When a buffer is displayed (`C-x b`, Back / Forward, restore), the file is re-read and updated if the contents differ (the host contract is unchanged; `readFile` is used).
- **Safety net:** when the app becomes active (on returning from another app), the displayed documents are checked again. This is insurance for when kqueue events do not arrive on network file systems or iCloud. Perfect tracking is not required.
- **When a file is deleted:** the displayed buffer is **left open, not closed**, and the window's mode line shows `(deleted; it may have been moved)`. If a file is recreated at the same path (for example by a replace-on-save), it is re-read automatically. A move is treated the same as a deletion (it is not tracked).
- The watch target is removed when the window changes what it displays (moves to another document, or the window is closed). When several frames display the same file, the host avoids duplicates.

### 8.1 Why moves are not tracked

There is no feature that follows a displayed file to its new path when it is moved or renamed. It is technically possible, since the current path can be obtained from the fd with `fcntl(F_GETPATH)`, but for these reasons:

- Depending on the save method, some operations merely look like a move (renaming the original file to `foo.md~` and writing a new one). There is a risk of following the wrong file.
- Moving to the trash means "delete" and must not be followed. If the destination is a warn path, the judgment would also have to be redone.
- To follow, the paths in the history, most-recently-used order, session, and selection of all windows would have to be rewritten together. For a move of a whole directory, documents that are not displayed cannot be followed, leaving it half-done.
- With the current policy (leave it as deleted, and reopen with `C-x C-f`), the practical trouble is small.

This will be considered when the need arises, for example if documents are frequently relocated by AI agents.

## 9. Session (persisting buffers)

- The session is saved as one file overall (not per project), as a **sequence of frames**. It is saved to `~/Library/Application Support/HyperBuf/session.json` (0600).
- At startup, all frames from last time are restored. If there is no saved data or it is broken, an empty screen with a single slot-1 frame shows "open with `C-x C-f`".
- When opening with `hyperbuf <file>`, that file is opened on top of the restored state (the destination frame is described in §7).
- When a frame is closed and it is not the last one, that frame's session is discarded (the same as Emacs `delete-frame`).
- For the save location, the file format, the scope of restore, the behavior of saving and restoring, and the handling of broken data, see [session-restore.md](session-restore.md).

## 10. Design decisions and open questions

**Why there is no project unit.** HyperBuf is a viewer for moving through many cross-referencing documents by keyboard. Documents do not stay within one project, and links point outside projects too. An operation to "open a project", and the settings, session, and access scope tied to it, would get in the way of this way of reading. So, as in Emacs, the buffer's location is the base, and a project is computed from a buffer only when needed.

**Undecided:**

- The handling of `C-x p d` (`project-find-dir`). It will be added after deciding how it fits with the rule of opening `index.md` / `README.md` when a directory is selected (§5.1).
- Simple support for `.gitignore`. A simple version that reads only the `.gitignore` directly under the root (not handling `!` and `**`) is under consideration. It will be considered when complaints about build output and vendored `.md` files getting mixed in increase.
- A way to specify the frame for an external "open" request (`--frame N`, `--new-frame`). To be added later.
