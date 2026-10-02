"""
holekit — a tiny height-field "photograph" renderer for Mildew's Hole illustrations.

Every Hole image is described as a height field (holes are simply deep negative heights), an albedo
map and a few material maps. render() lights it like a cheap studio product shot: key light from the
upper left, cast shadows by height-field ray marching, cavity occlusion, depth darkening for the inside
of holes, Blinn-Phong specular for wet/metal/glossy surfaces, then lens vignette and film grain.

All output is project-owned procedural art (no external imagery). PROVISIONAL quality.
"""
import math
import numpy as np
import cv2

W, H = 1600, 1200


class Scene:
    def __init__(self, seed):
        self.rng = np.random.default_rng(seed)
        self.h = np.zeros((H, W), np.float32)
        self.albedo = np.ones((H, W, 3), np.float32) * 0.5
        self.spec = np.zeros((H, W), np.float32)       # specular strength 0..1
        self.gloss = 40.0                                # Blinn exponent
        self.bump = 1.0                                  # normal strength
        self.ambient = 0.38
        self.light = (-0.55, -0.62, 0.56)
        self.deep_start = 40.0                           # heights below -deep_start darken
        self.deep_full = 260.0
        self.deep_colour = (0.02, 0.015, 0.012)
        self.shadow_soft = 6.0
        self.ao_strength = 0.010
        self.emit = None                                 # optional additive (H,W,3)
        self.tint = (1.0, 1.0, 1.0)

    # ---------------- coordinates / noise ----------------
    @staticmethod
    def grid():
        y, x = np.mgrid[0:H, 0:W].astype(np.float32)
        return x, y

    def noise(self, scale, octaves=4, persistence=0.5, aniso=(1.0, 1.0)):
        """Fractal value noise in roughly [-1, 1]; scale = feature size in pixels."""
        out = np.zeros((H, W), np.float32)
        amp, total = 1.0, 0.0
        s = float(scale)
        for _ in range(octaves):
            gw = max(2, int(W / (s * aniso[0])) + 3)
            gh = max(2, int(H / (s * aniso[1])) + 3)
            g = self.rng.standard_normal((gh, gw)).astype(np.float32)
            up = cv2.resize(g, (W, H), interpolation=cv2.INTER_CUBIC)
            out += up * amp
            total += amp
            amp *= persistence
            s *= 0.5
        return out / total

    def speckle(self, density, size=1.5, strength=1.0):
        """Sparse random dots (pores, crumbs, grit)."""
        m = (self.rng.random((H, W)) < density).astype(np.float32)
        if size > 0:
            m = cv2.GaussianBlur(m, (0, 0), size)
            m /= max(1e-6, m.max())
        return m * strength


# ---------------- shape helpers ----------------
def sstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def disc(x, y, cx, cy, r):
    return np.sqrt((x - cx) ** 2 + (y - cy) ** 2) - r


def ellipse(x, y, cx, cy, rx, ry, angle=0.0):
    c, s = math.cos(angle), math.sin(angle)
    dx, dy = x - cx, y - cy
    u = (dx * c + dy * s) / rx
    v = (-dx * s + dy * c) / ry
    return (np.sqrt(u * u + v * v) - 1.0) * min(rx, ry)


def rrect(x, y, cx, cy, hw, hh, r=0.0, angle=0.0):
    c, s = math.cos(angle), math.sin(angle)
    dx, dy = x - cx, y - cy
    u = np.abs(dx * c + dy * s) - (hw - r)
    v = np.abs(-dx * s + dy * c) - (hh - r)
    outside = np.sqrt(np.maximum(u, 0) ** 2 + np.maximum(v, 0) ** 2)
    inside = np.minimum(np.maximum(u, v), 0)
    return outside + inside - r


def polygon_mask(points, blur=1.5):
    m = np.zeros((H, W), np.uint8)
    cv2.fillPoly(m, [np.array(points, np.int32)], 255)
    f = m.astype(np.float32) / 255.0
    return cv2.GaussianBlur(f, (0, 0), blur) if blur > 0 else f


def pit(d, depth, softness=4.0, wall=1.0):
    """Height contribution of a hole given signed distance d (negative inside)."""
    inside = sstep(softness, -softness, d)
    bowl = np.clip(-d / max(1.0, wall), 0, 1)
    return -depth * inside * (0.35 + 0.65 * np.sqrt(bowl))


