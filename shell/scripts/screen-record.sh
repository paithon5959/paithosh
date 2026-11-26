#!/usr/bin/env bash
set -u

CMD="${1:-}"
TARGET_PATH="${2:-}"

# 20 MiB threshold (20 * 1024 * 1024 bytes)
MAX_CLIPBOARD_BYTES=20971520
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
MODULES_FILE="${RUNTIME_DIR}/paithosh-rec-modules.list"

REC_PID=0
STOPPING=0
MOD_IDS=()
STOP_FLAG=""
SH_PID_FILE=""
WF_PID_FILE=""
LOG_FILE=""

find_render_device() {
    for dev in /dev/dri/renderD*; do
        if [[ -e "$dev" ]]; then
            echo "$dev"
            return 0
        fi
    done
    return 1
}

escape_regex() {
    local s="$1" out="" i ch
    for ((i = 0; i < ${#s}; i++)); do
        ch="${s:i:1}"
        case "$ch" in
            \\|\[|\]|\.|\^|\$|\*|\+|\?|\(|\)|\{|\}|\|) out+="\\$ch" ;;
            *) out+="$ch" ;;
        esac
    done
    printf '%s' "$out"
}

read_pid_file() {
    local file="$1"
    local p=""
    if [[ -f "$file" ]]; then
        IFS= read -r p < "$file" || true
        if [[ "$p" =~ ^[0-9]+$ ]]; then
            echo "$p"
            return 0
        fi
    fi
    return 1
}

cleanup_stale_modules() {
    if [[ -f "$MODULES_FILE" ]] && command -v pactl >/dev/null 2>&1; then
        local mid
        while IFS= read -r mid; do
            if [[ "$mid" =~ ^[0-9]+$ ]]; then
                pactl unload-module "$mid" >/dev/null 2>&1 || true
            fi
        done < "$MODULES_FILE"
    fi
    rm -f "$MODULES_FILE"
}

stop_orphaned_recorders() {
    local pids=()
    local p
    while IFS= read -r p; do
        [[ -n "$p" ]] && pids+=("$p")
    done < <(pgrep -u "$(id -u)" -f '(^|/)wf-recorder .*paithosh-rec-' 2>/dev/null || true)

    if [[ "${#pids[@]}" -eq 0 ]]; then
        return 0
    fi

    local sig max_wait i alive still
    for sig in INT TERM KILL; do
        alive=()
        for p in "${pids[@]}"; do
            if kill -0 "$p" 2>/dev/null; then
                kill "-${sig}" "$p" 2>/dev/null || true
                alive+=("$p")
            fi
        done
        [[ "${#alive[@]}" -eq 0 ]] && return 0
        [[ "$sig" == "KILL" ]] && return 0

        max_wait=40
        [[ "$sig" == "TERM" ]] && max_wait=20
        for ((i = 0; i < max_wait; i++)); do
            still=0
            for p in "${alive[@]}"; do
                if kill -0 "$p" 2>/dev/null; then
                    still=1
                    break
                fi
            done
            [[ "$still" -eq 0 ]] && return 0
            sleep 0.05
        done
    done
}

is_stopping() {
    [[ "$STOPPING" -eq 1 ]] || [[ -n "$STOP_FLAG" && -f "$STOP_FLAG" ]]
}

handle_signal() {
    STOPPING=1
    if [[ "$REC_PID" -gt 0 ]] && kill -0 "$REC_PID" 2>/dev/null; then
        kill -INT "$REC_PID" 2>/dev/null || true
    fi
}

cleanup_all() {
    local mid
    for mid in "${MOD_IDS[@]}"; do
        if [[ "$mid" =~ ^[0-9]+$ ]] && command -v pactl >/dev/null 2>&1; then
            pactl unload-module "$mid" >/dev/null 2>&1 || true
        fi
    done
    rm -f "$MODULES_FILE" \
        ${SH_PID_FILE:+"$SH_PID_FILE"} \
        ${WF_PID_FILE:+"$WF_PID_FILE"} \
        ${STOP_FLAG:+"$STOP_FLAG"} \
        ${LOG_FILE:+"$LOG_FILE"}
}

extract_error() {
    local rc="${1:-1}"
    local msg=""
    if [[ -n "$LOG_FILE" && -s "$LOG_FILE" ]]; then
        msg="$(grep -iE 'Cannot|Unsupported|Error|Failed|Invalid|not found|Unable|Permission' "$LOG_FILE" | tail -n 1 || true)"
        if [[ -z "$msg" ]]; then
            msg="$(awk 'NF { line=$0 } END { print line }' "$LOG_FILE" || true)"
        fi
    fi
    msg="${msg#"${msg%%[![:space:]]*}"}"
    msg="${msg%"${msg##*[![:space:]]}"}"
    if [[ -z "$msg" ]]; then
        msg="wf-recorder exited (${rc})"
    fi
    if [[ "${#msg}" -gt 120 ]]; then
        msg="${msg:0:117}..."
    fi
    printf '%s' "$msg"
}

run_wf_recorder() {
    : > "$LOG_FILE"
    wf-recorder "$@" >"$LOG_FILE" 2>&1 </dev/null &
    REC_PID=$!
    printf '%s\n' "$REC_PID" > "$WF_PID_FILE"

    if is_stopping; then
        kill -INT "$REC_PID" 2>/dev/null || true
    fi

    local rc=0
    while true; do
        if wait "$REC_PID"; then
            rc=0
        else
            rc=$?
        fi
        # Bash wait returns immediately (>128) when a trapped signal hits while wf-recorder is still flushing MP4 atoms.
        if kill -0 "$REC_PID" 2>/dev/null; then
            continue
        fi
        break
    done
    REC_PID=0
    rm -f "$WF_PID_FILE"
    return "$rc"
}

stop_recording() {
    local out_path="${1:-}"
    if [[ -z "$out_path" ]]; then
        echo "Missing output path" >&2
        exit 1
    fi

    local stop_flag="${out_path}.stop"
    local sh_pid_file="${out_path}.sh.pid"
    local wf_pid_file="${out_path}.wf.pid"
    local regex_pat
    regex_pat="(^|/)wf-recorder .*$(escape_regex "$out_path")"

    # Create stop marker atomically first so a racing start sees it before PIDs exist.
    : > "$stop_flag"

    local wf_pid="" sh_pid="" signaled_wf_pid=""
    wf_pid="$(read_pid_file "$wf_pid_file" || true)"
    sh_pid="$(read_pid_file "$sh_pid_file" || true)"

    if [[ -n "$wf_pid" ]] && kill -0 "$wf_pid" 2>/dev/null; then
        kill -INT "$wf_pid" 2>/dev/null || true
        signaled_wf_pid="$wf_pid"
    else
        pkill -INT -f "$regex_pat" 2>/dev/null || true
    fi

    if [[ -n "$sh_pid" ]] && kill -0 "$sh_pid" 2>/dev/null; then
        kill -TERM "$sh_pid" 2>/dev/null || true
    fi

    local i wf_alive sh_alive
    for ((i = 0; i < 60; i++)); do
        wf_pid="$(read_pid_file "$wf_pid_file" || true)"
        sh_pid="$(read_pid_file "$sh_pid_file" || true)"
        wf_alive=0
        sh_alive=0

        if [[ -n "$wf_pid" ]] && kill -0 "$wf_pid" 2>/dev/null; then
            wf_alive=1
            if [[ "$wf_pid" != "$signaled_wf_pid" ]]; then
                kill -INT "$wf_pid" 2>/dev/null || true
                signaled_wf_pid="$wf_pid"
            fi
        elif pgrep -f "$regex_pat" >/dev/null 2>&1; then
            wf_alive=1
            pkill -INT -f "$regex_pat" 2>/dev/null || true
        fi

        if [[ -n "$sh_pid" ]] && kill -0 "$sh_pid" 2>/dev/null; then
            sh_alive=1
        fi

        if [[ "$wf_alive" -eq 0 && "$sh_alive" -eq 0 ]]; then
            exit 0
        fi
        sleep 0.05
    done

    wf_pid="$(read_pid_file "$wf_pid_file" || true)"
    sh_pid="$(read_pid_file "$sh_pid_file" || true)"
    [[ -n "$wf_pid" ]] && kill -TERM "$wf_pid" 2>/dev/null || true
    [[ -n "$sh_pid" ]] && kill -TERM "$sh_pid" 2>/dev/null || true
    pkill -TERM -f "$regex_pat" 2>/dev/null || true

    for ((i = 0; i < 30; i++)); do
        wf_alive=0
        sh_alive=0
        if [[ -n "$wf_pid" ]] && kill -0 "$wf_pid" 2>/dev/null; then
            wf_alive=1
        elif pgrep -f "$regex_pat" >/dev/null 2>&1; then
            wf_alive=1
        fi
        if [[ -n "$sh_pid" ]] && kill -0 "$sh_pid" 2>/dev/null; then
            sh_alive=1
        fi
        if [[ "$wf_alive" -eq 0 && "$sh_alive" -eq 0 ]]; then
            exit 0
        fi
        sleep 0.05
    done

    wf_pid="$(read_pid_file "$wf_pid_file" || true)"
    sh_pid="$(read_pid_file "$sh_pid_file" || true)"
    [[ -n "$wf_pid" ]] && kill -KILL "$wf_pid" 2>/dev/null || true
    [[ -n "$sh_pid" ]] && kill -KILL "$sh_pid" 2>/dev/null || true
    pkill -KILL -f "$regex_pat" 2>/dev/null || true
    exit 0
}

start_recording() {
    local out_path="${1:-}"
    local sys_audio="${2:-1}"
    local mic_audio="${3:-0}"
    local fps="${4:-30}"
    local res="${5:-native}"
    local preset="${6:-standard}"
    local codec="${7:-auto}"

    if [[ -z "$out_path" ]]; then
        echo "ERROR|Missing output path"
        exit 1
    fi
    if ! command -v wf-recorder >/dev/null 2>&1; then
        echo "ERROR|wf-recorder not installed"
        exit 1
    fi

    STOP_FLAG="${out_path}.stop"
    SH_PID_FILE="${out_path}.sh.pid"
    WF_PID_FILE="${out_path}.wf.pid"
    LOG_FILE="${out_path}.log"
    REC_PID=0
    STOPPING=0
    MOD_IDS=()

    trap 'handle_signal' INT TERM
    trap 'cleanup_all' EXIT

    printf '%s\n' "$$" > "$SH_PID_FILE"

    if is_stopping; then
        exit 0
    fi

    stop_orphaned_recorders
    cleanup_stale_modules

    if is_stopping; then
        exit 0
    fi

    local audio_args=()
    if command -v pactl >/dev/null 2>&1; then
        local sink source
        sink="$(pactl get-default-sink 2>/dev/null || true)"
        source="$(pactl get-default-source 2>/dev/null || true)"
        if [[ "$sys_audio" == "1" && "$mic_audio" == "1" && -n "$sink" && -n "$source" ]]; then
            local m_sink="" m_lb1="" m_lb2=""
            m_sink="$(pactl load-module module-null-sink sink_name=paithosh_rec_mix sink_properties=device.description=PaithoshRecMix 2>/dev/null || true)"
            if [[ -n "$m_sink" ]]; then
                m_lb1="$(pactl load-module module-loopback source="${sink}.monitor" sink=paithosh_rec_mix latency_msec=20 2>/dev/null || true)"
                m_lb2="$(pactl load-module module-loopback source="$source" sink=paithosh_rec_mix latency_msec=20 2>/dev/null || true)"
                [[ -n "$m_lb2" ]] && MOD_IDS+=("$m_lb2")
                [[ -n "$m_lb1" ]] && MOD_IDS+=("$m_lb1")
                MOD_IDS+=("$m_sink")
                printf '%s\n' "${MOD_IDS[@]}" > "$MODULES_FILE"
                audio_args+=("--audio=paithosh_rec_mix.monitor")
            else
                audio_args+=("--audio=${sink}.monitor")
            fi
        elif [[ "$sys_audio" == "1" && -n "$sink" ]]; then
            audio_args+=("--audio=${sink}.monitor")
        elif [[ "$mic_audio" == "1" && -n "$source" ]]; then
            audio_args+=("--audio=${source}")
        fi
    elif [[ "$sys_audio" == "1" || "$mic_audio" == "1" ]]; then
        audio_args+=(-a)
    fi

    local scale_w=""
    case "$res" in
        1080p) scale_w="1920" ;;
        720p)  scale_w="1280" ;;
        480p)  scale_w="854" ;;
    esac
    local scale_args=()
    if [[ -n "$scale_w" ]]; then
        scale_args=(-F "scale=${scale_w}:-2")
    fi

    local vaapi_qp="24"
    local nvenc_cq="24"
    local x264_crf="26"
    local x265_crf="28"
    case "$preset" in
        low)  vaapi_qp="30"; nvenc_cq="30"; x264_crf="32"; x265_crf="32" ;;
        high) vaapi_qp="20"; nvenc_cq="19"; x264_crf="20"; x265_crf="22" ;;
    esac

    local vaapi_scale_args=()
    if [[ -n "$scale_w" ]]; then
        vaapi_scale_args=(-F "scale_vaapi=w=${scale_w}:h=-2")
    fi

    local output_args=()
    if command -v hyprctl >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
        local focused_output
        focused_output="$(hyprctl -j monitors 2>/dev/null | python3 -c "import sys, json; ms = json.load(sys.stdin); print(next((m['name'] for m in ms if m.get('focused')), ms[0]['name'] if ms else ''))" 2>/dev/null || true)"
        if [[ -n "$focused_output" ]]; then
            output_args=(-o "$focused_output")
        fi
    fi

    if is_stopping; then
        exit 0
    fi

    local common_args=("${output_args[@]}" -D -y "${audio_args[@]}" -r "$fps")
    local rec_rc=0

    case "$codec" in
        h264_vaapi|hevc_vaapi)
            local render_dev=""
            render_dev="$(find_render_device || true)"
            if [[ -z "$render_dev" ]]; then
                echo "ERROR|No VAAPI render device found (/dev/dri/renderD*)"
                exit 1
            fi
            run_wf_recorder "${common_args[@]}" "${vaapi_scale_args[@]}" -c "$codec" -d "$render_dev" -p "qp=$vaapi_qp" -f "$out_path" || rec_rc=$?
            ;;
        h264_nvenc|hevc_nvenc)
            run_wf_recorder "${common_args[@]}" "${scale_args[@]}" -c "$codec" -p preset=p4 -p rc=vbr -p "cq=$nvenc_cq" -x yuv420p -f "$out_path" || rec_rc=$?
            ;;
        libx264)
            run_wf_recorder "${common_args[@]}" "${scale_args[@]}" -c libx264 -p preset=ultrafast -p tune=zerolatency -p profile=main -p level=4.1 -p "crf=$x264_crf" -x yuv420p -f "$out_path" || rec_rc=$?
            ;;
        libx265)
            run_wf_recorder "${common_args[@]}" "${scale_args[@]}" -c libx265 -p preset=ultrafast -p "crf=$x265_crf" -x yuv420p -f "$out_path" || rec_rc=$?
            ;;
        auto|*)
            # Try VAAPI only at native resolution (CPU scale= filter is incompatible with VAAPI hwframes).
            # No sleep probe: wait directly for wf-recorder and fall back immediately if VAAPI fails without output.
            if [[ -z "$scale_w" ]]; then
                local render_dev=""
                render_dev="$(find_render_device || true)"
                if [[ -n "$render_dev" ]]; then
                    local vaapi_cache="${RUNTIME_DIR}/paithosh-rec-vaapi-disabled-$(basename "$render_dev")"
                    if [[ ! -f "$vaapi_cache" ]]; then
                        local vaapi_rc=0
                        run_wf_recorder "${common_args[@]}" -c h264_vaapi -d "$render_dev" -p "qp=$vaapi_qp" -f "$out_path" || vaapi_rc=$?

                        if is_stopping; then
                            exit 0
                        fi
                        if [[ -s "$out_path" ]]; then
                            exit 0
                        fi

                        # VAAPI failed before producing frames; remember for this runtime session and fall back to libx264.
                        printf 'disabled\n' > "$vaapi_cache"
                        rm -f "$out_path"
                    fi
                fi
            fi

            if is_stopping; then
                exit 0
            fi

            run_wf_recorder "${common_args[@]}" "${scale_args[@]}" -c libx264 -p preset=ultrafast -p tune=zerolatency -p profile=main -p level=4.1 -p "crf=$x264_crf" -x yuv420p -f "$out_path" || rec_rc=$?
            ;;
    esac

    if is_stopping; then
        exit 0
    fi

    if [[ ! -s "$out_path" ]]; then
        rm -f "$out_path"
        echo "ERROR|$(extract_error "$rec_rc")"
        exit 1
    fi

    exit 0
}

