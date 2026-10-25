# Release procedure

The procedure for signing, notarizing and distributing. `scripts/release.sh` performs Developer ID signing, notarization, stapling, the `.zip` / `.dmg`, and the checksums. The contents of the artifacts and the signing design are in [distribution.md](distribution.md).

## 1. Prerequisites (once only)

1. **Signing certificate:** "Developer ID Application: …" is in the keychain (an Apple Developer Program certificate; check with `security find-identity -v -p codesigning`). When there are several, specify one with `HYPERBUF_SIGN_IDENTITY`.
2. **Notarization credentials:** Store an **app-specific password** for your Apple ID (issued at appleid.apple.com) as a keychain profile. **Neither this script nor Claude receives the password or the Apple ID**. Run this once on your own machine.

   ```bash
   xcrun notarytool store-credentials "hyperbuf-notary" --apple-id "<Apple ID>" --team-id "<team ID>"
   ```

   The command asks for the password interactively. Do not write `--password` as an argument (it would remain in the history).

## 2. Release steps

1. **Decide the version.** Make the following places carry the same version.
   - `hyperBufVersion` in `app/macos/Sources/HyperBufKit/Version.swift` (the source of truth for the app version)
   - `cliVersion` in `cli/Sources/HyperBufCLI/CLI.swift`
   - `version` in `core/src/index.ts`
   - `;; Version:` in the header of `emacs/hyperbuf.el`
   - `version` in `core/package.json` and `protocol/package.json`, and the top-level `version` (2 places) in each `package-lock.json`

   The version in `Info.plist` is set by `make-app.sh` from `Version.swift` (the build number is the commit count). `scripts/check.sh version` checks that they agree (`release.sh` also checks during its run). Also update the status lines in `README.md` and `CLAUDE.md` to the new version, and record it in `docs/history/plan-change-log.md`.

2. **Finalize the changelog.** Turn `[Unreleased]` in `CHANGELOG.md` into a version heading (`## [x.y.z] - date`), and put a new empty `[Unreleased]` at the top.
3. **Prepare on a branch and merge.** Do the version and changelog updates on a `chore/release-<version>` branch and merge it into `main` with `--no-ff` (branch workflow: `CLAUDE.md`). From here on, work on `main` after the merge.
4. **Check.** `scripts/check.sh` passes. The GUI integration tests (`scripts/integration-test*.sh`; not run in CI) also pass.
5. **Rehearsal** (optional; no notarization). `scripts/release.sh --dry-run`. It only tries assembly, ad-hoc signing and creating the `.zip` / `.dmg`. **Do not distribute these artifacts**.
6. **The real release.**

   ```bash
   HYPERBUF_NOTARY_PROFILE=hyperbuf-notary scripts/release.sh
   ```

   The artifacts are in `dist/release/` (`HyperBuf-<version>.zip`, `HyperBuf-<version>.dmg`, `SHA256SUMS`). During signing, you may be asked to allow keychain access.

7. **Check before distribution.** §3 "Verification on a clean Mac".
8. **Publish.** §4.

## 3. Verification on a clean Mac (before distribution)

Verify the notarization result on another Mac (or a new user) for real. **Also verify on an Intel Mac** (the x86_64 part of the Universal binary may not be runnable on the development machine).

1. Hand over the `.dmg` through a path that **sets the quarantine attribute**, such as a browser or AirDrop. To reproduce it locally: `xattr -w com.apple.quarantine "0081;$(printf %x $(date +%s));Safari;" <file>`.
2. Open the `.dmg`, drag `HyperBuf.app` to `/Applications` and launch it. **No Gatekeeper warning appears** (a failure if "the developer cannot be verified" appears).
3. `spctl -a -vv -t exec /Applications/HyperBuf.app` reports `accepted` and `source=Notarized Developer ID`. `codesign --verify --deep --strict` passes.
4. Launch it, open a document, and confirm that Mermaid, math and code blocks render. Confirm that the `hyperbuf` CLI (`Resources/bin/hyperbuf`) can open a file. Confirm there is no external network traffic (checking with Little Snitch or similar is the most reliable).
5. The confirmation dialog on first launch ("an app downloaded from the Internet") may appear normally for a notarized app.

## 4. Publishing (GitHub Releases)

**Procedure.** Publishing the source and the first public GitHub Release (v1.0.0) are the last steps of M8 ([migration-plan.md](../history/migration-plan.md)). The GitHub Release flow itself was already exercised with the private repository for v0.1.2. Before publication, artifacts are handed over through private sharing (distribution to the people involved).

1. Tag (`v<version>`) the `main` commit from which the real build was made, and push it.

   ```bash
   git tag -a v<version> -m "HyperBuf <version>"
   git push origin v<version>
   ```

2. Upload the artifacts and `SHA256SUMS` to GitHub Releases. For the release notes, use the section of `CHANGELOG.md` for that version.

   ```bash
   awk '/^## \[<version>\]/{f=1;next} /^## \[/{f=0} f' CHANGELOG.md > /tmp/notes.md
   gh release create v<version> dist/release/HyperBuf-<version>.zip dist/release/HyperBuf-<version>.dmg dist/release/SHA256SUMS \
     --title "HyperBuf <version>" --notes-file /tmp/notes.md
   ```

3. The downloaded `.dmg` matches `SHA256SUMS` and passes the §3 verification.

## 5. Open items

Items that affect the release procedure. The other remaining distribution work (the Homebrew cask, preparation for publishing the source, and so on) is M8 in [migration-plan.md](../history/migration-plan.md).

- **Release automation (GitHub Actions).** Whether to keep the signing secrets in CI needs a decision, so releases start out manual.
- **Automatic updates (Sparkle, for example).** They involve external network access, so they need to be reconciled with the "Local first" policy. None for now.
