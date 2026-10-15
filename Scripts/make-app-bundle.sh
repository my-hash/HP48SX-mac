#!/bin/sh
set -e
cd "$(dirname "$0")/.."

swift build -c release

APP="build/HP48SXMac.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

BIN_PATH=$(swift build -c release --show-bin-path)
cp "$BIN_PATH/HP48SXMac" "$APP/Contents/MacOS/"
cp -R "$BIN_PATH/HP48SXMac_HP48SXMac.bundle" "$APP/Contents/Resources/"
cp "Assets/AppIcon.icns" "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>48SX</string>
    <key>CFBundleDisplayName</key><string>48SX</string>
    <key>CFBundleIdentifier</key><string>com.my-hash.hp48sxmac</string>
    <key>CFBundleVersion</key><string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleExecutable</key><string>HP48SXMac</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "Built $APP"
