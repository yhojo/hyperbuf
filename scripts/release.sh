#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Yasuo Hojo
# リリースの成果物を作る: Developer ID 署名 → 公証 → ステープル → .zip / .dmg → チェックサム。
# 手順と前提: docs/release.md
#
# 使い方:
#   scripts/release.sh --dry-run   ad-hoc 署名で、組み立てとパッケージ化だけを試す(公証しない。配布しない)
#   scripts/release.sh             署名・公証して、配布できる成果物を作る
#
# 環境変数:
#   HYPERBUF_SIGN_IDENTITY   署名に使う証明書(「Developer ID Application: …」)。省略すると、キーチェーンに
#                            1 つだけある場合に、それを使う
#   HYPERBUF_NOTARY_PROFILE  公証の認証情報の保存名(`xcrun notarytool store-credentials` で作る)。
#                            このスクリプトは、Apple ID・パスワード・API キーを受け取らない(キーチェーンのプロファイルだけを使う)
#   HYPERBUF_RELEASE_DIR     成果物の置き場所(既定: dist/release)
#   HYPERBUF_ICON            アプリのアイコン(.icns)を差し替える(既定: app/macos/Resources/AppIcon.icns)
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
[ -n "$version" ] || die "バージョンを読めません(app/macos/Sources/HyperBufKit/Version.swift)"
app="app/macos/.build/HyperBuf.app"
name="HyperBuf-$version"

# --- 署名の証明書と、公証のプロファイル ------------------------------------------------------------
if [ "$dry_run" -eq 1 ]; then
  identity="-"
  timestamp="--timestamp=none"
else
  identity="${HYPERBUF_SIGN_IDENTITY:-}"
  if [ -z "$identity" ]; then
    found="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: .*\)"$/\1/p')"
    [ "$(printf '%s\n' "$found" | grep -c .)" -eq 1 ] \
      || die "Developer ID Application の証明書が 1 つに決まりません。HYPERBUF_SIGN_IDENTITY を指定してください(見つかったもの: ${found:-なし})"
    identity="$found"
  fi
  [ -n "${HYPERBUF_NOTARY_PROFILE:-}" ] \
    || die "HYPERBUF_NOTARY_PROFILE がありません(公証の認証情報の保存名。docs/release.md の手順 2)"
  xcrun notarytool history --keychain-profile "$HYPERBUF_NOTARY_PROFILE" >/dev/null 2>&1 \
    || die "公証のプロファイル「$HYPERBUF_NOTARY_PROFILE」を使えません(xcrun notarytool store-credentials で作ります)"
  timestamp="--timestamp"
fi
echo "バージョン: $version / 署名: $identity / 出力: $out"

# --- 検査と組み立て ---------------------------------------------------------------------------------
step "検査(ライセンス表記・ライセンスの一覧)"
scripts/check.sh license
(cd core && npm ci --silent && node scripts/licenses.mjs check)

step "組み立て(release ビルド)"
app/macos/scripts/make-app.sh release >/dev/null
[ -d "$app" ] || die "$app がありません"

# --- 署名(内側から外側へ。Hardened Runtime + セキュアタイムスタンプ) -------------------------------
step "署名"
sign() { codesign --force --options runtime "$timestamp" --sign "$identity" "$@"; }
sign "$app/Contents/Resources/bin/hyperbuf"
sign "$app"
codesign --verify --strict --verbose=2 "$app"
codesign --verify --strict "$app/Contents/Resources/bin/hyperbuf"
codesign -d --entitlements - --verbose=2 "$app" 2>&1 | grep -E "flags|Authority|TeamIdentifier|Timestamp|Identifier=" || true

rm -rf "$out"
mkdir -p "$out"

notarize() { # $1=ファイル(.zip / .dmg)
  xcrun notarytool submit "$1" --keychain-profile "$HYPERBUF_NOTARY_PROFILE" --wait --output-format json \
    >"$out/notary-result.json" || { cat "$out/notary-result.json" >&2; die "公証の提出に失敗しました"; }
  status="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("status",""))' "$out/notary-result.json")"
  id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("id",""))' "$out/notary-result.json")"
  if [ "$status" != "Accepted" ]; then
    xcrun notarytool log "$id" --keychain-profile "$HYPERBUF_NOTARY_PROFILE" >&2 || true
    die "公証が受理されませんでした(status=$status, id=$id)"
  fi
  echo "公証: Accepted ($id)"
}

# --- 公証とステープル(アプリ) -----------------------------------------------------------------------
if [ "$dry_run" -eq 0 ]; then
  step "公証(アプリ)"
  ditto -c -k --keepParent "$app" "$out/HyperBuf-notarize.zip"
  notarize "$out/HyperBuf-notarize.zip"
  rm -f "$out/HyperBuf-notarize.zip"
  xcrun stapler staple "$app"
  xcrun stapler validate "$app"
fi

# --- パッケージ化 -------------------------------------------------------------------------------------
step "パッケージ化(.zip / .dmg)"
ditto -c -k --keepParent "$app" "$out/$name.zip"

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
cp -R "$app" "$stage/HyperBuf.app"
ln -s /Applications "$stage/Applications"
cp LICENSE "$stage/LICENSE.txt"
cp NOTICE "$stage/NOTICE.txt"
cp app/macos/Resources/dmg/README.md "$stage/README.md"
# Emacs 連携(GPL-3.0-or-later。アプリとは別のプログラムとして、ライセンスを添えて同梱する)
mkdir "$stage/emacs"
cp emacs/hyperbuf.el emacs/README.md emacs/LICENSE "$stage/emacs/"
hdiutil create -volname "HyperBuf $version" -srcfolder "$stage" -ov -format UDZO "$out/$name.dmg" >/dev/null
codesign --force "$timestamp" --sign "$identity" "$out/$name.dmg"

if [ "$dry_run" -eq 0 ]; then
  step "公証(.dmg)"
  notarize "$out/$name.dmg"
  xcrun stapler staple "$out/$name.dmg"
  xcrun stapler validate "$out/$name.dmg"
fi

# --- チェックサムと、最終の検査 -------------------------------------------------------------------------
step "チェックサムと検査"
(cd "$out" && shasum -a 256 "$name.zip" "$name.dmg" >SHA256SUMS && cat SHA256SUMS)
if [ "$dry_run" -eq 0 ]; then
  spctl -a -vv -t exec "$app"
  spctl -a -vv -t open --context context:primary-signature "$out/$name.dmg"
else
  echo "(dry-run: ad-hoc 署名のため、Gatekeeper の評価と公証は行いません。配布しないでください)"
fi
printf '\nOK: %s\n' "$out"
