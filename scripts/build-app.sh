#!/bin/bash
set -e

APP_NAME="Token Jandi"
BUNDLE_ID="com.heeyeonlee.token-jandi"
VERSION="0.4.0"
BUILD_DIR=".build/release"
APP_DIR="dist/${APP_NAME}.app"

echo "Building ${APP_NAME} v${VERSION}..."

# Build release
swift build -c release

# Create .app bundle structure
rm -rf "dist"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

# Copy binary
cp "${BUILD_DIR}/TokenJandi" "${APP_DIR}/Contents/MacOS/TokenJandi"

# Copy resources
if [ -d "${BUILD_DIR}/TokenJandi_TokenJandi.bundle" ]; then
    cp -R "${BUILD_DIR}/TokenJandi_TokenJandi.bundle" "${APP_DIR}/Contents/Resources/"
fi

# Create Info.plist
cat > "${APP_DIR}/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleExecutable</key>
    <string>TokenJandi</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Heeyeon Lee. All rights reserved.</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>ko</string>
    </array>
</dict>
</plist>
PLIST

echo "✅ Built: ${APP_DIR}"
echo "   Version: ${VERSION}"
echo "   Bundle ID: ${BUNDLE_ID}"

# Create DMG (optional)
if command -v create-dmg &> /dev/null; then
    echo "Creating DMG..."
    create-dmg \
        --volname "${APP_NAME}" \
        --window-size 400 300 \
        --icon "${APP_NAME}.app" 100 150 \
        --app-drop-link 300 150 \
        "dist/${APP_NAME}-${VERSION}.dmg" \
        "dist/"
    echo "✅ DMG: dist/${APP_NAME}-${VERSION}.dmg"
else
    # Fallback: zip
    cd dist
    zip -r "${APP_NAME}-${VERSION}.zip" "${APP_NAME}.app"
    cd ..
    echo "✅ ZIP: dist/${APP_NAME}-${VERSION}.zip"
fi
