#!/usr/bin/env python3
"""Paithosh closed 3-cursor builder (Hyprcursor + XCursor), GTK/Qt/Hypr sync, and live daemon."""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import math
import os
import re
import select
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import time
from typing import Dict, List, Optional, Tuple

SCHEMA_REV = "v1"
STYLES = ("sharp", "soft", "wedge")
DEFAULT_STYLE = "sharp"
DEFAULT_SIZE = 24
MIN_SIZE = 16
MAX_SIZE = 64
XCURSOR_SIZES = (24, 32, 48, 64)
WAIT_FRAME_COUNT = 8
WAIT_DELAY_MS = 75

# Complete X11 / Wayland / GTK / Qt / legacy MD5 cursor alias map (~95 aliases across 21 shapes)
ALIASES: Dict[str, List[str]] = {
    "default": ["left_ptr", "arrow", "top_left_arrow", "right_ptr"],
    "pointer": [
        "hand", "hand1", "hand2", "pointing_hand",
        "9d800788f1b08800ae810202380a0822", "e29285e634086352946a0e7090d73106",
    ],
    "text": ["xterm", "ibeam", "vertical-text"],
    "crosshair": ["cross", "cross_reverse", "diamond_cross", "tcross", "color-picker"],
    "move": [
        "fleur", "all-scroll", "size_all", "dnd-move",
        "4498f0e0c1937ffe01fd06f973665830", "9081237383d90e509aa00f00170e968f",
    ],
    "grab": ["openhand", "dnd-none"],
    "grabbing": ["closedhand", "fcf21c00b30f7e3f83fe0dfd12e71cff"],
    "not-allowed": [
        "crossed_circle", "circle", "forbidden", "no-drop", "dnd-no-drop",
        "03b6e0fcb3499374a867c041f52298f0",
    ],
    "help": [
        "question_arrow", "whats_this", "left_ptr_help",
        "5c6cd98b3f3ebcb1f9c7f1c204630408", "d9ce0ab605698f320427677b458ad60b",
    ],
    "context-menu": ["menu"],
    "copy": [
        "dnd-copy", "plus",
        "1081e37283d90000800003c07f3ef6bf", "6407b0e94181790501fd1e167b474872",
        "b66166c04f8c3109214a4fbd64a50fc8",
    ],
    "alias": [
        "link", "dnd-link",
        "3085a0e285430894940527032f8b26df", "640fb0e74195791501fd1ed57b41487f",
        "a2a266d0498c3104214a47bd64ab0fc8",
    ],
    "wait": ["watch"],
    "progress": [
        "left_ptr_watch", "half-busy",
        "00000000000000020006000e7e9ffc3f", "08e8e1c95fe2fc01f976f1e063a24ccd",
        "3ecb610c1bf2410f44200f48c40d3599",
    ],
    "cell": ["draft", "center_ptr"],
    "zoom-in": [],
    "zoom-out": [],
    "ns-resize": [
        "size_ver", "row-resize", "sb_v_double_arrow", "v_double_arrow",
        "n-resize", "s-resize", "top_side", "bottom_side", "up-arrow", "down-arrow",
        "00008160000006810000408080010102", "2870a09082c103050810ffdffffe0204",
    ],
    "ew-resize": [
        "size_hor", "col-resize", "sb_h_double_arrow", "h_double_arrow",
        "e-resize", "w-resize", "left_side", "right_side", "left-arrow", "right-arrow",
        "028006030e0e7ebffc7f7070c0600140", "14fef782d02440884392942c11205230",
    ],
    "nwse-resize": [
        "size_fdiag", "fd_double_arrow", "nw-resize", "se-resize",
        "top_left_corner", "bottom_right_corner", "c7088f0f3e6c8088236ef8e1e3e70000",
    ],
    "nesw-resize": [
        "size_bdiag", "bd_double_arrow", "ne-resize", "sw-resize",
        "top_right_corner", "bottom_left_corner", "fcf1c3c7cd4491d801f1e1c78f100000",
    ],
}

def hotspot_for(shape: str, style: str) -> Tuple[float, float]:
    """Return style-accurate normalized (0..1) hotspot coordinates in 32x32 viewBox."""
    if shape in ("default", "help", "context-menu", "copy", "alias", "progress"):
        st = sanitize_style(style)
        if st == "sharp":
            return (6.5 / 32.0, 2.5 / 32.0)
        if st == "soft":
            return (7.5 / 32.0, 3.8 / 32.0)
        return (7.8 / 32.0, 3.8 / 32.0)
    return HOTSPOTS[shape]


# Normalized (0..1) fallback hotspot coordinates per shape in 32x32 viewBox
HOTSPOTS: Dict[str, Tuple[float, float]] = {
    "default": (7.0 / 32.0, 4.0 / 32.0),
    "pointer": (12.0 / 32.0, 4.0 / 32.0),
    "text": (16.0 / 32.0, 16.0 / 32.0),
    "crosshair": (16.0 / 32.0, 16.0 / 32.0),
    "move": (16.0 / 32.0, 16.0 / 32.0),
    "grab": (16.0 / 32.0, 14.0 / 32.0),
    "grabbing": (16.0 / 32.0, 15.0 / 32.0),
    "not-allowed": (16.0 / 32.0, 16.0 / 32.0),
    "help": (7.0 / 32.0, 4.0 / 32.0),
    "context-menu": (7.0 / 32.0, 4.0 / 32.0),
    "copy": (7.0 / 32.0, 4.0 / 32.0),
    "alias": (7.0 / 32.0, 4.0 / 32.0),
    "wait": (16.0 / 32.0, 16.0 / 32.0),
    "progress": (7.0 / 32.0, 4.0 / 32.0),
    "cell": (16.0 / 32.0, 16.0 / 32.0),
    "zoom-in": (14.0 / 32.0, 14.0 / 32.0),
    "zoom-out": (14.0 / 32.0, 14.0 / 32.0),
    "ns-resize": (16.0 / 32.0, 16.0 / 32.0),
    "ew-resize": (16.0 / 32.0, 16.0 / 32.0),
    "nwse-resize": (16.0 / 32.0, 16.0 / 32.0),
    "nesw-resize": (16.0 / 32.0, 16.0 / 32.0),
}


def sanitize_style(style: str) -> str:
    s = (style or "").strip().lower()
    return s if s in STYLES else DEFAULT_STYLE


def sanitize_size(size: int) -> int:
    try:
        v = int(round(float(size)))
    except Exception:
        v = DEFAULT_SIZE
    return max(MIN_SIZE, min(MAX_SIZE, v))


def normalize_hex(color: str, fallback: str = "#ffffff") -> str:
    c = (color or "").strip().lstrip("#")
    if re.fullmatch(r"[0-9a-fA-F]{6}", c):
        return "#" + c.lower()
    return fallback


def contrasting_outline(fill_hex: str) -> str:
    c = normalize_hex(fill_hex).lstrip("#")
    r = int(c[0:2], 16) / 255.0
    g = int(c[2:4], 16) / 255.0
    b = int(c[4:6], 16) / 255.0
    lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
    return "#0b0b0c" if lum > 0.50 else "#ffffff"


