# Integration protocol (CLI and Emacs integration)

A common contract for **opening a document by specifying a file (and a line or heading)** from outside HyperBuf.app. The machine-readable definition (JSON Schema) and the shared examples for conformance tests are in [`protocol/`](../../protocol/README.md). The reverse direction, returning from the viewer to the edit location, is in [edit-location.md](edit-location.md). Access checks when opening a file are in [file-access.md](file-access.md). The evaluation and decisions behind this are in [poc-integration-results.md](../history/poc-integration-results.md).

## 1. Purpose and scope

The contract is used by three kinds of clients.

- The `hyperbuf` CLI (`cli/`)
- The Emacs integration (`emacs/`)
- Other users (shell scripts, other tools, terminal hyperlinks, etc.)

The contract covers four operations.

- "Open" a document (`open`)
- Check connectivity (`ping`)
- Query the location the user pointed to with "Edit in Emacs" (`get-location`; [edit-location.md](edit-location.md))
- Query the current view (`get-view`)

Out of scope:

- Editing document content. HyperBuf is a viewer, and editing is left to Emacs and the like.
- Remote control such as search and layout operations.
- Display from standard input (`git diff | hyperbuf -`) and extensions of terminal hyperlinks (OSC 8).

### Use cases

| User          | Example                                                                                               |
| ------------- | ----------------------------------------------------------------------------------------------------- |
| Terminal      | `hyperbuf docs/design.md`, `hyperbuf docs/design.md:120`, `hyperbuf docs/design.md --anchor 設計方針` |
| Emacs         | Show the Markdown being edited in the viewer, at the current line (`M-x hyperbuf-open-file`)          |
| Coding agent  | Open a design document it generated or updated in the user's viewer                                   |
| Terminal link | Open by click from a file name and line number in error output                                        |

## 2. Routes

| Route            | Use                                                                                                               |
| ---------------- | ----------------------------------------------------------------------------------------------------------------- |
| **Socket (IPC)** | The main route for the CLI and Emacs integration. Supports result responses, queries and waiting for confirmation |
| URL scheme       | Launching the app (when it is not running), and "open" from external links and terminal hyperlinks                |

- The socket **exists only while the app is running.** If a client cannot connect, it launches the app through the URL scheme (`hyperbuf://ping`), waits for the socket to appear, and reconnects.
- A browser cannot connect to a Unix domain socket, so **requests originating from the web never arrive on the socket.** The URL scheme can also be triggered from web pages, mail and links in documents, so the socket, whose request origin is limited, is the main route.

## 3. Socket

### 3.1 Transport

| Item            | Contents                                                                                                                                                                   |
| --------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Type            | Unix domain socket (stream)                                                                                                                                                |
| Path            | `~/Library/Application Support/HyperBuf/hyperbuf.sock`. If `sun_path` would exceed 103 bytes, `$TMPDIR/hyperbuf-<uid>.sock`                                                |
| Permissions     | Directory `0700`, socket `0600`                                                                                                                                            |
| Peer check      | For each connection, checks that the peer's user ID (`getpeereid`) is the same as the app's. Disconnects otherwise                                                         |
| Single instance | At launch, tries to connect to the existing socket; if there is a response, considers the app already running and exits. If not, deletes the stale socket and recreates it |
| Override        | The environment variable `HYPERBUF_SOCKET_PATH` ([debug-environment.md](debug-environment.md))                                                                             |

### 3.2 Messages

UTF-8 JSON Lines (one message per line). Requests and responses are exchanged in order over one connection. The limit for one line is 1 MiB (the connection is closed if exceeded).

Request:

```json
{
  "v": 1,
  "id": "1",
  "op": "open",
  "path": "/abs/doc.md",
  "line": 120
}
```

Response:

```json
{"v":1,"id":"1","ok":true,"result":{"path":"/abs/doc.md"}}
{"v":1,"id":"1","ok":false,"error":{"code":"outside-project","message":"…"}}
```

- A response is matched to its request by the request's `id`. Multiple requests may be in flight on the same connection.
- Unknown fields are ignored. An unknown operation is answered with `unknown-op`.
- The source of truth for the definitions is `protocol/schema/request.schema.json` and `response.schema.json`.

### 3.3 Operations

| Operation      | Description                                                                                                                                                            | Response `result`                                                                  |
| -------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| `ping`         | Check connectivity and version                                                                                                                                         | `{ "version", "pid", "protocol": 1 }`                                              |
| `open`         | Open a document (§4). When a warn path confirmation (in the minibuffer) is needed, the response is held until the user answers (`timeout` after 30 seconds by default) | `{ "path": absolute path of the opened document }`                                 |
| `get-location` | Return the location the user pointed to with "Edit in Emacs" ([edit-location.md](edit-location.md) §5). `null` if there is none yet                                    | `{ "location": payload or null }`                                                  |
| `get-view`     | Return the current view (which document, and roughly where). That of the selected window                                                                               | `{ "view": { "path", "anchor", "scrollTop", "history", "absolutePath" } or null }` |

