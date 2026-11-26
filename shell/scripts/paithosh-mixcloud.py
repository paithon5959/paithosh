#!/usr/bin/env python3
"""Lightweight Mixcloud audio daemon for Paithosh shell.

Reads newline-delimited JSON commands from stdin, resolves Mixcloud audio
streams via yt-dlp, drives headless mpv instance(s) over UNIX socket JSON IPC,
provides a Hybrid Sidechain RMS audio ducking engine (pactl subscribe + 4kHz
mono parec stream monitors), applies live FFmpeg lavfi EQ/DSP chains, and
runs a dual-deck Progressive Audio Mix engine (volume, tempo & beat/buffer
offset alignment) using pure Python stdlib + already-installed ffmpeg/mpv.
"""

from __future__ import annotations

import array
import atexit
import ctypes
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


_PR_SET_PDEATHSIG = 1

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
DEFAULT_RMS_THRESHOLD = 0.005  # ~ -46 dBFS

BUFFER_PROFILES = {
    "low": ("16MiB", 10),
    "balanced": ("32MiB", 20),
    "high": ("64MiB", 45),
}


def _clamp(val: float, lo: float, hi: float) -> float:
    return lo if val < lo else (hi if val > hi else val)


def _set_pdeathsig(sig: int = signal.SIGTERM) -> None:
    """Ask the Linux kernel to send `sig` to this process when its parent dies."""
    try:
        libc = ctypes.CDLL("libc.so.6")
        libc.prctl(_PR_SET_PDEATHSIG, sig)
    except Exception:
        pass


def _cleanup_stale_mpv(runtime_dir: str) -> None:
    """Terminate any orphaned paithosh-mixcloud mpv instances left from a prior shell reload."""
    for name in (
        "paithosh-mixcloud-mpv.pid",
        "paithosh-mixcloud-mpv-A.pid",
        "paithosh-mixcloud-mpv-B.pid",
    ):
        pid_path = os.path.join(runtime_dir, name)
        if not os.path.exists(pid_path):
            continue
        try:
            with open(pid_path, "r", encoding="utf-8") as fh:
                raw = fh.read().strip()
            pid = int(raw) if raw.isdigit() else 0
        except OSError:
            pid = 0
        if pid > 1 and pid != os.getpid():
            try:
                with open(f"/proc/{pid}/cmdline", "rb") as fh:
                    cmdline = fh.read()
                if b"paithosh-mixcloud" in cmdline and b"mpv" in cmdline:
                    try:
                        os.kill(pid, signal.SIGTERM)
                    except ProcessLookupError:
                        pass
                    deadline = time.monotonic() + 0.8
                    while time.monotonic() < deadline:
                        if not os.path.exists(f"/proc/{pid}"):
                            break
                        time.sleep(0.05)
                    if os.path.exists(f"/proc/{pid}"):
                        try:
                            os.kill(pid, signal.SIGKILL)
                        except ProcessLookupError:
                            pass
            except OSError:
                pass
        try:
            os.unlink(pid_path)
        except OSError:
            pass


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
                return "sudo dnf install -y mpv yt-dlp ffmpeg"
            if "arch" in data or "cachyos" in data or "endeavour" in data:
                return "sudo pacman -S --needed mpv yt-dlp ffmpeg"
    except OSError:
        pass
    return "sudo apt install -y mpv yt-dlp ffmpeg"


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


# ---------------------------------------------------------------------------
# Pure Audio DSP & Progressive Mix Analysis Helpers (importable for tests)
# ---------------------------------------------------------------------------

def build_lavfi_chain(cfg: dict[str, Any]) -> str:
    """Build an mpv `lavfi=[...]` audio filter chain from DSP config.

    ponytail: mpv 0.41 does not forward `af-command` into lavfi EQ subfilters;
    live EQ updates rebuild `af` via debounced `set_property af`.
    """
    if not cfg.get("enabled", True):
        return ""

    bass_db = _clamp(float(cfg.get("bass_db", 0.0)), -12.0, 12.0)
    mid_db = _clamp(float(cfg.get("mid_db", 0.0)), -12.0, 12.0)
    high_db = _clamp(float(cfg.get("high_db", 0.0)), -12.0, 12.0)

    bass_freq = _clamp(float(cfg.get("bass_freq", 90.0)), 40.0, 250.0)
    bass_q = _clamp(float(cfg.get("bass_q", 0.7)), 0.3, 2.0)
    mid_freq = _clamp(float(cfg.get("mid_freq", 1000.0)), 300.0, 4000.0)
    mid_q = _clamp(float(cfg.get("mid_q", 1.0)), 0.4, 3.0)
    high_freq = _clamp(float(cfg.get("high_freq", 10000.0)), 4000.0, 16000.0)
    high_q = _clamp(float(cfg.get("high_q", 0.7)), 0.3, 2.0)

    preamp_db = _clamp(float(cfg.get("preamp_db", 0.0)), -12.0, 6.0)
    if bool(cfg.get("auto_headroom", True)):
        boost = max(0.0, bass_db, mid_db, high_db)
        preamp_db = min(preamp_db, -0.5 * boost)

    normalize = bool(cfg.get("normalize", False))
    norm_peak = _clamp(float(cfg.get("norm_peak", 0.92)), 0.75, 0.98)
    norm_frame_ms = int(round(_clamp(float(cfg.get("norm_frame_ms", 200)), 100.0, 500.0)))

    stereo_width = _clamp(float(cfg.get("stereo_width", 1.0)), 0.50, 1.80)
    crossfeed = bool(cfg.get("crossfeed", False))
    crossfeed_strength = _clamp(float(cfg.get("crossfeed_strength", 0.25)), 0.10, 0.80)

    limiter = bool(cfg.get("limiter", True))
    limiter_ceiling_db = _clamp(float(cfg.get("limiter_ceiling_db", -0.5)), -6.0, -0.1)

    parts: list[str] = []
    if abs(preamp_db) >= 0.05:
        parts.append(f"volume={preamp_db:.2f}dB")
    if abs(bass_db) >= 0.05:
        parts.append(f"bass=g={bass_db:.2f}:f={bass_freq:.0f}:t=q:w={bass_q:.2f}")
    if abs(mid_db) >= 0.05:
        parts.append(f"equalizer=f={mid_freq:.0f}:t=q:w={mid_q:.2f}:g={mid_db:.2f}")
    if abs(high_db) >= 0.05:
        parts.append(f"treble=g={high_db:.2f}:f={high_freq:.0f}:t=q:w={high_q:.2f}")
    if normalize:
        parts.append(f"dynaudnorm=f={norm_frame_ms}:g=15:p={norm_peak:.2f}")
    if abs(stereo_width - 1.0) >= 0.02:
        parts.append(f"extrastereo=m={stereo_width:.2f}")
    if crossfeed:
        parts.append(f"crossfeed=strength={crossfeed_strength:.2f}")
    if limiter:
        lim_lin = _clamp(10.0 ** (limiter_ceiling_db / 20.0), 0.5, 1.0)
        parts.append(f"alimiter=limit={lim_lin:.3f}")

    return f"lavfi=[{','.join(parts)}]" if parts else ""


