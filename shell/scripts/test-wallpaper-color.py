#!/usr/bin/env python3
"""Automated + visual color-matching test suite for Paithosh wallpaper color engine."""

from __future__ import annotations

import argparse
import importlib.util
import math
import sys
import time
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw, ImageFont

_SCRIPT_DIR = Path(__file__).resolve().parent
_MOD_PATH = _SCRIPT_DIR / "paithosh-wallpaper-color.py"
_SPEC = importlib.util.spec_from_file_location("paithosh_wallpaper_color", _MOD_PATH)
assert _SPEC and _SPEC.loader
wpc = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(wpc)


def _oklab_of_hex(hx: str) -> tuple[float, float, float]:
    return wpc.rgb_to_oklab(*wpc.hex_to_rgb(hx))


def _oklch_of_hex(hx: str) -> tuple[float, float, float]:
    return wpc.oklab_to_oklch(*_oklab_of_hex(hx))


def _make_gradient_img(w: int, h: int, c_tl: tuple[int, int, int], c_tr: tuple[int, int, int], c_bl: tuple[int, int, int], c_br: tuple[int, int, int]) -> Image.Image:
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        ty = y / max(1, h - 1)
        for x in range(w):
            tx = x / max(1, w - 1)
            r = int(round((1 - ty) * ((1 - tx) * c_tl[0] + tx * c_tr[0]) + ty * ((1 - tx) * c_bl[0] + tx * c_br[0])))
            g = int(round((1 - ty) * ((1 - tx) * c_tl[1] + tx * c_tr[1]) + ty * ((1 - tx) * c_bl[1] + tx * c_br[1])))
            b = int(round((1 - ty) * ((1 - tx) * c_tl[2] + tx * c_tr[2]) + ty * ((1 - tx) * c_bl[2] + tx * c_br[2])))
            px[x, y] = (r, g, b)
    return img