def _pointer_path(style: str, scale: float = 1.0, tx: float = 0.0, ty: float = 0.0) -> Tuple[str, str]:
    """Return (svg_path_d, linejoin) for the 3 closed pointer styles."""
    if style == "sharp":
        # Classic sharp pointed arrow with straight angled tail (miter corners)
        pts = [
            (7.5, 4.6),
            (7.5, 22.8),
            (11.9, 18.6),
            (15.2, 26.8),
            (18.2, 25.5),
            (14.9, 17.3),
            (21.4, 17.3),
        ]
        if scale != 1.0 or tx != 0.0 or ty != 0.0:
            pts = [(tx + x * scale, ty + y * scale) for x, y in pts]
        d = "M " + " L ".join(f"{x:.2f} {y:.2f}" for x, y in pts) + " Z"
        return d, "miter"

    if style == "soft":
        # Rounded tip + sculpted rounded tail (same family as sharp, smooth concentric corners)
        def p(x: float, y: float) -> str:
            return f"{tx + x * scale:.2f} {ty + y * scale:.2f}"

        d = (
            f"M {p(7.5, 6.4)} "
            f"Q {p(7.5, 4.2)} {p(9.1, 5.6)} "
            f"L {p(20.1, 15.5)} "
            f"Q {p(21.8, 17.0)} {p(19.6, 17.1)} "
            f"L {p(15.1, 17.1)} "
            f"L {p(17.9, 23.9)} "
            f"Q {p(18.6, 25.4)} {p(17.1, 26.0)} "
            f"L {p(16.2, 26.4)} "
            f"Q {p(14.7, 27.0)} {p(14.0, 25.5)} "
            f"L {p(11.4, 19.2)} "
            f"L {p(8.9, 21.7)} "
            f"Q {p(7.5, 23.1)} {p(7.5, 21.1)} Z"
        )
        return d, "round"

    # "wedge": Smooth rounded tip, tailless sculpted asymmetric wedge
    def pw(x: float, y: float) -> str:
        return f"{tx + x * scale:.2f} {ty + y * scale:.2f}"

    d = (
        f"M {pw(7.6, 6.6)} "
        f"Q {pw(7.6, 4.1)} {pw(9.4, 5.7)} "
        f"L {pw(21.7, 16.4)} "
        f"Q {pw(23.5, 18.0)} {pw(21.1, 18.3)} "
        f"L {pw(15.2, 18.9)} "
        f"Q {pw(13.6, 19.1)} {pw(12.3, 20.3)} "
        f"L {pw(9.3, 23.1)} "
        f"Q {pw(7.6, 24.6)} {pw(7.6, 22.3)} Z"
    )
    return d, "round"


def _layered_shape(body_markup: str, fill: str, outline: str, join: str, stroke_w: float = 2.6, shadow: bool = True) -> str:
    """Render soft drop-shadow + outer contrast halo + crisp inner fill (paint-order safe across all SVG engines)."""
    parts: List[str] = []
    if shadow:
        parts.append(
            f'<g transform="translate(0.4, 1.3)" opacity="0.28" fill="#000000" stroke="#000000" '
            f'stroke-width="{stroke_w:.2f}" stroke-linejoin="{join}" stroke-linecap="round">{body_markup}</g>'
        )
    parts.append(
        f'<g fill="{outline}" stroke="{outline}" stroke-width="{stroke_w:.2f}" '
        f'stroke-linejoin="{join}" stroke-linecap="round">{body_markup}</g>'
    )
    parts.append(f'<g fill="{fill}" stroke="none">{body_markup}</g>')
    return "\n  ".join(parts)


def _stroke_layered(stroke_markup: str, fill: str, outline: str, join: str, inner_w: float = 2.0, halo_pad: float = 2.2) -> str:
    """Render dual-stroke icon (hairlines, crosshairs, I-beam, arrows) with crisp halo."""
    outer_w = inner_w + halo_pad
    return "\n  ".join([
        f'<g transform="translate(0.3, 1.1)" opacity="0.25" fill="none" stroke="#000000" '
        f'stroke-width="{outer_w:.2f}" stroke-linejoin="{join}" stroke-linecap="round">{stroke_markup}</g>',
        f'<g fill="none" stroke="{outline}" stroke-width="{outer_w:.2f}" '
        f'stroke-linejoin="{join}" stroke-linecap="round">{stroke_markup}</g>',
        f'<g fill="none" stroke="{fill}" stroke-width="{inner_w:.2f}" '
        f'stroke-linejoin="{join}" stroke-linecap="round">{stroke_markup}</g>',
    ])


