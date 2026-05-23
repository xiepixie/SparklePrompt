#!/usr/bin/env bash
# Builds a universal (arm64 + x86_64) .app bundle and zips it for a GitHub release.
# Usage: ./package-release.sh [version]   (default: reads VERSION file or "0.1.0")
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:-$(cat VERSION 2>/dev/null || echo "0.1.0")}"
APP_NAME="SparklePrompt"
EXEC_NAME="SparklePrompt"
BUNDLE_ID="com.sparkle.sparkleprompt"
APP_DIR=".build/release-package/${APP_NAME}.app"
ZIP_NAME="sparkleprompt-v${VERSION}-macos-universal.zip"
ZIP_PATH=".build/release-package/${ZIP_NAME}"

echo "==> Building universal binary (arm64 + x86_64)..."
rm -rf .build/release-package

# Multi-arch SPM builds require full Xcode (xcbuild). If only Command Line Tools
# are installed, point at Xcode.app via DEVELOPER_DIR for this build.
if [[ ! -x /Library/Developer/SharedFrameworks/XCBuild.framework/Versions/A/Support/xcbuild ]] \
   && [[ -d /Applications/Xcode.app ]]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
    echo "    Using Xcode at: $DEVELOPER_DIR"
fi

swift build -c release --arch arm64 --arch x86_64

BIN_PATH="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/${EXEC_NAME}"
if [[ ! -f "$BIN_PATH" ]]; then
    echo "Build output not found at: $BIN_PATH" >&2
    exit 1
fi
echo "    Binary: $BIN_PATH"
file "$BIN_PATH"

echo "==> Assembling app bundle..."
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/${EXEC_NAME}"

echo "==> Generating icon..."
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

echo "==> Writing Info.plist..."
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
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>${EXEC_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
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

echo "==> Ad-hoc codesigning..."
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo "==> Zipping with ditto (preserves bundle metadata)..."
rm -f "$ZIP_PATH"
ditto -c -k --keepParent --sequesterRsrc "$APP_DIR" "$ZIP_PATH"

ZIP_SIZE=$(du -h "$ZIP_PATH" | cut -f1)
echo
echo "Done."
echo "  App:  $APP_DIR"
echo "  Zip:  $ZIP_PATH  (${ZIP_SIZE})"
echo
echo "Attach the zip to a GitHub release:"
echo "  gh release create v${VERSION} \"$ZIP_PATH\" --title \"v${VERSION}\" --notes-file CHANGELOG.md"
