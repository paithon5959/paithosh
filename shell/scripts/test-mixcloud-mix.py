#!/usr/bin/env python3
"""Self-check suite for paithosh-mixcloud DSP filters and Progressive Audio Mix engine."""

from __future__ import annotations

import array
import importlib.util
import json
import math
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import wave


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DAEMON_PATH = os.path.join(SCRIPT_DIR, "paithosh-mixcloud.py")

spec = importlib.util.spec_from_file_location("paithosh_mixcloud", DAEMON_PATH)
assert spec is not None and spec.loader is not None
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def synth_beat_pcm(
    bpm: float,
    duration_s: float = 12.0,
    amp: float = 0.65,
    lead_silence_s: float = 0.0,
    phase_offset_s: float = 0.0,
    sample_rate: int = 11025,
) -> bytes:
    """Synthesize a crisp kick + sub-bass pulse train at `bpm` in mono s16le PCM."""
    n = int(round(duration_s * sample_rate))
    period = 60.0 / bpm
    buf = array.array("h", [0] * n)
    for i in range(n):
        t = i / float(sample_rate)
        if t < lead_silence_s:
            continue
        pos = (t - lead_silence_s + phase_offset_s) % period
        # Kick transient (exponential pitch drop 130->50 Hz over 90ms) + sustain tone
        env = math.exp(-pos * 22.0)
        freq = 50.0 + 80.0 * math.exp(-pos * 35.0)
        kick = math.sin(2.0 * math.pi * freq * pos) * env
        bed = 0.12 * math.sin(2.0 * math.pi * 110.0 * t)
        val = amp * (0.88 * kick + bed)
        ival = max(-32767, min(32767, int(round(val * 32767.0))))
        buf[i] = ival
    return buf.tobytes()


def test_pcm_analysis_and_mix_plan() -> None:
    pcm_a = synth_beat_pcm(bpm=120.0, duration_s=12.0, amp=0.60, lead_silence_s=0.0)
    pcm_b = synth_beat_pcm(bpm=124.0, duration_s=12.0, amp=0.30, lead_silence_s=2.0)

    an_a = mod.analyze_pcm_s16le(pcm_a, sample_rate=11025, silence_thresh_db=-38.0)
    an_b = mod.analyze_pcm_s16le(pcm_b, sample_rate=11025, silence_thresh_db=-38.0)

    assert an_a["valid"] and an_b["valid"], "PCM analysis failed on synthetic tracks"
    assert abs(an_a["bpm"] - 120.0) <= 1.5, f"Expected ~120 BPM, got {an_a['bpm']}"
    assert abs(an_b["bpm"] - 124.0) <= 1.5, f"Expected ~124 BPM, got {an_b['bpm']}"
    assert an_a["confidence"] >= 0.45, f"Low BPM confidence A: {an_a['confidence']}"
    assert an_b["confidence"] >= 0.45, f"Low BPM confidence B: {an_b['confidence']}"
    assert abs(an_b["active_start_s"] - 2.0) <= 0.20, f"Expected ~2.0s intro offset, got {an_b['active_start_s']}"

    # 0.60 vs 0.30 amplitude is +6.02 dB difference
    rms_delta = an_a["rms_dbfs"] - an_b["rms_dbfs"]
    assert 5.0 <= rms_delta <= 7.0, f"Expected ~+6dB RMS delta, got {rms_delta:.2f}"

    cfg = {
        "match_volume": True,
        "match_tempo": True,
        "match_offset": True,
        "max_gain_trim_db": 6.0,
        "max_tempo_shift_pct": 6.0,
    }
    plan = mod.compute_mix_plan(an_a, an_b, cfg)
    assert plan["tempo_matched"] is True, f"Expected tempo match: {plan}"
    expected_ratio = 120.0 / 124.0
    assert abs(plan["speed_b"] - expected_ratio) <= 0.025, f"Bad speed ratio: {plan['speed_b']}"
    assert 5.0 <= plan["gain_trim_db"] <= 6.0, f"Expected gain trim capped near +6dB, got {plan['gain_trim_db']}"
    assert abs(plan["intro_offset_b"] - 2.0) <= 0.20

    # Verify tight tempo cap rejects wide BPM gaps safely
    plan_tight = mod.compute_mix_plan(an_a, an_b, {**cfg, "max_tempo_shift_pct": 1.0})
    assert plan_tight["tempo_matched"] is False and plan_tight["speed_b"] == 1.0

    # Verify beat phase + buffer/manual offset alignment math
    t_b = mod.align_deck_b_target(
        pos_a=10.10,
        beat_anchor_a=0.0,
        beat_period_a=0.5,
        intro_offset_b=2.0,
        beat_anchor_b=0.25,
        beat_period_b=0.5,
        speed_b=1.0,
        seek_comp_s=0.10,
        manual_offset_ms=0.0,
    )
    # pos_a_future = 10.20 -> phase 0.20 -> phase_frac 0.40 -> desired_mod 0.20 on B
    # At base_b = 2.0, (2.0 - 0.25) % 0.5 = 0.25 -> delta = (0.20 - 0.25) % 0.5 = 0.45 -> target = 2.45
    assert abs(t_b - 2.45) < 1e-4, f"Expected 2.45s aligned target, got {t_b}"
    t_b_man = mod.align_deck_b_target(
        pos_a=10.10,
        beat_anchor_a=0.0,
        beat_period_a=0.5,
        intro_offset_b=2.0,
        beat_anchor_b=0.25,
        beat_period_b=0.5,
        speed_b=1.0,
        seek_comp_s=0.10,
        manual_offset_ms=50.0,
    )
    assert abs(t_b_man - 2.50) < 1e-4, f"Expected +50ms offset -> 2.50s, got {t_b_man}"

    # Verify graceful degradation on beatless/empty audio
    an_empty = mod.analyze_pcm_s16le(b"", 11025)
    assert an_empty["valid"] is False
    plan_fb = mod.compute_mix_plan(an_empty, an_b, cfg)
    assert plan_fb["valid"] is False and plan_fb["speed_b"] == 1.0 and plan_fb["gain_trim_db"] == 0.0


