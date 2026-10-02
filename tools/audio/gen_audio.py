#!/usr/bin/env python3
"""
Synthesises Mildew's PROVISIONAL audio kit (late-90s cheap game-show library music,
stings, applause layers, UI sounds). Fully procedural (numpy/scipy) => owned by the
project, no licensing risk. Replace with produced audio later; keep filenames stable.

    python3 tools/audio/gen_audio.py            # writes assets/audio/*.wav

Status: provisional placeholder (tracked in PROGRESS.md / docs/testing reports).
"""
import os
import wave
import numpy as np
from scipy.signal import butter, lfilter

SR = 32000
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio")
rng = np.random.default_rng(1998)


def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12)


def t_axis(sec):
    return np.arange(int(sec * SR)) / SR


def env_adsr(n, a=0.01, d=0.08, s=0.7, r=0.12):
    e = np.ones(n) * s
    na, nd, nr = int(a * SR), int(d * SR), int(r * SR)
    na = max(1, min(na, n)); nd = max(1, min(nd, n - na)); nr = max(1, min(nr, n))
    e[:na] = np.linspace(0, 1, na)
    e[na:na + nd] = np.linspace(1, s, nd)
    e[-nr:] *= np.linspace(1, 0, nr)
    return e


def brass(freq, sec, vel=1.0, bright=1.0):
    """Additive 'cheap synth brass': harmonic weights open up during the attack."""
    t = t_axis(sec)
    n = len(t)
    swell = np.clip(t / 0.06, 0, 1) ** 0.7
    out = np.zeros(n)
    for k in range(1, 14):
        w = (1.0 / k) * (swell * bright) ** (0.35 * (k - 1))
        detune = 1 + 0.0025 * np.sin(2 * np.pi * 5.5 * t) * (k == 1)
        out += w * np.sin(2 * np.pi * freq * k * t * detune + rng.random() * 0.2)
    return out * env_adsr(n, 0.02, 0.1, 0.75, 0.08) * vel * 0.18


def epiano(freq, sec, vel=1.0):
    t = t_axis(sec)
    mod = np.sin(2 * np.pi * freq * 14 * t) * np.exp(-t * 9) * 1.6
    tone = np.sin(2 * np.pi * freq * t + mod) + 0.3 * np.sin(2 * np.pi * freq * 2 * t)
    return tone * np.exp(-t * 2.2) * env_adsr(len(t), 0.002, 0.05, 1.0, 0.05) * vel * 0.16


def bass(freq, sec, vel=1.0):
    t = t_axis(sec)
    saw = sum(np.sin(2 * np.pi * freq * k * t) / k for k in range(1, 8))
    return saw * np.exp(-t * 3.0) * env_adsr(len(t), 0.005, 0.05, 1, 0.04) * vel * 0.22


def kick(vel=1.0):
    t = t_axis(0.35)
    f = 50 + 120 * np.exp(-t * 30)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * np.exp(-t * 9) * vel * 0.9


def snare(vel=1.0):
    t = t_axis(0.25)
    noise = rng.standard_normal(len(t))
    b, a = butter(2, [1200 / (SR / 2), 7000 / (SR / 2)], btype="band")
    return (lfilter(b, a, noise) * 0.9 + 0.4 * np.sin(2 * np.pi * 190 * t)) * np.exp(-t * 18) * vel * 0.55


def hat(vel=1.0, open_=False):
    t = t_axis(0.3 if open_ else 0.06)
    noise = rng.standard_normal(len(t))
    b, a = butter(2, 7000 / (SR / 2), btype="high")
    return lfilter(b, a, noise) * np.exp(-t * (12 if open_ else 70)) * vel * 0.22


def cymbal(sec=2.5, vel=1.0):
    t = t_axis(sec)
    noise = rng.standard_normal(len(t))
    b, a = butter(2, 5000 / (SR / 2), btype="high")
    return lfilter(b, a, noise) * np.exp(-t * 1.6) * vel * 0.35


def mix_into(buf, sig, at_sec):
    i = int(at_sec * SR)
    if i >= len(buf):
        return
    j = min(len(buf), i + len(sig))
    buf[i:j] += sig[: j - i]


def chord(notes, sec, fn=brass, vel=1.0, **kw):
    return sum(fn(midi(n), sec, vel, **kw) for n in notes)


