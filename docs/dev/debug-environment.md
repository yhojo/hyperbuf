# Environment variables for development and testing

So that tests do not use the user's real state (settings, socket, remembered paths, session), locations such as storage paths are redirected with environment variables. They are listed here.

The user-written settings (`config.json`) are described in [configuration.md](../user/configuration.md).

## 1. Debug builds only

Release builds do not read these (so that a user's environment variables cannot redirect storage locations).

| Environment variable     | What it redirects / behavior                                                                                                                                |
| ------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `HYPERBUF_CONFIG`        | Location of the settings file (`config.json`)                                                                                                               |
| `HYPERBUF_SOCKET_PATH`   | Location of the app's socket                                                                                                                                |
| `HYPERBUF_TRUSTED_ROOTS` | Storage for remembered paths (`trusted-roots.json`; [file-access.md](file-access.md) §4)                                                                    |
| `HYPERBUF_TRUSTED_SITES` | Storage for remembered sites (`trusted-sites.json`)                                                                                                         |
| `HYPERBUF_SESSION_DIR`   | Storage for the session (the directory that holds `session.json`; [session-restore.md](session-restore.md))                                                 |
| `HYPERBUF_TEST_LOG`      | Appends the Web core's diagnostic log to this file                                                                                                          |
| `HYPERBUF_TEST_OPEN_LOG` | Appends URLs that would have been opened in the browser to this file, without actually opening them                                                         |
| `HYPERBUF_TEST_COMMANDS` | Runs the `N.js` files placed in this directory in order inside the WebView, and writes the result to `N.result` (used by `scripts/integration-test-ipc.sh`) |
| `HYPERBUF_TEST_SCRIPT`   | After launch, runs this JavaScript inside the WebView and prints `RESULT: …`. The script must resolve (do not return a pending Promise)                     |

## 2. All builds

| Environment variable   | Applies to | Meaning                                                                                                                                                  |
| ---------------------- | ---------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `HYPERBUF_WEB_ROOT`    | App        | Where the Web core is loaded from. Priority order: this environment variable, the app bundle (`Contents/Resources/web`), (debug builds only) `core/dist` |
| `HYPERBUF_SOCKET_PATH` | CLI, Emacs | Location of the socket to connect to (for Emacs, when `hyperbuf-socket-path` is nil). Redirecting the app side is for debug builds only (§1)             |
| `HYPERBUF_APP`         | CLI        | Path of the `.app` to launch. If not given, launches the app registered for the URL scheme                                                               |

## 3. Build and release scripts

| Environment variable      | Applies to                  | Meaning                                                      |
| ------------------------- | --------------------------- | ------------------------------------------------------------ |
| `HYPERBUF_ICON`           | `make-app.sh`, `release.sh` | Overrides the app icon (`.icns`)                             |
| `HYPERBUF_SIGN_IDENTITY`  | `release.sh`                | Certificate used for signing ("Developer ID Application: …") |
| `HYPERBUF_NOTARY_PROFILE` | `release.sh`                | Stored name of the notarization credentials                  |
| `HYPERBUF_RELEASE_DIR`    | `release.sh`                | Where the artifacts are placed (default `dist/release`)      |

The whole procedure is in [release.md](release.md).

## 4. Notes when changing

- Keep the list in sync with where the code reads them (`ProcessInfo.processInfo.environment[...]`, `getenv`, `$HYPERBUF_…` in shell scripts). When a new environment variable is added, update this table too.
