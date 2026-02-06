#!/bin/bash

# ci_post_clone.sh
# Dynamic versioning for Xcode Cloud
#
# This script runs automatically after Xcode Cloud clones the repository.
# It does two things:
#   1. Sets CURRENT_PROJECT_VERSION (build number) to CI_BUILD_NUMBER for all targets
#   2. Syncs MARKETING_VERSION across both targets (main app and keyboard extension)
#      so they always match. The main app's MARKETING_VERSION is the source of truth.
#
# To bump the user-facing version:
#   Change MARKETING_VERSION in Xcode for the main app target (e.g., 5.5 -> 6.0),
#   commit, and trigger a build. The keyboard extension version syncs automatically.

set -e

echo "============================================"
echo "  Xcode Cloud Version Update — SnipKey"
echo "============================================"
echo ""
echo "CI_BUILD_NUMBER:            ${CI_BUILD_NUMBER}"
echo "CI_BRANCH:                  ${CI_BRANCH}"
echo "CI_TAG:                     ${CI_TAG}"
echo "CI_WORKSPACE:               ${CI_WORKSPACE}"
echo "CI_PRIMARY_REPOSITORY_PATH: ${CI_PRIMARY_REPOSITORY_PATH}"
echo ""

# ---------------------------------------------------------------------------
# 1. Locate project.pbxproj
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

PROJECT_FILE=""

for SEARCH_PATH in "$REPO_ROOT" "$CI_PRIMARY_REPOSITORY_PATH" "$CI_WORKSPACE"; do
    CANDIDATE="${SEARCH_PATH}/SnipKey.xcodeproj/project.pbxproj"
    if [[ -f "$CANDIDATE" ]]; then
        PROJECT_FILE="$CANDIDATE"
        break
    fi
done

if [[ -z "$PROJECT_FILE" ]]; then
    echo "Error: project.pbxproj not found"
    echo "Searched in:"
    echo "  - ${REPO_ROOT}/SnipKey.xcodeproj/project.pbxproj"
    echo "  - ${CI_PRIMARY_REPOSITORY_PATH}/SnipKey.xcodeproj/project.pbxproj"
    echo "  - ${CI_WORKSPACE}/SnipKey.xcodeproj/project.pbxproj"
    echo ""
    echo "Directory contents at REPO_ROOT:"
    ls -la "$REPO_ROOT" || true
    exit 1
fi

echo "PROJECT_FILE: $PROJECT_FILE"
echo ""

# ---------------------------------------------------------------------------
# 2. Read current values
# ---------------------------------------------------------------------------

# Main app marketing version (source of truth)
# The main app bundle ID is "jrtv-projects.SnipKey" (without .SnipKeyboard suffix)
# Its MARKETING_VERSION appears right before that bundle ID line
MAIN_APP_MARKETING_VERSION=$(grep -B1 'PRODUCT_BUNDLE_IDENTIFIER = "jrtv-projects.SnipKey";' "$PROJECT_FILE" \
    | grep "MARKETING_VERSION" \
    | head -1 \
    | sed -E 's/.*= ([^;]+);/\1/')

# Keyboard extension marketing version
KEYBOARD_MARKETING_VERSION=$(grep -B1 'PRODUCT_BUNDLE_IDENTIFIER = "jrtv-projects.SnipKey.SnipKeyboard";' "$PROJECT_FILE" \
    | grep "MARKETING_VERSION" \
    | head -1 \
    | sed -E 's/.*= ([^;]+);/\1/')

# Current build number (same across all targets)
CURRENT_BUILD=$(grep -m1 "CURRENT_PROJECT_VERSION" "$PROJECT_FILE" \
    | sed -E 's/.*= ([^;]+);/\1/')

echo "--- Before ---"
echo "Main App    MARKETING_VERSION:      $MAIN_APP_MARKETING_VERSION"
echo "Keyboard    MARKETING_VERSION:      $KEYBOARD_MARKETING_VERSION"
echo "All Targets CURRENT_PROJECT_VERSION: $CURRENT_BUILD"
echo ""

# ---------------------------------------------------------------------------
# 3. Update CURRENT_PROJECT_VERSION (build number) to CI_BUILD_NUMBER
# ---------------------------------------------------------------------------

if [[ -n "$CI_BUILD_NUMBER" ]]; then
    sed -i '' -E "s/CURRENT_PROJECT_VERSION = [^;]+;/CURRENT_PROJECT_VERSION = ${CI_BUILD_NUMBER};/g" "$PROJECT_FILE"
    echo "Updated CURRENT_PROJECT_VERSION -> ${CI_BUILD_NUMBER} (all targets)"
else
    echo "Warning: CI_BUILD_NUMBER is not set. Skipping build number update."
fi

# ---------------------------------------------------------------------------
# 4. Sync MARKETING_VERSION across both targets
#    Use the main app's version as the source of truth.
# ---------------------------------------------------------------------------

if [[ -n "$MAIN_APP_MARKETING_VERSION" ]]; then
    sed -i '' -E "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = ${MAIN_APP_MARKETING_VERSION};/g" "$PROJECT_FILE"
    echo "Synced  MARKETING_VERSION    -> ${MAIN_APP_MARKETING_VERSION} (all targets)"
else
    echo "Warning: Could not read MARKETING_VERSION from main app. Skipping sync."
fi

# ---------------------------------------------------------------------------
# 5. Verify
# ---------------------------------------------------------------------------

echo ""
echo "--- After ---"

VERIFIED_BUILD=$(grep -m1 "CURRENT_PROJECT_VERSION" "$PROJECT_FILE" \
    | sed -E 's/.*= ([^;]+);/\1/')

VERIFIED_MAIN_MARKETING=$(grep -B1 'PRODUCT_BUNDLE_IDENTIFIER = "jrtv-projects.SnipKey";' "$PROJECT_FILE" \
    | grep "MARKETING_VERSION" \
    | head -1 \
    | sed -E 's/.*= ([^;]+);/\1/')

VERIFIED_KEYBOARD_MARKETING=$(grep -B1 'PRODUCT_BUNDLE_IDENTIFIER = "jrtv-projects.SnipKey.SnipKeyboard";' "$PROJECT_FILE" \
    | grep "MARKETING_VERSION" \
    | head -1 \
    | sed -E 's/.*= ([^;]+);/\1/')

echo "Main App    MARKETING_VERSION:      $VERIFIED_MAIN_MARKETING"
echo "Keyboard    MARKETING_VERSION:      $VERIFIED_KEYBOARD_MARKETING"
echo "All Targets CURRENT_PROJECT_VERSION: $VERIFIED_BUILD"
echo ""
echo "============================================"
echo "  Version update complete"
echo "============================================"
