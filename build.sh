#!/bin/bash
# Dung SysMonitor.app tu source trong thu muc nay.
#
#   ./build.sh            build lai + khoi dong lai app
#
# Bat khoi dong cung may: mo menu bat ky tren thanh menu -> "Khoi dong cung may".
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
APP="$HOME/Applications/SysMonitor.app"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$SRC/Info.plist" "$APP/Contents/Info.plist"

swiftc -O -whole-module-optimization \
    -o "$APP/Contents/MacOS/SysMonitor" \
    "$SRC/Sources"/*.swift

codesign --force --sign - "$APP" 2>/dev/null || true

pkill -f "SysMonitor.app/Contents/MacOS/SysMonitor" 2>/dev/null || true
sleep 0.5
open "$APP"
echo "Da build va khoi dong SysMonitor."
