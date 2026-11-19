#!/bin/bash
# Prints the RELEASE_NOTES.md section for one version, without its heading.
# Usage: scripts/release-notes.sh 1.4.1
set -euo pipefail

VERSION="${1:?usage: scripts/release-notes.sh <version>}"
NOTES_FILE="$(dirname "$0")/../RELEASE_NOTES.md"

notes=$(awk -v version="${VERSION}" '
    /^## / { if (found) exit; found = ($2 == version); next }
    found { print }
' "${NOTES_FILE}" | sed -e '/./,$!d')

if [ -z "${notes}" ]; then
    echo "error: RELEASE_NOTES.md has no \"## ${VERSION}\" section" >&2
    exit 1
fi

printf '%s\n' "${notes}"
