#!/usr/bin/env python3
"""Lightweight Mixcloud audio daemon for Paithosh shell.

Reads newline-delimited JSON commands from stdin, resolves Mixcloud audio
streams via yt-dlp, drives a headless mpv instance over its UNIX socket
JSON IPC, and provides a low-overhead Hybrid Sidechain RMS audio ducking
engine (pactl subscribe + 4kHz mono parec stream monitors) that ducks
smoothly only when external apps actually emit audible sound.
"""

from __future__ import annotations

import array
import atexit
import json
import math
import os
import re
import shutil
import signal
import socket
import subprocess
import sys
import threading
import time
from typing import Any


IGNORED_DUCK_APPS = {
    "paithosh-mixcloud",
    "pw-play",
    "pipewire-play",
    "paithosh-lock-ambient",
    "speech-dispatcher",
    "speech-dispatcher-dummy",
    "libcanberra",
    "canberra-gtk-play",
}

MAX_STREAM_MONITORS = 4
MONITOR_RATE = 4000          # 4kHz mono s16le = 8 KB/s (ultra-low CPU)
MONITOR_CHUNK_BYTES = 320    # 160 samples = 40ms per frame
RMS_THRESHOLD = 0.005        # ~ -46 dBFS (ignores digital silence & noise floor)


def _find_bin(name: str) -> str:
    found = shutil.which(name)
    if found:
        return found
    for extra in (
        os.path.expanduser(f"~/.local/bin/{name}"),
        f"/usr/local/bin/{name}",
        f"/usr/bin/{name}",
    ):
        if os.path.isfile(extra) and os.access(extra, os.X_OK):
            return extra
    return ""


def _detect_install_hint() -> str:
    try:
        if os.path.isfile("/etc/os-release"):
            with open("/etc/os-release", "r", encoding="utf-8") as f:
                data = f.read().lower()
            if "fedora" in data or "rhel" in data or "centos" in data:
                return "sudo dnf install -y mpv yt-dlp"
            if "arch" in data or "cachyos" in data or "endeavour" in data:
                return "sudo pacman -S --needed mpv yt-dlp"
    except OSError:
        pass
    return "sudo apt install -y mpv yt-dlp"


def _prettify_app_name(raw: str) -> str:
    s = (raw or "").strip()
    if not s:
        return "External Audio"
    low = s.lower()
    if "discord" in low or "vesktop" in low:
        return "Discord"
    if "firefox" in low:
        return "Firefox"
    if "zen" in low:
        return "Zen Browser"
    if "chromium" in low:
        return "Chromium"
    if "chrome" in low:
        return "Chrome"
    if "brave" in low:
        return "Brave"
    if "spotify" in low:
        return "Spotify"
    if "vlc" in low:
        return "VLC"
    return s[:28]


class _StreamMonitor:
    """Ultra-lightweight 4kHz mono RMS monitor for a single PipeWire sink-input."""

    def __init__(self, sink_input_id: str, label: str, parec_path: str, on_audio_cb: Any) -> None:
        self.sink_input_id = sink_input_id
        self.label = label
        self._parec_path = parec_path
        self._on_audio_cb = on_audio_cb
        self._stop_flag = False
        self._proc: subprocess.Popen[bytes] | None = None
        self.audible = False
        self.last_audible_ts = 0.0
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()

    def _run(self) -> None:
        try:
            proc = subprocess.Popen(
                [
                    self._parec_path,
                    f"--monitor-stream={self.sink_input_id}",
                    f"--rate={MONITOR_RATE}",
                    "--channels=1",
                    "--format=s16le",
                    "--latency-msec=40",
                ],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
            )
            self._proc = proc
            assert proc.stdout is not None
            while not self._stop_flag:
                chunk = proc.stdout.read(MONITOR_CHUNK_BYTES)
                if not chunk:
                    break
                n_samples = len(chunk) // 2
                if n_samples == 0:
                    continue
                samples = array.array("h")
                samples.frombytes(chunk[: n_samples * 2])
                # Fast RMS on 160 int16 samples (~12us)
                sum_sq = 0
                for s in samples:
                    sum_sq += s * s
                rms = math.sqrt(sum_sq / n_samples) / 32768.0
                now_audible = rms >= RMS_THRESHOLD
                if now_audible:
                    self.last_audible_ts = time.monotonic()
                if now_audible != self.audible:
                    self.audible = now_audible
                    self._on_audio_cb()
        except OSError:
            pass
        finally:
            self.audible = False
            self._terminate_proc()
            self._on_audio_cb()

    def _terminate_proc(self) -> None:
        proc = self._proc
        self._proc = None
        if proc is not None:
            try:
                if proc.poll() is None:
                    proc.terminate()
                    try:
                        proc.wait(timeout=0.5)
                    except subprocess.TimeoutExpired:
                        proc.kill()
            except OSError:
                pass

    def stop(self) -> None:
        self._stop_flag = True
        self._terminate_proc()


