# Contributing to HyperBuf

Thank you for your interest in HyperBuf. This is a small project maintained by one person, so the notes below are short and practical.

## Reporting bugs and asking for features

**Issues are welcome**, in English or Japanese. A good bug report has:

- the HyperBuf version (`hyperbuf --version`, or the app's About window) and your macOS version;
- the steps to reproduce it, ideally with a minimal Markdown file;
- what you expected and what happened.

For feature requests, describe the situation you are in rather than only the solution you have in mind. HyperBuf is a keyboard-driven *viewer*; editing, sync services and full IDE features are non-goals (see the README).

**Security problems** must not be reported in a public issue. See [SECURITY.md](SECURITY.md).

## Pull requests

**Please open an issue and discuss the change before sending a pull request.** This avoids work that does not fit the design. Typo fixes and small documentation corrections do not need an issue. The maintainer currently merges branches locally with merge commits (no squash, no rebase), so an accepted pull request may be merged that way.

## Development

You need macOS 14 or later, a Swift 6 toolchain, Node.js 22.18 or later, and Emacs 29.1 or later (for the Emacs package tests).

```bash
scripts/check.sh            # everything: license headers, versions, core, protocol, app, cli, emacs
scripts/check.sh core       # or one part: license | version | protocol | app | cli | emacs
```

The GUI integration tests (`scripts/integration-test*.sh`) need a graphical session and are not run in CI; run the ones related to your change.

Before sending a change:

- Make `scripts/check.sh` pass.
- Add or update tests. Generated documents (`docs/user/keybindings.md`, `docs/user/syntax-highlighting.md`, `docs/user/third-party-licenses.md`) are regenerated, not edited by hand.
- Add the SPDX license header to new source files (`scripts/check-license-headers.sh` checks it).
- Update the documentation that your change touches. `CLAUDE.md` ("Documentation") has a table of which document goes with which kind of change, and `docs/dev/architecture.md` is the best starting point for the design.
- Describe user-visible changes under `[Unreleased]` in [CHANGELOG.md](CHANGELOG.md), in English.
- All text that the app itself shows (menus, messages, command descriptions, CLI output) is English and not localized. Document contents, file names and input stay fully international.

Commit messages follow Conventional Commits (`type: summary`), and branches are named `<type>/<short description>` (for example `fix/scroll-restore`).

## License of contributions

HyperBuf is licensed under the Apache License 2.0 (see [LICENSE](LICENSE)); the `emacs/` directory is licensed under GPL-3.0-or-later (see `emacs/LICENSE`). Unless you state otherwise, a contribution that you submit is provided under the license of the part of the project it modifies (for the main project, as described in section 5 of the Apache License 2.0). There is no separate contributor agreement and no sign-off requirement.
