#!/usr/bin/env python3
"""Synthesize Tidepool's ambient "tide sounds" (v2.0): seamless loops of the
pool's sounds, mixed by the app from the real weather and time of day.

Every sound is built in the frequency domain (shaped noise) and with
envelopes and events that wrap around the loop, so each file loops with no
seam or click. No samples or recordings are used: the sounds are ours.

Loops (mono, 32 kHz, 48 s, Apple Lossless in CAF so they loop gaplessly):
    waves        gentle daytime waves lapping
    nightwaves   slower, softer, darker waves for the night
    rain         rain on the water: a soft wash plus droplets and plinks
    crickets     summer-night crickets (layered over nightwaves)
    wind         a soft wind for snowy days

Outputs: Assets/Sounds/<name>.caf (and preview WAVs in build/tide-preview/)

Usage:
    python3 Tools/generate_tide_sounds.py

Requires: Python 3.10+, numpy, macOS afconvert
"""
import subprocess
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "Assets/Sounds"
PREVIEW = ROOT / "build/tide-preview"
RATE = 32_000
SECONDS = 48
N = RATE * SECONDS
rng = np.random.default_rng(20261115)


def shaped_noise(shape):
    """Circular noise with a spectral `shape(freqs) -> gain`: loops perfectly."""
    freqs = np.fft.rfftfreq(N, 1 / RATE)
    spectrum = (rng.standard_normal(len(freqs)) + 1j * rng.standard_normal(len(freqs))) * shape(np.maximum(freqs, 1))
    spectrum[0] = 0
    out = np.fft.irfft(spectrum, N)
    return out / (np.abs(out).max() + 1e-9)


def band(lo, hi, tilt=0.0):
    """Smooth band-pass gain, with a 1/f^tilt slope inside."""
    def shape(f):
        g = 1 / (1 + (lo / f) ** 4) / (1 + (f / hi) ** 4)
        return g * f ** (-tilt)
    return shape


def wrap_add(buf, event, start):
    """Adds `event` at sample `start`, wrapping past the end (seamless loop)."""
    idx = (start + np.arange(len(event))) % N
    np.add.at(buf, idx, event)


def swell_envelope(period, jitter, rise, fall, floor):
    """Waves: a swell every ~`period` s (wrapping), rising `rise` s and easing off over `fall` s."""
    env = np.full(N, floor)
    count = round(SECONDS / period)
    t = np.arange(int((rise + fall) * RATE)) / RATE
    shape = np.where(t < rise, np.sin(np.pi / 2 * t / rise) ** 2, np.exp(-(t - rise) / (fall / 3)))
    for k in range(count):
        start = int((k * SECONDS / count + rng.uniform(-jitter, jitter)) * RATE)
        wrap_add(env, shape * rng.uniform(0.7, 1.0), start)
    return env / env.max()


def periodic_lfo(cycles, phase=0.0):
    """A slow sine that completes whole cycles in the loop."""
    t = np.arange(N) / N
    return 0.5 + 0.5 * np.sin(2 * np.pi * cycles * t + phase)


def waves(dark=False):
    body = shaped_noise(band(40, 260 if dark else 520, tilt=0.6))
    hiss = shaped_noise(band(900, 3200 if dark else 5200, tilt=0.3))
    env = swell_envelope(period=10.0 if dark else 7.0, jitter=1.2, rise=2.2, fall=4.5, floor=0.18)
    crest = env ** 3  # the hiss of foam only near the top of a swell
    mix = body * (0.25 + 0.75 * env) + hiss * crest * (0.18 if dark else 0.32)
    return mix * (0.55 if dark else 0.8)


def rain():
    wash = shaped_noise(band(400, 7000, tilt=0.4)) * (0.22 + 0.04 * periodic_lfo(3))
    low = shaped_noise(band(60, 300, tilt=0.5)) * 0.12
    buf = wash + low
    # droplets: tiny bright ticks; plinks: little falling tones on the water
    for _ in range(int(60 * SECONDS)):
        length = int(rng.uniform(0.004, 0.012) * RATE)
        t = np.arange(length) / RATE
        tick = np.sin(2 * np.pi * rng.uniform(2500, 6000) * t) * np.exp(-t / (length / RATE / 4))
        wrap_add(buf, tick * rng.uniform(0.05, 0.22), int(rng.uniform(0, N)))
    for _ in range(int(5 * SECONDS)):
        length = int(0.06 * RATE)
        t = np.arange(length) / RATE
        f0 = rng.uniform(700, 1500)
        phase = 2 * np.pi * np.cumsum(f0 * (1 - 0.35 * t / t[-1])) / RATE
        plink = np.sin(phase) * np.exp(-t / 0.015)
        wrap_add(buf, plink * rng.uniform(0.05, 0.14), int(rng.uniform(0, N)))
    return buf


def crickets():
    buf = np.zeros(N)
    for carrier, every, pulses, level in ((4400, 0.9, 3, 0.10), (4900, 1.25, 4, 0.06)):
        t = np.arange(int(0.12 * RATE)) / RATE
        gate = (np.sin(2 * np.pi * 32 * t) > 0.2).astype(float)
        gate[int(pulses / 32 * RATE):] = 0
        chirp = np.sin(2 * np.pi * carrier * t) * gate * np.hanning(len(t))
        count = round(SECONDS / every)
        for k in range(count):
            start = int((k * SECONDS / count + rng.uniform(-0.04, 0.04)) * RATE)
            wrap_add(buf, chirp * level * rng.uniform(0.6, 1.0), start)
    return buf * (0.6 + 0.4 * periodic_lfo(4, 1.0))  # they come and go a little


def wind():
    low = shaped_noise(band(120, 700, tilt=0.8))
    high = shaped_noise(band(500, 2000, tilt=0.5))
    a, b = periodic_lfo(3), periodic_lfo(5, 2.0)
    gusts = 0.35 + 0.65 * periodic_lfo(2, 0.5) ** 2
    return (low * a + high * b * 0.5) * gusts * 0.5


SOUNDS = {"waves": waves, "nightwaves": lambda: waves(dark=True), "rain": rain, "crickets": crickets, "wind": wind}


def write(name, samples):
    samples = samples / max(1.0, np.abs(samples).max() / 0.6)  # peak at most -4.4 dBFS
    PREVIEW.mkdir(parents=True, exist_ok=True)
    wav = PREVIEW / f"{name}.wav"
    with wave.open(str(wav), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes((samples * 32767).astype("<i2").tobytes())
    OUT.mkdir(parents=True, exist_ok=True)
    subprocess.run(["afconvert", "-f", "caff", "-d", "alac", str(wav), str(OUT / f"{name}.caf")], check=True)


def main():
    for name, make in SOUNDS.items():
        write(name, make())
    print(f"wrote {len(SOUNDS)} loops to {OUT.relative_to(ROOT)} (previews in {PREVIEW.relative_to(ROOT)})")


if __name__ == "__main__":
    main()