finish_recording() {
    local tmp_path="${1:-}"
    local custom_dir="${2:-}"

    if [[ -n "$tmp_path" ]]; then
        rm -f "${tmp_path}.stop" "${tmp_path}.sh.pid" "${tmp_path}.wf.pid" "${tmp_path}.log"
    fi

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
        if command -v wl-copy >/dev/null 2>&1; then
            printf 'file://%s\r\n' "$tmp_path" | wl-copy --type text/uri-list >/dev/null 2>&1 &
        fi
        echo "COPIED|$tmp_path|$size_label"
    fi
}

list_codecs() {
    echo "auto"

    if ! command -v ffmpeg >/dev/null 2>&1; then
        echo "libx264"
        return 0
    fi

    local encoders=""
    encoders="$(ffmpeg -hide_banner -encoders 2>/dev/null || true)"
    if [[ -z "$encoders" ]]; then
        echo "libx264"
        return 0
    fi

    local has_h264_vaapi=0 has_hevc_vaapi=0 has_h264_nvenc=0 has_hevc_nvenc=0 has_libx264=0 has_libx265=0
    grep -qE '^[[:space:]]*V[^ ]*[[:space:]]+h264_vaapi([[:space:]]|$)' <<< "$encoders" && has_h264_vaapi=1
    grep -qE '^[[:space:]]*V[^ ]*[[:space:]]+hevc_vaapi([[:space:]]|$)' <<< "$encoders" && has_hevc_vaapi=1
    grep -qE '^[[:space:]]*V[^ ]*[[:space:]]+h264_nvenc([[:space:]]|$)' <<< "$encoders" && has_h264_nvenc=1
    grep -qE '^[[:space:]]*V[^ ]*[[:space:]]+hevc_nvenc([[:space:]]|$)' <<< "$encoders" && has_hevc_nvenc=1
    grep -qE '^[[:space:]]*V[^ ]*[[:space:]]+libx264([[:space:]]|$)' <<< "$encoders" && has_libx264=1
    grep -qE '^[[:space:]]*V[^ ]*[[:space:]]+libx265([[:space:]]|$)' <<< "$encoders" && has_libx265=1

    local render_dev=""
    render_dev="$(find_render_device || true)"
    if [[ -n "$render_dev" && ( "$has_h264_vaapi" -eq 1 || "$has_hevc_vaapi" -eq 1 ) ]]; then
        if command -v vainfo >/dev/null 2>&1; then
            local va_out=""
            va_out="$(vainfo --display drm --device "$render_dev" 2>/dev/null || true)"
            if [[ "$has_h264_vaapi" -eq 1 ]] && grep -qE 'VAProfileH264.*VAEntrypointEncSlice' <<< "$va_out"; then
                echo "h264_vaapi"
            fi
            if [[ "$has_hevc_vaapi" -eq 1 ]] && grep -qE 'VAProfileHEVC.*VAEntrypointEncSlice' <<< "$va_out"; then
                echo "hevc_vaapi"
            fi
        else
            if [[ "$has_h264_vaapi" -eq 1 ]] && ffmpeg -hide_banner -loglevel error -init_hw_device "vaapi=va:${render_dev}" -filter_hw_device va -f lavfi -i color=black:s=64x64:d=0.04 -vf format=nv12,hwupload -c:v h264_vaapi -frames:v 1 -f null - 2>/dev/null; then
                echo "h264_vaapi"
            fi
            if [[ "$has_hevc_vaapi" -eq 1 ]] && ffmpeg -hide_banner -loglevel error -init_hw_device "vaapi=va:${render_dev}" -filter_hw_device va -f lavfi -i color=black:s=64x64:d=0.04 -vf format=nv12,hwupload -c:v hevc_vaapi -frames:v 1 -f null - 2>/dev/null; then
                echo "hevc_vaapi"
            fi
        fi
    fi

    if [[ -e /dev/nvidiactl ]]; then
        if [[ "$has_h264_nvenc" -eq 1 ]] && ffmpeg -hide_banner -loglevel error -f lavfi -i color=black:s=64x64:d=0.04 -c:v h264_nvenc -frames:v 1 -f null - 2>/dev/null; then
            echo "h264_nvenc"
        fi
        if [[ "$has_hevc_nvenc" -eq 1 ]] && ffmpeg -hide_banner -loglevel error -f lavfi -i color=black:s=64x64:d=0.04 -c:v hevc_nvenc -frames:v 1 -f null - 2>/dev/null; then
            echo "hevc_nvenc"
        fi
    fi

    [[ "$has_libx264" -eq 1 ]] && echo "libx264"
    [[ "$has_libx265" -eq 1 ]] && echo "libx265"
}

case "$CMD" in
    start)
        start_recording "$TARGET_PATH" "${3:-1}" "${4:-0}" "${5:-30}" "${6:-native}" "${7:-standard}" "${8:-auto}"
        ;;
    stop)
        stop_recording "$TARGET_PATH"
        ;;
    finish)
        finish_recording "$TARGET_PATH" "${3:-}"
        ;;
    codecs)
        list_codecs
        ;;
    *)
        echo "Usage: $0 {start|stop|finish|codecs} [path]" >&2
        exit 2
        ;;
esac
