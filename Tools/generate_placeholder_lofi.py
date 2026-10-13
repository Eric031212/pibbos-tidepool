#!/usr/bin/env python3
"""Synthesize a placeholder lofi loop until the real (Suno) tracks exist.

8 bars at 72 bpm: soft electric-piano chords (Fmaj7 - Em7 - Dm7 - Cmaj7),
a round bass, a gentle kick and hat, and a little vinyl crackle. Writes a
gapless-loop CAF (IMA4) plus the beat map from CLAUDE.md Section 9.

Outputs:
    Assets/Music/placeholder-loop.caf
    Assets/Music/placeholder-loop.json

Usage:
    python3 Tools/generate_placeholder_lofi.py

Requires: Python 3.10+ (standard library only) and macOS `afconvert`.
"""
import json
import math
import random
import struct
import subprocess
import tempfile
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "Assets/Music"
NAME = "placeholder-loop"

RATE = 22050
BPM = 72
BEAT = 60 / BPM
BARS = 8
LENGTH = int(BARS * 4 * BEAT * RATE)

# MIDI note numbers, two bars per chord.
CHORDS = [[53, 57, 60, 64], [52, 55, 59, 62], [50, 53, 57, 60], [48, 52, 55, 59]]


def freq(note):
    return 440.0 * 2 ** ((note - 69) / 12)


def add(buffer, start, samples):
    for k, value in enumerate(samples):
        i = (start + k) % LENGTH  # wrap so the loop tail flows into its start
        buffer[i] += value


def epiano(note, seconds, volume):
    f = freq(note)
    n = int(seconds * RATE)
    out = []
    for k in range(n):
        t = k / RATE
        env = math.exp(-t * 1.6) * min(1.0, t * 200)
        out.append(volume * env * (math.sin(2 * math.pi * f * t) + 0.25 * math.sin(4 * math.pi * f * t)))
    return out


def bass(note, seconds, volume):
    f = freq(note - 12)
    n = int(seconds * RATE)
    return [volume * math.exp(-k / RATE * 2.2) * min(1.0, k / 300) * math.sin(2 * math.pi * f * k / RATE)
            for k in range(n)]


def kick(volume):
    n = int(0.25 * RATE)
    out, phase = [], 0.0
    for k in range(n):
        t = k / RATE
        phase += 2 * math.pi * (45 + 70 * math.exp(-t * 30)) / RATE
        out.append(volume * math.exp(-t * 14) * math.sin(phase))
    return out


def hat(volume, rng):
    n = int(0.05 * RATE)
    return [volume * math.exp(-k / RATE * 90) * (rng.random() * 2 - 1) for k in range(n)]


def main():
    rng = random.Random(7)
    buffer = [0.0] * LENGTH
    bar = 4 * BEAT
    for b in range(BARS):
        chord = CHORDS[(b // 2) % len(CHORDS)]
        bar_start = b * bar
        for hit in (0, 2.5):  # lazy, slightly off-grid comping
            start = int((bar_start + hit * BEAT + rng.uniform(0, 0.02)) * RATE)
            for j, note in enumerate(chord):
                add(buffer, start + j * 90, epiano(note, 2.4, 0.06))  # gentle strum
        for beat in (0, 2):
            add(buffer, int((bar_start + beat * BEAT) * RATE), bass(chord[0], 1.4, 0.18))
            add(buffer, int((bar_start + beat * BEAT) * RATE), kick(0.35))
        for eighth in range(8):
            if eighth % 2 == 1:
                swing = 0.08 * BEAT
                add(buffer, int((bar_start + eighth * BEAT / 2 + swing) * RATE), hat(0.05, rng))

    # Vinyl crackle and a one-pole low-pass for warmth.
    for _ in range(int(BARS * 4 * BEAT * 6)):
        buffer[rng.randrange(LENGTH)] += rng.uniform(-0.04, 0.04)
    previous = 0.0
    for _ in range(2):  # two passes so the wrap-around point is smooth too
        for i in range(LENGTH):
            previous += 0.35 * (buffer[i] - previous)
            buffer[i] = previous

    peak = max(abs(v) for v in buffer) or 1.0
    frames = b"".join(struct.pack("<h", int(v / peak * 0.8 * 32767)) for v in buffer)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        wav_path = Path(tmp) / f"{NAME}.wav"
        with wave.open(str(wav_path), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(frames)
        # IMA4 in CAF: small, and loops without the encoder gap AAC adds.
        subprocess.run(["afconvert", "-f", "caff", "-d", "ima4", str(wav_path), str(OUT_DIR / f"{NAME}.caf")], check=True)

    beat_map = {"track": f"{NAME}.caf", "bpm": BPM, "offset": 0.0, "cues": []}
    (OUT_DIR / f"{NAME}.json").write_text(json.dumps(beat_map, indent=2) + "\n")
    print(f"wrote {OUT_DIR.relative_to(ROOT)}/{NAME}.caf ({LENGTH / RATE:.1f} s loop)")


if __name__ == "__main__":
    main()
