#!/bin/bash
set -euo pipefail

APP_PATH="$1"
DEVICE_TYPE="$2"
OUTPUT_PREFIX="$3"
DEVICE_ID=$(xcrun simctl create MochyGlassLayout "$DEVICE_TYPE")
trap 'xcrun simctl shutdown "$DEVICE_ID" >/dev/null 2>&1 || true' EXIT
xcrun simctl boot "$DEVICE_ID"
xcrun simctl bootstatus "$DEVICE_ID" -b
xcrun simctl status_bar "$DEVICE_ID" override --time '9:41' --batteryState charged --batteryLevel 100
xcrun simctl install "$DEVICE_ID" "$APP_PATH"
CONTAINER=$(xcrun simctl get_app_container "$DEVICE_ID" app.mochy.music.ios data)
python3 ios/Scripts/write_layout_fixture.py "$CONTAINER/Library/Application Support/MochyMusic/library.json"
xcrun simctl launch "$DEVICE_ID" app.mochy.music.ios
sleep 8
xcrun simctl io "$DEVICE_ID" screenshot "${OUTPUT_PREFIX}-mini.png"
xcrun simctl spawn "$DEVICE_ID" launchctl list | awk '/UIKitApplication:app.mochy.music.ios/ && $1 != "-" { found = 1 } END { exit !found }'

xcrun simctl ui "$DEVICE_ID" content_size accessibility-extra-extra-extra-large
sleep 2
xcrun simctl io "$DEVICE_ID" screenshot "${OUTPUT_PREFIX}-large-text.png"
xcrun simctl ui "$DEVICE_ID" content_size large
xcrun simctl terminate "$DEVICE_ID" app.mochy.music.ios
xcrun simctl launch "$DEVICE_ID" app.mochy.music.ios --layout-player
sleep 5
xcrun simctl io "$DEVICE_ID" screenshot "${OUTPUT_PREFIX}-player.png"