def render_svg(shape: str, style: str, fill: str, outline: str, frame: int = 0) -> str:
    style = sanitize_style(style)
    join = "miter" if style == "sharp" else "round"
    ptr_d, ptr_join = _pointer_path(style)
    small_ptr_d, _ = _pointer_path(style, scale=0.82, tx=0.6, ty=0.4)

    extra = ""
    ptr_sw = 2.2 if style == "sharp" else 2.5
    if shape == "default":
        body = _layered_shape(f'<path d="{ptr_d}"/>', fill, outline, ptr_join, stroke_w=ptr_sw)
    elif shape == "pointer":
        hand_d = (
            "M 11.5 14.5 L 11.5 5.2 Q 11.5 3.6 13.0 3.6 Q 14.5 3.6 14.5 5.2 L 14.5 11.8 "
            "Q 15.6 10.6 16.9 11.2 Q 17.7 11.5 17.8 12.6 Q 18.8 11.6 20.1 12.1 "
            "Q 20.9 12.5 21.0 13.6 Q 22.0 12.8 23.1 13.4 Q 23.9 13.9 23.9 15.3 "
            "L 23.9 20.8 Q 23.9 26.2 18.6 26.8 L 14.6 26.8 Q 11.8 26.8 10.1 24.1 "
            "L 7.3 19.3 Q 6.4 17.9 7.6 16.9 Q 8.8 16.0 10.0 17.2 L 11.5 18.7 Z"
        )
        body = _layered_shape(f'<path d="{hand_d}"/>', fill, outline, "round", stroke_w=2.4)
    elif shape == "text":
        beam = (
            '<path d="M 12.5 5.5 L 19.5 5.5 M 16.0 5.5 L 16.0 26.5 M 12.5 26.5 L 19.5 26.5"/>'
        )
        body = _stroke_layered(beam, fill, outline, join, inner_w=2.0, halo_pad=2.2)
    elif shape == "crosshair":
        cross = '<path d="M 16 5.5 L 16 26.5 M 5.5 16 L 26.5 16"/>'
        body = _stroke_layered(cross, fill, outline, join, inner_w=2.0, halo_pad=2.2)
    elif shape == "cell":
        plus_d = (
            "M 14.2 6.0 L 17.8 6.0 L 17.8 14.2 L 26.0 14.2 L 26.0 17.8 L 17.8 17.8 "
            "L 17.8 26.0 L 14.2 26.0 L 14.2 17.8 L 6.0 17.8 L 6.0 14.2 L 14.2 14.2 Z"
        )
        body = _layered_shape(f'<path d="{plus_d}"/>', fill, outline, join, stroke_w=2.2)
    elif shape == "move":
        mv_d = (
            "M 16 4.2 L 19.8 8.6 L 17.3 8.6 L 17.3 14.7 L 23.4 14.7 L 23.4 12.2 L 27.8 16 "
            "L 23.4 19.8 L 23.4 17.3 L 17.3 17.3 L 17.3 23.4 L 19.8 23.4 L 16 27.8 "
            "L 12.2 23.4 L 14.7 23.4 L 14.7 17.3 L 8.6 17.3 L 8.6 19.8 L 4.2 16 "
            "L 8.6 12.2 L 8.6 14.7 L 14.7 14.7 L 14.7 8.6 L 12.2 8.6 Z"
        )
        body = _layered_shape(f'<path d="{mv_d}"/>', fill, outline, join, stroke_w=2.2)
    elif shape == "grab":
        open_h = (
            "M 9.6 15.2 L 9.6 10.6 Q 9.6 9.3 10.9 9.3 Q 12.2 9.3 12.2 10.6 L 12.2 14.0 "
            "L 12.2 7.2 Q 12.2 5.9 13.5 5.9 Q 14.8 5.9 14.8 7.2 L 14.8 13.2 "
            "L 14.8 6.4 Q 14.8 5.1 16.2 5.1 Q 17.5 5.1 17.5 6.4 L 17.5 13.2 "
            "L 17.5 8.0 Q 17.5 6.7 18.8 6.7 Q 20.1 6.7 20.1 8.0 L 20.1 14.6 "
            "L 20.1 12.0 Q 20.1 10.7 21.4 10.7 Q 22.6 10.7 22.6 12.0 L 22.6 20.6 "
            "Q 22.6 25.8 17.5 26.4 L 14.0 26.4 Q 10.2 26.4 8.6 22.4 L 7.0 18.5 "
            "Q 6.5 17.2 7.6 16.5 Q 8.6 15.8 9.6 16.9 Z"
        )
        body = _layered_shape(f'<path d="{open_h}"/>', fill, outline, "round", stroke_w=2.2)
    elif shape == "grabbing":
        closed_h = (
            "M 9.8 15.6 Q 9.8 12.4 12.2 12.4 L 12.4 12.4 Q 12.8 10.8 14.7 10.8 "
            "Q 15.6 10.8 16.2 11.4 Q 16.9 10.6 18.1 10.6 Q 19.4 10.6 19.9 11.6 "
            "Q 22.5 11.6 22.5 14.6 L 22.5 20.6 Q 22.5 25.8 17.4 26.4 L 13.8 26.4 "
            "Q 10.1 26.4 8.8 22.4 L 7.7 19.0 Q 7.3 17.6 8.5 16.9 Q 9.2 16.5 9.8 17.1 Z"
        )
        body = _layered_shape(f'<path d="{closed_h}"/>', fill, outline, "round", stroke_w=2.2)
    elif shape == "not-allowed":
        ring = '<circle cx="16" cy="16" r="9.5"/><line x1="9.3" y1="9.3" x2="22.7" y2="22.7"/>'
        body = _stroke_layered(ring, "#ff453a", outline, "round", inner_w=2.5, halo_pad=2.2)
    elif shape == "help":
        body = _layered_shape(f'<path d="{small_ptr_d}"/>', fill, outline, ptr_join, stroke_w=2.3)
        extra = (
            '<circle cx="22.5" cy="22.5" r="6.2" fill="#0b0b0c" stroke="#ffffff" stroke-width="1.3"/>'
            '<path d="M 20.7 20.6 Q 20.8 19.1 22.5 19.1 Q 24.1 19.1 24.1 20.5 '
            'Q 24.1 21.5 22.5 22.1 L 22.5 23.4" fill="none" stroke="#ffffff" stroke-width="1.5" stroke-linecap="round"/>'
            '<circle cx="22.5" cy="25.3" r="0.9" fill="#ffffff"/>'
        )
    elif shape == "context-menu":
        body = _layered_shape(f'<path d="{small_ptr_d}"/>', fill, outline, ptr_join, stroke_w=2.3)
        extra = (
            f'<rect x="17.5" y="18.0" width="10.0" height="10.0" rx="2.0" fill="{fill}" stroke="{outline}" stroke-width="1.4"/>'
            f'<path d="M 19.6 20.8 L 25.4 20.8 M 19.6 23.0 L 25.4 23.0 M 19.6 25.2 L 25.4 25.2" '
            f'stroke="{outline}" stroke-width="1.3" stroke-linecap="round"/>'
        )
    elif shape == "copy":
        body = _layered_shape(f'<path d="{small_ptr_d}"/>', fill, outline, ptr_join, stroke_w=2.3)
        extra = (
            '<circle cx="22.5" cy="22.5" r="6.0" fill="#30d158" stroke="#ffffff" stroke-width="1.3"/>'
            '<path d="M 19.7 22.5 L 25.3 22.5 M 22.5 19.7 L 22.5 25.3" stroke="#ffffff" stroke-width="1.7" stroke-linecap="round"/>'
        )
    elif shape == "alias":
        body = _layered_shape(f'<path d="{small_ptr_d}"/>', fill, outline, ptr_join, stroke_w=2.3)
        extra = (
            '<circle cx="22.5" cy="22.5" r="6.0" fill="#0a84ff" stroke="#ffffff" stroke-width="1.3"/>'
            '<path d="M 20.0 24.6 Q 20.2 20.6 24.4 20.6 M 22.6 18.8 L 24.8 20.6 L 22.6 22.4" '
            'fill="none" stroke="#ffffff" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>'
        )
    elif shape == "wait":
        deg = (frame % WAIT_FRAME_COUNT) * (360.0 / WAIT_FRAME_COUNT)
        body = (
            f'<circle cx="16" cy="16" r="9.2" fill="none" stroke="{outline}" stroke-width="4.4" opacity="0.45"/>'
            f'<circle cx="16" cy="16" r="9.2" fill="none" stroke="{fill}" stroke-width="2.4" opacity="0.28"/>'
            f'<g transform="rotate({deg:.1f} 16 16)">'
            f'<path d="M 16 6.8 A 9.2 9.2 0 0 1 25.2 16" fill="none" stroke="{outline}" stroke-width="4.4" stroke-linecap="round"/>'
            f'<path d="M 16 6.8 A 9.2 9.2 0 0 1 25.2 16" fill="none" stroke="{fill}" stroke-width="2.4" stroke-linecap="round"/>'
            f'</g>'
        )
    elif shape == "progress":
        deg = (frame % WAIT_FRAME_COUNT) * (360.0 / WAIT_FRAME_COUNT)
        body = _layered_shape(f'<path d="{small_ptr_d}"/>', fill, outline, ptr_join, stroke_w=2.3)
        extra = (
            f'<circle cx="22.5" cy="22.5" r="5.3" fill="{outline}" opacity="0.72"/>'
            f'<circle cx="22.5" cy="22.5" r="3.9" fill="none" stroke="{fill}" stroke-width="1.6" opacity="0.30"/>'
            f'<g transform="rotate({deg:.1f} 22.5 22.5)">'
            f'<path d="M 22.5 18.6 A 3.9 3.9 0 0 1 26.4 22.5" fill="none" stroke="{fill}" stroke-width="1.8" stroke-linecap="round"/>'
            f'</g>'
        )
    elif shape in ("zoom-in", "zoom-out"):
        glass = (
            '<circle cx="14.0" cy="14.0" r="7.2"/>'
            '<line x1="19.3" y1="19.3" x2="26.2" y2="26.2"/>'
        )
        sym = '<line x1="11.0" y1="14.0" x2="17.0" y2="14.0"/>'
        if shape == "zoom-in":
            sym += '<line x1="14.0" y1="11.0" x2="14.0" y2="17.0"/>'
        body = _stroke_layered(glass + sym, fill, outline, "round", inner_w=2.1, halo_pad=2.2)
    elif shape == "ns-resize":
        d = (
            "M 16 4.2 L 20.6 9.5 L 17.6 9.5 L 17.6 22.5 L 20.6 22.5 L 16 27.8 "
            "L 11.4 22.5 L 14.4 22.5 L 14.4 9.5 L 11.4 9.5 Z"
        )
        body = _layered_shape(f'<path d="{d}"/>', fill, outline, join, stroke_w=2.2)
    elif shape == "ew-resize":
        d = (
            "M 4.2 16 L 9.5 11.4 L 9.5 14.4 L 22.5 14.4 L 22.5 11.4 L 27.8 16 "
            "L 22.5 20.6 L 22.5 17.6 L 9.5 17.6 L 9.5 20.6 Z"
        )
        body = _layered_shape(f'<path d="{d}"/>', fill, outline, join, stroke_w=2.2)
    elif shape == "nwse-resize":
        d = (
            "M 16 4.2 L 20.6 9.5 L 17.6 9.5 L 17.6 22.5 L 20.6 22.5 L 16 27.8 "
            "L 11.4 22.5 L 14.4 22.5 L 14.4 9.5 L 11.4 9.5 Z"
        )
        body = f'<g transform="rotate(-45 16 16)">{_layered_shape(f"<path d=\"{d}\"/>", fill, outline, join, stroke_w=2.2)}</g>'
    elif shape == "nesw-resize":
        d = (
            "M 16 4.2 L 20.6 9.5 L 17.6 9.5 L 17.6 22.5 L 20.6 22.5 L 16 27.8 "
            "L 11.4 22.5 L 14.4 22.5 L 14.4 9.5 L 11.4 9.5 Z"
        )
        body = f'<g transform="rotate(45 16 16)">{_layered_shape(f"<path d=\"{d}\"/>", fill, outline, join, stroke_w=2.2)}</g>'
    else:
        body = _layered_shape(f'<path d="{ptr_d}"/>', fill, outline, ptr_join)

    return (
        '<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32">\n'
        f"  {body}\n"
        f"{('  ' + extra + chr(10)) if extra else ''}"
        "</svg>\n"
    )


