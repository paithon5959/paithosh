#!/usr/bin/env bash
set -euo pipefail

OUT_VIDEO="${1:-/tmp/paithosh-test-recording.mp4}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAME_DIR="/tmp/paithosh-frames-$$"

rm -rf "$FRAME_DIR" "$OUT_VIDEO"
mkdir -p "$FRAME_DIR"

echo "Starting frame capture -> $FRAME_DIR"
(
    idx=0
    while true; do
        printf -v fname "%s/frame_%05d.png" "$FRAME_DIR" "$idx"
        spectacle -b -n -f -o "$fname" >/dev/null 2>&1 || true
        idx=$((idx + 1))
        sleep 0.05
    done
) &
REC_PID=$!

set +e
bash "$SCRIPT_DIR/test-states.sh"
TEST_RC=$?
set -e

kill "$REC_PID" 2>/dev/null || true
wait "$REC_PID" 2>/dev/null || true

FRAME_COUNT=$(ls -1 "$FRAME_DIR"/frame_*.png 2>/dev/null | wc -l)
echo "Captured $FRAME_COUNT frames, encoding video..."

if [[ "$FRAME_COUNT" -gt 0 ]]; then
    ffmpeg -y -loglevel error -framerate 6 -pattern_type glob -i "$FRAME_DIR/frame_*.png" \
        -vf "crop=iw:min(ih\,760):0:0,scale=trunc(iw/2)*2:trunc(ih/2)*2" \
        -c:v libx264 -pix_fmt yuv420p -movflags +faststart "$OUT_VIDEO"
    echo "Recording saved: $OUT_VIDEO ($(du -h "$OUT_VIDEO" | cut -f1))"
else
    echo "WARNING: No frames captured" >&2
fi

rm -rf "$FRAME_DIR"
exit "$TEST_RC"
