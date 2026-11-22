#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_VERSION="${APP_VERSION:-0.1.0}"
if [[ ! "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "APP_VERSION must use numeric major.minor.patch format (received: $APP_VERSION)"
    exit 1
fi

python3 scripts/sync_reviewed_card_catalog.py

ICON_SOURCE="$ROOT_DIR/Resources/AppIcon.png"
if [[ ! -f "$ICON_SOURCE" ]]; then
    echo "Missing app icon: $ICON_SOURCE"
    exit 1
fi

ROOT_BUILD="$(swift build -c release --show-bin-path)"
swift build -c release

DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/UrzasOculus.app"
ZIP_FILE="$DIST_DIR/UrzasOculus-macos.zip"
DMG_FILE="$DIST_DIR/UrzasOculus.dmg"
STAGING_DIR="$DIST_DIR/dmg-staging"
ICONSET="$DIST_DIR/AppIcon.iconset"

rm -rf "$APP_DIR" "$ZIP_FILE" "$DMG_FILE" "$STAGING_DIR" "$ICONSET"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$ICONSET"

# Generate the macOS icon sizes from the 1024px source.
sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET" -o "$APP_DIR/Contents/Resources/AppIcon.icns"

cp "$ROOT_BUILD/UrzasOculus" "$APP_DIR/Contents/MacOS/UrzasOculus"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
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
    <key>CFBundleDisplayName</key>
    <string>Urza's Oculus</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleVersion</key>
    <string>$APP_VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Urza's Oculus captures your mirrored iPhone window to analyze Magic: The Gathering Arena draft packs locally. Screen contents are never transmitted.</string>
</dict>
</plist>
PLIST

rm -rf "$ICONSET"

# Ad-hoc signing keeps the bundle structurally valid; distribution is not yet notarized.
codesign --force --deep --sign - "$APP_DIR"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_FILE"

# Standard macOS drag-to-install disk image.
mkdir -p "$STAGING_DIR"
cp -R "$APP_DIR" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"
hdiutil create -volname "Urza's Oculus" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_FILE" >/dev/null
rm -rf "$STAGING_DIR"

echo "Created: $ZIP_FILE"
echo "Created: $DMG_FILE"
