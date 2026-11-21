#!/bin/bash
# Ships one version everywhere, with the same version number:
#
#   1. sets the app version (and the next build number) in the Xcode project
#   2. runs the unit tests
#   3. archives the Mac App Store build and uploads it to App Store Connect
#   4. submits the build for App Store review (needs an API key, see below)
#   5. tags v<version> and pushes main and the tag to GitHub
#
# Pushing the tag triggers .github/workflows/release.yml, which publishes the
# GitHub release from the version's section in RELEASE_NOTES.md.
#
# Usage:
#   scripts/release.sh 1.4.1
#   scripts/release.sh 1.4.1 --skip-upload   # the build is already on App Store Connect
#
# Before running: write the "## <version>" section in RELEASE_NOTES.md, update
# "What's New in <version>" in README.md and the App Store texts in
# store/whats-new/, commit, and be on a clean main.
#
# App Store Connect API key (App Manager role): put these three lines in
# ~/.config/token-jandi/release.env, or export them:
#
#   ASC_KEY_PATH=~/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8
#   ASC_KEY_ID=XXXXXXXXXX
#   ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
#
# With the key, the build is signed, uploaded and submitted for review. Without
# it, the upload uses the Apple account signed in to Xcode and the submission is
# left to do by hand in App Store Connect.
set -euo pipefail

cd "$(dirname "$0")/.."

RELEASE_ENV="${HOME}/.config/token-jandi/release.env"
if [ -f "${RELEASE_ENV}" ]; then
    set -a
    # shellcheck disable=SC1090
    . "${RELEASE_ENV}"
    set +a
fi
ASC_KEY_PATH="${ASC_KEY_PATH:-}"
ASC_KEY_PATH="${ASC_KEY_PATH/#\~/${HOME}}"

SCHEME="token-jandi"
PROJECT="token-jandi.xcodeproj"
PBXPROJ="${PROJECT}/project.pbxproj"
CONFIGURATION="AppStore Release"
TEAM_ID="8ZJ7CHXMW2"
BUILD_DIR="build"
ARCHIVE_PATH="${BUILD_DIR}/TokenJandi-AppStore.xcarchive"

