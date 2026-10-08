#!/bin/zsh

set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
APP_NAME="Mac Monitor Control"
EXECUTABLE_NAME="MacMonitorControl"
APP_PATH="$PROJECT_ROOT/build/$APP_NAME.app"

cd "$PROJECT_ROOT"
swift build -c release
BIN_PATH="$(swift build -c release --show-bin-path)"

# Render the app icon (menu-bar laptop symbol) with macOS-native tools.
ICONSET_PATH="$PROJECT_ROOT/build/AppIcon.iconset"
ICNS_PATH="$PROJECT_ROOT/build/AppIcon.icns"
rm -rf "$ICONSET_PATH"
swift "$PROJECT_ROOT/scripts/render-app-icon.swift" "$ICONSET_PATH" laptop
iconutil -c icns "$ICONSET_PATH" -o "$ICNS_PATH"

mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"
cp "$BIN_PATH/$EXECUTABLE_NAME" "$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"
cp "$PROJECT_ROOT/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
cp "$ICNS_PATH" "$APP_PATH/Contents/Resources/AppIcon.icns"

codesign --force --deep --sign - "$APP_PATH"

echo "$APP_PATH"
