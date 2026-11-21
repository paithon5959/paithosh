#!/usr/bin/env bash
set -euo pipefail

OUT_VIDEO="${1:-/tmp/paithosh-test-recording.mp4}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

rm -f "$OUT_VIDEO"

echo "Starting screen recording -> $OUT_VIDEO"
spectacle --background --nonotify --record screen --output "$OUT_VIDEO" &
REC_PID=$!
sleep 1.2

set +e
bash "$SCRIPT_DIR/test-states.sh"
TEST_RC=$?
set -e

# Stop spectacle recording cleanly with SIGINT so MP4 moov atom is written
kill -INT "$REC_PID" 2>/dev/null || true
wait "$REC_PID" 2>/dev/null || true

if [[ -f "$OUT_VIDEO" ]]; then
    echo "Recording saved: $OUT_VIDEO ($(du -h "$OUT_VIDEO" | cut -f1))"
else
    echo "WARNING: Recording file was not created at $OUT_VIDEO" >&2
fi

exit "$TEST_RC"
