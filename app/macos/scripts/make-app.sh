#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Yasuo Hojo
# HyperBuf.app を組み立てる(開発用)。Web コア(core/dist)を Contents/Resources/web に同梱する。
# 署名は ad-hoc(ローカルで動かす用)。Developer ID 署名と公証は M8 で、このスクリプトを拡張して行う。
# 使い方: app/macos/scripts/make-app.sh [debug|release]   (既定: release)  → app/macos/.build/HyperBuf.app
set -euo pipefail
cd "$(dirname "$0")/../../.."   # リポジトリのルート

config="${1:-release}"
(cd core && npm ci --silent && npm run build >/dev/null)
(cd app/macos && swift build -c "$config" >/dev/null)

app="app/macos/.build/HyperBuf.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "app/macos/.build/$config/HyperBuf" "$app/Contents/MacOS/HyperBuf"
cp -R core/dist "$app/Contents/Resources/web"
# 同梱したサードパーティのソフトウェアの著作権表示とライセンス(配布の条件)。Web の配信範囲(web/)の外に置く
cp LICENSE "$app/Contents/Resources/LICENSE.txt"
cp NOTICE "$app/Contents/Resources/NOTICE.txt"
(cd core && node scripts/licenses.mjs notices "../$app/Contents/Resources/THIRD-PARTY-NOTICES.txt" >/dev/null)

# Bundle ID は、所有するドメイン(yhojo.com)の逆順(docs/migration-plan.md §8)。
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>HyperBuf</string>
  <key>CFBundleIdentifier</key><string>com.yhojo.hyperbuf</string>
  <key>CFBundleName</key><string>HyperBuf</string>
  <key>CFBundleDisplayName</key><string>HyperBuf</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.0.0</string>
  <key>CFBundleVersion</key><string>0</string>
  <key>NSHumanReadableCopyright</key><string>Copyright 2026 Yasuo Hojo. Apache License 2.0.</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <!-- hyperbuf:// : アプリの起動と、外部リンクからの「開く」(docs/integration-protocol.md §4.1) -->
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key><string>com.yhojo.hyperbuf.url</string>
      <key>CFBundleURLSchemes</key><array><string>hyperbuf</string></array>
    </dict>
  </array>
  <!-- Finder の「このアプリケーションで開く」・Dock へのドラッグ&ドロップ(Markdown とフォルダ)。
       既定のアプリにはならない(Alternate)。docs/project-model.md §3.1 -->
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>Markdown</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>LSItemContentTypes</key>
      <array><string>net.daringfireball.markdown</string></array>
      <key>CFBundleTypeExtensions</key><array><string>md</string><string>markdown</string></array>
    </dict>
    <dict>
      <key>CFBundleTypeName</key><string>Folder</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>LSItemContentTypes</key>
      <array><string>public.folder</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST
codesign --force --sign - "$app" >/dev/null 2>&1
echo "$app"