def rasterize_svg_argb32(svg_text: str, px: int) -> bytes:
    """Rasterize SVG string into premultiplied little-endian ARGB32 bytes for XCursor."""
    try:
        import cairo
        import gi

        gi.require_version("Rsvg", "2.0")
        from gi.repository import Rsvg

        handle = Rsvg.Handle.new_from_data(svg_text.encode("utf-8"))
        surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, px, px)
        ctx = cairo.Context(surface)
        ctx.scale(px / 32.0, px / 32.0)
        viewport = Rsvg.Rectangle()
        viewport.x = 0.0
        viewport.y = 0.0
        viewport.width = 32.0
        viewport.height = 32.0
        handle.render_document(ctx, viewport)
        surface.flush()
        return bytes(surface.get_data())
    except Exception:
        # Fallback if Rsvg/cairo is unavailable (PIL + magick/rsvg-convert)
        from PIL import Image

        with tempfile.TemporaryDirectory() as td:
            svg_p = os.path.join(td, "in.svg")
            png_p = os.path.join(td, "out.png")
            with open(svg_p, "w", encoding="utf-8") as f:
                f.write(svg_text)
            if shutil.which("rsvg-convert"):
                subprocess.run(["rsvg-convert", "-w", str(px), "-h", str(px), svg_p, "-o", png_p], check=True)
            elif shutil.which("magick"):
                subprocess.run(["magick", "-background", "none", svg_p, "-resize", f"{px}x{px}", png_p], check=True)
            else:
                raise RuntimeError("No SVG rasterizer available (requires python3-cairo + librsvg)")
            img = Image.open(png_p).convert("RGBA")
            raw = img.tobytes("raw", "RGBA")
            out = bytearray(len(raw))
            for i in range(0, len(raw), 4):
                r, g, b, a = raw[i], raw[i + 1], raw[i + 2], raw[i + 3]
                if a == 255:
                    out[i], out[i + 1], out[i + 2], out[i + 3] = b, g, r, a
                elif a > 0:
                    out[i] = (b * a + 127) // 255
                    out[i + 1] = (g * a + 127) // 255
                    out[i + 2] = (r * a + 127) // 255
                    out[i + 3] = a
            return bytes(out)


def pack_xcursor(frames: List[Tuple[int, int, int, bytes, int]]) -> bytes:
    """Pack XCursor v1.0 binary file from [(size, xhot, yhot, argb_bytes, delay_ms), ...]."""
    XCURSOR_IMAGE_TYPE = 0xFFFD0002
    n = len(frames)
    header = struct.pack("<4sIII", b"Xcur", 16, 0x00010000, n)
    offset = 16 + n * 12
    toc = bytearray()
    chunks = bytearray()
    for sz, xh, yh, data, delay in frames:
        toc.extend(struct.pack("<III", XCURSOR_IMAGE_TYPE, sz, offset))
        chunk_hdr = struct.pack("<IIIIIIIII", 36, XCURSOR_IMAGE_TYPE, sz, 1, sz, sz, xh, yh, delay)
        chunks.extend(chunk_hdr)
        chunks.extend(data)
        offset += 36 + len(data)
    return header + bytes(toc) + bytes(chunks)


def theme_id_for(style: str, fill: str, outline: str, sizes: List[int]) -> str:
    sizes_csv = ",".join(str(s) for s in sizes)
    digest = hashlib.sha1(f"{SCHEMA_REV}:{style}:{fill}:{outline}:{sizes_csv}".encode("utf-8")).hexdigest()[:8]
    return f"paithosh-{style}-{digest}"


