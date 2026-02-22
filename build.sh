#!/bin/bash
set -euo pipefail

APP_NAME="BatteryBar"
BUNDLE_DIR="${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

rm -rf "${BUNDLE_DIR}"

mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

echo "Compiling main.swift..."
swiftc main.swift \
    -target arm64-apple-macos13.0 \
    -framework AppKit \
    -framework IOKit \
    -framework CoreBluetooth \
    -o "${MACOS_DIR}/${APP_NAME}"

cp Info.plist "${CONTENTS_DIR}/Info.plist"

echo "Built ${BUNDLE_DIR} successfully."
