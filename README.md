# HyperBuf

> **Read like a hacker.**
>
> **No tabs. Just buffers.**

HyperBuf is a macOS document viewer for reading large numbers of Markdown documents freely and mostly from the keyboard (it is not an editor).

It is more than a Markdown previewer. It combines the **buffer / window / frame** model that comes from Emacs with a browser-like reference history, so that instead of opening documents "one at a time" you can **move across them, compare them and go back and forth**.

**Status:** v0.1.2 (2026-10-19). It is in a limited distribution stage and feedback is being collected. The builds are Developer ID signed and notarized Universal (arm64 + x86_64) builds, and macOS 14 or later is required. Because of the result of a trademark check on the name, the project is not made public; it is distributed only to people who ask for it (the steps needed for a public release are still carried out as preparation).

## Where the name comes from

**HyperBuf** combines **Hyper**text (documents linked to each other) and (Emacs) **Buf**fer. It stands for opening, switching between and moving around many linked documents as casually as buffers in Emacs.

## Why HyperBuf?

There are many Markdown viewers. But there is still room for one that consistently values what engineers need when they read dozens to hundreds of cross-referenced design documents: operability, faithful rendering of extended syntax, and free movement from the keyboard.

HyperBuf aims to be **a tool you can live in**, rooted in hacker culture. Not retro for its own sake, but predictable operation, transparency, configurability and coexistence with existing tools.

## Principles

- **Keyboard first. Mouse optional.** — The main reading operations can be done entirely from the keyboard. The mouse is not excluded either.
- **No tabs. Just buffers.** — Separate the document itself (buffer) from the area that shows it (window).
- **Navigation is a first-class feature.** — References between documents, Back / Forward, heading jumps and search are designed as core features.
- **Files are yours.** — Respect plain Markdown and the existing directory structure; never require a move to a proprietary format.
- **Render what engineers write.** — Emphasize support for what is used in practice: GFM, SVG, math, diagrams, code.
- **Extensible by design.** — Aim for a structure that is easy to extend and whose settings and behavior can be understood.
- **Local first.** — Basic reading works offline, and there is no unintended network traffic.
- **Mac outside, Emacs inside.** — The menu bar and dialogs follow macOS conventions; inside the frame (key bindings, mode line, minibuffer) follows Emacs conventions. The text the app itself shows is fixed to English (not localized), while the documents and file names it handles are fully international. See [docs/dev/ui-conventions.md](docs/dev/ui-conventions.md).

## Features

### Reading and navigation

- **buffer / window / frame.** Separate the opened document (buffer) from the area that shows it (window); show the same buffer in several windows, each with its own reading position. A frame (a macOS window) is an independent workspace, switched with `Cmd-1` to `Cmd-9`. See [docs/dev/buffer-model.md](docs/dev/buffer-model.md) and [docs/dev/interaction-model.md](docs/dev/interaction-model.md).
- **Reference history.** Back / Forward (`C-b` / `C-f`) move through the reference history; following links, heading jumps and buffer switches with `C-x b` are all pushed onto it, while scrolling, `C-s` search and heading movement inside a document never disturb it. The history is per window and is copied when a window is split.
- **No project to choose.** Everything is based on the directory of the current buffer (Emacs `default-directory`): files are opened from there and the tree below it is listed and searched. Some commands work on the project root (the nearest directory with `.git` or similar).
- File list, file name filtering, heading navigation, search in the document and full-text search. Search results appear in a virtual buffer.
- Input such as search or buffer selection is done in the minibuffer at the bottom of the frame, not in dialogs. Key bindings can be changed in `config.json`.
- The session (window layout, reference history, reading position) is saved per frame and restored at the next launch. See [docs/dev/session-restore.md](docs/dev/session-restore.md).

### Rendering

- GitHub Flavored Markdown (GFM) with a GitHub-like style.
- Local images (including SVG), math with KaTeX, Mermaid diagrams, and syntax highlighting for about 90 languages ([docs/user/syntax-highlighting.md](docs/user/syntax-highlighting.md)).
- A diagram error does not stop the whole document; it is shown in place.

### Integration with the development workflow

- Reload files updated by Emacs or by coding agents, keeping the reading position.
- Open a file at a line or heading from the `hyperbuf` command and from the Emacs integration (`emacs/`). There is also an integration that lets you edit exactly the place you pointed at in the viewer in Emacs (it verifies the location before moving, so that a wrong place is never edited silently). See [docs/dev/integration-protocol.md](docs/dev/integration-protocol.md) and [docs/dev/edit-location.md](docs/dev/edit-location.md).

## Getting started

Open the downloaded `.dmg` and move `HyperBuf.app` to `Applications`. Installation and the basic operations are in [docs/user/getting-started.md](docs/user/getting-started.md) (also included in the `.dmg` as `README.md`).

### Main keys

