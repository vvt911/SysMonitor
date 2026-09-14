#!/bin/bash
# Dung SysMonitor.app tu source trong thu muc nay.
#
#   ./build.sh            build lai + khoi dong lai app
#
# Cai dat (ngon ngu, khoi dong cung may, chi so hien thi...): mo menu bat ky tren
# thanh menu -> "Cai dat..." (Cmd+,), hoac mo lai SysMonitor.app khi app dang chay.
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