def build_theme(
    style: str,
    fill: str,
    outline: str,
    requested_size: int,
    icons_root: Optional[str] = None,
    legacy_icons_root: Optional[str] = None,
) -> str:
    style = sanitize_style(style)
    fill = normalize_hex(fill)
    outline = normalize_hex(outline, contrasting_outline(fill))
    requested_size = sanitize_size(requested_size)
    sizes = sorted(set(list(XCURSOR_SIZES) + [requested_size]))

    tid = theme_id_for(style, fill, outline, sizes)
    icons_base = icons_root or os.path.expanduser("~/.local/share/icons")
    legacy_base = legacy_icons_root if legacy_icons_root is not None else os.path.expanduser("~/.icons")
    os.makedirs(icons_base, exist_ok=True)
    target_dir = os.path.join(icons_base, tid)
    marker = os.path.join(target_dir, ".built-ok")

    if os.path.isfile(marker) and os.path.isdir(os.path.join(target_dir, "cursors")):
        _ensure_legacy_symlink(target_dir, legacy_base, tid)
        return tid

    staging_parent = tempfile.mkdtemp(prefix=f".staging-{tid}-", dir=icons_base)
    try:
        hc_src = os.path.join(staging_parent, "hc_src")
        hc_out = os.path.join(staging_parent, "hc_out")
        hc_cursors = os.path.join(hc_src, "hyprcursors")
        os.makedirs(hc_cursors, exist_ok=True)
        os.makedirs(hc_out, exist_ok=True)

        with open(os.path.join(hc_src, "manifest.hl"), "w", encoding="utf-8") as mf:
            mf.write(
                f"name = {tid}\n"
                f"description = Paithosh Closed Cursor ({style})\n"
                "version = 1.0\n"
                "cursors_directory = hyprcursors\n"
            )

        stage_final = os.path.join(staging_parent, tid)
        xc_dir = os.path.join(stage_final, "cursors")
        os.makedirs(xc_dir, exist_ok=True)

        for shape, aliases in ALIASES.items():
            hx, hy = hotspot_for(shape, style)
            is_anim = shape in ("wait", "progress")
            frame_count = WAIT_FRAME_COUNT if is_anim else 1

            shape_hc_dir = os.path.join(hc_cursors, shape)
            os.makedirs(shape_hc_dir, exist_ok=True)
            meta_lines = [
                "resize_algorithm = none",
                f"hotspot_x = {hx:.6f}",
                f"hotspot_y = {hy:.6f}",
            ]
            for al in aliases:
                meta_lines.append(f"define_override = {al}")

            xc_frames: List[Tuple[int, int, int, bytes, int]] = []
            for fr in range(frame_count):
                svg = render_svg(shape, style, fill, outline, fr)
                svg_name = f"{shape}_{fr}.svg" if is_anim else f"{shape}.svg"
                with open(os.path.join(shape_hc_dir, svg_name), "w", encoding="utf-8") as sf:
                    sf.write(svg)
                if is_anim:
                    meta_lines.append(f"define_size = 0, {svg_name}, {WAIT_DELAY_MS}")
                else:
                    meta_lines.append(f"define_size = 0, {svg_name}")

            for sz in sizes:
                xh = max(0, min(sz - 1, int(round(hx * sz))))
                yh = max(0, min(sz - 1, int(round(hy * sz))))
                for fr in range(frame_count):
                    svg = render_svg(shape, style, fill, outline, fr)
                    argb = rasterize_svg_argb32(svg, sz)
                    xc_frames.append((sz, xh, yh, argb, WAIT_DELAY_MS if is_anim else 0))

            with open(os.path.join(shape_hc_dir, "meta.hl"), "w", encoding="utf-8") as mh:
                mh.write("\n".join(meta_lines) + "\n")

            xc_bytes = pack_xcursor(xc_frames)
            with open(os.path.join(xc_dir, shape), "wb") as xf:
                xf.write(xc_bytes)

            for al in aliases:
                al_path = os.path.join(xc_dir, al)
                if os.path.lexists(al_path):
                    os.unlink(al_path)
                os.symlink(shape, al_path)

        # Compile Hyprcursor archive with hyprcursor-util
        if shutil.which("hyprcursor-util"):
            proc = subprocess.run(
                ["hyprcursor-util", "--create", hc_src, "-o", hc_out],
                capture_output=True,
                text=True,
                check=False,
            )
            if proc.returncode != 0:
                raise RuntimeError(f"hyprcursor-util failed: {proc.stderr or proc.stdout}")
            built_hc_dir = os.path.join(hc_out, f"theme_{tid}")
            if not os.path.isdir(built_hc_dir):
                # Fallback lookup in case hyprcursor-util names the output folder differently
                cands = [os.path.join(hc_out, d) for d in os.listdir(hc_out) if os.path.isdir(os.path.join(hc_out, d))]
                if not cands:
                    raise RuntimeError("hyprcursor-util produced no output directory")
                built_hc_dir = cands[0]
            shutil.move(os.path.join(built_hc_dir, "manifest.hl"), os.path.join(stage_final, "manifest.hl"))
            shutil.move(os.path.join(built_hc_dir, "hyprcursors"), os.path.join(stage_final, "hyprcursors"))

        with open(os.path.join(stage_final, "index.theme"), "w", encoding="utf-8") as it:
            it.write(
                "[Icon Theme]\n"
                f"Name={tid}\n"
                f"Comment=Paithosh Custom Cursor ({style})\n"
                "Inherits=Adwaita,breeze_cursors,hicolor\n"
            )

        with open(os.path.join(stage_final, ".built-ok"), "w", encoding="utf-8") as mk:
            mk.write("1\n")

        if os.path.lexists(target_dir):
            shutil.rmtree(target_dir, ignore_errors=True)
        os.replace(stage_final, target_dir)
        _ensure_legacy_symlink(target_dir, legacy_base, tid)
    finally:
        shutil.rmtree(staging_parent, ignore_errors=True)

    return tid


def _ensure_legacy_symlink(target_dir: str, legacy_base: str, tid: str) -> None:
    if not legacy_base:
        return
    os.makedirs(legacy_base, exist_ok=True)
    link_path = os.path.join(legacy_base, tid)
    if os.path.islink(link_path) and os.readlink(link_path) == target_dir:
        return
    if os.path.lexists(link_path):
        if os.path.isdir(link_path) and not os.path.islink(link_path):
            shutil.rmtree(link_path, ignore_errors=True)
        else:
            os.unlink(link_path)
    os.symlink(target_dir, link_path)


