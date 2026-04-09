#!/bin/bash
set -e

APP_NAME="Token Jandi"
VERSION="1.1.0"
SCHEME="token-jandi"
PROJECT="token-jandi.xcodeproj"
SIGN_IDENTITY="Developer ID Application: HEEYEON LEE (8ZJ7CHXMW2)"
BUILD_DIR="build"
ARCHIVE_PATH="${BUILD_DIR}/TokenJandi.xcarchive"
EXPORT_PATH="${BUILD_DIR}/export"
DIST_DIR="dist"

echo "=== Building ${APP_NAME} v${VERSION} ==="

# 1. Clean & Archive
echo "→ Archiving..."
xcodebuild archive \
    -project "${PROJECT}" \
    -scheme "${SCHEME}" \
    -archivePath "${ARCHIVE_PATH}" \
    -configuration Release \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="${SIGN_IDENTITY}" \
    DEVELOPMENT_TEAM="8ZJ7CHXMW2" \
    2>&1 | tail -3

# 2. Export for direct distribution
echo "→ Exporting..."
cat > "${BUILD_DIR}/export-options.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>8ZJ7CHXMW2</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
    -archivePath "${ARCHIVE_PATH}" \
    -exportOptionsPlist "${BUILD_DIR}/export-options.plist" \
    -exportPath "${EXPORT_PATH}" \
    2>&1 | tail -3

# 3. Notarize
echo "→ Notarizing..."
rm -rf "${DIST_DIR}"
mkdir -p "${DIST_DIR}"
BUNDLE_NAME="token-jandi"
cd "${EXPORT_PATH}"
zip -r "../../${DIST_DIR}/Token.Jandi-${VERSION}.zip" "${BUNDLE_NAME}.app"
cd ../..

xcrun notarytool submit "${DIST_DIR}/Token.Jandi-${VERSION}.zip" \
    --keychain-profile "AC_PASSWORD" \
    --wait

# 4. Staple
echo "→ Stapling..."
xcrun stapler staple "${EXPORT_PATH}/${BUNDLE_NAME}.app"

# 5. Re-zip with stapled app
rm "${DIST_DIR}/Token.Jandi-${VERSION}.zip"
cd "${EXPORT_PATH}"
zip -r "../../${DIST_DIR}/Token.Jandi-${VERSION}.zip" "${BUNDLE_NAME}.app"
cd ../..

echo ""
echo "=== Done ==="
echo "✅ ${DIST_DIR}/Token.Jandi-${VERSION}.zip (signed + notarized)"