def analyze_pcm_s16le(
    pcm_bytes: bytes,
    sample_rate: int = 11025,
    silence_thresh_db: float = -38.0,
) -> dict[str, Any]:
    """Analyze mono s16le PCM bytes for loudness, active bounds, BPM, and beat phase.

    ponytail: 11kHz mono low-pass onset autocorrelation in pure stdlib; upgrade to
    essentia/aubio only if complex polyrhythmic beat-tracking becomes necessary.
    """
    n_samples = len(pcm_bytes) // 2
    dur_s = n_samples / float(max(1, sample_rate))
    empty_res: dict[str, Any] = {
        "valid": False,
        "duration_s": dur_s,
        "rms_dbfs": -60.0,
        "active_start_s": 0.0,
        "active_end_s": dur_s,
        "bpm": 0.0,
        "confidence": 0.0,
        "beat_phase_s": 0.0,
    }
    if n_samples < sample_rate or sample_rate < 2000:
        return empty_res

    samples = array.array("h")
    samples.frombytes(pcm_bytes[: n_samples * 2])

    hop = max(1, int(round(sample_rate * 0.01)))  # 10ms blocks
    hop_s = hop / float(sample_rate)
    n_blocks = n_samples // hop
    if n_blocks < 40:
        return empty_res

    # 1-pole low-pass (~180 Hz) emphasizes kick/bass transients for beat detection
    alpha = 1.0 - math.exp(-2.0 * math.pi * 180.0 / float(sample_rate))
    lp = 0.0
    inv_scale = 1.0 / 32768.0
    inv_hop = 1.0 / float(hop)

    block_e: list[float] = []
    block_le: list[float] = []
    for b in range(n_blocks):
        start = b * hop
        sum_e = 0.0
        sum_le = 0.0
        for s in samples[start : start + hop]:
            x = s * inv_scale
            lp += alpha * (x - lp)
            sum_e += x * x
            sum_le += lp * lp
        block_e.append(sum_e * inv_hop)
        block_le.append(sum_le * inv_hop)

    nf = n_blocks - 1  # 20ms overlapping frames at 10ms hop
    e: list[float] = [0.0] * nf
    low_e: list[float] = [0.0] * nf
    db: list[float] = [-140.0] * nf
    for i in range(nf):
        ev = math.sqrt(0.5 * (block_e[i] + block_e[i + 1]))
        lev = math.sqrt(0.5 * (block_le[i] + block_le[i + 1]))
        e[i] = ev
        low_e[i] = lev
        db[i] = 20.0 * math.log10(ev if ev > 1e-7 else 1e-7)

    # Sustained active music bounds (250ms sustained above silence threshold)
    thresh = _clamp(float(silence_thresh_db), -65.0, -15.0)
    win_len = min(nf, 25)
    active_start_idx = 0
    found_start = False
    if win_len > 0:
        above_count = sum(1 for k in range(win_len) if db[k] >= thresh)
        req = max(1, int(win_len * 0.75))
        for i in range(nf - win_len + 1):
            if above_count >= req:
                active_start_idx = i
                found_start = True
                break
            if i + win_len < nf:
                if db[i] >= thresh:
                    above_count -= 1
                if db[i + win_len] >= thresh:
                    above_count += 1
    if not found_start:
        for i, val in enumerate(db):
            if val >= thresh:
                active_start_idx = i
                found_start = True
                break

    active_end_idx = nf - 1
    for i in range(nf - 1, -1, -1):
        if db[i] >= thresh:
            active_end_idx = i
            break

    active_start_s = _clamp(active_start_idx * hop_s, 0.0, dur_s)
    active_end_s = _clamp((active_end_idx + 12) * hop_s, active_start_s, dur_s)

    # Robust trimmed loudness across audible region (20th-90th percentile median)
    active_e = [e[i] for i in range(nf) if db[i] >= max(thresh, -55.0)]
    if not active_e:
        active_e = sorted(e)
    else:
        active_e.sort()
    lo_p = int(len(active_e) * 0.20)
    hi_p = max(lo_p + 1, int(len(active_e) * 0.90))
    trimmed = active_e[lo_p:hi_p]
    med_e = trimmed[len(trimmed) // 2] if trimmed else 1e-6
    rms_dbfs = 20.0 * math.log10(med_e if med_e > 1e-7 else 1e-7)

    # Half-wave adaptive onset flux
    raw_flux = [0.0] * nf
    for i in range(1, nf):
        dl = low_e[i] - low_e[i - 1]
        de = e[i] - e[i - 1]
        raw_flux[i] = 0.7 * (dl if dl > 0.0 else 0.0) + 0.3 * (de if de > 0.0 else 0.0)

    onset = [0.0] * nf
    avg_w = 8
    prefix = [0.0] * (nf + 1)
    for i, fv in enumerate(raw_flux):
        prefix[i + 1] = prefix[i] + fv
    for i in range(nf):
        a = max(0, i - avg_w)
        b = min(nf, i + avg_w + 1)
        local_mean = (prefix[b] - prefix[a]) / float(b - a)
        v = raw_flux[i] - 1.15 * local_mean
        onset[i] = v if v > 0.0 else 0.0

    # Restrict tempo search to active span when sufficiently long
    s0 = active_start_idx if (active_end_idx - active_start_idx) >= 150 else 0
    s1 = min(nf, active_end_idx + 1) if (active_end_idx - active_start_idx) >= 150 else nf
    seg = onset[s0:s1]
    seg_len = len(seg)
    energy = sum(v * v for v in seg)

    if seg_len < 120 or energy <= 1e-10:
        return {
            "valid": True,
            "duration_s": dur_s,
            "rms_dbfs": round(rms_dbfs, 2),
            "active_start_s": round(active_start_s, 3),
            "active_end_s": round(active_end_s, 3),
            "bpm": 0.0,
            "confidence": 0.0,
            "beat_phase_s": 0.0,
        }

    lag_min = max(10, int(math.floor(60.0 / (175.0 * hop_s))))
    lag_max = min(seg_len // 2, int(math.ceil(60.0 / (65.0 * hop_s))))
    if lag_max <= lag_min:
        return {
            "valid": True,
            "duration_s": dur_s,
            "rms_dbfs": round(rms_dbfs, 2),
            "active_start_s": round(active_start_s, 3),
            "active_end_s": round(active_end_s, 3),
            "bpm": 0.0,
            "confidence": 0.0,
            "beat_phase_s": 0.0,
        }

    ac_raw: dict[int, float] = {}
    ac_weighted: dict[int, float] = {}
    for lag in range(lag_min, lag_max + 1):
        span = seg_len - lag
        num = 0.0
        n1 = 0.0
        n2 = 0.0
        for j in range(span):
            x = seg[j]
            y = seg[j + lag]
            num += x * y
            n1 += x * x
            n2 += y * y
        denom = math.sqrt(n1 * n2)
        corr = (num / denom) if denom > 1e-12 else 0.0
        bpm_cand = 60.0 / (lag * hop_s)
        prior = math.exp(-0.5 * (math.log2(bpm_cand / 120.0) / 0.65) ** 2)
        ac_raw[lag] = corr
        ac_weighted[lag] = corr * (0.78 + 0.22 * prior)

    best_lag = max(ac_weighted, key=lambda k: ac_weighted[k])
    # Harmonic check: prevent sub-harmonic 0.5x lock when double-tempo is strong
    half_lag = int(round(best_lag / 2.0))
    if half_lag in ac_raw and ac_raw[half_lag] >= 0.80 * ac_raw[best_lag]:
        half_bpm = 60.0 / (half_lag * hop_s)
        if 90.0 <= half_bpm <= 165.0:
            best_lag = half_lag

    # Parabolic peak refinement around best_lag
    refined_lag = float(best_lag)
    if (best_lag - 1) in ac_raw and (best_lag + 1) in ac_raw:
        y0 = ac_raw[best_lag - 1]
        y1 = ac_raw[best_lag]
        y2 = ac_raw[best_lag + 1]
        denom = y0 - 2.0 * y1 + y2
        if abs(denom) > 1e-9:
            shift = _clamp(0.5 * (y0 - y2) / denom, -0.5, 0.5)
            refined_lag += shift

    bpm = _clamp(60.0 / (refined_lag * hop_s), 65.0, 175.0)
    vals_sorted = sorted(ac_raw.values())
    med_ac = vals_sorted[len(vals_sorted) // 2]
    peak_ac = ac_raw[best_lag]
    contrast = (peak_ac - med_ac) / max(1e-6, 1.0 - med_ac)
    confidence = _clamp(0.5 * peak_ac + 0.5 * contrast, 0.0, 1.0)

    # Fold onset flux modulo beat period T into 32 circular phase bins
    period_s = 60.0 / bpm
    n_bins = 32
    bins = [0.0] * n_bins
    for idx in range(s0, s1):
        t = idx * hop_s
        b = int(((t % period_s) / period_s) * n_bins) % n_bins
        bins[b] += onset[idx]

    smoothed = [
        0.25 * bins[(b - 1) % n_bins] + 0.50 * bins[b] + 0.25 * bins[(b + 1) % n_bins]
        for b in range(n_bins)
    ]
    best_bin = max(range(n_bins), key=lambda b: smoothed[b])
    w_sum = 0.0
    off_sum = 0.0
    for d in (-1, 0, 1):
        w = smoothed[(best_bin + d) % n_bins]
        w_sum += w
        off_sum += d * w
    frac_bin = (best_bin + (off_sum / w_sum if w_sum > 1e-12 else 0.0) + 0.5) % n_bins
    beat_phase_s = (frac_bin / float(n_bins)) * period_s

    return {
        "valid": True,
        "duration_s": round(dur_s, 3),
        "rms_dbfs": round(rms_dbfs, 2),
        "active_start_s": round(active_start_s, 3),
        "active_end_s": round(active_end_s, 3),
        "bpm": round(bpm, 2),
        "confidence": round(confidence, 3),
        "beat_phase_s": round(beat_phase_s, 4),
    }


def compute_mix_plan(
    analysis_a: dict[str, Any],
    analysis_b: dict[str, Any],
    cfg: dict[str, Any],
) -> dict[str, Any]:
    """Compute matched gain trim, tempo speed ratio, and beat/intro offset plan."""
    match_vol = bool(cfg.get("match_volume", True))
    match_tempo = bool(cfg.get("match_tempo", True))
    match_offset = bool(cfg.get("match_offset", True))
    max_trim_db = _clamp(float(cfg.get("max_gain_trim_db", 6.0)), 0.0, 12.0)
    max_shift_pct = _clamp(float(cfg.get("max_tempo_shift_pct", 6.0)), 0.0, 12.0)

    valid_a = bool(analysis_a and analysis_a.get("valid"))
    valid_b = bool(analysis_b and analysis_b.get("valid"))

    gain_trim_db = 0.0
    if match_vol and valid_a and valid_b:
        raw_delta = float(analysis_a.get("rms_dbfs", -18.0)) - float(analysis_b.get("rms_dbfs", -18.0))
        gain_trim_db = _clamp(raw_delta, -max_trim_db, max_trim_db)
    loudness_trim_b = _clamp(10.0 ** (gain_trim_db / 20.0), 0.25, 2.5)

    bpm_a = float(analysis_a.get("bpm", 0.0)) if valid_a else 0.0
    bpm_b = float(analysis_b.get("bpm", 0.0)) if valid_b else 0.0
    conf_a = float(analysis_a.get("confidence", 0.0)) if valid_a else 0.0
    conf_b = float(analysis_b.get("confidence", 0.0)) if valid_b else 0.0

    speed_b = 1.0
    tempo_matched = False
    if match_tempo and bpm_a > 0.0 and bpm_b > 0.0 and conf_a >= 0.22 and conf_b >= 0.22:
        cands = (bpm_a / bpm_b, bpm_a / (2.0 * bpm_b), (2.0 * bpm_a) / bpm_b)
        best_r = min(cands, key=lambda r: abs(r - 1.0))
        if abs(best_r - 1.0) <= (max_shift_pct / 100.0) and best_r > 0.5:
            speed_b = round(best_r, 4)
            tempo_matched = True

    intro_offset_b = 0.0
    if match_offset and valid_b:
        intro_offset_b = max(0.0, float(analysis_b.get("active_start_s", 0.0)))

    period_a = (60.0 / bpm_a) if bpm_a > 0.0 else 0.0
    period_b = (60.0 / bpm_b) if bpm_b > 0.0 else 0.0
    phase_sync = bool(
        match_offset
        and tempo_matched
        and period_a > 0.0
        and period_b > 0.0
    )

    notes: list[str] = []
    if not (valid_a and valid_b):
        notes.append("Fallback crossfade")
    else:
        if match_vol:
            notes.append(f"Vol {gain_trim_db:+.1f}dB")
        if tempo_matched:
            notes.append(f"BPM {bpm_a:.0f}->{bpm_b:.0f} ({speed_b:.3f}x)")
        elif match_tempo and bpm_a > 0 and bpm_b > 0:
            notes.append("BPM outside cap")
        if phase_sync:
            notes.append("Phase locked")
        elif intro_offset_b > 0.05:
            notes.append(f"Intro +{intro_offset_b:.2f}s")

    return {
        "valid": valid_a and valid_b,
        "bpm_a": round(bpm_a, 1),
        "bpm_b": round(bpm_b, 1),
        "conf_a": round(conf_a, 2),
        "conf_b": round(conf_b, 2),
        "gain_trim_db": round(gain_trim_db, 2),
        "loudness_trim_b": round(loudness_trim_b, 4),
        "speed_b": round(speed_b, 4),
        "tempo_matched": tempo_matched,
        "phase_sync": phase_sync,
        "intro_offset_b": round(intro_offset_b, 3),
        "beat_phase_a": float(analysis_a.get("beat_phase_s", 0.0)) if valid_a else 0.0,
        "beat_phase_b": float(analysis_b.get("beat_phase_s", 0.0)) if valid_b else 0.0,
        "beat_period_a": period_a,
        "beat_period_b": period_b,
        "outro_active_end_s": float(analysis_a.get("active_end_s", 0.0)) if valid_a else 0.0,
        "note": " • ".join(notes) if notes else "Smooth blend",
    }


def align_deck_b_target(
    pos_a: float,
    beat_anchor_a: float,
    beat_period_a: float,
    intro_offset_b: float,
    beat_anchor_b: float,
    beat_period_b: float,
    speed_b: float,
    seek_comp_s: float = 0.12,
    manual_offset_ms: float = 0.0,
) -> float:
    """Compute Deck B start seek position aligning its beat grid + buffer compensation."""
    base_b = max(0.0, float(intro_offset_b))
    manual_s = (float(manual_offset_ms) / 1000.0) * max(0.5, float(speed_b))
    if beat_period_a <= 0.05 or beat_period_b <= 0.05:
        return max(0.0, base_b + manual_s)

    pos_a_future = max(0.0, float(pos_a) + max(0.0, float(seek_comp_s)))
    phase_frac = ((pos_a_future - float(beat_anchor_a)) % beat_period_a) / beat_period_a
    desired_mod = phase_frac * beat_period_b
    cur_mod = (base_b - float(beat_anchor_b)) % beat_period_b
    delta = (desired_mod - cur_mod) % beat_period_b
    return max(0.0, base_b + delta + manual_s)


def crossfade_gains(u: float, curve: str = "progressive") -> tuple[float, float]:
    """Return (gain_deck_a, gain_deck_b) for normalized blend progress u in [0, 1]."""
    t = _clamp(float(u), 0.0, 1.0)
    c = (curve or "progressive").strip().lower()
    if c == "equal_power":
        ang = t * (math.pi * 0.5)
        return math.cos(ang), math.sin(ang)
    if c == "smooth_s":
        e = 0.5 - 0.5 * math.cos(math.pi * t)
        return 1.0 - e, e
    if c == "linear":
        return 1.0 - t, t
    # "progressive": bring Deck B up smoothly first, hold overlap plateau, glide Deck A out
    ub = min(1.0, t / 0.65)
    gb = 0.5 - 0.5 * math.cos(math.pi * ub)
    ua = max(0.0, (t - 0.35) / 0.65)
    ga = 0.5 + 0.5 * math.cos(math.pi * ua)
    return ga, gb


def probe_stream_pcm(
    ffmpeg_path: str,
    stream_url: str,
    start_sec: float,
    duration_sec: float,
    timeout_s: float = 8.0,
) -> bytes:
    """Extract mono 11025 Hz s16le PCM slice from a stream/file via ffmpeg."""
    if not ffmpeg_path or not stream_url or duration_sec <= 0.5:
        return b""
    cmd = [
        ffmpeg_path,
        "-nostdin",
        "-loglevel",
        "error",
        "-ss",
        f"{max(0.0, float(start_sec)):.2f}",
        "-i",
        stream_url,
        "-t",
        f"{_clamp(float(duration_sec), 1.0, 30.0):.2f}",
        "-vn",
        "-ac",
        "1",
        "-ar",
        "11025",
        "-f",
        "s16le",
        "pipe:1",
    ]
    try:
        proc = subprocess.run(
            cmd,
            capture_output=True,
            timeout=timeout_s,
        )
        if proc.returncode == 0 and proc.stdout:
            return proc.stdout
    except (subprocess.TimeoutExpired, OSError):
        pass
    return b""


# ---------------------------------------------------------------------------
# PipeWire Sidechain RMS Stream Monitor
# ---------------------------------------------------------------------------

class _StreamMonitor:
    """Ultra-lightweight 4kHz mono RMS monitor for a single PipeWire sink-input."""

    def __init__(
        self,
        sink_input_id: str,
        label: str,
        parec_path: str,
        on_audio_cb: Any,
        get_threshold_cb: Any,
    ) -> None:
        self.sink_input_id = sink_input_id
        self.label = label
        self._parec_path = parec_path
        self._on_audio_cb = on_audio_cb
        self._get_threshold_cb = get_threshold_cb
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
                sum_sq = 0
                for s in samples:
                    sum_sq += s * s
                rms = math.sqrt(sum_sq / n_samples) / 32768.0
                thresh = float(self._get_threshold_cb())
                now_audible = rms >= thresh
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


# ---------------------------------------------------------------------------
# Headless mpv Deck Wrapper
# ---------------------------------------------------------------------------

class _MpvDeck:
    """Manages one headless mpv process + UNIX JSON IPC socket."""

    def __init__(self, deck_id: str, runtime_dir: str) -> None:
        self.deck_id = deck_id
        self.sock_path = os.path.join(
            runtime_dir, f"paithosh-mixcloud-{os.getpid()}-{deck_id}-{int(time.monotonic() * 1000)}.sock"
        )
        self.pid_path = os.path.join(runtime_dir, f"paithosh-mixcloud-mpv-{deck_id}.pid")
        self._write_lock = threading.Lock()
        self.proc: subprocess.Popen[bytes] | None = None
        self.ipc_sock: socket.socket | None = None
        self.reader_thread: threading.Thread | None = None

        self.stream_url = ""
        self.seq = 0
        self.position = 0.0
        self.duration = 0.0
        self.pending_start_pos = 0.0
        self.paused = False
        self.paused_for_cache = False
        self.core_idle = True
        self.muted = False

        # Progressive mix multipliers
        self.mix_gain = 1.0
        self.loudness_trim = 1.0
        self.speed = 1.0

    def is_alive(self) -> bool:
        return self.proc is not None and self.proc.poll() is None and self.ipc_sock is not None

    def pid_str(self) -> str:
        if self.proc is not None and self.proc.poll() is None:
            return str(self.proc.pid)
        return ""

    def send(self, cmd: list[Any]) -> bool:
        msg = (json.dumps({"command": cmd}, ensure_ascii=False) + "\n").encode("utf-8")
        with self._write_lock:
            sock = self.ipc_sock
            if sock is None:
                return False
            try:
                sock.sendall(msg)
                return True
            except OSError:
                return False

    def close(self) -> None:
        with self._write_lock:
            sock = self.ipc_sock
            self.ipc_sock = None
        if sock is not None:
            try:
                sock.close()
            except OSError:
                pass
        proc = self.proc
        self.proc = None
        if proc is not None:
            try:
                if proc.poll() is None:
                    proc.terminate()
                    try:
                        proc.wait(timeout=1.4)
                    except subprocess.TimeoutExpired:
                        proc.kill()
                        proc.wait(timeout=0.8)
            except OSError:
                pass
        for p in (self.sock_path, self.pid_path):
            try:
                if os.path.exists(p):
                    os.unlink(p)
            except OSError:
                pass


# ---------------------------------------------------------------------------
# Main Daemon
# ---------------------------------------------------------------------------

class MixcloudDaemon:
    def __init__(self) -> None:
        self._emit_lock = threading.Lock()
        self._state_lock = threading.Lock()
        self._running = True
        self._play_seq = 0
        self._active_seq = 0

        runtime_dir = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
        if not os.path.isdir(runtime_dir):
            runtime_dir = "/tmp"
        self._runtime_dir = runtime_dir

        self._primary = _MpvDeck("A", runtime_dir)
        self._staging: _MpvDeck | None = None
        self._mix_lock = threading.Lock()
        self._mix_seq = 0
        self._mix_stage = "idle"

        self._mpv_path = _find_bin("mpv")
        self._yt_dlp_path = _find_bin("yt-dlp")
        self._ffmpeg_path = _find_bin("ffmpeg")
        self._pactl_path = _find_bin("pactl")
        self._parec_path = _find_bin("parec")
        self._install_hint = _detect_install_hint()

        # Primary playback state
        self._state = "idle"  # idle | resolving | buffering | playing | paused | error
        self._user_volume = 80
        self._muted = False
        self._last_pos_emit = 0.0

        # Playback & Audio DSP config
        self._buffer_preset = "balanced"
        self._pitch_correction = True
        self._dsp_cfg: dict[str, Any] = {
            "enabled": True,
            "bass_db": 0.0,
            "mid_db": 0.0,
            "high_db": 0.0,
            "bass_freq": 90.0,
            "bass_q": 0.7,
            "mid_freq": 1000.0,
            "mid_q": 1.0,
            "high_freq": 10000.0,
            "high_q": 0.7,
            "preamp_db": 0.0,
            "auto_headroom": True,
            "normalize": False,
            "norm_peak": 0.92,
            "norm_frame_ms": 200,
            "stereo_width": 1.0,
            "crossfeed": False,
            "crossfeed_strength": 0.25,
            "limiter": True,
            "limiter_ceiling_db": -0.5,
        }

        # Hybrid Sidechain RMS Audio Ducking state
        self._duck_lock = threading.Lock()
        self._duck_enabled = True
        self._duck_level = 0.24
        self._duck_mode = "rms"  # "rms" | "presence"
        self._duck_attack_delay_s = 0.06
        self._duck_release_hold_s = 0.32
        self._duck_down_s = 0.26
        self._duck_up_s = 0.52
        self._duck_rms_thresh = DEFAULT_RMS_THRESHOLD
        self._duck_ignored_custom: set[str] = set()

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

        # Progressive Audio Mix config
        self._mix_cfg: dict[str, Any] = {
            "enabled": True,
            "duration_s": 14.0,
            "curve": "progressive",
            "match_volume": True,
            "match_tempo": True,
            "match_offset": True,
            "cue_lead_s": 30.0,
            "analysis_window_s": 12.0,
            "max_tempo_shift_pct": 6.0,
            "tempo_release_s": 10.0,
            "max_gain_trim_db": 6.0,
            "silence_threshold_db": -38.0,
            "manual_offset_ms": 0.0,
            "min_track_duration_s": 45.0,
        }

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
        self._ffmpeg_path = _find_bin("ffmpeg")
        self._pactl_path = _find_bin("pactl")
        self._parec_path = _find_bin("parec")
        self.emit({
            "type": "deps",
            "mpv": bool(self._mpv_path),
            "yt_dlp": bool(self._yt_dlp_path),
            "ffmpeg": bool(self._ffmpeg_path),
            "pactl": bool(self._pactl_path),
            "parec": bool(self._parec_path),
            "mpv_path": self._mpv_path,
            "yt_dlp_path": self._yt_dlp_path,
            "install_hint": self._install_hint,
        })

    def _emit_duck(self) -> None:
        with self._monitors_lock:
            mon_count = len(self._monitors)
        with self._duck_lock:
            payload = {
                "type": "duck",
                "ducking": bool(self._duck_active),
                "gain": round(self._duck_gain, 3),
                "source": self._duck_source if self._duck_active else "",
                "enabled": bool(self._duck_enabled),
                "level": round(self._duck_level, 2),
                "mode": self._duck_mode,
                "monitored_count": mon_count,
            }
        self.emit(payload)

    def _emit_mix(
        self,
        stage: str,
        progress: float = 0.0,
        bpm_a: float = 0.0,
        bpm_b: float = 0.0,
        gain_trim_db: float = 0.0,
        offset_ms: float = 0.0,
        speed_ratio: float = 1.0,
        buffer_ms: float = 0.0,
        note: str = "",
    ) -> None:
        self._mix_stage = stage
        self.emit({
            "type": "mix",
            "stage": stage,
            "progress": round(_clamp(progress, 0.0, 1.0), 3),
            "bpm_a": round(bpm_a, 1),
            "bpm_b": round(bpm_b, 1),
            "gain_trim_db": round(gain_trim_db, 2),
            "offset_ms": round(offset_ms, 0),
            "speed_ratio": round(speed_ratio, 4),
            "buffer_ms": round(buffer_ms, 0),
            "note": note,
        })

    def _emit_state(self, state: str | None = None, seq: int | None = None, force: bool = True) -> None:
        now = time.monotonic()
        with self._state_lock:
            if state is not None:
                self._state = state
            cur_seq = self._active_seq if seq is None else seq
            if not force and (now - self._last_pos_emit) < 0.24:
                return
            self._last_pos_emit = now
            deck = self._primary
            payload = {
                "type": "state",
                "state": self._state,
                "seq": cur_seq,
                "position": round(deck.position, 2),
                "duration": round(deck.duration, 2),
                "volume": int(round(self._user_volume)),
                "muted": bool(self._muted),
            }
        self.emit(payload)

    def _effective_deck_volume(self, deck: _MpvDeck) -> float:
        with self._state_lock:
            base = float(self._user_volume)
        with self._duck_lock:
            dgain = float(self._duck_gain)
        vol = base * dgain * float(deck.loudness_trim) * float(deck.mix_gain)
        return round(_clamp(vol, 0.0, 100.0), 2)

    def _apply_effective_volume(self) -> None:
        with self._state_lock:
            primary = self._primary
            staging = self._staging
        primary.send(["set_property", "volume", self._effective_deck_volume(primary)])
        if staging is not None and staging.is_alive():
            staging.send(["set_property", "volume", self._effective_deck_volume(staging)])

    def _recompute_playback_state(self) -> None:
        with self._state_lock:
            if self._state in ("idle", "resolving", "error"):
                return
            deck = self._primary
            if deck.paused:
                next_state = "paused"
            elif deck.paused_for_cache or deck.core_idle:
                next_state = "buffering"
            else:
                next_state = "playing"
            changed = next_state != self._state
            self._state = next_state
        if changed:
            self._emit_state(force=True)
            self._need_rescan = True
            self._duck_eval_event.set()

    # ------------------------------------------------------------------
    # Sidechain RMS Ducking Watchers
    # ------------------------------------------------------------------

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

        own_pids: set[str] = set()
        with self._state_lock:
            for d in (self._primary, self._staging):
                if d is not None:
                    ps = d.pid_str()
                    if ps:
                        own_pids.add(ps)
        with self._duck_lock:
            custom_ignored = set(self._duck_ignored_custom)

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
            if pid_match and pid_match.group(1) in own_pids:
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
            if custom_ignored and any(ig in low_app or ig in low_node for ig in custom_ignored):
                continue

            label = _prettify_app_name(app_name or node_name or media_name)
            results.append((sid, label))

        return results

    def _get_rms_threshold(self) -> float:
        with self._duck_lock:
            return self._duck_rms_thresh

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
                        self._get_rms_threshold,
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

        dur = max(0.05, base_duration_s * min(1.0, dist / full_span))

        def _ramp_worker() -> None:
            t0 = time.monotonic()
            step_s = 1.0 / 30.0
            while self._running:
                with self._duck_lock:
                    if seq != self._duck_ramp_seq:
                        return
                elapsed = time.monotonic() - t0
                u = min(1.0, elapsed / dur)
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

            if is_active_playback and enabled:
                wait_s = 0.04 if ext_present != was_ducking else 2.0
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
                mode = self._duck_mode
                attack_s = self._duck_attack_delay_s
                hold_s = self._duck_release_hold_s
                down_s = self._duck_down_s
                up_s = self._duck_up_s

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
                    self._start_duck_ramp(1.0, up_s)
                continue

            now = time.monotonic()
            if self._need_rescan or (now - last_rescan_ts) >= 3.0:
                self._need_rescan = False
                last_rescan_ts = now
                cached_streams = self._list_external_sink_inputs()
                if mode == "rms" and self._parec_path:
                    self._sync_monitors(cached_streams)
                else:
                    self._stop_all_monitors()

            if mode == "rms" and self._parec_path:
                ext_now, ext_src = self._query_rms_audible()
            else:
                ext_now = len(cached_streams) > 0
                ext_src = cached_streams[0][1] if ext_now else ""

            action = ""
            with self._duck_lock:
                if ext_now:
                    if not self._ext_audio_present:
                        self._ext_first_seen_ts = now
                    self._ext_audio_present = True
                    self._ext_last_seen_ts = now

                    if not self._duck_active:
                        if (now - self._ext_first_seen_ts) >= attack_s:
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
                        if (now - self._ext_last_seen_ts) >= hold_s:
                            self._duck_active = False
                            self._duck_source = ""
                            action = "restore"

            if action == "duck":
                self._emit_duck()
                self._start_duck_ramp(target_level, down_s)
            elif action == "restore":
                self._emit_duck()
                self._start_duck_ramp(1.0, up_s)
            elif action == "source_changed":
                self._emit_duck()

    # ------------------------------------------------------------------
    # Dual-Deck mpv Lifecycle & IPC Event Routing
    # ------------------------------------------------------------------

    def _spawn_deck(self, deck: _MpvDeck, initial_mix_gain: float) -> bool:
        if deck.is_alive():
            return True

        deck.close()
        self._mpv_path = _find_bin("mpv")
        if not self._mpv_path:
            return False

        deck.mix_gain = initial_mix_gain
        deck.loudness_trim = 1.0
        deck.speed = 1.0
        deck.paused = False
        deck.paused_for_cache = False
        deck.core_idle = True

        max_bytes, readahead_s = BUFFER_PROFILES.get(self._buffer_preset, ("32MiB", 20))
        af_chain = build_lavfi_chain(self._dsp_cfg)
        with self._state_lock:
            muted = self._muted
            pitch_corr = self._pitch_correction

        cmd = [
            self._mpv_path,
            "--no-video",
            "--no-terminal",
            "--idle=yes",
            "--audio-display=no",
            "--audio-client-name=paithosh-mixcloud",
            "--title=Paithosh Music",
            "--cache=yes",
            f"--demuxer-max-bytes={max_bytes}",
            f"--demuxer-readahead-secs={readahead_s}",
            f"--audio-pitch-correction={'yes' if pitch_corr else 'no'}",
            f"--volume={self._effective_deck_volume(deck)}",
            f"--mute={'yes' if muted else 'no'}",
            f"--input-ipc-server={deck.sock_path}",
        ]
        if af_chain:
            cmd.append(f"--af={af_chain}")

        try:
            deck.proc = subprocess.Popen(
                cmd,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                preexec_fn=lambda: _set_pdeathsig(signal.SIGTERM),
            )
            try:
                with open(deck.pid_path, "w", encoding="utf-8") as fh:
                    fh.write(str(deck.proc.pid))
            except OSError:
                pass
        except OSError as exc:
            self.emit({"type": "error", "seq": self._active_seq, "message": f"Failed to launch mpv: {exc}"})
            return False

        deadline = time.monotonic() + 4.0
        sock: socket.socket | None = None
        while time.monotonic() < deadline and self._running:
            if deck.proc.poll() is not None:
                break
            if os.path.exists(deck.sock_path):
                try:
                    candidate = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                    candidate.settimeout(1.0)
                    candidate.connect(deck.sock_path)
                    sock = candidate
                    break
                except OSError:
                    try:
                        candidate.close()
                    except OSError:
                        pass
            time.sleep(0.05)

        if sock is None:
            deck.close()
            return False

        with deck._write_lock:
            deck.ipc_sock = sock

        deck.reader_thread = threading.Thread(target=self._deck_reader_loop, args=(deck, sock), daemon=True)
        deck.reader_thread.start()

        for prop_id, prop_name in (
            (1, "pause"),
            (2, "time-pos"),
            (3, "duration"),
            (4, "paused-for-cache"),
            (5, "core-idle"),
            (6, "mute"),
        ):
            deck.send(["observe_property", prop_id, prop_name])

        self._ensure_duck_watcher()
        return True

    def _deck_reader_loop(self, deck: _MpvDeck, sock: socket.socket) -> None:
        buf = b""
        while self._running:
            with deck._write_lock:
                if deck.ipc_sock is not sock:
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
                    self._handle_deck_event(deck, msg)
            except socket.timeout:
                continue
            except OSError:
                break

    def _handle_deck_event(self, deck: _MpvDeck, msg: dict[str, Any]) -> None:
        ev = msg.get("event")
        is_primary = False
        with self._state_lock:
            is_primary = deck is self._primary

        if ev == "property-change":
            name = msg.get("name")
            data = msg.get("data")
            if name == "time-pos" and isinstance(data, (int, float)) and data >= 0:
                deck.position = float(data)
                if is_primary:
                    self._emit_state(force=False)
            elif name == "duration" and isinstance(data, (int, float)) and data > 0:
                deck.duration = float(data)
                if is_primary:
                    self._emit_state(force=True)
            elif name == "pause" and isinstance(data, bool):
                deck.paused = data
                if is_primary:
                    self._recompute_playback_state()
            elif name == "paused-for-cache" and isinstance(data, bool):
                deck.paused_for_cache = data
                if is_primary:
                    self._recompute_playback_state()
            elif name == "core-idle" and isinstance(data, bool):
                deck.core_idle = data
                if is_primary:
                    self._recompute_playback_state()
            elif name == "mute" and isinstance(data, bool):
                deck.muted = data
                if is_primary:
                    with self._state_lock:
                        self._muted = data
                    self._emit_state(force=True)
        elif ev == "start-file":
            if is_primary:
                with self._state_lock:
                    if self._state != "idle":
                        self._state = "buffering"
                        if deck.pending_start_pos > 0.5:
                            deck.position = deck.pending_start_pos
                            deck.pending_start_pos = 0.0
                        else:
                            deck.position = 0.0
                self._emit_state(force=True)
                self._need_rescan = True
                self._duck_eval_event.set()
        elif ev == "playback-restart":
            deck.core_idle = False
            deck.paused_for_cache = False
            if is_primary:
                self._recompute_playback_state()
        elif ev == "end-file":
            if not is_primary:
                return
            reason = msg.get("reason", "")
            with self._state_lock:
                seq = self._active_seq
            if reason == "eof":
                with self._state_lock:
                    self._state = "idle"
                    deck.position = 0.0
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

    # ------------------------------------------------------------------
    # URL Resolution & Primary Play
    # ------------------------------------------------------------------

    def _resolve_url_ytdlp(self, url: str, timeout_s: float = 25.0) -> tuple[bool, str, str]:
        self._yt_dlp_path = _find_bin("yt-dlp")
        if not self._yt_dlp_path:
            return False, "", "Missing yt-dlp"
        try:
            proc = subprocess.run(
                [self._yt_dlp_path, "--no-playlist", "--no-warnings", "-f", "bestaudio/best", "-g", url],
                capture_output=True,
                text=True,
                timeout=timeout_s,
            )
        except subprocess.TimeoutExpired:
            return False, "", "Timed out resolving Mixcloud stream"
        except OSError as exc:
            return False, "", f"yt-dlp error: {exc}"

        if proc.returncode != 0:
            err_lines = [ln.strip() for ln in (proc.stderr or "").splitlines() if ln.strip()]
            return False, "", (err_lines[0] if err_lines else "Failed to resolve Mixcloud stream")

        urls = [ln.strip() for ln in (proc.stdout or "").splitlines() if ln.strip()]
        if not urls:
            return False, "", "No playable stream URL returned"
        return True, urls[0], ""

    def _resolve_and_play(self, url: str, seq: int, volume: int, muted: bool, start_position: float = 0.0) -> None:
        self._mpv_path = _find_bin("mpv")
        self._yt_dlp_path = _find_bin("yt-dlp")
        if not self._yt_dlp_path or not self._mpv_path:
            self.emit_deps()
            with self._state_lock:
                if seq != self._play_seq:
                    return
                self._state = "error"
            self.emit({"type": "error", "seq": seq, "message": "Missing mpv or yt-dlp"})
            self._emit_state(force=True)
            return

        ok, stream_url, err_msg = self._resolve_url_ytdlp(url)
        with self._state_lock:
            if seq != self._play_seq or not self._running:
                return
        if not ok:
            with self._state_lock:
                self._state = "error"
            self.emit({"type": "error", "seq": seq, "message": err_msg})
            self._emit_state(force=True)
            return

        with self._state_lock:
            self._user_volume = max(0, min(100, int(volume)))
            self._muted = bool(muted)
            primary = self._primary

        if not self._spawn_deck(primary, initial_mix_gain=1.0):
            with self._state_lock:
                if seq == self._play_seq:
                    self._state = "error"
            self.emit({"type": "error", "seq": seq, "message": "Failed to connect to mpv IPC"})
            self._emit_state(force=True)
            return

        with self._state_lock:
            if seq != self._play_seq:
                return
            self._active_seq = seq
            self._state = "buffering"
            primary.seq = seq
            primary.stream_url = stream_url
            primary.position = max(0.0, float(start_position))
            primary.pending_start_pos = max(0.0, float(start_position))
            primary.paused = False
            primary.paused_for_cache = False
            primary.core_idle = True
            primary.mix_gain = 1.0
            primary.loudness_trim = 1.0
            primary.speed = 1.0

        self._emit_state(force=True)
        primary.send(["set_property", "speed", 1.0])
        self._apply_effective_volume()
        primary.send(["set_property", "mute", bool(muted)])
        if start_position > 0.5:
            primary.send(["set_property", "start", f"+{start_position:.2f}"])
        else:
            primary.send(["set_property", "start", "none"])
        primary.send(["loadfile", stream_url, "replace"])
        primary.send(["set_property", "pause", False])
        self._need_rescan = True
        self._duck_eval_event.set()

    # ------------------------------------------------------------------
    # Progressive Audio Mix Engine
    # ------------------------------------------------------------------

    def _cancel_mix_internal(self, emit_idle: bool = True) -> None:
        with self._mix_lock:
            self._mix_seq += 1
            was_active = self._mix_stage != "idle"
        with self._state_lock:
            staging = self._staging
            self._staging = None
            self._primary.mix_gain = 1.0
        if staging is not None:
            staging.close()
        self._apply_effective_volume()
        self._need_rescan = True
        if emit_idle and was_active:
            self._emit_mix("idle")

    def _post_swap_release(self, deck: _MpvDeck, release_s: float) -> None:
        """Gently glide promoted deck's speed back to 1.00 and loudness trim to 1.00."""
        start_speed = deck.speed
        start_trim = deck.loudness_trim
        if abs(start_speed - 1.0) < 0.002 and abs(start_trim - 1.0) < 0.005:
            deck.speed = 1.0
            deck.loudness_trim = 1.0
            deck.send(["set_property", "speed", 1.0])
            self._apply_effective_volume()
            return

        dur = max(2.0, float(release_s))
        t0 = time.monotonic()
        while self._running:
            with self._state_lock:
                if deck is not self._primary or self._state == "idle":
                    return
            u = min(1.0, (time.monotonic() - t0) / dur)
            e = 0.5 - 0.5 * math.cos(math.pi * u)
            deck.speed = start_speed + (1.0 - start_speed) * e
            deck.loudness_trim = start_trim + (1.0 - start_trim) * e
            deck.send(["set_property", "speed", round(deck.speed, 4)])
            self._apply_effective_volume()
            if u >= 1.0:
                return
            time.sleep(0.1)

    def _progressive_mix_worker(
        self,
        mix_seq: int,
        url_b: str,
        next_seq: int,
        next_queue_index: int,
        immediate: bool,
    ) -> None:
        def _cancelled() -> bool:
            with self._mix_lock:
                return (not self._running) or (mix_seq != self._mix_seq)

        with self._state_lock:
            primary = self._primary
            url_a = primary.stream_url
            dur_a = primary.duration
            pos_a_now = primary.position
            next_deck_id = "B" if primary.deck_id == "A" else "A"

        if not url_a or not url_b:
            self._cancel_mix_internal(emit_idle=True)
            return

        cfg = dict(self._mix_cfg)
        blend_dur = _clamp(float(cfg.get("duration_s", 14.0)), 4.0, 30.0)
        curve = str(cfg.get("curve", "progressive"))
        win_s = _clamp(float(cfg.get("analysis_window_s", 12.0)), 6.0, 20.0)
        silence_db = _clamp(float(cfg.get("silence_threshold_db", -38.0)), -55.0, -24.0)
        manual_off_ms = _clamp(float(cfg.get("manual_offset_ms", 0.0)), -250.0, 250.0)
        tempo_release_s = _clamp(float(cfg.get("tempo_release_s", 10.0)), 4.0, 24.0)

        self._emit_mix("cueing", note="Resolving next track...")
        ok_b, stream_url_b, err_b = self._resolve_url_ytdlp(url_b, timeout_s=25.0)
        if _cancelled() or not ok_b:
            if not _cancelled():
                self._emit_mix("idle", note=err_b or "Next track unavailable")
                self._cancel_mix_internal(emit_idle=False)
            return

        staging = _MpvDeck(next_deck_id, self._runtime_dir)
        with self._state_lock:
            if _cancelled():
                staging.close()
                return
            self._staging = staging

        if not self._spawn_deck(staging, initial_mix_gain=0.0):
            self._cancel_mix_internal(emit_idle=True)
            return

        staging.seq = next_seq
        staging.stream_url = stream_url_b
        staging.mix_gain = 0.0
        staging.send(["set_property", "volume", 0.0])
        staging.send(["set_property", "start", "none"])
        staging.send(["loadfile", stream_url_b, "replace"])
        staging.send(["set_property", "pause", False])
        self._need_rescan = True

        # Parallel ffmpeg PCM probing for Track A outro & Track B intro while Deck B buffers
        self._emit_mix("analyzing", note="Matching loudness, tempo & offset...")
        buf_t0 = time.monotonic()
        self._ffmpeg_path = _find_bin("ffmpeg")

        res_a: dict[str, Any] = {"valid": False}
        res_b: dict[str, Any] = {"valid": False}

        def _probe_a() -> None:
            if not self._ffmpeg_path:
                return
            if dur_a > win_s + 2.0:
                start_a = max(0.0, dur_a - win_s - 4.0)
            else:
                start_a = max(0.0, pos_a_now)
            pcm = probe_stream_pcm(self._ffmpeg_path, url_a, start_a, win_s, timeout_s=8.5)
            if pcm:
                an = analyze_pcm_s16le(pcm, 11025, silence_db)
                if an.get("valid"):
                    # Shift local slice phase/bounds into Track A's absolute timeline
                    an["active_start_s"] = start_a + float(an["active_start_s"])
                    an["active_end_s"] = start_a + float(an["active_end_s"])
                    if float(an.get("bpm", 0.0)) > 0.0:
                        period = 60.0 / float(an["bpm"])
                        an["beat_phase_s"] = (start_a + float(an["beat_phase_s"])) % period
                    res_a.update(an)

        def _probe_b() -> None:
            if not self._ffmpeg_path:
                return
            pcm = probe_stream_pcm(self._ffmpeg_path, stream_url_b, 0.0, win_s, timeout_s=8.5)
            if pcm:
                an = analyze_pcm_s16le(pcm, 11025, silence_db)
                res_b.update(an)

        ta = threading.Thread(target=_probe_a, daemon=True)
        tb = threading.Thread(target=_probe_b, daemon=True)
        ta.start()
        tb.start()
        ta.join(timeout=9.0)
        tb.join(timeout=9.0)

        if _cancelled():
            return

        plan = compute_mix_plan(res_a, res_b, cfg)
        bpm_a = float(plan["bpm_a"])
        bpm_b = float(plan["bpm_b"])
        gain_trim_db = float(plan["gain_trim_db"])
        speed_b = float(plan["speed_b"])
        intro_offset_b = float(plan["intro_offset_b"])
        staging.loudness_trim = float(plan["loudness_trim_b"])
        staging.speed = speed_b
        staging.send(["set_property", "speed", speed_b])

        self._emit_mix(
            "syncing",
            bpm_a=bpm_a,
            bpm_b=bpm_b,
            gain_trim_db=gain_trim_db,
            speed_ratio=speed_b,
            note=plan["note"],
        )

        # Wait for Deck B initial stream buffer to become ready (still silent at vol=0)
        buf_deadline = time.monotonic() + 12.0
        while time.monotonic() < buf_deadline and not _cancelled():
            if not staging.core_idle and not staging.paused_for_cache:
                break
            time.sleep(0.05)

        buffer_ms = (time.monotonic() - buf_t0) * 1000.0
        if _cancelled():
            return

        # Hold silently paused at intro_offset_b until Deck A reaches blend_start_pos (when auto-cued)
        outro_end = float(plan.get("outro_active_end_s", 0.0))
        effective_end = outro_end if (outro_end > 5.0 and dur_a > 0.0) else dur_a
        blend_start_pos = max(primary.position, effective_end - blend_dur) if effective_end > 0.0 else primary.position

        if not immediate and dur_a > 0.0:
            if intro_offset_b > 0.2:
                staging.send(["seek", intro_offset_b, "absolute"])
            staging.send(["set_property", "pause", True])
            while not _cancelled():
                with self._state_lock:
                    cur_a = primary.position
                    a_paused = primary.paused
                    st = self._state
                if st in ("idle", "error"):
                    self._cancel_mix_internal(emit_idle=True)
                    return
                if not a_paused and cur_a >= (blend_start_pos - 0.35):
                    break
                time.sleep(0.05)

        if _cancelled():
            return

        # Compute exact beat-phase + buffer/seek latency alignment right before blend opens
        staging.send(["set_property", "pause", False])
        pos_a_ref = primary.position
        target_b = align_deck_b_target(
            pos_a=pos_a_ref,
            beat_anchor_a=float(plan["beat_phase_a"]) if plan["phase_sync"] else 0.0,
            beat_period_a=float(plan["beat_period_a"]) if plan["phase_sync"] else 0.0,
            intro_offset_b=intro_offset_b,
            beat_anchor_b=float(plan["beat_phase_b"]) if plan["phase_sync"] else 0.0,
            beat_period_b=float(plan["beat_period_b"]) if plan["phase_sync"] else 0.0,
            speed_b=speed_b,
            seek_comp_s=0.14,
            manual_offset_ms=manual_off_ms,
        )

        seek_t0 = time.monotonic()
        if target_b > 0.05:
            staging.send(["seek", round(target_b, 3), "absolute"])
            settle_deadline = time.monotonic() + 1.5
            while time.monotonic() < settle_deadline and not _cancelled():
                if (
                    not staging.paused_for_cache
                    and not staging.core_idle
                    and abs(staging.position - target_b) < 2.0
                    and (time.monotonic() - seek_t0) >= 0.10
                ):
                    break
                time.sleep(0.03)
        else:
            time.sleep(0.08)

        if _cancelled():
            return

        applied_offset_ms = round(target_b * 1000.0)
        # Active 30 Hz Progressive Blend Loop (respects pause cleanly)
        elapsed_blend = 0.0
        last_tick = time.monotonic()
        last_emit = 0.0
        step_s = 1.0 / 30.0
        tempo_glide_start_u = 0.45

        while not _cancelled():
            now = time.monotonic()
            dt = now - last_tick
            last_tick = now

            with self._state_lock:
                a_paused = primary.paused or self._state == "idle"
            if not a_paused:
                elapsed_blend += dt

            u = min(1.0, elapsed_blend / blend_dur)
            ga, gb = crossfade_gains(u, curve)
            primary.mix_gain = ga
            staging.mix_gain = gb

            if plan["tempo_matched"] and abs(speed_b - 1.0) > 0.002 and u >= tempo_glide_start_u:
                tu = min(1.0, (u - tempo_glide_start_u) / max(0.25, 1.0 - tempo_glide_start_u)) * 0.5
                staging.speed = speed_b + (1.0 - speed_b) * tu
                staging.send(["set_property", "speed", round(staging.speed, 4)])

            self._apply_effective_volume()

            if (now - last_emit) >= 0.10 or u >= 1.0:
                last_emit = now
                self._emit_mix(
                    "blending",
                    progress=u,
                    bpm_a=bpm_a,
                    bpm_b=bpm_b,
                    gain_trim_db=gain_trim_db,
                    offset_ms=applied_offset_ms,
                    speed_ratio=staging.speed,
                    buffer_ms=buffer_ms,
                    note=plan["note"],
                )

            if u >= 1.0:
                break
            time.sleep(step_s)

        if _cancelled():
            return

        # Atomic Deck Swap: Staging -> Primary
        self._emit_mix(
            "swapping",
            progress=1.0,
            bpm_a=bpm_a,
            bpm_b=bpm_b,
            gain_trim_db=gain_trim_db,
            offset_ms=applied_offset_ms,
            speed_ratio=staging.speed,
            buffer_ms=buffer_ms,
            note=plan["note"],
        )

        with self._state_lock:
            if _cancelled():
                return
            old_primary = self._primary
            self._primary = staging
            self._staging = None
            self._play_seq = next_seq
            self._active_seq = next_seq
            staging.mix_gain = 1.0
            self._state = "paused" if staging.paused else "playing"

        old_primary.close()
        self._apply_effective_volume()
        self._need_rescan = True
        self._duck_eval_event.set()

        # Continue gentle tempo/gain release into normalized 1.00x post-swap
        threading.Thread(target=self._post_swap_release, args=(staging, tempo_release_s), daemon=True).start()

        self.emit({
            "type": "mix_swapped",
            "seq": next_seq,
            "queue_index": next_queue_index,
            "position": round(staging.position, 2),
            "duration": round(staging.duration, 2),
        })
        self._emit_state(force=True)
        self._emit_mix("idle")

    # ------------------------------------------------------------------
    # Command Dispatch
    # ------------------------------------------------------------------

    def handle_command(self, obj: dict[str, Any]) -> None:
        cmd = str(obj.get("cmd", "")).strip()
        if cmd == "check_deps":
            self.emit_deps()
        elif cmd == "set_audio_dsp":
            for k in (
                "enabled", "bass_db", "mid_db", "high_db",
                "bass_freq", "bass_q", "mid_freq", "mid_q", "high_freq", "high_q",
                "preamp_db", "auto_headroom", "normalize", "norm_peak", "norm_frame_ms",
                "stereo_width", "crossfeed", "crossfeed_strength",
                "limiter", "limiter_ceiling_db",
            ):
                if k in obj:
                    self._dsp_cfg[k] = obj[k]
            chain = build_lavfi_chain(self._dsp_cfg)
            with self._state_lock:
                decks = [self._primary, self._staging]
            for d in decks:
                if d is not None and d.is_alive():
                    d.send(["set_property", "af", chain])
        elif cmd == "set_playback_config":
            bp = str(obj.get("buffer_preset", self._buffer_preset)).strip().lower()
            if bp in BUFFER_PROFILES:
                self._buffer_preset = bp
            if isinstance(obj.get("pitch_correction"), bool):
                self._pitch_correction = obj["pitch_correction"]
                with self._state_lock:
                    decks = [self._primary, self._staging]
                for d in decks:
                    if d is not None and d.is_alive():
                        d.send(["set_property", "audio-pitch-correction", self._pitch_correction])
        elif cmd == "set_ducking":
            with self._duck_lock:
                if isinstance(obj.get("enabled"), bool):
                    self._duck_enabled = obj["enabled"]
                if isinstance(obj.get("level"), (int, float)):
                    self._duck_level = _clamp(float(obj["level"]), 0.08, 0.75)
                if obj.get("mode") in ("rms", "presence"):
                    self._duck_mode = str(obj["mode"])
                if isinstance(obj.get("attack_ms"), (int, float)):
                    self._duck_attack_delay_s = _clamp(float(obj["attack_ms"]) / 1000.0, 0.02, 0.35)
                if isinstance(obj.get("release_hold_ms"), (int, float)):
                    self._duck_release_hold_s = _clamp(float(obj["release_hold_ms"]) / 1000.0, 0.10, 2.0)
                if isinstance(obj.get("fade_down_ms"), (int, float)):
                    self._duck_down_s = _clamp(float(obj["fade_down_ms"]) / 1000.0, 0.06, 1.2)
                if isinstance(obj.get("fade_up_ms"), (int, float)):
                    self._duck_up_s = _clamp(float(obj["fade_up_ms"]) / 1000.0, 0.12, 2.5)
                if isinstance(obj.get("rms_threshold_db"), (int, float)):
                    db_t = _clamp(float(obj["rms_threshold_db"]), -60.0, -25.0)
                    self._duck_rms_thresh = 10.0 ** (db_t / 20.0)
                if isinstance(obj.get("ignored_apps"), list):
                    self._duck_ignored_custom = {
                        str(x).strip().lower() for x in obj["ignored_apps"] if str(x).strip()
                    }
            self._need_rescan = True
            self._duck_eval_event.set()
            self._emit_duck()
        elif cmd == "set_mix_config":
            for k in (
                "enabled", "duration_s", "curve", "match_volume", "match_tempo",
                "match_offset", "cue_lead_s", "analysis_window_s",
                "max_tempo_shift_pct", "tempo_release_s", "max_gain_trim_db",
                "silence_threshold_db", "manual_offset_ms", "min_track_duration_s",
            ):
                if k in obj:
                    self._mix_cfg[k] = obj[k]
        elif cmd in ("prepare_mix", "mix_now"):
            url = str(obj.get("url", "")).strip()
            if not url:
                return
            immediate = (cmd == "mix_now") or bool(obj.get("immediate", False))
            next_seq = int(obj.get("next_seq", self._play_seq + 1))
            next_idx = int(obj.get("next_queue_index", -1))
            self._cancel_mix_internal(emit_idle=False)
            with self._mix_lock:
                self._mix_seq += 1
                mseq = self._mix_seq
            threading.Thread(
                target=self._progressive_mix_worker,
                args=(mseq, url, next_seq, next_idx, immediate),
                daemon=True,
            ).start()
        elif cmd == "cancel_mix":
            self._cancel_mix_internal(emit_idle=True)
        elif cmd == "play":
            url = str(obj.get("url", "")).strip()
            if not url:
                return
            self._cancel_mix_internal(emit_idle=True)
            vol = int(obj.get("volume", self._user_volume))
            muted = bool(obj.get("muted", self._muted))
            raw_start = obj.get("start_position", 0.0)
            start_pos = max(0.0, float(raw_start)) if isinstance(raw_start, (int, float)) else 0.0
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
                self._primary.position = start_pos
                self._primary.pending_start_pos = start_pos
                self._primary.duration = 0.0
                self._state = "resolving"
            self._emit_state(state="resolving", seq=seq, force=True)
            threading.Thread(
                target=self._resolve_and_play,
                args=(url, seq, vol, muted, start_pos),
                daemon=True,
            ).start()
        elif cmd == "pause":
            with self._state_lock:
                decks = [self._primary, self._staging]
            for d in decks:
                if d is not None and d.is_alive():
                    d.send(["set_property", "pause", True])
        elif cmd == "resume":
            with self._state_lock:
                decks = [self._primary, self._staging]
            for d in decks:
                if d is not None and d.is_alive():
                    d.send(["set_property", "pause", False])
        elif cmd == "toggle":
            self._primary.send(["cycle", "pause"])
            if self._staging is not None and self._staging.is_alive():
                self._staging.send(["set_property", "pause", not self._primary.paused])
        elif cmd == "seek":
            pos = obj.get("position")
            if isinstance(pos, (int, float)):
                target = max(0.0, float(pos))
                if self._primary.send(["seek", target, "absolute"]):
                    with self._state_lock:
                        self._primary.position = target
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
                decks = [self._primary, self._staging]
            for d in decks:
                if d is not None and d.is_alive():
                    d.send(["set_property", "mute", val])
        elif cmd == "stop":
            self._cancel_mix_internal(emit_idle=True)
            with self._state_lock:
                self._play_seq += 1
                self._state = "idle"
                self._primary.position = 0.0
                self._primary.duration = 0.0
                self._primary.paused = False
            self._primary.send(["stop"])
            self._emit_state(state="idle", force=True)
            self._duck_eval_event.set()
        elif cmd == "quit":
            self._running = False

    def shutdown(self) -> None:
        self._running = False
        self._duck_eval_event.set()
        self._cancel_mix_internal(emit_idle=False)
        self._stop_all_monitors()
        self._close_pactl_sub()
        self._primary.close()

    def run(self) -> None:
        _set_pdeathsig(signal.SIGTERM)
        _cleanup_stale_mpv(self._runtime_dir)
        atexit.register(self.shutdown)

        def _on_sig(_signum: int, _frame: object) -> None:
            self.shutdown()
            sys.exit(0)

        signal.signal(signal.SIGTERM, _on_sig)
        signal.signal(signal.SIGINT, _on_sig)
        if hasattr(signal, "SIGHUP"):
            signal.signal(signal.SIGHUP, _on_sig)

        self.emit_deps()
        self._emit_duck()
        self._emit_mix("idle")
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
