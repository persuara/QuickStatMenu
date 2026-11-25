#!/bin/bash
# persuara
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP=MenuStats.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp .build/release/MenuStats "$APP/Contents/MacOS/MenuStats"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>MenuStats</string>
  <key>CFBundleIdentifier</key><string>com.local.MenuStats</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleExecutable</key><string>MenuStats</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
pkill -x MenuStats 2>/dev/null || true
rm -rf "/Applications/$APP"
mv "$APP" "/Applications/$APP"
echo "Installed /Applications/$APP — run with: open /Applications/$APP"
