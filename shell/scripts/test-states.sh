#!/usr/bin/env bash
set -euo pipefail

SHELL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEEP_ALIVE=false
if [[ "${1:-}" == "--keep-alive" ]]; then
    KEEP_ALIVE=true
fi

STARTED_HERE=false
if ! qs list --all 2>/dev/null | grep -q "$SHELL_DIR"; then
    echo "Starting Paithosh Quickshell daemon..."
    qs -p "$SHELL_DIR" -d
    STARTED_HERE=true
    sleep 1.2
fi

ipc() {
    qs ipc -p "$SHELL_DIR" call paithosh "$@"
}

cleanup() {
    if [[ "$STARTED_HERE" == true && "$KEEP_ALIVE" == false ]]; then
        qs kill -p "$SHELL_DIR" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

echo "[1/8] Checking IPC target registration..."
qs ipc -p "$SHELL_DIR" show | grep -q "target paithosh"

echo "[2/8] Testing all 8 Dynamic Island states + pairwise/3-way transitions..."
for st in normal focus media notif focus-notif focus-media media-notif all focus media-notif normal; do
    ipc applyState "$st"
    sleep 0.25
done

echo "[3/8] Testing long-string text containment..."
ipc setPreviewFocus "Very Long Chromium Window Title — Testing Strict Text Containment Inside Dynamic Island Pill 2026"
sleep 0.3
ipc setPreviewFocus ""

echo "[4/8] Testing Volume & Brightness OSD..."
ipc adjustVolume -6
sleep 0.25
ipc adjustVolume 6
sleep 0.25
ipc adjustBrightness -10
sleep 0.25
ipc adjustBrightness 10
sleep 0.25

echo "[5/8] Testing Workspaces, Charger, KDE Connect & Alerts..."
for ws in 2 3 4 1; do
    ipc switchWorkspace "$ws"
    sleep 0.18
done
ipc triggerCharger
sleep 0.35
ipc triggerKdeDrop "hyprland.conf"
sleep 0.45
ipc cycleAlert
sleep 0.25
ipc cycleAlert
sleep 0.25
ipc cycleAlert

echo "[6/8] Testing Search, Launcher, Workspace Overview, 4-Tab Dashboard & Notification Toast..."
ipc toggleSearch
sleep 0.35
ipc toggleSearch
ipc toggleLauncher
sleep 0.35
ipc toggleLauncher
ipc toggleOverview
sleep 0.35
ipc toggleOverview
for tab in mission tasks kde power; do
    ipc toggleDashboard "$tab"
    sleep 0.28
done
ipc toggleDashboard ""
ipc triggerNotif "Hyprland" "Screenshot saved" "~/Pictures/Screenshots/2026-11-18.png"
sleep 0.4

echo "[7/8] Testing Fullscreen Auto-Hide & all 4 Modals..."
ipc toggleHideBar
sleep 0.35
ipc toggleHideBar
sleep 0.35
for m in confirm multi monitor progress; do
    ipc openModal "$m"
    sleep 0.35
done
ipc closeModal

echo "[7b/8] Testing Attached Settings, Files & Upload/Download Picker..."
ipc openSettings "system"
sleep 0.35
ipc triggerPackageUpdate 4
sleep 0.35
ipc openSettings "updates"
sleep 0.35
ipc openSettings "backup"
sleep 0.35
ipc triggerPackageUpdate 0
sleep 0.25
ipc openSettings "appearance"
sleep 0.35
ipc openSettings "personalization"
sleep 0.35
ipc setWallpaperColor true "Solid"
sleep 0.55
ipc nextWallpaper
sleep 0.65
ipc setWallpaperColor true "Gradient"
sleep 0.55
ipc nextWallpaper
sleep 0.65
ipc openSettings "appearance"
sleep 0.45
ipc setWallpaperColor false "Solid"
sleep 0.55
ipc openSettings "cursor"
sleep 0.45
ipc openSettings "layout"
sleep 0.35
ipc openSettings "keybind"
sleep 0.35
ipc openSettings "lockscreen"
sleep 0.45
ipc openFiles
sleep 0.35
ipc openMusic
sleep 0.45
ipc detachApp music
sleep 0.35
ipc reattachApp music
sleep 0.35
ipc openPicker "upload"
sleep 0.35
ipc openPicker "download"
sleep 0.35
ipc applyState normal

echo "[8/8] Auditing Quickshell logs for QML/JS errors..."
LOGS="$(qs log -p "$SHELL_DIR" 2>&1 || true)"
if echo "$LOGS" | grep -iE "TypeError|ReferenceError|SyntaxError|Cannot assign|Unable to assign|failed to create|ERROR"; then
    echo "FAIL: Errors found in Quickshell logs!" >&2
    exit 1
fi

echo "PASS: All Paithosh Quickshell states, popovers, modals & logs verified cleanly."