def master(x, gain=0.9, tape=True):
    if tape:
        # gentle "broadcast" band-limiting + slow wow
        b, a = butter(2, [60 / (SR / 2), 9000 / (SR / 2)], btype="band")
        x = lfilter(b, a, x)
    peak = np.max(np.abs(x)) or 1.0
    x = np.tanh(x / peak * 1.4) * gain
    return x


def write(name, x):
    os.makedirs(OUT, exist_ok=True)
    data = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print("wrote", name, "%.2fs" % (len(x) / SR))


# Bb major, 128 bpm, overconfident.
BPM = 128
BEAT = 60 / BPM
BB, GM, EB, F = [58, 62, 65, 70], [55, 58, 62, 67], [51, 55, 58, 63], [53, 57, 60, 65]


def drums(buf, start, bars, fill=False):
    for bar in range(bars):
        for b in range(4):
            t0 = start + (bar * 4 + b) * BEAT
            mix_into(buf, kick(1.0 if b in (0, 2) else 0.0), t0)
            if b in (1, 3):
                mix_into(buf, snare(), t0)
            for e in range(2):
                mix_into(buf, hat(0.8 if e == 0 else 0.5), t0 + e * BEAT / 2)
        if fill and bar == bars - 1:
            for k in range(4):
                mix_into(buf, snare(0.6 + 0.1 * k), start + (bar * 4 + 3) * BEAT + k * BEAT / 4)


def gen_opening():
    total = 9.4
    buf = np.zeros(int(total * SR))
    # pickup: rising brass run
    run = [58, 60, 62, 63, 65, 67, 69]
    for i, n in enumerate(run):
        mix_into(buf, brass(midi(n), BEAT / 2.2, 0.7), i * BEAT / 4)
    start = len(run) * BEAT / 4
    prog = [BB, GM, EB, F, BB, GM, EB, F]
    for i, c in enumerate(prog[:4]):
        t0 = start + i * 2 * BEAT * 2
        mix_into(buf, chord(c, BEAT * 0.9), t0)
        mix_into(buf, chord(c, BEAT * 0.45, vel=0.8), t0 + BEAT * 1.5)
        mix_into(buf, chord(c, BEAT * 1.8, vel=0.9), t0 + BEAT * 2.5)
        mix_into(buf, bass(midi(c[0] - 12), BEAT * 0.9), t0)
        mix_into(buf, bass(midi(c[0] - 12), BEAT * 0.9), t0 + BEAT * 2)
        mix_into(buf, bass(midi(c[0] - 5), BEAT * 0.9), t0 + BEAT * 3)
    drums(buf, start, 4, fill=True)
    end = start + 16 * BEAT
    mix_into(buf, chord([46, 58, 62, 65, 70, 74], 2.8, vel=1.2), end)
    mix_into(buf, cymbal(2.6), end)
    mix_into(buf, kick(1.2), end)
    write("theme_opening.wav", master(buf))


def gen_lobby_bed():
    bars = 8
    total = bars * 4 * BEAT * 1.25  # slower feel: 102 bpm
    beat = BEAT * 1.25
    buf = np.zeros(int(total * SR))
    prog = [[58, 62, 65, 69], [55, 58, 62, 65], [51, 55, 58, 62], [53, 57, 60, 64]]
    for bar in range(bars):
        c = prog[bar % 4]
        t0 = bar * 4 * beat
        for b in (0, 1.5, 2.5):
            mix_into(buf, chord(c, beat * 0.9, fn=epiano, vel=0.7), t0 + b * beat)
        mix_into(buf, bass(midi(c[0] - 24), beat * 0.9, 0.8), t0)
        mix_into(buf, bass(midi(c[0] - 17), beat * 0.9, 0.6), t0 + 2 * beat)
        for b in range(8):
            mix_into(buf, hat(0.35 if b % 2 else 0.5), t0 + b * beat / 2)
        mix_into(buf, kick(0.5), t0)
        mix_into(buf, kick(0.4), t0 + 2.5 * beat)
    write("lobby_bed.wav", master(buf, 0.6))


def gen_sting():
    buf = np.zeros(int(3.6 * SR))
    for i, n in enumerate([65, 67, 69, 70, 72, 74, 77]):
        mix_into(buf, brass(midi(n), 0.16, 0.7 + i * 0.04), i * 0.07)
    mix_into(buf, chord([58, 65, 70, 74, 77], 2.4, vel=1.3), 0.55)
    mix_into(buf, cymbal(2.2, 0.9), 0.55)
    mix_into(buf, kick(1.2), 0.55)
    mix_into(buf, snare(1.0), 0.55)
    write("sting_game.wav", master(buf))