def _synthetic_wallpapers() -> list[tuple[str, Image.Image, float | None]]:
    """Return [(name, PIL.Image, expected_dominant_hue_deg_or_None), ...]."""
    cases: list[tuple[str, Image.Image, float | None]] = []

    # 1. oled-dark: deep black/navy night sky with tiny stars
    oled = _make_gradient_img(192, 108, (4, 6, 14), (8, 12, 24), (2, 3, 7), (10, 14, 28))
    d = ImageDraw.Draw(oled)
    for sx, sy, col in [(30, 22, (165, 190, 245)), (96, 38, (220, 232, 255)), (150, 18, (140, 175, 240)), (62, 74, (190, 205, 235))]:
        d.ellipse((sx - 1, sy - 1, sx + 1, sy + 1), fill=col)
    cases.append(("synth:oled-dark", oled, None))

    # 2. bright-snow: high-key snowy peaks / ice sky
    snow = _make_gradient_img(192, 108, (226, 238, 250), (244, 248, 255), (202, 220, 238), (235, 242, 250))
    d = ImageDraw.Draw(snow)
    d.polygon([(0, 108), (58, 58), (118, 108)], fill=(182, 204, 226))
    d.polygon([(70, 108), (138, 50), (192, 108)], fill=(166, 192, 220))
    cases.append(("synth:bright-snow", snow, None))

    # 3. monochrome-bw: pure neutral grayscale gradient + geometric blocks
    bw = _make_gradient_img(192, 108, (18, 18, 18), (95, 95, 95), (36, 36, 36), (225, 225, 225))
    d = ImageDraw.Draw(bw)
    d.rectangle((24, 24, 72, 82), fill=(150, 150, 150))
    d.ellipse((110, 30, 158, 78), fill=(52, 52, 52))
    cases.append(("synth:monochrome-bw", bw, None))

    # 4. warm-sunset: deep indigo top -> crimson -> golden amber horizon
    sunset = _make_gradient_img(192, 108, (32, 20, 58), (82, 28, 72), (210, 82, 42), (245, 168, 56))
    d = ImageDraw.Draw(sunset)
    d.ellipse((78, 44, 114, 80), fill=(255, 205, 90))
    d.rectangle((0, 84, 192, 108), fill=(24, 14, 34))
    _, _, sunset_h = wpc.oklab_to_oklch(*wpc.rgb_to_oklab(230 / 255.0, 118 / 255.0, 50 / 255.0))
    cases.append(("synth:warm-sunset", sunset, sunset_h))

    # 5. nord-ocean: arctic teal + slate blue + frost
    nord = _make_gradient_img(192, 108, (22, 34, 48), (36, 62, 82), (48, 105, 128), (118, 186, 202))
    d = ImageDraw.Draw(nord)
    d.polygon([(0, 108), (74, 54), (150, 108)], fill=(30, 48, 66))
    _, _, nord_h = wpc.oklab_to_oklch(*wpc.rgb_to_oklab(76 / 255.0, 152 / 255.0, 172 / 255.0))
    cases.append(("synth:nord-ocean", nord, nord_h))

    # 6. cyberpunk-dual: dark violet + neon magenta + electric cyan
    cyber = _make_gradient_img(192, 108, (14, 10, 28), (34, 14, 54), (18, 22, 44), (16, 48, 68))
    d = ImageDraw.Draw(cyber)
    d.rectangle((22, 24, 68, 92), fill=(232, 48, 168))
    d.rectangle((112, 30, 164, 92), fill=(42, 214, 238))
    d.rectangle((74, 50, 104, 98), fill=(156, 72, 242))
    cases.append(("synth:cyberpunk-dual", cyber, None))

    # 7. pastel-anime: soft sakura pink + lavender + warm cream
    pastel = _make_gradient_img(192, 108, (246, 198, 214), (218, 198, 246), (252, 232, 216), (240, 178, 202))
    d = ImageDraw.Draw(pastel)
    d.ellipse((50, 22, 142, 92), fill=(248, 174, 204))
    cases.append(("synth:pastel-anime", pastel, None))

    # 8. emerald-forest: deep moss + pine + warm sunlight rays
    forest = _make_gradient_img(192, 108, (14, 34, 24), (26, 68, 42), (18, 46, 30), (88, 154, 78))
    d = ImageDraw.Draw(forest)
    d.polygon([(80, 0), (132, 0), (164, 108), (112, 108)], fill=(124, 186, 94))
    _, _, forest_h = wpc.oklab_to_oklch(*wpc.rgb_to_oklab(76 / 255.0, 150 / 255.0, 74 / 255.0))
    cases.append(("synth:emerald-forest", forest, forest_h))

    # 9. solid-single-red: uniform single #b83232 image (degenerate input!)
    solid_red = Image.new("RGB", (192, 108), (0xB8, 0x32, 0x32))
    _, _, red_h = wpc.oklab_to_oklch(*wpc.rgb_to_oklab(0xB8 / 255.0, 0x32 / 255.0, 0x32 / 255.0))
    cases.append(("synth:solid-single-red", solid_red, red_h))

    return cases


def _real_wallpapers() -> list[tuple[str, Path]]:
    found: list[tuple[str, Path]] = []
    wp_dir = Path.home() / ".config" / "paithosh" / "wallpapers"
    exts = {".png", ".jpg", ".jpeg", ".webp"}
    if wp_dir.is_dir():
        for p in sorted(wp_dir.iterdir()):
            if p.is_file() and p.suffix.lower() in exts:
                found.append((f"real:{p.name}", p))
    default_asset = _SCRIPT_DIR.parent / "assets" / "wallpapers" / "default.png"
    if default_asset.is_file():
        found.append(("asset:default.png", default_asset))
    return found


