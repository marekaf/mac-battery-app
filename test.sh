#!/bin/bash
set -euo pipefail

SOURCES=$(find Sources -name '*.swift' -type f | grep -v 'Sources/App/main.swift')
TESTS=$(find Tests -name '*.swift' -type f)

echo "Compiling $(echo "$TESTS" | wc -l | tr -d ' ') test files with $(echo "$SOURCES" | wc -l | tr -d ' ') source files..."

FRAMEWORKS="-framework AppKit -framework IOKit -framework CoreBluetooth -framework ServiceManagement -framework UserNotifications"

swiftc $SOURCES $TESTS \
    $FRAMEWORKS \
    -o test_runner

echo "Running tests..."
echo ""
./test_runner
STATUS=$?
rm -f test_runner
exit $STATUS