def gen_ident():
    buf = np.zeros(int(3.6 * SR))
    pad = chord([51, 58, 62, 67], 3.2, fn=epiano, vel=0.9)
    mix_into(buf, pad, 0.0)
    for i, n in enumerate([79, 82, 86]):
        t = t_axis(1.6)
        bell = np.sin(2 * np.pi * midi(n) * t) * np.exp(-t * 3.5) * 0.25
        mix_into(buf, bell, 0.35 + i * 0.22)
    write("ident_sallow.wav", master(buf, 0.7))


def gen_ui():
    t = t_axis(0.9)
    ding = np.zeros(len(t))
    for i, n in enumerate([84, 91]):
        tt = t_axis(0.9 - i * 0.12)
        s = (np.sin(2 * np.pi * midi(n) * tt) + 0.4 * np.sin(2 * np.pi * midi(n) * 2.76 * tt)) * np.exp(-tt * 5) * 0.4
        mix_into(ding, s, i * 0.12)
    write("correct.wav", master(ding, 0.8, tape=False))
    t = t_axis(0.75)
    buzz = (np.sign(np.sin(2 * np.pi * 98 * t)) + np.sign(np.sin(2 * np.pi * 104 * t))) * 0.3 * env_adsr(len(t), 0.005, 0.05, 1, 0.08)
    b, a = butter(2, 2500 / (SR / 2))
    write("wrong.wav", master(lfilter(b, a, buzz), 0.75, tape=False))
    t = t_axis(0.12)
    click = np.sin(2 * np.pi * 1320 * t) * np.exp(-t * 60) * 0.6 + rng.standard_normal(len(t)) * np.exp(-t * 200) * 0.2
    write("lock.wav", master(click, 0.6, tape=False))
    t = t_axis(0.08)
    write("tick.wav", master(np.sin(2 * np.pi * 900 * t) * np.exp(-t * 50), 0.4, tape=False))
    t = t_axis(0.45)
    noise = rng.standard_normal(len(t))
    write("static_burst.wav", master(noise * env_adsr(len(t), 0.005, 0.1, 0.6, 0.15), 0.35, tape=False))
    t = t_axis(0.7)
    noise = rng.standard_normal(len(t))
    out = np.zeros(len(t))
    for i in range(0, len(t), 256):
        fc = 400 + 5000 * (i / len(t))
        b, a = butter(2, [fc / (SR / 2), min(0.99, (fc * 1.6) / (SR / 2))], btype="band")
        out[i:i + 256] = lfilter(b, a, noise[i:i + 256])
    write("whoosh.wav", master(out * np.sin(np.pi * t / t[-1]), 0.5, tape=False))


def applause(sec, density, name, swell=0.25):
    """Many short band-passed noise claps; density = claps/sec at peak."""
    n = int(sec * SR)
    buf = np.zeros(n)
    t = np.arange(n) / SR
    shape = np.minimum(1, t / swell) * np.clip((sec - t) / (sec * 0.45), 0, 1) ** 1.2
    count = int(density * sec)
    clap_len = int(0.025 * SR)
    for _ in range(count):
        at = rng.random() * sec
        idx = int(at * SR)
        if shape[min(idx, n - 1)] < rng.random() * 0.9:
            continue
        ct = np.arange(clap_len) / SR
        c = rng.standard_normal(clap_len) * np.exp(-ct * (180 + rng.random() * 160)) * (0.4 + rng.random() * 0.6)
        j = min(n, idx + clap_len)
        buf[idx:j] += c[: j - idx]
    b, a = butter(2, [700 / (SR / 2), 6000 / (SR / 2)], btype="band")
    buf = lfilter(b, a, buf)
    # room tone / wash
    wash = lfilter(*butter(2, [300 / (SR / 2), 3000 / (SR / 2)], btype="band"), rng.standard_normal(n)) * 0.08 * shape
    write(name, master(buf + wash, 0.8, tape=True))


if __name__ == "__main__":
    gen_opening()
    gen_lobby_bed()
    gen_sting()
    gen_ident()
    gen_ui()
    applause(2.2, 500, "applause_small.wav", 0.15)
    applause(4.0, 1600, "applause_medium.wav", 0.3)
    applause(6.5, 3200, "applause_big.wav", 0.5)
