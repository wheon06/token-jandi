#!/bin/bash
set -e

APP_NAME="Token Jandi"
BUNDLE_ID="com.heeyeonlee.token-jandi"
VERSION="0.4.0"
BUILD_DIR=".build/release"
APP_DIR="dist/${APP_NAME}.app"
SIGN_IDENTITY="Developer ID Application: HEEYEON LEE (8ZJ7CHXMW2)"
TEAM_ID="8ZJ7CHXMW2"

echo "=== Building ${APP_NAME} v${VERSION} ==="

# 1. Build release
echo "→ Compiling..."
swift build -c release

# 2. Create .app bundle
rm -rf "dist"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${BUILD_DIR}/TokenJandi" "${APP_DIR}/Contents/MacOS/TokenJandi"

# Copy app icon
cp "TokenJandi/Resources/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"

# 3. Info.plist
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
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
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

# 4. Entitlements
cat > "/tmp/token-jandi.entitlements" << ENTITLEMENTS
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
</dict>
</plist>
ENTITLEMENTS

# 5. Code sign
echo "→ Signing..."
codesign --force --deep --options runtime \
    --sign "${SIGN_IDENTITY}" \
    --entitlements "/tmp/token-jandi.entitlements" \
    "${APP_DIR}"

echo "→ Verifying signature..."
codesign --verify --deep --strict "${APP_DIR}"
echo "✅ Signature verified"

# 6. Create ZIP for notarization
echo "→ Creating ZIP..."
cd dist
zip -r "${APP_NAME}-${VERSION}.zip" "${APP_NAME}.app"
cd ..

# 7. Notarize
echo "→ Notarizing (this may take a few minutes)..."
xcrun notarytool submit "dist/${APP_NAME}-${VERSION}.zip" \
    --keychain-profile "AC_PASSWORD" \
    --wait

# 8. Staple
echo "→ Stapling..."
xcrun stapler staple "${APP_DIR}"

# 9. Re-create ZIP with stapled app
rm "dist/${APP_NAME}-${VERSION}.zip"
cd dist
zip -r "${APP_NAME}-${VERSION}.zip" "${APP_NAME}.app"
cd ..

echo ""
echo "=== Done ==="
echo "✅ ${APP_DIR} (signed + notarized)"
echo "✅ dist/${APP_NAME}-${VERSION}.zip"
