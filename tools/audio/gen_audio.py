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


def gen_hole_sting():
    """HOLE! — ridiculous mystery slide-whistle dive, timpani, then a huge trumpet stab (docs/02)."""
    buf = np.zeros(int(4.2 * SR))
    t = t_axis(1.0)
    f = 1900 * (300 / 1900) ** (t / t[-1]) * (1 + 0.03 * np.sin(2 * np.pi * 7 * t))
    ph = 2 * np.pi * np.cumsum(f) / SR
    whistle = (np.sin(ph) + 0.15 * np.sin(2 * ph)) * env_adsr(len(t), 0.02, 0.1, 0.9, 0.1) * 0.22
    mix_into(buf, whistle, 0.0)
    tt = t_axis(1.4)
    timp = np.sin(2 * np.pi * 70 * tt * (1 + 0.15 * np.exp(-tt * 30))) * np.exp(-tt * 3.2) * 0.7
    mix_into(buf, timp, 1.0)
    mix_into(buf, timp * 0.8, 1.18)
    mix_into(buf, chord([58, 65, 70, 74, 77, 82], 2.6, vel=1.6, bright=1.2), 1.36)
    mix_into(buf, chord([46, 58], 2.6, fn=bass, vel=1.2), 1.36)
    mix_into(buf, cymbal(2.6, 1.0), 1.36)
    mix_into(buf, kick(1.4), 1.36)
    mix_into(buf, snare(1.1), 1.36)
    write("sting_hole.wav", master(buf))


def _voice(f0, sec, formants, glide=None, am=None):
    """One crude formant-synthesised voice: jittery sawtooth through vowel resonators."""
    t = t_axis(sec)
    n = len(t)
    f = f0 * (1 + 0.012 * np.sin(2 * np.pi * (4 + rng.random() * 2) * t + rng.random() * 6))
    if glide is not None:
        f = f * glide(t)
    ph = np.cumsum(f) / SR
    saw = 2 * (ph - np.floor(ph + 0.5))
    out = np.zeros(n)
    for fc, bw, g in formants:
        lo, hi = max(40, fc - bw / 2), min(SR / 2 - 100, fc + bw / 2)
        b, a = butter(2, [lo / (SR / 2), hi / (SR / 2)], btype="band")
        out += lfilter(b, a, saw) * g
    if am is not None:
        out *= am(t)
    return out


def crowd(name, sec, voices, formants_fn, contour, glide=None, am=None, gain=0.8, breath=0.0):
    n = int(sec * SR)
    buf = np.zeros(n)
    for _ in range(voices):
        f0 = rng.uniform(105, 150) if rng.random() < 0.5 else rng.uniform(190, 280)
        start = rng.uniform(0, 0.12)
        v = _voice(f0, sec - start, formants_fn(), glide, am)
        mix_into(buf, v * rng.uniform(0.5, 1.0), start)
    t = np.arange(n) / SR
    buf *= contour(t)
    if breath > 0:
        nb = lfilter(*butter(2, [500 / (SR / 2), 4000 / (SR / 2)], btype="band"), rng.standard_normal(n))
        buf += nb * breath * contour(t)
    buf /= max(1e-6, np.abs(buf).max())
    write(name, master(buf * 0.7, gain, tape=True))


def gen_crowd():
    oo = lambda: [(300, 120, 1.0), (870, 160, 0.4), (2240, 300, 0.1)]
    aa = lambda: [(730, 160, 1.0), (1090, 200, 0.6), (2440, 300, 0.15)]
    # "Ooooh!" — impressed: rises then settles
    crowd("crowd_ooh.wav", 1.9, 36, oo, lambda t: np.clip(t / 0.25, 0, 1) * np.clip((1.9 - t) / 0.9, 0, 1),
          glide=lambda t: 1 + 0.25 * np.sin(np.pi * np.clip(t / 1.4, 0, 1)))
    # "Awww" — sympathetic / disappointed: falls
    crowd("crowd_aww.wav", 1.7, 36, aa, lambda t: np.clip(t / 0.15, 0, 1) * np.clip((1.7 - t) / 1.0, 0, 1),
          glide=lambda t: 1.25 - 0.4 * np.clip(t / 1.5, 0, 1))
    # Laugh — chuckling bursts at ~5 Hz, slightly out of phase per voice
    def laugh_am(t):
        rate = rng.uniform(4.2, 5.6)
        return np.clip(np.sin(2 * np.pi * rate * t + rng.random() * 6), 0, 1) ** 2
    crowd("crowd_laugh.wav", 2.4, 30, aa, lambda t: np.clip(t / 0.1, 0, 1) * np.clip((2.4 - t) / 1.4, 0, 1),
          glide=lambda t: 1.15 - 0.15 * np.clip(t / 2.0, 0, 1), am=laugh_am, breath=0.2)
    # Gasp — sharp collective inhalation (mostly breath noise)
    n = int(0.9 * SR)
    t = np.arange(n) / SR
    nb = lfilter(*butter(2, [900 / (SR / 2), 6000 / (SR / 2)], btype="band"), rng.standard_normal(n))
    write("crowd_gasp.wav", master(nb * np.clip(t / 0.06, 0, 1) * np.exp(-t * 4.5) * 0.6, 0.6, tape=True))


