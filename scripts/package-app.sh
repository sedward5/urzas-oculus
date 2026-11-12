#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP_DIR="$ROOT_DIR/dist/UrzasOculus.app"
ZIP_FILE="$ROOT_DIR/dist/UrzasOculus-macos.zip"

rm -rf "$APP_DIR" "$ZIP_FILE"
mkdir -p "$APP_DIR/Contents/MacOS"

cp "$BIN_DIR/UrzasOculus" "$APP_DIR/Contents/MacOS/UrzasOculus"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>UrzasOculus</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.urzas-oculus</string>
    <key>CFBundleName</key>
    <string>Urza's Oculus</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>0.1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Urza's Oculus captures your mirrored iPhone window to analyze Magic: The Gathering Arena draft packs locally. Screen contents are never transmitted.</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_DIR"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_FILE"

echo "Created: $ZIP_FILE"