def test_crossfade_curves() -> None:
    for curve in ("progressive", "equal_power", "smooth_s", "linear"):
        ga0, gb0 = mod.crossfade_gains(0.0, curve)
        ga1, gb1 = mod.crossfade_gains(1.0, curve)
        assert abs(ga0 - 1.0) < 1e-6 and abs(gb0 - 0.0) < 1e-6, f"Bad start on {curve}: {(ga0, gb0)}"
        assert abs(ga1 - 0.0) < 1e-6 and abs(gb1 - 1.0) < 1e-6, f"Bad end on {curve}: {(ga1, gb1)}"

        prev_a, prev_b = ga0, gb0
        for step in range(1, 21):
            u = step / 20.0
            ga, gb = mod.crossfade_gains(u, curve)
            assert 0.0 <= ga <= 1.0 and 0.0 <= gb <= 1.0
            assert ga <= prev_a + 1e-9 and gb >= prev_b - 1e-9, f"Non-monotonic on {curve} at u={u}"
            if curve == "equal_power":
                assert abs(ga * ga + gb * gb - 1.0) < 1e-6
            prev_a, prev_b = ga, gb

    # Progressive curve intentionally brings Track B up early while Track A holds early
    ga_mid, gb_mid = mod.crossfade_gains(0.35, "progressive")
    assert abs(ga_mid - 1.0) < 1e-6 and gb_mid > 0.55, f"Unexpected progressive mid: {(ga_mid, gb_mid)}"


def test_lavfi_presets_in_mpv() -> None:
    mpv_bin = shutil.which("mpv")
    assert mpv_bin, "mpv binary required for DSP verification"

    presets = {
        "standard": {"enabled": True, "bass_db": 0, "mid_db": 0, "high_db": 0, "limiter": True},
        "warm": {"enabled": True, "bass_db": 4.5, "mid_db": 0.5, "high_db": -1.0, "bass_freq": 85, "stereo_width": 1.05, "limiter": True},
        "bass": {"enabled": True, "bass_db": 7.0, "mid_db": -1.0, "high_db": 1.5, "bass_freq": 75, "bass_q": 0.8, "auto_headroom": True, "limiter": True},
        "vocal": {"enabled": True, "bass_db": -1.0, "mid_db": 3.5, "high_db": 2.0, "mid_freq": 1600, "mid_q": 1.2, "normalize": True, "limiter": True},
        "club": {"enabled": True, "bass_db": 4.0, "mid_db": -1.5, "high_db": 4.5, "stereo_width": 1.15, "limiter": True},
        "custom_full": {
            "enabled": True, "bass_db": 6.0, "mid_db": -2.0, "high_db": 3.5,
            "bass_freq": 80, "bass_q": 0.85, "mid_freq": 1200, "mid_q": 1.4,
            "high_freq": 11000, "high_q": 0.75, "preamp_db": -1.0, "auto_headroom": True,
            "normalize": True, "norm_peak": 0.90, "norm_frame_ms": 180,
            "stereo_width": 1.20, "crossfeed": True, "crossfeed_strength": 0.30,
            "limiter": True, "limiter_ceiling_db": -0.5,
        },
        "bypass": {"enabled": False, "bass_db": 8.0},
    }

    assert mod.build_lavfi_chain(presets["bypass"]) == ""

    for name, cfg in presets.items():
        chain = mod.build_lavfi_chain(cfg)
        if not cfg.get("enabled", True):
            continue
        cmd = [mpv_bin, "--no-video", "--ao=null", "--end=0.08", "--audio-pitch-correction=yes"]
        if chain:
            cmd.append(f"--af={chain}")
        cmd.append("av://lavfi:sine=frequency=440:duration=0.15")
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=6.0)
        assert proc.returncode == 0, f"mpv failed on DSP preset '{name}' ({chain}): {proc.stderr}"


