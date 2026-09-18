#!/usr/bin/env python3
"""
CENTURY OF HUMILIATION -- audio pipeline.
Procedural audio pipeline.

Synthesizes the entire soundtrack and SFX library from scratch with numpy --
no sample packs, no external assets.  Output is converted to Ogg Vorbis by
ffmpeg so the game ships with compressed, streaming-friendly audio.

    python3 tools/gen_audio.py

Design notes
------------
* All IIR filtering is expressed as truncated-FIR + FFT convolution so it is
  fully vectorised.  A causal one-pole lowpass y[n] = (1-a) * sum a^k x[n-k]
  is exact once the impulse response is truncated past ~8 time constants, and
  a two-pole resonator is h[k] = r^k sin(w0 k).  No python-level sample loops.
* Music is composed on a bar grid, rendered into a buffer that is longer than
  the loop by a reverb tail, then the tail is *wrapped back onto the head*.
  That produces a mathematically seamless loop without crossfade smearing.
"""

import math
import os
import shutil
import subprocess
import sys

import numpy as np

SR = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "audio")
RAW_DIR = os.path.join(ROOT, ".raw_audio")

# --------------------------------------------------------------------------
# DSP primitives
# --------------------------------------------------------------------------


def nz(n, seed=0):
    """Gaussian white noise."""
    return np.random.default_rng(seed).standard_normal(n)


def fftconv(x, h):
    """Fast linear convolution, trimmed back to len(x)."""
    if len(h) == 0 or len(x) == 0:
        return np.zeros_like(x)
    n = len(x) + len(h) - 1
    nfft = 1 << int(math.ceil(math.log2(max(n, 2))))
    y = np.fft.irfft(np.fft.rfft(x, nfft) * np.fft.rfft(h, nfft), nfft)
    return y[: len(x)]


def lp(x, cutoff, order=1):
    """One-pole lowpass (per pole) via exact exponential impulse response."""
    cutoff = max(10.0, min(cutoff, SR * 0.49))
    a = math.exp(-2.0 * math.pi * cutoff / SR)
    n = int(min(len(x) - 1, max(2, 8.0 / max(1e-9, -math.log(a)))))
    h = (1.0 - a) * a ** np.arange(n)
    for _ in range(max(1, order)):
        x = fftconv(x, h)
    return x


def hp(x, cutoff, order=1):
    """Complementary highpass: x - lowpass(x)."""
    y = x
    for _ in range(max(1, order)):
        y = y - lp(y, cutoff)
    return y


def bp(x, low, high, order=1):
    return lp(hp(x, low, order), high, order)


def reson(x, freq, decay, amp=1.0):
    """Two-pole resonant bandpass.  `decay` = seconds to -60 dB."""
    r = math.exp(-6.907755 / (decay * SR))
    n = int(min(len(x) - 1, max(16, 8 * decay * SR)))
    k = np.arange(n)
    h = (r ** k) * np.sin(2.0 * math.pi * freq * k / SR) * amp
    return fftconv(x, h)


def env_exp(n, attack=0.002, decay=0.2):
    """Percussive attack/exponential-decay envelope."""
    t = np.arange(n) / SR
    a = max(attack, 1e-5)
    return np.where(t < a, t / a, np.exp(-(t - a) / max(decay, 1e-5)))


def env_adsr(n, attack=0.01, decay=0.1, sustain=0.7, release=0.3):
    t = np.arange(n) / SR
    total = n / SR
    rel_start = max(attack + decay, total - release)
    e = np.ones(n)
    a_end = min(n, int(attack * SR))
    if a_end > 0:
        e[:a_end] = np.linspace(0.0, 1.0, a_end)
    d_end = min(n, a_end + int(decay * SR))
    if d_end > a_end:
        e[a_end:d_end] = np.linspace(1.0, sustain, d_end - a_end)
    e[d_end:] = sustain
    r_start = int(rel_start * SR)
    if r_start < n:
        e[r_start:] *= np.linspace(1.0, 0.0, n - r_start) ** 0.6
    e[t >= total] = 0.0
    return np.clip(e, 0.0, 1.0)


def sweep_sine(n, f0, f1, tau=0.06, phase0=0.0):
    """Sine with an exponential frequency glide f0 -> f1."""
    t = np.arange(n) / SR
    ph = 2.0 * math.pi * (f1 * t + (f0 - f1) * tau * (1.0 - np.exp(-t / tau)))
    return np.sin(ph + phase0)


def soft_clip(x, drive=1.6):
    return np.tanh(x * drive) / np.tanh(drive)


def norm(x, peak=0.92):
    m = float(np.max(np.abs(x))) if len(x) else 0.0
    if m < 1e-9:
        return x
    return x * (peak / m)


def fade_edges(x, ms=3.0):
    n = int(SR * ms / 1000.0)
    if n * 2 >= len(x):
        return x
    x = x.copy()
    x[:n] *= np.linspace(0.0, 1.0, n)
    x[-n:] *= np.linspace(1.0, 0.0, n)
    return x


# --- reverb ---------------------------------------------------------------


def make_ir(decay=1.0, damp=5200, seed=7, pre=0.012):
    """Synthetic room impulse response: damped noise + early reflections."""
    n = int(decay * SR)
    t = np.arange(n) / SR
    ir = nz(n, seed) * np.exp(-6.907755 * t / decay)
    ir = lp(ir, damp, order=2)
    ir = hp(ir, 120)
    # early reflections give the room a size
    for dt, g in ((0.007, 0.55), (0.011, 0.42), (0.019, 0.3), (0.029, 0.22), (0.041, 0.14)):
        i = int((pre + dt) * SR)
        if i < n:
            ir[i] += g
    return norm(ir, 1.0)