def _assert_case(name: str, res_solid: dict[str, Any], res_grad: dict[str, Any], expected_hue: float | None, ms_solid: float, ms_grad: float) -> dict[str, float]:
    assert res_solid.get("ok") is True, f"{name} solid failed: {res_solid}"
    assert res_grad.get("ok") is True, f"{name} grad failed: {res_grad}"
    assert ms_solid < 250.0, f"{name} solid slow: {ms_solid:.1f}ms"
    assert ms_grad < 250.0, f"{name} grad slow: {ms_grad:.1f}ms"

    # Tone counts
    ext_s = res_solid["extractedColors"]
    ext_g = res_grad["extractedColors"]
    ref_g = res_grad["refinedPalette"]
    assert 3 <= len(ext_s) <= 5, f"{name} solid expected 3-5 extractedColors, got {len(ext_s)}: {ext_s}"
    assert 10 <= len(ext_g) <= 12, f"{name} grad expected 10-12 extractedColors, got {len(ext_g)}: {ext_g}"
    assert 10 <= len(ref_g) <= 12, f"{name} grad expected 10-12 refinedPalette, got {len(ref_g)}: {ref_g}"

    ps = res_solid["palette"]
    pg = res_grad["palette"]

    # Gradient flags
    assert ps["shellGradientEnabled"] is False and ps["surfaceGradientEnabled"] is False and ps["accentGradientEnabled"] is False
    assert pg["shellGradientEnabled"] is True and pg["surfaceGradientEnabled"] is True and pg["accentGradientEnabled"] is True
    assert 0 <= pg["gradientAngle"] <= 360

    metrics: dict[str, float] = {"min_text_cr": 99.0, "min_acc_cr": 99.0, "min_fg_cr": 99.0}

    for tag, pal in (("solid", ps), ("grad", pg)):
        text_rgb = wpc.hex_to_rgb(pal["text"])
        fg_rgb = wpc.hex_to_rgb(pal["accentFg"])
        bg_keys = ("pillBg", "pillBgMid", "pillBg2", "surfaceBg", "surfaceBgMid", "surfaceBg2")
        acc_keys = ("accent", "accentMid", "accent2")

        for bk in bg_keys:
            cr = wpc.wcag_contrast(text_rgb, wpc.hex_to_rgb(pal[bk]))
            metrics["min_text_cr"] = min(metrics["min_text_cr"], cr)
            assert cr >= 9.5, f"{name} [{tag}] text vs {bk} contrast {cr:.2f} < 9.5 ({pal['text']} on {pal[bk]})"

        for ak in acc_keys:
            acc_rgb = wpc.hex_to_rgb(pal[ak])
            for bk in ("pillBg", "surfaceBg"):
                cr_bg = wpc.wcag_contrast(acc_rgb, wpc.hex_to_rgb(pal[bk]))
                metrics["min_acc_cr"] = min(metrics["min_acc_cr"], cr_bg)
                assert cr_bg >= 4.5, f"{name} [{tag}] {ak} vs {bk} contrast {cr_bg:.2f} < 4.5 ({pal[ak]} on {pal[bk]})"
            cr_fg = wpc.wcag_contrast(fg_rgb, acc_rgb)
            metrics["min_fg_cr"] = min(metrics["min_fg_cr"], cr_fg)
            assert cr_fg >= 4.5, f"{name} [{tag}] accentFg vs {ak} contrast {cr_fg:.2f} < 4.5 ({pal['accentFg']} on {pal[ak]})"

        # Monotonic elevation ladder
        l_pill = _oklab_of_hex(pal["pillBg"])[0]
        l_surf = _oklab_of_hex(pal["surfaceBg"])[0]
        l_rais = _oklab_of_hex(pal["surfaceRaised"])[0]
        assert l_pill <= l_surf <= l_rais, f"{name} [{tag}] elevation non-monotonic: {l_pill:.3f}, {l_surf:.3f}, {l_rais:.3f}"

    # Monochrome restraint
    if name == "synth:monochrome-bw":
        for tag, pal in (("solid", ps), ("grad", pg)):
            assert _oklch_of_hex(pal["pillBg"])[1] < 0.02, f"{name} [{tag}] pillBg not restrained"
            assert _oklch_of_hex(pal["accent"])[1] < 0.03, f"{name} [{tag}] accent not restrained"

    # Hue fidelity on clear chromatic benchmarks
    if expected_hue is not None:
        _, _, h_acc = _oklch_of_hex(ps["accent"])
        _, _, h_pill = _oklch_of_hex(ps["pillBg"])
        hd_min = min(wpc.hue_diff_deg(h_acc, expected_hue), wpc.hue_diff_deg(h_pill, expected_hue))
        assert hd_min <= 45.0, f"{name} hue drift {hd_min:.1f} deg > 45 deg (expected ~{expected_hue:.1f}, got acc={h_acc:.1f}, pill={h_pill:.1f})"

    # Gradient stop perceptual smoothness
    for a, b in (("pillBg", "pillBgMid"), ("pillBgMid", "pillBg2"), ("surfaceBg", "surfaceBgMid"), ("surfaceBgMid", "surfaceBg2")):
        de = wpc.oklab_dist(_oklab_of_hex(pg[a]), _oklab_of_hex(pg[b]))
        assert de <= 0.16, f"{name} grad jump {a}->{b} too large: {de:.3f}"
    for a, b in (("accent", "accentMid"), ("accentMid", "accent2")):
        de = wpc.oklab_dist(_oklab_of_hex(pg[a]), _oklab_of_hex(pg[b]))
        assert de <= 0.24, f"{name} grad accent jump {a}->{b} too large: {de:.3f}"

    return metrics


