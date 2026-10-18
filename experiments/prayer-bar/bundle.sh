#!/bin/sh
# Builds PrayerBar.app next to this script. Notifications, location prompts
# and launch at login only work from a bundle, not from `swift run`.
set -eu
cd "$(dirname "$0")"
swift build -c release --product PrayerBar
bin="$(swift build -c release --show-bin-path)/PrayerBar"
app=PrayerBar.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp Support/Info.plist "$app/Contents/Info.plist"
cp "$bin" "$app/Contents/MacOS/PrayerBar"
codesign --force --sign - "$app"
echo "Built $(pwd)/$app"
