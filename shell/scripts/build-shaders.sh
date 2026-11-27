#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHADER_DIR="$(cd "$SCRIPT_DIR/../assets/shaders" && pwd)"

QSB_BIN="${QSB_BIN:-/usr/bin/qsb-qt6}"
if [[ ! -x "$QSB_BIN" ]]; then
    QSB_BIN="$(command -v qsb-qt6 || command -v qsb || true)"
fi

if [[ -z "$QSB_BIN" ]]; then
    echo "Error: qsb-qt6 / qsb not found" >&2
    exit 1
fi

"$QSB_BIN" --qt6 \
    -o "$SHADER_DIR/gooey.frag.qsb" \
    "$SHADER_DIR/gooey.frag"

"$QSB_BIN" --qt6 \
    -o "$SHADER_DIR/cursor_blur.frag.qsb" \
    "$SHADER_DIR/cursor_blur.frag"

"$QSB_BIN" --qt6 \
    -o "$SHADER_DIR/splash_glow.frag.qsb" \
    "$SHADER_DIR/splash_glow.frag"

"$QSB_BIN" --qt6 \
    -o "$SHADER_DIR/theme_gradient.frag.qsb" \
    "$SHADER_DIR/theme_gradient.frag"

"$QSB_BIN" --qt6 \
    -o "$SHADER_DIR/icon_tint.frag.qsb" \
    "$SHADER_DIR/icon_tint.frag"

echo "Compiled gooey.frag.qsb, cursor_blur.frag.qsb, splash_glow.frag.qsb, theme_gradient.frag.qsb & icon_tint.frag.qsb"
