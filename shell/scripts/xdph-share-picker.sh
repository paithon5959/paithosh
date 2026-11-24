#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="${XDG_RUNTIME_DIR:-/tmp}/paithosh-xdph-debug-$(id -u).log"
echo "=== $(date) PID=$$ ARGS=$* ===" >> "${LOG_FILE}" 2>/dev/null || true

SCRIPT_REAL="$(readlink -f "${BASH_SOURCE[0]}")"
SHELL_QML="$(cd "$(dirname "$SCRIPT_REAL")/.." && pwd)/shell.qml"
FALLBACK_PICKER="/usr/bin/hyprland-share-picker"

TMP_DIR="$(mktemp -d /tmp/paithosh-xdph.XXXXXX)"
RESULT_FIFO="${TMP_DIR}/result.fifo"
WINDOWS_FILE="${TMP_DIR}/windows.txt"

cleanup() {
    rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

mkfifo "${RESULT_FIFO}"
printf '%s' "${XDPH_WINDOW_SHARING_LIST:-}" > "${WINDOWS_FILE}"

# Trigger Quickshell portal modal; fall back to stock picker if Quickshell isn't running
if ! qs ipc -p "${SHELL_QML}" call portal open "${RESULT_FIFO}" "${WINDOWS_FILE}" >>"${LOG_FILE}" 2>&1; then
    echo "qs ipc failed, falling back to ${FALLBACK_PICKER}" >> "${LOG_FILE}"
    if [[ -x "${FALLBACK_PICKER}" ]]; then
        exec "${FALLBACK_PICKER}" "$@"
    fi
    exit 1
fi
echo "qs ipc succeeded, waiting on FIFO ${RESULT_FIFO}" >> "${LOG_FILE}"

# Block until Quickshell writes the selection or CANCEL
if ! IFS= read -r SELECTION < "${RESULT_FIFO}"; then
    echo "FIFO read failed" >> "${LOG_FILE}"
    exit 1
fi

echo "Got selection: ${SELECTION}" >> "${LOG_FILE}"
if [[ -z "${SELECTION}" || "${SELECTION}" == "CANCEL" ]]; then
    exit 1
fi

printf '%s\n' "${SELECTION}"
exit 0
