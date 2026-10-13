#!/bin/sh
# Builds the spike, wraps it in a minimal LSUIElement .app and launches it with
# `open`, so macOS treats it as its own app for permission checks instead of
# inheriting whatever the terminal already has. Output goes to .build/anim.log
# and is shown here. Ctrl+C stops both the log view and the app.
# Builds in release mode (for realistic CPU/memory numbers) unless CONFIG=debug.
set -e
cd "$(dirname "$0")"

CONFIG="${CONFIG:-release}"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/AnimSpike"
APP=.build/AnimSpike.app
LOG="$PWD/.build/anim.log"
PACK="$(cd ../.. && pwd)/Assets/Skins/pibbo"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/AnimSpike"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.tidepool.spike.anim</string>
    <key>CFBundleName</key><string>AnimSpike</string>
    <key>CFBundleExecutable</key><string>AnimSpike</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"

pkill -x AnimSpike 2>/dev/null || true
: > "$LOG"
trap 'pkill -x AnimSpike; exit 0' INT TERM
open -n --stdout "$LOG" --stderr "$LOG" "$APP" --args "$PACK" "$@"
tail -f "$LOG"
