#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CFG="$SHELL_DIR/shell.qml"

pkill -x qs 2>/dev/null || true
sleep 0.5

echo "Starting Quickshell for component profiling..."
qs -p "$CFG" >/tmp/qs-profiler.log 2>&1 &
QS_PID=$!

cleanup() {
    kill "$QS_PID" 2>/dev/null || true
    wait "$QS_PID" 2>/dev/null || true
}
trap cleanup EXIT

for _ in $(seq 1 30); do
    if qs ipc -p "$CFG" show >/dev/null 2>&1; then
        break
    fi
    sleep 0.2
done

if ! kill -0 "$QS_PID" 2>/dev/null; then
    echo "ERROR: Quickshell failed to start. Log:"
    cat /tmp/qs-profiler.log
    exit 1
fi

sample_proc() {
    local label="$1"
    local prev_rss="$2"
    sleep 0.7
    local rss threads cpu fds
    rss=$(awk '/VmRSS:/ {print $2}' "/proc/$QS_PID/status" 2>/dev/null || echo 0)
    threads=$(awk '/Threads:/ {print $2}' "/proc/$QS_PID/status" 2>/dev/null || echo 0)
    cpu=$(ps -p "$QS_PID" -o %cpu= 2>/dev/null | tr -d ' ' || echo "0.0")
    fds=$(ls "/proc/$QS_PID/fd" 2>/dev/null | wc -l || echo 0)
    local delta=$((rss - prev_rss))
    local rss_mb
    rss_mb=$(awk "BEGIN {printf \"%.1f\", $rss/1024}")
    local delta_mb
    delta_mb=$(awk "BEGIN {printf \"%+.2f\", $delta/1024}")
    printf "%-26s | %8s MB | %9s MB | %6s%% | %7s | %4s\n" \
        "$label" "$rss_mb" "$delta_mb" "$cpu" "$threads" "$fds"
    echo "$rss" > /tmp/qs-profiler-last-rss
}

echo ""
printf "%-26s | %11s | %12s | %7s | %7s | %4s\n" \
    "Component / State" "RSS" "Delta RSS" "%CPU" "Threads" "FDs"
printf -- "---------------------------+-------------+--------------+---------+---------+-----\n"

BASE_RSS=$(awk '/VmRSS:/ {print $2}' "/proc/$QS_PID/status" 2>/dev/null || echo 0)
sample_proc "Baseline (Idle)" "$BASE_RSS" >/dev/null
BASE_RSS=$(cat /tmp/qs-profiler-last-rss)
printf "%-26s | %8s MB | %12s | %6s%% | %7s | %4s\n" \
    "Baseline (Idle)" \
    "$(awk "BEGIN {printf \"%.1f\", $BASE_RSS/1024}")" \
    "+0.00 MB" \
    "$(ps -p "$QS_PID" -o %cpu= 2>/dev/null | tr -d ' ')" \
    "$(awk '/Threads:/ {print $2}' "/proc/$QS_PID/status")" \
    "$(ls "/proc/$QS_PID/fd" 2>/dev/null | wc -l)"

LAST_RSS="$BASE_RSS"

run_step() {
    local label="$1"
    shift
    "$@" >/dev/null 2>&1 || true
    sample_proc "$label" "$LAST_RSS"
    LAST_RSS=$(cat /tmp/qs-profiler-last-rss)
}

run_step "OSD (Volume + Bright)" qs ipc -p "$CFG" call osd show volume 75
run_step "Media + Focus" qs ipc -p "$CFG" call island setFocus "Profiler" "kitty"
run_step "Dashboard (Overview)" qs ipc -p "$CFG" call popover openDashboard overview
run_step "Dashboard (Tasks)" qs ipc -p "$CFG" call popover openDashboard tasks
run_step "Launcher" qs ipc -p "$CFG" call popover openLauncher
qs ipc -p "$CFG" call popover close >/dev/null 2>&1 || true
run_step "Settings (Island)" qs ipc -p "$CFG" call island openApp settings
qs ipc -p "$CFG" call island collapseApp >/dev/null 2>&1 || true
run_step "Files (Island)" qs ipc -p "$CFG" call island openApp files
qs ipc -p "$CFG" call island collapseApp >/dev/null 2>&1 || true
run_step "Picker (Island)" qs ipc -p "$CFG" call island openApp picker
qs ipc -p "$CFG" call island collapseApp >/dev/null 2>&1 || true
run_step "Modal (Power)" qs ipc -p "$CFG" call modal open power
qs ipc -p "$CFG" call modal close >/dev/null 2>&1 || true
run_step "Post-GC / Rest" qs ipc -p "$CFG" call island clearFocus

TOTAL_DELTA=$(awk "BEGIN {printf \"%+.2f\", ($LAST_RSS - $BASE_RSS)/1024}")
echo ""
echo "Total RSS growth from Baseline to Post-GC: ${TOTAL_DELTA} MB"
rm -f /tmp/qs-profiler-last-rss
