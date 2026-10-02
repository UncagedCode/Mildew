#!/usr/bin/env python3
"""
Generates Mildew's Hole illustrations: project-owned, procedurally rendered "product photographs"
of openings (holekit height-field renderer). PROVISIONAL art in the Mildew style; no external imagery.

    python3 tools/art/gen_holes.py              # all
    python3 tools/art/gen_holes.py crumpet ...  # selected
Writes assets/content/hole/<id>.jpg and assets/content/hole/stages.json (suggested reveal crops).
Stage crops are (x, y, zoom) with x/y the normalised crop centre; zoom 1 = whole frame.
"""
import json
import math
import os
import sys

import numpy as np
import cv2

sys.path.insert(0, os.path.dirname(__file__))
from holekit import (W, H, Scene, sstep, disc, ellipse, rrect, polygon_mask, pit, mix, col, fill, render, save)  # noqa: E402

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "content", "hole")
SCENES = {}


def scene(fn):
    SCENES[fn.__name__] = fn
    return fn


def wall_texture(sc, base, scale=60, amount=0.06):
    n = sc.noise(scale, 5)
    alb = fill(base) * (1 + n[..., None] * amount)
    return alb, n


# =============================================================================
# Household
# =============================================================================

@scene
def plug_socket(sc):
    x, y = sc.grid()
    alb, n = wall_texture(sc, col("#d9cfae"), 40, 0.05)  # magnolia wall
    h = n * 1.5
    plate = rrect(x, y, 800, 620, 430, 300, 34)
    plate_m = sstep(2, -2, plate)
    bevel = np.clip(-plate / 26.0, 0, 1)
    h += plate_m * (10 + 16 * np.sqrt(bevel))
    alb = mix(alb, fill(col("#efeadc")) * (1 + sc.noise(8, 2)[..., None] * 0.015), plate_m)
    # three socket slots (UK BS1363 layout): earth vertical on top, live/neutral horizontal below
    slots = [(690, 470, 18, 46), (585, 690, 44, 18), (795, 690, 44, 18)]
    for cx, cy, hw, hh in slots:
        d = rrect(x, y, cx, cy, hw, hh, 3)
        h += pit(d, 320, 2.5, 3)
    # socket recess shading ring around slots
    # rocker switch
    sw = rrect(x, y, 1040, 600, 70, 105, 10)
    sw_m = sstep(2, -2, sw)
    h += sw_m * (16 + 10 * np.clip((y - 500) / 200.0, 0, 1))
    alb = mix(alb, fill(col("#e9e3d2")), sw_m)
    red = sstep(2, -2, rrect(x, y, 1040, 640, 30, 18, 4))
    alb = mix(alb, fill(col("#c4291c")), red)
    # screws
    for cx in (500, 1100):
        d = disc(x, y, cx, 620, 26)
        h += sstep(2, -2, d) * 6
        slot = rrect(x, y, cx, 620, 22, 3.5, 1, angle=0.6 if cx < 800 else -0.3)
        h += pit(slot, 8, 1.2, 2) * sstep(2, -2, d)
        alb = mix(alb, fill(col("#b8b0a0")), sstep(2, -2, d))
    # grime near slots
    grime = sstep(60, 0, np.minimum.reduce([rrect(x, y, cx, cy, hw, hh, 3) for cx, cy, hw, hh in slots])) * 0.18
    alb *= (1 - grime[..., None] * 0.6)
    sc.h, sc.albedo = h, alb
    sc.spec = plate_m * 0.25 + sw_m * 0.2
    sc.gloss = 30
    return [(0.43, 0.39, 5.2), (0.47, 0.5, 2.6), (0.5, 0.52, 1.45)]


@scene
def crumpet(sc):
    x, y = sc.grid()
    # plate
    alb = fill(col("#e8e6df"))
    h = np.zeros((H, W), np.float32)
    pl = disc(x, y, 800, 640, 720)
    h += sstep(4, -4, pl) * 6 + sstep(-60, -110, pl) * -5
    alb = mix(fill(col("#3a2d2a")) * (1 + sc.noise(30, 3)[..., None] * 0.1), alb, sstep(4, -4, pl))  # table
    cr = disc(x, y, 790, 600, 470)
    cm = sstep(6, -6, cr)
    top = np.clip(-cr / 50.0, 0, 1)
    h += cm * (60 + 20 * np.sqrt(top) + sc.noise(40, 3) * 4)
    golden = mix(col("#c98a3a"), col("#e2b46a"), np.clip(0.5 + sc.noise(60, 3) * 0.8, 0, 1))
    # side band paler
    alb = mix(alb, golden * (1 + sc.noise(6, 2)[..., None] * 0.05), cm)
    # crumpet holes: Poisson-ish
    rng = sc.rng
    pts = []
    tries = 0
    while len(pts) < 260 and tries < 20000:
        tries += 1
        a = rng.random() * 2 * math.pi
        rr = 440 * math.sqrt(rng.random())
        px, py = 790 + rr * math.cos(a), 600 + rr * math.sin(a)
        r = rng.uniform(5, 13)
        if all((px - qx) ** 2 + (py - qy) ** 2 > (r + qr + 7) ** 2 for qx, qy, qr in pts):
            pts.append((px, py, r))
    holes = np.zeros((H, W), np.float32)
    for px, py, r in pts:
        x0, x1, y0, y1 = int(px - 20), int(px + 20), int(py - 20), int(py + 20)
        xs, ys = x[y0:y1, x0:x1], y[y0:y1, x0:x1]
        d = np.sqrt((xs - px) ** 2 + (ys - py) ** 2) - r
        holes[y0:y1, x0:x1] = np.minimum(holes[y0:y1, x0:x1], pit(d, 70, 2.0, 4))
    h += holes * cm
    alb = mix(alb, fill(col("#8f5a24")), sstep(-2, -25, holes) * cm * 0.7)
    # butter sheen
    butter = sstep(0.2, 0.7, sc.noise(120, 2)) * cm
    alb = mix(alb, fill(col("#f2d27a")), butter * 0.35)
    sc.h, sc.albedo = h, alb
    sc.spec = cm * (0.15 + butter * 0.5)
    sc.gloss = 25
    sc.deep_start, sc.deep_full = 20, 70
    sc.deep_colour = (0.18, 0.08, 0.02)
    return [(0.56, 0.47, 6.0), (0.53, 0.5, 3.0), (0.5, 0.5, 1.6)]


