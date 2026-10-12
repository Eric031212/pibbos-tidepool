#!/bin/sh
# Builds the spike, installs it as ~/Applications/Tidepool Login Spike.app
# (ad-hoc signed, LSUIElement) and launches it with `open` and one command:
#   ./run.sh register | unregister | status
# Every launch, including the one at login, appends to
# ~/Library/Logs/TidepoolLoginSpike.log, which this script prints afterwards.
set -e
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/LoginSpike"
APP="$HOME/Applications/Tidepool Login Spike.app"
LOG="$HOME/Library/Logs/TidepoolLoginSpike.log"

mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/LoginSpike"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.tidepool.spike.login</string>
    <key>CFBundleName</key><string>Tidepool Login Spike</string>
    <key>CFBundleExecutable</key><string>LoginSpike</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"

open -W -n "$APP" --args "${1:-status}"
echo "---- $LOG (last 15 lines)"
tail -15 "$LOG"