def test_worker_thread_spawn_survives_thread_exit() -> None:
    """Regression test: mpv spawned from a worker thread must NOT die when the thread exits."""
    import threading
    import time

    daemon = mod.MixcloudDaemon()
    ok_box = [False]

    def _spawn_from_worker() -> None:
        ok_box[0] = daemon._spawn_deck(daemon._primary, initial_mix_gain=1.0)

    t = threading.Thread(target=_spawn_from_worker)
    t.start()
    t.join(timeout=6.0)
    time.sleep(0.35)
    try:
        assert ok_box[0] is True, "Failed to spawn mpv deck"
        assert daemon._primary.is_alive(), (
            f"mpv died immediately after worker thread exited (poll={daemon._primary.proc.poll() if daemon._primary.proc else None})"
        )
    finally:
        daemon.shutdown()


def synth_musical_pcm(
    bpm: float = 120.0,
    root_hz: float = 220.0,
    is_minor: bool = True,
    duration_s: float = 12.0,
    amp: float = 0.60,
    bar_accent_offset_beats: int = 0,
    soft_melodic: bool = False,
    reverb_tail_s: float = 0.0,
    sample_rate: int = 11025,
) -> bytes:
    """Synthesize musical chord + beat PCM (or soft melodic / bar-accented / reverb tail)."""
    n = int(round(duration_s * sample_rate))
    period = 60.0 / bpm
    third = root_hz * (2.0 ** (3.0 / 12.0) if is_minor else 2.0 ** (4.0 / 12.0))
    fifth = root_hz * (2.0 ** (7.0 / 12.0))
    body_end = max(1.0, duration_s - reverb_tail_s)
    buf = array.array("h", [0] * n)
    for i in range(n):
        t = i / float(sample_rate)
        if t >= body_end:
            # Quiet decaying reverb tail (~ -14 dB below main body)
            tail_env = 0.07 * math.exp(-(t - body_end) * 0.4)
            chord = 0.35 * (
                math.sin(2.0 * math.pi * root_hz * t)
                + math.sin(2.0 * math.pi * third * t)
                + math.sin(2.0 * math.pi * fifth * t)
            )
            val = amp * tail_env * chord
        else:
            beat_idx = int(t / period)
            pos = t % period
            is_downbeat = ((beat_idx - bar_accent_offset_beats) % 4) == 0
            if soft_melodic:
                # Snare/woodblock mid-high transient (no sub-bass kick) + pad chord
                env = math.exp(-pos * 28.0)
                transient = (
                    math.sin(2.0 * math.pi * 920.0 * pos) * 0.55
                    + math.sin(2.0 * math.pi * 2450.0 * pos) * 0.45
                ) * env
                chord = 0.28 * (
                    math.sin(2.0 * math.pi * root_hz * t)
                    + math.sin(2.0 * math.pi * third * t)
                    + math.sin(2.0 * math.pi * fifth * t)
                )
                val = amp * (0.55 * transient + 0.45 * chord)
            else:
                beat_boost = 1.65 if is_downbeat else 0.72
                env = math.exp(-pos * 22.0)
                freq = 50.0 + 80.0 * math.exp(-pos * 35.0)
                kick = math.sin(2.0 * math.pi * freq * pos) * env * beat_boost
                chord = 0.25 * (
                    math.sin(2.0 * math.pi * root_hz * t)
                    + math.sin(2.0 * math.pi * third * t)
                    + math.sin(2.0 * math.pi * fifth * t)
                )
                val = amp * (0.62 * kick + 0.38 * chord)
        ival = max(-32767, min(32767, int(round(val * 32767.0))))
        buf[i] = ival
    return buf.tobytes()


