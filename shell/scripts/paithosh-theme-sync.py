#!/usr/bin/env python3
"""Automatic GTK (GTK3/GTK4/Libadwaita) & Qt (Qt5/Qt6/KDE) theme color sync.

Consumes Paithosh's active palette (via --json from Theme.exportTargetRenderColors()
or --preset for installer/CLI priming) and atomically updates:
  - ~/.config/gtk-4.0/{paithosh.css, gtk.css, settings.ini}
  - ~/.config/gtk-3.0/{paithosh.css, gtk.css, settings.ini}
  - ~/.config/qt6ct/{colors/paithosh.conf, qt6ct.conf}
  - ~/.config/qt5ct/{colors/paithosh.conf, qt5ct.conf}
  - ~/.local/share/color-schemes/Paithosh.colors & ~/.config/kdeglobals
  - ~/.config/hypr/config/env.lua (ensuring QT_QPA_PLATFORMTHEME=qt6ct)
  - Live gsettings (color-scheme, gtk-theme, accent-color) & systemd/D-Bus env
"""

from __future__ import annotations

import argparse
import colorsys
import fcntl
import glob
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from typing import Any, Dict, List, Optional, Tuple


# Matches shell/Theme.qml presetCatalog
PRESETS: Dict[str, Dict[str, Any]] = {
    "OLED Pure": {
        "pillBg": "#000000",
        "surfaceBg": "#0b0b0c",
        "surfaceRaised": "#101012",
        "text": "#ffffff",
        "accent": "#ffffff",
        "accent2": "#ffffff",
        "accentFg": "#000000",
        "borderColor": "#ffffff",
        "borderAlpha": 0.14,
        "cardAlpha": 0.08,
        "hoverAlpha": 0.14,
    },
    "Nord Frost": {
        "pillBg": "#1a1f29",
        "surfaceBg": "#212734",
        "surfaceRaised": "#293040",
        "text": "#eceff4",
        "accent": "#88c0d0",
        "accent2": "#81a1c1",
        "accentFg": "#141a24",
        "borderColor": "#eceff4",
        "borderAlpha": 0.18,
        "cardAlpha": 0.09,
        "hoverAlpha": 0.15,
    },
    "Mica Monochrome": {
        "pillBg": "#141416",
        "surfaceBg": "#1b1b1e",
        "surfaceRaised": "#232327",
        "text": "#f2f2f4",
        "accent": "#d4d4d8",
        "accent2": "#d4d4d8",
        "accentFg": "#111113",
        "borderColor": "#f2f2f4",
        "borderAlpha": 0.16,
        "cardAlpha": 0.09,
        "hoverAlpha": 0.15,
    },
    "Catppuccin Mocha": {
        "pillBg": "#1e1e2e",
        "surfaceBg": "#181825",
        "surfaceRaised": "#313244",
        "text": "#cdd6f4",
        "accent": "#cba6f7",
        "accent2": "#89b4fa",
        "accentFg": "#11111b",
        "borderColor": "#cdd6f4",
        "borderAlpha": 0.18,
        "cardAlpha": 0.09,
        "hoverAlpha": 0.15,
    },
    "Mica Dark": {
        "pillBg": "#121418",
        "surfaceBg": "#161920",
        "surfaceRaised": "#1d212a",
        "text": "#eef2f9",
        "accent": "#a8c7fa",
        "accent2": "#a8c7fa",
        "accentFg": "#0b1220",
        "borderColor": "#eef2f9",
        "borderAlpha": 0.16,
        "cardAlpha": 0.09,
        "hoverAlpha": 0.15,
    },
    "Adaptive": {
        "pillBg": "#0d1216",
        "surfaceBg": "#10161c",
        "surfaceRaised": "#161e26",
        "text": "#edf6f5",
        "accent": "#80cbc4",
        "accent2": "#4db6ac",
        "accentFg": "#071a18",
        "borderColor": "#edf6f5",
        "borderAlpha": 0.16,
        "cardAlpha": 0.09,
        "hoverAlpha": 0.15,
    },
}

HEX_RE = re.compile(r"^#?([0-9a-fA-F]{6})(?:[0-9a-fA-F]{2})?$")


def _clamp(v: float, lo: float, hi: float) -> float:
    return lo if v < lo else (hi if v > hi else v)


def norm_hex(val: Any, fallback: str) -> str:
    m = HEX_RE.match(str(val or "").strip())
    return ("#" + m.group(1).lower()) if m else fallback


def hex_to_rgb(hx: str) -> Tuple[int, int, int]:
    s = hx.lstrip("#")
    return int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16)


def rgb_to_hex(r: float, g: float, b: float) -> str:
    return f"#{int(round(_clamp(r, 0, 255))):02x}{int(round(_clamp(g, 0, 255))):02x}{int(round(_clamp(b, 0, 255))):02x}"


def hex_to_qargb(hx: str, alpha: float = 1.0) -> str:
    a = int(round(_clamp(alpha, 0.0, 1.0) * 255))
    return f"#{a:02x}{hx.lstrip('#').lower()}"


def hex_to_kde_rgb(hx: str) -> str:
    r, g, b = hex_to_rgb(hx)
    return f"{r},{g},{b}"


def blend_hex(fg_hex: str, bg_hex: str, alpha: float) -> str:
    a = _clamp(alpha, 0.0, 1.0)
    r1, g1, b1 = hex_to_rgb(fg_hex)
    r2, g2, b2 = hex_to_rgb(bg_hex)
    return rgb_to_hex(
        r1 * a + r2 * (1.0 - a),
        g1 * a + g2 * (1.0 - a),
        b1 * a + b2 * (1.0 - a),
    )


def _srgb_lin(u: int) -> float:
    c = _clamp(u / 255.0, 0.0, 1.0)
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def rel_luminance(hx: str) -> float:
    r, g, b = hex_to_rgb(hx)
    return 0.2126 * _srgb_lin(r) + 0.7152 * _srgb_lin(g) + 0.0722 * _srgb_lin(b)


