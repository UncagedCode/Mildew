#!/usr/bin/env python3
"""
Prepares the backstage room plates (D037) from the user's ChatGPT batch for the CCTV cutaways:
  * crops each image to its clean band (the batch has contact-sheet artefacts: a duplicated strip
    at the top and a mirrored "reflection" strip at the bottom);
  * returns it to 4:3 by trimming width (tall bands) or extending top/bottom into darkness (wide bands);
  * grades it as cheap late-90s security video: monochrome with a faint green cast, crushed blacks,
    soft focus, lifted noise floor. Live scanlines/noise/timestamp are drawn on top in cctv_view.gd;
  * writes assets/studio/rooms/<room>__<variant>.jpg (1440x1080). Masters in references/rooms/plates_v1 are untouched.

    python3 tools/art/prepare_room_plates.py
"""
import os
import cv2
import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "references", "rooms", "plates_v1")
OUT = os.path.join(ROOT, "assets", "studio", "rooms")
W, H = 1440, 1080

# (source file, output name, clean y0, y1)  — bands measured by eye on gridded previews (1024x768 sources)
PLATES = [
    ("01_green_room/01_base.png", "green_room__base", 150, 612),
    ("01_green_room/02_variant_a_door_open.png", "green_room__door_open", 150, 612),
    ("01_green_room/03_variant_b_chair_by_door.png", "green_room__chair_door", 152, 612),
    ("01_green_room/04_variant_c_light_off.png", "green_room__light_off", 152, 612),
    ("02_studio_c/01_base.png", "studio_c__base", 0, 545),
    ("02_studio_c/02_variant_a_fourth_podium_lit.png", "studio_c__podium_lit", 0, 545),
    ("02_studio_c/03_variant_b_exit_glow_only.png", "studio_c__light_off", 0, 545),
    ("03_prop_store/01_base.png", "prop_store__base", 162, 604),
    ("03_prop_store/02_variant_a_door_open.png", "prop_store__door_open", 162, 604),
    ("03_prop_store/03_variant_b_mannequin_faces_camera.png", "prop_store__mannequin_faces", 162, 604),
    ("03_prop_store/04_variant_c_mannequin_gone.png", "prop_store__mannequin_gone", 162, 604),
    ("04_archive_tape_room/01_base.png", "tape_room__base", 232, 548),
    ("04_archive_tape_room/02_variant_a_back_door_ajar.png", "tape_room__door_ajar", 220, 548),
    ("04_archive_tape_room/03_variant_b_tv_only_light.png", "tape_room__light_off", 220, 548),
    ("05_service_corridor/01_base.png", "corridor__base", 212, 553),
    ("05_service_corridor/02_variant_a_far_door_open.png", "corridor__door_open", 212, 553),
    ("05_service_corridor/03_variant_b_one_tube_out.png", "corridor__light_off", 210, 550),
    ("06_control_room/01_base.png", "control_room__base", 35, 768),
    ("07_staff_kitchenette/01_base.png", "kitchenette__base", 8, 698),
    ("08_loading_area/01_base.png", "loading__base", 98, 700),
    ("09_grahams_dressing_room/01_base.png", "dressing_room__base", 70, 545),
    ("10_locked_room/01_base.png", "locked__base", 45, 740),
]


def load(path):
    img = cv2.imread(path)
    if img is None:   # one master is a truncated PNG: decode what's there via PIL
        from PIL import Image, ImageFile
        ImageFile.LOAD_TRUNCATED_IMAGES = True
        img = cv2.cvtColor(np.array(Image.open(path).convert("RGB")), cv2.COLOR_RGB2BGR)
    return img


def to_43(band):
    h, w = band.shape[:2]
    if h / w >= 0.75:
        cw = int(h * 4 / 3)
        x0 = (w - cw) // 2
        out = band[:, x0:x0 + cw]
    else:
        need = int(w * 0.75) - h
        top, bot = need // 2, need - need // 2
        def ext(edge_rows, n):
            e = edge_rows.astype(np.float32).mean(axis=0)
            e = cv2.GaussianBlur(e[None], (0, 0), sigmaX=30, sigmaY=0.1)[0]
            k = np.linspace(1.0, 0.0, n, dtype=np.float32) ** 1.3
            return np.repeat(e[None], n, axis=0) * k[:, None, None]
        t = ext(band[:6], top)[::-1]
        b = ext(band[-6:], bot)
        out = np.vstack([t, band.astype(np.float32), b])
        for i in range(30):   # soften the joins
            a = (i + 1) / 31.0
            out[top + i] = out[top + i] * a + out[top - 1] * (1 - a)
            out[top + h - 1 - i] = out[top + h - 1 - i] * a + out[top + h] * (1 - a)
        out = np.clip(out, 0, 255).astype(np.uint8)
    return cv2.resize(out, (W, H), interpolation=cv2.INTER_CUBIC)


def grade(img):
    g = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY).astype(np.float32) / 255.0
    g = cv2.GaussianBlur(g, (0, 0), 1.6)                       # cheap lens + tape softness
    g = np.clip((g - 0.04) * 1.18, 0, 1) ** 1.1                # crushed blacks
    g = g * 0.88 + 0.05                                        # lifted floor
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    v = 1.0 - 0.35 * (((xx - W / 2) / (W / 2)) ** 2 + ((yy - H / 2) / (H / 2)) ** 2)
    g = g * np.clip(v, 0.55, 1.0)
    g += np.random.default_rng(98).normal(0, 0.018, g.shape).astype(np.float32)
    g = np.clip(g, 0, 1)
    out = np.stack([g * 0.86, g * 0.97, g * 0.88], axis=-1)   # faint green cast (BGR)
    return (out * 255).astype(np.uint8)


def main():
    os.makedirs(OUT, exist_ok=True)
    for src, name, y0, y1 in PLATES:
        img = load(os.path.join(SRC, src))
        band = img[y0:y1, :]
        out = grade(to_43(band))
        cv2.imwrite(os.path.join(OUT, name + ".jpg"), out, [cv2.IMWRITE_JPEG_QUALITY, 86])
        print("wrote", name, band.shape[:2])


if __name__ == "__main__":
    main()
