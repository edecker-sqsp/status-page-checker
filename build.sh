#!/bin/bash
# Builds "What's Down, Doc?.app" from the SwiftPM package. No Xcode required —
# this uses only Command Line Tools (swift build, codesign).
set -euo pipefail

cd "$(dirname "$0")"

EXECUTABLE_NAME="StatusChecker"
APP_DISPLAY_NAME="What's Down, Doc?"
APP_BUNDLE="${APP_DISPLAY_NAME}.app"
BUILD_DIR=".build/release"

echo "==> Building ${APP_DISPLAY_NAME} (release)"
swift build -c release

echo "==> Assembling ${APP_BUNDLE}"
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"
cp "${BUILD_DIR}/${EXECUTABLE_NAME}" "${APP_BUNDLE}/Contents/MacOS/${EXECUTABLE_NAME}"
cp "Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"
cp "Resources/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"

echo "==> Ad-hoc signing"
codesign --force --deep --sign - "${APP_BUNDLE}"

echo "==> Done: ${APP_BUNDLE}"
echo "    Run with: open ${APP_BUNDLE}"
echo "    For 'Launch at login' and notifications to behave reliably, move it to /Applications."