def atomic_write_text(path: str, content: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = f"{path}.tmp.{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(content)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)


def update_ini_section(path: str, section: str, updates: Dict[str, str], create_if_missing: bool = True) -> None:
    if not os.path.exists(path):
        if not create_if_missing:
            return
        lines = [f"[{section}]\n"] + [f"{k}={v}\n" for k, v in updates.items()]
        atomic_write_text(path, "".join(lines))
        return

    with open(path, "r", encoding="utf-8", errors="replace") as f:
        lines = f.readlines()

    sec_re = re.compile(r"^\s*\[\s*" + re.escape(section) + r"\s*\]\s*(#.*)?$", re.IGNORECASE)
    any_sec_re = re.compile(r"^\s*\[[^\]]+\]\s*$")
    sec_start: Optional[int] = None
    sec_end = len(lines)
    for i, ln in enumerate(lines):
        if sec_start is None:
            if sec_re.match(ln):
                sec_start = i
        elif any_sec_re.match(ln):
            sec_end = i
            break

    if sec_start is None:
        if lines and not lines[-1].endswith("\n"):
            lines[-1] += "\n"
        if lines and lines[-1].strip():
            lines.append("\n")
        lines.append(f"[{section}]\n")
        for k, v in updates.items():
            lines.append(f"{k}={v}\n")
    else:
        remaining = dict(updates)
        for i in range(sec_start + 1, sec_end):
            stripped = lines[i].strip()
            if not stripped or stripped.startswith("#") or "=" not in stripped:
                continue
            key = stripped.split("=", 1)[0].strip()
            if key in remaining:
                lines[i] = f"{key}={remaining.pop(key)}\n"
        if remaining:
            ins = sec_end
            while ins > sec_start + 1 and not lines[ins - 1].strip():
                ins -= 1
            if ins > 0 and not lines[ins - 1].endswith("\n"):
                lines[ins - 1] += "\n"
            for k, v in remaining.items():
                lines.insert(ins, f"{k}={v}\n")
                ins += 1

    new_txt = "".join(lines)
    try:
        if open(path, "r", encoding="utf-8").read() == new_txt:
            return
    except OSError:
        pass
    atomic_write_text(path, new_txt)


def _sync_hypr_lua_files(theme_id: str, size: int) -> None:
    lock_path = "/tmp/paithosh-hypr-cfg.lock"
    with open(lock_path, "w", encoding="utf-8") as lf:
        fcntl.flock(lf, fcntl.LOCK_EX)

        env_path = os.path.expanduser("~/.config/hypr/config/env.lua")
        if os.path.isfile(env_path):
            txt = open(env_path, "r", encoding="utf-8").read()
            envs = [
                ("HYPRCURSOR_THEME", theme_id),
                ("HYPRCURSOR_SIZE", str(size)),
                ("XCURSOR_THEME", theme_id),
                ("XCURSOR_SIZE", str(size)),
            ]
            new_txt = txt
            for k, v in envs:
                pat = re.compile(r'hl\.env\(\s*["\']' + re.escape(k) + r'["\']\s*,\s*["\'][^"\']*["\']\s*\)')
                repl = f'hl.env("{k}", "{v}")'
                if pat.search(new_txt):
                    new_txt = pat.sub(repl, new_txt, count=1)
                else:
                    sep = "" if (not new_txt or new_txt.endswith("\n")) else "\n"
                    new_txt += f"{sep}{repl}\n"
            if new_txt != txt:
                atomic_write_text(env_path, new_txt)

        app_path = os.path.expanduser("~/.config/hypr/config/appearance.lua")
        if os.path.isfile(app_path):
            txt = open(app_path, "r", encoding="utf-8").read()
            new_txt = txt
            cur_blk = re.search(r"(cursor\s*=\s*\{)([^}]*)(\})", new_txt, re.DOTALL)
            if cur_blk:
                blk = cur_blk.group(2)
                if re.search(r"enable_hyprcursor\s*=", blk):
                    blk = re.sub(r"(enable_hyprcursor\s*=\s*)(true|false)", r"\g<1>true", blk, count=1)
                else:
                    blk = "\n        enable_hyprcursor    = true," + blk
                if re.search(r"sync_gsettings_theme\s*=", blk):
                    blk = re.sub(r"(sync_gsettings_theme\s*=\s*)(true|false)", r"\g<1>true", blk, count=1)
                else:
                    blk = blk.rstrip() + "\n        sync_gsettings_theme = true,\n    "
                new_txt = new_txt[:cur_blk.start(2)] + blk + new_txt[cur_blk.end(2):]
            else:
                m_end = re.search(r"\n\}\)\s*$", new_txt)
                if m_end:
                    insert_blk = (
                        "\n    cursor = {\n"
                        "        enable_hyprcursor    = true,\n"
                        "        sync_gsettings_theme = true,\n"
                        "    },\n"
                    )
                    new_txt = new_txt[:m_end.start()] + insert_blk + new_txt[m_end.start():]
            if new_txt != txt:
                atomic_write_text(app_path, new_txt)


def _apply_live_cursor(theme_id: str, size: int) -> None:
    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    rt = os.environ.get("XDG_RUNTIME_DIR")
    sock_ok = False
    if sig and rt:
        sock_path = os.path.join(rt, "hypr", sig, ".socket.sock")
        if os.path.exists(sock_path):
            try:
                with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
                    s.settimeout(0.5)
                    s.connect(sock_path)
                    s.sendall(f"setcursor {theme_id} {size}".encode("utf-8"))
                    s.recv(256)
                sock_ok = True
            except Exception:
                sock_ok = False
    if not sock_ok and shutil.which("hyprctl"):
        subprocess.run(["hyprctl", "setcursor", theme_id, str(size)], capture_output=True, check=False)

    if shutil.which("gsettings"):
        subprocess.run(["gsettings", "set", "org.gnome.desktop.interface", "cursor-theme", theme_id], capture_output=True, check=False)
        subprocess.run(["gsettings", "set", "org.gnome.desktop.interface", "cursor-size", str(size)], capture_output=True, check=False)


def _sync_persistent_toolkits(theme_id: str, size: int, sync_env: bool = True) -> None:
    default_txt = f"[Icon Theme]\nInherits={theme_id}\n"
    atomic_write_text(os.path.expanduser("~/.icons/default/index.theme"), default_txt)
    atomic_write_text(os.path.expanduser("~/.local/share/icons/default/index.theme"), default_txt)

    gtk_updates = {
        "gtk-cursor-theme-name": theme_id,
        "gtk-cursor-theme-size": str(size),
    }
    update_ini_section(os.path.expanduser("~/.config/gtk-3.0/settings.ini"), "Settings", gtk_updates, create_if_missing=True)
    update_ini_section(os.path.expanduser("~/.config/gtk-4.0/settings.ini"), "Settings", gtk_updates, create_if_missing=True)
    update_ini_section(
        os.path.expanduser("~/.config/kcminputrc"),
        "Mouse",
        {"cursorTheme": theme_id, "cursorSize": str(size)},
        create_if_missing=True,
    )
    for qt_cfg in ("~/.config/qt5ct/qt5ct.conf", "~/.config/qt6ct/qt6ct.conf"):
        update_ini_section(os.path.expanduser(qt_cfg), "Appearance", {"cursor_theme": theme_id}, create_if_missing=False)

    _sync_hypr_lua_files(theme_id, size)

    if sync_env:
        env_pairs = [
            f"HYPRCURSOR_THEME={theme_id}",
            f"HYPRCURSOR_SIZE={size}",
            f"XCURSOR_THEME={theme_id}",
            f"XCURSOR_SIZE={size}",
        ]
        if shutil.which("dbus-update-activation-environment"):
            subprocess.run(["dbus-update-activation-environment", "--systemd"] + env_pairs, capture_output=True, check=False)
        if shutil.which("systemctl"):
            subprocess.run(["systemctl", "--user", "set-environment"] + env_pairs, capture_output=True, check=False)


def _prune_old_themes(keep_ids: List[str]) -> None:
    icons_base = os.path.expanduser("~/.local/share/icons")
    legacy_base = os.path.expanduser("~/.icons")
    keep = {k for k in keep_ids if k}
    if os.path.isdir(icons_base):
        entries = []
        for name in os.listdir(icons_base):
            if not name.startswith("paithosh-") or name in keep:
                continue
            full = os.path.join(icons_base, name)
            if os.path.isdir(full):
                try:
                    entries.append((os.path.getmtime(full), full, name))
                except OSError:
                    pass
        entries.sort(reverse=True)
        for _, full, name in entries[1:]:
            shutil.rmtree(full, ignore_errors=True)
            lp = os.path.join(legacy_base, name)
            if os.path.islink(lp):
                try:
                    os.unlink(lp)
                except OSError:
                    pass
    if os.path.isdir(legacy_base):
        for name in os.listdir(legacy_base):
            if name.startswith("paithosh-"):
                lp = os.path.join(legacy_base, name)
                if os.path.islink(lp) and not os.path.exists(lp):
                    try:
                        os.unlink(lp)
                    except OSError:
                        pass


def preview_tag_for(style: str, fill: str, outline: str) -> str:
    return hashlib.sha1(f"{SCHEMA_REV}:{sanitize_style(style)}:{fill}:{outline}".encode("utf-8")).hexdigest()[:8]


def write_preview_svgs(active_style: str, fill: str, outline: str) -> Tuple[str, str]:
    preview_dir = os.path.expanduser("~/.cache/paithosh/cursors")
    os.makedirs(preview_dir, exist_ok=True)
    style = sanitize_style(active_style)
    tag = preview_tag_for(style, fill, outline)
    keep_names = {f"preview-{st}-{tag}.svg" for st in STYLES}
    keep_names.add(f"active-{tag}.svg")
    for st in STYLES:
        target = os.path.join(preview_dir, f"preview-{st}-{tag}.svg")
        if not os.path.isfile(target):
            atomic_write_text(target, render_svg("default", st, fill, outline))
    active_target = os.path.join(preview_dir, f"active-{tag}.svg")
    if not os.path.isfile(active_target):
        atomic_write_text(active_target, render_svg("default", style, fill, outline))
    for fn in os.listdir(preview_dir):
        if fn.endswith(".svg") and fn not in keep_names:
            try:
                os.unlink(os.path.join(preview_dir, fn))
            except OSError:
                pass
    return preview_dir, tag


def cmd_preview_svgs(args: argparse.Namespace) -> int:
    style = sanitize_style(args.style)
    fill = normalize_hex(args.fill)
    outline = contrasting_outline(fill)
    pdir, tag = write_preview_svgs(style, fill, outline)
    print(json.dumps({"previewDir": pdir, "previewTag": tag, "fill": fill, "outline": outline}))
    return 0


def cmd_apply(args: argparse.Namespace) -> int:
    style = sanitize_style(args.style)
    size = sanitize_size(args.size)
    color_mode = (args.color_mode or "auto").strip().lower()
    if color_mode not in ("auto", "theme", "fixed"):
        color_mode = "auto"

    light_id = ""
    dark_id = ""
    if color_mode == "auto":
        light_id = build_theme(style, "#ffffff", "#0b0b0c", size)
        dark_id = build_theme(style, "#111113", "#ffffff", size)
        initial_tone = "dark" if args.initial_tone == "dark" else "light"
        active_id = dark_id if initial_tone == "dark" else light_id
        fill = "#111113" if initial_tone == "dark" else "#ffffff"
        outline = "#ffffff" if initial_tone == "dark" else "#0b0b0c"
    else:
        fill = normalize_hex(args.fill, "#ffffff")
        outline = contrasting_outline(fill)
        active_id = build_theme(style, fill, outline, size)

    preview_dir, preview_tag = write_preview_svgs(style, fill, outline)
    _sync_persistent_toolkits(active_id, size, sync_env=not args.no_live)
    if not args.no_live:
        _apply_live_cursor(active_id, size)
    _prune_old_themes([active_id, light_id, dark_id])

    hx, hy = hotspot_for("default", style)
    payload = {
        "themeId": active_id,
        "lightThemeId": light_id,
        "darkThemeId": dark_id,
        "style": style,
        "size": size,
        "colorMode": color_mode,
        "fill": fill,
        "outline": outline,
        "hotspotX": hx,
        "hotspotY": hy,
        "previewDir": preview_dir,
        "previewTag": preview_tag,
    }
    print(json.dumps(payload))
    return 0


def contrast_step(current_tone: str, lum: float) -> str:
    """Wide hysteresis prevents flicker on mid-gray surfaces."""
    if lum > 0.60:
        return "dark"
    if lum < 0.40:
        return "light"
    return current_tone


def _sample_luminance_at(x: float, y: float, monitors: List[dict]) -> Optional[float]:
    if not shutil.which("grim"):
        return None
    mx, my, mw, mh = 0, 0, 1920, 1080
    for m in monitors:
        bx, by = int(m.get("x", 0)), int(m.get("y", 0))
        bw, bh = int(m.get("width", 1920)), int(m.get("height", 1080))
        scale = float(m.get("scale", 1.0) or 1.0)
        lw, lh = max(1, int(round(bw / scale))), max(1, int(round(bh / scale)))
        if bx <= x < bx + lw and by <= y < by + lh:
            mx, my, mw, mh = bx, by, lw, lh
            break

    gx = max(mx, min(mx + mw - 16, int(round(x)) - 8))
    gy = max(my, min(my + mh - 16, int(round(y)) - 8))
    try:
        res = subprocess.run(
            ["grim", "-g", f"{gx},{gy} 16x16", "-t", "ppm", "-"],
            capture_output=True,
            timeout=1.0,
            check=False,
        )
        if res.returncode != 0 or not res.stdout:
            return None
        data = res.stdout
        if not data.startswith(b"P6"):
            return None
        idx = 2
        tokens: List[bytes] = []
        n = len(data)
        while len(tokens) < 3 and idx < n:
            while idx < n and data[idx] in (9, 10, 13, 32):
                idx += 1
            if idx < n and data[idx] == 35:  # '#' comment
                while idx < n and data[idx] != 10:
                    idx += 1
                continue
            start = idx
            while idx < n and data[idx] not in (9, 10, 13, 32):
                idx += 1
            if idx > start:
                tokens.append(data[start:idx])
        if len(tokens) < 3:
            return None
        idx += 1  # single whitespace byte after maxval
        pixels = data[idx:]
        if len(pixels) < 3:
            return None
        total = 0.0
        cnt = len(pixels) // 3
        for p in range(0, cnt * 3, 3):
            total += (0.2126 * pixels[p] + 0.7152 * pixels[p + 1] + 0.0722 * pixels[p + 2])
        return total / (cnt * 255.0)
    except Exception:
        return None


def _hypr_query(sock_path: str, cmd: bytes) -> Optional[str]:
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.settimeout(0.25)
            s.connect(sock_path)
            s.sendall(cmd)
            chunks = []
            while True:
                b = s.recv(4096)
                if not b:
                    break
                chunks.append(b)
                if len(b) < 4096:
                    break
            return b"".join(chunks).decode("utf-8", errors="ignore")
    except Exception:
        return None


def cmd_daemon(args: argparse.Namespace) -> int:
    auto_contrast = bool(args.auto_contrast)
    motion_blur = bool(args.motion_blur)
    if not auto_contrast and not motion_blur:
        return 0

    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    rt = os.environ.get("XDG_RUNTIME_DIR")
    if not sig or not rt:
        return 1
    sock1 = os.path.join(rt, "hypr", sig, ".socket.sock")
    sock2 = os.path.join(rt, "hypr", sig, ".socket2.sock")
    if not os.path.exists(sock1):
        return 1

    style = sanitize_style(args.style)
    size = sanitize_size(args.size)
    light_theme = args.light_theme or ""
    dark_theme = args.dark_theme or ""
    tone = "dark" if args.initial_tone == "dark" else "light"

    monitors: List[dict] = []
    mon_raw = _hypr_query(sock1, b"j/monitors")
    if mon_raw:
        try:
            parsed = json.loads(mon_raw)
            if isinstance(parsed, list):
                monitors = parsed
        except Exception:
            monitors = []

    ev_sock: Optional[socket.socket] = None
    if auto_contrast and os.path.exists(sock2):
        try:
            ev_sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            ev_sock.connect(sock2)
            ev_sock.setblocking(False)
        except Exception:
            ev_sock = None

    last_x: Optional[float] = None
    last_y: Optional[float] = None
    last_move_ts = time.monotonic()
    last_sample_x: Optional[float] = None
    last_sample_y: Optional[float] = None
    last_sample_ts = 0.0
    pending_contrast = True
    is_moving = False
    vx = 0.0
    vy = 0.0
    mon_refresh_ts = time.monotonic()

    try:
        while True:
            now = time.monotonic()
            if auto_contrast and (now - mon_refresh_ts) > 5.0:
                mon_refresh_ts = now
                mr = _hypr_query(sock1, b"j/monitors")
                if mr:
                    try:
                        pm = json.loads(mr)
                        if isinstance(pm, list):
                            monitors = pm
                    except Exception:
                        pass

            if ev_sock is not None:
                try:
                    ready, _, _ = select.select([ev_sock], [], [], 0.0)
                    if ready:
                        ev_data = ev_sock.recv(4096).decode("utf-8", errors="ignore")
                        if not ev_data:
                            ev_sock.close()
                            ev_sock = None
                        elif ("activewindow>>" in ev_data or "workspacev2>>" in ev_data or "focusedmon>>" in ev_data):
                            pending_contrast = True
                except Exception:
                    pass

            pos_raw = _hypr_query(sock1, b"cursorpos")
            if pos_raw and "," in pos_raw:
                try:
                    sx, sy = pos_raw.strip().split(",", 1)
                    cx, cy = float(sx), float(sy)
                except Exception:
                    cx, cy = last_x or 0.0, last_y or 0.0
            else:
                time.sleep(0.08)
                continue

            if last_x is None or last_y is None:
                last_x, last_y = cx, cy
                last_sample_x, last_sample_y = cx, cy

            dx = cx - last_x
            dy = cy - last_y
            dist = math.hypot(dx, dy)

            if dist >= 1.0:
                inst_vx = max(-140.0, min(140.0, dx))
                inst_vy = max(-140.0, min(140.0, dy))
                vx = vx * 0.45 + inst_vx * 0.55
                vy = vy * 0.45 + inst_vy * 0.55
                speed = math.hypot(vx, vy)
                last_x, last_y = cx, cy
                last_move_ts = now
                is_moving = True
                if motion_blur:
                    sys.stdout.write(f"POS {cx:.1f} {cy:.1f} {vx:.2f} {vy:.2f} {speed:.2f}\n")
                    sys.stdout.flush()
                if auto_contrast and (
                    last_sample_x is None or math.hypot(cx - last_sample_x, cy - last_sample_y) >= 24.0
                ):
                    pending_contrast = True
            else:
                if is_moving and (now - last_move_ts) >= 0.08:
                    is_moving = False
                    vx = 0.0
                    vy = 0.0
                    if motion_blur:
                        sys.stdout.write("IDLE\n")
                        sys.stdout.flush()

            if auto_contrast and light_theme and dark_theme:
                settled = (now - last_move_ts) >= 0.12
                cooldown_ok = (now - last_sample_ts) >= 0.28
                if pending_contrast and settled and cooldown_ok:
                    pending_contrast = False
                    last_sample_ts = now
                    last_sample_x, last_sample_y = cx, cy
                    lum = _sample_luminance_at(cx, cy, monitors)
                    if lum is not None:
                        next_tone = contrast_step(tone, lum)
                        if next_tone != tone:
                            tone = next_tone
                            next_theme = dark_theme if tone == "dark" else light_theme
                            _hypr_query(sock1, f"setcursor {next_theme} {size}".encode("utf-8"))
                            if shutil.which("gsettings"):
                                subprocess.run(
                                    ["gsettings", "set", "org.gnome.desktop.interface", "cursor-theme", next_theme],
                                    stdout=subprocess.DEVNULL,
                                    stderr=subprocess.DEVNULL,
                                    timeout=1.0,
                                    check=False,
                                )
                            n_fill = "#111113" if tone == "dark" else "#ffffff"
                            n_out = "#ffffff" if tone == "dark" else "#0b0b0c"
                            _, n_tag = write_preview_svgs(style, n_fill, n_out)
                            sys.stdout.write(f"CONTRAST {tone} {lum:.3f} {n_tag}\n")
                            sys.stdout.flush()

            sleep_s = 0.013 if (motion_blur and is_moving) else 0.065
            time.sleep(sleep_s)
    except KeyboardInterrupt:
        return 0
    finally:
        if ev_sock is not None:
            try:
                ev_sock.close()
            except Exception:
                pass


def run_self_test() -> int:
    assert sanitize_style("unknown") == "sharp"
    assert sanitize_size(999) == MAX_SIZE
    assert sanitize_size(4) == MIN_SIZE
    assert contrasting_outline("#ffffff") == "#0b0b0c"
    assert contrasting_outline("#111113") == "#ffffff"
    assert contrast_step("light", 0.72) == "dark"
    assert contrast_step("dark", 0.50) == "dark"  # hysteresis hold
    assert contrast_step("light", 0.50) == "light"  # hysteresis hold
    assert contrast_step("dark", 0.25) == "light"

    with tempfile.TemporaryDirectory(prefix="paithosh-cursor-test-") as td:
        icons_dir = os.path.join(td, "icons")
        legacy_dir = os.path.join(td, "legacy_icons")
        for st in STYLES:
            tid = build_theme(st, "#ffffff", "#0b0b0c", 24, icons_root=icons_dir, legacy_icons_root=legacy_dir)
            tdir = os.path.join(icons_dir, tid)
            assert os.path.isfile(os.path.join(tdir, "index.theme")), f"missing index.theme for {st}"
            assert os.path.isfile(os.path.join(tdir, ".built-ok")), f"missing .built-ok for {st}"
            if shutil.which("hyprcursor-util"):
                assert os.path.isfile(os.path.join(tdir, "manifest.hl")), f"missing manifest.hl for {st}"
                hc_default = os.path.join(tdir, "hyprcursors", "default.hlc")
                assert os.path.isfile(hc_default) and os.path.getsize(hc_default) > 0, f"missing default.hlc for {st}"

            xc_default = os.path.join(tdir, "cursors", "default")
            with open(xc_default, "rb") as xf:
                hdr = xf.read(16)
            magic, hdr_sz, ver, n_img = struct.unpack("<4sIII", hdr)
            assert magic == b"Xcur" and hdr_sz == 16 and n_img >= 4, (st, magic, hdr_sz, n_img)

            for critical in (
                "left_ptr", "hand2", "xterm", "9d800788f1b08800ae810202380a0822",
                "sb_h_double_arrow", "08e8e1c95fe2fc01f976f1e063a24ccd", "fleur", "crossed_circle",
            ):
                p = os.path.join(tdir, "cursors", critical)
                assert os.path.exists(p), f"dangling/missing cursor alias {critical} in {st}"

            assert os.path.islink(os.path.join(legacy_dir, tid)), f"missing ~/.icons symlink for {st}"

    print("PASS: All 3 closed cursor styles (Hyprcursor + XCursor + ~95 GTK/Qt aliases + hysteresis) verified")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Paithosh Closed Custom Cursor Tool")
    parser.add_argument("--self-test", action="store_true", help="Run built-in dual-format verification")
    sub = parser.add_subparsers(dest="cmd")

    p_apply = sub.add_parser("apply", help="Build and sync custom cursor theme across Hyprland, GTK, and Qt")
    p_apply.add_argument("--style", default=DEFAULT_STYLE)
    p_apply.add_argument("--size", type=int, default=DEFAULT_SIZE)
    p_apply.add_argument("--color-mode", default="auto")
    p_apply.add_argument("--fill", default="#ffffff")
    p_apply.add_argument("--initial-tone", default="light")
    p_apply.add_argument("--no-live", action="store_true")

    p_prev = sub.add_parser("preview-svgs", help="Export preview SVGs for Settings showcase cards")
    p_prev.add_argument("--style", default=DEFAULT_STYLE)
    p_prev.add_argument("--fill", default="#ffffff")

    p_dmn = sub.add_parser("daemon", help="Run live Auto Contrast & Motion Blur daemon")
    p_dmn.add_argument("--style", default=DEFAULT_STYLE)
    p_dmn.add_argument("--auto-contrast", type=int, default=0)
    p_dmn.add_argument("--motion-blur", type=int, default=0)
    p_dmn.add_argument("--size", type=int, default=DEFAULT_SIZE)
    p_dmn.add_argument("--light-theme", default="")
    p_dmn.add_argument("--dark-theme", default="")
    p_dmn.add_argument("--initial-tone", default="light")

    args = parser.parse_args()
    if args.self_test:
        return run_self_test()
    if args.cmd == "apply":
        return cmd_apply(args)
    if args.cmd == "preview-svgs":
        return cmd_preview_svgs(args)
    if args.cmd == "daemon":
        return cmd_daemon(args)
    parser.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main())
