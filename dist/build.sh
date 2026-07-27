#!/bin/bash
set -e

CLEAN=false
BUILD_CONFIG="release"

for arg in "$@"; do
  case "$arg" in
    --clean) CLEAN=true ;;
    --debug) BUILD_CONFIG="debug" ;;
    --help)
      echo "Usage: $0 [--clean] [--debug] [--help]"
      echo ""
      echo "Options:"
      echo "  --clean    Delete build directory before building"
      echo "  --debug    Build in debug mode (default: release)"
      echo "  --help     Show this help message"
      exit 0
      ;;
  esac
done

PRODUCT_NAME="InstantSpaceSwitcher"
BUILD_DIR="build"

if [[ "$CLEAN" == true ]]; then
  echo "Cleaning build directory..."
  rm -rf "${BUILD_DIR}"
fi

BUILD_PATH="${BUILD_DIR}/${BUILD_CONFIG}"
APP_BUNDLE="${BUILD_DIR}/${PRODUCT_NAME}.app"

# Build arm64 and x86_64 in parallel
echo "Building arm64 and x86_64 in parallel..."
ARM64_LOG=$(mktemp)
X86_LOG=$(mktemp)

swift build -c "${BUILD_CONFIG}" --arch arm64  --build-path "${BUILD_DIR}/arm64"  --disable-sandbox > "${ARM64_LOG}" 2>&1 &
PID_ARM64=$!
swift build -c "${BUILD_CONFIG}" --arch x86_64 --build-path "${BUILD_DIR}/x86_64" --disable-sandbox > "${X86_LOG}"  2>&1 &
PID_X86=$!

printf "  arm64: starting...\n x86_64: starting...\n"
while kill -0 "${PID_ARM64}" 2>/dev/null || kill -0 "${PID_X86}" 2>/dev/null; do
    ARM_LINE=$(tail -1 "${ARM64_LOG}" 2>/dev/null)
    X86_LINE=$(tail -1 "${X86_LOG}"  2>/dev/null)
    printf "\033[2A\033[2K  arm64: %.110s\n\033[2K x86_64: %.110s\n" \
        "${ARM_LINE:-starting...}" "${X86_LINE:-starting...}"
    sleep 0.2
done

wait "${PID_ARM64}" && ARM64_STATUS=0 || ARM64_STATUS=$?
wait "${PID_X86}"   && X86_STATUS=0  || X86_STATUS=$?

[[ ${ARM64_STATUS} -eq 0 ]] && ARM_FINAL="done" || ARM_FINAL="FAILED"
[[ ${X86_STATUS}   -eq 0 ]] && X86_FINAL="done" || X86_FINAL="FAILED"
printf "\033[2A\033[2K  arm64: %s\n\033[2K x86_64: %s\n" "${ARM_FINAL}" "${X86_FINAL}"

if [[ ${ARM64_STATUS} -ne 0 ]]; then
    echo ""; echo "=== arm64 build output ==="; cat "${ARM64_LOG}"
fi
if [[ ${X86_STATUS} -ne 0 ]]; then
    echo ""; echo "=== x86_64 build output ==="; cat "${X86_LOG}"
fi
rm -f "${ARM64_LOG}" "${X86_LOG}"

[[ ${ARM64_STATUS} -eq 0 ]] || exit 1
[[ ${X86_STATUS}   -eq 0 ]] || exit 1

echo ""
echo "Creating universal binaries..."
mkdir -p "${BUILD_PATH}"
lipo -create \
  "${BUILD_DIR}/arm64/${BUILD_CONFIG}/${PRODUCT_NAME}" \
  "${BUILD_DIR}/x86_64/${BUILD_CONFIG}/${PRODUCT_NAME}" \
  -output "${BUILD_PATH}/${PRODUCT_NAME}"

lipo -create \
  "${BUILD_DIR}/arm64/${BUILD_CONFIG}/ISSCli" \
  "${BUILD_DIR}/x86_64/${BUILD_CONFIG}/ISSCli" \
  -output "${BUILD_PATH}/ISSCli"

echo ""
echo "Bundling..."
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"
cp "${BUILD_PATH}/${PRODUCT_NAME}" "${APP_BUNDLE}/Contents/MacOS/"
cp "${BUILD_PATH}/ISSCli" "${APP_BUNDLE}/Contents/MacOS/"
cp Info.plist "${APP_BUNDLE}/Contents/"

GIT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
echo "Injecting git SHA: ${GIT_SHA}"
/usr/libexec/PlistBuddy -c "Add :GitCommitHash string ${GIT_SHA}" "${APP_BUNDLE}/Contents/Info.plist" 2>/dev/null || \
/usr/libexec/PlistBuddy -c "Set :GitCommitHash ${GIT_SHA}" "${APP_BUNDLE}/Contents/Info.plist"

echo ""
echo "Signing (ad-hoc)..."
codesign --force --deep --sign - "${APP_BUNDLE}"

echo ""
echo "App bundled at $(pwd)/${APP_BUNDLE} (${BUILD_CONFIG})"
