#!/usr/bin/env python3
"""Paithosh Theme Codec (paish: schema v5, bit-packed Base64URL, v2/v3/v4-compatible).

Supports v5 encoding/decoding and backward-compatible v2/v3/v4 decoding.
Versioning (4 bits) and profile/preset name (5 + 6*L bits) are packed
directly inside the binary payload under the lowercase `paish:` prefix.
"""

from __future__ import annotations

import argparse
import json
import os
import random
import re
import sys
from pathlib import Path
from typing import Any

PREFIX = "paish:"
SCHEMA_VERSION = 5
SUPPORTED_DECODE_VERSIONS = (2, 3, 4, 5)
WALLPAPER_COLOR_MODES = ["Solid", "Gradient"]

B64URL = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
B64URL_MAP = {ch: idx for idx, ch in enumerate(B64URL)}

NAME_ALPHABET = "abcdefghijklmnopqrstuvwxyz0123456789-_ ."
NAME_MAP = {ch: idx for idx, ch in enumerate(NAME_ALPHABET)}
MAX_NAME_LEN = 31

PRESET_NAMES = [
    "OLED Pure",
    "Mica Dark",
    "Adaptive",
    "Nord Frost",
    "Mica Monochrome",
    "Catppuccin Mocha",
]
SURFACE_THEME_NAMES = ["OLED Pure", "Mica Dark", "Adaptive"]
ISLAND_RADII = ["12px", "18px", "26px (Default)"]
CURSOR_STYLES = ["sharp", "soft", "wedge"]
CURSOR_COLOR_MODES = ["auto", "theme", "fixed"]
LOCK_EFFECT_PRESETS = ["none", "snow", "rain", "wind"]
LOCK_AMBIENT_SOUNDS = ["none", "wind", "rain", "snow"]


def _clamp(val: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, val))


def _clamp_int(val: Any, lo: int, hi: int, default: int) -> int:
    try:
        n = int(round(float(val)))
    except (TypeError, ValueError):
        n = default
    return max(lo, min(hi, n))


def _clamp_float(val: Any, lo: float, hi: float, default: float) -> float:
    try:
        n = float(val)
    except (TypeError, ValueError):
        n = default
    return _clamp(n, lo, hi)


def _to_bool(val: Any, default: bool = False) -> bool:
    if isinstance(val, bool):
        return val
    if isinstance(val, (int, float)):
        return val >= 0.5
    if isinstance(val, str):
        return val.strip().lower() in ("1", "true", "yes", "on")
    return default


def _idx(lst: list[str], val: Any, default: int = 0) -> int:
    if isinstance(val, str) and val in lst:
        return lst.index(val)
    return default


def _normalize_island_radius_idx(val: Any) -> int:
    s = str(val or "26px (Default)")
    if "12" in s:
        return 0
    if "18" in s:
        return 1
    return 2


def _normalize_hex_rgb(val: Any) -> int:
    raw = re.sub(r"[^0-9a-fA-F]", "", str(val or "ffffff")).lower()
    if len(raw) != 6:
        raw = "ffffff"
    return int(raw, 16)


def _opt_hex_rgb(val: Any) -> int | None:
    raw = re.sub(r"[^0-9a-fA-F]", "", str(val or "").strip()).lower()
    if len(raw) != 6:
        return None
    return int(raw, 16)


def _normalize_profile_name(val: Any) -> str:
    raw = str(val or "").strip().lower()
    out: list[str] = []
    for ch in raw:
        if ch in NAME_MAP:
            out.append(ch)
        else:
            out.append("_")
    cleaned = "".join(out).strip("_ ")
    return cleaned[:MAX_NAME_LEN]


class BitWriter:
    def __init__(self) -> None:
        self._bits: list[int] = []

    def write(self, value: int, width: int) -> None:
        mask = (1 << width) - 1
        v = int(value) & mask
        for shift in range(width - 1, -1, -1):
            self._bits.append((v >> shift) & 1)

    def to_b64url(self) -> str:
        bits = self._bits
        pad = (-len(bits)) % 6
        if pad:
            bits = bits + [0] * pad
        chars: list[str] = []
        for i in range(0, len(bits), 6):
            chunk = (
                (bits[i] << 5)
                | (bits[i + 1] << 4)
                | (bits[i + 2] << 3)
                | (bits[i + 3] << 2)
                | (bits[i + 4] << 1)
                | bits[i + 5]
            )
            chars.append(B64URL[chunk])
        return "".join(chars)


class BitReader:
    def __init__(self, payload: str) -> None:
        self._bits: list[int] = []
        for ch in payload:
            idx = B64URL_MAP.get(ch)
            if idx is None:
                raise ValueError(f"Invalid base64url character: {ch!r}")
            for shift in range(5, -1, -1):
                self._bits.append((idx >> shift) & 1)
        self._pos = 0

    def remaining(self) -> int:
        return len(self._bits) - self._pos

    def read(self, width: int) -> int:
        if self.remaining() < width:
            raise ValueError("Unexpected end of paish bitstream")
        val = 0
        for _ in range(width):
            val = (val << 1) | self._bits[self._pos]
            self._pos += 1
        return val