| Key                                               | Command                                   | Intent                                                                     |
| ------------------------------------------------- | ----------------------------------------- | -------------------------------------------------------------------------- |
| `C-x C-f`                                         | `find-file`                               | Open a file (path completion starting at the base directory)               |
| `C-x p f`                                         | `project-find-file`                       | List and open the documents under the project root                         |
| `C-x b`                                           | `switch-buffer`                           | Switch the buffer that is shown                                            |
| `C-b` / `C-f`                                     | `back` / `forward`                        | Move back / forward in the reference history                               |
| `C-a` / `C-e`                                     | `beginning-of-history` / `end-of-history` | Jump to the first / last entry of the reference history                    |
| `C-s` / `C-r`                                     | `isearch-forward` / `isearch-backward`    | Incremental search in the document                                         |
| `M-s g` / `C-x p g`                               | `search-project` / `project-find-regexp`  | Full-text search under the base directory / under the project root         |
| `C-x 2` / `C-x 3` / `C-x 0` / `C-x 1` / `C-x o`   | `split-below` and others                  | Split, close and move between windows                                      |
| `C-x 5 2` / `Cmd-N` / `Cmd-1`…`Cmd-9`             | `make-frame` and others                   | Create and switch frames (`Cmd-W` closes one)                              |
| Two-finger swipe / mouse back and forward buttons | `back` / `forward`                        | Move in the reference history (can be turned off with `gestureNavigation`) |
| `M-x`                                             | `execute-command`                         | Run a command by name                                                      |
| `C-h b`                                           | `describe-bindings`                       | List the key bindings                                                      |

All key bindings are in [docs/user/keybindings.md](docs/user/keybindings.md) (generated from the code); how to configure them is in [docs/user/configuration.md](docs/user/configuration.md). The Mac shortcuts (`Cmd-N`, `Cmd-W`, `Cmd-O`, …), the mouse and the trackpad are described in [docs/user/getting-started.md](docs/user/getting-started.md).

## Documentation

| Location                       | Audience            | Contents                                                                                                                  |
| ------------------------------ | ------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| [docs/user/](docs/user/)       | Users               | Getting started, key bindings, configuration, languages supported by syntax highlighting, third-party licenses            |
| [docs/dev/](docs/dev/)         | Developers          | The current design and specification (architecture, buffer / window / frame, access rules, integration protocol, release) |
| [docs/history/](docs/history/) | Development history | PoC results, the migration plan, the plan change log (mostly in Japanese)                                                 |

For the structure and the technology choices see [docs/dev/architecture.md](docs/dev/architecture.md). For the change history see [CHANGELOG.md](CHANGELOG.md).

## Non-goals

- Building a full-featured Markdown editor. Editing is left to existing editors such as Emacs.
- Requiring a proprietary note format, a sync service or a cloud account.
- Fully supporting every Markdown dialect and plugin from day one.
- Including whole Git clients, IDEs or knowledge-management services.
- Making the look Emacs-like without reproducing the essence of the interaction model.

## Architecture

HyperBuf consists of a macOS shell (SwiftUI + WKWebView) and an OS-independent shared Web core (TypeScript; unified / remark / rehype, KaTeX, Mermaid, starry-night). The only boundary between the shell and the Web core is the `hyperbufHost` contract. To port it to another OS, write a shell with the best framework for that OS and reuse the Web core. The reasons for the choices and the candidates not yet evaluated are in [docs/dev/architecture.md](docs/dev/architecture.md).

## Security baseline

Local Markdown is treated as untrusted input when it comes from an external repository or was generated by an AI agent.

- Restrict script execution and external references in HTML/SVG and diagram engines.
- Manage explicitly which local files may be accessed and which external commands may be run.
- External network access is disabled in principle, or visible to the user.
- Extension mechanisms get permissions and trust boundaries.

How this is realized: [docs/dev/architecture.md](docs/dev/architecture.md) §4 and [docs/dev/file-access.md](docs/dev/file-access.md).

## Open questions

- Zooming and panning of images (including SVG).
- The shell for porting to other OSes (the macOS shell is decided: SwiftUI + WKWebView; for other OSes the policy is to use the best framework of each platform and reuse the shared Web core).
- How to select text for copying from the keyboard (a cursor in the reading view will not be introduced; to be examined separately).
- How to define the scope of GitHub-compatible rendering.
- In which permission boundary diagram plugins run (when external commands such as Graphviz are used).
- How to realize partial updates of large documents while keeping the scroll position.
- A check of memory usage (leaks and breakdown).
- The granularity of Back / Forward history (whether consecutive anchor moves within one document become one entry).
- The assignment of `M-f` / `M-b`.

## Contributing and security

Bug reports and requests are welcome as issues. Please discuss a pull request in an issue first; the steps are in [CONTRIBUTING.md](CONTRIBUTING.md). Please report vulnerabilities through the channel in [SECURITY.md](SECURITY.md), not in a public issue.

## License

Apache-2.0 ([LICENSE](LICENSE), [NOTICE](NOTICE)). `emacs/` is GPL-3.0-or-later ([emacs/LICENSE](emacs/LICENSE)).

---

**HyperBuf** — _Read like a hacker._