def reverb(x, decay=0.9, mix=0.3, damp=5200, seed=7):
    w = norm(fftconv(x, make_ir(decay, damp, seed)), 1.0)
    return (1.0 - mix) * x + mix * w


def stereo_wide(x, width=0.6, ms=0.35):
    """Cheap but effective width: tiny decorrelating delay + side energy."""
    d = int(SR * ms / 1000.0)
    l = x
    r = np.concatenate([np.zeros(d), x[:-d]]) if d > 0 else x
    mid = (l + r) * 0.5
    side = (l - r) * 0.5
    l2 = mid + side * (1.0 + width)
    r2 = mid - side * (1.0 + width)
    return np.stack([l2, r2], axis=1)


def wrap_tail(x, loop_len):
    """Wrap the post-loop reverb tail back onto the head -> seamless loop."""
    if len(x) <= loop_len:
        return x
    y = x[:loop_len].copy()
    extra = min(len(x) - loop_len, loop_len)
    y[:extra] += x[loop_len : loop_len + extra]
    return y


# --------------------------------------------------------------------------
# Musical helpers
# --------------------------------------------------------------------------

_SEMI = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def pf(tok):
    """Parse a note token such as 'D3', 'Bb2', 'F#4' into a frequency."""
    name = tok[0].upper()
    i = 1
    semi = _SEMI[name]
    while i < len(tok) and tok[i] in "#b":
        semi += 1 if tok[i] == "#" else -1
        i += 1
    octave = int(tok[i:])
    midi = 12 * (octave + 1) + semi
    return 440.0 * 2.0 ** ((midi - 69) / 12.0)


_PAD_CACHE = {}


def pad_chord(chord, dur, cutoff=1200, detune=0.005, seed=3, bright=0.3):
    """Warm detuned-saw pad.  Cached because chords repeat across bars."""
    key = (tuple(chord), round(dur, 4), cutoff, detune, seed, bright)
    if key in _PAD_CACHE:
        return _PAD_CACHE[key]
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    r = np.random.default_rng(seed)
    voices = 0
    for tok in chord:
        f = pf(tok)
        for d in (-detune, 0.0, detune):
            ph = 2.0 * math.pi * f * (1.0 + d) * t + r.uniform(0, 6.283)
            out += np.sin(ph) + bright * 0.45 * np.sin(2 * ph) + bright * 0.2 * np.sin(3 * ph)
            voices += 1
    out /= max(1, voices)
    out = lp(out, cutoff, order=2)
    out = lp(out, cutoff * 1.6)
    _PAD_CACHE[key] = out
    return out