step() { printf '\n==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# Runs a noisy command with its output in a log file; on failure shows the
# errors (or the end of the log) and stops.
run_logged() {
    local name="$1" message="$2"
    shift 2
    local log="${BUILD_DIR}/release-${name}.log"
    mkdir -p "${BUILD_DIR}"
    if ! "$@" > "${log}" 2>&1; then
        grep -E "error:|\*\* .* FAILED" "${log}" | sort -u | tail -15 || true
        die "${message} (full log: ${log})"
    fi
}

VERSION="${1:-}"
SKIP_UPLOAD=false
[ "${2:-}" = "--skip-upload" ] && SKIP_UPLOAD=true
[[ "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "usage: scripts/release.sh <major.minor.patch> [--skip-upload]"
TAG="v${VERSION}"

project_setting() {
    sed -n "s/.*$1 = \(.*\);/\1/p" "${PBXPROJ}" | sort -u
}

# 1. Preflight: fail before anything leaves this Mac.
step "Checking the repository"
[ "$(git branch --show-current)" = "main" ] || die "switch to main first"
[ -z "$(git status --porcelain)" ] || die "the working tree has uncommitted changes"
git fetch --quiet origin --tags
git merge-base --is-ancestor origin/main HEAD || die "main is behind origin/main; pull first"
if git ls-remote --exit-code --tags origin "refs/tags/${TAG}" >/dev/null 2>&1; then
    die "${TAG} is already on GitHub"
fi
scripts/release-notes.sh "${VERSION}" >/dev/null
grep -q "What's New in ${VERSION}" README.md || die "README.md has no \"What's New in ${VERSION}\" section"
if [ -n "${ASC_KEY_PATH:-}" ]; then
    [ -f "${ASC_KEY_PATH}" ] || die "API key file not found: ${ASC_KEY_PATH}"
    : "${ASC_KEY_ID:?set ASC_KEY_ID}" "${ASC_ISSUER_ID:?set ASC_ISSUER_ID}"
    # The App Store text is per release; refuse to resubmit the previous one.
    PREVIOUS_TAG=$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)
    if [ -n "${PREVIOUS_TAG}" ] && git diff --quiet "${PREVIOUS_TAG}" -- store/whats-new; then
        die "store/whats-new still has the text from ${PREVIOUS_TAG}; write this version's"
    fi
fi

# 2. Version: every target gets the same version; the build number goes up by one.
if [ "$(project_setting MARKETING_VERSION)" != "${VERSION}" ]; then
    BUILD=$(( $(project_setting CURRENT_PROJECT_VERSION | sort -n | tail -1) + 1 ))
    step "Setting version ${VERSION} (build ${BUILD})"
    sed -i '' -E \
        -e "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = ${VERSION};/" \
        -e "s/CURRENT_PROJECT_VERSION = [^;]+;/CURRENT_PROJECT_VERSION = ${BUILD};/" \
        "${PBXPROJ}"
    git commit --quiet -m "chore: 버전을 ${VERSION}(빌드 ${BUILD})으로 상향" -- "${PBXPROJ}"
fi
BUILD=$(project_setting CURRENT_PROJECT_VERSION)
[ "$(printf '%s\n' "${BUILD}" | wc -l | tr -d ' ')" = "1" ] || die "targets disagree on the build number"
echo "Version ${VERSION}, build ${BUILD}"

# 3. Tests
step "Running unit tests"
run_logged test "tests failed" xcodebuild test \
    -project "${PROJECT}" \
    -scheme "${SCHEME}" \
    -destination 'platform=macOS' \
    -derivedDataPath "${BUILD_DIR}/DerivedData-Release" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=""

# 4. App Store
if [ "${SKIP_UPLOAD}" = true ]; then
    step "Skipping the App Store upload"
else
    AUTH=(-allowProvisioningUpdates)
    if [ -n "${ASC_KEY_PATH:-}" ]; then
        AUTH+=(-authenticationKeyPath "${ASC_KEY_PATH}"
               -authenticationKeyID "${ASC_KEY_ID}"
               -authenticationKeyIssuerID "${ASC_ISSUER_ID}")
    fi

    step "Archiving for the Mac App Store"
    rm -rf "${ARCHIVE_PATH}"
    run_logged archive "archive failed" xcodebuild archive \
        -project "${PROJECT}" \
        -scheme "${SCHEME}" \
        -configuration "${CONFIGURATION}" \
        -archivePath "${ARCHIVE_PATH}" \
        "${AUTH[@]}"

    step "Uploading to App Store Connect"
    cat > "${BUILD_DIR}/app-store-export.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>destination</key>
    <string>upload</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
PLIST
    run_logged upload "upload failed; nothing was tagged or pushed. Fix it and run the same command again" \
        xcodebuild -exportArchive \
        -archivePath "${ARCHIVE_PATH}" \
        -exportOptionsPlist "${BUILD_DIR}/app-store-export.plist" \
        -exportPath "${BUILD_DIR}/app-store-export" \
        "${AUTH[@]}"
fi

# 5. Review
if [ -n "${ASC_KEY_PATH:-}" ]; then
    step "Submitting ${VERSION} (${BUILD}) for App Store review"
    scripts/asc-submit.py "${VERSION}" "${BUILD}" \
        || die "submission failed; nothing was tagged or pushed. Fix it and run: scripts/release.sh ${VERSION} --skip-upload"
    REVIEW_STATUS="submitted for review"
else
    REVIEW_STATUS="uploaded; no API key, so submit it for review at https://appstoreconnect.apple.com"
fi

# 6. GitHub: only after the App Store has the build, so the versions never drift.
step "Tagging ${TAG} and pushing to GitHub"
git tag -a "${TAG}" -m "Token Jandi ${VERSION}"
git push origin main "${TAG}"

step "Done"
echo "App Store Connect: build ${VERSION} (${BUILD}) ${REVIEW_STATUS}"
echo "GitHub release:    https://github.com/wheon06/token-jandi/releases/tag/${TAG} (published by the Release workflow)"