def gen_production():
    # Camera zoom servo (each Hole stage pull-back)
    t = t_axis(0.6)
    f = 180 + 120 * t / t[-1]
    ph = np.cumsum(f) / SR
    whir = (2 * (ph - np.floor(ph + 0.5))) * 0.15 + rng.standard_normal(len(t)) * 0.04
    whir = lfilter(*butter(2, [150 / (SR / 2), 2500 / (SR / 2)], btype="band"), whir)
    write("zoom_servo.wav", master(whir * env_adsr(len(t), 0.05, 0.1, 0.8, 0.2), 0.45, tape=True))
    # Mic pop / knock (Tier 0)
    t = t_axis(0.35)
    pop = np.sin(2 * np.pi * 60 * t) * np.exp(-t * 18) * 0.9 + rng.standard_normal(len(t)) * np.exp(-t * 90) * 0.4
    write("mic_pop.wav", master(lfilter(*butter(2, 1800 / (SR / 2)), pop), 0.8, tape=False))
    # Feedback squeal (Tier 0, short)
    t = t_axis(0.7)
    squeal = np.sin(2 * np.pi * 2900 * t * (1 + 0.004 * np.sin(2 * np.pi * 6 * t))) * env_adsr(len(t), 0.15, 0.1, 0.9, 0.2) * 0.25
    write("feedback.wav", master(squeal, 0.45, tape=False))


def gen_cp8():
    """Adverts jingle, break bumper, and the sinister kit: distant banging, room tone, door, drone."""
    # Advert jingle: 2.2 s bright cheap synth hook
    buf = np.zeros(int(SR * 2.4))
    notes = [72, 76, 79, 84, 79, 84]
    for i, n in enumerate(notes):
        mix_into(buf, epiano(midi(n), 0.3, 0.9), i * 0.18)
    mix_into(buf, chord([60, 64, 67, 72], 1.2, brass, 0.6), 1.1)
    write("jingle_advert.wav", master(buf, 0.6))
    # Break bumper: ident-like rising chord
    buf = np.zeros(int(SR * 3.0))
    mix_into(buf, chord([55, 62, 67, 71], 2.4, brass, 0.7), 0.0)
    mix_into(buf, cymbal(2.0, 0.4), 0.0)
    write("break_bumper.wav", master(buf, 0.6))
    # Distant banging: three heavy, muffled thuds somewhere in the building, with a tail
    t = t_axis(3.2)
    x = np.zeros(len(t))
    for at, v in [(0.0, 1.0), (0.55, 0.85), (1.6, 1.0)]:
        i0 = int(at * SR)
        tt = t[: len(t) - i0]
        thud = (np.sin(2 * np.pi * 52 * tt) * np.exp(-tt * 9) + rng.standard_normal(len(tt)) * np.exp(-tt * 30) * 0.3) * v
        x[i0:] += thud
    x = lfilter(*butter(2, 420 / (SR / 2)), x)
    tail = np.convolve(x, np.exp(-np.linspace(0, 6, int(SR * 0.6))) * rng.standard_normal(int(SR * 0.6)) * 0.02, mode="full")[: len(x)]
    write("bang_distant.wav", master(x * 0.8 + tail, 0.55, tape=True))
    # Room tone / hum drone: 6 s, 50 Hz mains + air
    t = t_axis(6.0)
    hum = np.sin(2 * np.pi * 50 * t) * 0.12 + np.sin(2 * np.pi * 100 * t) * 0.06 + np.sin(2 * np.pi * 150 * t) * 0.02
    air = lfilter(*butter(2, 700 / (SR / 2)), rng.standard_normal(len(t))) * 0.05
    fade = np.minimum(1, np.minimum(t / 0.8, (t[-1] - t) / 0.8))
    write("room_tone.wav", master((hum + air) * fade, 0.5, tape=True))
    # Heavy door closing somewhere off-set
    t = t_axis(1.6)
    door = np.sin(2 * np.pi * 70 * t) * np.exp(-t * 6) + lfilter(*butter(2, 1200 / (SR / 2)), rng.standard_normal(len(t))) * np.exp(-t * 14) * 0.5
    creak = np.sin(2 * np.pi * (300 + 60 * np.sin(2 * np.pi * 3 * t)) * t) * np.exp(-((t - 0.0) * 4)) * 0.0
    write("door_distant.wav", master(lfilter(*butter(2, 900 / (SR / 2)), door + creak) * 0.9, 0.5, tape=True))


if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1 and sys.argv[1] == "cp8":
        gen_cp8()
        raise SystemExit
    if len(sys.argv) > 1 and sys.argv[1] == "cp2":
        gen_hole_sting()
        gen_crowd()
        gen_production()
        raise SystemExit
    gen_opening()
    gen_lobby_bed()
    gen_sting()
    gen_ident()
    gen_ui()
    applause(2.2, 500, "applause_small.wav", 0.15)
    applause(4.0, 1600, "applause_medium.wav", 0.3)
    applause(6.5, 3200, "applause_big.wav", 0.5)
