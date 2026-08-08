#!/usr/bin/env bash
set -euo pipefail

REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="${REPOSITORY_ROOT}/.build/xcode-derived-data"

cd "${REPOSITORY_ROOT}"

echo "==> Package tests"
for package_directory in Packages/*/; do
    package_name="$(basename "${package_directory}")"
    echo "--- ${package_name}"
    (cd "${package_directory}" && swift test --quiet)
done

echo "==> AnchorDomain platform independence"
if grep -rlE '^import (SwiftUI|UIKit|AppKit)$' Packages/AnchorDomain/Sources; then
    echo "AnchorDomain imports a UI framework" >&2
    exit 1
fi

echo "==> Application builds"
xcodebuild build -workspace Anchor.xcworkspace -scheme AnchorMac \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "${DERIVED_DATA_PATH}" -quiet

xcodebuild build -workspace Anchor.xcworkspace -scheme AnchorMobile \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -derivedDataPath "${DERIVED_DATA_PATH}" -quiet

xcodebuild build -workspace Anchor.xcworkspace -scheme AnchorMobile \
    -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
    -derivedDataPath "${DERIVED_DATA_PATH}" -quiet

echo "==> Scaffold verification passed"
