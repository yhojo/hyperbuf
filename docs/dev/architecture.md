# Architecture

The structure of HyperBuf and its technology decisions. Details of each part are in the linked documents. The evaluations behind the choices are the PoC results in [docs/history/](../history/).

## 1. Overall structure

```
┌─────────────────────────── HyperBuf.app (macOS shell) ────────────────────────────┐
│  SwiftUI + WKWebView   file access, watching, search, session, socket, menus       │
│          │  hyperbufHost contract                                                  │
│  ┌───────▼─────────────────────────────────────────────────────────────────────┐   │
│  │ Web core (core/, TypeScript): buffer / window / frame model, keys, UI,      │   │
│  │ Markdown rendering (unified / remark / rehype)                              │   │
│  └─────────────────────────────────────────────────────────────────────────────┘   │
└───────────────▲────────────────────────────────────────────────────────────────────┘
                │ Unix domain socket (JSON Lines) / hyperbuf:// URL
        hyperbuf CLI (cli/)      Emacs integration (emacs/)
```

| Location     | Role                                                                                                                       |
| ------------ | -------------------------------------------------------------------------------------------------------------------------- |
| `core/`      | Shared Web core (TypeScript). Interaction model, keys, commands, UI, rendering. OS-independent                             |
| `app/macos/` | HyperBuf.app. A SwiftUI + WKWebView shell. `HyperBufKit` holds the logic for file access, search, watching, settings, etc. |
| `cli/`       | The `hyperbuf` command (a single Swift binary)                                                                             |
| `emacs/`     | Emacs integration (`hyperbuf.el`, Emacs 29.1 or later)                                                                     |
| `protocol/`  | JSON Schema of the integration protocol, shared examples, and a Swift library (types, validation, socket)                  |

## 2. The boundary between the Web core and the shell

- **The Web core does not depend on the shell.** The shell provides, as `window.hyperbufHost`, file listing and reading, search, access checks, settings, session saving and so on. The Web core uses no shell functionality by any other means.
- The contract is defined in `core/src/host.ts` (types and descriptions). The main roles are as follows.

  | Role                 | Contents                                                                                                                                                                |
  | -------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
  | Files                | `listDirectory` (one level), `listTree` (recursive listing), `projectRoot`, `readFile`, `watch` / `onFileChanged` (change notification)                                 |
  | Search               | `search` (full-text search)                                                                                                                                             |
  | Access checks        | `checkAccess`, approving and remembering confirmations (`allow`, `listRemembered`, `forget`), checking and remembering external URLs (`checkUrl`, `rememberSite`, etc.) |
  | Settings             | `getConfig` (key bindings, various settings, settings problems)                                                                                                         |
  | Session              | `loadSession`, `saveSession`                                                                                                                                            |
  | Frames               | `frame` (create, go to the next frame, delete)                                                                                                                          |
  | External integration | Receiving "open" requests from outside (`onOpen`), answering queries (`onQuery`, `respond`), recording the edit location (`markLocation`)                               |

- Decisions are made on the **shell side** as much as possible (file system access checks, running external commands, deciding whether to open a URL, etc.). Decisions made by the Web core are not trusted.
- When porting to another OS, **write the shell with the best framework for that OS and reuse the Web core**. The policy of sharing a cross-platform shell is not adopted (based on the experience of being troubled by subtle per-OS bugs).

## 3. Technology choices

### 3.1 Decided

