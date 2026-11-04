#!/bin/bash
set -e

PRODUCT_NAME="InstantSpaceSwitcher"
BUILD_DIR="build"
APP_BUNDLE="${BUILD_DIR}/${PRODUCT_NAME}.app"

# Extract version from Info.plist
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist 2>/dev/null || echo "unknown")
DMG_NAME="${BUILD_DIR}/${PRODUCT_NAME}-${VERSION}.dmg"

# Check if create-dmg is installed
if ! command -v create-dmg &> /dev/null; then
  echo "Error: create-dmg not found. Install with: brew install create-dmg"
  exit 1
fi

# Check if app bundle exists
if [ ! -d "${APP_BUNDLE}" ]; then
  echo "Error: ${APP_BUNDLE} not found. Run build.sh first."
  exit 1
fi

echo "Creating DMG..."
rm -f "${DMG_NAME}"

VOLICON_ARGS=()
if [ -f "Resources/ISS.icns" ]; then
  VOLICON_ARGS+=(--volicon "Resources/ISS.icns")
fi

create-dmg \
  --volname "${PRODUCT_NAME}" \
  "${VOLICON_ARGS[@]}" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "${PRODUCT_NAME}.app" 175 190 \
  --hide-extension "${PRODUCT_NAME}.app" \
  --app-drop-link 425 190 \
  "${DMG_NAME}" \
  "${APP_BUNDLE}"

echo "DMG created at $(pwd)/${DMG_NAME}"