def bell(f, dur, amp=0.3, ratio=3.01, index=1.7, decay=2.4, mod_decay=None):
    """FM bell / music-box voice."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    md = mod_decay if mod_decay is not None else decay * 0.11
    idx = index * np.exp(-t / md)
    y = np.sin(2.0 * math.pi * f * t + idx * np.sin(2.0 * math.pi * f * ratio * t))
    return y * np.exp(-t / decay) * amp


def sub_note(f, dur, amp=0.5, attack=0.01, release=0.25, drive=1.2):
    n = int(dur * SR)
    t = np.arange(n) / SR
    y = np.sin(2.0 * math.pi * f * t) + 0.25 * np.sin(4.0 * math.pi * f * t)
    y = soft_clip(y * drive, 1.3)
    return y * env_adsr(n, attack, 0.05, 0.85, release) * amp


def kick(dur=0.42, f0=150.0, f1=44.0, amp=1.0):
    n = int(dur * SR)
    y = sweep_sine(n, f0, f1, tau=0.045) * env_exp(n, 0.001, dur * 0.34)
    click = bp(nz(n, 11) * env_exp(n, 0.0002, 0.006), 1800, 7000) * 0.45
    return norm(y + click, amp)


def snare(dur=0.3, amp=1.0, seed=5):
    n = int(dur * SR)
    body = reson(nz(n, seed), 195.0, 0.055) * 0.5
    noise = bp(nz(n, seed + 1) * env_exp(n, 0.0004, 0.11), 700, 8000)
    return norm(body + noise, amp)


def hat(dur=0.055, amp=1.0, seed=9, open_=False):
    n = int(dur * SR)
    x = hp(nz(n, seed) * env_exp(n, 0.0002, dur * (0.6 if open_ else 0.22)), 6500)
    return norm(x, amp)


def tamb(dur=0.12, amp=1.0, seed=13):
    n = int(dur * SR)
    x = bp(nz(n, seed) * env_exp(n, 0.0004, dur * 0.5), 3000, 9000, order=2)
    return norm(x, amp)


class Track:
    """Bar-grid composition buffer with L/R buses and a wrapped reverb tail."""

    def __init__(self, bpm, bars, beats_per_bar=4, tail=4.0, seed=0):
        self.bpm = bpm
        self.bars = bars
        self.bpb = beats_per_bar
        self.spb = 60.0 / bpm
        self.bar = self.spb * beats_per_bar
        self.loop_len = int(round(bars * self.bar * SR))
        pad = int(tail * SR)
        self.L = np.zeros(self.loop_len + pad)
        self.R = np.zeros(self.loop_len + pad)
        self.seed = seed
        self._counter = 0

    def _seed(self):
        self._counter += 1
        return self.seed * 977 + self._counter

    def t(self, bar, beat=0.0):
        return bar * self.bar + beat * self.spb

    def add(self, sig, t, gain=1.0, pan=0.0):
        i = int(t * SR)
        if i < 0:
            sig = sig[-i:]
            i = 0
        n = min(len(sig), len(self.L) - i)
        if n <= 0:
            return
        gl = math.sqrt(max(0.0, 0.5 * (1.0 - pan)))
        gr = math.sqrt(max(0.0, 0.5 * (1.0 + pan)))
        self.L[i : i + n] += sig[:n] * gain * gl
        self.R[i : i + n] += sig[:n] * gain * gr

    def finish(self, rev_decay=2.4, rev_mix=0.34, rev_damp=4800, drive=1.15, peak=0.9):
        out = []
        for i, bus in enumerate((self.L, self.R)):
            ch = reverb(bus, rev_decay, rev_mix, rev_damp, 21 + i)
            ch = soft_clip(ch, drive)
            ch = wrap_tail(ch, self.loop_len)
            ch = fade_edges(ch, 1.5)
            out.append(ch)
        st = np.stack(out, axis=1)
        st = norm(st, peak)
        return st


# --------------------------------------------------------------------------
# SFX definitions
# --------------------------------------------------------------------------


def gunshot(seed=0, amp=1.0, body=0.14, low=0.55, tail=0.6):
    n = int((tail + 0.02) * SR)
    t = np.arange(n) / SR
    crack = hp(nz(n, seed) * env_exp(n, 0.00015, 0.005), 2600)
    mid = bp(nz(n, seed + 1) * env_exp(n, 0.0005, body), 190, 3200)
    thump = np.sin(2.0 * math.pi * 74.0 * t) * env_exp(n, 0.0004, 0.075) * low
    mech = bp(nz(n, seed + 5) * env_exp(n, 0.0001, 0.0035), 4000, 12000) * 0.35
    x = crack * 1.0 + mid * 1.15 + thump + mech
    x = reverb(x, tail, 0.4, 3600, seed + 2)
    return norm(x, amp)


def mechanical_click(seed=0, lo=900, hi=7000, dur=0.07, body_f=280.0, amp=1.0):
    n = int(dur * SR)
    click = bp(nz(n, seed) * env_exp(n, 0.00015, 0.006), lo, hi)
    body = reson(nz(n, seed + 1) * env_exp(n, 0.0004, dur * 0.4), body_f, 0.02) * 0.6
    return norm(click + body, amp)


def impact_concrete(seed=0, amp=1.0):
    n = int(0.4 * SR)
    x = lp(nz(n, seed) * env_exp(n, 0.0004, 0.05), 1700, order=2)
    x += reson(nz(n, seed + 1), 620.0, 0.03) * 0.25
    x = reverb(x, 0.5, 0.35, 3000, seed + 2)
    return norm(x, amp)


def impact_metal(seed=0, amp=1.0):
    n = int(0.55 * SR)
    x = np.zeros(n)
    for f, d, g in ((1240, 0.22, 1.0), (1830, 0.16, 0.7), (2670, 0.11, 0.5), (3910, 0.07, 0.3)):
        x += reson(nz(n, seed), f, d) * g
    x += bp(nz(n, seed + 3) * env_exp(n, 0.0002, 0.02), 2500, 9000) * 0.7
    x = reverb(x, 0.6, 0.3, 6000, seed + 4)
    return norm(x, amp)


def impact_flesh(seed=0, amp=1.0):
    n = int(0.28 * SR)
    x = lp(nz(n, seed) * env_exp(n, 0.0006, 0.055), 900, order=2)
    x += np.sin(2.0 * math.pi * 130.0 * np.arange(n) / SR) * env_exp(n, 0.0005, 0.04)
    return norm(x, amp)


def impact_water(seed=0, amp=1.0):
    n = int(0.6 * SR)
    x = bp(nz(n, seed) * env_exp(n, 0.002, 0.11), 500, 5200)
    x += reson(nz(n, seed + 1) * env_exp(n, 0.001, 0.06), 900.0, 0.05) * 0.4
    return norm(x, amp)


def footstep(seed=0, kind="concrete", amp=1.0):
    n = int(0.3 * SR)
    if kind == "concrete":
        x = bp(nz(n, seed) * env_exp(n, 0.0006, 0.032), 260, 3400)
        x += np.sin(2.0 * math.pi * 95.0 * np.arange(n) / SR) * env_exp(n, 0.0008, 0.028) * 0.5
    elif kind == "gravel":
        x = bp(nz(n, seed) * env_exp(n, 0.0003, 0.07), 900, 7000, order=2)
    elif kind == "water":
        x = bp(nz(n, seed) * env_exp(n, 0.001, 0.13), 420, 5600)
        x += bp(nz(n, seed + 1) * env_exp(n, 0.004, 0.2), 300, 2600) * 0.6
    elif kind == "grass":
        x = bp(nz(n, seed) * env_exp(n, 0.0009, 0.05), 1400, 8000, order=2)
        x += bp(nz(n, seed + 1) * env_exp(n, 0.002, 0.09), 500, 2200) * 0.35
    else:  # metal / interior
        x = bp(nz(n, seed) * env_exp(n, 0.0004, 0.03), 700, 6000)
        x += reson(nz(n, seed + 2), 1500.0, 0.05) * 0.4
    return norm(x, amp)


def water_lap(seed=0, amp=1.0, dur=3.0):
    n = int(dur * SR)
    x = bp(nz(n, seed), 300, 2800) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.4 * np.arange(n) / SR))
    x = lp(x, 2400)
    # slow amplitude swells
    lfo = 0.45 + 0.55 * np.abs(np.sin(2 * np.pi * 0.23 * np.arange(n) / SR + 0.7))
    x *= lfo
    return norm(x, amp)


def ambience_noise(dur, seed=0, lo=180, hi=3800, smooth=2500, amp=1.0, brown=True):
    n = int(dur * SR)
    if brown:
        x = np.cumsum(nz(n, seed))
        x = x / (np.max(np.abs(x)) + 1e-9)
    else:
        x = nz(n, seed)
    x = bp(x, lo, hi)
    x = lp(x, smooth, order=2)
    lfo = 0.6 + 0.4 * np.sin(2 * np.pi * 0.07 * np.arange(n) / SR + seed)
    return norm(x * lfo, amp)


def rain_layer(dur, seed=0, amp=1.0, intensity=1.0):
    n = int(dur * SR)
    hiss = bp(nz(n, seed), 900, 9000)
    hiss = lp(hiss, 7000, order=2) * 0.7
    # individual drop transients
    drops = np.zeros(n)
    r = np.random.default_rng(seed + 4)
    count = int(dur * 90 * intensity)
    for _ in range(count):
        i = r.integers(0, max(1, n - 900))
        d = bp(nz(900, int(r.integers(0, 9999))) * env_exp(900, 0.0002, 0.006), 2200, 11000)
        drops[i : i + 900] += d * r.uniform(0.25, 0.9)
    x = hiss + drops * 0.5
    x = soft_clip(x, 1.2)
    return norm(x, amp)


def ui_blip(f=880.0, dur=0.09, amp=0.5, kind="sine", seed=0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    if kind == "sine":
        y = np.sin(2 * np.pi * f * t) + 0.25 * np.sin(4 * np.pi * f * t)
    elif kind == "square":
        y = np.sign(np.sin(2 * np.pi * f * t)) * 0.5 + 0.5 * np.sin(2 * np.pi * f * t)
    else:
        y = nz(n, seed)
    y *= env_exp(n, 0.0015, dur * 0.35)
    y = lp(y, 6000)
    return norm(y, amp)


def ui_sequence(freqs, dur_each=0.1, amp=0.5, kind="sine"):
    seg = [ui_blip(f, dur_each, 1.0, kind) for f in freqs]
    x = np.concatenate(seg)
    return norm(x, amp)


def vocal(seed=0, base=180.0, dur=0.5, amp=1.0, kind="shout"):
    """Formant-ish synthetic vocalisation for enemy barks."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    if kind == "shout":
        f0 = base * (1.0 + 0.18 * np.sin(2 * np.pi * 5.5 * t))
        src = np.sign(np.sin(2 * np.pi * np.cumsum(f0) / SR)) * 0.6
        env = env_exp(n, 0.012, dur * 0.42)
    else:  # grunt / pain
        f0 = base * np.exp(-t / 0.22)
        src = np.sign(np.sin(2 * np.pi * np.cumsum(f0) / SR)) * 0.6
        env = env_exp(n, 0.004, dur * 0.3)
    x = np.zeros(n)
    for f, g, q in ((520, 1.0, 90), (1180, 0.6, 120), (2650, 0.35, 160)):
        x += reson(src, f, q / SR * 0.02 + 0.002) * g
    x += src * 0.25
    x = lp(x, 4200)
    x = reverb(x, 0.45, 0.22, 3000, seed)
    return norm(x * env, amp)


