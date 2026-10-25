# Configuration (config.json)

All the settings you write live in a single file.

```
~/Library/Application Support/HyperBuf/config.json
```

- If the file does not exist, everything stays at its defaults. The app reads it at startup (restart the app after changing it).
- Write it in JSON. **Invalid entries are ignored, and the reason is reported** (in a message at startup and in the `C-h b` list).
- You write the settings yourself. The app never rewrites the configuration file.
- `Show Config File in Finder` in the app menu shows `config.json` in Finder (or its folder if the file does not exist).

## List of configuration keys

| Key                      | Type                | Default                          | Description                                                   |
| ------------------------ | ------------------- | -------------------------------- | ------------------------------------------------------------- |
| `appearance`             | string              | `"system"`                       | [Appearance](#appearance-appearance)                          |
| `alpha`                  | array of 2 integers | `[100, 100]`                     | [Frame opacity](#frame-opacity-alpha)                         |
| `frameTitleFormat`       | string              | `"default"`                      | [Frame title](#frame-title-frametitleformat)                  |
| `mathUnescapeUnderscore` | boolean             | `true`                           | [Document display](#document-display)                         |
| `followUpdates`          | boolean             | `false`                          | [Document display](#document-display)                         |
| `modeLineVcsBranch`      | boolean             | `true`                           | [Project root](#project-root)                                 |
| `gestureNavigation`      | boolean             | `true`                           | [Gestures](#gestures-gesturenavigation)                       |
| `restoreSession`         | boolean             | `true`                           | [Restoring the previous state](#restoring-the-previous-state) |
| `warnPaths`              | array of strings    | built-in list (see below)        | [File access](#file-access)                                   |
| `allowPaths`             | array of strings    | built-in list (see below)        | [File access](#file-access)                                   |
| `projectIgnorePaths`     | array of strings    | `[]`                             | [Project root](#project-root)                                 |
| `trustedUrls`            | array of strings    | `[]`                             | [External links](#external-links)                             |
| `editorName`             | string              | `"Emacs"`                        | [Editor integration](#editor-integration)                     |
| `editorCommand`          | array of strings    | none (the editor is not invoked) | [Editor integration](#editor-integration)                     |
| `keybindings`            | object              | `{}`                             | [Key bindings](#key-bindings-keybindings)                     |

## Example

```json
{
  "editorName": "Emacs",
  "editorCommand": [
    "/opt/homebrew/bin/emacsclient",
    "-n",
    "-e",
    "(hyperbuf-edit-here)"
  ],
  "restoreSession": true,
  "mathUnescapeUnderscore": true,
  "followUpdates": false,
  "modeLineVcsBranch": true,
  "gestureNavigation": true,
  "appearance": "system",
  "alpha": [100, 100],
  "frameTitleFormat": "default",
  "trustedUrls": ["https://github.com/yhojo/*", "https://*.wikipedia.org/*"],
  "warnPaths": ["/usr", "/opt", "/tmp", "~/.ssh"],
  "allowPaths": ["~/work", "/usr/share/doc"],
  "projectIgnorePaths": ["~/work/wrapper"],
  "keybindings": {
    "M-p": "back",
    "M-n": "forward",
    "C-x 2": "split-below",
    "C-f": null
  }
}
```

## Appearance (`appearance`)

| Key          | Type   | Meaning                                                                                                                                          |
| ------------ | ------ | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `appearance` | string | `"system"` (follow the OS setting; the **default**), `"light"`, `"dark"`. `light` / `dark` fix the app's appearance regardless of the OS setting |

- Windows, menus, scroll bars and document display all follow it.
- With `system`, the app follows the OS appearance even if it switches while the app is running. Documents, code, math and UI parts switch as they are, and diagrams (Mermaid) are redrawn in the new appearance (the reading position is kept).
- There is only one color scheme (light and dark variants), close to GitHub's. There is no mechanism (theme) for defining your own colors.
- **Image (PNG, SVG) colors are not changed.** A diagram drawn only with dark lines or text on a transparent background can be hard to see in dark mode (the same limitation as GitHub's dark display).

## Frame opacity (`alpha`)

| Key     | Type                | Meaning                                                                                                                                                  |
| ------- | ------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `alpha` | array of 2 integers | `[front, other]`. Percentages (10 to 100; **the default is `[100, 100]`**, no transparency). Same as Emacs's `(set-frame-parameter nil 'alpha '(80 65))` |

- Example: `"alpha": [80, 65]` makes the frontmost frame 80% opaque and background frames (including all frames while the app is in the background) 65% opaque.
- This is the opacity of the **whole window**. Text and images become equally see-through (there is no way to make only the background transparent).
- The same value is applied to all frames.
- While the accessibility option "Reduce transparency" is on, frames are opaque regardless of this setting.
- Out-of-range or wrongly shaped values are ignored (the frame stays opaque) and reported under "settings problems" in `C-h b`.

## Frame title (`frameTitleFormat`)

| Key                | Type   | Meaning                                                                                                                                          |
| ------------------ | ------ | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `frameTitleFormat` | string | `"default"` (the **default**; `README.md — hyperbuf/docs/user`), `"simple"` (a fixed `HyperBuf`), `"filename"` (the file name only, `README.md`) |

- The title shows the buffer of the selected window. With `default`, the directory is written relative to the project root and starts with the root's name (`hyperbuf/docs/user`); outside a project it is the directory with `~` for your home. More than four components are cut from the front (`…/b/c/d`).
- With several frames, ` [slot]` is appended (`README.md — hyperbuf/docs/user [2]`). Without a buffer, or for a virtual buffer such as search results, the title is `HyperBuf`.
- The title appears in screen sharing and in the window lists of macOS (Mission Control, `Cmd-\``). Use `simple` to keep directory names out of them.
- Project roots are found as in [Project root](#project-root). The title is first shown without the root and is corrected as soon as the search finishes.

## Document display

| Key                      | Type    | Meaning                                                                                                                              |
| ------------------------ | ------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `mathUnescapeUnderscore` | boolean | Whether to turn `\_` in math back into `_` before rendering. **The default is `true`**                                               |
| `followUpdates`          | boolean | Whether to jump to the first changed place when a file is updated externally. **The default is `false`** (keep the reading position) |

- `mathUnescapeUnderscore`: Marked 2 and similar tools remove Markdown backslash escapes before rendering math, so `$x\_1$` becomes the subscript `x_1`. In TeX, `\_` is "an underscore as a character", but with this compatibility, math in which `_` was written as `\_` for Markdown's sake reads as intended. A `\_` inside the arguments of `\text{…}`, `\mathrm{…}` and the like stays a literal underscore. With `false`, TeX rules apply exactly.
- `followUpdates`: you can toggle it on the spot with `C-x x u` (`toggle-follow-updates`) (the toggle lasts until the app quits and does not change the setting). While it is on, `[Follow]` appears in the mode line. The place jumped to is briefly highlighted.

## Gestures (`gestureNavigation`)

| Key                 | Type    | Meaning                                                                                                                             |
| ------------------- | ------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| `gestureNavigation` | boolean | Whether a two-finger horizontal swipe and the mouse back / forward buttons move in the reference history. **The default is `true`** |

- The swipe is macOS's own "Swipe between pages" gesture, so the direction and the animation follow the system setting (System Settings → Trackpad → More Gestures). The mouse's back / forward buttons (buttons 4 and 5) also work. Both act like `back` / `forward`: a swipe acts on the selected window, a mouse button on the window under the pointer.
- Set it to `false` to turn the gestures off, for example if horizontal scrolling on a trackpad triggers them by accident. The keys (`C-b` / `C-f`, `←` / `→`, `Cmd+[` / `Cmd+]`) are not affected.

## Restoring the previous state

| Key              | Type    | Meaning                                                                                                |
| ---------------- | ------- | ------------------------------------------------------------------------------------------------------ |
| `restoreSession` | boolean | Whether to restore and save the previous state. **The default is `true`** (disabled only with `false`) |

- While it is `false`, nothing is restored and nothing is saved (what was saved earlier is left as it is).
- What is restored and how it is saved are described in [session-restore.md](../dev/session-restore.md).

## File access

When you open a file under a warn path from a link or an external integration, the app asks for confirmation in the minibuffer. Everything else opens without confirmation.

| Key          | Type             | Meaning                                                                                                                               |
| ------------ | ---------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| `warnPaths`  | array of strings | Warn paths. Opening a file under one asks for confirmation. **If you write it, it replaces the default list**. `[]` means no warnings |
| `allowPaths` | array of strings | Allow paths. Places under a warn path where the confirmation is skipped. **If you write it, it replaces the default list**            |

- Default warn paths: `/usr`, `/opt`, `/tmp`, `/var`, `/etc`, `/System`, `/Library`, `~/.ssh`, `~/.aws`, `~/.gnupg`, `~/Library`. Default allow path: `~/Library/Mobile Documents` (iCloud Drive).
- Write absolute paths or `~/…`. Symbolic links are resolved before matching (`/tmp` is treated as `/private/tmp`). Relative paths, values of the wrong type and empty values are ignored, and the reason is reported under "settings problems" in `C-h b`.
- **The longest match wins** (the more specific entry takes precedence). If an allow path and a warn path are the same, it is treated as a warn path and reported as a settings problem.
- **Paths you type or choose yourself (`C-x C-f`, `C-x p f`) are not judged.** What is judged is link clicks, external integrations (CLI, Emacs, URL scheme) and images referenced by a document.
- When you approve a file under a warn path, everything under that file's directory becomes a "remembered path" and you are not asked again (stored in `~/Library/Application Support/HyperBuf/trusted-roots.json`). You can undo a remembered path with `M-x forget-remembered-path`.
- The detailed rules for the judgment are in [file-access.md](../dev/file-access.md).

## Project root

`C-x p f` / `C-x p g` / `C-x p b` / `C-x p k` start from the directory of the buffer you are viewing and go up through its parents. The first directory that has a VCS marker (`.git`, `.hg`, `.svn`, `.bzr`, `_darcs`, `.jj`) becomes the project root. If none is found, it is the buffer's own directory. `~` and `/` are never used as a root. The details of how the root is determined are in [buffer-model.md](../dev/buffer-model.md) §6.

| Key                  | Type             | Meaning                                                                                                                                                                                 |
| -------------------- | ---------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `projectIgnorePaths` | array of strings | Directories that are never used as a root. They are skipped even if they have a marker, and the search continues upward. Exact match only (it does not apply to directories below them) |
| `modeLineVcsBranch`  | boolean          | Whether to show the Git branch name in the mode line. **The default is `true`**                                                                                                         |

- Write absolute paths or `~/…`. Relative paths and values of the wrong type are ignored, and the reason is reported under "settings problems" in `C-h b`.
- `modeLineVcsBranch`: if the buffer's project root is a Git repository, the branch name is shown to the right of `[History N/M]` in the mode line (for a detached HEAD, the 7-character short hash). **It does not run the `git` command; it reads `.git/HEAD` directly.** The file's modification state (Emacs's `-` / `:` / `@`) is not shown. A branch switch is reflected when you reopen the buffer, when the file is reloaded, and when the app becomes active. Nothing is shown for VCSs other than Git, or for buffers without a project root.
- Listing and searching exclude hidden files and `node_modules`. `.gitignore` is not read.

## External links

When you select an `http` / `https` link in a document (click, `RET`), it opens in your default browser. **The app asks every time** (`yes` / `no` / `always`).

| Key           | Type             | Meaning                                                                                                 |
| ------------- | ---------------- | ------------------------------------------------------------------------------------------------------- |
| `trustedUrls` | array of strings | URL patterns that open without confirmation. `*` matches any string. Start with `http://` or `https://` |

- Sites (`scheme://host[:port]`) for which you answered `always` are remembered in `~/Library/Application Support/HyperBuf/trusted-sites.json`. You can undo that with `M-x forget-remembered-site`.
- `mailto:` is confirmed every time (there is no `always`). Other schemes (`file:`, `javascript:` and so on) are not opened.
- URLs that contain a user name or password (`https://example.com@evil.example/`), URLs that contain control characters, and URLs longer than 2048 characters are not opened, and no confirmation is asked.
- The app (Swift) checks the decision to open the browser again (it does not trust the Web side's decision).

## Editor integration

`Edit in <editorName>` in the context menu (or `C-c e`) records the pointed place and runs `editorCommand`.

| Key             | Type                         | Meaning                                                                                                                                 |
| --------------- | ---------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| `editorName`    | string (up to 40 characters) | The name shown in the menu. The default is `Emacs`                                                                                      |
| `editorCommand` | array of strings             | The command to run. **The first element is an existing executable's absolute path**. At most 16 arguments, each at most 1024 characters |

- Only the **fixed command you write here** is run, without a shell. **No document content, selection, path or position is included in the arguments or the environment** (the editor fetches the position with `get-location`).
- Without `editorCommand`, the editor is not invoked and the position is only recorded (the menu item is `Record Location for Editor`; in the editor, use `M-x hyperbuf-visit-location`).
- An invalid command (a relative path, nonexistent, not executable, not an array, and so on) is ignored (the editor is not invoked).

How the integration works is described in [edit-location.md](../dev/edit-location.md); the Emacs side is in [`emacs/README.md`](../../emacs/README.md).

## Key bindings (`keybindings`)

This layers on top of the default bindings ([keybindings.md](keybindings.md)).

```json
"keybindings": { "<key sequence>": "<command name>" | null, ... }
```

| Value                 | Meaning                                                                                             |
| --------------------- | --------------------------------------------------------------------------------------------------- |
| Command name (string) | Assigns the command to that key sequence. The default binding for the same key sequence is replaced |
| `null`                | Removes the default binding for that key sequence                                                   |

- **Command names** are the same as the `M-x` candidates. The list and descriptions are in [keybindings.md](keybindings.md) (or `C-h b` in the app).
- **How to write a key sequence:** separate keys with spaces, up to 4. One key is the modifiers in the **order** `C-` `M-` `s-` `S-`, followed by the base key (one character, or `RET` `ESC` `TAB` `SPC` `DEL` `up` `down` `left` `right`). Examples: `C-x 2`, `M-x`, `s-[`, `S-TAB`, `C-M-s`.
- **Processing order does not depend on the order you write entries in:** removals (`null`) come first, then assignments in key-sequence order.
- **Settings that are ignored** (the reason appears under "settings problems" in `C-h b`):
  - Unknown command names.
  - Invalid key notation (`Ctrl-x`, `M-C-x`, and so on).
  - Removing a key sequence that has no binding.
  - **`C-g`**: reserved for cancel (it cannot be changed).
  - Conflicts with a prefix: the same key sequence cannot be both a command and a prefix (such as `C-x`, which has keys such as `2` following it). To make `C-x` a command, first remove every binding that starts with `C-x` using `null`.
- Keys inside the input field (minibuffer) are outside the scope of this setting (confirm, cancel, candidate selection and history are fixed).
