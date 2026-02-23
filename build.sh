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

FRAMEWORKS="-framework AppKit -framework IOKit -framework CoreBluetooth -framework ServiceManagement -framework UserNotifications"

swiftc $SOURCES \
    -target arm64-apple-macos13.0 \
    -O \
    $FRAMEWORKS \
    -o "${MACOS_DIR}/${APP_NAME}_arm64"

swiftc $SOURCES \
    -target x86_64-apple-macos13.0 \
    -O \
    $FRAMEWORKS \
    -o "${MACOS_DIR}/${APP_NAME}_x86_64"

lipo -create "${MACOS_DIR}/${APP_NAME}_arm64" "${MACOS_DIR}/${APP_NAME}_x86_64" \
    -output "${MACOS_DIR}/${APP_NAME}"
rm "${MACOS_DIR}/${APP_NAME}_arm64" "${MACOS_DIR}/${APP_NAME}_x86_64"

cp Info.plist "${CONTENTS_DIR}/Info.plist"
cp Resources/AppIcon.icns "${RESOURCES_DIR}/AppIcon.icns"

codesign --force --sign - --entitlements /dev/stdin "${BUNDLE_DIR}" <<ENTITLEMENTS
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.device.bluetooth</key>
    <true/>
</dict>
</plist>
ENTITLEMENTS

echo "Built ${BUNDLE_DIR} successfully."