def _lerp_rgb(c1: tuple[float, float, float], c2: tuple[float, float, float], c3: tuple[float, float, float], t: float) -> tuple[int, int, int]:
    omt = 1.0 - t
    r = int(round(wpc._clamp(omt * omt * c1[0] + 2 * omt * t * c2[0] + t * t * c3[0], 0.0, 1.0) * 255))
    g = int(round(wpc._clamp(omt * omt * c1[1] + 2 * omt * t * c2[1] + t * t * c3[1], 0.0, 1.0) * 255))
    b = int(round(wpc._clamp(omt * omt * c1[2] + 2 * omt * t * c2[2] + t * t * c3[2], 0.0, 1.0) * 255))
    return (r, g, b)


def _render_contact_sheet(rows: list[dict[str, Any]], out_path: Path) -> None:
    row_h = 112
    pad = 16
    width = 1280
    height = 68 + len(rows) * row_h + pad
    canvas = Image.new("RGB", (width, height), (11, 11, 12))
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.load_default()

    draw.text((pad, 18), "Paithosh Adaptive Wallpaper Color Suite — Solid (3-5) & Gradient (10-12) Verification", fill=(255, 255, 255), font=font)
    draw.text((pad, 38), "Columns: Wallpaper | Solid 3-5 Extracted | Solid Mini-UI | Gradient 10-12 Refined | Gradient 3-Stop Mini-UI | WCAG Ratios", fill=(168, 174, 184), font=font)

    for idx, row in enumerate(rows):
        y0 = 64 + idx * row_h
        draw.rounded_rectangle((pad, y0, width - pad, y0 + row_h - 10), radius=10, fill=(18, 19, 22), outline=(42, 45, 52), width=1)

        # Thumbnail
        thumb = row["img"].convert("RGB").resize((128, 72), Image.Resampling.BILINEAR)
        canvas.paste(thumb, (pad + 10, y0 + 10))
        label = row["name"][:22]
        draw.text((pad + 10, y0 + 85), label, fill=(228, 232, 238), font=font)

        # Solid 3-5 extracted swatches
        sx = pad + 150
        ext_s = row["solid"]["extractedColors"]
        for ci, hx in enumerate(ext_s):
            draw.rounded_rectangle((sx + ci * 26, y0 + 14, sx + ci * 26 + 22, y0 + 48), radius=5, fill=hx, outline=(60, 64, 72))
        draw.text((sx, y0 + 56), f"Solid: {len(ext_s)} colors", fill=(160, 166, 176), font=font)

        # Solid mini UI card
        ps = row["solid"]["palette"]
        mx = sx + 142
        draw.rounded_rectangle((mx, y0 + 12, mx + 178, y0 + 86), radius=8, fill=ps["surfaceBg"], outline=ps["borderColor"])
        draw.rounded_rectangle((mx + 8, y0 + 18, mx + 170, y0 + 42), radius=8, fill=ps["pillBg"])
        draw.text((mx + 16, y0 + 25), "Island", fill=ps["text"], font=font)
        draw.rounded_rectangle((mx + 106, y0 + 22, mx + 162, y0 + 38), radius=6, fill=ps["accent"])
        draw.text((mx + 114, y0 + 25), "Focus", fill=ps["accentFg"], font=font)
        draw.rounded_rectangle((mx + 8, y0 + 49, mx + 170, y0 + 78), radius=6, fill=ps["surfaceRaised"])
        draw.text((mx + 16, y0 + 58), f"{ps['pillBg']} -> {ps['accent']}", fill=ps["text"], font=font)

        # Gradient 10-12 refined spectrum
        gx = mx + 194
        ref_g = row["grad"]["refinedPalette"]
        sw_w = max(14, int(236 / max(1, len(ref_g))))
        for ci, hx in enumerate(ref_g):
            x1 = gx + ci * (sw_w + 2)
            draw.rounded_rectangle((x1, y0 + 14, x1 + sw_w, y0 + 48), radius=4, fill=hx, outline=(52, 56, 64))
        draw.text((gx, y0 + 56), f"Grad: {len(ref_g)} refined @ {row['grad']['palette']['gradientAngle']}deg", fill=(160, 166, 176), font=font)

        # Gradient 3-stop mini UI card
        pg = row["grad"]["palette"]
        ux = gx + 258
        s1, sm, s2 = wpc.hex_to_rgb(pg["surfaceBg"]), wpc.hex_to_rgb(pg["surfaceBgMid"]), wpc.hex_to_rgb(pg["surfaceBg2"])
        for px_i in range(180):
            col = _lerp_rgb(s1, sm, s2, px_i / 179.0)
            draw.line((ux + px_i, y0 + 14, ux + px_i, y0 + 84), fill=col)
        draw.rounded_rectangle((ux, y0 + 12, ux + 180, y0 + 86), radius=8, outline=pg["borderColor"], width=1)

        p1, pm, p2 = wpc.hex_to_rgb(pg["pillBg"]), wpc.hex_to_rgb(pg["pillBgMid"]), wpc.hex_to_rgb(pg["pillBg2"])
        for px_i in range(160):
            col = _lerp_rgb(p1, pm, p2, px_i / 159.0)
            draw.line((ux + 10 + px_i, y0 + 20, ux + 10 + px_i, y0 + 42), fill=col)
        draw.text((ux + 16, y0 + 25), "3-Stop", fill=pg["text"], font=font)

        a1, am, a2 = wpc.hex_to_rgb(pg["accent"]), wpc.hex_to_rgb(pg["accentMid"]), wpc.hex_to_rgb(pg["accent2"])
        for px_i in range(74):
            col = _lerp_rgb(a1, am, a2, px_i / 73.0)
            draw.line((ux + 92 + px_i, y0 + 22, ux + 92 + px_i, y0 + 38), fill=col)
        draw.text((ux + 102, y0 + 25), "Accent", fill=pg["accentFg"], font=font)
        draw.rounded_rectangle((ux + 10, y0 + 50, ux + 170, y0 + 78), radius=6, fill=pg["surfaceRaised"])
        draw.text((ux + 16, y0 + 58), f"{pg['accent']} -> {pg['accent2']}", fill=pg["text"], font=font)

        # Contrast badge
        m = row["metrics"]
        cx = ux + 192
        draw.text((cx, y0 + 20), f"Txt CR: {m['min_text_cr']:.1f}:1", fill=(48, 209, 88), font=font)
        draw.text((cx, y0 + 38), f"Acc CR: {m['min_acc_cr']:.1f}:1", fill=(48, 209, 88), font=font)
        draw.text((cx, y0 + 56), f"Ink CR: {m['min_fg_cr']:.1f}:1", fill=(48, 209, 88), font=font)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out_path)


