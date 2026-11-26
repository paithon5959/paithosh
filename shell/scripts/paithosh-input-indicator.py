#!/usr/bin/env python3
"""Paithosh Input Indicator daemon & fcitx5 popup helper.

Monitors Caps Lock LED state and Fcitx5 active input method, emitting
newline-delimited JSON events to stdout whenever either changes.

Usage:
  paithosh-input-indicator.py watch [--caps 1|0] [--fcitx 1|0]
  paithosh-input-indicator.py set-fcitx-popup <true|false>
"""

import argparse
import glob
import json
import os
import re
import signal
import subprocess
import sys
import time

try:
    import dbus
except ImportError:
    dbus = None


FCITX_CONFIG_PATH = os.path.expanduser("~/.config/fcitx5/config")

# Friendly display mapping for common fcitx5 input methods
IM_DISPLAY_MAP = {
    "keyboard-us": ("English", "EN", False),
    "keyboard-us-intl": ("English Intl", "EN", False),
    "keyboard-gb": ("English UK", "EN", False),
    "unikey": ("Unikey", "VI", True),
    "bamboo": ("Bamboo", "VI", True),
    "mozc": ("Mozc", "JA", True),
    "anthy": ("Anthy", "JA", True),
    "pinyin": ("Pinyin", "ZH", True),
    "rime": ("Rime", "ZH", True),
    "hangul": ("Hangul", "KO", True),
}


def read_capslock() -> bool:
    """Return True if any keyboard capslock LED reports brightness > 0."""
    paths = glob.glob("/sys/class/leds/*::capslock/brightness")
    for p in paths:
        try:
            with open(p, "r", encoding="utf-8") as f:
                if f.read().strip() == "1":
                    return True
        except OSError:
            continue
    return False


def format_im_info(im_name: str, native_name: str = "", lang_code: str = ""):
    """Return (label, badge, active_accent) for an fcitx5 input method."""
    if not im_name:
        return ("Keyboard", "EN", False)

    if im_name in IM_DISPLAY_MAP:
        return IM_DISPLAY_MAP[im_name]

    if im_name.startswith("keyboard-"):
        code = im_name.split("-", 1)[1].split("-")[0].upper()[:2]
        label = native_name if native_name else f"Keyboard ({code})"
        # Shorten "Keyboard - English (US)" -> "English (US)"
        if label.startswith("Keyboard - "):
            label = label[len("Keyboard - "):]
        return (label, code or "EN", code != "EN" and code != "US")

    badge = (lang_code or im_name[:2]).upper()[:2]
    label = native_name if native_name else im_name.capitalize()
    return (label, badge, True)