@scene
def plughole(sc):
    x, y = sc.grid()
    alb = fill(col("#f1f0ec")) * (1 + sc.noise(50, 3)[..., None] * 0.02)
    h = sc.noise(80, 3) * 1.0
    # basin bowl slope toward centre
    rr = np.sqrt((x - 800) ** 2 + (y - 600) ** 2)
    h += -np.clip(rr, 0, 900) * -0.06
    ring = disc(x, y, 800, 600, 190)
    ring_m = sstep(3, -3, ring)
    h += ring_m * 8
    chrome = 0.55 + 0.35 * np.cos((rr / 30.0)) * 0.3 + sc.noise(15, 2) * 0.05
    alb = mix(alb, np.dstack([chrome, chrome, chrome * 1.03]), ring_m)
    # cross slots (radial)
    inner = disc(x, y, 800, 600, 150)
    hole_d = np.full((H, W), 999.0, np.float32)
    ang = np.arctan2(y - 600, x - 800)
    for k in range(6):
        a = k * math.pi / 3 + 0.2
        c, s = math.cos(a), math.sin(a)
        u = (x - 800) * c + (y - 600) * s
        v = -(x - 800) * s + (y - 600) * c
        d = np.maximum(np.abs(v) - 14, np.maximum(40 - u, u - 140))
        hole_d = np.minimum(hole_d, d)
    hole_d = np.minimum(hole_d, disc(x, y, 800, 600, 22))
    h += pit(hole_d, 300, 2, 3)
    # limescale + hair
    scale_m = sstep(0.3, 0.6, sc.noise(25, 3)) * sstep(200, 120, rr) * 0.5
    alb = mix(alb, fill(col("#d6cfb2")), scale_m)
    hair = np.zeros((H, W), np.uint8)
    pts = np.array([[700, 560], [760, 610], [830, 590], [880, 650], [940, 700], [1010, 690]], np.int32)
    cv2.polylines(hair, [pts], False, 255, 2, cv2.LINE_AA)
    hm = hair.astype(np.float32) / 255
    alb = mix(alb, fill(col("#2b1d14")), hm * 0.9)
    # water droplets
    drops = np.zeros((H, W), np.float32)
    for _ in range(40):
        px, py, r = sc.rng.uniform(250, 1350), sc.rng.uniform(150, 1050), sc.rng.uniform(4, 12)
        drops = np.maximum(drops, sstep(2, -2, disc(x, y, px, py, r)) * (1 - ((x - px) ** 2 + (y - py) ** 2) / (r * r + 1)).clip(0, 1))
    h += drops * 2
    sc.h, sc.albedo = h, alb
    sc.spec = ring_m * 0.9 + 0.3 + drops * 0.35
    sc.gloss = 60
    return [(0.53, 0.47, 5.5), (0.5, 0.5, 2.8), (0.5, 0.5, 1.6)]


@scene
def keyhole(sc):
    x, y = sc.grid()
    # painted wooden door, vertical grain
    grain = sc.noise(30, 4, aniso=(0.15, 4.0))
    alb = fill(col("#3f5e4a")) * (1 + grain[..., None] * 0.08)  # dark green gloss paint
    h = grain * 1.2
    # brass escutcheon
    esc = ellipse(x, y, 800, 600, 150, 300)
    em = sstep(2, -2, esc)
    h = h * (1 - em) + em * (12 + 10 * np.sqrt(np.clip(-esc / 40, 0, 1)) + sc.noise(25, 2) * 0.6)
    brass = mix(col("#7a5a22"), col("#d8b25a"), np.clip(0.55 + sc.noise(20, 3) * 0.6, 0, 1))
    alb = mix(alb, brass, em)
    # keyhole: circle + trapezoid
    circ = disc(x, y, 800, 520, 52)
    trap = polygon_mask([(770, 530), (830, 530), (860, 760), (740, 760)], 1.0)
    trap_d = (0.5 - trap) * 20
    kd = np.minimum(circ, trap_d)
    h += pit(kd, 400, 2, 2)
    # light leaking through from the other side (dim)
    sc.emit = (sstep(0, -60, kd) * 0.0)[..., None] * np.array([0.0, 0.0, 0.0], np.float32)
    # scratches around keyhole
    scratch = np.zeros((H, W), np.uint8)
    for _ in range(26):
        a = sc.rng.uniform(0, 2 * math.pi)
        r0 = sc.rng.uniform(70, 140)
        x0, y0 = 800 + r0 * math.cos(a), 600 + r0 * math.sin(a) * 1.6
        x1, y1 = x0 + sc.rng.uniform(-50, 50), y0 + sc.rng.uniform(-30, 30)
        cv2.line(scratch, (int(x0), int(y0)), (int(x1), int(y1)), 255, 1, cv2.LINE_AA)
    sm = scratch.astype(np.float32) / 255 * em
    alb = mix(alb, fill(col("#f3dc9a")), sm * 0.6)
    sc.h, sc.albedo = h, alb
    sc.spec = 0.25 + em * 0.75
    sc.gloss = 45
    return [(0.5, 0.47, 6.0), (0.5, 0.5, 3.0), (0.5, 0.5, 1.7)]


@scene
def pig_snout(sc):
    x, y = sc.grid()
    skin = mix(col("#e7a99a"), col("#f2c2b3"), np.clip(0.5 + sc.noise(70, 3) * 0.7, 0, 1))
    alb = skin * (1 + sc.noise(5, 2)[..., None] * 0.04)
    h = sc.noise(160, 3) * 4
    snout = ellipse(x, y, 800, 640, 470, 360)
    sm = sstep(10, -10, snout)
    dome = np.sqrt(np.clip(-snout / 360.0, 0, 1))
    h += sm * (40 + 80 * dome)
    alb = mix(alb, mix(col("#f0a9a0"), col("#e18f86"), np.clip(0.5 + sc.noise(30, 3) * 0.6, 0, 1)), sm)
    # nostrils
    nl = ellipse(x, y, 640, 650, 70, 120, 0.25)
    nr = ellipse(x, y, 960, 650, 70, 120, -0.25)
    nd = np.minimum(nl, nr)
    h += pit(nd, 300, 4, 6)
    # moist rim
    rim = sstep(18, 0, nd) * sstep(-4, 4, nd)
    alb = mix(alb, fill(col("#d07a74")), rim * 0.6)
    # pores / bristles
    pores = sc.speckle(0.0025, 1.2)
    h -= pores * 3
    bristle = np.zeros((H, W), np.uint8)
    for _ in range(180):
        px, py = sc.rng.uniform(0, W), sc.rng.uniform(0, H)
        if ((px - 800) / 470) ** 2 + ((py - 640) / 360) ** 2 < 1.05:
            continue
        a = sc.rng.uniform(-2.6, -0.5)
        L = sc.rng.uniform(20, 60)
        cv2.line(bristle, (int(px), int(py)), (int(px + L * math.cos(a)), int(py + L * math.sin(a))), 255, 1, cv2.LINE_AA)
    bm = bristle.astype(np.float32) / 255
    alb = mix(alb, fill(col("#f7e9d8")), bm * 0.8)
    # mucus glints near nostrils
    wet = sstep(40, 0, nd) * 0.6 + sm * 0.25
    sc.h, sc.albedo = h, alb
    sc.spec = wet + pores * 0.2
    sc.gloss = 55
    sc.deep_colour = (0.12, 0.03, 0.03)
    return [(0.44, 0.58, 5.5), (0.47, 0.55, 2.7), (0.5, 0.53, 1.5)]


