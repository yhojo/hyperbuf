# File Access Judgment

The rules for which files HyperBuf opens without confirmation and which it opens only after confirmation. For the buffer concept, see [buffer-model.md](buffer-model.md); for the list of configuration keys, see [configuration.md](../user/configuration.md); for the contract of external integration (socket and URL scheme), see [integration-protocol.md](integration-protocol.md).

## 1. Policy

As a viewer, HyperBuf can **read Markdown from any location**. At the same time, Markdown is untrusted input (including what AI agents write), so HyperBuf makes sure that **links and external requests do not cause files the user did not intend to be read**.

- The decision is made by **path rules**, not by "inside or outside the project". Only files under the **warn paths** written in the settings are confirmed before opening.
- **A path the user chose themselves is not judged.** A path typed (selected) with `C-x C-f` or `C-x p f` is the user's own intent.
- The judgment is made on the Swift side (`FileAccess`). The Web core is responsible only for showing the confirmation, and its judgment is not trusted (see the final check in §5).

## 2. Targets and routes of judgment

The following routes all go through the same judgment.

- Clicking a link
- "Open" from the CLI, Emacs, or the URL scheme
- Resources such as images referenced by a document

The strictness differs by route. The URL scheme (`hyperbuf://open?...`) can be triggered from routes whose **origin cannot be identified**, such as any page in a browser. So the judgment does not rest on path rules alone; handling is split by origin.

| Route                                                                    | Judgment                                                                                     |
| ------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------- |
| Socket (CLI, Emacs; includes the CLI's first launch; see the note below) | Judged by the path rules (§3) only, since it is a process of the same user                   |
| **URL scheme**                                                           | A file not in the allow paths is **confirmed in the minibuffer even outside the warn paths** |
| Link click, resources                                                    | Judged by the path rules (§3) only                                                           |
| `C-x C-f`, a path typed in the minibuffer                                | Not judged (the user's intent)                                                               |

**Note: the CLI's first launch.** When the app is not running, the CLI starts it with `hyperbuf://ping` (launch only), waits until the socket appears, and then sends the "open" request over the socket. All CLI and Emacs requests go through the socket. The URL scheme is used for launching the app and for "open" from external links. This form is used because passing the first file by URL at launch would show the URL-scheme confirmation on every launch.

The confirmation appears in the minibuffer of the **destination frame** (the destination of an external "open" is the frame that was last active; [buffer-model.md](buffer-model.md) §7).

## 3. Path rules

After normalizing the path (`realpath`; symbolic links are judged by their target), it is matched against the **allow paths** and **warn paths** in the settings.

1. If it matches neither → **open**.
2. If any match, the **longest match** wins (the more specific entry takes precedence).
   - If an allow path wins → open.
   - If a warn path wins → confirm in the minibuffer.
3. If an allow path and a warn path overlap on the **same path**, it is treated as a warning, the safe side, and reported as a configuration problem.

| Settings                                         | File                   | Result                            |
| ------------------------------------------------ | ---------------------- | --------------------------------- |
| `allowPaths: ~/work`, `warnPaths: ~/work/vendor` | `~/work/vendor/x.md`   | Warn (the more specific one wins) |
| `allowPaths: /usr/share/doc`, `warnPaths: /usr`  | `/usr/share/doc/a.md`  | Allow                             |
| (matches neither)                                | `~/Downloads/foo/a.md` | Open                              |

- Path matching is judged at separator boundaries (`/tmp` does not match `/tmp2`). Comparison of nonexistent paths is case-insensitive (APFS).
- `allowPaths` has meaning only where it overlaps a warn path (it specifies places under a warn path where confirmation is skipped).

## 4. Confirmation and remembering

- When opening a file under a warn path, it is confirmed in the minibuffer.
- On approval, the directory of that file and everything under it is remembered, and it is not confirmed from then on. The memory is persisted and in effect works as a specific allow path.
- **Limit on the remembered scope:** if the directory to remember would be **the warn path itself or one of its ancestors**, only **that single file** is remembered instead of the directory (this prevents approving `/tmp/x.md` from making all of `/tmp` allowed).
- For places you want to allow in bulk, write them in `allowPaths`.
- **Listing and revoking** remembered paths is done with `M-x forget-remembered-path` (the remembered paths appear as candidates, and `RET` revokes the selected one).
- The memory is saved separately from the `config.json` that the user writes (`trusted-roots.json`). **The app does not rewrite the settings file.**
- Memory and settings are shared by all frames (managed on the host side).

## 5. Resources such as images

Resources are loaded asynchronously while a document is rendered, so a confirmation cannot be shown on the spot to stop them. The flow is as follows.

1. **Before** rendering, the paths of local images in the document are collected and the host judges them together.
2. Resources subject to a warning are not loaded; a placeholder is shown instead.
3. After rendering, the minibuffer asks once: "There are N images at warned paths (`<directory>`). Allow?"
4. The confirmation is shown **only for the document in the selected window of the active frame** (so that multiple frames do not show confirmations at the same time during session restore). Other documents wait with placeholders and ask when their window is selected.
5. On approval, the directory is remembered and the document is re-rendered. If declined, it is **remembered for that session**, and the user is not asked again on re-rendering caused by a file update.
6. The **final allow/deny judgment is always rechecked on the scheme handler side** (the Web core's judgment is not trusted).

## 6. Defaults

- Default `warnPaths`: `/usr`, `/opt`, `/tmp`, `/var`, `/etc`, `/System`, `/Library`, plus sensitive places under the host: `~/.ssh`, `~/.aws`, `~/.gnupg`, `~/Library`.
- Default `allowPaths`: `~/Library/Mobile Documents` (iCloud Drive; the longer match wins over the `~/Library` warning).
- `/Volumes` (external drives) is not included in the warnings. This is so that the user's own documents are not confirmed every time; instead it is protected by the timeout of recursive enumeration ([buffer-model.md](buffer-model.md) §6.1).
- On macOS, `/tmp`, `/var`, and `/etc` are symbolic links to `/private/...`, so paths in the settings are also normalized at load time before matching. Nonexistent paths are used as strings.

## 7. Settings

```json
{
  "warnPaths": ["/usr", "/opt", "/tmp", "/var", "/etc", "/System", "/Library"],
  "allowPaths": ["~/work", "/usr/share/doc"]
}
```

- When you write `warnPaths`, it **replaces** the default list. `[]` means no warnings. The same applies to `allowPaths`.
- `~` is expanded. Entries that are not absolute paths or have the wrong type are ignored, and the reason is shown under "Configuration problems" in `C-h b`.
- For the list of keys, see [configuration.md](../user/configuration.md).
