#!/bin/sh
# Builds the spike, wraps it in a minimal LSUIElement .app and launches it with
# `open`, so macOS treats it as its own app for permission checks instead of
# inheriting whatever the terminal already has. Output goes to .build/call.log
# and is shown here. Optional argument: seconds to run (default 600).
set -e
cd "$(dirname "$0")"

swift build
BIN="$(swift build --show-bin-path)/CallSpike"
APP=.build/CallSpike.app
LOG="$PWD/.build/call.log"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/CallSpike"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.tidepool.spike.call</string>
    <key>CFBundleName</key><string>CallSpike</string>
    <key>CFBundleExecutable</key><string>CallSpike</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"

pkill -x CallSpike 2>/dev/null || true
: > "$LOG"
trap 'pkill -x CallSpike; exit 0' INT TERM
open -n --stdout "$LOG" --stderr "$LOG" "$APP" --args "${1:-600}"
tail -f "$LOG"