The `history` of `get-view` is a string `<current position>/<count>`. `absolutePath` is attached for documents that are real files (not for virtual buffers).

### 3.4 Error codes

| Error code            | Meaning                                                                                   |
| --------------------- | ----------------------------------------------------------------------------------------- |
| `bad-request`         | Malformed request, missing required field, or failed validation (§4.2)                    |
| `unsupported-version` | The contract version is not supported                                                     |
| `unknown-op`          | The operation is not supported                                                            |
| `not-found`           | The file does not exist                                                                   |
| `not-markdown`        | Not a `.md` file                                                                          |
| `outside-project`     | The file is under a warn path and the user denied it (the name is kept for compatibility) |
| `timeout`             | The user did not answer in time                                                           |
| `stale`               | The location is based on an outdated view                                                 |
| `internal`            | Internal error in the app                                                                 |

### 3.5 Compatibility

- If `v` is an unknown version, the request is rejected with `unsupported-version`.
- Additional parameters are added without changing the meaning of existing ones. Unknown parameters are ignored.
- The name `outside-project` dates from before the notion of a project was removed, and is kept for compatibility. Its meaning is "not opened because of a warn path".

### 3.6 Security

- Only **processes of the same user** can connect (permissions and peer check). It is not reachable from a browser or over the network.
- The set of operations is small and fixed, and does not include operations with side effects (modifying or deleting files, running external commands).
- The response of `get-location` contains part of a document, so the peer check is mandatory.
- Limits are set on request size (1 MiB per line) and count, and connections with a malformed format are closed.
- Multiple requests on the same connection are processed concurrently, and each response is written exactly once. Even if the client closes its sending side (half-close), the connection is not closed while there are unanswered requests.

## 4. `open`

### 4.1 Parameters

| Parameter   | Required | Meaning                                                                                                                             |
| ----------- | -------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| `v`         | No       | Contract version. 1 if omitted                                                                                                      |
| `path`      | **Yes**  | Absolute path of the Markdown to open. Only the `.md` extension                                                                     |
| `line`      | No       | Line number in the original Markdown (1-based). Treated as the line anchor `line:N`                                                 |
| `anchor`    | No       | An anchor such as a heading. If specified together with `line`, `anchor` takes precedence                                           |
| `timeoutMs` | No       | Deadline for waiting on a confirmation (milliseconds). The default is 30 seconds                                                    |
| `target`    | No       | **Reserved, unimplemented.** Where to show (`current` / `split-right` / `split-below` / `new-frame`). Accepted but currently unused |
| `project`   | No       | **Reserved, unimplemented.** Accepted but unused (there is no notion of a project)                                                  |

- A position specification (`line` / `anchor`) has the same meaning as the existing anchors (`path#heading`, `path#line:N`; [interaction-model.md](interaction-model.md) §5).
- The destination is always the **selected window of the last active frame**. It is pushed onto the reference history and can be undone with Back ([buffer-model.md](buffer-model.md) §7). An `open` with a position for the same document that is already shown does not push onto the history and only replaces the position ([interaction-model.md](interaction-model.md) §3).
- `target` and `project` exist in the schema and the CLI arguments, but the app does nothing with them. They are kept in the contract for future extension.

### 4.2 Validation

The URL route and the socket route are validated with the same rules (shared by Swift, the CLI and Emacs through `protocol/examples/open-validation.json`).

- `path` must be an absolute path and `.md` only. Paths containing `..` and paths containing control characters are rejected. Relative paths are rejected (the CLI converts them to absolute paths).
- A symbolic link is revalidated against the resolved target.
- `line` must be a positive integer. `anchor` is up to 200 characters (counted in Unicode code points). Always escape it when using it for DOM lookup (`CSS.escape`).
- A request that fails validation is rejected with `bad-request`, `not-markdown`, `not-found` and so on.

### 4.3 Access checks and confirmation

If the file to open is under a warn path, it is confirmed in the minibuffer. The rules for the decision, the differences between routes (the URL scheme also confirms files not under an allow path even outside the warn paths), and remembering are in [file-access.md](file-access.md).

- The confirmation appears in the **minibuffer of the destination frame**.
- The result of the confirmation is returned as the response of `open` (approved: success, denied: `outside-project`, expired: `timeout`). When the deadline passes, **the confirmation still on screen is also cancelled**, and, distinguished from a denial, `Integration: request timed out` is shown on screen.
- The deadline is the request's `timeoutMs` (30 seconds by default). The CLI specifies 3 seconds by default and 60 seconds with `--wait`.

### 4.4 Resolving the position and reporting errors

- `anchor` / `line` look up the matching element in the rendered DOM. If it is not found, the beginning of the document is opened and the minibuffer is notified.
- Failures (the file does not exist, it is not `.md`, it was denied, etc.) are shown in the minibuffer. No dialog is shown.

## 5. URL scheme

### 5.1 `hyperbuf://ping`

Only launches the app (does nothing if it is already running). Used by the CLI and Emacs when the app is not running.

### 5.2 `hyperbuf://open`

