# protocol/

The machine-readable definition of HyperBuf's integration protocol (Unix domain socket and URL scheme), and data for conformance tests.
The specification itself is [`docs/dev/integration-protocol.md`](../docs/dev/integration-protocol.md) (the reverse direction, the edit location, is [`docs/dev/edit-location.md`](../docs/dev/edit-location.md)).

| Location    | Contents                                                                                                                                                                                                       |
| ----------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `schema/`   | JSON Schema (2020-12) for requests, responses and locations (`location`: the editor integration)                                                                                                               |
| `examples/` | **Shared examples.** The Swift library, `cli/`, `emacs/` and the JSON Schema tests use the same examples, so that differences between implementations are detected (see the table below)                       |
| `swift/`    | The Swift libraries shared by the app (server) and `cli/` (client): `HyperBufProtocol` (types, `open` validation, URLs, JSON Lines framing, socket path) and `HyperBufIPC` (`SocketServer` and `SocketClient`) |
| `test/`     | Checks that the JSON Schema and `examples/` do not disagree, and that the tables in the documents match the schema (Node + ajv)                                                                                |

## Shared examples

| File                   | Contents                                                                                         | Used by                                                    |
| ---------------------- | ------------------------------------------------------------------------------------------------ | ---------------------------------------------------------- |
| `open-validation.json` | Validation of `open` requests (accepted and rejected)                                            | JSON Schema tests, `swift/` (`HyperBufProtocol`), `emacs/` |
| `url.json`             | Conversion between requests and `hyperbuf://` URLs (`emacs/` uses only the `ping` URL to launch) | JSON Schema tests, `swift/` (`HyperBufProtocol`), `emacs/` |
| `framing.json`         | JSON Lines framing (split input, several lines at once, empty lines, ...)                        | `swift/` (`HyperBufProtocol`)                              |
| `cli-args.json`        | Parsing of the arguments of the `hyperbuf` CLI                                                   | `cli/`                                                     |
| `location.json`        | The location payload (`result.location` of `get-location`)                                       | JSON Schema tests, `swift/` (`HyperBufProtocol`)           |
| `location-check.json`  | The editor-side verification rules ([edit-location.md](../docs/dev/edit-location.md) §6)         | JSON Schema tests, `emacs/`                                |

If you break an example, every test that uses it fails.

## Making changes

When you add a new operation, field or error code, update the following together:

1. `schema/` (the source of truth).
2. `examples/` (examples that are accepted and examples that are rejected).
3. `docs/dev/integration-protocol.md` (the tables of operations and error codes; `test/docs.test.mjs` checks that they match the schema). For the location payload, `docs/dev/edit-location.md`.
4. The implementations: `swift/`, `cli/` and `emacs/` (`emacs/` has its own validation rules).

## Checking

```bash
scripts/check.sh protocol     # Node (formatting, schema and examples, tables in the documents) and Swift (protocol/swift)
```
