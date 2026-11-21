#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CFG="$SHELL_DIR/shell.qml"
MOUSE="$SCRIPT_DIR/mouse-ctl.py"

pkill -x qs 2>/dev/null || true
sleep 0.4

qs -p "$CFG" >/tmp/qs-mouse-test.log 2>&1 &
QS_PID=$!
cleanup() {
    kill "$QS_PID" 2>/dev/null || true
    wait "$QS_PID" 2>/dev/null || true
}
trap cleanup EXIT

for _ in $(seq 1 30); do
    if qs ipc -p "$CFG" show >/dev/null 2>&1; then break; fi
    sleep 0.2
done

# Detect primary screen width/height via spectacle screenshot
spectacle -b -n -f -o /tmp/paithosh-screen-probe.png >/dev/null 2>&1
read -r SW SH < <(python3 -c '
from PIL import Image
im = Image.open("/tmp/paithosh-screen-probe.png")
print(im.width, im.height)
')
echo "Detected screen: ${SW}x${SH}"

# 1. Open Files (Island), right-click inside file viewport center-right
qs ipc -p "$SHELL_DIR" call paithosh openFiles >/dev/null
sleep 0.7
RX=$((SW / 2 + 120))
RY=260
echo "Right-clicking FilesView at ($RX, $RY)..."
python3 "$MOUSE" rightclick "$RX" "$RY" "$SW" "$SH"
sleep 0.35
spectacle -b -n -f -o /tmp/paithosh-mouse-files-ctx.png >/dev/null 2>&1

# Close Files
qs ipc -p "$SHELL_DIR" call paithosh collapseIslandApp >/dev/null 2>&1 || qs ipc -p "$SHELL_DIR" call paithosh reset >/dev/null 2>&1 || true
sleep 0.4

# 2. Open Settings (Island) -> Display page, click Scale/Resolution select
qs ipc -p "$SHELL_DIR" call paithosh openSettings "display" >/dev/null
sleep 0.7
SX=$((SW / 2 + 340))
SY=276
echo "Clicking Settings Display select at ($SX, $SY)..."
python3 "$MOUSE" click "$SX" "$SY" "$SW" "$SH"
sleep 0.35
spectacle -b -n -f -o /tmp/paithosh-mouse-settings-select.png >/dev/null 2>&1

echo "Saved screenshots:"
echo "  - /tmp/paithosh-mouse-files-ctx.png"
echo "  - /tmp/paithosh-mouse-settings-select.png"
