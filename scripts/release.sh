#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Yasuo Hojo
# Builds release artifacts: Developer ID signing → notarization → stapling → .zip / .dmg → checksums.
# Steps and prerequisites: docs/dev/release.md
#
# Usage:
#   scripts/release.sh --dry-run only try assembling and packaging with ad-hoc signing (no notarization; do
# not distribute)
#   scripts/release.sh             sign and notarize, producing distributable artifacts
#
# Environment variables:
#   HYPERBUF_SIGN_IDENTITY certificate used for signing ("Developer ID Application: …"). If omitted, the one
# in the keychain
#                            is used when there is exactly one
#   HYPERBUF_NOTARY_PROFILE saved name of the notarization credentials (created with `xcrun notarytool
# store-credentials`).
#                            This script does not accept an Apple ID, password or API key (only the keychain
# profile is used)
#   HYPERBUF_RELEASE_DIR     where artifacts are placed (default: dist/release)
#   HYPERBUF_ICON            replaces the app icon (.icns) (default: app/macos/Resources/AppIcon.icns)
set -euo pipefail
cd "$(dirname "$0")/.."

dry_run=0
case "${1:-}" in
  --dry-run) dry_run=1 ;;
  "") ;;
  *) echo "usage: scripts/release.sh [--dry-run]" >&2; exit 2 ;;
esac

step() { printf '\n==> %s\n' "$1"; }
die() { echo "NG: $1" >&2; exit 1; }

out="${HYPERBUF_RELEASE_DIR:-dist/release}"
version="$(sed -n 's/^public let hyperBufVersion = "\(.*\)"$/\1/p' app/macos/Sources/HyperBufKit/Version.swift)"
[ -n "$version" ] || die "Cannot read the version (app/macos/Sources/HyperBufKit/Version.swift)"
app="app/macos/.build/HyperBuf.app"
name="HyperBuf-$version"

# --- Signing certificate and notarization profile --------------------------------------------------
if [ "$dry_run" -eq 1 ]; then
  identity="-"
  timestamp="--timestamp=none"
else
  identity="${HYPERBUF_SIGN_IDENTITY:-}"
  if [ -z "$identity" ]; then
    found="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: .*\)"$/\1/p')"
    [ "$(printf '%s\n' "$found" | grep -c .)" -eq 1 ] \
      || die "Cannot pick a single Developer ID Application certificate. Set HYPERBUF_SIGN_IDENTITY (found: ${found:-none})"
    identity="$found"
  fi
  [ -n "${HYPERBUF_NOTARY_PROFILE:-}" ] \
    || die "HYPERBUF_NOTARY_PROFILE is not set (the stored name of the notarization credentials; docs/dev/release.md step 2)"
  xcrun notarytool history --keychain-profile "$HYPERBUF_NOTARY_PROFILE" >/dev/null 2>&1 \
    || die "Cannot use the notarization profile '$HYPERBUF_NOTARY_PROFILE' (create it with xcrun notarytool store-credentials)"
  timestamp="--timestamp"
fi
echo "Version: $version / signing: $identity / output: $out"

# --- Checks and assembly ----------------------------------------------------------------------------
step "Checks (license headers, version strings, license list)"
scripts/check.sh license
scripts/check.sh version
(cd core && npm ci --silent && node scripts/licenses.mjs check)

step "Assemble (release build)"
app/macos/scripts/make-app.sh release >/dev/null
[ -d "$app" ] || die "$app does not exist"

# --- Signing (inside out. Hardened Runtime + secure timestamp) -------------------------------------
step "Sign"
sign() { codesign --force --options runtime "$timestamp" --sign "$identity" "$@"; }
sign "$app/Contents/Resources/bin/hyperbuf"
sign "$app"
codesign --verify --strict --verbose=2 "$app"
codesign --verify --strict "$app/Contents/Resources/bin/hyperbuf"
codesign -d --entitlements - --verbose=2 "$app" 2>&1 | grep -E "flags|Authority|TeamIdentifier|Timestamp|Identifier=" || true

rm -rf "$out"
mkdir -p "$out"

notarize() { # $1=file (.zip / .dmg)
  xcrun notarytool submit "$1" --keychain-profile "$HYPERBUF_NOTARY_PROFILE" --wait --output-format json \
    >"$out/notary-result.json" || { cat "$out/notary-result.json" >&2; die "notarization submission failed"; }
  status="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("status",""))' "$out/notary-result.json")"
  id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("id",""))' "$out/notary-result.json")"
  if [ "$status" != "Accepted" ]; then
    xcrun notarytool log "$id" --keychain-profile "$HYPERBUF_NOTARY_PROFILE" >&2 || true
    die "notarization was not accepted (status=$status, id=$id)"
  fi
  echo "Notarization: Accepted ($id)"
}

# --- Notarization and stapling (app) ----------------------------------------------------------------
if [ "$dry_run" -eq 0 ]; then
  step "Notarize (app)"
  ditto -c -k --keepParent "$app" "$out/HyperBuf-notarize.zip"
  notarize "$out/HyperBuf-notarize.zip"
  rm -f "$out/HyperBuf-notarize.zip"
  xcrun stapler staple "$app"
  xcrun stapler validate "$app"
fi

# --- Packaging ----------------------------------------------------------------------------------------
step "Package (.zip / .dmg)"
ditto -c -k --keepParent "$app" "$out/$name.zip"

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
cp -R "$app" "$stage/HyperBuf.app"
ln -s /Applications "$stage/Applications"
cp LICENSE "$stage/LICENSE.txt"
cp NOTICE "$stage/NOTICE.txt"
cp CHANGELOG.md "$stage/CHANGELOG.md"
cp docs/user/getting-started.md "$stage/README.md"
# Emacs integration (GPL-3.0-or-later. Bundled with its license as a separate program from the app)
mkdir "$stage/emacs"
cp emacs/hyperbuf.el emacs/README.md emacs/LICENSE "$stage/emacs/"
hdiutil create -volname "HyperBuf $version" -srcfolder "$stage" -ov -format UDZO "$out/$name.dmg" >/dev/null
codesign --force "$timestamp" --sign "$identity" "$out/$name.dmg"

if [ "$dry_run" -eq 0 ]; then
  step "Notarize (.dmg)"
  notarize "$out/$name.dmg"
  xcrun stapler staple "$out/$name.dmg"
  xcrun stapler validate "$out/$name.dmg"
fi

# --- Checksums and final checks -------------------------------------------------------------------------
step "Checksums and verification"
(cd "$out" && shasum -a 256 "$name.zip" "$name.dmg" >SHA256SUMS && cat SHA256SUMS)
if [ "$dry_run" -eq 0 ]; then
  spctl -a -vv -t exec "$app"
  spctl -a -vv -t open --context context:primary-signature "$out/$name.dmg"
else
  echo "(dry-run: ad-hoc signed, so Gatekeeper assessment and notarization are skipped. Do not distribute)"
fi
printf '\nOK: %s\n' "$out"
