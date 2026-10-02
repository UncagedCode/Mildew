#!/usr/bin/env python3
"""
Generates PROVISIONAL on-brand textures for the Mildew studio (owned/procedural, no licensing
risk). Late-90s regional TV studio: loud patterned carpet, burgundy curtains, app icon.

    python3 tools/art/gen_textures.py      # writes assets/textures/*.png
"""
import math
import os
import random
from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "textures")
FONTS = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "fonts")
random.seed(1998)


def tile_draw(size, draw_fn):
    """Draw with wrap-around so the texture tiles seamlessly."""
    img = Image.new("RGBA", (size, size))
    base = Image.new("RGBA", (size * 3, size * 3))
    d = ImageDraw.Draw(base)
    draw_fn(d, size)
    for ox in range(3):
        for oy in range(3):
            pass
    # fold the 3x3 canvas back into one tile
    acc = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    for ox in range(3):
        for oy in range(3):
            acc.alpha_composite(base.crop((ox * size, oy * size, ox * size + size, oy * size + size)))
    img.alpha_composite(acc)
    return img


def carpet():
    S = 512
    bg = Image.new("RGBA", (S, S), (44, 22, 66, 255))
    # subtle pile noise
    px = bg.load()
    for y in range(S):
        for x in range(S):
            n = random.randint(-9, 9)
            r, g, b, a = px[x, y]
            px[x, y] = (max(0, r + n), max(0, g + n // 2), max(0, b + n), 255)

    def shapes(d, s):
        cols = [(32, 170, 170), (230, 180, 40), (220, 60, 130), (120, 200, 90), (250, 240, 220)]
        for _ in range(70):
            cx, cy = s + random.randrange(s), s + random.randrange(s)
            c = random.choice(cols)
            kind = random.random()
            if kind < 0.35:  # squiggle
                pts = []
                ang = random.random() * math.tau
                for k in range(9):
                    pts.append((cx + k * 9 * math.cos(ang), cy + k * 9 * math.sin(ang) + 10 * math.sin(k * 1.4)))
                d.line(pts, fill=c + (255,), width=6, joint="curve")
            elif kind < 0.6:  # triangle
                r = random.randint(10, 22)
                a0 = random.random() * math.tau
                d.polygon([(cx + r * math.cos(a0 + i * 2.094), cy + r * math.sin(a0 + i * 2.094)) for i in range(3)], fill=c + (255,))
            elif kind < 0.8:  # ring
                r = random.randint(7, 14)
                d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=c + (255,), width=5)
            else:  # confetti dots
                for _k in range(5):
                    rx, ry = cx + random.randint(-25, 25), cy + random.randint(-25, 25)
                    d.ellipse([rx - 3, ry - 3, rx + 3, ry + 3], fill=c + (255,))
        # replicate into all 9 cells for wrap
        return

    layer = Image.new("RGBA", (S * 3, S * 3))
    d = ImageDraw.Draw(layer)
    shapes(d, S)
    acc = Image.new("RGBA", (S, S))
    for ox in range(3):
        for oy in range(3):
            acc.alpha_composite(layer.crop((ox * S, oy * S, ox * S + S, oy * S + S)))
    acc = acc.filter(ImageFilter.GaussianBlur(0.8))
    bg.alpha_composite(acc)
    bg.convert("RGB").save(os.path.join(OUT, "carpet.png"))


def curtain():
    W, H = 256, 512
    img = Image.new("RGB", (W, H))
    px = img.load()
    for x in range(W):
        fold = 0.5 + 0.5 * math.cos(x / W * math.tau * 4)
        fold2 = 0.5 + 0.5 * math.cos(x / W * math.tau * 9 + 1.3)
        shade = 0.45 + 0.45 * fold + 0.1 * fold2
        for y in range(H):
            n = random.uniform(-0.03, 0.03)
            v = max(0, min(1, shade + n - 0.12 * (y / H)))
            px[x, y] = (int(120 * v + 20), int(18 * v + 6), int(40 * v + 12))
    img.save(os.path.join(OUT, "curtain.png"))


def flare():
    S = 256
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    px = img.load()
    for y in range(S):
        for x in range(S):
            dx, dy = (x - S / 2) / (S / 2), (y - S / 2) / (S / 2)
            r = math.sqrt(dx * dx + dy * dy)
            core = max(0, 1 - r) ** 3
            streak = max(0, 1 - abs(dy) * 22) * max(0, 1 - abs(dx)) * 0.8
            a = min(1, core + streak)
            px[x, y] = (255, 245, 230, int(a * 255))
    img.save(os.path.join(OUT, "flare.png"))


def icon():
    S = 432
    img = Image.new("RGBA", (S, S))
    d = ImageDraw.Draw(img)
    for y in range(S):
        t = y / S
        d.line([(0, y), (S, y)], fill=(int(70 + 40 * t), int(20 + 60 * t), int(110 - 20 * t), 255))
    for _ in range(40):
        x, y, r = random.randrange(S), random.randrange(S), random.randint(4, 18)
        d.ellipse([x - r, y - r, x + r, y + r], fill=(120, 170, 70, random.randint(40, 110)))
    try:
        font = ImageFont.truetype(os.path.join(FONTS, "InterDisplay-BlackItalic.otf"), 300)
    except OSError:
        font = ImageFont.load_default()
    for off, col in [((10, 12), (20, 10, 30, 255)), ((4, 4), (120, 110, 90, 255)), ((0, 0), (235, 235, 245, 255))]:
        d.text((S / 2 + off[0], S / 2 + off[1]), "M", font=font, fill=col, anchor="mm")
    img.save(os.path.join(OUT, "icon_432.png"))
    img.resize((192, 192), Image.LANCZOS).save(os.path.join(OUT, "icon.png"))
    # adaptive icon layers
    bg = img.copy()
    bg.save(os.path.join(OUT, "icon_bg_432.png"))
    fg = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    fd = ImageDraw.Draw(fg)
    for off, col in [((10, 12), (20, 10, 30, 255)), ((4, 4), (120, 110, 90, 255)), ((0, 0), (235, 235, 245, 255))]:
        fd.text((S / 2 + off[0], S / 2 + off[1]), "M", font=ImageFont.truetype(os.path.join(FONTS, "InterDisplay-BlackItalic.otf"), 200), fill=col, anchor="mm")
    fg.save(os.path.join(OUT, "icon_fg_432.png"))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    carpet()
    curtain()
    flare()
    icon()
    print("textures written to", os.path.abspath(OUT))
