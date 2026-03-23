#!/bin/bash
set -e

PRODUCT_NAME="InstantSpaceSwitcher"
BUILD_PATH=".build/release"
APP_BUNDLE="${PRODUCT_NAME}.app"
APP_PATH="$(pwd)/${APP_BUNDLE}"
INSTALL_PATH="/Applications/${APP_BUNDLE}"

swift build -c release --disable-sandbox

echo "Bundling..."
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"
cp "${BUILD_PATH}/${PRODUCT_NAME}" "${APP_BUNDLE}/Contents/MacOS/"
cp Info.plist "${APP_BUNDLE}/Contents/"

echo "Signing..."
codesign --force --deep --sign - "${APP_BUNDLE}"

if [[ "${1:-}" == "--install" ]]; then
  echo "Installing to ${INSTALL_PATH}..."
  rm -rf "${INSTALL_PATH}"
  cp -R "${APP_BUNDLE}" "${INSTALL_PATH}"
  echo "App installed at ${INSTALL_PATH}"
else
  echo "App bundled at ${APP_PATH}"
  echo "Run './build.sh --install' to copy it to ${INSTALL_PATH}"
fi
