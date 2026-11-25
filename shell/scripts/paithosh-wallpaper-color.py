#!/usr/bin/env python3
"""Wallpaper color analysis & Paithosh palette engine (Solid 3-5 / Gradient 10-12).

Extracts perceptual OKLab/OKLCH clusters deterministically from a wallpaper image
and maps them to Paithosh's 4-tier dark elevation ladder + luminous accents with
guaranteed WCAG contrast and smooth multi-stop gradients.
"""

from __future__ import annotations

import argparse
import json
import math
import subprocess
import sys
from pathlib import Path
from typing import Any

from PIL import Image

try:
    _RESAMPLE_BILINEAR = Image.Resampling.BILINEAR
except AttributeError:  # Pillow < 9.1
    _RESAMPLE_BILINEAR = Image.BILINEAR


def _clamp(v: float, lo: float, hi: float) -> float:
    return lo if v < lo else (hi if v > hi else v)


def _srgb_to_linear(u: float) -> float:
    u = _clamp(u, 0.0, 1.0)
    return u / 12.92 if u <= 0.04045 else ((u + 0.055) / 1.055) ** 2.4


def _linear_to_srgb(u: float) -> float:
    u = _clamp(u, 0.0, 1.0)
    return 12.92 * u if u <= 0.0031308 else 1.055 * (u ** (1.0 / 2.4)) - 0.055


def _cbrt(x: float) -> float:
    return math.copysign(abs(x) ** (1.0 / 3.0), x)


def rgb_to_oklab(r: float, g: float, b: float) -> tuple[float, float, float]:
    """Convert normalized sRGB [0,1] to Björn Ottosson OKLab (L, a, b)."""
    lr = _srgb_to_linear(r)
    lg = _srgb_to_linear(g)
    lb = _srgb_to_linear(b)

    l = 0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb
    m = 0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb
    s = 0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb

    l_ = _cbrt(l)
    m_ = _cbrt(m)
    s_ = _cbrt(s)

    L = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_
    a = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_
    bk = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
    return (L, a, bk)


def oklab_to_linear_rgb(L: float, a: float, b: float) -> tuple[float, float, float]:
    l_ = L + 0.3963377774 * a + 0.2158037573 * b
    m_ = L - 0.1055613458 * a - 0.0638541728 * b
    s_ = L - 0.0894841775 * a - 1.2914855480 * b

    l = l_ * l_ * l_
    m = m_ * m_ * m_
    s = s_ * s_ * s_

    lr = +4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
    lg = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
    lb = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
    return (lr, lg, lb)


def oklab_to_oklch(L: float, a: float, b: float) -> tuple[float, float, float]:
    C = math.hypot(a, b)
    h = (math.degrees(math.atan2(b, a)) + 360.0) % 360.0 if C > 1e-7 else 0.0
    return (L, C, h)


def oklch_to_srgb_gamut(L: float, C: float, h_deg: float) -> tuple[float, float, float]:
    """Convert OKLCH to in-gamut sRGB [0,1] via binary-search chroma clipping."""
    L = _clamp(L, 0.0, 1.0)
    C = max(0.0, C)
    rad = math.radians(h_deg % 360.0)
    ca = math.cos(rad)
    sb = math.sin(rad)

    def _in_gamut(ch: float) -> tuple[bool, tuple[float, float, float]]:
        lr, lg, lb = oklab_to_linear_rgb(L, ch * ca, ch * sb)
        ok = (-1e-4 <= lr <= 1.0001) and (-1e-4 <= lg <= 1.0001) and (-1e-4 <= lb <= 1.0001)
        return ok, (lr, lg, lb)

    ok, lrgb = _in_gamut(C)
    if not ok:
        lo, hi = 0.0, C
        best = (L, L, L)
        for _ in range(18):
            mid = 0.5 * (lo + hi)
            m_ok, m_lrgb = _in_gamut(mid)
            if m_ok:
                lo = mid
                best = m_lrgb
            else:
                hi = mid
        lrgb = best

    return (
        _linear_to_srgb(lrgb[0]),
        _linear_to_srgb(lrgb[1]),
        _linear_to_srgb(lrgb[2]),
    )


def srgb_to_hex(rgb: tuple[float, float, float]) -> str:
    r = int(round(_clamp(rgb[0], 0.0, 1.0) * 255))
    g = int(round(_clamp(rgb[1], 0.0, 1.0) * 255))
    b = int(round(_clamp(rgb[2], 0.0, 1.0) * 255))
    return f"#{r:02x}{g:02x}{b:02x}"


def hex_to_rgb(hx: str) -> tuple[float, float, float]:
    s = hx.strip().lstrip("#")
    return (
        int(s[0:2], 16) / 255.0,
        int(s[2:4], 16) / 255.0,
        int(s[4:6], 16) / 255.0,
    )


def oklab_dist(c1: tuple[float, float, float], c2: tuple[float, float, float]) -> float:
    return math.sqrt((c1[0] - c2[0]) ** 2 + (c1[1] - c2[1]) ** 2 + (c1[2] - c2[2]) ** 2)


