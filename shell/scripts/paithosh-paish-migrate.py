#!/usr/bin/env python3
"""Standalone migrator converting Paithosh .paish v1 (PAISH1: / ';' raw) to v2 (paish:)."""

from __future__ import annotations

import argparse
import base64
import importlib.util
import re
import sys
from pathlib import Path
from typing import Any

# Load sibling paithosh-paish.py module (filename contains a hyphen)
_CODEC_PATH = Path(__file__).resolve().parent / "paithosh-paish.py"
_SPEC = importlib.util.spec_from_file_location("paithosh_paish", _CODEC_PATH)
assert _SPEC and _SPEC.loader
paish_v2 = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(paish_v2)


def _b64url_decode(s: str) -> str:
    padded = s.strip().replace("-", "+").replace("_", "/")
    rem = len(padded) % 4
    if rem:
        padded += "=" * (4 - rem)
    return base64.b64decode(padded.encode("ascii")).decode("utf-8")


def _clamp(val: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, val))


def decode_v1(raw_input: str, fallback_name: str = "") -> dict[str, Any]:
    raw = str(raw_input or "").strip()
    if raw.startswith("PAISH1:"):
        raw = _b64url_decode(raw[7:].rstrip("="))

    parts = raw.split(";")
    if len(parts) < 32:
        raise ValueError(f"Not a valid v1 paish string (expected >=32 fields, got {len(parts)})")

    lim = min(len(parts), 35)
    nums: list[float] = []
    for i in range(lim):
        nums.append(float(parts[i]))

    if round(nums[0]) != 1:
        raise ValueError(f"Expected v1 schema version 1, got {nums[0]}")

    rad_val = round(nums[3])
    island_rad = "12px" if rad_val <= 12 else ("18px" if rad_val <= 18 else "26px (Default)")

    hue = _clamp(nums[9], 0.0, 1.0)
    sat = _clamp(nums[10], 0.0, 1.0)
    val = _clamp(nums[11], 0.0, 1.0)
    has_explicit_custom = len(nums) >= 33

    def _opt_num(idx: int) -> float | None:
        if idx < len(parts):
            try:
                return float(parts[idx])
            except ValueError:
                return None
        return None

    profile_name = ""
    if len(parts) >= 36 and parts[35].strip():
        profile_name = parts[35].strip()
    elif fallback_name:
        profile_name = fallback_name

    c_style_n = _opt_num(36)
    c_size_n = _opt_num(37)
    c_mode_n = _opt_num(38)
    c_hex_raw = parts[39].strip().lower() if len(parts) >= 40 else ""
    c_blur_n = _opt_num(40)
    bar_pos_n = _opt_num(41)

    l_eff_n = _opt_num(42)
    l_snd_n = _opt_num(43)
    l_sil_n = _opt_num(44)
    l_sfx_n = _opt_num(45)
    l_snot_n = _opt_num(46)
    l_hnot_n = _opt_num(47)
    l_smed_n = _opt_num(48)
    l_salr_n = _opt_num(49)
    l_int_n = _opt_num(50)
    l_vol_n = _opt_num(51)
    l_dim_n = _opt_num(52)

    state: dict[str, Any] = {
        "presetName": paish_v2.PRESET_NAMES[int(_clamp(round(nums[1]), 0, len(paish_v2.PRESET_NAMES) - 1))],
        "globalSurfaceTheme": paish_v2.SURFACE_THEME_NAMES[
            int(_clamp(round(nums[2]), 0, len(paish_v2.SURFACE_THEME_NAMES) - 1))
        ],
        "islandCornerRadius": island_rad,
        "topEdgeOffset": nums[4] >= 0.5,
        "hideBarFullscreen": nums[5] >= 0.5,
        "autoHideOnOverlap": nums[6] >= 0.5,
        "activeBorderHighlight": nums[7] >= 0.5,
        "accentMode": "Gradient" if nums[8] >= 0.5 else "Solid",
        "hueVal": hue,
        "satVal": sat,
        "valVal": val,
        "gradientAngle": int(_clamp(round(nums[12]), 0, 360)),
        "gapsIn": int(_clamp(round(nums[13]), 0, 32)),
        "gapsOut": int(_clamp(round(nums[14]), 0, 48)),
        "borderSize": int(_clamp(round(nums[15]), 0, 6)),
        "layoutName": "master" if nums[16] >= 0.5 else "dwindle",
        "masterRatio": int(_clamp(round(nums[17]), 30, 80)),
        "preserveSplit": nums[18] >= 0.5,
        "cornerRounding": int(_clamp(round(nums[19]), 0, 28)),
        "shadowEnabled": nums[20] >= 0.5,
        "inactiveOpacity": _clamp(nums[21], 0.6, 1.0),
        "shadowRange": int(_clamp(round(nums[22]), 0, 48)),
        "animationsEnabled": nums[23] >= 0.5,
        "springStiffness": int(_clamp(round(nums[24]), 80, 600)),
        "springDamping": int(_clamp(round(nums[25]), 5, 60)),
        "blurEnabled": nums[26] >= 0.5,
        "blurSize": int(_clamp(round(nums[27]), 1, 24)),
        "blurPasses": int(_clamp(round(nums[28]), 1, 6)),
        "blurVibrancy": _clamp(nums[29], 0.0, 1.0),
        "customAccentActive": (nums[32] >= 0.5) if has_explicit_custom else (sat > 0.001 or abs(val - 0.92) > 0.01),
        "gooeyEnabled": (nums[33] >= 0.5) if len(nums) >= 34 else True,
        "speedMultiplier": _clamp(nums[34], 0.5, 2.5) if len(nums) >= 35 else 1.0,
        "profileName": profile_name,
        "cursorStyle": paish_v2.CURSOR_STYLES[int(_clamp(round(c_style_n), 0, len(paish_v2.CURSOR_STYLES) - 1))]
        if c_style_n is not None
        else "sharp",
        "cursorSize": int(_clamp(round(c_size_n), 16, 64)) if c_size_n is not None else 24,
        "cursorColorMode": paish_v2.CURSOR_COLOR_MODES[
            int(_clamp(round(c_mode_n), 0, len(paish_v2.CURSOR_COLOR_MODES) - 1))
        ]
        if c_mode_n is not None
        else "auto",
        "cursorFixedColor": f"#{c_hex_raw}" if re.fullmatch(r"[0-9a-f]{6}", c_hex_raw) else "#ffffff",
        "cursorMotionBlur": (c_blur_n >= 0.5) if c_blur_n is not None else False,
        "barPosition": ("bottom" if bar_pos_n >= 0.5 else "top") if bar_pos_n is not None else "top",
        "lockEffectPreset": paish_v2.LOCK_EFFECT_PRESETS[
            int(_clamp(round(l_eff_n), 0, len(paish_v2.LOCK_EFFECT_PRESETS) - 1))
        ]
        if l_eff_n is not None
        else "none",
        "lockAmbientSound": paish_v2.LOCK_AMBIENT_SOUNDS[
            int(_clamp(round(l_snd_n), 0, len(paish_v2.LOCK_AMBIENT_SOUNDS) - 1))
        ]
        if l_snd_n is not None
        else "wind",
        "lockSilentMode": (l_sil_n >= 0.5) if l_sil_n is not None else False,
        "lockSfxEnabled": (l_sfx_n >= 0.5) if l_sfx_n is not None else True,
        "lockShowNotifications": (l_snot_n >= 0.5) if l_snot_n is not None else True,
        "lockHideNotifContent": (l_hnot_n >= 0.5) if l_hnot_n is not None else False,
        "lockShowMedia": (l_smed_n >= 0.5) if l_smed_n is not None else True,
        "lockShowSystemAlerts": (l_salr_n >= 0.5) if l_salr_n is not None else True,
        "lockEffectIntensity": int(_clamp(round(l_int_n), 50, 150)) if l_int_n is not None else 100,
        "lockAmbientVolume": int(_clamp(round(l_vol_n), 5, 100)) if l_vol_n is not None else 35,
        "lockDimOpacity": int(_clamp(round(l_dim_n), 15, 75)) if l_dim_n is not None else 36,
    }
    return state


