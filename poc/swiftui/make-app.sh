#!/bin/bash
# PoC 用の .app バンドルを作る(URL スキーム hyperbuf:// の登録・受け取りの検証用)。
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP=.build/Hyperbuf-PoC.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/hyperbuf-poc "$APP/Contents/MacOS/hyperbuf-poc"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>hyperbuf-poc</string>
  <key>CFBundleIdentifier</key><string>dev.hyperbuf.poc</string>
  <key>CFBundleName</key><string>Hyperbuf PoC</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.0.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key><string>dev.hyperbuf.poc.url</string>
      <key>CFBundleURLSchemes</key><array><string>hyperbuf</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
echo "$APP"