def encode_state(state: dict[str, Any]) -> str:
    bw = BitWriter()

    # 0. Header (4 bits)
    bw.write(SCHEMA_VERSION, 4)

    # 1. Theme & Accent (48 bits)
    bw.write(_idx(PRESET_NAMES, state.get("presetName", state.get("activePreset")), 0), 4)
    bw.write(_idx(SURFACE_THEME_NAMES, state.get("globalSurfaceTheme"), 0), 3)
    bw.write(1 if _to_bool(state.get("customAccentActive"), False) else 0, 1)
    bw.write(1 if str(state.get("accentMode", "Solid")) == "Gradient" else 0, 1)
    bw.write(_clamp_int(_clamp_float(state.get("hueVal"), 0.0, 1.0, 0.0) * 360.0, 0, 360, 0), 9)
    bw.write(_clamp_int(_clamp_float(state.get("satVal"), 0.0, 1.0, 0.0) * 100.0, 0, 100, 0), 7)
    bw.write(_clamp_int(_clamp_float(state.get("valVal"), 0.0, 1.0, 0.92) * 100.0, 0, 100, 92), 7)
    bw.write(_clamp_int(state.get("gradientAngle"), 0, 360, 135), 9)
    bw.write(1 if _to_bool(state.get("gooeyEnabled"), True) else 0, 1)
    speed = _clamp_float(state.get("speedMultiplier"), 0.5, 2.5, 1.0)
    bw.write(_clamp_int((speed - 0.5) * 20.0, 0, 40, 10), 6)

    # 2. Decoration, Motion & Blur (51 bits)
    bw.write(_clamp_int(state.get("cornerRounding"), 0, 28, 18), 5)
    bw.write(1 if _to_bool(state.get("shadowEnabled"), True) else 0, 1)
    bw.write(_clamp_int(state.get("shadowRange"), 0, 48, 24), 6)
    inact = _clamp_float(state.get("inactiveOpacity"), 0.6, 1.0, 0.96)
    bw.write(_clamp_int(inact * 100.0 - 60.0, 0, 40, 36), 6)
    bw.write(1 if _to_bool(state.get("animationsEnabled"), True) else 0, 1)
    bw.write(_clamp_int(state.get("springStiffness"), 80, 600, 260) - 80, 10)
    bw.write(_clamp_int(state.get("springDamping"), 5, 60, 23) - 5, 6)
    bw.write(1 if _to_bool(state.get("blurEnabled"), True) else 0, 1)
    bw.write(_clamp_int(state.get("blurSize"), 1, 24, 6) - 1, 5)
    bw.write(_clamp_int(state.get("blurPasses"), 1, 6, 2) - 1, 3)
    vib = _clamp_float(state.get("blurVibrancy"), 0.0, 1.0, 0.12)
    bw.write(_clamp_int(vib * 100.0, 0, 100, 12), 7)

    # 3. Layout & Dynamic Island (30 bits)
    bw.write(1 if str(state.get("layoutName", "dwindle")) == "master" else 0, 1)
    bw.write(_clamp_int(state.get("masterRatio"), 30, 80, 55) - 30, 6)
    bw.write(1 if _to_bool(state.get("preserveSplit"), True) else 0, 1)
    bw.write(_clamp_int(state.get("gapsIn"), 0, 32, 6), 6)
    bw.write(_clamp_int(state.get("gapsOut"), 0, 48, 12), 6)
    bw.write(_clamp_int(state.get("borderSize"), 0, 6, 1), 3)
    bw.write(1 if _to_bool(state.get("activeBorderHighlight"), True) else 0, 1)
    bw.write(1 if str(state.get("barPosition", "top")) == "bottom" else 0, 1)
    bw.write(_normalize_island_radius_idx(state.get("islandCornerRadius")), 2)
    bw.write(1 if _to_bool(state.get("topEdgeOffset"), True) else 0, 1)
    bw.write(1 if _to_bool(state.get("hideBarFullscreen"), True) else 0, 1)
    bw.write(1 if _to_bool(state.get("autoHideOnOverlap"), False) else 0, 1)

    # 4. Cursor (35 bits)
    bw.write(_idx(CURSOR_STYLES, state.get("cursorStyle"), 0), 2)
    bw.write(_clamp_int(state.get("cursorSize"), 16, 64, 24) - 16, 6)
    bw.write(_idx(CURSOR_COLOR_MODES, state.get("cursorColorMode"), 0), 2)
    bw.write(_normalize_hex_rgb(state.get("cursorFixedColor")), 24)
    bw.write(1 if _to_bool(state.get("cursorMotionBlur"), False) else 0, 1)

    # 5. Lock Screen (30 bits)
    bw.write(_idx(LOCK_EFFECT_PRESETS, state.get("lockEffectPreset"), 0), 2)
    bw.write(_idx(LOCK_AMBIENT_SOUNDS, state.get("lockAmbientSound"), 1), 2)
    bw.write(1 if _to_bool(state.get("lockSilentMode"), False) else 0, 1)
    bw.write(1 if _to_bool(state.get("lockSfxEnabled"), True) else 0, 1)
    bw.write(1 if _to_bool(state.get("lockShowNotifications"), True) else 0, 1)
    bw.write(1 if _to_bool(state.get("lockHideNotifContent"), False) else 0, 1)
    bw.write(1 if _to_bool(state.get("lockShowMedia"), True) else 0, 1)
    bw.write(1 if _to_bool(state.get("lockShowSystemAlerts"), True) else 0, 1)
    bw.write(_clamp_int(state.get("lockEffectIntensity"), 50, 150, 100) - 50, 7)
    bw.write(_clamp_int(state.get("lockAmbientVolume"), 5, 100, 35) - 5, 7)
    bw.write(_clamp_int(state.get("lockDimOpacity"), 15, 75, 36) - 15, 6)

    # 6. Embedded Profile / Preset Name (5 + 6*L bits)
    clean_name = _normalize_profile_name(state.get("profileName", ""))
    bw.write(len(clean_name), 5)
    for ch in clean_name:
        bw.write(NAME_MAP[ch], 6)

    # 7. Extended Colors & Gradients (v3)
    shell_grad = _to_bool(state.get("shellGradientEnabled"), False)
    bw.write(1 if shell_grad else 0, 1)
    if shell_grad:
        bw.write(_normalize_hex_rgb(state.get("pillBg2")), 24)

    surf_grad = _to_bool(state.get("surfaceGradientEnabled"), False)
    bw.write(1 if surf_grad else 0, 1)
    if surf_grad:
        bw.write(_normalize_hex_rgb(state.get("surfaceBg2")), 24)

    custom_acc2 = _to_bool(state.get("customAccent2Active"), False)
    bw.write(1 if custom_acc2 else 0, 1)
    if custom_acc2:
        bw.write(_normalize_hex_rgb(state.get("accent2")), 24)

    palette_slots = [
        _opt_hex_rgb(state.get("customPillBg")),
        _opt_hex_rgb(state.get("customSurfaceBg")),
        _opt_hex_rgb(state.get("customSurfaceRaised")),
        _opt_hex_rgb(state.get("customText")),
        _opt_hex_rgb(state.get("customBorderColor")),
    ]
    has_palette = any(x is not None for x in palette_slots)
    bw.write(1 if has_palette else 0, 1)
    if has_palette:
        for slot_rgb in palette_slots:
            if slot_rgb is not None:
                bw.write(1, 1)
                bw.write(slot_rgb, 24)
            else:
                bw.write(0, 1)

    # 8. Adaptive Wallpaper Color Mode (v4: 2 bits)
    wp_disabled = _to_bool(state.get("wallpapersDisabled"), False)
    wp_enabled = (not wp_disabled) and _to_bool(state.get("wallpaperColorEnabled"), False)
    wp_mode_idx = 1 if str(state.get("wallpaperColorMode", "Solid")).strip().lower() == "gradient" else 0
    bw.write(1 if wp_enabled else 0, 1)
    bw.write(wp_mode_idx, 1)

    # 9. Wallpapers Disabled Flag (v5: 1 bit)
    bw.write(1 if wp_disabled else 0, 1)

    return PREFIX + bw.to_b64url()