def migrate_string(raw_input: str, fallback_name: str = "") -> str:
    trimmed = raw_input.strip()
    if trimmed.startswith("paish:"):
        paish_v2.decode_code(trimmed)  # validate
        return trimmed
    state = decode_v1(trimmed, fallback_name=fallback_name)
    return paish_v2.encode_state(state)


def migrate_file(path: Path, dry_run: bool = False) -> str:
    content = path.read_text(encoding="utf-8").strip()
    if content.startswith("paish:"):
        paish_v2.decode_code(content)
        return "already-v2"
    v2_code = migrate_string(content, fallback_name=path.stem)
    if not dry_run:
        path.write_text(v2_code + "\n", encoding="utf-8")
    return v2_code


def _self_test() -> None:
    sample_raw = (
        "1;3;2;18;1;1;0;1;1;0.5;0.6;0.8;90;8;16;2;1;60;1;16;1;0.9;20;1;300;25;1;8;3;0.2;"
        "0;0;1;1;1.25;nord-custom;2;32;2;88c0d0;1"
    )
    b64 = base64.urlsafe_b64encode(sample_raw.encode("utf-8")).decode("ascii").rstrip("=")
    v1_code = f"PAISH1:{b64}"

    v2_from_raw = migrate_string(sample_raw)
    v2_from_code = migrate_string(v1_code)
    assert v2_from_raw == v2_from_code
    assert v2_from_code.startswith("paish:")

    decoded = paish_v2.decode_code(v2_from_code)
    assert decoded["version"] == 3
    assert decoded["presetName"] == "Nord Frost"
    assert decoded["globalSurfaceTheme"] == "Adaptive"
    assert decoded["islandCornerRadius"] == "18px"
    assert decoded["accentMode"] == "Gradient"
    assert decoded["layoutName"] == "master"
    assert decoded["masterRatio"] == 60
    assert decoded["cursorStyle"] == "wedge"
    assert decoded["cursorSize"] == 32
    assert decoded["cursorColorMode"] == "fixed"
    assert decoded["cursorFixedColor"] == "#88c0d0"
    assert decoded["cursorMotionBlur"] is True
    assert decoded["profileName"] == "nord-custom"

    print(f"OK (v1 {len(v1_code)} chars -> v2 {len(v2_from_code)} chars: {v2_from_code})")