@scene
def lotus_pod(sc):
    x, y = sc.grid()
    alb = fill(col("#1c2a1a")) * (1 + sc.noise(50, 3)[..., None] * 0.2)
    h = np.zeros((H, W), np.float32)
    pod = disc(x, y, 800, 600, 500)
    pm = sstep(6, -6, pod)
    h += pm * (70 + 25 * np.sqrt(np.clip(-pod / 500, 0, 1)) + sc.noise(60, 3) * 5)
    pod_col = mix(col("#7f8a4d"), col("#b5ad6a"), np.clip(0.5 + sc.noise(80, 3) * 0.8, 0, 1))
    alb = mix(alb, pod_col * (1 + sc.noise(4, 2)[..., None] * 0.06), pm)
    # seed holes in rings
    holes = np.zeros((H, W), np.float32)
    seeds = np.zeros((H, W), np.float32)
    rings = [(0, 1), (115, 7), (230, 13), (345, 19), (440, 24)]
    for rr, count in rings:
        for k in range(count):
            a = k * 2 * math.pi / count + rr * 0.01 + sc.rng.uniform(-0.05, 0.05)
            px, py = 800 + rr * math.cos(a), 600 + rr * math.sin(a)
            r = sc.rng.uniform(30, 40)
            d = disc(x, y, px, py, r)
            holes = np.minimum(holes, pit(d, 90, 3, 6))
            if sc.rng.random() < 0.45:
                sr = r * 0.7
                sd = disc(x, y, px + 3, py + 4, sr)
                seeds = np.maximum(seeds, sstep(2, -2, sd) * np.sqrt(np.clip(-sd / sr, 0, 1)))
    h += holes * pm + seeds * 50 - (seeds > 0) * 40
    alb = mix(alb, fill(col("#3f3a1c")), sstep(-5, -40, holes) * pm * 0.6)
    alb = mix(alb, fill(col("#4c5a2a")), np.clip(seeds * 3, 0, 1))
    sc.h, sc.albedo = h, alb
    sc.spec = seeds * 0.6 + pm * 0.08
    sc.gloss = 30
    sc.deep_start, sc.deep_full = 15, 80
    sc.deep_colour = (0.06, 0.05, 0.02)
    return [(0.6, 0.42, 5.0), (0.55, 0.47, 2.6), (0.5, 0.5, 1.5)]


@scene
def shower_head(sc):
    x, y = sc.grid()
    tiles = (np.abs(((x + 20) % 200) - 100) > 96) | (np.abs(((y + 50) % 200) - 100) > 96)
    alb = mix(fill(col("#cfe0dd")), fill(col("#9aa9a5")), tiles.astype(np.float32))
    h = -tiles.astype(np.float32) * 3
    face = disc(x, y, 800, 600, 420)
    fm = sstep(4, -4, face)
    rr = np.sqrt((x - 800) ** 2 + (y - 600) ** 2)
    h += fm * (30 + 14 * np.sqrt(np.clip(-face / 420, 0, 1)))
    chrome = 0.62 + 0.08 * np.cos(rr / 9.0) + sc.noise(40, 2) * 0.05
    alb = mix(alb, np.dstack([chrome, chrome * 1.01, chrome * 1.04]), fm)
    plate = disc(x, y, 800, 600, 310)
    pm = sstep(3, -3, plate)
    alb = mix(alb, fill(col("#d7d9d6")), pm)  # white plastic spray plate
    nubs = np.zeros((H, W), np.float32)
    holes = np.zeros((H, W), np.float32)
    for ring, count in [(0, 1), (60, 8), (120, 14), (180, 20), (240, 26)]:
        for k in range(count):
            a = k * 2 * math.pi / max(1, count) + ring * 0.004
            px, py = 800 + ring * math.cos(a), 600 + ring * math.sin(a)
            nd = disc(x, y, px, py, 17)
            nubs = np.maximum(nubs, sstep(3, -3, nd) * np.sqrt(np.clip(-nd / 17, 0, 1)))
            holes = np.minimum(holes, pit(disc(x, y, px, py, 6), 60, 1.2, 2))
    h += pm * (nubs * 14 + holes)
    alb = mix(alb, fill(col("#3c3f44")), nubs * pm * 0.85)  # black rubber nozzles
    lime = sstep(0.45, 0.7, sc.noise(14, 3)) * pm * (1 - nubs)
    alb = mix(alb, fill(col("#e6dcc0")), lime * 0.6)
    sc.h, sc.albedo = h, alb
    sc.spec = fm * (1 - pm) + pm * 0.25 + 0.1
    sc.gloss = 70
    sc.deep_start, sc.deep_full = 15, 55
    return [(0.6, 0.46, 6.0), (0.56, 0.48, 3.0), (0.5, 0.5, 1.55)]


@scene
def colander(sc):
    x, y = sc.grid()
    alb = fill(col("#c4b49a")) * (1 + sc.noise(10, 2)[..., None] * 0.05)  # worktop
    h = np.zeros((H, W), np.float32)
    bowl = disc(x, y, 800, 600, 520)
    bm = sstep(5, -5, bowl)
    rr = np.sqrt((x - 800) ** 2 + (y - 600) ** 2)
    # inside of bowl seen from above: deep in the middle
    h += bm * (-160 * (1 - (rr / 520.0) ** 2).clip(0, 1) + 40)
    rim = sstep(6, -6, bowl) * sstep(-26, -14, bowl)
    h += rim * 30
    enamel = mix(col("#c94a2c"), col("#e06a43"), np.clip(0.5 + sc.noise(60, 2) * 0.5, 0, 1))
    alb = mix(alb, enamel, bm)
    alb = mix(alb, fill(col("#f2efe7")), rim)
    holes = np.zeros((H, W), np.float32)
    for gy in range(-8, 9):
        for gx in range(-8, 9):
            px = 800 + gx * 44 + (22 if gy % 2 else 0)
            py = 600 + gy * 40
            if (px - 800) ** 2 + (py - 600) ** 2 > 400 ** 2:
                continue
            holes = np.minimum(holes, pit(disc(x, y, px, py, 9), 80, 1.5, 2))
    h += holes * bm
    alb = mix(alb, fill(col("#efe9dc")), sstep(-1, -6, holes) * 0.0)
    chips = sstep(0.55, 0.75, sc.noise(16, 3)) * bm * 0.7
    alb = mix(alb, fill(col("#202020")), chips)
    sc.h, sc.albedo = h, alb
    sc.spec = bm * 0.7
    sc.gloss = 50
    sc.deep_start, sc.deep_full = 30, 100
    sc.deep_colour = (0.42, 0.38, 0.32)  # worktop visible through the holes
    return [(0.42, 0.55, 5.5), (0.47, 0.52, 2.7), (0.5, 0.5, 1.5)]