def _wav_rms_dbfs(wav_path: str, t0_s: float, t1_s: float) -> float:
    with wave.open(wav_path, "rb") as w:
        sr = w.getframerate()
        nch = w.getnchannels()
        raw = w.readframes(w.getnframes())
    arr = array.array("h")
    arr.frombytes(raw)
    i0 = max(0, int(round(t0_s * sr * nch)))
    i1 = min(len(arr), int(round(t1_s * sr * nch)))
    sl = arr[i0:i1]
    if not sl:
        return -140.0
    rms = math.sqrt(sum(x * x for x in sl) / float(len(sl))) / 32768.0
    return 20.0 * math.log10(max(1e-7, rms))


def test_mpv_cubic_volume_and_equal_power() -> None:
    mpv_bin = shutil.which("mpv")
    assert mpv_bin, "mpv binary required"
    with tempfile.TemporaryDirectory() as td:
        src = os.path.join(td, "sine.wav")
        out = os.path.join(td, "out.wav")
        subprocess.run(
            ["ffmpeg", "-y", "-loglevel", "error", "-f", "lavfi", "-i", "sine=frequency=440:duration=0.4", src],
            check=True,
        )

        def _measure(vol: float) -> float:
            if os.path.exists(out):
                os.unlink(out)
            subprocess.run(
                [
                    mpv_bin, "--no-video", "--ao=pcm", f"--ao-pcm-file={out}",
                    "--audio-format=s16", "--volume-max=150", f"--volume={vol}", src,
                ],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=True,
            )
            return _wav_rms_dbfs(out, 0.08, 0.32)

        db_base = _measure(mod.mpv_volume_from_linear(80, 1.0, 1.0, 1.0))
        db_mid = _measure(mod.mpv_volume_from_linear(80, 1.0, math.cos(math.pi * 0.25), 1.0))
        db_boost = _measure(mod.mpv_volume_from_linear(80, 1.0, 1.0, 10.0 ** (4.0 / 20.0)))

        mid_delta = db_mid - db_base
        boost_delta = db_boost - db_base
        assert -3.26 <= mid_delta <= -2.76, f"Expected -3.01dB equal-power midpoint, got {mid_delta:+.2f}dB"
        assert 3.70 <= boost_delta <= 4.30, f"Expected +4.00dB loudness trim, got {boost_delta:+.2f}dB"


def test_3band_bpm_and_phrase() -> None:
    # 1. Soft melodic track without sub-bass kick
    pcm_mel = synth_musical_pcm(bpm=104.0, root_hz=220.0, is_minor=True, duration_s=12.0, soft_melodic=True)
    an_mel = mod.analyze_pcm_s16le(pcm_mel, 11025, -38.0)
    assert an_mel["valid"] and abs(an_mel["bpm"] - 104.0) <= 1.5, f"Bad melodic BPM: {an_mel}"
    assert an_mel["confidence"] >= 0.35, f"Low melodic BPM confidence: {an_mel['confidence']}"

    # 2. 4-beat phrase downbeat detection (Beat-1 accented at beat offset 1 -> 0.5s, 2.5s, 4.5s...)
    pcm_bar = synth_musical_pcm(bpm=120.0, root_hz=220.0, is_minor=True, duration_s=12.0, bar_accent_offset_beats=1)
    an_bar = mod.analyze_pcm_s16le(pcm_bar, 11025, -38.0)
    assert an_bar["bar_confidence"] >= 0.15, f"Low bar confidence: {an_bar}"
    bar_err = min(abs(an_bar["bar_phase_s"] - 0.5), 2.0 - abs(an_bar["bar_phase_s"] - 0.5))
    assert bar_err <= 0.08, f"Expected bar_phase_s ~0.50s, got {an_bar['bar_phase_s']}"

    # 3. Smart outro energy drop detection before quiet reverb tail
    pcm_tail = synth_musical_pcm(bpm=120.0, duration_s=12.0, reverb_tail_s=3.2)
    an_tail = mod.analyze_pcm_s16le(pcm_tail, 11025, -38.0)
    assert 8.3 <= an_tail["outro_cue_s"] <= 9.6, f"Expected outro_cue_s near 8.8s, got {an_tail['outro_cue_s']}"


