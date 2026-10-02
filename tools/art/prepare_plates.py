#!/usr/bin/env python3
"""
Prepares the photographic studio plates (D026) from the ChatGPT batch:
  * crops away contact-sheet artefacts (duplicated strips, baked-in filename labels, black edges);
  * returns each plate to exact 4:3 by trimming width (cam1) or by extending the top of wide shots
    into darkness (real studio grids fall away to black), so no podium is lost;
  * writes assets/studio/plates/<id>.jpg (1600x1200) — masters in references/studio/plates_v1 are untouched.

    python3 tools/art/prepare_plates.py [SOURCE_DIR]
"""
import os
import sys

import cv2
import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "references", "studio", "plates_v1")
OUT = os.path.join(ROOT, "assets", "studio", "plates")
W, H = 1600, 1200

# id: (clean box x0,y0,x1,y1 in the 1600x1200 source, method, extra)
PLATES = {
    "cam1_presenter_empty": ((0, 100, 1588, 1097), "crop_x", 215),
    "cam1_presenter_with_graham": ((0, 100, 1588, 1097), "crop_x", 215),
    "wide_master": ((12, 100, 1588, 1097), "extend_top", None),
    "podium_row": ((0, 232, 1590, 1044), "extend_top", None),
    "presenter_wide": ((8, 224, 1600, 1040), "extend_top", None),
    "podium_closeup": ((0, 18, 1598, 1200), "crop_x", None),
    "audience_clapping": ((0, 0, 1588, 1200), "crop_x", None),
    "audience_unimpressed": ((10, 0, 1598, 1200), "crop_x", None),
    "floor_wrong_camera": ((8, 0, 1598, 1200), "crop_x", None),
    "corridor": ((4, 0, 1588, 1200), "crop_x", None),
    "corridor_doorway": ((4, 0, 1600, 1200), "crop_x", None),
}


def extend_top(img, need):
    """Grow the image upward by `need` px: continue each column's colour (heavily blurred) up into
    the darkness of the studio grid, so walls read as rising out of the light."""
    h, w = img.shape[:2]
    edge = img[2:14].astype(np.float32).mean(axis=0)                     # (w, 3)
    edge = cv2.GaussianBlur(edge[None], (0, 0), sigmaX=40, sigmaY=0.1)[0]
    ext = np.repeat(edge[None], need, axis=0)
    k = np.linspace(0.04, 1.0, need, dtype=np.float32) ** 1.6
    ext = ext * k[:, None, None]
    ext += np.random.default_rng(7).normal(0, 2.2, ext.shape).astype(np.float32)
    out = np.vstack([ext, img.astype(np.float32)])
    # cross-fade the first 50 rows of the photograph into the extension (no visible join)
    j = need
    fade = 50
    for i in range(fade):
        t = (i + 1) / (fade + 1)
        out[j + i] = out[j + i] * t + out[j - 1] * (1 - t)
    return np.clip(out, 0, 255).astype(np.uint8)


def prepare(pid, box, method, extra):
    src = cv2.imread(os.path.join(SRC, pid + ".png"))
    assert src is not None, pid
    x0, y0, x1, y1 = box
    img = src[y0:y1, x0:x1]
    h, w = img.shape[:2]
    if method == "crop_x":
        tw = min(w, int(round(h * 4 / 3)))
        if tw < w:
            left = extra if extra is not None else (w - tw) // 2
            left = max(0, min(w - tw, left))
            img = img[:, left:left + tw]
        else:
            th = int(round(w * 3 / 4))
            top = (h - th) // 2
            img = img[top:top + th]
    elif method == "extend_top":
        need = int(round(w * 3 / 4)) - h
        if need > 0:
            img = extend_top(img, need)
    out = cv2.resize(img, (W, H), interpolation=cv2.INTER_LANCZOS4)
    os.makedirs(OUT, exist_ok=True)
    cv2.imwrite(os.path.join(OUT, pid + ".jpg"), out, [cv2.IMWRITE_JPEG_QUALITY, 92])
    return out


if __name__ == "__main__":
    for pid, (box, method, extra) in PLATES.items():
        prepare(pid, box, method, extra)
        print("prepared", pid)