def door_sfx(seed=0, amp=1.0, close=False):
    n = int(1.1 * SR)
    x = bp(nz(n, seed) * env_exp(n, 0.004, 0.35), 220, 2400)
    for i, g in enumerate((0.6, 0.4, 0.25)):
        off = int((0.06 + i * 0.09) * SR)
        x[off : off + n // 3] += reson(nz(n // 3, seed + i + 1), 340.0 + 90 * i, 0.02) * g
    if close:
        x = x[::-1] * 0.9
    x = reverb(x, 0.7, 0.3, 3000, seed + 5)
    return norm(x, amp)


def locker_sfx(seed=0, amp=1.0, close=False):
    n = int(0.7 * SR)
    x = bp(nz(n, seed) * env_exp(n, 0.001, 0.09), 500, 6000)
    x += reson(nz(n, seed + 1), 780.0, 0.09) * 0.7
    x += reson(nz(n, seed + 2), 1620.0, 0.05) * 0.4
    thud = np.sin(2 * np.pi * 88.0 * np.arange(n) / SR) * env_exp(n, 0.002, 0.06)
    x += thud * (0.8 if close else 0.3)
    x = reverb(x, 0.5, 0.28, 4200, seed + 3)
    return norm(x, amp)


def explosion(seed=0, amp=1.0, dur=2.2):
    n = int(dur * SR)
    t = np.arange(n) / SR
    boom = lp(nz(n, seed) * env_exp(n, 0.003, 0.5), 320, order=2)
    crack = hp(nz(n, seed + 1) * env_exp(n, 0.0004, 0.02), 1800)
    rumble = np.sin(2 * np.pi * 42.0 * t) * env_exp(n, 0.006, 0.7)
    x = boom * 1.4 + crack * 0.8 + rumble * 0.9
    x = reverb(x, 1.8, 0.4, 2200, seed + 2)
    return norm(x, amp)


def whoosh(seed=0, amp=1.0, dur=1.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = bp(nz(n, seed), 200, 3000)
    env = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 1.5
    x = lp(x * env, 2200)
    return norm(x, amp)


def heartbeat(seed=0, amp=1.0):
    n = int(0.9 * SR)
    x = np.zeros(n)
    for off, g in ((0.0, 1.0), (0.30, 0.72)):
        i = int(off * SR)
        seg = np.sin(2 * np.pi * 58.0 * np.arange(n - i) / SR) * env_exp(n - i, 0.004, 0.09)
        x[i:] += seg * g
    return norm(lp(x, 260, order=2), amp)


def metal_stinger(seed=0, amp=1.0, dur=2.4):
    n = int(dur * SR)
    x = np.zeros(n)
    for f, d, g in ((220, 1.4, 1.0), (330, 1.1, 0.6), (466, 0.9, 0.45), (622, 0.7, 0.3)):
        x += reson(nz(n, seed), f, d) * g
    x = reverb(x, 2.2, 0.45, 4000, seed + 3)
    return norm(x, amp)


def fade_in_out(x, ms=20):
    return fade_edges(x, ms)


# --------------------------------------------------------------------------
# Composition
# --------------------------------------------------------------------------


def compose_menu():
    """Slow, awe-struck.  The monolith at dusk."""
    tr = Track(66, 16, tail=6.0, seed=2)
    prog = [
        (["D3", "F3", "A3"], "D2"),
        (["Bb2", "D3", "F3"], "Bb1"),
        (["F2", "A2", "C3"], "F1"),
        (["C3", "E3", "G3"], "C2"),
    ]
    mel = [None, "A4", None, None, "F4", None, None, "D4",
           None, "C5", None, None, "A4", None, None, None,
           None, "D5", None, "C5", None, None, "A4", None,
           None, "G4", None, None, "E4", None, None, None]
    for bar in range(16):
        chord, root = prog[(bar // 4) % 4]
        if bar % 4 == 0:
            tr.add(pad_chord(chord, tr.bar * 4.05, cutoff=1150, detune=0.007, seed=bar), tr.t(bar), 0.30)
            tr.add(sub_note(pf(root), tr.bar * 4.05, amp=0.42, attack=0.6, release=1.2), tr.t(bar), 1.0)
        # airy noise swell every 4 bars
        if bar % 4 == 2:
            n = int(tr.bar * 2 * SR)
            swell = lp(nz(n, bar), 1400, order=2) * np.sin(np.pi * np.arange(n) / n) ** 2
            tr.add(norm(swell, 0.3), tr.t(bar), 0.5, pan=0.4)
        tok = mel[(bar * 2) % len(mel)] if bar < 16 else None
        if tok:
            tr.add(bell(pf(tok), 3.4, amp=0.30, index=1.5, decay=2.6), tr.t(bar, 0.0), 1.0, pan=-0.25)
        tok2 = mel[(bar * 2 + 8) % len(mel)]
        if tok2 and bar % 2 == 1:
            tr.add(bell(pf(tok2), 2.8, amp=0.16, index=2.2, decay=1.9), tr.t(bar, 2.5), 1.0, pan=0.35)
    return tr.finish(rev_decay=3.4, rev_mix=0.42, rev_damp=4200, peak=0.86)


def compose_explore():
    """Tense, patient, forward motion.  The drowned district."""
    tr = Track(74, 16, tail=5.0, seed=3)
    prog = [
        (["D3", "F3", "A3"], "D2", "D"),
        (["Bb2", "D3", "F3"], "Bb1", "Bb"),
        (["F2", "A2", "C3"], "F1", "F"),
        (["C3", "E3", "G3"], "C2", "C"),
    ]
    for bar in range(16):
        chord, root, _ = prog[(bar // 4) % 4]
        if bar % 4 == 0:
            tr.add(pad_chord(chord, tr.bar * 4.05, cutoff=950, detune=0.006, seed=bar + 40), tr.t(bar), 0.26)
            tr.add(sub_note(pf(root), tr.bar * 4.05, amp=0.38, attack=0.35, release=1.0), tr.t(bar))
        # pulsing low ostinato on the root
        for beat in (0.0, 1.5, 2.5, 3.0):
            tr.add(sub_note(pf(root), tr.spb * 0.9, amp=0.20, attack=0.006, release=0.18),
                   tr.t(bar, beat), 1.0, pan=-0.1)
        # frame-drum / taiko hits
        if bar % 4 in (0, 2):
            tr.add(kick(0.5, 120.0, 46.0) * 0.8, tr.t(bar, 0.0), 0.55)
        if bar % 8 == 3:
            tr.add(kick(0.5, 120.0, 46.0) * 0.8, tr.t(bar, 2.0), 0.5)
        if bar % 4 == 3:
            tr.add(snare(0.35, 0.6, seed=bar), tr.t(bar, 3.5), 0.35, pan=0.2)
        # distant metal clangs as texture
        if bar % 4 == 1:
            tr.add(reson(nz(int(1.6 * SR), bar), 820.0, 0.5) * 0.25, tr.t(bar, 1.5), 0.4, pan=0.55)
    return tr.finish(rev_decay=2.8, rev_mix=0.36, peak=0.88)


def compose_combat():
    """Driving, aggressive.  Suppressing fire in the flooded market."""
    bpm = 138
    tr = Track(bpm, 16, tail=3.5, seed=4)
    prog = [
        (["A2", "C3", "E3"], "A1"),
        (["F2", "A2", "C3"], "F1"),
        (["C3", "E3", "G3"], "C2"),
        (["E2", "G#2", "B2"], "E1"),
    ]
    for bar in range(16):
        chord, root = prog[(bar // 4) % 4]
        if bar % 4 == 0:
            tr.add(pad_chord(chord, tr.bar * 4.05, cutoff=1400, detune=0.01, seed=bar + 80, bright=0.5),
                   tr.t(bar), 0.24)
        # 8th-note driving bass
        for i in range(8):
            g = 0.42 if i % 2 == 0 else 0.28
            tr.add(sub_note(pf(root), tr.spb * 0.45, amp=g, attack=0.004, release=0.1),
                   tr.t(bar, i * 0.5), 1.0)
        # drums
        for beat in (0.0, 1.0, 2.0, 3.0):
            tr.add(kick(0.36, 160.0, 46.0), tr.t(bar, beat), 0.85)
        tr.add(kick(0.36, 160.0, 46.0) * 0.7, tr.t(bar, 2.75), 0.6)
        for beat in (1.0, 3.0):
            tr.add(snare(0.3, 0.95, seed=bar * 3 + int(beat)), tr.t(bar, beat), 0.7)
        for i in range(8):
            tr.add(hat(0.05, 0.35 if i % 2 else 0.5, seed=bar * 7 + i), tr.t(bar, i * 0.5 + 0.25), 1.0,
                   pan=0.3 if i % 2 else -0.3)
        tr.add(hat(0.13, 0.3, seed=bar + 500, open_=True), tr.t(bar, 3.75), 1.0)
        # brass-ish stabs
        if bar % 2 == 1:
            stab = pad_chord([chord[0], chord[1]], tr.spb * 0.4, cutoff=2600, detune=0.014,
                             seed=bar + 200, bright=0.8)
            tr.add(soft_clip(stab, 2.0), tr.t(bar, 2.5), 0.5, pan=0.15)
    return tr.finish(rev_decay=1.6, rev_mix=0.22, rev_damp=5200, drive=1.5, peak=0.92)


def compose_stealth():
    """Sparse, anxious.  Boots on wet tile in the dark."""
    tr = Track(58, 16, tail=6.0, seed=5)
    prog = [(["A2", "C3", "E3"], "A1"), (["G#2", "B2", "E3"], "G#1")]
    for bar in range(16):
        chord, root = prog[(bar // 4) % 2]
        if bar % 4 == 0:
            tr.add(pad_chord(chord, tr.bar * 4.05, cutoff=700, detune=0.004, seed=bar + 300), tr.t(bar), 0.22)
            tr.add(sub_note(pf(root), tr.bar * 2.0, amp=0.34, attack=1.2, release=1.5), tr.t(bar))
        # slow heartbeat-like pulse
        tr.add(heartbeat(seed=bar) * 0.35, tr.t(bar, 0.0 if bar % 2 == 0 else 2.0), 0.5)
        # high tension drone
        n = int(tr.bar * SR)
        drone = np.sin(2 * np.pi * pf("E6") * np.arange(n) / SR) * 0.5
        drone += np.sin(2 * np.pi * pf("B5") * np.arange(n) / SR) * 0.4
        trem = 0.35 + 0.65 * (0.5 + 0.5 * np.sin(2 * np.pi * 6.5 * np.arange(n) / SR))
        tr.add(lp(drone * trem, 3000) * 0.10, tr.t(bar), 0.5, pan=0.5)
        # metallic pings
        if bar % 8 == 5:
            tr.add(reson(nz(int(2.4 * SR), bar + 11), 1180.0, 1.2) * 0.3, tr.t(bar, 0.25), 0.4, pan=-0.6)
        if bar % 4 == 2:
            tr.add(whoosh(seed=bar, dur=1.6), tr.t(bar), 0.18, pan=0.0)
    return tr.finish(rev_decay=4.0, rev_mix=0.46, rev_damp=3600, peak=0.82)


def compose_meadow():
    """Warm and hopeful.  Sunlight after the ash."""
    tr = Track(78, 16, tail=5.0, seed=6)
    prog = [
        (["F3", "A3", "C4"], "F2"),
        (["C3", "E3", "G3"], "C2"),
        (["G2", "B2", "D3"], "G1"),
        (["A2", "C3", "E3"], "A1"),
    ]
    mel = ["A4", "C5", "F4", "G4", "A4", "F4", "C5", "A4",
           "G4", "E4", "G4", "C5", "D5", "C5", "A4", "G4",
           "F4", "A4", "C5", "D5", "E5", "D5", "C5", "A4",
           "G4", "A4", "C5", "G4", "F4", "C5", "A4", None]
    for bar in range(16):
        chord, root = prog[(bar // 4) % 4]
        if bar % 4 == 0:
            tr.add(pad_chord(chord, tr.bar * 4.05, cutoff=2000, detune=0.009, seed=bar + 400, bright=0.6),
                   tr.t(bar), 0.26)
            tr.add(sub_note(pf(root), tr.bar * 4.05, amp=0.30, attack=0.5, release=2.0), tr.t(bar))
        # gentle arpeggio
        for i in range(4):
            tok = chord[i % len(chord)]
            tr.add(bell(pf(tok) * 2, 1.6, amp=0.10, index=1.2, decay=1.2), tr.t(bar, i * 1.0), 1.0,
                   pan=-0.4 + 0.3 * i)
        tok = mel[(bar * 2) % len(mel)]
        if tok:
            tr.add(bell(pf(tok), 3.0, amp=0.24, index=1.4, decay=2.2), tr.t(bar, 0.0), 1.0, pan=0.2)
        tok2 = mel[(bar * 2 + 1) % len(mel)]
        if tok2:
            tr.add(bell(pf(tok2), 2.0, amp=0.12, index=2.0, decay=1.4), tr.t(bar, 2.0), 1.0, pan=-0.2)
        # soft shaker and light kick for pulse
        for i in range(8):
            tr.add(tamb(0.1, 0.16, seed=bar * 13 + i), tr.t(bar, i * 0.5 + 0.25), 1.0,
                   pan=0.45 if i % 2 else -0.45)
        if bar % 4 in (0, 2):
            tr.add(kick(0.3, 110.0, 48.0) * 0.5, tr.t(bar, 0.0), 0.4)
    return tr.finish(rev_decay=3.6, rev_mix=0.4, rev_damp=5000, peak=0.88)


# --------------------------------------------------------------------------
# Render manifest
# --------------------------------------------------------------------------


def build_manifest():
    """Return {filename: (signal_builder, loop)}."""
    m = {}

    # --- UI ---------------------------------------------------------------
    m["ui_hover"] = (lambda: ui_blip(1320.0, 0.05, 0.22, "sine"), False)
    m["ui_click"] = (lambda: ui_blip(760.0, 0.07, 0.5, "square"), False)
    m["ui_confirm"] = (lambda: ui_sequence([660.0, 990.0], 0.07, 0.45), False)
    m["ui_back"] = (lambda: ui_sequence([520.0, 340.0], 0.08, 0.45), False)
    m["ui_deny"] = (lambda: ui_sequence([300.0, 220.0], 0.09, 0.5, "square"), False)
    m["ui_tab"] = (lambda: ui_blip(1050.0, 0.06, 0.3, "sine"), False)
    m["ui_slider"] = (lambda: ui_blip(1500.0, 0.03, 0.25, "sine"), False)

    # --- combat -----------------------------------------------------------
    for i in range(3):
        m["rifle_fire_%d" % (i + 1)] = (lambda i=i: gunshot(100 + i, 0.95, 0.13, 0.5), False)
    m["rifle_dry"] = (lambda: mechanical_click(7, 2000, 9000, 0.05, 900.0, 0.85), False)
    m["mag_out"] = (lambda: mechanical_click(11, 700, 5000, 0.12, 240.0, 0.9), False)
    m["mag_in"] = (lambda: mechanical_click(13, 500, 4200, 0.14, 190.0, 1.0), False)
    m["bolt"] = (lambda: mechanical_click(17, 1500, 9000, 0.1, 420.0, 0.95), False)
    m["shell_drop"] = (lambda: np.concatenate([
        mechanical_click(19, 3000, 12000, 0.09, 2400.0, 0.5),
        np.zeros(int(0.14 * SR)),
        mechanical_click(23, 3500, 13000, 0.07, 2900.0, 0.32),
    ]), False)
    m["hit_marker"] = (lambda: ui_blip(2100.0, 0.045, 0.4), False)
    m["hit_crit"] = (lambda: ui_sequence([2600.0, 3400.0], 0.04, 0.45), False)

    # --- impacts ----------------------------------------------------------
    for i in range(3):
        m["impact_concrete_%d" % (i + 1)] = (lambda i=i: impact_concrete(200 + i, 0.85), False)
    for i in range(2):
        m["impact_metal_%d" % (i + 1)] = (lambda i=i: impact_metal(210 + i, 0.85), False)
    m["impact_flesh"] = (lambda: impact_flesh(220, 0.9), False)
    m["impact_water"] = (lambda: impact_water(230, 0.8), False)
    m["impact_ricochet"] = (lambda: np.concatenate([
        reson(nz(int(0.5 * SR), 240), 3400.0, 0.25),
        np.zeros(int(0.05 * SR)),
        reson(nz(int(0.3 * SR), 241), 2100.0, 0.15) * 0.4,
    ]), False)

    # --- movement ---------------------------------------------------------
    for kind, seed0 in (("concrete", 300), ("gravel", 320), ("water", 340), ("grass", 360), ("metal", 380)):
        for i in range(4):
            m["step_%s_%d" % (kind, i + 1)] = (lambda k=kind, s=seed0 + i: footstep(s, k, 0.7), False)
    m["jump_grunt"] = (lambda: vocal(400, 150.0, 0.35, 0.5, "grunt"), False)
    m["land"] = (lambda: footstep(402, "concrete", 1.0) * 1.2, False)
    m["gear"] = (lambda: bp(nz(int(0.35 * SR), 404) * env_exp(int(0.35 * SR), 0.003, 0.09), 800, 7000, 2) * 0.4, False)

    # --- player state -----------------------------------------------------
    m["player_hurt"] = (lambda: vocal(410, 170.0, 0.4, 0.85, "grunt"), False)
    m["player_death"] = (lambda: vocal(412, 150.0, 1.4, 1.0, "grunt"), False)
    m["heartbeat"] = (lambda: heartbeat(414, 0.9), False)
    m["heal"] = (lambda: ui_sequence([660.0, 880.0, 1320.0], 0.09, 0.35), False)

    # --- enemy ------------------------------------------------------------
    m["enemy_alert"] = (lambda: vocal(500, 190.0, 0.55, 1.0, "shout"), False)
    m["enemy_shout"] = (lambda: vocal(502, 205.0, 0.7, 0.9, "shout"), False)
    m["enemy_pain"] = (lambda: vocal(504, 175.0, 0.33, 0.9, "grunt"), False)
    m["enemy_death"] = (lambda: vocal(506, 160.0, 0.95, 1.0, "grunt"), False)
    m["enemy_spot"] = (lambda: ui_sequence([880.0, 1180.0], 0.05, 0.3), False)

    # --- world ------------------------------------------------------------
    m["door_open"] = (lambda: door_sfx(600, 0.8, False), False)
    m["door_close"] = (lambda: door_sfx(602, 0.8, True), False)
    m["locker_open"] = (lambda: locker_sfx(610, 0.85, False), False)
    m["locker_close"] = (lambda: locker_sfx(612, 0.85, True), False)
    m["switch"] = (lambda: mechanical_click(620, 1400, 6000, 0.09, 520.0, 0.8), False)
    m["pickup"] = (lambda: ui_sequence([780.0, 1040.0, 1560.0], 0.06, 0.35), False)
    m["objective"] = (lambda: ui_sequence([660.0, 990.0, 1320.0], 0.13, 0.4), False)
    m["checkpoint"] = (lambda: np.concatenate([
        ui_sequence([520.0, 780.0], 0.1, 0.35),
        np.zeros(int(0.08 * SR)),
        norm(bell(pf("D5"), 2.0, 0.3, 1.4, 2.0), 0.35),
    ]), False)
    m["chapter"] = (lambda: norm(np.concatenate([
        np.zeros(int(0.3 * SR)),
        metal_stinger(700, 0.8, 3.0),
    ]), 0.8), False)
    m["explosion"] = (lambda: explosion(720, 0.95), False)
    m["whoosh"] = (lambda: whoosh(730, 0.6, 1.2), False)
    m["flesh_fall"] = (lambda: lp(nz(int(0.4 * SR), 740) * env_exp(int(0.4 * SR), 0.004, 0.09), 700, 2) * 0.7, False)

    # --- ambience loops ---------------------------------------------------
    m["amb_rain"] = (lambda: fade_in_out(rain_layer(14.0, 800, 0.8, 1.0), 60.0), True)
    m["amb_rain_light"] = (lambda: fade_in_out(rain_layer(14.0, 802, 0.45, 0.45), 60.0), True)
    m["amb_wind"] = (lambda: fade_in_out(ambience_noise(16.0, 810, 120, 2600, 1800, 0.5), 60.0), True)
    m["amb_city"] = (lambda: fade_in_out(ambience_noise(18.0, 820, 60, 900, 700, 0.6), 60.0), True)
    m["amb_water"] = (lambda: fade_in_out(water_lap(830, 0.5, 18.0), 60.0), True)
    m["amb_interior"] = (lambda: fade_in_out(ambience_noise(16.0, 840, 40, 500, 400, 0.4) * 0.7, 60.0), True)
    m["amb_meadow"] = (lambda: fade_in_out(ambience_noise(18.0, 850, 200, 5000, 4000, 0.35, brown=False), 60.0), True)
    m["amb_embers"] = (lambda: fade_in_out(bp(nz(int(12 * SR), 860), 300, 1800) * 0.35, 60.0), True)

    # --- music ------------------------------------------------------------
    m["mus_menu"] = (compose_menu, True)
    m["mus_explore"] = (compose_explore, True)
    m["mus_combat"] = (compose_combat, True)
    m["mus_stealth"] = (compose_stealth, True)
    m["mus_meadow"] = (compose_meadow, True)

    return m


# --------------------------------------------------------------------------
# IO
# --------------------------------------------------------------------------


def save_wav(path, data):
    import wave

    st = np.asarray(data, dtype=np.float64)
    if st.ndim == 1:
        st = np.stack([st, st], axis=1)
    st = np.clip(st, -1.0, 1.0)
    pcm = (st * 32767.0).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def find_encoder():
    """Pick a codec Godot can decode (.ogg Vorbis preferred, then .mp3).

    `ffmpeg -h encoder=x` exits 0 even for unknown encoders, so the only
    reliable probe is a real test encode.
    """
    probe = os.path.join(RAW_DIR, "_probe.wav")
    import wave as _wave

    t = np.arange(SR // 4) / SR
    tone = np.stack([np.sin(2 * np.pi * 440 * t)] * 2, axis=1)
    pcm = (np.clip(tone, -1, 1) * 32767).astype("<i2")
    with _wave.open(probe, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())

    for ext, enc, args in (
        ("ogg", "vorbis", ["-c:a", "libvorbis", "-q:a", "5"]),
        ("ogg", "vorbis", ["-c:a", "vorbis", "-strict", "-2", "-q:a", "5"]),
        ("mp3", "mp3", ["-c:a", "libmp3lame", "-q:a", "3"]),
    ):
        try:
            r = subprocess.run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
                                "-i", probe] + args + [os.path.join(RAW_DIR, "_probe." + ext)],
                               capture_output=True, text=True, timeout=30)
            if r.returncode == 0 and os.path.getsize(os.path.join(RAW_DIR, "_probe." + ext)) > 128:
                return ext, args
        except Exception:
            pass
    return None, None


def main():
    only = set(sys.argv[1:])
    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs(RAW_DIR, exist_ok=True)
    ext, enc_args = find_encoder()
    if ext is None:
        print("!! no compressed encoder found; shipping WAV")
    else:
        print("container: .%s" % ext)

    manifest = build_manifest()
    names = sorted(manifest)
    if only:
        names = [n for n in names if n in only]

    total = 0
    for i, name in enumerate(names, 1):
        builder, loop = manifest[name]
        try:
            data = builder()
        except Exception as e:  # keep going; report at the end
            print("  [%3d/%3d] %-22s FAILED: %s" % (i, len(names), name, e))
            continue
        wav = os.path.join(RAW_DIR, name + ".wav")
        save_wav(wav, data)
        dur = len(np.asarray(data)) / float(SR)
        out = None
        if ext is not None:
            out = os.path.join(OUT_DIR, name + "." + ext)
            r = subprocess.run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
                                "-i", wav] + enc_args + ["-ar", "44100", "-ac", "2", out],
                               capture_output=True, text=True)
            if r.returncode != 0:
                print("  [%3d/%3d] %-22s ffmpeg error: %s" % (i, len(names), name, r.stderr.strip()[:120]))
                out = None
        if out is None:
            out = os.path.join(OUT_DIR, name + ".wav")
            shutil.copy(wav, out)
        for stale in (".ogg", ".mp3", ".wav"):
            other = os.path.join(OUT_DIR, name + stale)
            if other != out and os.path.exists(other):
                os.remove(other)
        sz = os.path.getsize(out)
        total += sz
        print("  [%3d/%3d] %-22s %5.1fs  loop=%-5s %6.0f KB"
              % (i, len(names), name, dur, str(loop), sz / 1024.0))

    if os.path.isdir(RAW_DIR):
        shutil.rmtree(RAW_DIR, ignore_errors=True)
    print("\n%d files, %.1f MB total -> %s" % (len(names), total / 1048576.0, OUT_DIR))


if __name__ == "__main__":
    main()