@scene
def bowling_ball(sc):
    x, y = sc.grid()
    alb = fill(col("#a87a4a")) * (1 + sc.noise(20, 3, aniso=(6, 0.2))[..., None] * 0.12)  # lane wood
    h = np.zeros((H, W), np.float32)
    ball = disc(x, y, 800, 610, 520)
    bm = sstep(3, -3, ball)
    rr2 = ((x - 800) ** 2 + (y - 610) ** 2) / 520.0 ** 2
    h += bm * 520 * np.sqrt(np.clip(1 - rr2, 0, 1)) * 0.6
    swirl = sc.noise(90, 4) + 0.5 * np.sin((x * 0.006 + y * 0.004) + sc.noise(120, 2) * 3)
    marble = mix(col("#14204d"), col("#6f2e8a"), np.clip(0.5 + swirl * 0.6, 0, 1))
    marble = mix(marble, col("#d8d0ff"), sstep(0.75, 0.95, swirl) * 0.5)
    alb = mix(alb, marble, bm)
    holes = np.zeros((H, W), np.float32)
    for px, py, r in [(700, 470, 46), (900, 470, 46), (800, 680, 54)]:
        holes = np.minimum(holes, pit(disc(x, y, px, py, r), 400, 3, 10))
        h += sstep(6, 0, disc(x, y, px, py, r + 6)) * 0
    h += holes * bm
    sc.h, sc.albedo = h, alb
    sc.spec = bm * 1.0 + 0.05
    sc.gloss = 120
    sc.bump = 1.0
    return [(0.5, 0.39, 5.5), (0.5, 0.45, 2.8), (0.5, 0.5, 1.5)]


@scene
def button(sc):
    x, y = sc.grid()
    # tweed: two woven noises
    weave = np.sin(x * 0.45) * np.sin(y * 0.45)
    tw = sc.noise(14, 3)
    alb = mix(col("#5a4b3a"), col("#8f7a5c"), np.clip(0.5 + tw * 0.8 + weave * 0.15, 0, 1))
    flecks = sc.speckle(0.004, 1.0)
    alb = mix(alb, fill(col("#b03a2a")), np.clip(flecks * 1.5, 0, 1) * 0.6)
    h = (tw * 3 + weave * 1.5).astype(np.float32)
    b = disc(x, y, 800, 600, 330)
    bm = sstep(3, -3, b)
    rr = np.sqrt((x - 800) ** 2 + (y - 600) ** 2)
    profile = np.where(rr < 250, 30 - 8 * (1 - rr / 250.0) ** 2, 30 + 12 * np.sqrt(np.clip((330 - rr) / 80.0, 0, 1)))
    h = h * (1 - bm) + bm * profile
    alb = mix(alb, mix(col("#2e5a4f"), col("#3f7a6a"), np.clip(0.5 + sc.noise(50, 2) * 0.5, 0, 1)), bm)
    holes = np.zeros((H, W), np.float32)
    for px, py in [(735, 535), (865, 535), (735, 665), (865, 665)]:
        holes = np.minimum(holes, pit(disc(x, y, px, py, 34), 200, 2, 6))
    h += holes * bm
    # thread crossing between holes
    thread = np.zeros((H, W), np.uint8)
    for (a, b2) in [((735, 535), (865, 665)), ((865, 535), (735, 665))]:
        cv2.line(thread, a, b2, 255, 14, cv2.LINE_AA)
    tm = thread.astype(np.float32) / 255 * sstep(2, -2, b) * sstep(-2, 6, holes)
    h += tm * 12
    alb = mix(alb, fill(col("#e9e1cc")), tm)
    sc.h, sc.albedo = h, alb
    sc.spec = bm * 0.6
    sc.gloss = 60
    sc.deep_colour = (0.18, 0.14, 0.1)
    sc.deep_start, sc.deep_full = 20, 120
    return [(0.53, 0.45, 6.0), (0.5, 0.48, 3.2), (0.5, 0.5, 1.7)]


@scene
def golf_hole(sc):
    x, y = sc.grid()
    blades = sc.noise(3, 2)
    stripe = 0.5 + 0.5 * np.sign(np.sin((x * 0.6 + y) * 0.01))
    grass = mix(col("#3d7a2d"), col("#5c9c3f"), np.clip(0.45 + blades * 0.5 + stripe * 0.12, 0, 1))
    alb = grass
    h = blades * 3 + sc.noise(200, 2) * 20
    cup = ellipse(x, y, 820, 640, 230, 150)
    h += pit(cup, 700, 3, 4)
    liner = sstep(0, -14, cup) * sstep(-34, -14, cup)
    alb = mix(alb, fill(col("#f4f4f0")), liner)
    h += liner * -20
    # flagpole shadow suggestion: the pole itself is out of frame top-right; a ball rests near the hole
    ball = disc(x, y, 1180, 900, 70)
    bmask = sstep(2, -2, ball)
    dimples = (np.sin(x * 0.35) * np.sin(y * 0.35)) * 2
    h += bmask * (70 * np.sqrt(np.clip(-ball / 70, 0, 1)) + dimples)
    alb = mix(alb, fill(col("#fbfbf6")), bmask)
    sc.h, sc.albedo = h, alb
    sc.spec = bmask * 0.5 + liner * 0.3
    sc.gloss = 40
    sc.deep_start, sc.deep_full = 260, 700
    return [(0.6, 0.58, 5.0), (0.55, 0.55, 2.5), (0.55, 0.57, 1.45)]


@scene
def swiss_cheese(sc):
    x, y = sc.grid()
    alb = fill(col("#6b4a35")) * (1 + sc.noise(30, 3, aniso=(4, 0.3))[..., None] * 0.15)  # board
    h = np.zeros((H, W), np.float32)
    wedge = polygon_mask([(180, 1050), (1450, 1080), (1300, 180), (520, 260)], 3)
    h += wedge * 90
    cheese = mix(col("#f1d47a"), col("#e8c25a"), np.clip(0.5 + sc.noise(70, 3) * 0.6, 0, 1))
    alb = mix(alb, cheese, wedge)
    holes = np.zeros((H, W), np.float32)
    for _ in range(26):
        px, py = sc.rng.uniform(300, 1350), sc.rng.uniform(300, 1020)
        r = sc.rng.uniform(25, 85)
        holes = np.minimum(holes, -80 * np.sqrt(np.clip(1 - ((x - px) ** 2 + (y - py) ** 2) / (r * r), 0, 1)))
    h += holes * wedge
    alb = mix(alb, fill(col("#f7e2a0")), sstep(-5, -60, holes) * wedge * 0.4)
    sc.h, sc.albedo = h, alb
    sc.spec = wedge * 0.35
    sc.gloss = 20
    sc.deep_start, sc.deep_full = 200, 400
    return [(0.47, 0.6, 5.0), (0.5, 0.55, 2.6), (0.5, 0.52, 1.4)]


