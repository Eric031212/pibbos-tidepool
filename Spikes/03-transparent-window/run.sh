#!/bin/sh
# Builds the spike, wraps it in a minimal LSUIElement .app and launches it with
# `open`, so macOS treats it as its own app for permission checks instead of
# inheriting whatever the terminal already has. Output goes to .build/window.log
# and is shown here. Ctrl+C stops both the log view and the app.
set -e
cd "$(dirname "$0")"

swift build
BIN="$(swift build --show-bin-path)/WindowSpike"
APP=.build/WindowSpike.app
LOG="$PWD/.build/window.log"
SHEET="$(cd ../.. && pwd)/Assets/Skins/pibbo/sprites.png"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/WindowSpike"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.tidepool.spike.window</string>
    <key>CFBundleName</key><string>WindowSpike</string>
    <key>CFBundleExecutable</key><string>WindowSpike</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"

pkill -x WindowSpike 2>/dev/null || true
: > "$LOG"
trap 'pkill -x WindowSpike; exit 0' INT TERM
open -n --stdout "$LOG" --stderr "$LOG" "$APP" --args "$SHEET" "$@"
tail -f "$LOG"