def relative_luminance(rgb: tuple[float, float, float]) -> float:
    return (
        0.2126 * _srgb_to_linear(rgb[0])
        + 0.7152 * _srgb_to_linear(rgb[1])
        + 0.0722 * _srgb_to_linear(rgb[2])
    )


def wcag_contrast(rgb1: tuple[float, float, float], rgb2: tuple[float, float, float]) -> float:
    y1 = relative_luminance(rgb1)
    y2 = relative_luminance(rgb2)
    hi = max(y1, y2)
    lo = min(y1, y2)
    return (hi + 0.05) / (lo + 0.05)


def hue_diff_deg(h1: float, h2: float) -> float:
    d = abs((h1 - h2) % 360.0)
    return 360.0 - d if d > 180.0 else d


def lerp_hue_deg(h1: float, h2: float, t: float) -> float:
    delta = ((h2 - h1 + 540.0) % 360.0) - 180.0
    return (h1 + delta * t + 360.0) % 360.0


def clamp_hue_step(base_h: float, target_h: float, min_deg: float, max_deg: float) -> float:
    """Pull target_h along the shortest arc from base_h within [min_deg, max_deg]."""
    delta = ((target_h - base_h + 540.0) % 360.0) - 180.0
    if abs(delta) < 1e-4:
        return (base_h + min_deg) % 360.0
    sign = 1.0 if delta >= 0.0 else -1.0
    mag = _clamp(abs(delta), min_deg, max_deg)
    return (base_h + sign * mag + 360.0) % 360.0


def _ensure_contrast(
    lch: tuple[float, float, float],
    bg_rgbs: list[tuple[float, float, float]],
    min_ratio: float,
    lift: bool = True,
) -> tuple[float, float, float]:
    L, C, h = lch
    rgb = oklch_to_srgb_gamut(L, C, h)
    if min(wcag_contrast(rgb, bg) for bg in bg_rgbs) >= min_ratio:
        return (L, C, h)
    step = 0.014 if lift else -0.014
    for _ in range(60):
        L = _clamp(L + step, 0.02, 0.985)
        rgb = oklch_to_srgb_gamut(L, C, h)
        if min(wcag_contrast(rgb, bg) for bg in bg_rgbs) >= min_ratio:
            break
        if (lift and L >= 0.984) or (not lift and L <= 0.021):
            # If still short due to extreme chroma, gently relax chroma toward neutral
            C *= 0.85
    return (L, C, h)


def _pick_accent_fg(
    accent_lchs: list[tuple[float, float, float]],
    base_h: float,
    monochrome: bool,
    min_ratio: float,
) -> tuple[list[tuple[float, float, float]], str]:
    """Choose dark/light accent foreground ink and nudge accent lightness if needed."""
    dark_ink = (0.04, 0.004, base_h) if not monochrome else (0.04, 0.0, 0.0)
    dark_rgb = oklch_to_srgb_gamut(*dark_ink)
    dark_hex = "#000000" if monochrome else srgb_to_hex(dark_rgb)
    dark_rgb = hex_to_rgb(dark_hex)
    light_rgb = (1.0, 1.0, 1.0)

    rgbs = [oklch_to_srgb_gamut(*x) for x in accent_lchs]
    min_dark = min(wcag_contrast(dark_rgb, r) for r in rgbs)
    min_light = min(wcag_contrast(light_rgb, r) for r in rgbs)

    use_dark = min_dark >= min_light or min_dark >= min_ratio
    fg_rgb = dark_rgb if use_dark else light_rgb
    fg_hex = dark_hex if use_dark else "#ffffff"

    adjusted: list[tuple[float, float, float]] = []
    for L, C, h in accent_lchs:
        cur_L, cur_C = L, C
        for _ in range(45):
            r = oklch_to_srgb_gamut(cur_L, cur_C, h)
            if wcag_contrast(fg_rgb, r) >= min_ratio:
                break
            cur_L = _clamp(cur_L + (0.015 if use_dark else -0.015), 0.25, 0.95)
        adjusted.append((cur_L, cur_C, h))
    return adjusted, fg_hex


def _load_image_rgb(path: Path) -> Image.Image:
    try:
        with Image.open(path) as im:
            im.draft("RGB", (192, 192))
            return im.convert("RGB")
    except Exception as pil_err:
        # Fallback to ImageMagick raw RGB pipe for exotic formats (e.g. AVIF/HEIC/JXL)
        proc = subprocess.run(
            ["magick", str(path), "-resize", "96x96>", "-depth", "8", "rgb:-"],
            capture_output=True,
            check=False,
        )
        if proc.returncode != 0 or not proc.stdout:
            raise ValueError(f"Failed to decode image {path}: {pil_err}") from pil_err
        wh = subprocess.run(
            ["magick", str(path), "-resize", "96x96>", "-format", "%w %h", "info:"],
            capture_output=True,
            text=True,
            check=True,
        )
        w, h = (int(x) for x in wh.stdout.strip().split())
        return Image.frombytes("RGB", (w, h), proc.stdout)