class MixcloudDaemon:
    def __init__(self) -> None:
        self._emit_lock = threading.Lock()
        self._state_lock = threading.Lock()
        self._ipc_write_lock = threading.Lock()
        self._running = True
        self._play_seq = 0
        self._active_seq = 0

        runtime_dir = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
        if not os.path.isdir(runtime_dir):
            runtime_dir = "/tmp"
        self._sock_path = os.path.join(runtime_dir, f"paithosh-mixcloud-{os.getpid()}.sock")

        self._mpv_proc: subprocess.Popen[bytes] | None = None
        self._ipc_sock: socket.socket | None = None
        self._ipc_thread: threading.Thread | None = None

        self._mpv_path = _find_bin("mpv")
        self._yt_dlp_path = _find_bin("yt-dlp")
        self._pactl_path = _find_bin("pactl")
        self._parec_path = _find_bin("parec")
        self._install_hint = _detect_install_hint()

        # Tracked mpv state
        self._state = "idle"  # idle | resolving | buffering | playing | paused | error
        self._position = 0.0
        self._duration = 0.0
        self._user_volume = 80
        self._muted = False
        self._paused = False
        self._paused_for_cache = False
        self._core_idle = True
        self._last_pos_emit = 0.0

        # Hybrid Sidechain RMS Audio Ducking state
        self._duck_lock = threading.Lock()
        self._duck_enabled = True
        self._duck_level = 0.24
        self._duck_attack_delay_s = 0.06   # 60ms snappy attack debounce (filters 1-frame pops)
        self._duck_release_hold_s = 0.32   # 320ms musical hold (bridges word gaps, releases fast)
        self._duck_down_s = 0.26           # 260ms smooth cosine duck-in
        self._duck_up_s = 0.52             # 520ms lush cosine restore

        self._duck_gain = 1.0
        self._duck_active = False
        self._duck_source = ""
        self._duck_ramp_seq = 0
        self._ext_audio_present = False
        self._ext_first_seen_ts = 0.0
        self._ext_last_seen_ts = 0.0

        self._monitors_lock = threading.Lock()
        self._monitors: dict[str, _StreamMonitor] = {}
        self._need_rescan = True

        self._pactl_sub_proc: subprocess.Popen[str] | None = None
        self._duck_eval_event = threading.Event()
        self._duck_threads_started = False

    def emit(self, payload: dict[str, Any]) -> None:
        line = json.dumps(payload, ensure_ascii=False) + "\n"
        with self._emit_lock:
            try:
                sys.stdout.write(line)
                sys.stdout.flush()
            except BrokenPipeError:
                self._running = False

    def emit_deps(self) -> None:
        self._mpv_path = _find_bin("mpv")
        self._yt_dlp_path = _find_bin("yt-dlp")
        self._pactl_path = _find_bin("pactl")
        self._parec_path = _find_bin("parec")
        self.emit({
            "type": "deps",
            "mpv": bool(self._mpv_path),
            "yt_dlp": bool(self._yt_dlp_path),
            "mpv_path": self._mpv_path,
            "yt_dlp_path": self._yt_dlp_path,
            "install_hint": self._install_hint,
        })

    def _emit_duck(self) -> None:
        with self._duck_lock:
            payload = {
                "type": "duck",
                "ducking": bool(self._duck_active),
                "gain": round(self._duck_gain, 3),
                "source": self._duck_source if self._duck_active else "",
                "enabled": bool(self._duck_enabled),
                "level": round(self._duck_level, 2),
            }
        self.emit(payload)

    def _emit_state(self, state: str | None = None, seq: int | None = None, force: bool = True) -> None:
        now = time.monotonic()
        with self._state_lock:
            if state is not None:
                self._state = state
            cur_seq = self._active_seq if seq is None else seq
            if not force and (now - self._last_pos_emit) < 0.24:
                return
            self._last_pos_emit = now
            payload = {
                "type": "state",
                "state": self._state,
                "seq": cur_seq,
                "position": round(self._position, 2),
                "duration": round(self._duration, 2),
                "volume": int(round(self._user_volume)),
                "muted": bool(self._muted),
            }
        self.emit(payload)

    def _effective_mpv_volume(self) -> float:
        with self._state_lock:
            base = float(self._user_volume)
        with self._duck_lock:
            gain = float(self._duck_gain)
        return round(max(0.0, min(100.0, base * gain)), 2)

    def _apply_effective_volume(self) -> None:
        self._send_mpv(["set_property", "volume", self._effective_mpv_volume()])

    def _recompute_playback_state(self) -> None:
        with self._state_lock:
            if self._state in ("idle", "resolving", "error"):
                return
            if self._paused:
                next_state = "paused"
            elif self._paused_for_cache or self._core_idle:
                next_state = "buffering"
            else:
                next_state = "playing"
            changed = next_state != self._state
            self._state = next_state
        if changed:
            self._emit_state(force=True)
            self._need_rescan = True
            self._duck_eval_event.set()

    def _send_mpv(self, cmd: list[Any]) -> bool:
        msg = (json.dumps({"command": cmd}, ensure_ascii=False) + "\n").encode("utf-8")
        with self._ipc_write_lock:
            sock = self._ipc_sock
            if sock is None:
                return False
            try:
                sock.sendall(msg)
                return True
            except OSError:
                return False

    def _close_mpv(self) -> None:
        with self._ipc_write_lock:
            sock = self._ipc_sock
            self._ipc_sock = None
        if sock is not None:
            try:
                sock.close()
            except OSError:
                pass
        proc = self._mpv_proc
        self._mpv_proc = None
        if proc is not None:
            try:
                if proc.poll() is None:
                    proc.terminate()
                    try:
                        proc.wait(timeout=1.5)
                    except subprocess.TimeoutExpired:
                        proc.kill()
                        proc.wait(timeout=1.0)
            except OSError:
                pass
        try:
            if os.path.exists(self._sock_path):
                os.unlink(self._sock_path)
        except OSError:
            pass

    def _close_pactl_sub(self) -> None:
        proc = self._pactl_sub_proc
        self._pactl_sub_proc = None
        if proc is not None:
            try:
                if proc.poll() is None:
                    proc.terminate()
                    try:
                        proc.wait(timeout=0.8)
                    except subprocess.TimeoutExpired:
                        proc.kill()
            except OSError:
                pass

    def _stop_all_monitors(self) -> None:
        with self._monitors_lock:
            mons = list(self._monitors.values())
            self._monitors.clear()
        for m in mons:
            m.stop()

    def _ensure_duck_watcher(self) -> None:
        if self._duck_threads_started or not self._pactl_path:
            return
        self._duck_threads_started = True
        threading.Thread(target=self._pactl_subscribe_loop, daemon=True).start()
        threading.Thread(target=self._duck_supervisor_loop, daemon=True).start()

    def _pactl_subscribe_loop(self) -> None:
        while self._running:
            if not self._pactl_path:
                time.sleep(2.0)
                continue
            try:
                proc = subprocess.Popen(
                    [self._pactl_path, "subscribe"],
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.DEVNULL,
                    text=True,
                )
                self._pactl_sub_proc = proc
                assert proc.stdout is not None
                for line in proc.stdout:
                    if not self._running:
                        break
                    if "sink-input" in line:
                        self._need_rescan = True
                        self._duck_eval_event.set()
            except OSError:
                pass
            finally:
                self._close_pactl_sub()
            if self._running:
                time.sleep(1.0)

    def _list_external_sink_inputs(self) -> list[tuple[str, str]]:
        """Return [(sink_input_id, pretty_label)] for active non-corked external streams."""
        if not self._pactl_path:
            return []
        try:
            proc = subprocess.run(
                [self._pactl_path, "list", "sink-inputs"],
                capture_output=True,
                text=True,
                timeout=2.0,
            )
        except (subprocess.TimeoutExpired, OSError):
            return []
        if proc.returncode != 0 or not proc.stdout:
            return []

        mpv_pid = str(self._mpv_proc.pid) if (self._mpv_proc and self._mpv_proc.poll() is None) else ""
        results: list[tuple[str, str]] = []
        blocks = re.split(r"(?m)^Sink Input #", proc.stdout)
        for blk in blocks[1:]:
            first_line = blk.split("\n", 1)[0].strip()
            if not first_line.isdigit():
                continue
            sid = first_line
            if re.search(r"^\s*Corked:\s*yes\b", blk, re.MULTILINE):
                continue
            if re.search(r"^\s*Mute:\s*yes\b", blk, re.MULTILINE):
                continue
            vol_match = re.search(r"^\s*Volume:.*?(\d+)%", blk, re.MULTILINE)
            if vol_match and int(vol_match.group(1)) <= 0:
                continue

            pid_match = re.search(r'application\.process\.id\s*=\s*"([^"]+)"', blk)
            if mpv_pid and pid_match and pid_match.group(1) == mpv_pid:
                continue

            app_match = re.search(r'application\.name\s*=\s*"([^"]+)"', blk)
            node_match = re.search(r'node\.name\s*=\s*"([^"]+)"', blk)
            media_match = re.search(r'media\.name\s*=\s*"([^"]+)"', blk)

            app_name = app_match.group(1) if app_match else ""
            node_name = node_match.group(1) if node_match else ""
            media_name = media_match.group(1) if media_match else ""

            low_app = app_name.strip().lower()
            low_node = node_name.strip().lower()
            if low_app in IGNORED_DUCK_APPS or low_node in IGNORED_DUCK_APPS:
                continue
            if "paithosh-mixcloud" in low_app or "paithosh-mixcloud" in low_node:
                continue

            label = _prettify_app_name(app_name or node_name or media_name)
            results.append((sid, label))

        return results

    def _sync_monitors(self, active_streams: list[tuple[str, str]]) -> None:
        if not self._parec_path:
            return
        wanted = {sid: lbl for sid, lbl in active_streams[:MAX_STREAM_MONITORS]}
        to_stop: list[_StreamMonitor] = []
        with self._monitors_lock:
            for sid in list(self._monitors.keys()):
                if sid not in wanted:
                    to_stop.append(self._monitors.pop(sid))
            for sid, lbl in wanted.items():
                if sid not in self._monitors:
                    self._monitors[sid] = _StreamMonitor(
                        sid,
                        lbl,
                        self._parec_path,
                        self._duck_eval_event.set,
                    )
                else:
                    self._monitors[sid].label = lbl
        for m in to_stop:
            m.stop()

    def _query_rms_audible(self) -> tuple[bool, str]:
        with self._monitors_lock:
            mons = list(self._monitors.values())
        for m in mons:
            if m.audible:
                return True, m.label
        return False, ""

    def _start_duck_ramp(self, target_gain: float, base_duration_s: float) -> None:
        with self._duck_lock:
            start_gain = self._duck_gain
            self._duck_ramp_seq += 1
            seq = self._duck_ramp_seq
            full_span = max(0.05, 1.0 - self._duck_level)

        dist = abs(target_gain - start_gain)
        if dist < 0.004:
            with self._duck_lock:
                self._duck_gain = target_gain
            self._apply_effective_volume()
            return

        dur = max(0.07, base_duration_s * min(1.0, dist / full_span))

        def _ramp_worker() -> None:
            t0 = time.monotonic()
            step_s = 1.0 / 30.0
            while self._running:
                with self._duck_lock:
                    if seq != self._duck_ramp_seq:
                        return
                elapsed = time.monotonic() - t0
                u = min(1.0, elapsed / dur)
                # Cosine S-curve (InOutSine) for silky, non-jarring volume glide
                eased = 0.5 - 0.5 * math.cos(math.pi * u)
                cur = start_gain + (target_gain - start_gain) * eased
                with self._duck_lock:
                    if seq != self._duck_ramp_seq:
                        return
                    self._duck_gain = cur
                self._apply_effective_volume()
                if u >= 1.0:
                    return
                time.sleep(step_s)

        threading.Thread(target=_ramp_worker, daemon=True).start()

    def _duck_supervisor_loop(self) -> None:
        last_rescan_ts = 0.0
        cached_streams: list[tuple[str, str]] = []

        while self._running:
            with self._state_lock:
                is_active_playback = self._state in ("playing", "buffering")
            with self._duck_lock:
                enabled = self._duck_enabled
                was_ducking = self._duck_active
                ext_present = self._ext_audio_present

            # Tight wait ONLY during short attack/release hold transitions; sleep cleanly otherwise
            if is_active_playback and enabled:
                if ext_present != was_ducking:
                    wait_s = 0.04
                else:
                    wait_s = 2.0
            elif was_ducking:
                wait_s = 0.05
            else:
                wait_s = 3.0

            self._duck_eval_event.wait(timeout=wait_s)
            self._duck_eval_event.clear()
            if not self._running:
                break

            with self._state_lock:
                is_active_playback = self._state in ("playing", "buffering")
            with self._duck_lock:
                enabled = self._duck_enabled
                target_level = self._duck_level

            if not enabled or not is_active_playback:
                self._stop_all_monitors()
                cached_streams = []
                need_restore = False
                with self._duck_lock:
                    self._ext_audio_present = False
                    self._ext_first_seen_ts = 0.0
                    if self._duck_active or self._duck_gain < 0.995:
                        self._duck_active = False
                        self._duck_source = ""
                        need_restore = True
                if need_restore:
                    self._emit_duck()
                    self._start_duck_ramp(1.0, self._duck_up_s)
                continue

            now = time.monotonic()
            # Only invoke `pactl list sink-inputs` on actual PipeWire events or every 3s safety check
            if self._need_rescan or (now - last_rescan_ts) >= 3.0:
                self._need_rescan = False
                last_rescan_ts = now
                cached_streams = self._list_external_sink_inputs()
                self._sync_monitors(cached_streams)

            if self._parec_path:
                ext_now, ext_src = self._query_rms_audible()
            else:
                ext_now = len(cached_streams) > 0
                ext_src = cached_streams[0][1] if ext_now else ""

            action = ""  # "" | "duck" | "restore" | "source_changed"
            with self._duck_lock:
                if ext_now:
                    if not self._ext_audio_present:
                        self._ext_first_seen_ts = now
                    self._ext_audio_present = True
                    self._ext_last_seen_ts = now

                    if not self._duck_active:
                        if (now - self._ext_first_seen_ts) >= self._duck_attack_delay_s:
                            self._duck_active = True
                            self._duck_source = ext_src
                            action = "duck"
                    elif ext_src and ext_src != self._duck_source:
                        self._duck_source = ext_src
                        action = "source_changed"
                else:
                    self._ext_audio_present = False
                    self._ext_first_seen_ts = 0.0
                    if self._duck_active:
                        if (now - self._ext_last_seen_ts) >= self._duck_release_hold_s:
                            self._duck_active = False
                            self._duck_source = ""
                            action = "restore"

            if action == "duck":
                self._emit_duck()
                self._start_duck_ramp(target_level, self._duck_down_s)
            elif action == "restore":
                self._emit_duck()
                self._start_duck_ramp(1.0, self._duck_up_s)
            elif action == "source_changed":
                self._emit_duck()

    def _ensure_mpv(self, volume: int, muted: bool) -> bool:
        if self._mpv_proc is not None and self._mpv_proc.poll() is None and self._ipc_sock is not None:
            return True

        self._close_mpv()
        self._mpv_path = _find_bin("mpv")
        if not self._mpv_path:
            return False

        try:
            if os.path.exists(self._sock_path):
                os.unlink(self._sock_path)
        except OSError:
            pass

        with self._state_lock:
            self._user_volume = max(0, min(100, int(volume)))
            self._muted = bool(muted)

        cmd = [
            self._mpv_path,
            "--no-video",
            "--no-terminal",
            "--idle=yes",
            "--audio-display=no",
            "--audio-client-name=paithosh-mixcloud",
            "--title=Paithosh Music",
            "--cache=yes",
            "--demuxer-max-bytes=32MiB",
            "--demuxer-readahead-secs=20",
            f"--volume={self._effective_mpv_volume()}",
            f"--mute={'yes' if muted else 'no'}",
            f"--input-ipc-server={self._sock_path}",
        ]
        try:
            self._mpv_proc = subprocess.Popen(
                cmd,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except OSError as exc:
            self.emit({"type": "error", "seq": self._active_seq, "message": f"Failed to launch mpv: {exc}"})
            return False

        deadline = time.monotonic() + 4.0
        sock: socket.socket | None = None
        while time.monotonic() < deadline and self._running:
            if self._mpv_proc.poll() is not None:
                break
            if os.path.exists(self._sock_path):
                try:
                    candidate = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                    candidate.settimeout(1.0)
                    candidate.connect(self._sock_path)
                    sock = candidate
                    break
                except OSError:
                    try:
                        candidate.close()
                    except OSError:
                        pass
            time.sleep(0.05)

        if sock is None:
            self._close_mpv()
            self.emit({"type": "error", "seq": self._active_seq, "message": "Timed out connecting to mpv IPC"})
            return False

        with self._ipc_write_lock:
            self._ipc_sock = sock

        self._ipc_thread = threading.Thread(target=self._mpv_reader_loop, args=(sock,), daemon=True)
        self._ipc_thread.start()

        for prop_id, prop_name in (
            (1, "pause"),
            (2, "time-pos"),
            (3, "duration"),
            (4, "paused-for-cache"),
            (5, "core-idle"),
            (6, "mute"),
        ):
            self._send_mpv(["observe_property", prop_id, prop_name])

        self._ensure_duck_watcher()
        return True

    def _mpv_reader_loop(self, sock: socket.socket) -> None:
        buf = b""
        while self._running:
            with self._ipc_write_lock:
                if self._ipc_sock is not sock:
                    break
            try:
                chunk = sock.recv(4096)
                if not chunk:
                    break
                buf += chunk
                while b"\n" in buf:
                    raw_line, buf = buf.split(b"\n", 1)
                    line = raw_line.decode("utf-8", errors="replace").strip()
                    if not line:
                        continue
                    try:
                        msg = json.loads(line)
                    except ValueError:
                        continue
                    self._handle_mpv_event(msg)
            except socket.timeout:
                continue
            except OSError:
                break

    def _handle_mpv_event(self, msg: dict[str, Any]) -> None:
        ev = msg.get("event")
        if ev == "property-change":
            name = msg.get("name")
            data = msg.get("data")
            if name == "time-pos":
                if isinstance(data, (int, float)) and data >= 0:
                    with self._state_lock:
                        self._position = float(data)
                    self._emit_state(force=False)
            elif name == "duration":
                if isinstance(data, (int, float)) and data > 0:
                    with self._state_lock:
                        self._duration = float(data)
                    self._emit_state(force=True)
            elif name == "pause":
                if isinstance(data, bool):
                    with self._state_lock:
                        self._paused = data
                    self._recompute_playback_state()
            elif name == "paused-for-cache":
                if isinstance(data, bool):
                    with self._state_lock:
                        self._paused_for_cache = data
                    self._recompute_playback_state()
            elif name == "core-idle":
                if isinstance(data, bool):
                    with self._state_lock:
                        self._core_idle = data
                    self._recompute_playback_state()
            elif name == "mute":
                if isinstance(data, bool):
                    with self._state_lock:
                        self._muted = data
                    self._emit_state(force=True)
        elif ev == "start-file":
            with self._state_lock:
                if self._state != "idle":
                    self._state = "buffering"
                    self._position = 0.0
            self._emit_state(force=True)
            self._need_rescan = True
            self._duck_eval_event.set()
        elif ev == "playback-restart":
            with self._state_lock:
                self._core_idle = False
                self._paused_for_cache = False
            self._recompute_playback_state()
        elif ev == "end-file":
            reason = msg.get("reason", "")
            with self._state_lock:
                seq = self._active_seq
            if reason == "eof":
                with self._state_lock:
                    self._state = "idle"
                    self._position = 0.0
                self._emit_state(force=True)
                self._duck_eval_event.set()
                self.emit({"type": "eof", "seq": seq})
            elif reason == "error":
                err_msg = msg.get("file_error") or "Audio stream interrupted"
                with self._state_lock:
                    self._state = "error"
                self._emit_state(force=True)
                self._duck_eval_event.set()
                self.emit({"type": "error", "seq": seq, "message": str(err_msg)})

    def _resolve_and_play(self, url: str, seq: int, volume: int, muted: bool) -> None:
        self._yt_dlp_path = _find_bin("yt-dlp")
        self._mpv_path = _find_bin("mpv")
        if not self._yt_dlp_path or not self._mpv_path:
            self.emit_deps()
            with self._state_lock:
                if seq != self._play_seq:
                    return
                self._state = "error"
            self.emit({"type": "error", "seq": seq, "message": "Missing mpv or yt-dlp"})
            self._emit_state(force=True)
            return

        try:
            proc = subprocess.run(
                [
                    self._yt_dlp_path,
                    "--no-playlist",
                    "--no-warnings",
                    "-f",
                    "bestaudio/best",
                    "-g",
                    url,
                ],
                capture_output=True,
                text=True,
                timeout=25,
            )
        except subprocess.TimeoutExpired:
            with self._state_lock:
                if seq != self._play_seq:
                    return
                self._state = "error"
            self.emit({"type": "error", "seq": seq, "message": "Timed out resolving Mixcloud stream"})
            self._emit_state(force=True)
            return
        except OSError as exc:
            with self._state_lock:
                if seq != self._play_seq:
                    return
                self._state = "error"
            self.emit({"type": "error", "seq": seq, "message": f"yt-dlp error: {exc}"})
            self._emit_state(force=True)
            return

        with self._state_lock:
            if seq != self._play_seq or not self._running:
                return

        if proc.returncode != 0:
            err_lines = [ln.strip() for ln in (proc.stderr or "").splitlines() if ln.strip()]
            msg = err_lines[0] if err_lines else "Failed to resolve Mixcloud stream"
            with self._state_lock:
                self._state = "error"
            self.emit({"type": "error", "seq": seq, "message": msg})
            self._emit_state(force=True)
            return

        stream_urls = [ln.strip() for ln in (proc.stdout or "").splitlines() if ln.strip()]
        if not stream_urls:
            with self._state_lock:
                self._state = "error"
            self.emit({"type": "error", "seq": seq, "message": "No playable stream URL returned"})
            self._emit_state(force=True)
            return

        stream_url = stream_urls[0]
        if not self._ensure_mpv(volume, muted):
            with self._state_lock:
                if seq == self._play_seq:
                    self._state = "error"
            self._emit_state(force=True)
            return

        with self._state_lock:
            if seq != self._play_seq:
                return
            self._active_seq = seq
            self._state = "buffering"
            self._position = 0.0
            self._paused = False
            self._paused_for_cache = False
            self._core_idle = True
            self._user_volume = max(0, min(100, int(volume)))
            self._muted = bool(muted)

        self._emit_state(force=True)
        self._apply_effective_volume()
        self._send_mpv(["set_property", "mute", bool(muted)])
        self._send_mpv(["loadfile", stream_url, "replace"])
        self._send_mpv(["set_property", "pause", False])
        self._need_rescan = True
        self._duck_eval_event.set()

    def handle_command(self, obj: dict[str, Any]) -> None:
        cmd = str(obj.get("cmd", "")).strip()
        if cmd == "check_deps":
            self.emit_deps()
        elif cmd == "set_ducking":
            with self._duck_lock:
                if isinstance(obj.get("enabled"), bool):
                    self._duck_enabled = obj["enabled"]
                if isinstance(obj.get("level"), (int, float)):
                    self._duck_level = max(0.08, min(0.75, float(obj["level"])))
            self._need_rescan = True
            self._duck_eval_event.set()
            self._emit_duck()
        elif cmd == "play":
            url = str(obj.get("url", "")).strip()
            if not url:
                return
            vol = int(obj.get("volume", self._user_volume))
            muted = bool(obj.get("muted", self._muted))
            if isinstance(obj.get("ducking"), bool):
                with self._duck_lock:
                    self._duck_enabled = obj["ducking"]
            with self._state_lock:
                req_seq = obj.get("seq")
                self._play_seq = int(req_seq) if isinstance(req_seq, int) else (self._play_seq + 1)
                seq = self._play_seq
                self._active_seq = seq
                self._user_volume = max(0, min(100, vol))
                self._muted = muted
                self._position = 0.0
                self._duration = 0.0
                self._state = "resolving"
            self._emit_state(state="resolving", seq=seq, force=True)
            t = threading.Thread(
                target=self._resolve_and_play,
                args=(url, seq, vol, muted),
                daemon=True,
            )
            t.start()
        elif cmd == "pause":
            self._send_mpv(["set_property", "pause", True])
        elif cmd == "resume":
            self._send_mpv(["set_property", "pause", False])
        elif cmd == "toggle":
            self._send_mpv(["cycle", "pause"])
        elif cmd == "seek":
            pos = obj.get("position")
            if isinstance(pos, (int, float)):
                target = max(0.0, float(pos))
                if self._send_mpv(["seek", target, "absolute"]):
                    with self._state_lock:
                        self._position = target
                    self._emit_state(force=True)
        elif cmd == "volume":
            val = obj.get("value")
            if isinstance(val, (int, float)):
                clamped = max(0, min(100, int(round(val))))
                with self._state_lock:
                    self._user_volume = clamped
                self._apply_effective_volume()
        elif cmd == "mute":
            val = bool(obj.get("value", not self._muted))
            with self._state_lock:
                self._muted = val
            self._send_mpv(["set_property", "mute", val])
        elif cmd == "stop":
            with self._state_lock:
                self._play_seq += 1
                self._state = "idle"
                self._position = 0.0
                self._duration = 0.0
                self._paused = False
            self._send_mpv(["stop"])
            self._emit_state(state="idle", force=True)
            self._duck_eval_event.set()
        elif cmd == "quit":
            self._running = False

    def shutdown(self) -> None:
        self._running = False
        self._duck_eval_event.set()
        self._stop_all_monitors()
        self._close_pactl_sub()
        self._close_mpv()

    def run(self) -> None:
        atexit.register(self.shutdown)

        def _on_sig(_signum: int, _frame: object) -> None:
            self.shutdown()
            sys.exit(0)

        signal.signal(signal.SIGTERM, _on_sig)
        signal.signal(signal.SIGINT, _on_sig)

        self.emit_deps()
        self._emit_duck()
        try:
            while self._running:
                line = sys.stdin.readline()
                if line == "":
                    break
                trimmed = line.strip()
                if not trimmed:
                    continue
                try:
                    obj = json.loads(trimmed)
                except ValueError:
                    continue
                if isinstance(obj, dict):
                    self.handle_command(obj)
        finally:
            self.shutdown()


if __name__ == "__main__":
    MixcloudDaemon().run()
