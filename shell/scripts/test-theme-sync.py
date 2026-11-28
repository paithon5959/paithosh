#!/usr/bin/env python3
"""Self-check suite for paithosh-theme-sync.py in an isolated temporary HOME."""

from __future__ import annotations

import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image


SCRIPT_DIR = Path(__file__).resolve().parent
SYNC_SCRIPT = SCRIPT_DIR / "paithosh-theme-sync.py"
WP_SCRIPT = SCRIPT_DIR / "paithosh-wallpaper-color.py"


def _load_sync_module():
    spec = importlib.util.spec_from_file_location("paithosh_theme_sync", SYNC_SCRIPT)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _run_sync(args: list[str], env: dict[str, str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SYNC_SCRIPT), *args],
        env=env,
        capture_output=True,
        text=True,
        check=True,
    )


def main() -> int:
    mod = _load_sync_module()

    with tempfile.TemporaryDirectory(prefix="paithosh-theme-sync-test-") as td:
        root = Path(td)
        cfg = root / ".config"
        data = root / ".local" / "share"
        hypr_cfg = cfg / "hypr" / "config"
        hypr_cfg.mkdir(parents=True)
        (cfg / "gtk-3.0").mkdir(parents=True)
        (cfg / "gtk-4.0").mkdir(parents=True)
        (cfg / "qt6ct").mkdir(parents=True)
        (cfg / "qt5ct").mkdir(parents=True)

        # Pre-seed existing user files that MUST be preserved across syncs
        (cfg / "gtk-3.0" / "gtk.css").write_text("@import 'colors.css';\n.user-keep { opacity: 0.99; }\n", encoding="utf-8")
        (cfg / "gtk-4.0" / "gtk.css").write_text("@import 'colors.css';\nwindow.user-keep { border-radius: 12px; }\n", encoding="utf-8")
        (cfg / "gtk-3.0" / "settings.ini").write_text(
            "[Settings]\ngtk-cursor-theme-name=paithosh-wedge\ngtk-font-name=Open Sans 11\ngtk-icon-theme-name=MacTahoe-dark\n",
            encoding="utf-8",
        )
        (cfg / "gtk-4.0" / "settings.ini").write_text(
            "[Settings]\ngtk-cursor-theme-name=paithosh-wedge\ngtk-font-name=Open Sans 11\n",
            encoding="utf-8",
        )
        (cfg / "qt6ct" / "qt6ct.conf").write_text(
            "[Appearance]\nicon_theme=MacTahoe-dark\nstyle=Breeze\n\n[Fonts]\ngeneral=\"Open Sans,11,-1,5,400,0,0,0,0,0\"\n",
            encoding="utf-8",
        )
        (cfg / "qt5ct" / "qt5ct.conf").write_text(
            "[Appearance]\nicon_theme=MacTahoe-dark\nstyle=Breeze\n",
            encoding="utf-8",
        )
        (cfg / "kdeglobals").write_text(
            "[General]\nfont=Open Sans,11,-1,5,400,0,0,0,0,0\n\n[Icons]\nTheme=MacTahoe-dark\n\n[KFileDialog Settings]\nShow hidden files=true\n",
            encoding="utf-8",
        )
        (hypr_cfg / "env.lua").write_text('hl.env("QT_IM_MODULE", "fcitx")\n', encoding="utf-8")

        env = os.environ.copy()
        env["HOME"] = str(root)
        env["XDG_CONFIG_HOME"] = str(cfg)
        env["XDG_DATA_HOME"] = str(data)

        # 1. OLED Pure preset -> black accentFg on white accent, idempotency, preservation
        _run_sync(["--preset", "OLED Pure", "--no-live"], env)
        _run_sync(["--preset", "OLED Pure", "--no-live"], env)

        gtk4_p = (cfg / "gtk-4.0" / "paithosh.css").read_text(encoding="utf-8")
        gtk3_p = (cfg / "gtk-3.0" / "paithosh.css").read_text(encoding="utf-8")
        assert "@define-color accent_bg_color #ffffff;" in gtk4_p
        assert "@define-color accent_fg_color #000000;" in gtk4_p
        assert "--accent-bg-color: #ffffff;" in gtk4_p
        assert "--accent-fg-color: #000000;" in gtk4_p
        assert "@define-color accent_bg_color #ffffff;" in gtk3_p
        assert "@define-color accent_fg_color #000000;" in gtk3_p
        assert "button.suggested-action:not(.flat)" in gtk3_p
        assert "switch:checked > slider" in gtk3_p
        assert "switch:checked > slider" in gtk4_p
        assert ":root" not in gtk3_p and "--accent-bg-color" not in gtk3_p

        gtk3_main = (cfg / "gtk-3.0" / "gtk.css").read_text(encoding="utf-8")
        gtk4_main = (cfg / "gtk-4.0" / "gtk.css").read_text(encoding="utf-8")
        assert ".user-keep" in gtk3_main and "@import 'colors.css';" in gtk3_main
        assert gtk3_main.count('paithosh.css') == 1 and gtk3_main.rstrip().endswith('@import url("paithosh.css");')
        assert gtk4_main.count('paithosh.css') == 1 and gtk4_main.rstrip().endswith('@import url("paithosh.css");')

        qt6_scheme = (cfg / "qt6ct" / "colors" / "paithosh.conf").read_text(encoding="utf-8")
        qt5_scheme = (cfg / "qt5ct" / "colors" / "paithosh.conf").read_text(encoding="utf-8")
        for line in qt6_scheme.splitlines():
            if "=" in line:
                vals = [v.strip() for v in line.split("=", 1)[1].split(",")]
                assert len(vals) == 22, f"Expected 22 colors in qt6ct, got {len(vals)}"
                assert all(re.match(r"^#[0-9a-f]{8}$", v) for v in vals), vals
        for line in qt5_scheme.splitlines():
            if "=" in line:
                vals = [v.strip() for v in line.split("=", 1)[1].split(",")]
                assert len(vals) == 21, f"Expected 21 colors in qt5ct, got {len(vals)}"
                assert all(re.match(r"^#[0-9a-f]{8}$", v) for v in vals), vals

        qt6_conf = (cfg / "qt6ct" / "qt6ct.conf").read_text(encoding="utf-8")
        assert "style=Breeze" in qt6_conf and "icon_theme=MacTahoe-dark" in qt6_conf and "[Fonts]" in qt6_conf
        assert "custom_palette=true" in qt6_conf
        expected_qt6_scheme = (
            str(data / "color-schemes" / "Paithosh.colors")
            if mod.qt6ct_supports_kcolorscheme()
            else str(cfg / "qt6ct" / "colors" / "paithosh.conf")
        )
        assert f"color_scheme_path={expected_qt6_scheme}" in qt6_conf, qt6_conf

        kde_txt = (cfg / "kdeglobals").read_text(encoding="utf-8")
        assert "Theme=MacTahoe-dark" in kde_txt and "Show hidden files=true" in kde_txt
        assert "ColorScheme=Paithosh" in kde_txt and "BackgroundNormal=11,11,12" in kde_txt
        assert "[Colors:Header][Inactive]" in kde_txt
        assert (data / "color-schemes" / "Paithosh.colors").is_file()

        env_lua = (hypr_cfg / "env.lua").read_text(encoding="utf-8")
        assert env_lua.count('hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")') == 1

        # 2. Nord Frost & Catppuccin Mocha presets
        _run_sync(["--preset", "Nord Frost", "--no-live"], env)
        assert "@define-color accent_bg_color #88c0d0;" in (cfg / "gtk-4.0" / "paithosh.css").read_text(encoding="utf-8")
        _run_sync(["--preset", "Catppuccin Mocha", "--no-live"], env)
        assert "@define-color accent_bg_color #cba6f7;" in (cfg / "gtk-3.0" / "paithosh.css").read_text(encoding="utf-8")
        assert "BackgroundNormal=203,166,247" in (cfg / "kdeglobals").read_text(encoding="utf-8")

        # 3. Real wallpaper-adaptive ("Adjust colors based on what you see") contract
        wp_png = root / "wp.png"
        img = Image.new("RGB", (64, 64), (20, 48, 72))
        for x in range(32, 64):
            for y in range(64):
                img.putpixel((x, y), (225, 110, 65))
        img.save(wp_png)
        wp_res = subprocess.run(
            [sys.executable, str(WP_SCRIPT), str(wp_png), "--mode", "gradient"],
            capture_output=True,
            text=True,
            check=True,
        )
        wp_data = json.loads(wp_res.stdout)
        assert wp_data.get("ok") and wp_data.get("palette")
        _run_sync(["--json", json.dumps(wp_data["palette"]), "--no-live"], env)
        acc = wp_data["palette"]["accent"].lower()
        assert f"--accent-bg-color: {acc};" in (cfg / "gtk-4.0" / "paithosh.css").read_text(encoding="utf-8")
        assert acc.lstrip("#") in (cfg / "qt6ct" / "colors" / "paithosh.conf").read_text(encoding="utf-8")

        # 4. Custom light palette detection
        light_payload = json.dumps({
            "pillBg": "#e8e8ed",
            "surfaceBg": "#f5f5f7",
            "surfaceRaised": "#ffffff",
            "text": "#111113",
            "accent": "#007aff",
            "accentFg": "#ffffff",
        })
        _run_sync(["--json", light_payload, "--no-live"], env)
        assert "gtk-application-prefer-dark-theme=false" in (cfg / "gtk-4.0" / "settings.ini").read_text(encoding="utf-8")
        assert "gtk-application-prefer-dark-theme=false" in (cfg / "gtk-3.0" / "settings.ini").read_text(encoding="utf-8")
        assert mod.nearest_gnome_accent("#007aff") == "blue"

        # 5. Live Qt6 offscreen verification with generated qt6ct config
        if shutil.which("kcalc"):
            qt_env = env.copy()
            qt_env["QT_QPA_PLATFORM"] = "offscreen"
            qt_env["QT_QPA_PLATFORMTHEME"] = "qt6ct"
            qt_env["QT_LOGGING_RULES"] = "qt.qpa.theme*=true;qt6ct*=true"
            p = subprocess.run(["kcalc", "--version"], env=qt_env, capture_output=True, text=True, timeout=5)
            assert p.returncode == 0, p.stderr
            assert 'Successfully created platform theme "qt6ct"' in p.stderr or "qt6ct: using qt6ct plugin" in p.stderr, p.stderr

    print("PASS: paithosh-theme-sync verified (presets, Adjust Colors, light mode, preservation, qt6ct/qt5ct/KDE)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
