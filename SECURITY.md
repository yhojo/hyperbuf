# Security Policy

HyperBuf treats every Markdown file as untrusted input, including files written by AI agents. Reports of weaknesses in that boundary are welcome and taken seriously.

## Supported versions

HyperBuf is in the 0.x series. Security fixes are made for **the latest release only**; please check that the problem still exists in the latest version before reporting it.

## Reporting a vulnerability

**Please do not open a public issue for a security problem.**

Use GitHub's private vulnerability reporting: open the **Security** tab of this repository and choose **Report a vulnerability**. If that button is not available, open a public issue that only asks for a private contact channel, without describing the problem.

Please include:

- the HyperBuf version (`hyperbuf --version`, or the app's About window) and your macOS version;
- what you did, what you expected and what happened, ideally with a minimal Markdown file or command that reproduces it;
- the impact as you understand it.

This is a small project maintained by one person, so there is no guaranteed response time, but reports are handled on a best-effort basis. Fixes are released as a new version and described in [CHANGELOG.md](CHANGELOG.md); the reporter is credited unless they prefer not to be. Please keep the problem private until a fixed version is available.

## What is in scope

Problems that let untrusted content or another party cross a boundary that HyperBuf promises to keep. For example:

- script execution, or loading of external resources, from Markdown, HTML, SVG or diagrams (see [docs/dev/architecture.md](docs/dev/architecture.md) §4);
- reading files that the access rules should have asked about, or bypassing the confirmation for warn paths and the `hyperbuf://` URL scheme (see [docs/dev/file-access.md](docs/dev/file-access.md));
- access to the control socket by another user, or by a web page;
- command injection through the "Edit in editor" feature or the URL handling;
- weaknesses in the signed and notarized builds.

## What is out of scope

- Anything that needs the attacker to already run code as the same user or to edit the user's `config.json`; the editor command configured there is trusted by design.
- Documents that are merely large or slow to render, unless they crash or freeze the app in a way that loses data.
- Problems in Emacs or other tools that HyperBuf only talks to.

Third-party components are listed in [docs/user/third-party-licenses.md](docs/user/third-party-licenses.md). A vulnerability in one of them is welcome too, but it may need to be reported upstream as well.
