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

echo "==> MCP helper signature and protocol"
MCP_HELPER_PATH="${DERIVED_DATA_PATH}/Build/Products/Debug/AnchorMac.app/Contents/Helpers/AnchorMCPServer"
if [[ ! -x "${MCP_HELPER_PATH}" ]]; then
    echo "Embedded MCP helper is missing or not executable" >&2
    exit 1
fi
codesign --verify --strict "${MCP_HELPER_PATH}"
MCP_VERIFICATION_DIRECTORY="$(mktemp -d)"
trap 'rm -rf -- "${MCP_VERIFICATION_DIRECTORY}"' EXIT
codesign -d --entitlements - --xml "${MCP_HELPER_PATH}" \
    > "${MCP_VERIFICATION_DIRECTORY}/helper-entitlements.plist"
codesign -d --entitlements - --xml "${DERIVED_DATA_PATH}/Build/Products/Debug/AnchorMac.app" \
    > "${MCP_VERIFICATION_DIRECTORY}/app-entitlements.plist"
python3 - "${MCP_VERIFICATION_DIRECTORY}/helper-entitlements.plist" \
    "${MCP_VERIFICATION_DIRECTORY}/app-entitlements.plist" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "rb") as source:
    helper_entitlements = plistlib.load(source)
with open(sys.argv[2], "rb") as source:
    application = plistlib.load(source)
anchor_groups = {group for group in application.get("keychain-access-groups", [])
                 if group.endswith(".com.akira.anchor")}
if len(anchor_groups) != 1 or set(helper_entitlements.get("keychain-access-groups", [])) != anchor_groups:
    sys.exit("MCP helper must use the application's Anchor Keychain group")
if any(key.startswith(("com.apple.developer.icloud-", "com.apple.developer.ubiquity-"))
       for key in helper_entitlements):
    sys.exit("MCP helper must not have CloudKit or iCloud entitlements")
PY
python3 Scripts/verify-mcp-stdio.py --self-test
ANCHOR_MCP_TEST_SUPPORT="${MCP_VERIFICATION_DIRECTORY}/support"
ANCHOR_MCP_FIXTURE_OUTPUT="${ANCHOR_MCP_TEST_SUPPORT}" \
    swift test --package-path Packages/AnchorPlatformMacOS --filter AnchorMCPStdioFixtureTests
python3 Scripts/verify-mcp-stdio.py "${MCP_HELPER_PATH}" \
    "${ANCHOR_MCP_TEST_SUPPORT}/workspace" "${ANCHOR_MCP_TEST_SUPPORT}"

resolve_simulator_identifier() {
    python3 - "$1" <<'PY'
import json
import subprocess
import sys

device_name = sys.argv[1]
catalog = json.loads(subprocess.check_output(
    ["xcrun", "simctl", "list", "--json", "devices", "available"], text=True))
for runtime in sorted(catalog["devices"], reverse=True):
    for simulator in catalog["devices"][runtime]:
        if simulator.get("name") == device_name and simulator.get("isAvailable"):
            print(simulator["udid"])
            sys.exit(0)
sys.exit(f"No available simulator named {device_name}")
PY
}

IPHONE_SIMULATOR_ID="$(resolve_simulator_identifier 'iPhone 17 Pro')"
xcodebuild build -workspace Anchor.xcworkspace -scheme AnchorMobile \
    -destination "platform=iOS Simulator,id=${IPHONE_SIMULATOR_ID}" \
    -derivedDataPath "${DERIVED_DATA_PATH}" -quiet

IPAD_SIMULATOR_ID="$(resolve_simulator_identifier 'iPad Pro 13-inch (M5)')"
xcodebuild build -workspace Anchor.xcworkspace -scheme AnchorMobile \
    -destination "platform=iOS Simulator,id=${IPAD_SIMULATOR_ID}" \
    -derivedDataPath "${DERIVED_DATA_PATH}" -quiet

echo "==> Scaffold verification passed"
