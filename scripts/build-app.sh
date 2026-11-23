#!/bin/bash
# 把 AppKit 图形界面打包成 .build/VisionApp.app，并生成用于分发的 zip。
#
# 可选的环境变量：
#   APP_VERSION        版本号，默认 1.0.0
#   CODESIGN_IDENTITY  Developer ID 签名身份，例如 "Developer ID Application: Your Name (TEAMID)"。
#                      不设置时使用临时（ad-hoc）签名，只适合在本机运行。
#   NOTARY_PROFILE     notarytool 的钥匙串配置名（用 `xcrun notarytool store-credentials` 创建）。
#                      与 CODESIGN_IDENTITY 同时设置时会提交公证并装订票据。
#   APP_ICON           1024x1024 的 PNG 图标路径，默认 Assets/AppIcon.png（文件不存在则不设置图标）。
set -euo pipefail

cd "$(dirname "$0")/.."

APP_VERSION="${APP_VERSION:-1.0.0}"
APP_ICON="${APP_ICON:-Assets/AppIcon.png}"
APP_DIR=".build/VisionApp.app"
ZIP_PATH=".build/VisionApp-${APP_VERSION}.zip"

swift build -c release --product VisionApp
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/VisionApp" "$APP_DIR/Contents/MacOS/VisionApp"

# 内嵌 API 服务需要的静态文件
if [ -d Public ]; then
    cp -R Public "$APP_DIR/Contents/Resources/Public"
fi

# 可选：由 PNG 生成应用图标
ICON_PLIST=""
if [ -f "$APP_ICON" ]; then
    ICONSET="$(mktemp -d)/AppIcon.iconset"
    mkdir -p "$ICONSET"
    for size in 16 32 128 256 512; do
        sips -z "$size" "$size" "$APP_ICON" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
        sips -z "$((size * 2))" "$((size * 2))" "$APP_ICON" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
    ICON_PLIST="    <key>CFBundleIconFile</key>
    <string>AppIcon</string>"
fi

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
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
    <key>CFBundleDisplayName</key>
    <string>Vision</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${APP_VERSION}</string>
${ICON_PLIST}
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Image or PDF</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.image</string>
                <string>com.adobe.pdf</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

if [ -n "${CODESIGN_IDENTITY:-}" ]; then
    codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP_DIR"
else
    codesign --force --sign - "$APP_DIR"
fi

rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

if [ -n "${CODESIGN_IDENTITY:-}" ] && [ -n "${NOTARY_PROFILE:-}" ]; then
    xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP_DIR"
    # 装订票据后重新打包
    rm -f "$ZIP_PATH"
    ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"
fi

echo "已生成 $APP_DIR"
echo "分发包 $ZIP_PATH"
echo "运行：open $APP_DIR"
