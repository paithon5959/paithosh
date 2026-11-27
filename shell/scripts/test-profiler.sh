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

# Detect GPU telemetry backend (NVIDIA -> AMD -> Intel)
GPU_BACKEND="none"
GPU_NAME="$(lspci 2>/dev/null | grep -iE 'vga|3d|display' | head -n1 | cut -d: -f3- | sed 's/^ *//; s/ (rev .*//' || echo 'Unknown')"
GPU_CARD_PATH=""
if command -v nvidia-smi >/dev/null 2>&1; then
    GPU_BACKEND="nvidia"
else
    for c in /sys/class/drm/card*/device; do
        if [ -r "$c/gpu_busy_percent" ]; then
            GPU_BACKEND="amd"
            GPU_CARD_PATH="$c"
            break
        fi
    done
    if [ "$GPU_BACKEND" = "none" ]; then
        for c in /sys/class/drm/card*; do
            if [ -r "$c/gt_act_freq_mhz" ] && [ -r "$c/gt_max_freq_mhz" ]; then
                GPU_BACKEND="intel"
                GPU_CARD_PATH="$c"
                break
            fi
        done
    fi
fi

echo "0" > /tmp/qs-profiler-peak-gpu
sample_gpu() {
    local pct="N/A"
    local detail="--"
    if [ "$GPU_BACKEND" = "nvidia" ]; then
        local nv
        nv=$(nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null | head -n1 || true)
        if [ -n "$nv" ]; then
            pct=$(echo "$nv" | awk -F',' '{gsub(/ /,"",$1); print $1+0}')
            detail=$(echo "$nv" | awk -F',' '{gsub(/ /,"",$2); gsub(/ /,"",$3); printf "%d/%dM", $2, $3}')
        fi
    elif [ "$GPU_BACKEND" = "amd" ]; then
        pct=$(cat "$GPU_CARD_PATH/gpu_busy_percent" 2>/dev/null || echo 0)
        local vu vt
        vu=$(cat "$GPU_CARD_PATH/mem_info_vram_used" 2>/dev/null || echo 0)
        vt=$(cat "$GPU_CARD_PATH/mem_info_vram_total" 2>/dev/null || echo 0)
        if [ "$vt" -gt 0 ] 2>/dev/null; then
            detail=$(awk "BEGIN {printf \"%.0f/%.0fM\", $vu/1048576, $vt/1048576}")
        fi
    elif [ "$GPU_BACKEND" = "intel" ]; then
        local fa fx
        fa=$(cat "$GPU_CARD_PATH/gt_act_freq_mhz" 2>/dev/null || echo 0)
        fx=$(cat "$GPU_CARD_PATH/gt_max_freq_mhz" 2>/dev/null || echo 1)
        pct=$(awk "BEGIN {v=int(($fa/$fx)*100+0.5); if(v>100)v=100; if(v<0)v=0; print v}")
        detail="${fa}/${fx}MHz"
    fi
    if [[ "$pct" =~ ^[0-9]+$ ]]; then
        local prev_peak
        prev_peak=$(cat /tmp/qs-profiler-peak-gpu 2>/dev/null || echo 0)
        if [ "$pct" -gt "$prev_peak" ]; then
            echo "$pct" > /tmp/qs-profiler-peak-gpu
        fi
        printf "%3s%% (%s)" "$pct" "$detail"
    else
        printf "%-14s" "N/A"
    fi
}

sample_proc() {
    local label="$1"
    local prev_rss="$2"
    sleep 0.7
    local rss threads cpu fds gpu_str
    rss=$(awk '/VmRSS:/ {print $2}' "/proc/$QS_PID/status" 2>/dev/null || echo 0)
    threads=$(awk '/Threads:/ {print $2}' "/proc/$QS_PID/status" 2>/dev/null || echo 0)
    cpu=$(ps -p "$QS_PID" -o %cpu= 2>/dev/null | tr -d ' ' || echo "0.0")
    fds=$(ls "/proc/$QS_PID/fd" 2>/dev/null | wc -l || echo 0)
    gpu_str=$(sample_gpu)
    local delta=$((rss - prev_rss))
    local rss_mb
    rss_mb=$(awk "BEGIN {printf \"%.1f\", $rss/1024}")
    local delta_mb
    delta_mb=$(awk "BEGIN {printf \"%+.2f\", $delta/1024}")
    printf "%-26s | %8s MB | %9s MB | %6s%% | %-16s | %7s | %4s\n" \
        "$label" "$rss_mb" "$delta_mb" "$cpu" "$gpu_str" "$threads" "$fds"
    echo "$rss" > /tmp/qs-profiler-last-rss
}

echo ""
echo "GPU: ${GPU_NAME} (backend: ${GPU_BACKEND})"
echo ""
printf "%-26s | %11s | %12s | %7s | %-16s | %7s | %4s\n" \
    "Component / State" "RSS" "Delta RSS" "%CPU" "GPU (Util/Clk)" "Threads" "FDs"
printf -- "---------------------------+-------------+--------------+---------+------------------+---------+-----\n"

BASE_RSS=$(awk '/VmRSS:/ {print $2}' "/proc/$QS_PID/status" 2>/dev/null || echo 0)
sample_proc "Baseline (Idle)" "$BASE_RSS" >/dev/null
BASE_RSS=$(cat /tmp/qs-profiler-last-rss)
BASE_GPU=$(sample_gpu)
printf "%-26s | %8s MB | %12s | %6s%% | %-16s | %7s | %4s\n" \
    "Baseline (Idle)" \
    "$(awk "BEGIN {printf \"%.1f\", $BASE_RSS/1024}")" \
    "+0.00 MB" \
    "$(ps -p "$QS_PID" -o %cpu= 2>/dev/null | tr -d ' ')" \
    "$BASE_GPU" \
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

# GPU Render Burst Test: rapid morph + popover transitions to measure GPU spike
gpu_burst_test() {
    for _ in 1 2 3; do
        qs ipc -p "$CFG" call popover openDashboard tasks >/dev/null 2>&1 || true
        sleep 0.15
        qs ipc -p "$CFG" call popover openLauncher >/dev/null 2>&1 || true
        sleep 0.15
    done
    qs ipc -p "$CFG" call popover close >/dev/null 2>&1 || true
}
run_step "GPU Burst (Morph/Spark)" gpu_burst_test
run_step "Post-GC / Rest" qs ipc -p "$CFG" call island clearFocus

TOTAL_DELTA=$(awk "BEGIN {printf \"%+.2f\", ($LAST_RSS - $BASE_RSS)/1024}")
echo ""
echo "Total RSS growth from Baseline to Post-GC: ${TOTAL_DELTA} MB"
PEAK_GPU_PCT=$(cat /tmp/qs-profiler-peak-gpu 2>/dev/null || echo 0)
echo "Peak GPU utilization observed: ${PEAK_GPU_PCT}% (backend: ${GPU_BACKEND})"
rm -f /tmp/qs-profiler-last-rss /tmp/qs-profiler-peak-gpu