def wcag_contrast(hx1: str, hx2: str) -> float:
    y1, y2 = rel_luminance(hx1), rel_luminance(hx2)
    hi, lo = (y1, y2) if y1 >= y2 else (y2, y1)
    return (hi + 0.05) / (lo + 0.05)


def ensure_contrast(fg: str, bg: str, toward: str, min_ratio: float = 4.5) -> str:
    if wcag_contrast(fg, bg) >= min_ratio:
        return fg
    for step in range(1, 21):
        cand = blend_hex(toward, fg, step / 20.0)
        if wcag_contrast(cand, bg) >= min_ratio:
            return cand
    return toward if wcag_contrast(toward, bg) > wcag_contrast(fg, bg) else fg


def nearest_gnome_accent(hx: str) -> str:
    r, g, b = hex_to_rgb(hx)
    h, s, _ = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
    if s < 0.14:
        return "slate"
    deg = (h * 360.0) % 360.0
    if deg < 15.0 or deg >= 342.0:
        return "red"
    if deg < 40.0:
        return "orange"
    if deg < 68.0:
        return "yellow"
    if deg < 155.0:
        return "green"
    if deg < 192.0:
        return "teal"
    if deg < 252.0:
        return "blue"
    if deg < 305.0:
        return "purple"
    return "pink"


def build_tokens(raw: Dict[str, Any]) -> Dict[str, Any]:
    defaults = PRESETS["OLED Pure"]
    pill = norm_hex(raw.get("pillBg"), defaults["pillBg"])
    surf = norm_hex(raw.get("surfaceBg"), defaults["surfaceBg"])
    raised = norm_hex(raw.get("surfaceRaised"), defaults["surfaceRaised"])
    text = norm_hex(raw.get("text"), defaults["text"])
    border_base = norm_hex(raw.get("borderColor"), text)
    accent = norm_hex(raw.get("accent"), defaults["accent"])
    accent2 = norm_hex(raw.get("accent2"), accent)

    raw_fg = norm_hex(raw.get("accentFg"), "")
    if raw_fg and wcag_contrast(raw_fg, accent) >= 4.5:
        accent_fg = raw_fg
    else:
        accent_fg = "#000000" if wcag_contrast("#000000", accent) >= wcag_contrast("#ffffff", accent) else "#ffffff"

    border_alpha = _clamp(float(raw.get("borderAlpha", 0.14) or 0.14), 0.08, 0.60)
    card_alpha = _clamp(float(raw.get("cardAlpha", 0.09) or 0.09), 0.04, 0.30)
    hover_alpha = _clamp(float(raw.get("hoverAlpha", 0.15) or 0.15), 0.06, 0.35)

    ok = norm_hex(raw.get("ok"), "#30d158")
    info = norm_hex(raw.get("info"), "#0a84ff")
    warn = norm_hex(raw.get("warn"), "#ff9f0a")
    danger = norm_hex(raw.get("danger"), "#ff453a")
    danger_text = norm_hex(raw.get("dangerText"), "#ff6961")

    is_dark = rel_luminance(surf) < 0.45
    backdrop = blend_hex(pill, surf, 0.50)
    surface_alt = blend_hex(raised, surf, 0.55)
    surface_disabled = blend_hex(surf, pill, 0.40) if is_dark else blend_hex(pill, surf, 0.25)

    text_sub = blend_hex(text, surf, 0.62)
    text_muted = blend_hex(text, surf, 0.45)
    text_disabled = blend_hex(text, surf, 0.36)

    card_solid = blend_hex(text, surf, card_alpha)
    hover_solid = blend_hex(text, surf, hover_alpha)
    border_solid = blend_hex(border_base, surf, max(border_alpha, 0.14))
    border_strong = blend_hex(border_base, surf, min(0.38, max(border_alpha, 0.14) * 2.0))

    bevel_light = blend_hex(border_base, raised, 0.24)
    bevel_midlight = blend_hex(border_base, raised, 0.14)
    bevel_mid = blend_hex(pill, raised, 0.45) if is_dark else blend_hex("#000000", raised, 0.10)
    bevel_dark = pill if is_dark else blend_hex("#000000", raised, 0.18)

    accent_standalone = ensure_contrast(accent, surf, text, 4.5)
    accent2_standalone = ensure_contrast(accent2, surf, text, 4.5)
    accent_hover = blend_hex(text if is_dark else "#000000", accent, 0.12)
    accent_inactive = blend_hex(raised, accent, 0.38)
    selection_alt = blend_hex(surf, accent, 0.30)

    ok_fg = "#000000" if wcag_contrast("#000000", ok) >= wcag_contrast("#ffffff", ok) else "#ffffff"
    warn_fg = "#000000" if wcag_contrast("#000000", warn) >= wcag_contrast("#ffffff", warn) else "#ffffff"
    danger_fg = "#000000" if wcag_contrast("#000000", danger) >= wcag_contrast("#ffffff", danger) else "#ffffff"

    ok_standalone = ensure_contrast(ok, surf, text, 4.5)
    warn_standalone = ensure_contrast(warn, surf, text, 4.5)
    danger_standalone = ensure_contrast(danger_text if is_dark else danger, surf, text, 4.5)

    r_txt, g_txt, b_txt = hex_to_rgb(text)
    r_bdr, g_bdr, b_bdr = hex_to_rgb(border_base)

    return {
        "is_dark": is_dark,
        "pill_bg": pill,
        "surface_bg": surf,
        "surface_raised": raised,
        "surface_alt": surface_alt,
        "surface_disabled": surface_disabled,
        "backdrop_bg": backdrop,
        "text": text,
        "text_sub": text_sub,
        "text_muted": text_muted,
        "text_disabled": text_disabled,
        "border_base": border_base,
        "border_solid": border_solid,
        "border_strong": border_strong,
        "border_alpha": border_alpha,
        "border_rgba": f"rgba({r_bdr}, {g_bdr}, {b_bdr}, {border_alpha:.3f})",
        "card_solid": card_solid,
        "card_rgba": f"rgba({r_txt}, {g_txt}, {b_txt}, {card_alpha:.3f})",
        "hover_solid": hover_solid,
        "shade_rgba": "rgba(0, 0, 0, 0.36)" if is_dark else "rgba(0, 0, 0, 0.08)",
        "shade_soft_rgba": "rgba(0, 0, 0, 0.24)" if is_dark else "rgba(0, 0, 0, 0.06)",
        "bevel_light": bevel_light,
        "bevel_midlight": bevel_midlight,
        "bevel_mid": bevel_mid,
        "bevel_dark": bevel_dark,
        "accent": accent,
        "accent2": accent2,
        "accent_fg": accent_fg,
        "accent_hover": accent_hover,
        "accent_inactive": accent_inactive,
        "selection_alt": selection_alt,
        "accent_standalone": accent_standalone,
        "accent2_standalone": accent2_standalone,
        "ok": ok,
        "ok_fg": ok_fg,
        "ok_standalone": ok_standalone,
        "info": info,
        "warn": warn,
        "warn_fg": warn_fg,
        "warn_standalone": warn_standalone,
        "danger": danger,
        "danger_fg": danger_fg,
        "danger_standalone": danger_standalone,
        "gnome_accent": nearest_gnome_accent(accent),
    }