@scene
def rabbit_burrow(sc):
    x, y = sc.grid()
    soil = mix(col("#5a3e26"), col("#8a6440"), np.clip(0.5 + sc.noise(25, 4) * 0.7, 0, 1))
    pebbles = sc.speckle(0.0015, 2.5)
    alb = mix(soil, fill(col("#b8ad98")), np.clip(pebbles * 1.5, 0, 1))
    h = sc.noise(60, 4) * 25 + pebbles * 6 + (H - y) * 0.15
    # grass fringe at the top
    grass_m = sstep(380, 300, y + sc.noise(30, 3) * 60)
    alb = mix(alb, mix(col("#3c6b28"), col("#6d9a3c"), np.clip(0.5 + sc.noise(4, 2) * 0.8, 0, 1)), grass_m)
    h += grass_m * (30 + sc.noise(3, 2) * 12)
    burrow = ellipse(x, y, 820, 700, 270, 210)
    h += pit(burrow + sc.noise(20, 2) * 10, 900, 10, 70)
    # spoil heap in front
    heap = ellipse(x, y, 820, 1020, 420, 150)
    h += sstep(30, -60, heap) * 40
    sc.h, sc.albedo = h, alb
    sc.spec = grass_m * 0.1
    sc.deep_start, sc.deep_full = 60, 500
    sc.deep_colour = (0.03, 0.02, 0.01)
    return [(0.39, 0.55, 5.0), (0.46, 0.57, 2.5), (0.5, 0.55, 1.4)]


@scene
def manhole(sc):
    x, y = sc.grid()
    tar = mix(col("#2f2f31"), col("#4a4a4c"), np.clip(0.5 + sc.noise(4, 2) * 0.9, 0, 1))
    alb = tar
    h = sc.noise(3, 2) * 2 + sc.noise(150, 2) * 6
    frame = rrect(x, y, 800, 600, 380, 380, 10)
    fm = sstep(2, -2, frame)
    h += fm * 6
    alb = mix(alb, mix(col("#4b3b2e"), col("#6b513a"), np.clip(0.5 + sc.noise(10, 3), 0, 1)), fm)  # rusty iron
    opening = rrect(x, y, 800, 600, 300, 300, 6)
    h += pit(opening, 1200, 3, 4)
    # ladder rungs on the far wall
    for k in range(5):
        ry = 330 + k * 120
        rung = rrect(x, y, 800, ry, 150, 9, 6)
        rm = sstep(2, -2, rung) * sstep(2, -2, opening)
        h = np.where(rm > 0.5, np.maximum(h, -200.0 - k * 160), h)
        alb = mix(alb, fill(col("#7d5236")), rm)
    # displaced cover at the side
    cover = disc(x, y, 1380, 1000, 360)
    cm = sstep(2, -2, cover)
    pattern = (np.sin(x * 0.12) > 0.6) | (np.sin(y * 0.12) > 0.6)
    h += cm * (14 + pattern * 4)
    alb = mix(alb, fill(col("#3a3532")), cm)
    puddle = sstep(0.4, 0.55, sc.noise(80, 2)) * (1 - fm) * (1 - cm)
    sc.h, sc.albedo = h, alb
    sc.spec = puddle * 0.8 + fm * 0.15
    sc.gloss = 80
    sc.deep_start, sc.deep_full = 80, 900
    return [(0.39, 0.3, 4.5), (0.45, 0.4, 2.2), (0.55, 0.55, 1.35)]


@scene
def trumpet_bell(sc):
    x, y = sc.grid()
    alb = fill(col("#5b1324")) * (1 + sc.noise(6, 2)[..., None] * 0.06)  # velvet case lining
    h = sc.noise(6, 2) * 2
    rr = np.sqrt((x - 800) ** 2 + (y - 600) ** 2)
    bell = rr - 480
    bmask = sstep(3, -3, bell)
    # flare: height rises toward the rim then plunges into the throat (exponential horn)
    throat = 60.0
    prof = 40 - 900 * np.exp(-(rr - throat) / 110.0)
    h = h * (1 - bmask) + bmask * np.maximum(prof, -1500)
    brass = mix(col("#b07a2a"), col("#f0cf7a"), np.clip(0.5 + 0.5 * np.cos(rr / 60.0) * 0.4 + sc.noise(70, 2) * 0.3, 0, 1))
    alb = mix(alb, brass, bmask)
    tarnish = sstep(0.4, 0.7, sc.noise(40, 3)) * bmask * 0.4
    alb = mix(alb, fill(col("#4f5a3a")), tarnish)
    sc.h, sc.albedo = h, alb
    sc.spec = bmask * 0.9
    sc.gloss = 35
    sc.bump = 0.6
    sc.deep_start, sc.deep_full = 300, 1300
    return [(0.62, 0.42, 5.0), (0.56, 0.47, 2.5), (0.5, 0.5, 1.45)]


@scene
def woodpecker_tree(sc):
    x, y = sc.grid()
    bark_n = sc.noise(26, 4, aniso=(0.25, 3.0))
    ridges = np.abs(np.sin(x * 0.03 + bark_n * 3))
    alb = mix(col("#6d5c4a"), col("#b3a38a"), np.clip(ridges * 0.8 + bark_n * 0.3, 0, 1))
    lichen = sstep(0.45, 0.7, sc.noise(40, 3))
    alb = mix(alb, fill(col("#9fae6a")), lichen * 0.6)
    h = ridges * 40 + bark_n * 20
    holes = np.zeros((H, W), np.float32)
    for row in range(4):
        for k in range(7):
            px = 330 + k * 150 + sc.rng.uniform(-20, 20)
            py = 280 + row * 200 + sc.rng.uniform(-20, 20)
            r = sc.rng.uniform(22, 34)
            holes = np.minimum(holes, pit(ellipse(x, y, px, py, r, r * 1.15) + sc.noise(5, 1) * 3, 300, 2, 6))
    h += holes
    pale = sstep(14, 0, holes * 0 + np.where(holes < -1, 0, 30))
    alb = mix(alb, fill(col("#c9a77a")), sstep(-1, -20, holes) * 0.5)
    sc.h, sc.albedo = h, alb
    sc.spec = np.zeros((H, W), np.float32) + 0.05
    sc.deep_start, sc.deep_full = 40, 250
    return [(0.3, 0.42, 5.0), (0.4, 0.45, 2.4), (0.5, 0.5, 1.4)]


