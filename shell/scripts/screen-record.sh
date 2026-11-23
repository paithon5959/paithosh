#!/usr/bin/env bash
set -u

CMD="${1:-}"
TARGET_PATH="${2:-}"

# 20 MiB threshold (20 * 1024 * 1024 bytes)
MAX_CLIPBOARD_BYTES=20971520

find_render_device() {
    for dev in /dev/dri/renderD*; do
        if [[ -e "$dev" ]]; then
            echo "$dev"
            return 0
        fi
    done
    return 1
}

start_recording() {
    local out_path="$1"
    local sys_audio="${2:-1}"
    local mic_audio="${3:-0}"
    local fps="${4:-30}"
    local res="${5:-native}"
    local preset="${6:-standard}"
    if [[ -z "$out_path" ]]; then
        echo "Missing output path" >&2
        exit 1
    fi

    # Clean up any orphaned paithosh wf-recorder from a previous hot-reload
    pkill -INT -f "wf-recorder.*/tmp/paithosh-rec-" 2>/dev/null || true

    local extra_args=()
    local mod_ids=()
    cleanup_audio_mix() {
        for mid in "${mod_ids[@]}"; do
            pactl unload-module "$mid" >/dev/null 2>&1 || true
        done
    }

    if command -v pactl >/dev/null 2>&1; then
        local sink source
        sink="$(pactl get-default-sink 2>/dev/null || true)"
        source="$(pactl get-default-source 2>/dev/null || true)"
        if [[ "$sys_audio" == "1" && "$mic_audio" == "1" && -n "$sink" && -n "$source" ]]; then
            local m_sink m_lb1 m_lb2
            m_sink="$(pactl load-module module-null-sink sink_name=paithosh_rec_mix sink_properties=device.description=PaithoshRecMix 2>/dev/null || true)"
            if [[ -n "$m_sink" ]]; then
                m_lb1="$(pactl load-module module-loopback source="${sink}.monitor" sink=paithosh_rec_mix latency_msec=20 2>/dev/null || true)"
                m_lb2="$(pactl load-module module-loopback source="$source" sink=paithosh_rec_mix latency_msec=20 2>/dev/null || true)"
                mod_ids=("$m_lb2" "$m_lb1" "$m_sink")
                extra_args+=("--audio=paithosh_rec_mix.monitor")
            else
                extra_args+=("--audio=${sink}.monitor")
            fi
        elif [[ "$sys_audio" == "1" && -n "$sink" ]]; then
            extra_args+=("--audio=${sink}.monitor")
        elif [[ "$mic_audio" == "1" && -n "$source" ]]; then
            extra_args+=("--audio=${source}")
        fi
    elif [[ "$sys_audio" == "1" || "$mic_audio" == "1" ]]; then
        extra_args+=(-a)
    fi

    local scale_w=""
    case "$res" in
        1080p) scale_w="1920" ;;
        720p)  scale_w="1280" ;;
        480p)  scale_w="854" ;;
    esac
    if [[ -n "$scale_w" ]]; then
        extra_args+=(-F "scale=${scale_w}:-2")
    fi

    local vaapi_qp="24"
    local x264_crf="26"
    case "$preset" in
        low)  vaapi_qp="30"; x264_crf="32" ;;
        high) vaapi_qp="20"; x264_crf="20" ;;
    esac

    local output_args=()
    if command -v hyprctl >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
        local focused_output
        focused_output="$(hyprctl -j monitors 2>/dev/null | python3 -c "import sys, json; ms = json.load(sys.stdin); print(next((m['name'] for m in ms if m.get('focused')), ms[0]['name'] if ms else ''))" 2>/dev/null || true)"
        if [[ -n "$focused_output" ]]; then
            output_args=(-o "$focused_output")
        fi
    fi

    local rec_pid=0
    local stopping=0

    handle_signal() {
        stopping=1
        if [[ "$rec_pid" -gt 0 ]] && kill -0 "$rec_pid" 2>/dev/null; then
            kill -INT "$rec_pid" 2>/dev/null || true
        fi
    }
    trap 'handle_signal' INT TERM
    trap 'cleanup_audio_mix' EXIT

    local render_dev=""
    render_dev="$(find_render_device || true)"

    if [[ -n "$render_dev" ]]; then
        wf-recorder "${output_args[@]}" "${extra_args[@]}" -r "$fps" -c h264_vaapi -d "$render_dev" -p "qp=$vaapi_qp" -f "$out_path" >/dev/null 2>&1 &
        rec_pid=$!
        sleep 0.5

        local proc_stat
        proc_stat="$(ps -o stat= -p "$rec_pid" 2>/dev/null | tr -d ' ')"
        if [[ -n "$proc_stat" && "$proc_stat" != Z* ]]; then
            wait "$rec_pid" || true
            exit 0
        fi

        wait "$rec_pid" 2>/dev/null || true

        # If user stopped during startup probe, exit cleanly
        if [[ "$stopping" -eq 1 ]]; then
            exit 0
        fi

        # VAAPI failed to initialize on this driver/hardware; clean up and fall back to smooth CPU x264
        rm -f "$out_path"
    fi

    wf-recorder "${output_args[@]}" "${extra_args[@]}" -r "$fps" -c libx264 -p preset=ultrafast -p tune=zerolatency -p profile=main -p level=4.1 -p "crf=$x264_crf" -x yuv420p -f "$out_path" >/dev/null 2>&1 &
    rec_pid=$!
    wait "$rec_pid" || true
}