def _write_atomic(path: str, content: str) -> None:
    parent = os.path.dirname(os.path.abspath(path))
    os.makedirs(parent, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".paithosh-sync-", dir=parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(content)
            f.flush()
            os.fsync(f.fileno())
        os.chmod(tmp, 0o644)
        os.replace(tmp, path)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def atomic_write_text(path: str, content: str) -> bool:
    """Write atomically; returns True if file contents changed or did not exist."""
    try:
        with open(path, "r", encoding="utf-8") as f:
            if f.read() == content:
                return False
    except OSError:
        pass
    _write_atomic(path, content)
    return True


def force_atomic_write_text(path: str, content: str) -> None:
    """Always replace target atomically (triggers directoryChanged/fileChanged watchers)."""
    _write_atomic(path, content)


def update_ini_sections(
    path: str,
    section_updates: Dict[str, Dict[str, str]],
    default_if_missing: Optional[Dict[str, Dict[str, str]]] = None,
    create_if_missing: bool = True,
    force_rewrite: bool = False,
) -> bool:
    """Case-preserving line-based INI section updater supporting nested brackets like [Colors:Header][Inactive]."""
    existed = os.path.exists(path)
    if not existed:
        if not create_if_missing:
            return False
        lines: List[str] = []
    else:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            lines = f.readlines()

    # Apply defaults for keys only when they don't already exist
    merged: Dict[str, Dict[str, str]] = {sec: dict(vals) for sec, vals in section_updates.items()}
    any_sec_re = re.compile(r"^\s*\[.+\]\s*$")

    def _apply_section(cur_lines: List[str], sec: str, updates: Dict[str, str], only_if_absent: bool) -> List[str]:
        sec_re = re.compile(r"^\s*" + re.escape(f"[{sec}]") + r"\s*(#.*)?$")
        sec_start: Optional[int] = None
        sec_end = len(cur_lines)
        for i, ln in enumerate(cur_lines):
            if sec_start is None:
                if sec_re.match(ln):
                    sec_start = i
            elif any_sec_re.match(ln):
                sec_end = i
                break

        if sec_start is None:
            if cur_lines and not cur_lines[-1].endswith("\n"):
                cur_lines[-1] += "\n"
            if cur_lines and cur_lines[-1].strip():
                cur_lines.append("\n")
            cur_lines.append(f"[{sec}]\n")
            for k, v in updates.items():
                cur_lines.append(f"{k}={v}\n")
            return cur_lines

        remaining = dict(updates)
        for i in range(sec_start + 1, sec_end):
            stripped = cur_lines[i].strip()
            if not stripped or stripped.startswith("#") or stripped.startswith(";") or "=" not in stripped:
                continue
            key = stripped.split("=", 1)[0].strip()
            val = stripped.split("=", 1)[1].strip()
            if key in remaining:
                if only_if_absent and val != "":
                    remaining.pop(key)
                else:
                    cur_lines[i] = f"{key}={remaining.pop(key)}\n"
        if remaining:
            ins = sec_end
            while ins > sec_start + 1 and not cur_lines[ins - 1].strip():
                ins -= 1
            if ins > 0 and not cur_lines[ins - 1].endswith("\n"):
                cur_lines[ins - 1] += "\n"
            for k, v in remaining.items():
                cur_lines.insert(ins, f"{k}={v}\n")
                ins += 1
        return cur_lines

    if default_if_missing:
        for sec, defs in default_if_missing.items():
            lines = _apply_section(lines, sec, defs, only_if_absent=True)

    for sec, updates in merged.items():
        lines = _apply_section(lines, sec, updates, only_if_absent=False)

    new_txt = "".join(lines)
    if force_rewrite:
        force_atomic_write_text(path, new_txt)
        return True
    return atomic_write_text(path, new_txt)


def _gtk_define_colors(t: Dict[str, Any]) -> List[str]:
    return [
        "/* Auto-generated by Paithosh Theme Sync — do not edit manually */",
        f"@define-color accent_bg_color {t['accent']};",
        f"@define-color accent_fg_color {t['accent_fg']};",
        f"@define-color accent_color {t['accent_standalone']};",
        f"@define-color window_bg_color {t['surface_bg']};",
        f"@define-color window_fg_color {t['text']};",
        f"@define-color view_bg_color {t['surface_bg']};",
        f"@define-color view_fg_color {t['text']};",
        f"@define-color headerbar_bg_color {t['pill_bg']};",
        f"@define-color headerbar_fg_color {t['text']};",
        f"@define-color headerbar_border_color {t['border_base']};",
        f"@define-color headerbar_backdrop_color {t['backdrop_bg']};",
        f"@define-color headerbar_shade_color {t['shade_rgba']};",
        f"@define-color headerbar_darker_shade_color {t['shade_rgba']};",
        f"@define-color sidebar_bg_color {t['pill_bg']};",
        f"@define-color sidebar_fg_color {t['text']};",
        f"@define-color sidebar_backdrop_color {t['backdrop_bg']};",
        f"@define-color sidebar_border_color {t['border_rgba']};",
        f"@define-color sidebar_shade_color {t['shade_soft_rgba']};",
        f"@define-color secondary_sidebar_bg_color {t['surface_raised']};",
        f"@define-color secondary_sidebar_fg_color {t['text']};",
        f"@define-color secondary_sidebar_backdrop_color {t['surface_bg']};",
        f"@define-color secondary_sidebar_border_color {t['border_rgba']};",
        f"@define-color secondary_sidebar_shade_color {t['shade_soft_rgba']};",
        f"@define-color card_bg_color {t['card_rgba']};",
        f"@define-color card_fg_color {t['text']};",
        f"@define-color card_shade_color {t['shade_soft_rgba']};",
        f"@define-color dialog_bg_color {t['surface_raised']};",
        f"@define-color dialog_fg_color {t['text']};",
        f"@define-color popover_bg_color {t['surface_raised']};",
        f"@define-color popover_fg_color {t['text']};",
        f"@define-color popover_shade_color {t['shade_soft_rgba']};",
        f"@define-color thumbnail_bg_color {t['surface_raised']};",
        f"@define-color thumbnail_fg_color {t['text']};",
        f"@define-color shade_color {t['shade_soft_rgba']};",
        f"@define-color scrollbar_outline_color {t['border_rgba']};",
        f"@define-color destructive_bg_color {t['danger']};",
        f"@define-color destructive_fg_color {t['danger_fg']};",
        f"@define-color destructive_color {t['danger_standalone']};",
        f"@define-color success_bg_color {t['ok']};",
        f"@define-color success_fg_color {t['ok_fg']};",
        f"@define-color success_color {t['ok_standalone']};",
        f"@define-color warning_bg_color {t['warn']};",
        f"@define-color warning_fg_color {t['warn_fg']};",
        f"@define-color warning_color {t['warn_standalone']};",
        f"@define-color error_bg_color {t['danger']};",
        f"@define-color error_fg_color {t['danger_fg']};",
        f"@define-color error_color {t['danger_standalone']};",
        f"@define-color theme_fg_color {t['text']};",
        f"@define-color theme_text_color {t['text']};",
        f"@define-color theme_bg_color {t['surface_bg']};",
        f"@define-color theme_base_color {t['surface_bg']};",
        f"@define-color theme_selected_bg_color {t['accent']};",
        f"@define-color theme_selected_fg_color {t['accent_fg']};",
        f"@define-color theme_unfocused_fg_color {t['text_sub']};",
        f"@define-color theme_unfocused_text_color {t['text_sub']};",
        f"@define-color theme_unfocused_bg_color {t['backdrop_bg']};",
        f"@define-color theme_unfocused_base_color {t['surface_bg']};",
        f"@define-color theme_unfocused_selected_bg_color {t['accent_inactive']};",
        f"@define-color theme_unfocused_selected_fg_color {t['text']};",
        f"@define-color insensitive_bg_color {t['surface_disabled']};",
        f"@define-color insensitive_fg_color {t['text_disabled']};",
        f"@define-color insensitive_base_color {t['surface_disabled']};",
        f"@define-color borders {t['border_solid']};",
        f"@define-color unfocused_borders {t['border_solid']};",
        f"@define-color content_view_bg {t['surface_bg']};",
        f"@define-color link_color {t['accent_standalone']};",
        f"@define-color link_visited_color {t['accent2_standalone']};",
    ]


def _breeze_gtk_define_colors(t: Dict[str, Any]) -> List[str]:
    return [
        f"@define-color theme_fg_color_breeze {t['text']};",
        f"@define-color theme_text_color_breeze {t['text']};",
        f"@define-color theme_bg_color_breeze {t['surface_bg']};",
        f"@define-color theme_base_color_breeze {t['surface_bg']};",
        f"@define-color content_view_bg_breeze {t['surface_bg']};",
        f"@define-color theme_selected_bg_color_breeze {t['accent']};",
        f"@define-color theme_selected_fg_color_breeze {t['accent_fg']};",
        f"@define-color theme_hovering_selected_bg_color_breeze {t['accent_hover']};",
        f"@define-color theme_view_active_decoration_color_breeze {t['accent']};",
        f"@define-color theme_view_hover_decoration_color_breeze {t['accent_hover']};",
        f"@define-color theme_button_background_normal_breeze {t['surface_raised']};",
        f"@define-color theme_button_background_backdrop_breeze {t['surface_raised']};",
        f"@define-color theme_button_background_insensitive_breeze {t['surface_disabled']};",
        f"@define-color theme_button_background_backdrop_insensitive_breeze {t['surface_disabled']};",
        f"@define-color theme_button_foreground_normal_breeze {t['text']};",
        f"@define-color theme_button_foreground_active_breeze {t['accent_fg']};",
        f"@define-color theme_button_foreground_insensitive_breeze {t['text_disabled']};",
        f"@define-color theme_button_decoration_focus_breeze {t['accent']};",
        f"@define-color theme_button_decoration_hover_breeze {t['accent_hover']};",
        f"@define-color theme_header_background_breeze {t['pill_bg']};",
        f"@define-color theme_header_background_light_breeze {t['pill_bg']};",
        f"@define-color theme_header_background_backdrop_breeze {t['backdrop_bg']};",
        f"@define-color theme_header_foreground_breeze {t['text']};",
        f"@define-color theme_header_foreground_backdrop_breeze {t['text_sub']};",
        f"@define-color theme_titlebar_background_breeze {t['pill_bg']};",
        f"@define-color theme_titlebar_background_light_breeze {t['pill_bg']};",
        f"@define-color theme_titlebar_background_backdrop_breeze {t['backdrop_bg']};",
        f"@define-color theme_titlebar_foreground_breeze {t['text']};",
        f"@define-color theme_titlebar_foreground_backdrop_breeze {t['text_sub']};",
        f"@define-color borders_breeze {t['border_solid']};",
        f"@define-color insensitive_borders_breeze {t['border_solid']};",
        f"@define-color insensitive_bg_color_breeze {t['surface_disabled']};",
        f"@define-color insensitive_base_color_breeze {t['surface_disabled']};",
        f"@define-color insensitive_fg_color_breeze {t['text_disabled']};",
        f"@define-color insensitive_base_fg_color_breeze {t['text_disabled']};",
        f"@define-color theme_unfocused_fg_color_breeze {t['text_sub']};",
        f"@define-color theme_unfocused_text_color_breeze {t['text_sub']};",
        f"@define-color theme_unfocused_bg_color_breeze {t['backdrop_bg']};",
        f"@define-color theme_unfocused_base_color_breeze {t['surface_bg']};",
        f"@define-color theme_unfocused_selected_bg_color_breeze {t['accent_inactive']};",
        f"@define-color theme_unfocused_selected_fg_color_breeze {t['text']};",
        f"@define-color tooltip_background_breeze {t['surface_raised']};",
        f"@define-color tooltip_text_breeze {t['text']};",
        f"@define-color link_color_breeze {t['accent_standalone']};",
        f"@define-color link_visited_color_breeze {t['accent2_standalone']};",
        f"@define-color success_color_breeze {t['ok_standalone']};",
        f"@define-color warning_color_breeze {t['warn_standalone']};",
        f"@define-color error_color_breeze {t['danger_standalone']};",
    ]


def render_gtk3_css(t: Dict[str, Any]) -> str:
    # GTK3 strictly accepts @define-color (never :root { --* })
    lines = _gtk_define_colors(t) + _breeze_gtk_define_colors(t)
    lines.extend([
        "",
        "button.suggested-action:not(.flat),",
        "button.suggested-action:not(.flat):hover,",
        "button.suggested-action:not(.flat):active,",
        "button.suggested-action:not(.flat):checked {",
        "  color: @accent_fg_color;",
        "}",
        "switch:checked > slider {",
        "  background-color: @accent_fg_color;",
        "}",
    ])
    return "\n".join(lines) + "\n"


def render_gtk4_css(t: Dict[str, Any]) -> str:
    lines = _gtk_define_colors(t) + _breeze_gtk_define_colors(t)
    lines.extend([
        "",
        ":root {",
        f"  --accent-bg-color: {t['accent']};",
        f"  --accent-fg-color: {t['accent_fg']};",
        f"  --accent-color: {t['accent_standalone']};",
        f"  --window-bg-color: {t['surface_bg']};",
        f"  --window-fg-color: {t['text']};",
        f"  --view-bg-color: {t['surface_bg']};",
        f"  --view-fg-color: {t['text']};",
        f"  --headerbar-bg-color: {t['pill_bg']};",
        f"  --headerbar-fg-color: {t['text']};",
        f"  --headerbar-backdrop-color: {t['backdrop_bg']};",
        f"  --headerbar-border-color: {t['border_base']};",
        f"  --headerbar-shade-color: {t['shade_rgba']};",
        f"  --headerbar-darker-shade-color: {t['shade_rgba']};",
        f"  --sidebar-bg-color: {t['pill_bg']};",
        f"  --sidebar-fg-color: {t['text']};",
        f"  --sidebar-backdrop-color: {t['backdrop_bg']};",
        f"  --sidebar-border-color: {t['border_rgba']};",
        f"  --sidebar-shade-color: {t['shade_soft_rgba']};",
        f"  --secondary-sidebar-bg-color: {t['surface_raised']};",
        f"  --secondary-sidebar-fg-color: {t['text']};",
        f"  --secondary-sidebar-backdrop-color: {t['surface_bg']};",
        f"  --secondary-sidebar-border-color: {t['border_rgba']};",
        f"  --secondary-sidebar-shade-color: {t['shade_soft_rgba']};",
        f"  --card-bg-color: {t['card_rgba']};",
        f"  --card-fg-color: {t['text']};",
        f"  --card-shade-color: {t['shade_soft_rgba']};",
        f"  --dialog-bg-color: {t['surface_raised']};",
        f"  --dialog-fg-color: {t['text']};",
        f"  --popover-bg-color: {t['surface_raised']};",
        f"  --popover-fg-color: {t['text']};",
        f"  --popover-shade-color: {t['shade_soft_rgba']};",
        f"  --thumbnail-bg-color: {t['surface_raised']};",
        f"  --thumbnail-fg-color: {t['text']};",
        f"  --overview-bg-color: {t['pill_bg']};",
        f"  --overview-fg-color: {t['text']};",
        f"  --destructive-bg-color: {t['danger']};",
        f"  --destructive-fg-color: {t['danger_fg']};",
        f"  --destructive-color: {t['danger_standalone']};",
        f"  --success-bg-color: {t['ok']};",
        f"  --success-fg-color: {t['ok_fg']};",
        f"  --success-color: {t['ok_standalone']};",
        f"  --warning-bg-color: {t['warn']};",
        f"  --warning-fg-color: {t['warn_fg']};",
        f"  --warning-color: {t['warn_standalone']};",
        f"  --error-bg-color: {t['danger']};",
        f"  --error-fg-color: {t['danger_fg']};",
        f"  --error-color: {t['danger_standalone']};",
        f"  --shade-color: {t['shade_soft_rgba']};",
        f"  --scrollbar-outline-color: {t['border_rgba']};",
        f"  --border-color: {t['border_rgba']};",
        "}",
        "switch:checked > slider {",
        "  background-color: var(--accent-fg-color);",
        "}",
    ])
    return "\n".join(lines) + "\n"


def ensure_gtk_css_import(gtk_css_path: str) -> None:
    """Ensure a single trailing @import url("paithosh.css"); while preserving all user CSS."""
    existing = ""
    if os.path.exists(gtk_css_path):
        with open(gtk_css_path, "r", encoding="utf-8", errors="replace") as f:
            existing = f.read()

    # Strip any previous paithosh-theme-sync import lines so ours stays last (highest priority)
    cleaned_lines = []
    for ln in existing.splitlines():
        s = ln.strip()
        if s == "/* paithosh-theme-sync */":
            continue
        if re.match(r'^@import\s+(?:url\(\s*)?["\']paithosh\.css["\'](?:\s*\))?\s*;\s*$', s):
            continue
        cleaned_lines.append(ln)

    while cleaned_lines and not cleaned_lines[-1].strip():
        cleaned_lines.pop()

    block = ['/* paithosh-theme-sync */', '@import url("paithosh.css");']
    out_lines = (cleaned_lines + [""] + block) if cleaned_lines else block
    atomic_write_text(gtk_css_path, "\n".join(out_lines) + "\n")


def resolve_adw_gtk3_theme(is_dark: bool, home_dir: str, data_home: str) -> str:
    preferred = ["adw-gtk3-dark", "adw-gtk3"] if is_dark else ["adw-gtk3", "adw-gtk3-dark"]
    bases = [
        os.path.join(data_home, "themes"),
        os.path.join(home_dir, ".themes"),
        "/usr/local/share/themes",
        "/usr/share/themes",
    ]
    for name in preferred:
        for base in bases:
            if os.path.isfile(os.path.join(base, name, "gtk-3.0", "gtk.css")):
                return name
    return ""


def render_qt_scheme(t: Dict[str, Any], include_accent_role: bool) -> str:
    # QPalette::ColorRole indices 0..21:
    # 0:WindowText, 1:Button, 2:Light, 3:Midlight, 4:Dark, 5:Mid, 6:Text,
    # 7:BrightText, 8:ButtonText, 9:Base, 10:Window, 11:Shadow, 12:Highlight,
    # 13:HighlightedText, 14:Link, 15:LinkVisited, 16:AlternateBase, 17:NoRole,
    # 18:ToolTipBase, 19:ToolTipText, 20:PlaceholderText, 21:Accent (Qt 6.6+)
    def _row(
        win_txt: str,
        btn: str,
        txt: str,
        btn_txt: str,
        base: str,
        win: str,
        hi: str,
        hi_txt: str,
        link: str,
        link_vis: str,
        alt_base: str,
        acc: str,
    ) -> str:
        cols = [
            hex_to_qargb(win_txt),
            hex_to_qargb(btn),
            hex_to_qargb(t["bevel_light"]),
            hex_to_qargb(t["bevel_midlight"]),
            hex_to_qargb(t["bevel_dark"]),
            hex_to_qargb(t["bevel_mid"]),
            hex_to_qargb(txt),
            hex_to_qargb(t["text"]),
            hex_to_qargb(btn_txt),
            hex_to_qargb(base),
            hex_to_qargb(win),
            hex_to_qargb(t["pill_bg"]),
            hex_to_qargb(hi),
            hex_to_qargb(hi_txt),
            hex_to_qargb(link),
            hex_to_qargb(link_vis),
            hex_to_qargb(alt_base),
            "#ff000000",
            hex_to_qargb(t["surface_raised"]),
            hex_to_qargb(t["text"]),
            hex_to_qargb(t["text_muted"], 0.55),
        ]
        if include_accent_role:
            cols.append(hex_to_qargb(acc))
        return ", ".join(cols)

    active = _row(
        t["text"],
        t["surface_raised"],
        t["text"],
        t["text"],
        t["surface_bg"],
        t["surface_bg"],
        t["accent"],
        t["accent_fg"],
        t["accent_standalone"],
        t["accent2_standalone"],
        t["surface_alt"],
        t["accent"],
    )
    disabled = _row(
        t["text_disabled"],
        t["surface_disabled"],
        t["text_disabled"],
        t["text_disabled"],
        t["surface_disabled"],
        t["surface_disabled"],
        t["surface_raised"],
        t["text_disabled"],
        t["text_muted"],
        t["text_muted"],
        t["surface_disabled"],
        t["accent_inactive"],
    )
    inactive = _row(
        t["text_sub"],
        t["surface_raised"],
        t["text_sub"],
        t["text_sub"],
        t["surface_bg"],
        t["backdrop_bg"],
        t["accent_inactive"],
        t["text"],
        t["accent_standalone"],
        t["accent2_standalone"],
        t["surface_alt"],
        t["accent_inactive"],
    )
    return (
        "[ColorScheme]\n"
        f"active_colors={active}\n"
        f"disabled_colors={disabled}\n"
        f"inactive_colors={inactive}\n"
    )


def build_kde_color_sections(t: Dict[str, Any]) -> Dict[str, Dict[str, str]]:
    c_pill = hex_to_kde_rgb(t["pill_bg"])
    c_surf = hex_to_kde_rgb(t["surface_bg"])
    c_raised = hex_to_kde_rgb(t["surface_raised"])
    c_alt = hex_to_kde_rgb(t["surface_alt"])
    c_back = hex_to_kde_rgb(t["backdrop_bg"])
    c_txt = hex_to_kde_rgb(t["text"])
    c_sub = hex_to_kde_rgb(t["text_sub"])
    c_muted = hex_to_kde_rgb(t["text_muted"])
    c_dis = hex_to_kde_rgb(t["text_disabled"])
    c_acc = hex_to_kde_rgb(t["accent"])
    c_acc_hov = hex_to_kde_rgb(t["accent_hover"])
    c_acc_fg = hex_to_kde_rgb(t["accent_fg"])
    c_acc_sa = hex_to_kde_rgb(t["accent_standalone"])
    c_acc2_sa = hex_to_kde_rgb(t["accent2_standalone"])
    c_sel_alt = hex_to_kde_rgb(t["selection_alt"])
    c_ok = hex_to_kde_rgb(t["ok_standalone"])
    c_warn = hex_to_kde_rgb(t["warn_standalone"])
    c_err = hex_to_kde_rgb(t["danger_standalone"])
    c_bdr = hex_to_kde_rgb(t["border_solid"])

    def _palette_block(bg_norm: str, bg_alt: str, fg_norm: str, deco: str) -> Dict[str, str]:
        return {
            "BackgroundAlternate": bg_alt,
            "BackgroundNormal": bg_norm,
            "DecorationFocus": deco,
            "DecorationHover": c_acc_hov,
            "ForegroundActive": c_acc_sa,
            "ForegroundInactive": c_muted,
            "ForegroundLink": c_acc_sa,
            "ForegroundNegative": c_err,
            "ForegroundNeutral": c_warn,
            "ForegroundNormal": fg_norm,
            "ForegroundPositive": c_ok,
            "ForegroundVisited": c_acc2_sa,
        }

    return {
        "ColorEffects:Disabled": {
            "ChangeSelectionColor": "",
            "Color": c_dis,
            "ColorAmount": "0",
            "ColorEffect": "0",
            "ContrastAmount": "0.65",
            "ContrastEffect": "1",
            "Enable": "",
            "IntensityAmount": "0.1",
            "IntensityEffect": "2",
        },
        "ColorEffects:Inactive": {
            "ChangeSelectionColor": "true",
            "Color": c_sub,
            "ColorAmount": "0.025",
            "ColorEffect": "2",
            "ContrastAmount": "0.1",
            "ContrastEffect": "2",
            "Enable": "false",
            "IntensityAmount": "0",
            "IntensityEffect": "0",
        },
        "Colors:Button": _palette_block(c_raised, c_alt, c_txt, c_acc),
        "Colors:Complementary": _palette_block(c_pill, c_raised, c_txt, c_acc),
        "Colors:Header": _palette_block(c_pill, c_raised, c_txt, c_acc),
        "Colors:Header][Inactive": _palette_block(c_back, c_surf, c_sub, c_acc),
        "Colors:Selection": {
            "BackgroundAlternate": c_sel_alt,
            "BackgroundNormal": c_acc,
            "DecorationFocus": c_acc,
            "DecorationHover": c_acc_hov,
            "ForegroundActive": c_acc_fg,
            "ForegroundInactive": c_acc_fg,
            "ForegroundLink": c_acc_fg,
            "ForegroundNegative": c_err,
            "ForegroundNeutral": c_warn,
            "ForegroundNormal": c_acc_fg,
            "ForegroundPositive": c_ok,
            "ForegroundVisited": c_acc_fg,
        },
        "Colors:Tooltip": _palette_block(c_raised, c_alt, c_txt, c_acc),
        "Colors:View": _palette_block(c_surf, c_alt, c_txt, c_acc),
        "Colors:Window": _palette_block(c_surf, c_raised, c_txt, c_acc),
        "WM": {
            "activeBackground": c_pill,
            "activeBlend": c_bdr,
            "activeForeground": c_txt,
            "inactiveBackground": c_back,
            "inactiveBlend": c_bdr,
            "inactiveForeground": c_muted,
        },
    }


def render_kde_colorscheme_file(sections: Dict[str, Dict[str, str]]) -> str:
    all_secs = {"General": {"Name": "Paithosh", "ColorScheme": "Paithosh"}}
    all_secs.update(sections)
    out: List[str] = []
    for sec, kv in all_secs.items():
        out.append(f"[{sec}]")
        for k, v in kv.items():
            out.append(f"{k}={v}")
        out.append("")
    return "\n".join(out)


def sync_hypr_env_lua(config_home: str) -> None:
    env_path = os.path.join(config_home, "hypr", "config", "env.lua")
    if not os.path.isfile(env_path):
        return
    lock_dir = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
    lock_path = os.path.join(lock_dir, f"paithosh-hypr-cfg-{os.getuid()}.lock")
    with open(lock_path, "w", encoding="utf-8") as lf:
        fcntl.flock(lf, fcntl.LOCK_EX)
        txt = open(env_path, "r", encoding="utf-8", errors="replace").read()
        pat = re.compile(r'hl\.env\(\s*["\']QT_QPA_PLATFORMTHEME["\']\s*,\s*["\'][^"\']*["\']\s*\)')
        if pat.search(txt):
            return
        sep = "" if (not txt or txt.endswith("\n")) else "\n"
        atomic_write_text(env_path, txt + f'{sep}hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")\n')


def sync_live_session(t: Dict[str, Any], gtk3_theme: str) -> None:
    if shutil.which("gsettings"):
        scheme = "prefer-dark" if t["is_dark"] else "prefer-light"
        subprocess.run(
            ["gsettings", "set", "org.gnome.desktop.interface", "color-scheme", scheme],
            capture_output=True,
            check=False,
        )
        if gtk3_theme:
            subprocess.run(
                ["gsettings", "set", "org.gnome.desktop.interface", "gtk-theme", gtk3_theme],
                capture_output=True,
                check=False,
            )
        keys = subprocess.run(
            ["gsettings", "list-keys", "org.gnome.desktop.interface"],
            capture_output=True,
            text=True,
            check=False,
        )
        if keys.returncode == 0 and "accent-color" in keys.stdout.splitlines():
            subprocess.run(
                ["gsettings", "set", "org.gnome.desktop.interface", "accent-color", t["gnome_accent"]],
                capture_output=True,
                check=False,
            )

    if os.environ.get("QT_QPA_PLATFORMTHEME") != "qt6ct":
        if shutil.which("dbus-update-activation-environment"):
            subprocess.run(
                ["dbus-update-activation-environment", "--systemd", "QT_QPA_PLATFORMTHEME=qt6ct"],
                capture_output=True,
                check=False,
            )
        if shutil.which("systemctl"):
            subprocess.run(
                ["systemctl", "--user", "set-environment", "QT_QPA_PLATFORMTHEME=qt6ct"],
                capture_output=True,
                check=False,
            )


def qt6ct_supports_kcolorscheme() -> bool:
    patterns = (
        "/usr/lib*/libqt6ct-common.so*",
        "/usr/lib/*/libqt6ct-common.so*",
        "/usr/lib*/qt6/plugins/platformthemes/libqt6ct.so",
        "/usr/lib/*/qt6/plugins/platformthemes/libqt6ct.so",
    )
    for pat in patterns:
        for path in glob.glob(pat):
            try:
                with open(path, "rb") as f:
                    if b"isKColorScheme" in f.read():
                        return True
            except OSError:
                pass
    return False


def apply_theme(raw_palette: Dict[str, Any], live: bool = True) -> Dict[str, Any]:
    home_dir = os.path.expanduser("~")
    config_home = os.environ.get("XDG_CONFIG_HOME") or os.path.join(home_dir, ".config")
    data_home = os.environ.get("XDG_DATA_HOME") or os.path.join(home_dir, ".local", "share")

    t = build_tokens(raw_palette)
    prefer_dark = "true" if t["is_dark"] else "false"
    gtk3_theme = resolve_adw_gtk3_theme(t["is_dark"], home_dir, data_home)

    # 1. GTK4 / Libadwaita
    gtk4_dir = os.path.join(config_home, "gtk-4.0")
    atomic_write_text(os.path.join(gtk4_dir, "paithosh.css"), render_gtk4_css(t))
    ensure_gtk_css_import(os.path.join(gtk4_dir, "gtk.css"))
    update_ini_sections(
        os.path.join(gtk4_dir, "settings.ini"),
        {"Settings": {"gtk-application-prefer-dark-theme": prefer_dark}},
        create_if_missing=True,
    )

    # 2. GTK3
    gtk3_dir = os.path.join(config_home, "gtk-3.0")
    atomic_write_text(os.path.join(gtk3_dir, "paithosh.css"), render_gtk3_css(t))
    ensure_gtk_css_import(os.path.join(gtk3_dir, "gtk.css"))
    gtk3_ini = {"gtk-application-prefer-dark-theme": prefer_dark}
    if gtk3_theme:
        gtk3_ini["gtk-theme-name"] = gtk3_theme
    update_ini_sections(
        os.path.join(gtk3_dir, "settings.ini"),
        {"Settings": gtk3_ini},
        create_if_missing=True,
    )

    # 3. KDE Frameworks / Kirigami / Breeze (.colors + kdeglobals)
    kde_sections = build_kde_color_sections(t)
    kde_scheme_txt = render_kde_colorscheme_file(kde_sections)
    kde_scheme_file = os.path.join(data_home, "color-schemes", "Paithosh.colors")
    kde_scheme_changed = atomic_write_text(kde_scheme_file, kde_scheme_txt)

    kde_updates = dict(kde_sections)
    kde_updates["General"] = {
        "ColorScheme": "Paithosh",
        "ColorSchemeHash": hashlib.sha1(kde_scheme_txt.encode("utf-8")).hexdigest(),
    }
    update_ini_sections(os.path.join(config_home, "kdeglobals"), kde_updates, create_if_missing=True)

    # 4. Qt6 & Qt5 (qt6ct / qt5ct)
    use_kcolorscheme_qt6 = qt6ct_supports_kcolorscheme()
    for ver, include_accent in (("qt6ct", True), ("qt5ct", False)):
        qdir = os.path.join(config_home, ver)
        conf_scheme_path = os.path.join(qdir, "colors", "paithosh.conf")
        conf_scheme_changed = atomic_write_text(conf_scheme_path, render_qt_scheme(t, include_accent))
        if ver == "qt6ct" and use_kcolorscheme_qt6:
            active_scheme_path = kde_scheme_file
            any_scheme_changed = kde_scheme_changed or conf_scheme_changed
        else:
            active_scheme_path = conf_scheme_path
            any_scheme_changed = conf_scheme_changed
        update_ini_sections(
            os.path.join(qdir, f"{ver}.conf"),
            {
                "Appearance": {
                    "color_scheme_path": active_scheme_path,
                    "custom_palette": "true",
                }
            },
            default_if_missing={"Appearance": {"style": "Fusion"}},
            create_if_missing=True,
            force_rewrite=any_scheme_changed,  # Trigger QFileSystemWatcher in running Qt apps
        )

    # 5. Hyprland env.lua & live portals/gsettings
    sync_hypr_env_lua(config_home)
    if live:
        sync_live_session(t, gtk3_theme)

    return t


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Sync Paithosh theme colors to GTK3/GTK4/Qt5/Qt6/KDE.")
    src = parser.add_mutually_exclusive_group(required=True)
    src.add_argument("--json", help="JSON palette payload from Theme.exportTargetRenderColors()")
    src.add_argument("--preset", help="Built-in Paithosh preset name")
    parser.add_argument("--no-live", action="store_true", help="Skip live gsettings/dbus/systemd calls")
    args = parser.parse_args(argv)

    if args.json:
        try:
            payload = json.loads(args.json)
            if not isinstance(payload, dict):
                raise ValueError("JSON payload must be an object")
        except Exception as exc:
            print(f"[paithosh-theme-sync] Invalid --json payload: {exc}", file=sys.stderr)
            return 2
    else:
        payload = PRESETS.get(args.preset, PRESETS["OLED Pure"])

    apply_theme(payload, live=not args.no_live)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