@scene
def volcano_crater(sc):
    x, y = sc.grid()
    rr = np.sqrt((x - 760) ** 2 + ((y - 620) * 1.15) ** 2)
    n = sc.noise(70, 5)
    cone = 300 * np.exp(-((rr - 330) / 260.0) ** 2) - np.where(rr < 330, (330 - rr) * 2.2, 0)
    h = cone + n * 40 + sc.noise(12, 3) * 8
    rock = mix(col("#4b3b33"), col("#8a7461"), np.clip(0.5 + n * 0.7, 0, 1))
    ash = sstep(200, 600, rr)
    alb = mix(rock, fill(col("#9a8f80")), ash * 0.5)
    # sulphur streaks inside
    sulph = sstep(0.4, 0.75, sc.noise(30, 3)) * sstep(330, 250, rr)
    alb = mix(alb, fill(col("#d9c35a")), sulph * 0.6)
    # faint glow at the bottom
    glow = sstep(140, 0, rr)
    sc.emit = (glow * 0.35)[..., None] * np.array([1.0, 0.35, 0.08], np.float32)
    sc.h, sc.albedo = h, alb
    sc.light = (-0.7, -0.4, 0.5)
    sc.deep_start, sc.deep_full = 200, 700
    sc.deep_colour = (0.06, 0.03, 0.02)
    sc.shadow_soft = 20
    return [(0.33, 0.47, 4.5), (0.42, 0.5, 2.2), (0.48, 0.52, 1.3)]


@scene
def rotary_dial(sc):
    x, y = sc.grid()
    body = fill(col("#a0201f")) * (1 + sc.noise(40, 2)[..., None] * 0.03)  # red GPO-style phone body
    h = np.zeros((H, W), np.float32) + 20
    alb = body
    # number plate underneath (white with digits) and the finger wheel on top
    plate = disc(x, y, 800, 600, 470)
    pm = sstep(2, -2, plate)
    alb = mix(alb, fill(col("#f2efe6")), pm)
    h += pm * 10
    wheel = disc(x, y, 800, 600, 450)
    wm = sstep(2, -2, wheel)
    h += wm * 30
    alb = mix(alb, fill(col("#e9e5dc")) * 0.98, wm)
    centre = disc(x, y, 800, 600, 150)
    cm = sstep(2, -2, centre)
    alb = mix(alb, fill(col("#dcd4c0")), cm)
    h += cm * 6
    holes = np.zeros((H, W), np.float32)
    digits = np.zeros((H, W), np.uint8)
    for k in range(10):
        a = math.radians(-60 - k * 30)  # 1 at top-right going anticlockwise
        px, py = 800 + 345 * math.cos(a), 600 - 345 * math.sin(a)
        d = disc(x, y, px, py, 58)
        holes = np.minimum(holes, pit(d, 40, 2, 4))
        label = str((k + 1) % 10)
        cv2.putText(digits, label, (int(px - 18), int(py + 18)), cv2.FONT_HERSHEY_SIMPLEX, 1.6, 255, 4, cv2.LINE_AA)
    h += holes * wm
    dm = digits.astype(np.float32) / 255 * sstep(-2, -8, holes)
    alb = mix(alb, fill(col("#1b1b1b")), dm)
    # finger stop
    stop = polygon_mask([(1180, 820), (1250, 760), (1290, 800), (1215, 870)], 1.5)
    h += stop * 40
    alb = mix(alb, fill(col("#c8c8c8")), stop)
    sc.h, sc.albedo = h, alb
    sc.spec = wm * 0.5 + (1 - pm) * 0.6 + stop * 0.8
    sc.gloss = 60
    sc.deep_start, sc.deep_full = 400, 800  # holes are shallow: you see the digits
    return [(0.69, 0.33, 5.0), (0.62, 0.42, 2.5), (0.5, 0.5, 1.4)]


@scene
def belly_button(sc):
    x, y = sc.grid()
    tone = mix(col("#cf9478"), col("#e8b497"), np.clip(0.5 + sc.noise(160, 3) * 0.4, 0, 1))
    alb = tone * (1 + sc.noise(3, 2)[..., None] * 0.02)
    # a soft rounded belly: broad dome lit from the upper left
    h = 260 * np.exp(-(((x - 800) / 900.0) ** 2 + ((y - 560) / 800.0) ** 2)) + sc.noise(220, 2) * 6
    navel = ellipse(x, y, 800, 610, 95, 150, 0.04)
    h += pit(navel + sc.noise(40, 2) * 6, 150, 20, 90)
    # upper fold overhangs the navel
    fold = ellipse(x, y, 800, 520, 170, 70)
    h += sstep(20, -40, fold) * 34
    crease = ellipse(x, y, 800, 610, 150, 205)
    hairs = np.zeros((H, W), np.uint8)
    for _ in range(90):
        px, py = sc.rng.normal(800, 45), sc.rng.uniform(780, 1220)
        L = sc.rng.uniform(25, 55)
        a = sc.rng.normal(0, 0.45)
        cv2.line(hairs, (int(px), int(py)), (int(px + L * math.sin(a)), int(py - L * math.cos(a))), 255, 1, cv2.LINE_AA)
    alb = mix(alb, fill(col("#3b2618")), hairs.astype(np.float32) / 255 * 0.8)
    fluff = sstep(0.35, 0.6, sc.noise(7, 2)) * sstep(-40, -110, navel * 0 + h - 200) * sstep(0, -50, navel)
    alb = mix(alb, fill(col("#5d7ab0")), np.clip(fluff, 0, 1) * 0.5)  # blue jumper fluff, naturally
    sc.h, sc.albedo = h, alb
    sc.spec = 0.16 + sc.speckle(0.0006, 1.5) * 0.3
    sc.gloss = 22
    sc.deep_start, sc.deep_full = 60, 160
    sc.deep_colour = (0.22, 0.09, 0.06)
    sc.shadow_soft = 10
    return [(0.52, 0.47, 5.5), (0.5, 0.5, 2.7), (0.5, 0.52, 1.5)]


@scene
def ear(sc):
    x, y = sc.grid()
    skin = mix(col("#d79a82"), col("#efbea4"), np.clip(0.5 + sc.noise(90, 3) * 0.5, 0, 1))
    alb = skin * (1 + sc.noise(5, 2)[..., None] * 0.03)
    h = sc.noise(150, 2) * 10
    outer = ellipse(x, y, 820, 600, 400, 540)
    om = sstep(10, -10, outer)
    h += om * 60
    # helix rim
    helix = sstep(20, -10, outer) * sstep(-80, -40, outer)
    h += helix * 50
    # concha bowl and canal
    concha = ellipse(x, y, 800, 650, 210, 250)
    h += sstep(30, -60, concha) * -90
    canal = ellipse(x, y, 720, 640, 60, 80, 0.4)
    h += pit(canal, 600, 6, 30)
    tragus = ellipse(x, y, 600, 680, 70, 90)
    h += sstep(10, -20, tragus) * 70
    wax = sstep(10, -30, canal) * sstep(-60, -20, canal) * sstep(0.2, 0.5, sc.noise(10, 2))
    alb = mix(alb, fill(col("#b88a2a")), wax * 0.9)
    alb = mix(fill(col("#3a2a22")) * (1 + sc.noise(4, 2)[..., None] * 0.2), alb, om)  # hair behind
    sc.h, sc.albedo = h, alb
    sc.spec = om * 0.2 + wax * 0.7
    sc.gloss = 35
    sc.deep_start, sc.deep_full = 120, 500
    sc.deep_colour = (0.15, 0.05, 0.03)
    return [(0.44, 0.52, 5.5), (0.47, 0.53, 2.6), (0.5, 0.52, 1.4)]