```
hyperbuf://open?v=1&path=<absolute path>[&line=<N>][&anchor=<ID>][&project=<absolute path>][&target=<current|split-right|split-below|new-frame>]
```

- The meaning and validation of the parameters are in §4. `path` is percent-encoded.
- It can be triggered from routes whose origin cannot be identified, such as an arbitrary page in a browser, so files not under an allow path are confirmed ([file-access.md](file-access.md) §2).

## 6. CLI

```
hyperbuf [options] <file>[:<line>] ...
```

| Item                   | Contents                                                                                                                  |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| Position               | `file.md:120` (line number). Can also be given with `--line N` and `--anchor ID` (not usable when passing multiple files) |
| Multiple files         | Opened in order, and the last file is shown (the earlier ones remain as buffers)                                          |
| Directory              | `hyperbuf DIR` opens `DIR/index.md`, or `DIR/README.md` if there is none (fails if neither exists)                        |
| `--target <…>`         | `current` (default), `split-right`, `split-below`, `new-frame`. **Reserved, unimplemented** (§4.1)                        |
| `--wait`               | Wait up to 60 seconds for a confirmation in the app (the default is 3 seconds)                                            |
| `--no-activate`        | Do not bring the app to the front when launching it                                                                       |
| `--print-url`          | Print the constructed URL instead of opening (for checking and for use with other tools)                                  |
| `--version` / `--help` |                                                                                                                           |
| Removed                | `--project` was removed (specifying it is a usage error)                                                                  |

### 6.1 Exit codes

| Code | Meaning                                                                        |
| ---- | ------------------------------------------------------------------------------ |
| 0    | Success                                                                        |
| 1    | Usage error                                                                    |
| 2    | File problem (missing, unreadable, not `.md`)                                  |
| 3    | The app could not be launched                                                  |
| 4    | Rejected by the app (not approved for a warn path, expired, etc.)              |
| 5    | Protocol mismatch, internal error, or a response that could not be interpreted |

### 6.2 Flow

1. Connect to the socket. If it cannot connect, launch the app with `hyperbuf://ping` (URL scheme), wait up to 15 seconds for the socket to appear, and reconnect.
2. Send the request and wait for the response. Multiple files are sent in order.
3. Return the exit code according to the response. Unless `--wait` is given, it does not wait long for a confirmation in the app (3 seconds by default).

All CLI and Emacs requests go through the socket. The URL scheme is used for launching only for `ping` (if the first file were passed by URL to launch the app, the URL-scheme confirmation would appear on every launch).

## 7. Emacs

`emacs/hyperbuf.el` (Emacs 29.1 or later). Usage and settings are in [`emacs/README.md`](../../emacs/README.md).

- **The default is to use the socket directly** (`make-network-process` with `:family 'local`). There is no process-launch cost, and the `get-location` round trip is fast. Setting `hyperbuf-transport` to `cli` calls the `hyperbuf` CLI instead. JSON uses Emacs's built-in `json-serialize` / `json-parse-string`.
- **Input validation is also done on the Emacs side** (`hyperbuf--validate-open`). It returns an immediately understandable error to the user before connecting. To keep the rules from drifting from the server, conformance tests share `protocol/examples/open-validation.json` and `url.json`.
- **When the app is not running:** if `hyperbuf-launch-if-needed` (default t), it launches the app with `hyperbuf://ping` (`open`), waits for the socket to appear up to `hyperbuf-launch-timeout` (default 15 seconds; can be interrupted with `C-g`), and sends the open request over the socket. The flow is the same as the CLI: the result (success, denial, expiry) is returned to Emacs, and access checks follow the socket's rules. If nil, it notifies and stops.
- **Unsaved buffers:** the viewer reads the disk, so `hyperbuf-save-before-open` (default `ask`) asks whether to save before opening.
- **TRAMP files are not opened** (the viewer reads only local files).
- **Wait time:** the app returns `timeout` after `timeoutMs`, so the client waits for that plus a 2-second margin.
- The Emacs side does not compute heading anchors. It passes a line number, and the app resolves it to the matching block (to avoid bringing the GitHub-style heading ID computation into Emacs).

## 8. Security

- **The range of files that can be opened** is determined by warn paths, allow paths and remembered paths ([file-access.md](file-access.md)).
- **Content is handled as usual.** An opened document is rendered as untrusted input.
- **Path and input validation** is in §4.2.
- Socket-specific protections (same user, fixed operations, limits) are in §3.6.
- For the part of the reverse-direction integration where the app runs an external command, the permission design is in [edit-location.md](edit-location.md) §7.

## 9. Unimplemented / unverified

- Handling of `target` and `project` (§4.1).
- Real-device verification of rejecting connections from another user (`getpeereid`). It was confirmed that connections from the same user pass, but the path that rejects another user's connection is unverified because it needs a separate account.
- Bringing the existing instance to the front when a duplicate launch is detected (currently it just exits).
- Verifying socket creation and connection in the signed and notarized app (expected to be unchanged).
- Handling of another `open` arriving while waiting for a confirmation (make it wait, run concurrently, or reject). Currently it is processed concurrently.