class FcitxClient:
    def __init__(self):
        self._bus = None
        self._ctrl = None
        self._last_retry = 0.0

    def _connect(self):
        if dbus is None:
            return False
        now = time.monotonic()
        if self._ctrl is not None:
            return True
        if now - self._last_retry < 2.0:
            return False
        self._last_retry = now
        try:
            if self._bus is None:
                self._bus = dbus.SessionBus()
            obj = self._bus.get_object("org.fcitx.Fcitx5", "/controller")
            self._ctrl = dbus.Interface(obj, "org.fcitx.Fcitx.Controller1")
            return True
        except Exception:
            self._ctrl = None
            return False

    def get_current_im(self):
        """Return (im_name, native_name, lang_code) or None if unavailable."""
        if not self._connect():
            return None
        try:
            info = self._ctrl.CurrentInputMethodInfo()
            # Signature: sssssssbsa{sv}
            # (uniqueName, name, nativeName, icon, label, langCode, ...)
            im_name = str(info[0]) if len(info) > 0 else ""
            name = str(info[1]) if len(info) > 1 else ""
            native_name = str(info[2]) if len(info) > 2 else ""
            lang_code = str(info[5]) if len(info) > 5 else ""
            return (im_name, native_name or name, lang_code)
        except Exception:
            self._ctrl = None
            return None

    def reload_config(self):
        if self._connect():
            try:
                self._ctrl.ReloadConfig()
                return True
            except Exception:
                self._ctrl = None
        try:
            subprocess.run(
                ["fcitx5-remote", "-r"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=2,
                check=False,
            )
            return True
        except Exception:
            return False


def set_fcitx_popup(show: bool) -> int:
    """Set ShowInputMethodInformation=True|False in ~/.config/fcitx5/config and reload.

    When hiding the default popup (show=False), also upgrade ShareInputState=No
    to ShareInputState=All so switching windows/workspaces does not unexpectedly
    flip the input method on users with default Fcitx5 configs.
    """
    value_str = "True" if show else "False"
    cfg_dir = os.path.dirname(FCITX_CONFIG_PATH)
    os.makedirs(cfg_dir, exist_ok=True)

    lines = []
    if os.path.exists(FCITX_CONFIG_PATH):
        with open(FCITX_CONFIG_PATH, "r", encoding="utf-8") as f:
            lines = f.readlines()

    changed = False
    found_key = False
    found_share = False
    in_behavior = False
    behavior_idx = -1

    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            in_behavior = (stripped == "[Behavior]")
            if in_behavior:
                behavior_idx = i
            continue
        if in_behavior and re.match(r"^ShowInputMethodInformation\s*=", stripped):
            found_key = True
            new_line = f"ShowInputMethodInformation={value_str}\n"
            if line != new_line:
                lines[i] = new_line
                changed = True
        elif in_behavior and re.match(r"^ShareInputState\s*=", stripped):
            found_share = True
            if not show and re.match(r"^ShareInputState\s*=\s*No\s*$", stripped, re.IGNORECASE):
                lines[i] = "ShareInputState=All\n"
                changed = True

    if not found_key:
        if behavior_idx >= 0:
            lines.insert(behavior_idx + 1, f"ShowInputMethodInformation={value_str}\n")
        else:
            if lines and not lines[-1].endswith("\n"):
                lines[-1] += "\n"
            lines.append("\n[Behavior]\n")
            lines.append(f"ShowInputMethodInformation={value_str}\n")
            behavior_idx = len(lines) - 2
        changed = True

    if not show and not found_share:
        if behavior_idx >= 0:
            lines.insert(behavior_idx + 1, "ShareInputState=All\n")
        else:
            lines.append("ShareInputState=All\n")
        changed = True

    if changed:
        tmp_path = FCITX_CONFIG_PATH + ".paithosh.tmp"
        with open(tmp_path, "w", encoding="utf-8") as f:
            f.writelines(lines)
        os.replace(tmp_path, FCITX_CONFIG_PATH)

    client = FcitxClient()
    client.reload_config()
    return 0


def emit(payload: dict):
    sys.stdout.write(json.dumps(payload, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def watch_loop(watch_caps: bool, watch_fcitx: bool):
    running = True

    def _stop(_sig, _frame):
        nonlocal running
        running = False

    signal.signal(signal.SIGTERM, _stop)
    signal.signal(signal.SIGINT, _stop)

    fcitx = FcitxClient() if watch_fcitx else None

    last_caps = read_capslock() if watch_caps else None
    last_im = None
    if fcitx is not None:
        info = fcitx.get_current_im()
        if info is not None:
            last_im = info[0]

    while running:
        time.sleep(0.14)
        if not running:
            break

        if watch_caps:
            cur_caps = read_capslock()
            if cur_caps != last_caps:
                last_caps = cur_caps
                emit({
                    "kind": "capslock",
                    "label": "Caps Lock",
                    "badge": "ON" if cur_caps else "OFF",
                    "active": cur_caps,
                })

        if fcitx is not None:
            info = fcitx.get_current_im()
            if info is not None:
                im_name, native_name, lang_code = info
                if last_im is None:
                    last_im = im_name
                elif im_name != last_im:
                    last_im = im_name
                    label, badge, active = format_im_info(im_name, native_name, lang_code)
                    emit({
                        "kind": "fcitx",
                        "im": im_name,
                        "label": label,
                        "badge": badge,
                        "active": active,
                    })

    return 0


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_watch = sub.add_parser("watch")
    p_watch.add_argument("--caps", type=int, default=1)
    p_watch.add_argument("--fcitx", type=int, default=1)

    p_popup = sub.add_parser("set-fcitx-popup")
    p_popup.add_argument("state", choices=["true", "false"])

    args = parser.parse_args()
    if args.cmd == "set-fcitx-popup":
        return set_fcitx_popup(args.state == "true")
    if args.cmd == "watch":
        return watch_loop(bool(args.caps), bool(args.fcitx))
    return 0


if __name__ == "__main__":
    sys.exit(main())
