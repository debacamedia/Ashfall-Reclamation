#!/usr/bin/env python3
"""
Synthesizes ASHFALL's placeholder sound effects into assets/audio/.

Every sound is generated from noise, oscillators and filters, so there are no
licensing questions. They are placeholders: swap any file for a recorded
sound with the same name (and keep it a .wav, or update the scene references).

Usage (from the project root):
    python3 tools/audio/synth_sounds.py

Requires numpy and scipy. Loops are written with a WAV "smpl" chunk so Godot
imports them as looping automatically (import setting: Loop Mode = Detect).
"""
from __future__ import annotations

import os
import struct
import wave

import numpy as np
from scipy import signal

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio")


# --------------------------------------------------------------------- tools

def t_axis(seconds: float) -> np.ndarray:
    return np.arange(int(seconds * SR)) / SR


def silence(seconds: float) -> np.ndarray:
    return np.zeros(int(seconds * SR))


def noise(seconds: float, rng: np.random.Generator) -> np.ndarray:
    return rng.uniform(-1.0, 1.0, int(seconds * SR))


def brown(seconds: float, rng: np.random.Generator) -> np.ndarray:
    x = np.cumsum(rng.normal(0, 1, int(seconds * SR)))
    x = signal.sosfilt(signal.butter(1, 20, "hp", fs=SR, output="sos"), x)
    return x / (np.max(np.abs(x)) + 1e-9)


def lp(x: np.ndarray, hz: float, order: int = 2) -> np.ndarray:
    return signal.sosfilt(signal.butter(order, hz, "lp", fs=SR, output="sos"), x)


def hp(x: np.ndarray, hz: float, order: int = 2) -> np.ndarray:
    return signal.sosfilt(signal.butter(order, hz, "hp", fs=SR, output="sos"), x)


def bp(x: np.ndarray, lo: float, hi: float, order: int = 2) -> np.ndarray:
    return signal.sosfilt(signal.butter(order, [lo, hi], "bp", fs=SR, output="sos"), x)


def decay(n: int, tau: float, attack: float = 0.001) -> np.ndarray:
    t = np.arange(n) / SR
    env = np.exp(-t / tau)
    a = max(int(attack * SR), 1)
    env[:a] *= np.linspace(0, 1, a)
    return env


def place(dst: np.ndarray, src: np.ndarray, at: float, gain: float = 1.0) -> None:
    i = int(at * SR)
    end = min(len(dst), i + len(src))
    if end > i:
        dst[i:end] += src[: end - i] * gain


def sine_glide(seconds: float, f0: float, f1: float, curve: float = 1.0) -> np.ndarray:
    t = t_axis(seconds)
    frac = (t / seconds) ** curve
    freq = f0 + (f1 - f0) * frac
    return np.sin(2 * np.pi * np.cumsum(freq) / SR)


def metal(seconds: float, partials: list[tuple[float, float, float]], rng) -> np.ndarray:
    """Inharmonic ringing: (frequency, amplitude, decay seconds) per partial."""
    t = t_axis(seconds)
    out = np.zeros_like(t)
    for f, a, tau in partials:
        out += a * np.sin(2 * np.pi * f * t + rng.uniform(0, 6.28)) * np.exp(-t / tau)
    out += hp(noise(seconds, rng), 3000) * decay(len(t), 0.004) * 0.6
    return out


def voice(seconds: float, f0_start: float, f0_end: float, formants: list[tuple[float, float]],
          rng, breath: float = 0.25, jitter: float = 0.02) -> np.ndarray:
    """Very simple source-filter voice: glottal saw train through formant bandpasses."""
    t = t_axis(seconds)
    f0 = np.linspace(f0_start, f0_end, len(t)) * (1 + jitter * lp(rng.normal(0, 1, len(t)), 30))
    phase = 2 * np.pi * np.cumsum(f0) / SR
    # Band-limited sawtooth (additive, harmonics below 5 kHz) to avoid aliasing
    src = np.zeros_like(t)
    for k in range(1, int(5000 / max(f0_start, f0_end)) + 1):
        src += np.sin(k * phase) / k
    src = src * 0.6 + breath * lp(noise(seconds, rng), 6000)
    out = np.zeros_like(t)
    for f, bw in formants:
        out += bp(src, max(f - bw / 2, 40), f + bw / 2, order=2)
    return out


def soft_clip(x: np.ndarray, drive: float = 2.0) -> np.ndarray:
    return np.tanh(x * drive) / np.tanh(drive)


def seamless(x: np.ndarray, overlap: float) -> np.ndarray:
    """Crossfades the tail into the head so the result loops without a click."""
    n = int(overlap * SR)
    head, body, tail = x[:n], x[n:-n], x[-n:]
    fade = np.linspace(0, 1, n)
    return np.concatenate([tail * (1 - fade) + head * fade, body])