@scene
def whale_blowhole(sc):
    x, y = sc.grid()
    skin = mix(col("#4a5560"), col("#6b7782"), np.clip(0.5 + sc.noise(120, 3) * 0.6, 0, 1))
    scars = sstep(0.82, 0.9, np.abs(sc.noise(30, 2, aniso=(3, 0.3))))
    alb = mix(skin, fill(col("#c6ccd0")), scars * 0.25)
    barnacle = sc.speckle(0.00012, 7)
    alb = mix(alb, fill(col("#d8d4c4")), np.clip(barnacle * 0.8, 0, 1))
    h = sc.noise(200, 2) * 30 + barnacle * 5 - ((x - 800) ** 2) * 0.0003
    # paired slits (baleen whale)
    for cx, ang in [(720, 0.35), (880, -0.35)]:
        sl = ellipse(x, y, cx, 600, 40, 190, ang)
        h += pit(sl, 400, 8, 20)
        h += sstep(40, 10, sl) * 18
    wet = 0.45 + 0.15 * sc.noise(60, 2)
    sc.h, sc.albedo = h, alb
    sc.spec = np.clip(wet, 0, 1)
    sc.gloss = 30
    sc.deep_colour = (0.08, 0.02, 0.03)
    sc.light = (-0.4, -0.7, 0.5)
    return [(0.45, 0.42, 5.0), (0.47, 0.47, 2.5), (0.5, 0.5, 1.4)]