finish_recording() {
    local tmp_path="$1"
    local custom_dir="${2:-}"
    if [[ -z "$tmp_path" || ! -f "$tmp_path" ]]; then
        echo "EMPTY||0 B"
        exit 0
    fi

    local size_bytes
    size_bytes="$(stat -c%s "$tmp_path" 2>/dev/null || echo 0)"
    if [[ "$size_bytes" -le 0 ]]; then
        rm -f "$tmp_path"
        echo "EMPTY||0 B"
        exit 0
    fi

    # Remux with +faststart (stream-copy, <100ms) so Discord/web players can play the MP4 inline
    if command -v ffmpeg >/dev/null 2>&1; then
        local fast_path="${tmp_path%.mp4}.fast.mp4"
        if ffmpeg -y -i "$tmp_path" -c copy -movflags +faststart "$fast_path" >/dev/null 2>&1 && [[ -s "$fast_path" ]]; then
            mv -f "$fast_path" "$tmp_path"
        else
            rm -f "$fast_path"
        fi
        size_bytes="$(stat -c%s "$tmp_path" 2>/dev/null || echo 0)"
    fi

    local size_label
    size_label="$(awk -v s="$size_bytes" 'BEGIN {
        if (s >= 1048576) printf "%.1f MB", s / 1048576;
        else if (s >= 1024) printf "%.0f KB", s / 1024;
        else printf "%d B", s;
    }')"

    if [[ "$size_bytes" -gt "$MAX_CLIPBOARD_BYTES" ]]; then
        local videos_dir="${custom_dir:-$HOME/Videos}"
        videos_dir="${videos_dir/#\~/$HOME}"
        mkdir -p "$videos_dir"
        local dest_path="$videos_dir/recording-$(date +%Y%m%d-%H%M%S).mp4"
        mv -f "$tmp_path" "$dest_path"
        echo "SAVED|$dest_path|$size_label"
    else
        # Copy file URI to Wayland clipboard; redirect stdio so wl-copy daemonizes without blocking callers
        printf 'file://%s\r\n' "$tmp_path" | wl-copy --type text/uri-list >/dev/null 2>&1 &
        echo "COPIED|$tmp_path|$size_label"
    fi
}

case "$CMD" in
    start)
        start_recording "$TARGET_PATH" "${3:-1}" "${4:-0}" "${5:-30}" "${6:-native}" "${7:-standard}"
        ;;
    finish)
        finish_recording "$TARGET_PATH" "${3:-}"
        ;;
    *)
        echo "Usage: $0 {start|finish} <path>" >&2
        exit 2
        ;;
esac