def test_key_and_harmonic_adaptation() -> None:
    pcm_am = synth_musical_pcm(bpm=120.0, root_hz=220.0, is_minor=True, duration_s=12.0)    # 8A
    pcm_c = synth_musical_pcm(bpm=122.0, root_hz=261.63, is_minor=False, duration_s=12.0)   # 8B (Relative)
    pcm_bbm = synth_musical_pcm(bpm=122.0, root_hz=233.08, is_minor=True, duration_s=12.0)  # 3A (Clash)

    t0 = time.monotonic()
    an_am = mod.analyze_pcm_s16le(pcm_am, 11025, -38.0)
    dt_ms = (time.monotonic() - t0) * 1000.0
    assert dt_ms < 250.0, f"12s PCM analysis too slow: {dt_ms:.1f}ms"

    an_c = mod.analyze_pcm_s16le(pcm_c, 11025, -38.0)
    an_bbm = mod.analyze_pcm_s16le(pcm_bbm, 11025, -38.0)

    assert an_am["camelot"] == "8A" and an_am["key_confidence"] >= 0.40, f"Bad Am key: {an_am}"
    assert an_c["camelot"] == "8B" and an_c["key_confidence"] >= 0.40, f"Bad C key: {an_c}"
    assert an_bbm["camelot"] == "3A" and an_bbm["key_confidence"] >= 0.40, f"Bad Bbm key: {an_bbm}"

    cfg = {
        "duration_s": 16.0,
        "eq_mode": "bass_swap",
        "harmonic_adapt": True,
        "phrase_sync": True,
        "match_volume": True,
        "match_tempo": True,
        "match_offset": True,
        "max_gain_trim_db": 6.0,
        "max_tempo_shift_pct": 6.0,
    }
    plan_rel = mod.compute_mix_plan(an_am, an_c, cfg)
    assert plan_rel["key_compat"] >= 0.90 and plan_rel["key_compat_label"] == "Relative", plan_rel
    assert plan_rel["effective_duration_s"] == 16.0 and plan_rel["effective_eq_mode"] == "bass_swap", plan_rel

    plan_clash = mod.compute_mix_plan(an_am, an_bbm, cfg)
    assert plan_clash["key_compat"] <= 0.30 and plan_clash["key_compat_label"] == "Clash", plan_clash
    assert plan_clash["effective_duration_s"] < 16.0 and plan_clash["effective_eq_mode"] == "stem_eq", plan_clash


def test_coupled_tempo_and_pll() -> None:
    bpm_a, bpm_b = 120.0, 125.0
    spd_b_init = bpm_a / bpm_b
    for step in range(21):
        u = step / 20.0
        sa, sb = mod.compute_coupled_speeds(u, bpm_a, bpm_b, spd_b_init, coupled=True)
        assert abs(sa - 1.0) <= 0.0301, f"Deck A speed exceeded ±3%: {sa}"
        assert abs(sa * bpm_a - sb * bpm_b) <= 0.05, f"Tempo drift at u={u}: {(sa, sb)}"

    # Micro-PLL wrapped phase error around period=0.5s
    e_ahead = mod.compute_phase_error_s(10.475, 0.0, 0.5, 2.025, 0.0, 0.5)   # B wrapped +50ms ahead
    e_behind = mod.compute_phase_error_s(10.025, 0.0, 0.5, 2.475, 0.0, 0.5)  # B is -50ms behind
    assert abs(e_ahead - 0.05) < 1e-4, f"Expected +0.05s wrapped phase error, got {e_ahead}"
    assert abs(e_behind + 0.05) < 1e-4, f"Expected -0.05s wrapped phase error, got {e_behind}"


