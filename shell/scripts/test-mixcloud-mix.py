#!/usr/bin/env python3
"""Self-check suite for paithosh-mixcloud DSP filters and Progressive Audio Mix engine."""

from __future__ import annotations

import array
import importlib.util
import math
import os
import shutil
import subprocess
import sys


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


def main() -> None:
    test_pcm_analysis_and_mix_plan()
    test_crossfade_curves()
    test_lavfi_presets_in_mpv()
    print("PASS: All paithosh-mixcloud DSP, BPM, loudness, offset, crossfade & mpv checks passed.")


if __name__ == "__main__":
    main()
