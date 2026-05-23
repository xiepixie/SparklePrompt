#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="SparklePrompt"
EXEC_NAME="SparklePrompt"
BUNDLE_ID="com.sparkle.sparkleprompt"
APP_DIR=".build/${APP_NAME}.app"
DESKTOP_APP="$HOME/Desktop/${APP_NAME}.app"

echo "Building binary..."
swift build -c release

echo "Assembling app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp ".build/release/${EXEC_NAME}" "$APP_DIR/Contents/MacOS/${EXEC_NAME}"

echo "Generating icon..."
ICON_PNG="$APP_DIR/Contents/Resources/icon-1024.png"
swift Tools/MakeIcon.swift "$ICON_PNG"

ICONSET="$APP_DIR/Contents/Resources/AppIcon.iconset"
mkdir -p "$ICONSET"
sips -z 16   16   "$ICON_PNG" --out "$ICONSET/icon_16x16.png"     >/dev/null
sips -z 32   32   "$ICON_PNG" --out "$ICONSET/icon_16x16@2x.png"  >/dev/null
sips -z 32   32   "$ICON_PNG" --out "$ICONSET/icon_32x32.png"     >/dev/null
sips -z 64   64   "$ICON_PNG" --out "$ICONSET/icon_32x32@2x.png"  >/dev/null
sips -z 128  128  "$ICON_PNG" --out "$ICONSET/icon_128x128.png"   >/dev/null
sips -z 256  256  "$ICON_PNG" --out "$ICONSET/icon_128x128@2x.png">/dev/null
sips -z 256  256  "$ICON_PNG" --out "$ICONSET/icon_256x256.png"   >/dev/null
sips -z 512  512  "$ICON_PNG" --out "$ICONSET/icon_256x256@2x.png">/dev/null
sips -z 512  512  "$ICON_PNG" --out "$ICONSET/icon_512x512.png"   >/dev/null
cp "$ICON_PNG" "$ICONSET/icon_512x512@2x.png"

iconutil -c icns "$ICONSET" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET" "$ICON_PNG"

echo "Writing Info.plist..."
cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>SparklePrompt</string>
    <key>CFBundleDisplayName</key>
    <string>SparklePrompt</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>${EXEC_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
    <key>NSSupportsSuddenTermination</key>
    <true/>
</dict>
</plist>
EOF

echo "Ad-hoc codesigning..."
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo "Installing to Desktop..."
rm -rf "$DESKTOP_APP"
cp -R "$APP_DIR" "$DESKTOP_APP"
xattr -cr "$DESKTOP_APP" 2>/dev/null || true

echo
echo "Done."
echo "  Icon installed: $DESKTOP_APP"
echo "  Double-click it to launch."