def decode_code(code: str) -> dict[str, Any]:
    raw = str(code or "").strip()
    if not raw.startswith(PREFIX):
        raise ValueError("Invalid prefix: expected lowercase 'paish:'")
    payload = raw[len(PREFIX):].strip()
    if not payload:
        raise ValueError("Empty paish payload")

    br = BitReader(payload)

    # 0. Header (4 bits)
    version = br.read(4)
    if version not in SUPPORTED_DECODE_VERSIONS:
        raise ValueError(f"Unsupported paish schema version: {version}")

    # 1. Theme & Accent (48 bits)
    preset_idx = min(br.read(4), len(PRESET_NAMES) - 1)
    surface_idx = min(br.read(3), len(SURFACE_THEME_NAMES) - 1)
    custom_accent = br.read(1) == 1
    accent_mode = "Gradient" if br.read(1) == 1 else "Solid"
    hue_val = round(min(br.read(9), 360) / 360.0, 4)
    sat_val = round(min(br.read(7), 100) / 100.0, 2)
    val_val = round(min(br.read(7), 100) / 100.0, 2)
    gradient_angle = min(br.read(9), 360)
    gooey_enabled = br.read(1) == 1
    speed_multiplier = round(0.5 + min(br.read(6), 40) * 0.05, 2)

    # 2. Decoration, Motion & Blur (51 bits)
    corner_rounding = min(br.read(5), 28)
    shadow_enabled = br.read(1) == 1
    shadow_range = min(br.read(6), 48)
    inactive_opacity = round((60 + min(br.read(6), 40)) / 100.0, 2)
    animations_enabled = br.read(1) == 1
    spring_stiffness = 80 + min(br.read(10), 520)
    spring_damping = 5 + min(br.read(6), 55)
    blur_enabled = br.read(1) == 1
    blur_size = 1 + min(br.read(5), 23)
    blur_passes = 1 + min(br.read(3), 5)
    blur_vibrancy = round(min(br.read(7), 100) / 100.0, 2)

    # 3. Layout & Dynamic Island (30 bits)
    layout_name = "master" if br.read(1) == 1 else "dwindle"
    master_ratio = 30 + min(br.read(6), 50)
    preserve_split = br.read(1) == 1
    gaps_in = min(br.read(6), 32)
    gaps_out = min(br.read(6), 48)
    border_size = min(br.read(3), 6)
    active_border_highlight = br.read(1) == 1
    bar_position = "bottom" if br.read(1) == 1 else "top"
    island_rad_idx = min(br.read(2), len(ISLAND_RADII) - 1)
    top_edge_offset = br.read(1) == 1
    hide_bar_fullscreen = br.read(1) == 1
    auto_hide_on_overlap = br.read(1) == 1

    # 4. Cursor (35 bits)
    cursor_style_idx = min(br.read(2), len(CURSOR_STYLES) - 1)
    cursor_size = 16 + min(br.read(6), 48)
    cursor_color_mode_idx = min(br.read(2), len(CURSOR_COLOR_MODES) - 1)
    cursor_fixed_rgb = br.read(24)
    cursor_motion_blur = br.read(1) == 1

    # 5. Lock Screen (30 bits)
    lock_effect_idx = min(br.read(2), len(LOCK_EFFECT_PRESETS) - 1)
    lock_sound_idx = min(br.read(2), len(LOCK_AMBIENT_SOUNDS) - 1)
    lock_silent = br.read(1) == 1
    lock_sfx = br.read(1) == 1
    lock_show_notif = br.read(1) == 1
    lock_hide_notif = br.read(1) == 1
    lock_show_media = br.read(1) == 1
    lock_show_alerts = br.read(1) == 1
    lock_intensity = 50 + min(br.read(7), 100)
    lock_volume = 5 + min(br.read(7), 95)
    lock_dim = 15 + min(br.read(6), 60)

    # 6. Embedded Profile / Preset Name (5 + 6*L bits)
    name_len = br.read(5)
    name_chars: list[str] = []
    for _ in range(name_len):
        c_idx = br.read(6)
        if c_idx < len(NAME_ALPHABET):
            name_chars.append(NAME_ALPHABET[c_idx])
    profile_name = "".join(name_chars)

    # 7. Extended Colors & Gradients (v3; clean defaults for v2)
    shell_grad = False
    pill_bg2 = ""
    surf_grad = False
    surf_bg2 = ""
    custom_acc2 = False
    accent2 = ""
    custom_palette = False
    c_pill = ""
    c_surf = ""
    c_raised = ""
    c_text = ""
    c_border = ""

    wp_enabled = False
    wp_mode = "Solid"
    wp_disabled = False

    if version >= 3 and br.remaining() >= 4:
        shell_grad = br.read(1) == 1
        if shell_grad:
            pill_bg2 = f"#{br.read(24):06x}"
        surf_grad = br.read(1) == 1
        if surf_grad:
            surf_bg2 = f"#{br.read(24):06x}"
        custom_acc2 = br.read(1) == 1
        if custom_acc2:
            accent2 = f"#{br.read(24):06x}"
        custom_palette = br.read(1) == 1
        if custom_palette:
            decoded_slots: list[str] = []
            for _ in range(5):
                if br.read(1) == 1:
                    decoded_slots.append(f"#{br.read(24):06x}")
                else:
                    decoded_slots.append("")
            c_pill, c_surf, c_raised, c_text, c_border = decoded_slots

    if version >= 4 and br.remaining() >= 2:
        wp_enabled = br.read(1) == 1
        wp_mode = WALLPAPER_COLOR_MODES[br.read(1)]

    if version >= 5 and br.remaining() >= 1:
        wp_disabled = br.read(1) == 1
        if wp_disabled:
            wp_enabled = False

    return {
        "version": version,
        "presetName": PRESET_NAMES[preset_idx],
        "globalSurfaceTheme": SURFACE_THEME_NAMES[surface_idx],
        "customAccentActive": custom_accent,
        "accentMode": accent_mode,
        "hueVal": hue_val,
        "satVal": sat_val,
        "valVal": val_val,
        "gradientAngle": gradient_angle,
        "gooeyEnabled": gooey_enabled,
        "speedMultiplier": speed_multiplier,
        "cornerRounding": corner_rounding,
        "shadowEnabled": shadow_enabled,
        "shadowRange": shadow_range,
        "inactiveOpacity": inactive_opacity,
        "animationsEnabled": animations_enabled,
        "springStiffness": spring_stiffness,
        "springDamping": spring_damping,
        "blurEnabled": blur_enabled,
        "blurSize": blur_size,
        "blurPasses": blur_passes,
        "blurVibrancy": blur_vibrancy,
        "layoutName": layout_name,
        "masterRatio": master_ratio,
        "preserveSplit": preserve_split,
        "gapsIn": gaps_in,
        "gapsOut": gaps_out,
        "borderSize": border_size,
        "activeBorderHighlight": active_border_highlight,
        "barPosition": bar_position,
        "islandCornerRadius": ISLAND_RADII[island_rad_idx],
        "topEdgeOffset": top_edge_offset,
        "hideBarFullscreen": hide_bar_fullscreen,
        "autoHideOnOverlap": auto_hide_on_overlap,
        "cursorStyle": CURSOR_STYLES[cursor_style_idx],
        "cursorSize": cursor_size,
        "cursorColorMode": CURSOR_COLOR_MODES[cursor_color_mode_idx],
        "cursorFixedColor": f"#{cursor_fixed_rgb:06x}",
        "cursorMotionBlur": cursor_motion_blur,
        "lockEffectPreset": LOCK_EFFECT_PRESETS[lock_effect_idx],
        "lockAmbientSound": LOCK_AMBIENT_SOUNDS[lock_sound_idx],
        "lockSilentMode": lock_silent,
        "lockSfxEnabled": lock_sfx,
        "lockShowNotifications": lock_show_notif,
        "lockHideNotifContent": lock_hide_notif,
        "lockShowMedia": lock_show_media,
        "lockShowSystemAlerts": lock_show_alerts,
        "lockEffectIntensity": lock_intensity,
        "lockAmbientVolume": lock_volume,
        "lockDimOpacity": lock_dim,
        "profileName": profile_name,
        "shellGradientEnabled": shell_grad,
        "pillBg2": pill_bg2,
        "surfaceGradientEnabled": surf_grad,
        "surfaceBg2": surf_bg2,
        "customAccent2Active": custom_acc2,
        "accent2": accent2,
        "customPaletteActive": custom_palette,
        "customPillBg": c_pill,
        "customSurfaceBg": c_surf,
        "customSurfaceRaised": c_raised,
        "customText": c_text,
        "customBorderColor": c_border,
        "wallpaperColorEnabled": wp_enabled,
        "wallpaperColorMode": wp_mode,
        "wallpapersDisabled": wp_disabled,
    }


