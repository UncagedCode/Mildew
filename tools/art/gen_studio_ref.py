#!/usr/bin/env python3
"""
Studio C textures after the Graham reference video (references/graham/graham_reference_performance_v1.mp4):
sponge-painted sage-green flats, the rectangular MILDEW sign (heavy soft-serif lettering, orange swoosh),
a painted blue back wall and a navy 1990s carpet with coloured rings. Owned, reproducible, no branding.

    python3 tools/art/gen_studio_ref.py          -> assets/textures/studio/*.png

Font: Fraunces (SIL OFL 1.1, tools/art/fonts/OFL-Fraunces.txt) at Black / Softness 100, the closest
open-licence match to the reference's Cooper-style lettering. The font is only used here, at build time.
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "textures", "studio")
FONT = os.path.join(ROOT, "tools", "art", "fonts", "Fraunces-Variable.ttf")
RNG = np.random.default_rng(1998)


def fbm(w, h, octaves=6, base=8, seed=0, tile=True):
    """Tileable value-noise fBm in [0,1]."""
    rng = np.random.default_rng(seed)
    out = np.zeros((h, w), np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        n = base * (2 ** o)
        g = rng.random((n, n)).astype(np.float32)
        if tile:
            g = np.pad(g, ((0, 1), (0, 1)), mode="wrap")
        else:
            g = np.pad(g, ((0, 1), (0, 1)), mode="edge")
        img = Image.fromarray((g * 255).astype(np.uint8)).resize((w + w // n, h + h // n), Image.BICUBIC)
        a = np.asarray(img, np.float32)[:h, :w] / 255.0
        out += a * amp
        tot += amp
        amp *= 0.55
    return out / tot


def sponge(w, h, c_lo, c_hi, seed, blotch=0.35):
    """Sponge-painted wall: two-tone dabs plus fine speckle (very 1990s set painting)."""
    n1 = fbm(w, h, 6, 6, seed)
    n2 = fbm(w, h, 4, 24, seed + 7)
    t = np.clip((n1 - 0.5) * 2.2 + 0.5 + (n2 - 0.5) * blotch, 0, 1)[..., None]
    lo, hi = np.array(c_lo, np.float32), np.array(c_hi, np.float32)
    img = lo * (1 - t) + hi * t
    speck = (RNG.random((h, w, 1)) - 0.5) * 10
    return np.clip(img + speck, 0, 255).astype(np.uint8)


def save(name, arr):
    os.makedirs(OUT, exist_ok=True)
    im = arr if isinstance(arr, Image.Image) else Image.fromarray(arr)
    im.save(os.path.join(OUT, name), optimize=True)


def sign_face():
    W, H = 2048, 720
    base = Image.fromarray(sponge(W, H, (96, 128, 82), (150, 172, 118), 11, 0.5)).convert("RGBA")
    # subtle vertical light falloff (lit from above)
    grad = np.linspace(1.08, 0.86, H, dtype=np.float32)[:, None, None]
    a = np.asarray(base, np.float32)
    a[..., :3] *= grad
    base = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
    font = ImageFont.truetype(FONT, 400)
    font.set_variation_by_axes([144, 900, 100, 0])
    text = "MILDEW"
    bbox = font.getbbox(text)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    x0 = (W - tw) // 2 - bbox[0]
    y0 = (H - th) // 2 - bbox[1] - 40
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    # orange swoosh under the word (tapered arc), drawn first so letters sit on it
    sw = Image.new("L", (W, H), 0)
    sd = ImageDraw.Draw(sw)
    pts = []
    for i in range(200):
        t = i / 199
        x = 260 + t * (W - 520)
        y = y0 + th + 175 - math.sin(t * math.pi) * 40 + t * 8
        pts.append((x, y, 4 + 34 * math.sin(t * math.pi) ** 0.8))
    for x, y, r in pts:
        sd.ellipse([x - r, y - r * 0.55, x + r, y + r * 0.55], fill=255)
    swoosh = Image.new("RGBA", (W, H), (236, 128, 32, 255))
    layer.paste(swoosh, (0, 0), sw)
    # extruded block shadow (dark orange-brown), then outline, then gold face
    for k in range(18, 0, -1):
        d.text((x0 + k * 1.1, y0 + k * 1.3), text, font=font, fill=(120, 52, 14, 255))
    d.text((x0, y0), text, font=font, fill=(70, 30, 8, 255), stroke_width=9, stroke_fill=(70, 30, 8, 255))
    face = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(face).text((x0, y0), text, font=font, fill=(255, 255, 255, 255))
    mask = face.split()[3]
    g = np.linspace(0, 1, H, dtype=np.float32)[:, None]
    top, bot = np.array([255, 214, 92], np.float32), np.array([236, 158, 34], np.float32)
    col = top * (1 - g[..., None]) + bot * g[..., None]
    col = np.broadcast_to(col, (H, W, 3))
    gold = Image.fromarray(np.dstack([col, np.full((H, W), 255, np.float32)]).astype(np.uint8), "RGBA")
    layer.paste(gold, (0, 0), mask)
    # highlight sheen on the upper half of the letters
    sheen = Image.new("RGBA", (W, H), (255, 246, 210, 90))
    hm = np.asarray(mask, np.float32) * (np.linspace(1, 0, H)[:, None] ** 3)
    layer.paste(sheen, (0, 0), Image.fromarray(hm.astype(np.uint8)))
    out = Image.alpha_composite(base, layer.filter(ImageFilter.GaussianBlur(0.8)))
    save("sign_face.png", out.convert("RGB"))


def flats():
    save("sponge_green.png", sponge(1024, 1024, (82, 116, 74), (140, 166, 112), 21, 0.45))
    save("wall_blue.png", sponge(1024, 1024, (34, 52, 108), (66, 92, 152), 31, 0.4))
    save("cream.png", sponge(512, 512, (200, 182, 150), (232, 214, 182), 41, 0.25))


def carpet():
    S = 1024
    img = Image.fromarray(sponge(S, S, (22, 26, 70), (36, 42, 96), 51, 0.3)).convert("RGB")
    d = ImageDraw.Draw(img)
    cols = [(232, 196, 64), (214, 70, 72), (60, 170, 160), (190, 80, 170), (240, 130, 40), (110, 160, 220)]
    rng = np.random.default_rng(7)
    for _ in range(170):
        x, y = rng.uniform(0, S), rng.uniform(0, S)
        r = rng.uniform(14, 46)
        c = cols[rng.integers(len(cols))]
        kind = rng.integers(3)
        for ox in (-S, 0, S):           # wrap for tiling
            for oy in (-S, 0, S):
                cx, cy = x + ox, y + oy
                if -60 < cx < S + 60 and -60 < cy < S + 60:
                    if kind == 0:
                        d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=c, width=int(r * 0.28))
                    elif kind == 1:
                        d.ellipse([cx - r * 0.5, cy - r * 0.5, cx + r * 0.5, cy + r * 0.5], fill=c)
                    else:
                        d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=c, width=5)
                        d.ellipse([cx - r * 0.35, cy - r * 0.35, cx + r * 0.35, cy + r * 0.35], fill=cols[(cols.index(c) + 2) % len(cols)])
    a = np.asarray(img.filter(ImageFilter.GaussianBlur(1.2)), np.float32)
    a += (RNG.random(a.shape[:2])[..., None] - 0.5) * 18      # pile texture
    save("carpet_navy.png", np.clip(a, 0, 255).astype(np.uint8))


if __name__ == "__main__":
    sign_face()
    flats()
    carpet()
    print("wrote", sorted(os.listdir(OUT)))
