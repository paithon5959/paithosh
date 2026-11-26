#!/usr/bin/env python3
"""Lightweight Discord Rich Presence daemon for Paithosh shell.

Uses only the Python standard library to talk to Discord's local IPC socket
(`discord-ipc-0`..`9`), automatically detects when Discord starts or stops,
and supports instant live config updates over stdin + JSON persistence.
"""

from __future__ import annotations

import argparse
import datetime
import json
import os
import random
import select
import signal
import socket
import struct
import subprocess
import sys
import time
import uuid

DEFAULT_CLIENT_ID = "920711890211053579"
DEFAULT_CONFIG_PATH = os.path.expanduser("~/.config/paithosh/discord-rpc.json")

OP_HANDSHAKE = 0
OP_FRAME = 1
OP_CLOSE = 2

_running = True


def _handle_signal(_signum: int, _frame: object) -> None:
    global _running
    _running = False


signal.signal(signal.SIGTERM, _handle_signal)
signal.signal(signal.SIGINT, _handle_signal)


def emit(payload: dict) -> None:
    sys.stdout.write(json.dumps(payload, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def emit_status(discord_running: bool, connected: bool, details: str = "", state: str = "") -> None:
    emit({
        "type": "status",
        "discord_running": discord_running,
        "connected": connected,
        "details": details,
        "state": state,
    })


def load_config(path: str, defaults: dict) -> dict:
    cfg = dict(defaults)
    try:
        if os.path.isfile(path):
            with open(path, "r", encoding="utf-8") as f:
                saved = json.load(f)
            if isinstance(saved, dict):
                cfg.update(saved)
    except (OSError, ValueError):
        pass
    return cfg


def save_config(path: str, cfg: dict) -> None:
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(cfg, f, ensure_ascii=False, indent=2)
        os.replace(tmp, path)
    except OSError:
        pass


def find_ipc_sockets() -> list[str]:
    """Return candidate Discord IPC socket paths that currently exist."""
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    search_dirs = [
        runtime_dir,
        "/tmp",
        os.path.join(runtime_dir, "app", "com.discordapp.Discord"),
        os.path.join(runtime_dir, "app", "dev.vencord.Vesktop"),
        os.path.join(runtime_dir, "snap.discord"),
    ]
    found: list[str] = []
    for base in search_dirs:
        if not base or not os.path.isdir(base):
            continue
        for i in range(10):
            path = os.path.join(base, f"discord-ipc-{i}")
            if os.path.exists(path):
                found.append(path)
    return found


def send_packet(sock: socket.socket, opcode: int, payload: dict) -> None:
    data = json.dumps(payload).encode("utf-8")
    header = struct.pack("<II", opcode, len(data))
    sock.sendall(header + data)


def recv_packet(sock: socket.socket) -> tuple[int, dict]:
    header = b""
    while len(header) < 8:
        chunk = sock.recv(8 - len(header))
        if not chunk:
            raise ConnectionError("Discord IPC closed")
        header += chunk
    opcode, length = struct.unpack("<II", header)
    body = b""
    while len(body) < length:
        chunk = sock.recv(length - len(body))
        if not chunk:
            raise ConnectionError("Discord IPC closed")
        body += chunk
    return opcode, json.loads(body.decode("utf-8"))


def get_active_window() -> str:
    """Return the currently focused Hyprland window class/title, or empty string."""
    try:
        res = subprocess.run(
            ["hyprctl", "activewindow", "-j"],
            capture_output=True,
            text=True,
            timeout=0.5,
            check=False,
        )
        if res.returncode != 0 or not res.stdout.strip():
            return ""
        data = json.loads(res.stdout)
        cls = str(data.get("class") or data.get("initialClass") or "").strip()
        if cls:
            return cls[:28]
        title = str(data.get("title") or "").strip()
        return title[:28]
    except (OSError, ValueError, subprocess.SubprocessError):
        return ""


def get_system_uptime() -> str:
    """Read /proc/uptime and format as e.g. 'up 3h 42m'."""
    try:
        with open("/proc/uptime", "r", encoding="utf-8") as f:
            secs = int(float(f.read().split()[0]))
        days, rem = divmod(secs, 86400)
        hours, rem = divmod(rem, 3600)
        mins, _ = divmod(rem, 60)
        if days > 0:
            return f"up {days}d {hours}h"
        if hours > 0:
            return f"up {hours}h {mins}m"
        return f"up {mins}m"
    except (OSError, ValueError):
        return ""


def get_status_for_config(cfg: dict, last_pair: tuple[str, str] | None = None) -> tuple[str, str]:
    preset = str(cfg.get("preset", "auto"))
    theme = str(cfg.get("theme", "")).strip()
    show_theme = bool(cfg.get("showTheme", True))

    if preset == "custom":
        now_str = datetime.datetime.now().strftime("%H:%M")
        replacements = {
            "{window}": get_active_window() or "desktop",
            "{uptime}": get_system_uptime() or "up 0m",
            "{theme}": theme or "Paithosh",
            "{time}": now_str,
        }
        details = str(cfg.get("customDetails", "")).strip() or "Running Paithosh Shell"
        state = str(cfg.get("customState", "")).strip() or "Wayland • Hyprland"
        for k, v in replacements.items():
            details = details.replace(k, v)
            state = state.replace(k, v)
    elif preset == "larper":
        options = [
            ("Compiling kernel with -O3 -funroll-loops", "0.2ms bar latency verified"),
            ("Editing Hyprland dotfiles (again)", "Definitely productive right now"),
            ("I use Fedora btw", "Former KDE enjoyer in disguise"),
            ("Vibecoding a Wayland shell", "Zero bloat, maximum ego"),
            ("Tuning spring physics at 240Hz", "Peak Linux larper energy"),
            ("Inspecting /proc/meminfo for fun", "Minimalism is a lifestyle"),
        ]
        pool = [o for o in options if o != last_pair] or options
        details, state = random.choice(pool)
    elif preset == "satire":
        options = [
            ("Entirely vibecoded shell", "Built purely to mess around"),
            ("Poking fun at ricing ego", "Actually daily-driving KDE"),
            ("Maintaining this on pure whim", "PRs closed without comment"),
            ("Absurd personal DIY shell", "Fedora user, priorities shifted"),
        ]
        pool = [o for o in options if o != last_pair] or options
        details, state = random.choice(pool)
    elif preset == "minimal":
        details, state = "Paithosh Shell", "Wayland • Hyprland"
    elif preset == "music":
        m_title = str(cfg.get("musicTitle", "")).strip()
        m_artist = str(cfg.get("musicArtist", "")).strip()
        m_playing = bool(cfg.get("musicPlaying", False))
        m_source = str(cfg.get("musicSource", "")).strip()
        if m_title:
            prefix = "Listening to" if m_playing else "Paused:"
            details = f"{prefix} {m_title}"
            state = f"by {m_artist}" if m_artist else (f"via {m_source}" if m_source else "Paithosh Music")
        else:
            details, state = "Paithosh Music", "Idle • Ready to spin"
    elif preset == "dj":
        options = [
            ("Crate digging on Mixcloud", "Sidechain RMS ducking active"),
            ("Spinning DJ sets in Wayland", "Smooth audio ducking • Paithosh"),
            ("Vibing to Mixcloud streams", "Zero-latency media island"),
            ("Mixing beats on Hyprland", "Hybrid sidechain RMS audio"),
            ("Late night Mixcloud session", "Auto-ducking on notifications"),
        ]
        pool = [o for o in options if o != last_pair] or options
        details, state = random.choice(pool)
    else:
        hour = datetime.datetime.now().hour
        if 5 <= hour < 9:
            options = [
                ("Booting up the day", "Fresh Hyprland session"),
                ("Morning coffee & rice", "Paithosh Shell"),
                ("Early bird on Linux", "Ready to build"),
            ]
        elif 9 <= hour < 12:
            options = [
                ("In the zone", "Crafting on Hyprland"),
                ("Morning productivity", "Paithosh Shell"),
                ("Building cool things", "Wayland • Quickshell"),
            ]
        elif 12 <= hour < 14:
            options = [
                ("Lunch break mode", "BRB, refueling"),
                ("Recharging batteries", "Idle on Paithosh"),
            ]
        elif 14 <= hour < 18:
            options = [
                ("Deep work session", "Paithosh Shell"),
                ("Tweaking pixels & shaders", "Hyprland desktop"),
                ("Afternoon flow", "Wayland • Quickshell"),
            ]
        elif 18 <= hour < 22:
            options = [
                ("Evening chill", "Vibing on Linux"),
                ("Music & terminal", "Paithosh Shell"),
                ("Winding down", "Hyprland desktop"),
            ]
        elif 22 <= hour or hour < 1:
            options = [
                ("Night owl session", "Late night rice"),
                ("Quiet hours on Linux", "Paithosh Shell"),
            ]
        else:
            options = [
                ("3AM debugging energy", "Why does this work?"),
                ("Still awake on Hyprland", "Send coffee"),
            ]
        pool = [o for o in options if o != last_pair] or options
        details, state = random.choice(pool)

    if show_theme and theme and "{theme}" not in str(cfg.get("customState", "")):
        state = f"{state} • {theme}"
    return details, state


def set_activity(sock: socket.socket, start_ts: int, details: str, state: str, show_elapsed: bool) -> None:
    activity: dict = {
        "details": details,
        "state": state,
        "instance": False,
    }
    if show_elapsed:
        activity["timestamps"] = {"start": start_ts}
    payload = {
        "cmd": "SET_ACTIVITY",
        "args": {
            "pid": os.getpid(),
            "activity": activity,
        },
        "nonce": str(uuid.uuid4()),
    }
    send_packet(sock, OP_FRAME, payload)
    recv_packet(sock)


def poll_stdin_commands(timeout: float) -> list[dict]:
    """Wait up to `timeout` seconds for newline-delimited JSON commands on stdin."""
    cmds: list[dict] = []
    try:
        ready, _, _ = select.select([sys.stdin], [], [], timeout)
    except (OSError, ValueError):
        time.sleep(timeout)
        return cmds
    if not ready:
        return cmds
    line = sys.stdin.readline()
    if not line:
        return cmds
    line = line.strip()
    if not line:
        return cmds
    try:
        obj = json.loads(line)
        if isinstance(obj, dict):
            cmds.append(obj)
    except ValueError:
        pass
    return cmds


def main() -> int:
    parser = argparse.ArgumentParser(description="Paithosh Discord RPC daemon")
    parser.add_argument("--client-id", default="", help="Discord Application Client ID")
    parser.add_argument("--theme", default="", help="Optional active theme name")
    parser.add_argument("--config-file", default=DEFAULT_CONFIG_PATH, help="Path to persistent JSON config")
    parser.add_argument("--poll-interval", type=float, default=2.0, help="Seconds between Discord checks")
    args = parser.parse_args()

    defaults = {
        "enabled": True,
        "preset": "auto",
        "customDetails": "Compiling kernel with -O3",
        "customState": "I use Fedora btw",
        "showTheme": True,
        "showElapsed": True,
        "showActiveWindow": False,
        "showUptime": False,
        "updateInterval": 60,
        "clientId": os.environ.get("PAITHOSH_DISCORD_CLIENT_ID", DEFAULT_CLIENT_ID),
        "theme": args.theme,
    }
    cfg = load_config(args.config_file, defaults)
    if args.client_id:
        cfg["clientId"] = args.client_id
    if args.theme:
        cfg["theme"] = args.theme
    if not cfg.get("clientId"):
        cfg["clientId"] = DEFAULT_CLIENT_ID

    emit({"type": "config", "config": cfg})

    start_ts = int(time.time())
    last_discord_running: bool | None = None
    last_pair: tuple[str, str] | None = None

    while _running:
        # Process any pending stdin commands before connecting
        for cmd in poll_stdin_commands(0.05):
            if cmd.get("cmd") == "config" and isinstance(cmd.get("config"), dict):
                cfg.update(cmd["config"])
                if not cfg.get("clientId"):
                    cfg["clientId"] = DEFAULT_CLIENT_ID
                save_config(args.config_file, cfg)

        if not cfg.get("enabled", True):
            if last_discord_running is not False:
                emit_status(discord_running=False, connected=False)
                last_discord_running = False
            for cmd in poll_stdin_commands(args.poll_interval):
                if cmd.get("cmd") == "config" and isinstance(cmd.get("config"), dict):
                    cfg.update(cmd["config"])
                    if not cfg.get("clientId"):
                        cfg["clientId"] = DEFAULT_CLIENT_ID
                    save_config(args.config_file, cfg)
            continue

        sockets = find_ipc_sockets()
        if not sockets:
            if last_discord_running is not False:
                emit_status(discord_running=False, connected=False)
                last_discord_running = False
            for cmd in poll_stdin_commands(args.poll_interval):
                if cmd.get("cmd") == "config" and isinstance(cmd.get("config"), dict):
                    cfg.update(cmd["config"])
                    if not cfg.get("clientId"):
                        cfg["clientId"] = DEFAULT_CLIENT_ID
                    save_config(args.config_file, cfg)
            continue

        active_client_id = str(cfg.get("clientId") or DEFAULT_CLIENT_ID)
        sock: socket.socket | None = None
        connected = False
        for path in sockets:
            try:
                candidate = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                candidate.settimeout(5.0)
                candidate.connect(path)
                send_packet(candidate, OP_HANDSHAKE, {"v": 1, "client_id": active_client_id})
                recv_packet(candidate)
                sock = candidate
                connected = True
                break
            except OSError:
                try:
                    candidate.close()
                except OSError:
                    pass
                continue

        if not connected or sock is None:
            if last_discord_running is not False:
                emit_status(discord_running=False, connected=False)
                last_discord_running = False
            for cmd in poll_stdin_commands(args.poll_interval):
                if cmd.get("cmd") == "config" and isinstance(cmd.get("config"), dict):
                    cfg.update(cmd["config"])
                    if not cfg.get("clientId"):
                        cfg["clientId"] = DEFAULT_CLIENT_ID
                    save_config(args.config_file, cfg)
            continue

        last_discord_running = True
        try:
            force_update = True
            last_update = 0.0
            while _running:
                if not cfg.get("enabled", True):
                    break
                if str(cfg.get("clientId") or DEFAULT_CLIENT_ID) != active_client_id:
                    # Reconnect with new Client ID
                    break

                interval = max(15.0, float(cfg.get("updateInterval", 60)))
                now = time.time()
                if force_update or (now - last_update >= interval):
                    details, state = get_status_for_config(cfg, last_pair)
                    last_pair = (details, state)
                    set_activity(sock, start_ts, details, state, bool(cfg.get("showElapsed", True)))
                    emit_status(discord_running=True, connected=True, details=details, state=state)
                    last_update = now
                    force_update = False

                cmds = poll_stdin_commands(0.5)
                for cmd in cmds:
                    c = cmd.get("cmd")
                    if c == "config" and isinstance(cmd.get("config"), dict):
                        cfg.update(cmd["config"])
                        if not cfg.get("clientId"):
                            cfg["clientId"] = DEFAULT_CLIENT_ID
                        save_config(args.config_file, cfg)
                        force_update = True
                    elif c == "reroll":
                        force_update = True
        except (OSError, ConnectionError, ValueError):
            emit_status(discord_running=False, connected=False)
            last_discord_running = False
        finally:
            try:
                send_packet(sock, OP_CLOSE, {})
            except OSError:
                pass
            try:
                sock.close()
            except OSError:
                pass

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