def write(name: str, x: np.ndarray, peak_db: float = -1.0, loop: bool = False) -> None:
    x = np.asarray(x, dtype=np.float64)
    x = x - np.mean(x)
    peak = np.max(np.abs(x)) + 1e-12
    x = x / peak * (10 ** (peak_db / 20))
    if not loop:
        # Short fade-out so nothing ends on a click
        f = min(int(0.01 * SR), len(x))
        x[-f:] *= np.linspace(1, 0, f)
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2")
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    if loop:
        # Append a 'smpl' chunk with one forward loop over the whole file
        smpl = struct.pack("<9I", 0, 0, int(1e9 / SR), 60, 0, 0, 0, 1, 0)
        smpl += struct.pack("<6I", 0, 0, 0, len(pcm) - 1, 0, 0)
        with open(path, "r+b") as f:
            f.seek(0, 2)
            f.write(b"smpl" + struct.pack("<I", len(smpl)) + smpl)
            size = f.tell() - 8
            f.seek(4)
            f.write(struct.pack("<I", size))
    print(f"  {name:24s} {len(pcm) / SR:5.2f}s{'  (loop)' if loop else ''}")


# --------------------------------------------------------------------- sounds

def rifle_shot(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    out = silence(1.1)
    crack = hp(noise(0.03, rng), 1800) * decay(int(0.03 * SR), 0.006)
    body = lp(noise(0.25, rng), 1400) * decay(int(0.25 * SR), 0.045)
    thump = sine_glide(0.18, 130 + rng.uniform(-10, 10), 48, 0.5) * decay(int(0.18 * SR), 0.05)
    tail = lp(noise(1.0, rng), 650) * decay(int(1.0 * SR), 0.28, attack=0.02)
    echo = lp(noise(0.6, rng), 450) * decay(int(0.6 * SR), 0.18, attack=0.03)
    place(out, crack, 0.0, 1.0)
    place(out, body, 0.0, 0.9)
    place(out, thump, 0.0, 1.1)
    place(out, tail, 0.005, 0.22)
    place(out, echo, 0.12 + rng.uniform(0, 0.04), 0.12)
    # Bolt cycling tick
    place(out, metal(0.05, [(3100, 1, 0.01), (4700, 0.6, 0.008)], rng), 0.035, 0.08)
    return soft_clip(out, 2.5)


def dry_fire() -> np.ndarray:
    rng = np.random.default_rng(7)
    out = silence(0.25)
    place(out, metal(0.08, [(2600, 1, 0.012), (4100, 0.5, 0.008), (5800, 0.3, 0.006)], rng), 0.0)
    place(out, metal(0.06, [(1900, 1, 0.01), (3300, 0.5, 0.008)], rng), 0.05, 0.6)
    return out


def reload_sound() -> np.ndarray:
    """Matches the service rifle's 2.3 s reload."""
    rng = np.random.default_rng(11)
    out = silence(2.3)
    # Magazine release button
    place(out, metal(0.06, [(2900, 1, 0.01), (4300, 0.5, 0.007)], rng), 0.12, 0.5)
    # Magazine sliding out
    slide = bp(noise(0.22, rng), 900, 3500) * np.hanning(int(0.22 * SR))
    place(out, slide, 0.25, 0.5)
    # New magazine seated: thump + clack
    place(out, lp(noise(0.08, rng), 500) * decay(int(0.08 * SR), 0.02), 1.05, 0.9)
    place(out, metal(0.12, [(1700, 1, 0.025), (2650, 0.7, 0.02), (3900, 0.4, 0.015)], rng), 1.06, 0.8)
    # Charging handle back (ratchet) and released forward (slam)
    for i in range(6):
        place(out, metal(0.02, [(3400 + i * 120, 1, 0.004)], rng), 1.62 + i * 0.016, 0.35)
    place(out, lp(noise(0.06, rng), 800) * decay(int(0.06 * SR), 0.015), 1.92, 0.8)
    place(out, metal(0.15, [(1400, 1, 0.03), (2300, 0.8, 0.025), (3600, 0.5, 0.02)], rng), 1.92, 1.0)
    return out


def impact_dirt(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    out = silence(0.45)
    place(out, lp(noise(0.12, rng), 700) * decay(int(0.12 * SR), 0.025), 0.0, 1.0)
    grains = np.zeros(int(0.35 * SR))
    for _ in range(40):
        i = rng.integers(0, len(grains) - 200)
        g = bp(noise(0.004, rng), 2500, 7000) * rng.uniform(0.2, 1.0)
        grains[i:i + len(g)] += g
    grains *= decay(len(grains), 0.09)
    place(out, grains, 0.005, 0.5)
    return out


def impact_hard(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    out = silence(0.5)
    place(out, hp(noise(0.02, rng), 2000) * decay(int(0.02 * SR), 0.004), 0.0, 1.0)
    place(out, lp(noise(0.08, rng), 1500) * decay(int(0.08 * SR), 0.015), 0.0, 0.7)
    chips = np.zeros(int(0.25 * SR))
    for _ in range(14):
        i = rng.integers(0, len(chips) - 300)
        chips[i:i + 220] += bp(noise(0.005, rng), 1500, 5000)[:220] * rng.uniform(0.2, 0.8)
    place(out, chips * decay(len(chips), 0.06), 0.01, 0.4)
    if seed % 2 == 0:
        # Ricochet whine
        whine = sine_glide(0.35, 3800, 1600, 0.7) * decay(int(0.35 * SR), 0.12, attack=0.01)
        place(out, whine, 0.02, 0.18)
    return out


def impact_flesh(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    out = silence(0.3)
    place(out, lp(noise(0.1, rng), 900) * decay(int(0.1 * SR), 0.03), 0.0, 1.0)
    place(out, sine_glide(0.12, 160, 70) * decay(int(0.12 * SR), 0.04), 0.0, 0.8)
    place(out, bp(noise(0.06, rng), 1200, 3000) * decay(int(0.06 * SR), 0.012), 0.004, 0.3)
    return out


def target_ping(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    base = 1180 + seed * 37
    return metal(1.0, [(base, 1.0, 0.35), (base * 1.71, 0.6, 0.25), (base * 2.73, 0.4, 0.18),
                       (base * 4.07, 0.25, 0.12), (base * 0.52, 0.3, 0.2)], rng)


def footstep(seed: int, heavy: float = 1.0) -> np.ndarray:
    rng = np.random.default_rng(seed)
    out = silence(0.3)
    place(out, lp(noise(0.06, rng), 350) * decay(int(0.06 * SR), 0.018 * heavy), 0.0, 1.0)
    crunch = np.zeros(int(0.18 * SR))
    for _ in range(int(30 * heavy)):
        i = rng.integers(0, len(crunch) - 300)
        g = bp(noise(0.006, rng), 1500, 6000)
        crunch[i:i + len(g)] += g * rng.uniform(0.1, 0.7)
    crunch *= decay(len(crunch), 0.05 * heavy, attack=0.01)
    place(out, crunch, 0.008, 0.7)
    return out


def land() -> np.ndarray:
    rng = np.random.default_rng(21)
    out = silence(0.45)
    place(out, sine_glide(0.2, 110, 45) * decay(int(0.2 * SR), 0.06), 0.0, 1.0)
    place(out, footstep(22, heavy=1.8), 0.0, 0.8)
    place(out, footstep(23, heavy=1.4), 0.05, 0.5)
    return out


def player_hurt(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    out = silence(0.4)
    place(out, sine_glide(0.15, 120, 55) * decay(int(0.15 * SR), 0.05), 0.0, 1.0)
    place(out, lp(noise(0.08, rng), 600) * decay(int(0.08 * SR), 0.02), 0.0, 0.7)
    grunt = voice(0.22, 125 + seed * 8, 95, [(640, 120), (1190, 160), (2390, 220)], rng, breath=0.5)
    grunt *= np.hanning(len(grunt)) ** 0.6
    place(out, grunt, 0.03, 0.45)
    return out


def heartbeat() -> np.ndarray:
    """One beat at ~95 bpm, looped while health is low."""
    rng = np.random.default_rng(31)
    out = silence(0.63)
    for at, f, g in [(0.0, 58, 1.0), (0.17, 48, 0.7)]:
        beat = sine_glide(0.16, f * 1.4, f, 0.4) * decay(int(0.16 * SR), 0.045, attack=0.008)
        beat += lp(noise(0.16, rng), 120) * decay(int(0.16 * SR), 0.03) * 0.5
        place(out, beat, at, g)
    return out


def death_sting() -> np.ndarray:
    rng = np.random.default_rng(41)
    t = t_axis(3.5)
    drone = (np.sin(2 * np.pi * 55 * t) + 0.5 * np.sin(2 * np.pi * 82.5 * t)) * np.exp(-t / 1.4)
    drone *= np.clip(t / 0.15, 0, 1)
    ring = np.sin(2 * np.pi * 3600 * t) * np.exp(-t / 1.2) * 0.25      # tinnitus
    rumble = lp(brown(3.5, rng), 200) * np.exp(-t / 1.0) * 0.6
    return drone + ring + rumble


def raider_alert(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    x = voice(0.5, 210 + seed * 6, 150, [(820, 140), (1250, 180), (2600, 260), (3300, 300)], rng,
              breath=0.35, jitter=0.04)
    env = np.clip(t_axis(0.5) / 0.03, 0, 1) * np.exp(-t_axis(0.5) / 0.22)
    return soft_clip(x * env, 3.0)


def raider_pain(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    x = voice(0.22, 190 + seed * 5, 130, [(700, 140), (1150, 170), (2500, 250)], rng, breath=0.45)
    return soft_clip(x * np.hanning(len(x)), 2.0)


def raider_death(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    out = silence(1.5)
    groan = voice(1.0, 150 + seed * 4, 70, [(520, 120), (900, 150), (2400, 220)], rng, breath=0.5)
    groan *= np.clip(t_axis(1.0) / 0.05, 0, 1) * np.exp(-t_axis(1.0) / 0.45) * np.linspace(1, 0, len(groan)) ** 0.5
    place(out, soft_clip(groan, 2.0), 0.0, 0.8)
    place(out, sine_glide(0.25, 90, 40) * decay(int(0.25 * SR), 0.08), 0.62, 1.0)   # body hits ground
    place(out, footstep(seed + 3, heavy=2.0), 0.62, 0.8)
    return out


def swing() -> np.ndarray:
    rng = np.random.default_rng(51)
    n = int(0.32 * SR)
    src = noise(0.32, rng)
    out = np.zeros(n)
    # Moving band-pass "whoosh"
    hop = 256
    centers = np.concatenate([np.linspace(500, 2200, n // 2), np.linspace(2200, 700, n - n // 2)])
    for i in range(0, n - hop, hop):
        c = centers[i]
        seg = bp(src[max(i - 2048, 0):i + hop], c * 0.7, c * 1.3)[-hop:]
        out[i:i + hop] = seg
    return out * np.hanning(n) ** 1.5


def fire_loop() -> np.ndarray:
    rng = np.random.default_rng(61)
    seconds = 6.0
    t = t_axis(seconds + 0.5)
    rumble = lp(brown(seconds + 0.5, rng), 350) * (0.6 + 0.4 * np.sin(2 * np.pi * 0.37 * t))
    hiss = bp(noise(seconds + 0.5, rng), 2000, 6000) * 0.08
    pops = np.zeros(len(t))
    for _ in range(int(55 * seconds)):
        i = rng.integers(0, len(pops) - 2000)
        tau = rng.uniform(0.002, 0.012)
        p = bp(noise(0.04, rng), 900, 6000) * decay(int(0.04 * SR), tau)
        pops[i:i + len(p)] += p * rng.uniform(0.15, 1.0) ** 2
    return seamless(rumble * 0.6 + hiss + pops * 0.9, 0.5)


def wind_loop() -> np.ndarray:
    rng = np.random.default_rng(71)
    seconds = 16.0
    total = seconds + 2.0
    t = t_axis(total)
    base = brown(total, rng)
    gust = 0.55 + 0.3 * np.sin(2 * np.pi * t / 7.3) + 0.15 * np.sin(2 * np.pi * t / 2.9 + 1.0)
    low = lp(base, 400) * gust
    whistle = bp(noise(total, rng), 600, 1100) * (0.1 + 0.1 * np.sin(2 * np.pi * t / 5.1)) * gust
    return seamless(low + whistle * 0.6, 2.0)


def ui_hit() -> np.ndarray:
    t = t_axis(0.05)
    return np.sin(2 * np.pi * 1900 * t) * np.exp(-t / 0.012)


def ui_kill() -> np.ndarray:
    out = silence(0.16)
    t = t_axis(0.07)
    place(out, np.sin(2 * np.pi * 1300 * t) * np.exp(-t / 0.02), 0.0)
    place(out, np.sin(2 * np.pi * 870 * t) * np.exp(-t / 0.03), 0.06)
    return out


def ui_denied() -> np.ndarray:
    t = t_axis(0.16)
    sq = np.sign(np.sin(2 * np.pi * 150 * t))
    return lp(sq, 1200) * np.exp(-t / 0.08)


def pickup_metal() -> np.ndarray:
    rng = np.random.default_rng(81)
    out = silence(0.45)
    place(out, metal(0.4, [(820, 1, 0.08), (1390, 0.7, 0.06), (2210, 0.5, 0.04)], rng), 0.0)
    place(out, metal(0.3, [(960, 1, 0.06), (1610, 0.6, 0.05)], rng), 0.07, 0.7)
    return out


def pickup_soft() -> np.ndarray:
    rng = np.random.default_rng(82)
    x = bp(noise(0.3, rng), 1200, 5000) * np.hanning(int(0.3 * SR)) ** 2
    x *= 0.7 + 0.3 * np.sin(2 * np.pi * 23 * t_axis(0.3))
    return x


def pickup_ammo() -> np.ndarray:
    rng = np.random.default_rng(83)
    out = silence(0.4)
    for i in range(7):
        place(out, metal(0.05, [(2800 + rng.uniform(-300, 300), 1, 0.012), (4200, 0.5, 0.008)], rng),
              i * 0.035 + rng.uniform(0, 0.01), rng.uniform(0.4, 1.0))
    return out


def pickup_fuel() -> np.ndarray:
    rng = np.random.default_rng(84)
    t = t_axis(0.7)
    slosh = lp(noise(0.7, rng), 600) * (0.5 + 0.5 * np.sin(2 * np.pi * 5.5 * t)) * np.hanning(len(t))
    out = slosh
    place(out, metal(0.2, [(420, 1, 0.05), (690, 0.6, 0.04)], rng), 0.0, 0.5)
    return out


def heal() -> np.ndarray:
    rng = np.random.default_rng(85)
    out = silence(0.8)
    zip_ = np.zeros(int(0.3 * SR))
    for i in range(18):
        j = int(i * 0.016 * SR)
        g = bp(noise(0.004, rng), 2000, 7000)
        zip_[j:j + len(g)] += g
    place(out, zip_, 0.0, 0.5)
    t = t_axis(0.45)
    chime = (np.sin(2 * np.pi * 660 * t) + 0.6 * np.sin(2 * np.pi * 990 * t)) * np.exp(-t / 0.15)
    place(out, chime, 0.3, 0.5)
    return out


def ladder_step(seed: int) -> np.ndarray:
    """Boot on a metal rung: a dull knock plus a short, damped ring."""
    rng = np.random.default_rng(seed)
    out = silence(0.4)
    knock = lp(noise(0.05, rng), 600) * decay(int(0.05 * SR), 0.012)
    place(out, knock, 0.0, 1.0)
    base = 420 + seed % 7 * 23
    ring = metal(0.35, [(base, 0.5, 0.07), (base * 2.31, 0.3, 0.05), (base * 3.9, 0.15, 0.03)], rng)
    place(out, ring, 0.002, 0.35)
    place(out, sine_glide(0.08, 140, 80) * decay(int(0.08 * SR), 0.025), 0.0, 0.5)
    return out


def aim_in() -> np.ndarray:
    """Raising the rifle to the shoulder: cloth rustle and a light stock tap."""
    rng = np.random.default_rng(91)
    out = silence(0.3)
    rustle = bp(noise(0.16, rng), 900, 5000) * decay(int(0.16 * SR), 0.05, attack=0.04)
    place(out, rustle, 0.0, 0.5)
    tap = lp(noise(0.03, rng), 900) * decay(int(0.03 * SR), 0.008)
    place(out, tap, 0.11, 0.8)
    return out


def crate_open() -> np.ndarray:
    """Wooden lid: a creaking hinge then a hollow thunk as it falls open."""
    rng = np.random.default_rng(700)
    out = silence(0.9)
    t = t_axis(0.35)
    creak_f = 180 + 90 * np.sin(2 * np.pi * 3.0 * t) + 60 * t
    phase = 2 * np.pi * np.cumsum(creak_f) / SR
    creak = np.sign(np.sin(phase)) * 0.3 + np.sin(phase * 2.01) * 0.3
    creak = bp(creak, 400, 2500) * decay(len(t), 0.25, attack=0.05)
    place(out, creak, 0.0, 0.5)
    thunk = lp(noise(0.12, rng), 400) * decay(int(0.12 * SR), 0.03)
    place(out, thunk, 0.38, 1.0)
    place(out, sine_glide(0.15, 120, 70) * decay(int(0.15 * SR), 0.05), 0.38, 0.6)
    return out


def locker_open() -> np.ndarray:
    """Metal locker: latch click, then a door swinging with a tinny rattle."""
    rng = np.random.default_rng(710)
    out = silence(0.9)
    place(out, hp(noise(0.01, rng), 2500) * decay(int(0.01 * SR), 0.002), 0.0, 1.0)
    place(out, metal(0.4, [(1800, 0.4, 0.05), (2900, 0.3, 0.04)], rng), 0.005, 0.4)
    rattle = metal(0.7, [(310, 0.5, 0.25), (734, 0.35, 0.2), (1210, 0.2, 0.15), (1890, 0.1, 0.1)], rng)
    rattle *= decay(len(rattle), 0.3, attack=0.08)
    place(out, rattle, 0.12, 0.45)
    return out


def rummage() -> np.ndarray:
    """Searching through a container: shuffled objects and cloth, ~1.2 s."""
    rng = np.random.default_rng(720)
    out = silence(1.3)
    for i in range(14):
        at = rng.uniform(0.0, 1.15)
        kind = rng.integers(0, 3)
        if kind == 0:
            g = bp(noise(0.08, rng), 700, 4000) * decay(int(0.08 * SR), 0.03, attack=0.01)
        elif kind == 1:
            g = lp(noise(0.04, rng), 900) * decay(int(0.04 * SR), 0.01)
        else:
            g = metal(0.12, [(rng.uniform(900, 2400), 0.4, 0.03)], rng) * 0.5
        place(out, g, at, rng.uniform(0.25, 0.7))
    return out


def soft_step(seed: int) -> np.ndarray:
    """Player/raider footstep on packed dirt: a soft heel thud with a little
    grit. Quieter and duller than footstep(), which is kept for landings."""
    rng = np.random.default_rng(seed)
    out = silence(0.25)
    thud = lp(noise(0.07, rng), 220 + seed % 5 * 15) * decay(int(0.07 * SR), 0.022, attack=0.004)
    place(out, thud, 0.0, 1.0)
    grit = np.zeros(int(0.12 * SR))
    for _ in range(10):
        i = rng.integers(0, len(grit) - 300)
        g = bp(noise(0.005, rng), 900, 3200)
        grit[i:i + len(g)] += g * rng.uniform(0.05, 0.3)
    grit *= decay(len(grit), 0.03, attack=0.008)
    place(out, grit, 0.01, 0.35)
    return lp(out, 5000)


def crate_close() -> np.ndarray:
    """Wooden lid dropping shut: a dull knock."""
    rng = np.random.default_rng(730)
    out = silence(0.4)
    place(out, lp(noise(0.08, rng), 500) * decay(int(0.08 * SR), 0.025), 0.0, 1.0)
    place(out, sine_glide(0.12, 140, 80) * decay(int(0.12 * SR), 0.04), 0.0, 0.7)
    place(out, bp(noise(0.03, rng), 1200, 3000) * decay(int(0.03 * SR), 0.01), 0.0, 0.2)
    return out


def pistol_shot(seed: int) -> np.ndarray:
    """Sharper and lighter than the rifle: a snappy crack, less body."""
    rng = np.random.default_rng(seed)
    out = silence(0.8)
    place(out, hp(noise(0.02, rng), 2400) * decay(int(0.02 * SR), 0.004), 0.0, 1.0)
    place(out, bp(noise(0.12, rng), 600, 3000) * decay(int(0.12 * SR), 0.025), 0.0, 0.8)
    place(out, sine_glide(0.1, 190 + rng.uniform(-15, 15), 80, 0.5) * decay(int(0.1 * SR), 0.03), 0.0, 0.7)
    place(out, lp(noise(0.7, rng), 900) * decay(int(0.7 * SR), 0.18, attack=0.01), 0.004, 0.15)
    place(out, metal(0.04, [(3800, 1, 0.008), (5200, 0.5, 0.006)], rng), 0.03, 0.1)
    return soft_clip(out, 2.2)


def shotgun_shot(seed: int) -> np.ndarray:
    """A deep boom with a long, rolling tail."""
    rng = np.random.default_rng(seed)
    out = silence(1.6)
    place(out, hp(noise(0.04, rng), 1200) * decay(int(0.04 * SR), 0.008), 0.0, 0.9)
    place(out, lp(noise(0.4, rng), 900) * decay(int(0.4 * SR), 0.08), 0.0, 1.0)
    place(out, sine_glide(0.35, 95 + rng.uniform(-8, 8), 38, 0.5) * decay(int(0.35 * SR), 0.1), 0.0, 1.3)
    place(out, lp(noise(1.4, rng), 500) * decay(int(1.4 * SR), 0.4, attack=0.03), 0.01, 0.3)
    place(out, lp(noise(0.8, rng), 380) * decay(int(0.8 * SR), 0.25, attack=0.04), 0.16 + rng.uniform(0, 0.05), 0.15)
    return soft_clip(out, 2.8)


def shotgun_pump() -> np.ndarray:
    """Pump back (slide + clack), pump forward (clack)."""
    rng = np.random.default_rng(810)
    out = silence(0.55)
    place(out, bp(noise(0.12, rng), 700, 3200) * np.hanning(int(0.12 * SR)), 0.0, 0.4)
    place(out, metal(0.08, [(1500, 1, 0.02), (2400, 0.7, 0.015), (3700, 0.4, 0.01)], rng), 0.12, 0.8)
    place(out, bp(noise(0.1, rng), 700, 3200) * np.hanning(int(0.1 * SR)), 0.2, 0.35)
    place(out, metal(0.1, [(1300, 1, 0.025), (2100, 0.8, 0.02), (3300, 0.5, 0.012)], rng), 0.31, 1.0)
    place(out, lp(noise(0.05, rng), 700) * decay(int(0.05 * SR), 0.012), 0.31, 0.6)
    return out


def shell_insert(seed: int) -> np.ndarray:
    """One shell pushed into the tube: a click and a soft thunk."""
    rng = np.random.default_rng(seed)
    out = silence(0.35)
    place(out, metal(0.05, [(2600 + seed % 3 * 150, 1, 0.01), (4000, 0.5, 0.007)], rng), 0.05, 0.6)
    place(out, lp(noise(0.05, rng), 600) * decay(int(0.05 * SR), 0.012), 0.08, 0.7)
    return out


def sniper_shot(seed: int) -> np.ndarray:
    """A hard, very loud crack with a long echo off the hills."""
    rng = np.random.default_rng(seed)
    out = silence(2.4)
    place(out, hp(noise(0.025, rng), 2000) * decay(int(0.025 * SR), 0.005), 0.0, 1.0)
    place(out, lp(noise(0.3, rng), 1600) * decay(int(0.3 * SR), 0.05), 0.0, 1.0)
    place(out, sine_glide(0.25, 110 + rng.uniform(-8, 8), 40, 0.5) * decay(int(0.25 * SR), 0.07), 0.0, 1.2)
    place(out, lp(noise(2.0, rng), 600) * decay(int(2.0 * SR), 0.55, attack=0.03), 0.01, 0.25)
    place(out, lp(noise(1.2, rng), 420) * decay(int(1.2 * SR), 0.35, attack=0.05), 0.3 + rng.uniform(0, 0.08), 0.2)
    place(out, lp(noise(0.9, rng), 350) * decay(int(0.9 * SR), 0.3, attack=0.05), 0.75 + rng.uniform(0, 0.1), 0.1)
    return soft_clip(out, 2.6)


def bolt_cycle() -> np.ndarray:
    """Bolt up, back, forward, down."""
    rng = np.random.default_rng(820)
    out = silence(0.7)
    place(out, metal(0.05, [(2200, 1, 0.012), (3500, 0.6, 0.008)], rng), 0.0, 0.6)
    place(out, bp(noise(0.12, rng), 1000, 4000) * np.hanning(int(0.12 * SR)), 0.06, 0.35)
    place(out, metal(0.07, [(1700, 1, 0.018), (2900, 0.6, 0.012)], rng), 0.2, 0.8)
    place(out, bp(noise(0.1, rng), 1000, 4000) * np.hanning(int(0.1 * SR)), 0.3, 0.3)
    place(out, metal(0.09, [(1500, 1, 0.022), (2500, 0.7, 0.016)], rng), 0.42, 0.9)
    place(out, metal(0.05, [(2400, 1, 0.01)], rng), 0.52, 0.5)
    return out


def pistol_reload() -> np.ndarray:
    """1.5 s: magazine out, in, slide release."""
    rng = np.random.default_rng(830)
    out = silence(1.5)
    place(out, metal(0.05, [(3100, 1, 0.01), (4500, 0.5, 0.007)], rng), 0.1, 0.5)
    place(out, bp(noise(0.15, rng), 900, 3500) * np.hanning(int(0.15 * SR)), 0.18, 0.4)
    place(out, lp(noise(0.06, rng), 600) * decay(int(0.06 * SR), 0.015), 0.75, 0.8)
    place(out, metal(0.1, [(1900, 1, 0.02), (2900, 0.6, 0.015)], rng), 0.76, 0.7)
    place(out, metal(0.12, [(1600, 1, 0.025), (2700, 0.7, 0.02), (4100, 0.4, 0.012)], rng), 1.25, 0.9)
    return out


def sniper_reload() -> np.ndarray:
    """3.0 s: bolt open, magazine swap, bolt closed."""
    rng = np.random.default_rng(840)
    out = silence(3.0)
    place(out, bolt_cycle()[: int(0.3 * SR)], 0.1, 0.8)
    place(out, metal(0.05, [(2900, 1, 0.01)], rng), 0.6, 0.5)
    place(out, bp(noise(0.2, rng), 900, 3500) * np.hanning(int(0.2 * SR)), 0.7, 0.4)
    place(out, lp(noise(0.08, rng), 500) * decay(int(0.08 * SR), 0.02), 1.6, 0.9)
    place(out, metal(0.12, [(1700, 1, 0.025), (2650, 0.7, 0.02)], rng), 1.61, 0.8)
    place(out, bolt_cycle()[int(0.3 * SR):], 2.2, 0.9)
    return out


def weapon_draw() -> np.ndarray:
    """Switching guns: cloth rustle and a light metal knock."""
    rng = np.random.default_rng(850)
    out = silence(0.4)
    place(out, bp(noise(0.18, rng), 800, 4500) * decay(int(0.18 * SR), 0.06, attack=0.03), 0.0, 0.45)
    place(out, metal(0.08, [(1900, 1, 0.02), (3000, 0.5, 0.012)], rng), 0.14, 0.5)
    return out


def pickup_weapon() -> np.ndarray:
    """Picking up a gun: a heavy grab and a chamber check."""
    rng = np.random.default_rng(860)
    out = silence(0.7)
    place(out, lp(noise(0.08, rng), 600) * decay(int(0.08 * SR), 0.02), 0.0, 0.8)
    place(out, bp(noise(0.12, rng), 900, 3500) * np.hanning(int(0.12 * SR)), 0.15, 0.35)
    place(out, metal(0.12, [(1600, 1, 0.025), (2600, 0.7, 0.02), (3900, 0.4, 0.012)], rng), 0.32, 0.9)
    return out


# --------------------------------------------------------------------- construction (Increment 13)
def build_place() -> np.ndarray:
    """Setting a structure down and hammering it in: three knocks."""
    rng = np.random.default_rng(1300)
    out = silence(0.9)
    place(out, lp(noise(0.12, rng), 350) * decay(int(0.12 * SR), 0.04), 0.0, 1.0)
    place(out, sine_glide(0.15, 110, 70) * decay(int(0.15 * SR), 0.05), 0.0, 0.8)
    for k, at in enumerate((0.28, 0.48, 0.66)):
        place(out, bp(noise(0.03, rng), 900, 3500) * decay(int(0.03 * SR), 0.006), at, 0.55 - k * 0.08)
        place(out, sine_glide(0.06, 420, 300) * decay(int(0.06 * SR), 0.015), at, 0.35 - k * 0.05)
    return out


def structure_hit(seed: int) -> np.ndarray:
    """A machete or club biting into a barricade: thud and splinter."""
    rng = np.random.default_rng(seed)
    out = silence(0.5)
    place(out, lp(noise(0.1, rng), 600) * decay(int(0.1 * SR), 0.03), 0.0, 1.0)
    place(out, sine_glide(0.12, 160 + seed % 3 * 15, 90) * decay(int(0.12 * SR), 0.04), 0.0, 0.6)
    chips = np.zeros(int(0.2 * SR))
    for _ in range(10):
        i = rng.integers(0, len(chips) - 300)
        chips[i:i + 200] += bp(noise(0.005, rng), 1200, 4500)[:200] * rng.uniform(0.2, 0.7)
    place(out, chips * decay(len(chips), 0.05), 0.01, 0.45)
    return out


def structure_break() -> np.ndarray:
    """A structure giving way: crack, crash and tumbling debris."""
    rng = np.random.default_rng(1310)
    out = silence(1.6)
    place(out, hp(noise(0.05, rng), 1500) * decay(int(0.05 * SR), 0.01), 0.0, 0.8)
    place(out, lp(brown(0.6, rng), 400) * decay(int(0.6 * SR), 0.2), 0.03, 1.0)
    for _ in range(18):
        at = rng.uniform(0.1, 1.2)
        n = rng.uniform(0.02, 0.08)
        place(out, bp(noise(n, rng), rng.uniform(300, 900), rng.uniform(1500, 4000)) * decay(int(n * SR), n / 3),
              at, rng.uniform(0.15, 0.5) * (1.3 - at))
    return out


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    print("Writing to", os.path.abspath(OUT))
    for i in range(3):
        write(f"rifle_shot_{i + 1}", rifle_shot(100 + i), -0.5)
    write("rifle_dry_fire", dry_fire(), -6)
    write("rifle_reload", reload_sound(), -3)
    for i in range(3):
        write(f"impact_dirt_{i + 1}", impact_dirt(200 + i), -4)
    for i in range(2):
        write(f"impact_hard_{i + 1}", impact_hard(210 + i), -3)
    for i in range(2):
        write(f"impact_flesh_{i + 1}", impact_flesh(220 + i), -3)
    for i in range(2):
        write(f"target_ping_{i + 1}", target_ping(i), -4)
    for i in range(6):
        write(f"footstep_gravel_{i + 1}", soft_step(300 + i), -6)
    write("land", land(), -3)
    for i in range(2):
        write(f"player_hurt_{i + 1}", player_hurt(400 + i), -3)
    write("heartbeat", heartbeat(), -3, loop=True)
    write("death_sting", death_sting(), -4)
    for i in range(2):
        write(f"raider_alert_{i + 1}", raider_alert(500 + i), -3)
    for i in range(2):
        write(f"raider_pain_{i + 1}", raider_pain(510 + i), -4)
    for i in range(2):
        write(f"raider_death_{i + 1}", raider_death(520 + i), -3)
    write("melee_swing", swing(), -4)
    write("fire_loop", fire_loop(), -6, loop=True)
    write("wind_loop", wind_loop(), -8, loop=True)
    write("ui_hit", ui_hit(), -10)
    write("ui_kill", ui_kill(), -8)
    write("ui_denied", ui_denied(), -10)
    write("pickup_metal", pickup_metal(), -5)
    write("pickup_soft", pickup_soft(), -6)
    write("pickup_ammo", pickup_ammo(), -5)
    write("pickup_fuel", pickup_fuel(), -5)
    write("heal", heal(), -5)
    for i in range(3):
        write(f"ladder_step_{i + 1}", ladder_step(600 + i), -6)
    write("aim_in", aim_in(), -12)
    write("crate_open", crate_open(), -5)
    write("locker_open", locker_open(), -5)
    write("rummage", rummage(), -8)
    write("crate_close", crate_close(), -6)
    for i in range(3):
        write(f"pistol_shot_{i + 1}", pistol_shot(900 + i), -1.5)
    for i in range(2):
        write(f"shotgun_shot_{i + 1}", shotgun_shot(910 + i), -0.5)
        write(f"sniper_shot_{i + 1}", sniper_shot(920 + i), -0.3)
    write("shotgun_pump", shotgun_pump(), -3)
    write("shell_insert", shell_insert(930), -4)
    write("bolt_cycle", bolt_cycle(), -3)
    write("pistol_reload", pistol_reload(), -3)
    write("sniper_reload", sniper_reload(), -3)
    write("weapon_draw", weapon_draw(), -8)
    write("pickup_weapon", pickup_weapon(), -4)
    write("build_place", build_place(), -3)
    for i in range(3):
        write(f"structure_hit_{i + 1}", structure_hit(1301 + i), -3)
    write("structure_break", structure_break(), -2)


if __name__ == "__main__":
    main()