| Item                | Choice                                                                                                                    | Rationale                                                                                                                                                                                                                         |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| macOS shell         | **SwiftUI + WKWebView**                                                                                                   | Direct access to macOS integration (menus, native windows, URL scheme, socket). Equal or better responsiveness, with a lighter build and fewer dependencies ([poc-interaction-results.md](../history/poc-interaction-results.md)) |
| Markdown pipeline   | **unified / remark / rehype**, remark-gfm, remark-math, rehype-katex, **rehype-sanitize**                                 | No rendering differences from GitHub were found, it meets the security premises, and performance is not a problem ([poc-rendering-results.md](../history/poc-rendering-results.md))                                               |
| Display style       | **github-markdown-css**. Differences from GitHub are absorbed with small transforms (e.g. `$` in currency notation)       | GitHub-compatible appearance                                                                                                                                                                                                      |
| Math                | **KaTeX**. The interpretation of `\_` (compatibility with Marked 2) is switched with the setting `mathUnescapeUnderscore` | Meets the requirements. MathJax is not adopted until it is needed                                                                                                                                                                 |
| Diagrams            | **Mermaid** (lazy-loaded, `securityLevel: strict`, layout fixed to dagre)                                                 | `elkjs` (EPL-2.0) is excluded for licensing reasons ([license-options.md](../history/license-options.md))                                                                                                                         |
| Syntax highlighting | **starry-night**                                                                                                          | The same grammars as GitHub. Better than Shiki in speed, output size and GitHub compatibility. Supported languages: [syntax-highlighting.md](../user/syntax-highlighting.md)                                                      |
| Full-text search    | **A custom Swift implementation** (`TreeSearch`). The engine can be replaced through the `host.search` contract           | Re-evaluate ripgrep when regular expressions or exclusion rules become necessary ([poc-navigation-results.md](../history/poc-navigation-results.md))                                                                              |
| File watching       | **kqueue** (`DispatchSource`; the displayed file and its parent directory, non-recursive)                                 | Polling cannot detect deletion and its cost grows with the number of files. Recursive FSEvents is noisy ([buffer-model.md](buffer-model.md) §8)                                                                                   |
| Integration         | **Unix domain socket** (JSON Lines) + `hyperbuf://` URL                                                                   | [integration-protocol.md](integration-protocol.md)                                                                                                                                                                                |
| License             | Core: Apache-2.0; `emacs/`: GPL-3.0-or-later                                                                              | [license-options.md](../history/license-options.md)                                                                                                                                                                               |

### 3.2 Implementation notes

- **Do not pass search queries as `Process` arguments.** macOS decomposes voiced and semi-voiced marks in arguments (converts to NFD), which corrupts Japanese search terms. When passing a search term to an external process, pass it through standard input.

### 3.3 Candidates not yet evaluated

The following will be evaluated when they become necessary. For anything involving external commands, the permission boundary is decided first.

- Graphviz, PlantUML, WaveDrom, D2 (candidates for diagrams).
- MathJax (not compared, because KaTeX meets the requirements).
- ripgrep for full-text search (when regular expressions or exclusion rules become necessary).
- Zoom and pan operations for images (including SVG).

## 4. Rendering and security

The policy of treating input as untrusted is realized as follows.

- **HTML:** sanitized with rehype-sanitize. ids get the prefix `user-content-` (it must not be removed; it prevents collisions with the app's DOM). Script execution is not allowed.
- **Images:** only `<img>` is allowed. The scheme handler (`SchemeHandler`) **checks access at every load** ([file-access.md](file-access.md) §5).
- **CSP:** `ContentSecurityPolicy` does not allow external communication. The starry-night WASM is bundled, and fetching from the default CDN is disabled.
- **Diagrams:** Mermaid renders in strict mode. A diagram error does not stop the whole document and is shown in place.
- **External links:** the shell decides whether to open them in the browser ([configuration.md](../user/configuration.md)).
- **External commands:** only fixed commands configured by the user are run ([edit-location.md](edit-location.md) §7).

## 5. Main design documents

- Interaction model: [interaction-model.md](interaction-model.md)
- Buffers and frames: [buffer-model.md](buffer-model.md)
- Access checks: [file-access.md](file-access.md)
- Session: [session-restore.md](session-restore.md)
- Integration: [integration-protocol.md](integration-protocol.md), [edit-location.md](edit-location.md)
- UI conventions: [ui-conventions.md](ui-conventions.md)
- Distribution: [distribution.md](distribution.md), [release.md](release.md)
