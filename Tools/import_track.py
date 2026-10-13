#!/usr/bin/env python3
"""Import a built-in lofi track: WAV master -> app-ready CAF + beat map.

Put masters (e.g. Suno WAV exports) in Assets/MusicMasters/ (git-ignored,
never bundled). For each one this writes, into Assets/Music/:
    <slug>.caf    AAC 128 kbps in CAF (~1 MB per minute)
    <slug>.json   beat map (CLAUDE.md Section 9): track, title, bpm, offset, cues

BPM and offset are estimated offline from the audio (spectral-flux onsets +
autocorrelation), never at runtime. Check them by ear; edit the JSON if needed.
Existing `cues` in a beat map are kept when re-importing.

Usage:
    python3 Tools/import_track.py                 # every WAV in Assets/MusicMasters/
    python3 Tools/import_track.py path/to/song.wav

Requires: Python 3.10+, numpy, macOS `afconvert`.
"""
import json
import re
import subprocess
import sys
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
MASTERS = ROOT / "Assets/MusicMasters"
OUT_DIR = ROOT / "Assets/Music"

ANALYSIS_RATE = 11025
FRAME, HOP = 1024, 256
BPM_RANGE = (60, 180)


def slug(name):
    return re.sub(r"[^a-z0-9]+", "-", name.lower().replace("'", "")).strip("-")


def read_mono(path):
    with wave.open(str(path), "rb") as w:
        channels, width, rate, n = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
        raw = w.readframes(n)
    if width == 2:
        data = np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768
    elif width == 3:
        b = np.frombuffer(raw, dtype=np.uint8).reshape(-1, 3)
        ints = (b[:, 0].astype(np.int32) | (b[:, 1].astype(np.int32) << 8) | (b[:, 2].astype(np.int32) << 16))
        ints = np.where(ints & 0x800000, ints - 0x1000000, ints)
        data = ints.astype(np.float32) / 8388608
    elif width == 4:
        data = np.frombuffer(raw, dtype="<i4").astype(np.float32) / 2147483648
    else:
        raise SystemExit(f"{path.name}: unsupported sample width {width}")
    mono = data.reshape(-1, channels).mean(axis=1)
    step = max(1, rate // ANALYSIS_RATE)  # crude decimation is fine for tempo
    return mono[::step], rate / step


def onset_envelope(signal):
    frames = 1 + (len(signal) - FRAME) // HOP
    index = np.arange(FRAME)[None, :] + HOP * np.arange(frames)[:, None]
    spectrum = np.abs(np.fft.rfft(signal[index] * np.hanning(FRAME), axis=1))
    flux = np.maximum(0, np.diff(np.log1p(spectrum * 10), axis=0)).sum(axis=1)
    flux -= np.convolve(flux, np.ones(16) / 16, mode="same")  # remove slow trends
    return np.maximum(flux, 0)


def estimate_tempo(envelope, rate):
    frames_per_second = rate / HOP
    ac = np.correlate(envelope, envelope, mode="full")[len(envelope) - 1:]
    lags = np.arange(len(ac))
    with np.errstate(divide="ignore"):
        bpm_at_lag = 60 * frames_per_second / lags
    valid = (bpm_at_lag >= BPM_RANGE[0]) & (bpm_at_lag <= BPM_RANGE[1])
    # Gentle preference for lofi tempos (log-Gaussian around 85 bpm).
    weight = np.exp(-0.5 * (np.log2(np.where(valid, bpm_at_lag, 85) / 85) / 0.6) ** 2)
    score = np.where(valid, ac * weight, 0)
    best = int(np.argmax(score))
    # Parabolic interpolation for a sub-frame lag.
    if 0 < best < len(score) - 1:
        a, b, c = score[best - 1], score[best], score[best + 1]
        best = best + 0.5 * (a - c) / (a - 2 * b + c) if (a - 2 * b + c) != 0 else best
    bpm = 60 * frames_per_second / best

    # Offset: the beat phase that lines up with the most onset energy.
    period = best
    phases = np.arange(int(np.ceil(period)))
    energy = [envelope[np.round(np.arange(p, len(envelope), period)).astype(int).clip(0, len(envelope) - 1)].sum()
              for p in phases]
    offset = float(phases[int(np.argmax(energy))]) / frames_per_second
    return round(float(bpm), 1), round(offset, 3)


def import_track(master):
    name = master.stem
    out = slug(name)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    caf = OUT_DIR / f"{out}.caf"
    subprocess.run(["afconvert", "-f", "caff", "-d", "aac", "-b", "128000", str(master), str(caf)], check=True)

    signal, rate = read_mono(master)
    bpm, offset = estimate_tempo(onset_envelope(signal), rate)

    beat_map_path = OUT_DIR / f"{out}.json"
    cues = []
    if beat_map_path.exists():
        cues = json.loads(beat_map_path.read_text()).get("cues", [])
    beat_map = {"track": caf.name, "title": name, "bpm": bpm, "offset": offset, "cues": cues}
    beat_map_path.write_text(json.dumps(beat_map, indent=2, ensure_ascii=False) + "\n")
    size_mb = caf.stat().st_size / 1_000_000
    print(f"{master.name} -> {caf.relative_to(ROOT)} ({size_mb:.1f} MB), {bpm} bpm, offset {offset} s")


def main():
    masters = [Path(p) for p in sys.argv[1:]] or sorted(MASTERS.glob("*.wav"))
    if not masters:
        raise SystemExit(f"no WAV files given and none in {MASTERS.relative_to(ROOT)}/")
    for master in masters:
        import_track(master)


if __name__ == "__main__":
    main()