def main() -> int:
    parser = argparse.ArgumentParser(description="Test Paithosh wallpaper color matching suite")
    parser.add_argument("--render-sheet", default=None, help="Optional PNG path for visual contact sheet")
    args = parser.parse_args()

    sheet_rows: list[dict[str, Any]] = []

    for name, img, expected_hue in _synthetic_wallpapers():
        t0 = time.perf_counter()
        res_s = wpc.analyze_image(img, mode="Solid")
        ms_s = (time.perf_counter() - t0) * 1000.0

        t1 = time.perf_counter()
        res_g = wpc.analyze_image(img, mode="Gradient")
        ms_g = (time.perf_counter() - t1) * 1000.0

        # Determinism check
        res_s2 = wpc.analyze_image(img, mode="Solid")
        res_g2 = wpc.analyze_image(img, mode="Gradient")
        assert res_s["palette"] == res_s2["palette"], f"{name} solid non-deterministic!"
        assert res_g["palette"] == res_g2["palette"], f"{name} grad non-deterministic!"

        metrics = _assert_case(name, res_s, res_g, expected_hue, ms_s, ms_g)
        print(
            f"PASS {name:<24} | Solid({len(res_s['extractedColors'])}): {ms_s:5.1f}ms | "
            f"Grad({len(res_g['refinedPalette'])}): {ms_g:5.1f}ms | "
            f"CR txt={metrics['min_text_cr']:.1f} acc={metrics['min_acc_cr']:.1f} ink={metrics['min_fg_cr']:.1f}"
        )
        sheet_rows.append({"name": name, "img": img, "solid": res_s, "grad": res_g, "metrics": metrics})

    for name, path in _real_wallpapers():
        t0 = time.perf_counter()
        res_s = wpc.analyze_wallpaper(path, mode="Solid")
        ms_s = (time.perf_counter() - t0) * 1000.0

        t1 = time.perf_counter()
        res_g = wpc.analyze_wallpaper(path, mode="Gradient")
        ms_g = (time.perf_counter() - t1) * 1000.0

        res_s2 = wpc.analyze_wallpaper(path, mode="Solid")
        assert res_s["palette"] == res_s2["palette"], f"{name} solid non-deterministic!"

        metrics = _assert_case(name, res_s, res_g, None, ms_s, ms_g)
        print(
            f"PASS {name:<24} | Solid({len(res_s['extractedColors'])}): {ms_s:5.1f}ms | "
            f"Grad({len(res_g['refinedPalette'])}): {ms_g:5.1f}ms | "
            f"CR txt={metrics['min_text_cr']:.1f} acc={metrics['min_acc_cr']:.1f} ink={metrics['min_fg_cr']:.1f}"
        )
        with Image.open(path) as im:
            sheet_rows.append({"name": name, "img": im.convert("RGB"), "solid": res_s, "grad": res_g, "metrics": metrics})

    if args.render_sheet:
        out_p = Path(args.render_sheet)
        _render_contact_sheet(sheet_rows, out_p)
        print(f"Rendered contact sheet: {out_p} ({len(sheet_rows)} wallpapers)")

    print(f"ALL OK ({len(sheet_rows)} wallpapers x 2 modes verified)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
