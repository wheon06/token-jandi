#!/bin/bash
set -e

APP_NAME="Token Jandi"
SCHEME="token-jandi"
PROJECT="token-jandi.xcodeproj"
CONFIGURATION="AppStore Release"
ARCHIVE_PATH="build/TokenJandi-AppStore.xcarchive"

echo "=== Archiving ${APP_NAME} for the Mac App Store ==="

xcodebuild archive \
    -project "${PROJECT}" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -archivePath "${ARCHIVE_PATH}"

echo ""
echo "=== Done ==="
echo "Archive created at ${ARCHIVE_PATH}"
echo "Upload this archive to App Store Connect using Xcode Organizer or Transporter."
