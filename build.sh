#!/bin/bash
set -euo pipefail

APP_NAME="BatteryBar"
BUNDLE_DIR="${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

rm -rf "${BUNDLE_DIR}"

mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

SOURCES=$(find Sources -name '*.swift' -type f)
echo "Compiling $(echo "$SOURCES" | wc -l | tr -d ' ') Swift files..."
swiftc $SOURCES \
    -target arm64-apple-macos13.0 \
    -O \
    -framework AppKit \
    -framework IOKit \
    -framework CoreBluetooth \
    -framework ServiceManagement \
    -o "${MACOS_DIR}/${APP_NAME}"

cp Info.plist "${CONTENTS_DIR}/Info.plist"

echo "Built ${BUNDLE_DIR} successfully."
