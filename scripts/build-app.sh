#!/bin/zsh

set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
APP_NAME="Mac Monitor Control"
EXECUTABLE_NAME="MacMonitorControl"
APP_PATH="$PROJECT_ROOT/build/$APP_NAME.app"

cd "$PROJECT_ROOT"
swift build -c release
BIN_PATH="$(swift build -c release --show-bin-path)"

mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"
cp "$BIN_PATH/$EXECUTABLE_NAME" "$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"
cp "$PROJECT_ROOT/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"

codesign --force --deep --sign - "$APP_PATH"

echo "$APP_PATH"