def _resize_fit(img: Image.Image, max_dim: int = 96) -> Image.Image:
    rgb_img = img if img.mode == "RGB" else img.convert("RGB")
    w, h = rgb_img.size
    if w <= 0 or h <= 0:
        raise ValueError("Image has zero dimensions")
    scale = min(1.0, max_dim / float(max(w, h)))
    nw = max(1, int(round(w * scale)))
    nh = max(1, int(round(h * scale)))
    if (nw, nh) != (w, h):
        return rgb_img.resize((nw, nh), _RESAMPLE_BILINEAR)
    return rgb_img


def _rgb_pixels(img: Image.Image) -> list[tuple[int, int, int]]:
    if hasattr(img, "get_flattened_data"):
        return list(img.get_flattened_data())
    return list(img.getdata())


def _compute_gradient_angle(w: int, h: int, pixels: list[tuple[int, int, int]]) -> int:
    """Compute dominant brightness flow angle (0-360 deg) from 4x4 spatial grid."""
    grid = [[0.0] * 4 for _ in range(4)]
    counts = [[0] * 4 for _ in range(4)]
    for y in range(h):
        gy = min(3, (y * 4) // h)
        row_off = y * w
        for x in range(w):
            gx = min(3, (x * 4) // w)
            r, g, b = pixels[row_off + x]
            lum = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0
            grid[gy][gx] += lum
            counts[gy][gx] += 1

    for gy in range(4):
        for gx in range(4):
            if counts[gy][gx] > 0:
                grid[gy][gx] /= counts[gy][gx]

    dx = 0.0
    dy = 0.0
    for gy in range(4):
        for gx in range(4):
            wx = (gx - 1.5) / 1.5
            wy = (gy - 1.5) / 1.5
            dx += wx * grid[gy][gx]
            dy += wy * grid[gy][gx]

    if math.hypot(dx, dy) < 0.025:
        return 135
    # Match theme_gradient.frag convention: dir = (sin(angleRad), -cos(angleRad))
    deg = math.degrees(math.atan2(dx, -dy))
    return int(round((deg + 360.0) % 360.0)) % 360


def _bin_image_oklab(pixels: list[tuple[int, int, int]]) -> tuple[list[tuple[float, float, float, float]], dict[str, float]]:
    """Pre-bin pixels into 5-bit RGB histogram -> exact OKLab centroids + global stats."""
    bins: dict[int, list[int]] = {}
    total = len(pixels)
    if total == 0:
        return [(0.15, 0.0, 0.0, 1.0)], {"mean_L": 0.15, "p10_L": 0.15, "p90_L": 0.15, "mean_C": 0.0, "p90_C": 0.0}

    for r, g, b in pixels:
        key = ((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4)
        slot = bins.get(key)
        if slot is None:
            bins[key] = [1, r, g, b]
        else:
            slot[0] += 1
            slot[1] += r
            slot[2] += g
            slot[3] += b

    items: list[tuple[float, float, float, float]] = []
    l_hist: list[tuple[float, float]] = []
    c_hist: list[tuple[float, float]] = []
    mean_L = 0.0
    mean_C = 0.0

    for cnt, sr, sg, sb in bins.values():
        w = cnt / float(total)
        cr = sr / (cnt * 255.0)
        cg = sg / (cnt * 255.0)
        cb = sb / (cnt * 255.0)
        L, a, bk = rgb_to_oklab(cr, cg, cb)
        C = math.hypot(a, bk)
        items.append((L, a, bk, w))
        l_hist.append((L, w))
        c_hist.append((C, w))
        mean_L += L * w
        mean_C += C * w

    def _weighted_quantile(pairs: list[tuple[float, float]], q: float) -> float:
        pairs.sort(key=lambda x: x[0])
        acc = 0.0
        for val, w in pairs:
            acc += w
            if acc >= q:
                return val
        return pairs[-1][0]

    stats = {
        "mean_L": mean_L,
        "p10_L": _weighted_quantile(l_hist, 0.10),
        "p90_L": _weighted_quantile(l_hist, 0.90),
        "mean_C": mean_C,
        "p90_C": _weighted_quantile(c_hist, 0.90),
    }
    return items, stats


def _weighted_kmeans_oklab(
    points: list[tuple[float, float, float, float]],
    k: int,
    max_iter: int = 18,
) -> list[tuple[float, float, float, float]]:
    """Deterministic weighted OKLab K-Means++ returning [(L, a, b, weight), ...] sorted by weight."""
    if not points:
        return [(0.15, 0.0, 0.0, 1.0)]

    sorted_pts = sorted(points, key=lambda p: (-p[3], p[0], p[1], p[2]))
    centers: list[tuple[float, float, float]] = [(sorted_pts[0][0], sorted_pts[0][1], sorted_pts[0][2])]
    min_d2 = [
        (p[0] - centers[0][0]) ** 2 + (p[1] - centers[0][1]) ** 2 + (p[2] - centers[0][2]) ** 2
        for p in sorted_pts
    ]

    target_k = min(k, len(sorted_pts))
    for _ in range(1, target_k):
        best_idx = 0
        best_score = -1.0
        for idx, p in enumerate(sorted_pts):
            sc = p[3] * min_d2[idx]
            if sc > best_score:
                best_score = sc
                best_idx = idx
        if best_score <= 1e-12:
            break
        nc = (sorted_pts[best_idx][0], sorted_pts[best_idx][1], sorted_pts[best_idx][2])
        centers.append(nc)
        for idx, p in enumerate(sorted_pts):
            d2 = (p[0] - nc[0]) ** 2 + (p[1] - nc[1]) ** 2 + (p[2] - nc[2]) ** 2
            if d2 < min_d2[idx]:
                min_d2[idx] = d2

    m = len(centers)
    assigns = [0] * len(sorted_pts)
    for _ in range(max_iter):
        changed = False
        sums = [[0.0, 0.0, 0.0, 0.0] for _ in range(m)]
        for idx, (L, a, b, w) in enumerate(sorted_pts):
            best_c = 0
            best_d2 = 1e9
            for ci, (cL, ca, cb) in enumerate(centers):
                d2 = (L - cL) ** 2 + (a - ca) ** 2 + (b - cb) ** 2
                if d2 < best_d2:
                    best_d2 = d2
                    best_c = ci
            if assigns[idx] != best_c:
                assigns[idx] = best_c
                changed = True
            s = sums[best_c]
            s[0] += L * w
            s[1] += a * w
            s[2] += b * w
            s[3] += w

        new_centers: list[tuple[float, float, float]] = []
        for ci, s in enumerate(sums):
            if s[3] > 1e-9:
                new_centers.append((s[0] / s[3], s[1] / s[3], s[2] / s[3]))
            else:
                new_centers.append(centers[ci])
        centers = new_centers
        if not changed:
            break

    final_w = [0.0] * m
    final_s = [[0.0, 0.0, 0.0] for _ in range(m)]
    for idx, (L, a, b, w) in enumerate(sorted_pts):
        ci = assigns[idx]
        final_w[ci] += w
        final_s[ci][0] += L * w
        final_s[ci][1] += a * w
        final_s[ci][2] += b * w

    out: list[tuple[float, float, float, float]] = []
    for ci in range(m):
        w = final_w[ci]
        if w > 1e-9:
            out.append((final_s[ci][0] / w, final_s[ci][1] / w, final_s[ci][2] / w, w))
    out.sort(key=lambda c: -c[3])
    return out


def _merge_and_bound_clusters(
    clusters: list[tuple[float, float, float, float]],
    merge_dist: float,
    min_count: int,
    max_count: int,
    noise_thresh: float,
) -> list[tuple[float, float, float, float]]:
    cur = list(clusters)
    # Greedily merge overly close clusters while respecting min_count
    merged = True
    while merged and len(cur) > min_count:
        merged = False
        for i in range(len(cur)):
            for j in range(i + 1, len(cur)):
                if oklab_dist(cur[i][:3], cur[j][:3]) < merge_dist:
                    w1, w2 = cur[i][3], cur[j][3]
                    wt = w1 + w2
                    comb = (
                        (cur[i][0] * w1 + cur[j][0] * w2) / wt,
                        (cur[i][1] * w1 + cur[j][1] * w2) / wt,
                        (cur[i][2] * w1 + cur[j][2] * w2) / wt,
                        wt,
                    )
                    cur[i] = comb
                    cur.pop(j)
                    merged = True
                    break
            if merged:
                break

    cur.sort(key=lambda c: -c[3])
    while len(cur) > min_count and cur[-1][3] < noise_thresh:
        cur.pop()
    cur = cur[:max_count]

    # Synthesize subtle tonal steps if minimalist/uniform image produced < min_count clusters
    seen_hex = {srgb_to_hex(oklch_to_srgb_gamut(*oklab_to_oklch(*c[:3]))) for c in cur}
    step_idx = 0
    while len(cur) < min_count:
        base = cur[step_idx % len(cur)]
        L, C, h = oklab_to_oklch(*base[:3])
        delta_l = (0.14 if step_idx % 2 == 0 else -0.14) * (1 + step_idx // 2 * 0.5)
        cand_L = _clamp(L + delta_l, 0.08, 0.94)
        cand_h = (h + (18.0 if step_idx % 2 == 0 else -18.0) * (step_idx // 2)) % 360.0
        rgb = oklch_to_srgb_gamut(cand_L, C, cand_h)
        hx = srgb_to_hex(rgb)
        if hx in seen_hex:
            cand_L = _clamp(0.15 + (step_idx * 0.13) % 0.75, 0.08, 0.94)
            rgb = oklch_to_srgb_gamut(cand_L, C, cand_h)
            hx = srgb_to_hex(rgb)
        seen_hex.add(hx)
        nL, na, nb = rgb_to_oklab(*rgb)
        cur.append((nL, na, nb, 0.01))
        step_idx += 1

    return cur


def _cluster_hexes(clusters: list[tuple[float, float, float, float]]) -> list[str]:
    out: list[str] = []
    seen: set[str] = set()
    for L, a, b, _ in clusters:
        hx = srgb_to_hex(oklch_to_srgb_gamut(*oklab_to_oklch(L, a, b)))
        if hx not in seen:
            seen.add(hx)
            out.append(hx)
    return out


def _pick_base_and_accent_clusters(
    clusters: list[tuple[float, float, float, float]],
) -> tuple[tuple[float, float, float, float], tuple[float, float, float, float], tuple[float, float, float, float]]:
    """Return (base_cluster, primary_accent_cluster, secondary_accent_cluster)."""
    lch_list = [(oklab_to_oklch(*c[:3]), c) for c in clusters]

    # Base atmosphere: favor dominant coverage + dark/mid lightness
    base_pair = max(
        lch_list,
        key=lambda item: item[1][3] * (1.0 - 0.35 * abs(item[0][0] - 0.35)),
    )
    base_lch, base_c = base_pair

    def _salience(lch: tuple[float, float, float], w: float, ref_h: float | None = None) -> float:
        L, C, h = lch
        sweet = math.exp(-(((L - 0.62) / 0.34) ** 2))
        hue_bonus = 1.0
        if ref_h is not None:
            hd = hue_diff_deg(h, ref_h)
            hue_bonus = 1.15 if hd >= 20.0 else 1.0
        return (max(C, 0.002) ** 1.35) * (max(w, 0.005) ** 0.35) * sweet * hue_bonus

    acc1_pair = max(
        lch_list,
        key=lambda item: _salience(item[0], item[1][3], base_lch[2]),
    )
    acc1_lch, acc1_c = acc1_pair

    # Secondary accent: prefer a distinct prominent hue if available
    def _sec_score(item: tuple[tuple[float, float, float], tuple[float, float, float, float]]) -> float:
        lch, c = item
        hd = hue_diff_deg(lch[2], acc1_lch[2])
        sep = 1.35 if 22.0 <= hd <= 85.0 else (1.10 if hd > 85.0 else 0.35)
        return _salience(lch, c[3]) * sep

    acc2_pair = max(lch_list, key=_sec_score)
    return base_c, acc1_c, acc2_pair[1]


def _build_solid_palette(
    clusters: list[tuple[float, float, float, float]],
    stats: dict[str, float],
    angle: int,
) -> dict[str, Any]:
    solid_clusters = _merge_and_bound_clusters(
        clusters, merge_dist=0.06, min_count=3, max_count=5, noise_thresh=0.015
    )
    extracted = _cluster_hexes(solid_clusters)
    # Guarantee 3..5 distinct extracted hexes after quantization
    while len(extracted) < 3 and solid_clusters:
        L, C, h = oklab_to_oklch(*solid_clusters[0][:3])
        cand = srgb_to_hex(oklch_to_srgb_gamut(_clamp(L + 0.16 * len(extracted), 0.1, 0.92), C, h))
        if cand not in extracted:
            extracted.append(cand)
        else:
            extracted.append(srgb_to_hex(oklch_to_srgb_gamut(0.18 + 0.25 * len(extracted), C, (h + 24.0 * len(extracted)) % 360.0)))
    extracted = extracted[:5]

    is_mono = stats["p90_C"] < 0.025
    mean_L = stats["mean_L"]
    base_c, acc_c, _ = _pick_base_and_accent_clusters(solid_clusters)
    _, base_C, base_h = oklab_to_oklch(*base_c[:3])
    acc_L, acc_C, acc_h = oklab_to_oklch(*acc_c[:3])

    if is_mono:
        pill_L = _clamp(0.10 + 0.07 * mean_L, 0.09, 0.17)
        surf_L = pill_L + 0.045
        raised_L = surf_L + 0.055
        pill_lch = (pill_L, 0.0, 0.0)
        surf_lch = (surf_L, 0.0, 0.0)
        raised_lch = (raised_L, 0.0, 0.0)
        acc_lch = (0.90 if mean_L > 0.5 else 0.88, 0.0, 0.0)
        text_lch = (0.96, 0.0, 0.0)
        border_lch = (0.82, 0.0, 0.0)
    else:
        pill_L = _clamp(0.13 + 0.075 * mean_L, 0.13, 0.205)
        surf_L = pill_L + 0.048
        raised_L = surf_L + 0.055
        pill_C = _clamp(base_C * 0.24, 0.014, 0.030)
        surf_C = _clamp(base_C * 0.28, 0.016, 0.036)
        raised_C = _clamp(base_C * 0.30, 0.018, 0.040)

        pill_lch = (pill_L, pill_C, base_h)
        surf_lch = (surf_L, surf_C, base_h)
        raised_lch = (raised_L, raised_C, base_h)

        target_acc_C = _clamp(acc_C * 0.92, 0.065, 0.165) if acc_C >= 0.045 else max(0.045, acc_C)
        target_acc_L = _clamp(max(acc_L, 0.72), 0.72, 0.83)
        acc_lch = (target_acc_L, target_acc_C, acc_h)
        text_lch = (0.955, 0.010, base_h)
        border_lch = (0.80, _clamp(base_C * 0.35, 0.022, 0.048), lerp_hue_deg(base_h, acc_h, 0.35))

    pill_rgb = oklch_to_srgb_gamut(*pill_lch)
    surf_rgb = oklch_to_srgb_gamut(*surf_lch)
    bg_rgbs = [pill_rgb, surf_rgb]

    text_lch = _ensure_contrast(text_lch, bg_rgbs, 11.0, lift=True)
    acc_lch = _ensure_contrast(acc_lch, bg_rgbs, 4.5, lift=True)
    adj_acc, accent_fg_hex = _pick_accent_fg([acc_lch], base_h, is_mono, min_ratio=6.0)
    acc_lch = _ensure_contrast(adj_acc[0], bg_rgbs, 4.5, lift=True)
    # Re-evaluate accentFg after final contrast clamp
    _, accent_fg_hex = _pick_accent_fg([acc_lch], base_h, is_mono, min_ratio=4.5)

    pill_hex = srgb_to_hex(pill_rgb)
    surf_hex = srgb_to_hex(surf_rgb)
    raised_hex = srgb_to_hex(oklch_to_srgb_gamut(*raised_lch))
    text_hex = srgb_to_hex(oklch_to_srgb_gamut(*text_lch))
    acc_hex = srgb_to_hex(oklch_to_srgb_gamut(*acc_lch))
    border_hex = srgb_to_hex(oklch_to_srgb_gamut(*border_lch))

    return {
        "ok": True,
        "mode": "Solid",
        "monochrome": bool(is_mono),
        "extractedColors": extracted,
        "refinedPalette": [pill_hex, surf_hex, raised_hex, acc_hex, text_hex],
        "palette": {
            "pillBg": pill_hex,
            "pillBgMid": pill_hex,
            "pillBg2": pill_hex,
            "surfaceBg": surf_hex,
            "surfaceBgMid": surf_hex,
            "surfaceBg2": surf_hex,
            "surfaceRaised": raised_hex,
            "text": text_hex,
            "borderColor": border_hex,
            "accent": acc_hex,
            "accentMid": acc_hex,
            "accent2": acc_hex,
            "accentFg": accent_fg_hex,
            "gradientAngle": angle,
            "shellGradientEnabled": False,
            "surfaceGradientEnabled": False,
            "accentGradientEnabled": False,
            "cardAlpha": 0.08 if is_mono else 0.09,
            "hoverAlpha": 0.14 if is_mono else 0.15,
            "borderAlpha": 0.15 if is_mono else 0.17,
        },
    }


def _build_gradient_palette(
    clusters: list[tuple[float, float, float, float]],
    stats: dict[str, float],
    angle: int,
) -> dict[str, Any]:
    grad_clusters = _merge_and_bound_clusters(
        clusters, merge_dist=0.03, min_count=10, max_count=12, noise_thresh=0.004
    )
    extracted = _cluster_hexes(grad_clusters)
    idx = 0
    while len(extracted) < 10 and grad_clusters:
        L, C, h = oklab_to_oklch(*grad_clusters[idx % len(grad_clusters)][:3])
        cand_L = _clamp(0.12 + 0.075 * len(extracted), 0.08, 0.94)
        cand_h = (h + 18.0 * len(extracted)) % 360.0
        hx = srgb_to_hex(oklch_to_srgb_gamut(cand_L, C, cand_h))
        if hx not in extracted:
            extracted.append(hx)
        idx += 1
    extracted = extracted[:12]

    is_mono = stats["p90_C"] < 0.025
    mean_L = stats["mean_L"]

    # Partition clusters by lightness for dark/mid/light zone awareness
    by_L = sorted(grad_clusters, key=lambda c: c[0])
    n = len(by_L)
    shadows = by_L[: max(1, n // 3)]
    mids = by_L[max(1, n // 3) : max(2, (2 * n) // 3)]
    base_c, acc1_c, acc2_c = _pick_base_and_accent_clusters(grad_clusters)

    _, base_C, base_h = oklab_to_oklch(*base_c[:3])
    sh_c = max(shadows, key=lambda c: c[3])
    md_c = max(mids, key=lambda c: c[3])
    _, sh_C, sh_h = oklab_to_oklch(*sh_c[:3])
    _, md_C, md_h = oklab_to_oklch(*md_c[:3])
    a1_L, a1_C, a1_h = oklab_to_oklch(*acc1_c[:3])
    a2_L, a2_C, a2_h = oklab_to_oklch(*acc2_c[:3])

    if is_mono:
        pill_L = _clamp(0.10 + 0.065 * mean_L, 0.095, 0.175)
        pill_stops = [
            (pill_L, 0.0, 0.0),
            (pill_L + 0.032, 0.0, 0.0),
            (pill_L + 0.064, 0.0, 0.0),
        ]
        surf_L = pill_L + 0.042
        surf_stops = [
            (surf_L, 0.0, 0.0),
            (surf_L + 0.032, 0.0, 0.0),
            (surf_L + 0.062, 0.0, 0.0),
        ]
        raised_lch = (max(surf_L + 0.055, surf_stops[2][0] + 0.015), 0.0, 0.0)
        border_lch = (0.82, 0.0, 0.0)
        text_lch = (0.96, 0.0, 0.0)
        acc_stops = [
            (0.84, 0.0, 0.0),
            (0.90, 0.0, 0.0),
            (0.95, 0.0, 0.0),
        ]
    else:
        # Shell & Surface hue arcs capped <= 45 deg so dark gradients stay lush, never muddy gray
        h_s1 = sh_h if sh_C > 0.015 else base_h
        h_s2 = clamp_hue_step(h_s1, md_h if md_C > 0.015 else a1_h, 12.0, 42.0)
        h_s_mid = lerp_hue_deg(h_s1, h_s2, 0.45)

        h_f1 = base_h if base_C > 0.015 else h_s1
        h_f2 = clamp_hue_step(h_f1, a1_h, 14.0, 45.0)
        h_f_mid = lerp_hue_deg(h_f1, h_f2, 0.50)

        pill_L = _clamp(0.125 + 0.065 * mean_L, 0.125, 0.19)
        pill_C = _clamp(max(sh_C, base_C) * 0.25, 0.018, 0.032)
        pill_stops = [
            (pill_L, pill_C, h_s1),
            (pill_L + 0.032, pill_C * 1.12, h_s_mid),
            (pill_L + 0.064, _clamp(pill_C * 1.25, 0.020, 0.044), h_s2),
        ]

        surf_L = pill_L + 0.042
        surf_C = _clamp(max(md_C, base_C) * 0.28, 0.020, 0.036)
        surf_stops = [
            (surf_L, surf_C, h_f1),
            (surf_L + 0.032, surf_C * 1.10, h_f_mid),
            (surf_L + 0.062, _clamp(surf_C * 1.22, 0.022, 0.048), h_f2),
        ]

        raised_L = min(0.34, max(surf_L + 0.055, surf_stops[2][0] + 0.015))
        raised_lch = (raised_L, _clamp(surf_C * 1.15, 0.020, 0.044), h_f_mid)
        border_lch = (0.80, _clamp(base_C * 0.35, 0.022, 0.048), lerp_hue_deg(h_f1, a1_h, 0.4))
        text_lch = (0.955, 0.010, h_f1)

        # Luminous Accent 3-stop arc (22-72 deg span keeps gradient rich without muddy center cross)
        h_a1 = a1_h
        h_a2 = clamp_hue_step(h_a1, a2_h if a2_C > 0.025 else (h_a1 + 36.0) % 360.0, 22.0, 72.0)
        h_amid = lerp_hue_deg(h_a1, h_a2, 0.50)

        a1_target_C = _clamp(a1_C * 0.95, 0.075, 0.165) if a1_C >= 0.045 else max(0.050, a1_C)
        a2_target_C = _clamp(max(a2_C, a1_C * 0.85) * 0.95, 0.075, 0.165) if a1_C >= 0.045 else max(0.050, a1_C)
        amid_C = _clamp(max(a1_target_C, a2_target_C) * 1.05, 0.080, 0.170) if a1_C >= 0.045 else max(0.052, a1_C)

        L_a1 = _clamp(max(a1_L, 0.72), 0.72, 0.82)
        L_a2 = _clamp(max(a2_L, 0.74), 0.74, 0.85)
        if abs(L_a1 - L_a2) < 0.025:
            L_a2 = _clamp(L_a1 + 0.04, 0.74, 0.85)
        L_amid = _clamp(0.5 * (L_a1 + L_a2) + 0.02, 0.73, 0.85)

        acc_stops = [
            (L_a1, a1_target_C, h_a1),
            (L_amid, amid_C, h_amid),
            (L_a2, a2_target_C, h_a2),
        ]

    # Guard WCAG contrast on all 6 dark stops
    dark_rgbs = [oklch_to_srgb_gamut(*st) for st in (pill_stops + surf_stops)]
    text_lch = _ensure_contrast(text_lch, dark_rgbs, 9.5, lift=True)
    text_rgb = oklch_to_srgb_gamut(*text_lch)

    # If any dark stop fails 9.5 against text, gently compress that stop's L down while keeping order
    for group in (pill_stops, surf_stops):
        for i in range(len(group)):
            L, C, h = group[i]
            while wcag_contrast(text_rgb, oklch_to_srgb_gamut(L, C, h)) < 9.5 and L > 0.08:
                L -= 0.01
            group[i] = (L, C, h)
        # Preserve monotonic ramp L0 <= L1 <= L2
        for i in range(1, len(group)):
            if group[i][0] < group[i - 1][0] + 0.018:
                group[i] = (group[i - 1][0] + 0.018, group[i][1], group[i][2])

    # Ensure surfaceBg >= pillBg and surfaceRaised >= surfaceBg
    if surf_stops[0][0] < pill_stops[0][0] + 0.030:
        shift = (pill_stops[0][0] + 0.030) - surf_stops[0][0]
        surf_stops = [(L + shift, C, h) for (L, C, h) in surf_stops]
    if raised_lch[0] < surf_stops[0][0] + 0.040:
        raised_lch = (surf_stops[0][0] + 0.040, raised_lch[1], raised_lch[2])

    dark_rgbs = [oklch_to_srgb_gamut(*st) for st in (pill_stops + surf_stops)]
    acc_stops = [_ensure_contrast(st, dark_rgbs, 4.5, lift=True) for st in acc_stops]
    acc_stops, accent_fg_hex = _pick_accent_fg(acc_stops, base_h, is_mono, min_ratio=4.5)
    acc_stops = [_ensure_contrast(st, dark_rgbs, 4.5, lift=True) for st in acc_stops]
    _, accent_fg_hex = _pick_accent_fg(acc_stops, base_h, is_mono, min_ratio=4.5)

    p1, pm, p2 = (srgb_to_hex(oklch_to_srgb_gamut(*st)) for st in pill_stops)
    s1, sm, s2 = (srgb_to_hex(oklch_to_srgb_gamut(*st)) for st in surf_stops)
    raised_hex = srgb_to_hex(oklch_to_srgb_gamut(*raised_lch))
    border_hex = srgb_to_hex(oklch_to_srgb_gamut(*border_lch))
    text_hex = srgb_to_hex(text_rgb)
    a1, am, a2 = (srgb_to_hex(oklch_to_srgb_gamut(*st)) for st in acc_stops)

    refined_12 = [p1, pm, p2, s1, sm, s2, raised_hex, border_hex, a1, am, a2, text_hex]

    return {
        "ok": True,
        "mode": "Gradient",
        "monochrome": bool(is_mono),
        "extractedColors": extracted,
        "refinedPalette": refined_12,
        "palette": {
            "pillBg": p1,
            "pillBgMid": pm,
            "pillBg2": p2,
            "surfaceBg": s1,
            "surfaceBgMid": sm,
            "surfaceBg2": s2,
            "surfaceRaised": raised_hex,
            "text": text_hex,
            "borderColor": border_hex,
            "accent": a1,
            "accentMid": am,
            "accent2": a2,
            "accentFg": accent_fg_hex,
            "gradientAngle": angle,
            "shellGradientEnabled": True,
            "surfaceGradientEnabled": True,
            "accentGradientEnabled": True,
            "cardAlpha": 0.08 if is_mono else 0.09,
            "hoverAlpha": 0.14 if is_mono else 0.15,
            "borderAlpha": 0.15 if is_mono else 0.17,
        },
    }


def analyze_image(img: Image.Image, mode: str = "Solid") -> dict[str, Any]:
    norm_mode = "Gradient" if str(mode).strip().lower() == "gradient" else "Solid"
    small = _resize_fit(img, max_dim=96)
    w, h = small.size
    pixels = _rgb_pixels(small)
    angle = _compute_gradient_angle(w, h, pixels)
    points, stats = _bin_image_oklab(pixels)
    k = 12 if norm_mode == "Gradient" else 5
    clusters = _weighted_kmeans_oklab(points, k=k, max_iter=18)
    if norm_mode == "Gradient":
        return _build_gradient_palette(clusters, stats, angle)
    return _build_solid_palette(clusters, stats, angle)


def analyze_wallpaper(image_path: str | Path, mode: str = "Solid") -> dict[str, Any]:
    p = Path(image_path).expanduser()
    if not p.is_file():
        raise FileNotFoundError(f"Wallpaper image not found: {p}")
    img = _load_image_rgb(p)
    return analyze_image(img, mode=mode)


def main() -> int:
    parser = argparse.ArgumentParser(description="Analyze wallpaper and generate Paithosh adaptive palette")
    parser.add_argument("image", help="Path to wallpaper image")
    parser.add_argument("--mode", default="solid", choices=["solid", "gradient", "Solid", "Gradient"])
    args = parser.parse_args()

    try:
        res = analyze_wallpaper(args.image, mode=args.mode)
        print(json.dumps(res, separators=(",", ":")))
        return 0
    except Exception as exc:
        print(json.dumps({"ok": False, "error": str(exc)}, separators=(",", ":")))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