@scene
def pepper_shaker(sc):
    x, y = sc.grid()
    cloth = (np.abs(((x // 80) + (y // 80)) % 2)).astype(np.float32)
    alb = mix(col("#f2eee6"), col("#c33a32"), cloth)  # gingham tablecloth
    h = sc.noise(4, 2) * 1.5
    top = disc(x, y, 800, 600, 380)
    tm = sstep(3, -3, top)
    rr = np.sqrt((x - 800) ** 2 + (y - 600) ** 2)
    h += tm * (60 + 30 * np.sqrt(np.clip(1 - (rr / 380) ** 2, 0, 1)))
    chrome = 0.62 + 0.2 * np.cos(rr / 16.0) * 0.2 + sc.noise(30, 2) * 0.05
    alb = mix(alb, np.dstack([chrome, chrome, chrome * 1.03]), tm)
    holes = np.zeros((H, W), np.float32)
    for k, (px, py) in enumerate([(800, 600), (720, 540), (880, 540), (720, 660), (880, 660), (800, 480), (800, 720), (680, 600), (920, 600)]):
        holes = np.minimum(holes, pit(disc(x, y, px, py, 16), 300, 1.5, 2))
    h += holes * tm
    pepper = sc.speckle(0.00025, 1.4) * tm * sstep(160, 40, np.sqrt((x - 800) ** 2 + (y - 600) ** 2))
    alb = mix(alb, fill(col("#2a2420")), np.clip(pepper * 2, 0, 1))
    sc.h, sc.albedo = h, alb
    sc.spec = tm * 1.0
    sc.gloss = 90
    return [(0.47, 0.47, 6.0), (0.5, 0.5, 3.0), (0.5, 0.5, 1.6)]


@scene
def cave_entrance(sc):
    x, y = sc.grid()
    n = sc.noise(80, 5)
    strata = np.sin((y + n * 80) * 0.03)
    rock = mix(col("#6e6a62"), col("#a39d8f"), np.clip(0.5 + n * 0.5 + strata * 0.2, 0, 1))
    alb = rock
    h = n * 70 + strata * 15 + sc.noise(18, 2) * 4
    mouth = ellipse(x, y, 820, 760, 360, 300) + sc.noise(40, 3) * 40
    h += pit(mouth, 1500, 20, 200)
    moss = sstep(0.2, 0.6, sc.noise(30, 3)) * sstep(-30, 120, mouth) * sstep(400, 0, mouth)
    alb = mix(alb, fill(col("#4c6b2a")), moss * 0.8)
    drip = sstep(0.6, 0.8, sc.noise(8, 2, aniso=(0.2, 4)))
    alb *= (1 - drip[..., None] * 0.25)
    sc.h, sc.albedo = h, alb
    sc.spec = drip * 0.3
    sc.light = (-0.3, -0.75, 0.55)
    sc.deep_start, sc.deep_full = 200, 1300
    return [(0.33, 0.55, 4.5), (0.42, 0.58, 2.2), (0.5, 0.58, 1.3)]


@scene
def sea_sponge(sc):
    x, y = sc.grid()
    alb = fill(col("#2a6f8a")) * (1 + sc.noise(100, 3)[..., None] * 0.15)  # aquarium blue
    h = np.zeros((H, W), np.float32)
    body = ellipse(x, y, 800, 640, 520, 440) + sc.noise(80, 3) * 50
    bm = sstep(10, -10, body)
    pores = sc.noise(6, 3)
    h += bm * (90 + pores * 12)
    alb = mix(alb, mix(col("#c9933a"), col("#e8bd6a"), np.clip(0.5 + sc.noise(40, 3) * 0.6, 0, 1)), bm)
    small = sstep(-0.2, -0.5, pores) * bm
    h -= small * 30
    holes = np.zeros((H, W), np.float32)
    for px, py, r in [(800, 560, 70), (610, 700, 45), (990, 690, 50), (700, 430, 30), (930, 450, 34)]:
        holes = np.minimum(holes, pit(disc(x, y, px, py, r) + sc.noise(10, 2) * 6, 400, 4, 20))
    h += holes * bm
    sc.h, sc.albedo = h, alb
    sc.spec = bm * 0.15
    sc.deep_start, sc.deep_full = 60, 300
    sc.deep_colour = (0.12, 0.06, 0.02)
    return [(0.55, 0.46, 5.0), (0.52, 0.5, 2.5), (0.5, 0.52, 1.4)]


@scene
def drain_outfall(sc):
    x, y = sc.grid()
    con = mix(col("#7c7a72"), col("#a3a092"), np.clip(0.5 + sc.noise(30, 4) * 0.6, 0, 1))
    alb = con
    h = sc.noise(6, 3) * 4 + sc.noise(60, 3) * 8
    pipe = disc(x, y, 790, 560, 330)
    lip = sstep(4, -4, pipe) * sstep(-60, -50, pipe)
    h += sstep(4, -4, pipe) * 40
    alb = mix(alb, fill(col("#8a8478")), sstep(4, -4, pipe))
    h += pit(disc(x, y, 790, 560, 270), 1200, 4, 60)
    slime = sstep(0.0, 0.5, sc.noise(20, 3)) * sstep(-280, -200, -(y - 560)) * sstep(400, 0, np.abs(x - 790))
    streak = sstep(0.3, 0.6, sc.noise(10, 3, aniso=(0.15, 5))) * sstep(560, 800, y) * sstep(240, 0, np.abs(x - 790))
    alb = mix(alb, fill(col("#3f5a1e")), np.clip(slime * 0.5 + streak * 0.9, 0, 1))
    rust = sstep(0.5, 0.8, sc.noise(15, 3)) * 0.5
    alb = mix(alb, fill(col("#7a4a22")), rust)
    sc.h, sc.albedo = h, alb
    sc.spec = streak * 0.9 + slime * 0.4
    sc.gloss = 50
    sc.deep_start, sc.deep_full = 80, 900
    sc.deep_colour = (0.02, 0.03, 0.01)
    return [(0.3, 0.47, 4.5), (0.4, 0.47, 2.3), (0.5, 0.5, 1.35)]


@scene
def studio_hatch(sc):
    """STUDIO HOLE (rare): a service hatch in the Mildew studio's own purple MDF flats."""
    x, y = sc.grid()
    paint = mix(col("#4b1f6e"), col("#6a2d93"), np.clip(0.5 + sc.noise(90, 3) * 0.5, 0, 1))
    alb = paint * (1 + sc.noise(5, 2)[..., None] * 0.03)
    h = sc.noise(80, 2) * 3
    seam = (np.abs((x % 400) - 200) > 197).astype(np.float32)
    h -= seam * 4
    alb = mix(alb, fill(col("#2a1040")), seam * 0.6)
    # grey metal hatch frame
    outer = rrect(x, y, 780, 640, 290, 270, 8)
    inner = rrect(x, y, 780, 640, 250, 230, 4)
    frame = sstep(2, -2, outer) * sstep(-2, 2, inner)
    h += frame * 14
    alb = mix(alb, fill(col("#6c6c70")) * (1 + sc.noise(6, 2)[..., None] * 0.08), frame)
    # the hatch door: swung slightly inward on its left hinge, leaving a dark wedge on the right
    door = rrect(x, y, 760, 640, 230, 228, 3)
    dm = sstep(2, -2, door)
    h += dm * (2 - np.clip((x - 530) / 460.0, 0, 1) * 25)
    alb = mix(alb, fill(col("#55247a")), dm)
    gap = polygon_mask([(990, 412), (1030, 412), (1030, 868), (990, 868)], 1.0)
    h += pit((0.5 - gap) * 10, 900, 1, 2)
    handle = sstep(2, -2, rrect(x, y, 940, 640, 10, 50, 5))
    h += handle * 12
    alb = mix(alb, fill(col("#9a9a9a")), handle)
    # gaffer tape label
    tape = sstep(2, -2, rrect(x, y, 700, 470, 120, 26, 2, angle=-0.05))
    alb = mix(alb, fill(col("#d8d2c0")), tape)
    txt = np.zeros((H, W), np.uint8)
    cv2.putText(txt, "DO NOT", (602, 486), cv2.FONT_HERSHEY_SIMPLEX, 1.35, 255, 4, cv2.LINE_AA)
    alb = mix(alb, fill(col("#141414")), txt.astype(np.float32) / 255 * tape)
    h += tape * 2
    scuffs = sstep(0.6, 0.8, sc.noise(12, 3)) * sstep(900, 1100, y)
    alb = mix(alb, fill(col("#2c1440")), scuffs * 0.5)
    sc.h, sc.albedo = h, alb
    sc.spec = tape * 0.2 + frame * 0.4 + 0.06
    sc.deep_start, sc.deep_full = 40, 600
    return [(0.63, 0.55, 5.0), (0.56, 0.53, 2.4), (0.5, 0.53, 1.35)]


@scene
def leaf_stoma(sc):
    """A leaf pore under a cheap school microscope: tiny, but it fills the frame (Scale-round bait)."""
    x, y = sc.grid()
    cells = sc.noise(70, 2)
    # jigsaw epidermal cells: thin dark walls from a warped Voronoi-ish pattern
    warp = sc.noise(120, 2) * 60
    wall = np.abs(np.sin((x + warp) * 0.018) * np.sin((y - warp) * 0.022))
    walls = sstep(0.08, 0.0, wall)
    alb = mix(col("#7fb35a"), col("#a6d07a"), np.clip(0.5 + cells * 0.5, 0, 1))
    alb = mix(alb, fill(col("#3e6b2a")), walls * 0.8)
    h = cells * 6 - walls * 8
    # guard cells: two kidney shapes around a slit
    for side in (-1, 1):
        g = ellipse(x, y, 800 + side * 95, 600, 120, 230)
        gm = sstep(6, -6, g)
        h += gm * 50 * np.sqrt(np.clip(-g / 120, 0, 1))
        alb = mix(alb, mix(col("#4f8f34"), col("#79b553"), np.clip(0.5 + sc.noise(20, 2) * 0.6, 0, 1)), gm)
        chloro = sc.speckle(0.0012, 7) * gm
        alb = mix(alb, fill(col("#2f6a1e")), np.clip(chloro * 1.4, 0, 1))
    slit = ellipse(x, y, 800, 600, 30, 170)
    h += pit(slit, 300, 4, 10)
    # microscope: circular field stop, slight colour fringe
    rr = np.sqrt((x - 800) ** 2 + (y - 600) ** 2)
    field = sstep(600, 560, rr)
    sc.h, sc.albedo = h, alb
    sc.spec = 0.25 * field
    sc.gloss = 20
    sc.light = (-0.3, -0.4, 0.86)
    sc.ambient = 0.55
    sc.tint = (0.95, 1.0, 0.92)
    sc.deep_colour = (0.05, 0.12, 0.03)
    sc.emit = None
    sc.field = field
    return [(0.5, 0.42, 5.0), (0.5, 0.48, 2.5), (0.5, 0.5, 1.4)]


def run(names):
    os.makedirs(OUT, exist_ok=True)
    stages_path = os.path.join(OUT, "stages.json")
    stages = {}
    if os.path.exists(stages_path):
        stages = json.load(open(stages_path))
    for i, name in enumerate(sorted(SCENES)):
        if names and name not in names:
            continue
        sc = Scene(1998 + i * 31)
        st = SCENES[name](sc)
        img = render(sc)
        field = getattr(sc, "field", None)
        if field is not None:  # microscope field stop
            img = (img.astype(np.float32) * field[..., None]).astype(np.uint8)
        save(img, os.path.join(OUT, name + ".jpg"))
        imp = os.path.join(OUT, name + ".jpg.import")
        if not os.path.exists(imp):  # lossy WebP in the pack keeps the APK small (~0.3 MB/image)
            open(imp, "w").write('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n\ncompress/mode=1\ncompress/lossy_quality=0.85\nmipmaps/generate=false\n')
        stages[name] = [{"x": a, "y": b, "zoom": z} for a, b, z in st]
        print("rendered", name)
    json.dump(stages, open(stages_path, "w"), indent=1, sort_keys=True)


if __name__ == "__main__":
    run(set(sys.argv[1:]))