def mix(a, b, m):
    a = np.asarray(a, np.float32)
    b = np.asarray(b, np.float32)
    m = np.asarray(m, np.float32)
    if m.ndim == 2:
        m = m[..., None]
    return a * (1 - m) + b * m


def col(hexstr):
    hexstr = hexstr.lstrip("#")
    return np.array([int(hexstr[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], np.float32)


def fill(c):
    return np.broadcast_to(np.asarray(c, np.float32), (H, W, 3)).copy()


# ---------------- renderer ----------------
def _shift(a, dx, dy):
    M = np.float32([[1, 0, -dx], [0, 1, -dy]])
    return cv2.warpAffine(a, M, (W, H), flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE)


def render(sc, grain=0.018, vignette=0.32):
    h = sc.h.astype(np.float32)
    gx = cv2.Sobel(h, cv2.CV_32F, 1, 0, ksize=3) / 8.0 * sc.bump
    gy = cv2.Sobel(h, cv2.CV_32F, 0, 1, ksize=3) / 8.0 * sc.bump
    n = np.dstack([-gx, -gy, np.ones_like(h)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    L = np.array(sc.light, np.float32)
    L /= np.linalg.norm(L)
    lam = np.clip((n * L).sum(axis=2), 0, 1)
    # cast shadows: march toward the light
    lxy = math.hypot(L[0], L[1])
    dirx, diry = L[0] / lxy, L[1] / lxy
    slope = L[2] / lxy
    occl = np.zeros_like(h)
    s = 2.0
    while s < 420.0:
        sample = _shift(h, dirx * s, diry * s)
        occl = np.maximum(occl, sample - (h + slope * s))
        s *= 1.16
    shadow = 1.0 - np.clip(occl / sc.shadow_soft, 0, 1) * 0.88
    shadow = cv2.GaussianBlur(shadow, (0, 0), 1.6)
    # cavity occlusion (two scales)
    cav = np.maximum(cv2.GaussianBlur(h, (0, 0), 28) - h, 0) + 0.6 * np.maximum(cv2.GaussianBlur(h, (0, 0), 7) - h, 0)
    ao = np.clip(1.0 - cav * sc.ao_strength, 0.12, 1.0)
    deep = sstep(-sc.deep_start, -sc.deep_full, h)
    # specular
    V = np.array([0, 0, 1], np.float32)
    Hv = (L + V) / np.linalg.norm(L + V)
    ndh = np.clip((n * Hv).sum(axis=2), 0, 1)
    spec = (ndh ** sc.gloss) * sc.spec * shadow
    light = sc.ambient * ao + (1.0 - sc.ambient) * lam * shadow * (0.55 + 0.45 * ao)
    rgb = sc.albedo * light[..., None]
    rgb = mix(rgb, fill(sc.deep_colour) * light[..., None] * 0.6, deep)
    rgb += spec[..., None] * np.array([1.0, 0.97, 0.9], np.float32)
    if sc.emit is not None:
        rgb += sc.emit
    rgb *= np.array(sc.tint, np.float32)
    # lens: vignette + grain + gentle filmic curve
    x, y = Scene.grid()
    r = np.sqrt(((x - W / 2) / (W / 2)) ** 2 + ((y - H / 2) / (H / 2)) ** 2)
    rgb *= (1.0 - vignette * sstep(0.55, 1.45, r))[..., None]
    rng = np.random.default_rng(12345)
    rgb += rng.standard_normal((H, W, 1)).astype(np.float32) * grain
    rgb = np.clip(rgb, 0, None)
    rgb = rgb / (1.0 + 0.18 * rgb)          # soft highlight roll-off
    rgb = np.clip(rgb * 1.12, 0, 1) ** (1 / 1.05)
    return (rgb * 255.0 + 0.5).astype(np.uint8)


def save(img, path, quality=86):
    bgr = cv2.cvtColor(img, cv2.COLOR_RGB2BGR)
    cv2.imwrite(path, bgr, [cv2.IMWRITE_JPEG_QUALITY, quality, cv2.IMWRITE_JPEG_PROGRESSIVE, 0])