def test_mixtr_eq_modes_in_mpv() -> None:
    mpv_bin = shutil.which("mpv")
    assert mpv_bin, "mpv binary required"
    assert mod.build_mix_eq_filter("out", "clean", 0.0, 10.0) == ""

    with tempfile.TemporaryDirectory() as td:
        src = os.path.join(td, "bass_mid.wav")
        out = os.path.join(td, "eq_out.wav")
        subprocess.run(
            [
                "ffmpeg", "-y", "-loglevel", "error", "-f", "lavfi",
                "-i", "aevalsrc=0.45*sin(2*PI*90*t)+0.25*sin(2*PI*2200*t):s=44100:d=3.2",
                src,
            ],
            check=True,
        )

        for mode in ("bass_swap", "stem_eq", "filter_sweep"):
            for role in ("out", "in"):
                flt = mod.build_mix_eq_filter(role, mode, 0.4, 2.2, xover_hz=180.0, depth_db=18.0)
                assert flt.startswith("@mixtr:lavfi=[")
                p = subprocess.run(
                    [mpv_bin, "--no-video", "--ao=null", "--end=0.25", f"--af={flt}", src],
                    capture_output=True, text=True, timeout=6.0,
                )
                assert p.returncode == 0, f"mpv failed on @mixtr {mode}/{role}: {p.stderr}"

        # Measure actual 90Hz attenuation on bass_swap out vs in using 90Hz pure sine
        src_bass = os.path.join(td, "bass90.wav")
        subprocess.run(
            ["ffmpeg", "-y", "-loglevel", "error", "-f", "lavfi", "-i", "sine=frequency=90:duration=3.2", src_bass],
            check=True,
        )
        for role in ("out", "in"):
            if os.path.exists(out):
                os.unlink(out)
            flt = mod.build_mix_eq_filter(role, "bass_swap", 0.4, 2.2, xover_hz=180.0, depth_db=18.0)
            subprocess.run(
                [mpv_bin, "--no-video", "--ao=pcm", f"--ao-pcm-file={out}", "--audio-format=s16", f"--af={flt}", src_bass],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True,
            )
            early = _wav_rms_dbfs(out, 0.10, 0.35)
            late = _wav_rms_dbfs(out, 2.75, 3.00)
            if role == "out":
                assert early - late >= 10.0, f"Expected >=10dB bass cut on out: {early:.1f} -> {late:.1f}"
            else:
                assert late - early >= 10.0, f"Expected >=10dB bass rise on in: {early:.1f} -> {late:.1f}"

        # Verify @mixtr + @dsp IPC isolation
        sock_path = os.path.join(td, "ipc.sock")
        proc = subprocess.Popen(
            [
                mpv_bin, "--no-video", "--ao=null", "--idle=yes",
                "--af=@dsp:lavfi=[alimiter=limit=0.944]", f"--input-ipc-server={sock_path}", src,
            ],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        try:
            for _ in range(40):
                if os.path.exists(sock_path):
                    break
                time.sleep(0.05)
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.settimeout(1.0)
            s.connect(sock_path)
            time.sleep(0.2)

            def _call(cmd: list, rid: int) -> dict:
                s.sendall((json.dumps({"command": cmd, "request_id": rid}) + "\n").encode())
                buf = b""
                deadline = time.monotonic() + 1.0
                while time.monotonic() < deadline:
                    buf += s.recv(4096)
                    while b"\n" in buf:
                        ln, buf = buf.split(b"\n", 1)
                        msg = json.loads(ln.decode())
                        if msg.get("request_id") == rid:
                            return msg
                return {}

            eq = mod.build_mix_eq_filter("out", "stem_eq", 0.5, 2.0)
            assert _call(["af", "pre", eq], 1).get("error") == "success"
            assert _call(["af", "remove", "@dsp"], 2).get("error") == "success"
            assert _call(["af", "add", "@dsp:lavfi=[bass=g=3:f=90:t=q:w=0.7,alimiter=limit=0.944]"], 3).get("error") == "success"
            assert _call(["af", "remove", "@mixtr"], 4).get("error") == "success"
            labels = [f.get("label") for f in (_call(["get_property", "af"], 5).get("data") or [])]
            assert labels == ["dsp"], f"Expected only ['dsp'] after removing @mixtr, got {labels}"
            s.close()
        finally:
            proc.terminate()
            proc.wait(timeout=2)


def main() -> None:
    test_pcm_analysis_and_mix_plan()
    test_crossfade_curves()
    test_lavfi_presets_in_mpv()
    test_mpv_cubic_volume_and_equal_power()
    test_3band_bpm_and_phrase()
    test_key_and_harmonic_adaptation()
    test_coupled_tempo_and_pll()
    test_mixtr_eq_modes_in_mpv()
    test_worker_thread_spawn_survives_thread_exit()
    print("PASS: All paithosh-mixcloud DSP, cubic volume, key, phrase, coupled-tempo, PLL, @mixtr & mpv checks passed.")


if __name__ == "__main__":
    main()