def _self_test() -> None:
    cases = [
        # Default unnamed preset
        {"profileName": ""},
        # Named preset
        {"presetName": "Nord Frost", "profileName": "nord-frost"},
        # Min bounds
        {
            "presetName": PRESET_NAMES[0],
            "globalSurfaceTheme": SURFACE_THEME_NAMES[0],
            "customAccentActive": False,
            "accentMode": "Solid",
            "hueVal": 0.0,
            "satVal": 0.0,
            "valVal": 0.0,
            "gradientAngle": 0,
            "gooeyEnabled": False,
            "speedMultiplier": 0.5,
            "cornerRounding": 0,
            "shadowEnabled": False,
            "shadowRange": 0,
            "inactiveOpacity": 0.6,
            "animationsEnabled": False,
            "springStiffness": 80,
            "springDamping": 5,
            "blurEnabled": False,
            "blurSize": 1,
            "blurPasses": 1,
            "blurVibrancy": 0.0,
            "layoutName": "dwindle",
            "masterRatio": 30,
            "preserveSplit": False,
            "gapsIn": 0,
            "gapsOut": 0,
            "borderSize": 0,
            "activeBorderHighlight": False,
            "barPosition": "top",
            "islandCornerRadius": "12px",
            "topEdgeOffset": False,
            "hideBarFullscreen": False,
            "autoHideOnOverlap": False,
            "cursorStyle": "sharp",
            "cursorSize": 16,
            "cursorColorMode": "auto",
            "cursorFixedColor": "#000000",
            "cursorMotionBlur": False,
            "lockEffectPreset": "none",
            "lockAmbientSound": "none",
            "lockSilentMode": False,
            "lockSfxEnabled": False,
            "lockShowNotifications": False,
            "lockHideNotifContent": False,
            "lockShowMedia": False,
            "lockShowSystemAlerts": False,
            "lockEffectIntensity": 50,
            "lockAmbientVolume": 5,
            "lockDimOpacity": 15,
            "profileName": "min",
            "shellGradientEnabled": False,
            "pillBg2": "",
            "surfaceGradientEnabled": False,
            "surfaceBg2": "",
            "customAccent2Active": False,
            "accent2": "",
            "customPaletteActive": False,
            "customPillBg": "",
            "customSurfaceBg": "",
            "customSurfaceRaised": "",
            "customText": "",
            "customBorderColor": "",
            "wallpaperColorEnabled": False,
            "wallpaperColorMode": "Solid",
            "wallpapersDisabled": False,
        },
        # Max bounds
        {
            "presetName": PRESET_NAMES[-1],
            "globalSurfaceTheme": SURFACE_THEME_NAMES[-1],
            "customAccentActive": True,
            "accentMode": "Gradient",
            "hueVal": 1.0,
            "satVal": 1.0,
            "valVal": 1.0,
            "gradientAngle": 360,
            "gooeyEnabled": True,
            "speedMultiplier": 2.5,
            "cornerRounding": 28,
            "shadowEnabled": True,
            "shadowRange": 48,
            "inactiveOpacity": 1.0,
            "animationsEnabled": True,
            "springStiffness": 600,
            "springDamping": 60,
            "blurEnabled": True,
            "blurSize": 24,
            "blurPasses": 6,
            "blurVibrancy": 1.0,
            "layoutName": "master",
            "masterRatio": 80,
            "preserveSplit": True,
            "gapsIn": 32,
            "gapsOut": 48,
            "borderSize": 6,
            "activeBorderHighlight": True,
            "barPosition": "bottom",
            "islandCornerRadius": "26px (Default)",
            "topEdgeOffset": True,
            "hideBarFullscreen": True,
            "autoHideOnOverlap": True,
            "cursorStyle": "wedge",
            "cursorSize": 64,
            "cursorColorMode": "fixed",
            "cursorFixedColor": "#ff88aa",
            "cursorMotionBlur": True,
            "lockEffectPreset": "wind",
            "lockAmbientSound": "snow",
            "lockSilentMode": True,
            "lockSfxEnabled": True,
            "lockShowNotifications": True,
            "lockHideNotifContent": True,
            "lockShowMedia": True,
            "lockShowSystemAlerts": True,
            "lockEffectIntensity": 150,
            "lockAmbientVolume": 100,
            "lockDimOpacity": 75,
            "profileName": "max-profile_1.0",
            "shellGradientEnabled": True,
            "pillBg2": "#1a2233",
            "surfaceGradientEnabled": True,
            "surfaceBg2": "#222c40",
            "customAccent2Active": True,
            "accent2": "#88c0d0",
            "customPaletteActive": True,
            "customPillBg": "#0a0d14",
            "customSurfaceBg": "#111622",
            "customSurfaceRaised": "#1c2436",
            "customText": "#eef4ff",
            "customBorderColor": "#7da6d9",
            "wallpaperColorEnabled": True,
            "wallpaperColorMode": "Gradient",
            "wallpapersDisabled": False,
        },
        # Wallpapers disabled (solid/gradient theme background + forced manual colors)
        {
            "presetName": "Nord Frost",
            "globalSurfaceTheme": "Adaptive",
            "customAccentActive": True,
            "accentMode": "Gradient",
            "hueVal": 0.55,
            "satVal": 0.45,
            "valVal": 0.85,
            "gradientAngle": 120,
            "profileName": "no-wallpaper-theme",
            "shellGradientEnabled": True,
            "pillBg2": "#222b3b",
            "surfaceGradientEnabled": True,
            "surfaceBg2": "#273142",
            "customAccent2Active": False,
            "accent2": "",
            "customPaletteActive": True,
            "customPillBg": "#1a1f29",
            "customSurfaceBg": "#212734",
            "customSurfaceRaised": "",
            "customText": "",
            "customBorderColor": "",
            "wallpaperColorEnabled": False,
            "wallpaperColorMode": "Solid",
            "wallpapersDisabled": True,
        },
        # User A -> User B preservation case (wallpaper enabled + custom manual setup)
        {
            "presetName": "Catppuccin Mocha",
            "globalSurfaceTheme": "Adaptive",
            "customAccentActive": True,
            "accentMode": "Gradient",
            "hueVal": 0.75,
            "satVal": 0.65,
            "valVal": 0.94,
            "gradientAngle": 145,
            "profileName": "user-a-wallpaper-share",
            "shellGradientEnabled": True,
            "pillBg2": "#2a243d",
            "surfaceGradientEnabled": True,
            "surfaceBg2": "#231e36",
            "customAccent2Active": True,
            "accent2": "#f5c2e7",
            "customPaletteActive": True,
            "customPillBg": "#161322",
            "customSurfaceBg": "#1c182c",
            "customSurfaceRaised": "#26213c",
            "customText": "#f4ecff",
            "customBorderColor": "#9d86c7",
            "wallpaperColorEnabled": True,
            "wallpaperColorMode": "Solid",
            "wallpapersDisabled": False,
        },
    ]

    rng = random.Random(42)
    for idx in range(25):
        sh_grad = rng.choice([True, False])
        sf_grad = rng.choice([True, False])
        ac2_on = rng.choice([True, False])
        wp_dis = rng.choice([True, False])
        wp_col = (not wp_dis) and rng.choice([True, False])
        slot_vals = [
            f"#{rng.randint(0, 0xFFFFFF):06x}" if rng.choice([True, False]) else ""
            for _ in range(5)
        ]
        cases.append(
            {
                "presetName": rng.choice(PRESET_NAMES),
                "globalSurfaceTheme": rng.choice(SURFACE_THEME_NAMES),
                "customAccentActive": rng.choice([True, False]),
                "accentMode": rng.choice(["Solid", "Gradient"]),
                "hueVal": round(rng.randint(0, 360) / 360.0, 4),
                "satVal": round(rng.randint(0, 100) / 100.0, 2),
                "valVal": round(rng.randint(0, 100) / 100.0, 2),
                "gradientAngle": rng.randint(0, 360),
                "gooeyEnabled": rng.choice([True, False]),
                "speedMultiplier": round(0.5 + rng.randint(0, 40) * 0.05, 2),
                "cornerRounding": rng.randint(0, 28),
                "shadowEnabled": rng.choice([True, False]),
                "shadowRange": rng.randint(0, 48),
                "inactiveOpacity": round((60 + rng.randint(0, 40)) / 100.0, 2),
                "animationsEnabled": rng.choice([True, False]),
                "springStiffness": rng.randint(80, 600),
                "springDamping": rng.randint(5, 60),
                "blurEnabled": rng.choice([True, False]),
                "blurSize": rng.randint(1, 24),
                "blurPasses": rng.randint(1, 6),
                "blurVibrancy": round(rng.randint(0, 100) / 100.0, 2),
                "layoutName": rng.choice(["dwindle", "master"]),
                "masterRatio": rng.randint(30, 80),
                "preserveSplit": rng.choice([True, False]),
                "gapsIn": rng.randint(0, 32),
                "gapsOut": rng.randint(0, 48),
                "borderSize": rng.randint(0, 6),
                "activeBorderHighlight": rng.choice([True, False]),
                "barPosition": rng.choice(["top", "bottom"]),
                "islandCornerRadius": rng.choice(ISLAND_RADII),
                "topEdgeOffset": rng.choice([True, False]),
                "hideBarFullscreen": rng.choice([True, False]),
                "autoHideOnOverlap": rng.choice([True, False]),
                "cursorStyle": rng.choice(CURSOR_STYLES),
                "cursorSize": rng.randint(16, 64),
                "cursorColorMode": rng.choice(CURSOR_COLOR_MODES),
                "cursorFixedColor": f"#{rng.randint(0, 0xFFFFFF):06x}",
                "cursorMotionBlur": rng.choice([True, False]),
                "lockEffectPreset": rng.choice(LOCK_EFFECT_PRESETS),
                "lockAmbientSound": rng.choice(LOCK_AMBIENT_SOUNDS),
                "lockSilentMode": rng.choice([True, False]),
                "lockSfxEnabled": rng.choice([True, False]),
                "lockShowNotifications": rng.choice([True, False]),
                "lockHideNotifContent": rng.choice([True, False]),
                "lockShowMedia": rng.choice([True, False]),
                "lockShowSystemAlerts": rng.choice([True, False]),
                "lockEffectIntensity": rng.randint(50, 150),
                "lockAmbientVolume": rng.randint(5, 100),
                "lockDimOpacity": rng.randint(15, 75),
                "profileName": f"rnd-{idx}",
                "shellGradientEnabled": sh_grad,
                "pillBg2": f"#{rng.randint(0, 0xFFFFFF):06x}" if sh_grad else "",
                "surfaceGradientEnabled": sf_grad,
                "surfaceBg2": f"#{rng.randint(0, 0xFFFFFF):06x}" if sf_grad else "",
                "customAccent2Active": ac2_on,
                "accent2": f"#{rng.randint(0, 0xFFFFFF):06x}" if ac2_on else "",
                "customPaletteActive": any(x != "" for x in slot_vals),
                "customPillBg": slot_vals[0],
                "customSurfaceBg": slot_vals[1],
                "customSurfaceRaised": slot_vals[2],
                "customText": slot_vals[3],
                "customBorderColor": slot_vals[4],
                "wallpaperColorEnabled": wp_col,
                "wallpaperColorMode": rng.choice(WALLPAPER_COLOR_MODES),
                "wallpapersDisabled": wp_dis,
            }
        )

    for i, sample in enumerate(cases):
        code = encode_state(sample)
        assert code.startswith("paish:"), f"case {i}: bad prefix {code}"
        assert "=" not in code, f"case {i}: unexpected padding in {code}"
        decoded = decode_code(code)
        assert decoded["version"] == 5
        reencoded = encode_state(decoded)
        assert reencoded == code, f"case {i}: round-trip mismatch\n  {code}\n  {reencoded}"
        if i >= 2:
            for k, v in sample.items():
                assert decoded[k] == v, f"case {i} key {k}: expected {v!r}, got {decoded[k]!r}"

    # Verify invariant: wallpapersDisabled=True forces wallpaperColorEnabled=False
    inv_code = encode_state({"wallpapersDisabled": True, "wallpaperColorEnabled": True, "wallpaperColorMode": "Gradient"})
    inv_dec = decode_code(inv_code)
    assert inv_dec["wallpapersDisabled"] is True
    assert inv_dec["wallpaperColorEnabled"] is False

    # Verify v2 backward compatibility with real existing v2 code
    legacy_v2 = "paish:Iz0t1iUEqGSKZCNBJGYxiqBB___-FtkeVOGIKAoWm"
    dec_v2 = decode_code(legacy_v2)
    assert dec_v2["version"] == 2
    assert dec_v2["shellGradientEnabled"] is False
    assert dec_v2["customPaletteActive"] is False
    assert dec_v2["customPillBg"] == ""
    assert dec_v2["wallpaperColorEnabled"] is False
    assert dec_v2["wallpaperColorMode"] == "Solid"
    assert dec_v2["wallpapersDisabled"] is False

    # Verify v3 backward compatibility (synthesized v3 header + minimal body)
    v3_bw = BitWriter()
    v3_bw.write(3, 4)  # version 3
    for _ in range(48 + 51 + 30 + 35 + 30 + 5 + 4):
        v3_bw.write(0, 1)
    dec_v3 = decode_code(PREFIX + v3_bw.to_b64url())
    assert dec_v3["version"] == 3
    assert dec_v3["wallpaperColorEnabled"] is False
    assert dec_v3["wallpaperColorMode"] == "Solid"
    assert dec_v3["wallpapersDisabled"] is False

    # Verify v4 backward compatibility (synthesized v4 header + minimal body + wp_enabled=1, Gradient)
    v4_bw = BitWriter()
    v4_bw.write(4, 4)  # version 4
    for _ in range(48 + 51 + 30 + 35 + 30 + 5 + 4):
        v4_bw.write(0, 1)
    v4_bw.write(1, 1)  # wallpaperColorEnabled
    v4_bw.write(1, 1)  # Gradient
    dec_v4 = decode_code(PREFIX + v4_bw.to_b64url())
    assert dec_v4["version"] == 4
    assert dec_v4["wallpaperColorEnabled"] is True
    assert dec_v4["wallpaperColorMode"] == "Gradient"
    assert dec_v4["wallpapersDisabled"] is False

    # Verify v1 & unsupported versions are rejected
    bad_v6_bw = BitWriter()
    bad_v6_bw.write(6, 4)
    for bad in ("PAISH1:abc", "1;0;0;26", "paish:", PREFIX + bad_v6_bw.to_b64url()):
        try:
            decode_code(bad)
            raise AssertionError(f"Expected failure for {bad!r}")
        except ValueError:
            pass

    c0 = encode_state(cases[0])
    c1 = encode_state(cases[1])
    assert len(c0) <= 48, f"Expected compact default code <=48 chars, got {len(c0)}: {c0}"
    print(f"OK ({len(cases)} v5 round-trip + v2/v3/v4 compat passed)")
    print(f"  unnamed ({len(c0)} chars): {c0}")
    print(f"  named   ({len(c1)} chars): {c1}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Paithosh paish: v2 codec")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_enc = sub.add_parser("encode", help="Encode JSON state from stdin or --json")
    p_enc.add_argument("--json", dest="json_str", default=None, help="JSON state string")
    p_enc.add_argument("--out", dest="out_path", default=None, help="Write code to file path")

    p_dec = sub.add_parser("decode", help="Decode paish: code to JSON")
    p_dec.add_argument("code", help="paish:... string")

    p_decf = sub.add_parser("decode-file", help="Decode a .paish file to JSON")
    p_decf.add_argument("path", help="Path to .paish file")

    sub.add_parser("self-test", help="Run round-trip self-test")

    args = parser.parse_args()

    if args.cmd == "self-test":
        _self_test()
        return 0

    if args.cmd == "encode":
        raw_json = args.json_str if args.json_str is not None else sys.stdin.read()
        state = json.loads(raw_json)
        code = encode_state(state)
        if args.out_path:
            out_file = Path(args.out_path)
            out_file.parent.mkdir(parents=True, exist_ok=True)
            out_file.write_text(code + "\n", encoding="utf-8")
        print(code)
        return 0

    if args.cmd == "decode":
        decoded = decode_code(args.code)
        print(json.dumps(decoded, separators=(",", ":")))
        return 0

    if args.cmd == "decode-file":
        p = Path(args.path)
        if not p.is_file():
            print(f"File not found: {p}", file=sys.stderr)
            return 2
        content = p.read_text(encoding="utf-8").strip()
        decoded = decode_code(content)
        print(json.dumps(decoded, separators=(",", ":")))
        return 0

    return 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"paish error: {exc}", file=sys.stderr)
        raise SystemExit(1)