def main() -> int:
    parser = argparse.ArgumentParser(description="Migrate Paithosh .paish v1 -> v2 (paish:)")
    parser.add_argument("files", nargs="*", help="Specific .paish files to migrate")
    parser.add_argument("--code", default=None, help="Convert a single v1 code string and print v2")
    parser.add_argument("--dir", dest="directory", default=None, help="Migrate all *.paish files in directory")
    parser.add_argument("--dry-run", action="store_true", help="Preview migration without writing files")
    parser.add_argument("--self-test", action="store_true", help="Run migration self-test")
    args = parser.parse_args()

    if args.self_test:
        _self_test()
        return 0

    if args.code is not None:
        print(migrate_string(args.code))
        return 0

    targets: list[Path] = [Path(f).expanduser() for f in args.files]
    if args.directory:
        d = Path(args.directory).expanduser()
        targets.extend(sorted(d.glob("*.paish")))
    elif not targets:
        default_dir = Path.home() / ".config" / "paithosh"
        if default_dir.is_dir():
            targets.extend(sorted(default_dir.glob("*.paish")))

    if not targets:
        print("No .paish files found to migrate.")
        return 0

    migrated = 0
    skipped = 0
    for p in targets:
        try:
            res = migrate_file(p, dry_run=args.dry_run)
            if res == "already-v2":
                skipped += 1
                print(f"[skip] {p.name} (already v2)")
            else:
                migrated += 1
                tag = "[dry-run]" if args.dry_run else "[migrated]"
                print(f"{tag} {p.name} -> {res}")
        except Exception as exc:
            print(f"[error] {p.name}: {exc}", file=sys.stderr)

    print(f"Done: {migrated} migrated, {skipped} already v2.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
