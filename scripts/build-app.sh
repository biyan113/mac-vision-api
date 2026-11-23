#!/bin/bash
# 把 AppKit 图形界面打包成可双击运行的 .build/VisionApp.app
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release --product VisionApp
BIN_DIR="$(swift build -c release --show-bin-path)"

APP_DIR=".build/VisionApp.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
cp "$BIN_DIR/VisionApp" "$APP_DIR/Contents/MacOS/VisionApp"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>VisionApp</string>
    <key>CFBundleIdentifier</key>
    <string>local.vision-api.VisionApp</string>
    <key>CFBundleName</key>
    <string>Vision</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

echo "已生成 $APP_DIR"
echo "运行：open $APP_DIR"
