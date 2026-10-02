#!/usr/bin/env python3
"""
Authors config/studio_plates.json for the photographic plates (D026) prepared by prepare_plates.py:
  * Graham's mark (anchor = bottom-centre of his cut-out frame, height = frame height / plate height),
    measured on cam1 from the with/without-Graham pair and carried to the wide plates via the
    presenter table (table width : Graham frame height ratio from cam1);
  * foreground layers (the presenter table in front of him) cut from each plate with feathered masks;
  * podium CRT screen quads (podium numbers left to right) and their coloured lamp strips;
  * rig/practical lights for subtle flicker (auto-detected bright blobs).
All coordinates are written normalised to the 4:3 frame, so higher-resolution re-renders of the same
plates drop in without re-authoring.

    python3 tools/art/author_plates.py
"""
import json
import os

import cv2
import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
PL = os.path.join(ROOT, "assets", "studio", "plates")
RES = "res://assets/studio/plates/"
W, H = 1600.0, 1200.0

# ---- measured by hand on the prepared 1600x1200 plates (see DECISIONS D026) ----------------------
GRAHAM = {
    # x, y (px) of the cut-out frame's bottom-centre; h = frame height (px)
    "cam1_presenter_empty": (523, 1060, 753),
    "wide_master": (237, 880, 246),
    "presenter_wide": (333, 895, 236),
}
# table masks: list of ("ellipse", cx, cy, rx, ry) / ("rect", x0, y0, x1, y1)
TABLES = {
    "cam1_presenter_empty": [("ellipse", 488, 1030, 494, 54), ("rect", 0, 1030, 980, 1200)],
    "wide_master": [("ellipse", 225, 876, 177, 26), ("rect", 98, 876, 357, 1135), ("ellipse", 226, 1128, 142, 30)],
    "presenter_wide": [("ellipse", 322, 889, 162, 23), ("rect", 172, 889, 462, 1098), ("ellipse", 316, 1100, 150, 26)],
}
# podium screens (x, y, w, h) in podium order left->right; podium 0 = whoever is framed
SCREENS = {
    "wide_master": [(458, 800, 76, 72), (593, 796, 72, 67), (723, 795, 74, 61), (857, 795, 72, 60),
                    (989, 796, 73, 62), (1123, 798, 75, 64), (1261, 802, 78, 70), (1404, 808, 82, 78)],
    "podium_row": [(250, 658, 152, 180), (518, 678, 98, 130), (694, 682, 78, 114), (842, 688, 70, 100),
                   (982, 692, 70, 90), (1123, 693, 75, 88), (1265, 696, 77, 82), (1412, 697, 82, 79)],
    "presenter_wide": [(909, 901, 80, 72), (1051, 909, 73, 77), (1185, 922, 75, 84), (1327, 939, 82, 94), (1482, 964, 98, 115)],
    "podium_closeup": [(569, 422, 461, 379)],
}
CAMERAS = {
    "cam1": "cam1_presenter_empty", "cam2": "wide_master", "cam3": "podium_row", "cam4": "presenter_wide",
    "cam_podium": "podium_closeup", "cam_corridor": "corridor", "cam_doorway": "corridor_doorway",
    "cam_floor": "floor_wrong_camera", "cam_audience": "audience_clapping", "cam_audience_meh": "audience_unimpressed",
}
DRIFT = {"cam1_presenter_empty": 2.0, "podium_closeup": 3.0}


def n(x, y):
    return [round(x / W, 4), round(y / H, 4)]


def quad(x, y, w, h, inset=0.06):
    dx, dy = w * inset, h * inset
    return [n(x + dx, y + dy), n(x + w - dx, y + dy), n(x + w - dx, y + h - dy), n(x + dx, y + h - dy)]


def lamp_for(img, x, y, w, h):
    """The lit coloured strip on top of a podium: brightest saturated band above the screen."""
    hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
    y0, y1 = max(0, int(y - h * 1.6)), int(y - h * 0.05)
    x0, x1 = max(0, int(x - w * 0.35)), min(int(W), int(x + w * 1.35))
    reg = hsv[y0:y1, x0:x1]
    m = ((reg[..., 2] > 190) & ((reg[..., 1] > 70) | (reg[..., 2] > 235))).astype(np.uint8)
    m = cv2.morphologyEx(m, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    num, lab, st, _ = cv2.connectedComponentsWithStats(m)
    if num <= 1:
        return None
    i = 1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA]))
    lx, ly, lw, lh, _ = st[i]
    return [n(x0 + lx, y0 + ly), n(x0 + lx + lw, y0 + ly), n(x0 + lx + lw, y0 + ly + lh), n(x0 + lx, y0 + ly + lh)]


LIGHT_YMAX = {"cam1_presenter_empty": 0.22}


def rig_lights(img, ymax_frac=0.45):
    hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
    m = (hsv[..., 2] > 235).astype(np.uint8)
    m[int(H * ymax_frac):] = 0
    m = cv2.morphologyEx(m, cv2.MORPH_OPEN, np.ones((5, 5), np.uint8))
    num, lab, st, cen = cv2.connectedComponentsWithStats(m)
    out = []
    for i in range(1, num):
        x, y, w, h, a = st[i]
        if 120 < a < 20000 and 0.5 < w / max(1, h) < 2.0:
            col = img[lab == i].mean(axis=0)[::-1]
            sat = cv2.cvtColor(np.uint8([[img[lab == i].mean(axis=0)]]), cv2.COLOR_BGR2HSV)[0, 0]
            # rim colour (lens centres blow out to white): sample a ring around the blob
            ring = cv2.dilate((lab == i).astype(np.uint8), np.ones((15, 15), np.uint8)) - (lab == i).astype(np.uint8)
            rc = img[ring > 0].mean(axis=0)[::-1]
            c = rc if np.ptp(rc) > 25 else col
            out.append({"at": n(cen[i][0], cen[i][1]), "r": round(max(w, h) / 2 / W, 4),
                        "colour": "#%02x%02x%02x" % tuple(int(v) for v in np.clip(c * 1.2, 0, 255))})
    out.sort(key=lambda l: l["at"][0])
    return out[:14]


def foreground(pid, img, shapes):
    mask = np.zeros(img.shape[:2], np.uint8)
    for s in shapes:
        if s[0] == "ellipse":
            cv2.ellipse(mask, (int(s[1]), int(s[2])), (int(s[3]), int(s[4])), 0, 0, 360, 255, -1)
        else:
            cv2.rectangle(mask, (int(s[1]), int(s[2])), (int(s[3]), int(s[4])), 255, -1)
    mask = cv2.GaussianBlur(mask, (0, 0), 1.6)
    rgba = np.dstack([img, mask])
    path = os.path.join(PL, pid + "_fg.png")
    cv2.imwrite(path, rgba)
    return RES + pid + "_fg.png"


def main():
    plates = {}
    for f in sorted(os.listdir(PL)):
        if not f.endswith(".jpg") or f.startswith("standin_") or f == "cam1_presenter_with_graham.jpg":
            continue
        pid = f[:-4]
        img = cv2.imread(os.path.join(PL, f))
        spec = {"image": RES + f, "drift": {"px": DRIFT.get(pid, 4.0), "zoom": 0.004}}
        if pid in GRAHAM:
            x, y, h = GRAHAM[pid]
            spec["graham"] = {"anchor": n(x, y), "height": round(h / H, 4)}
        if pid in TABLES:
            spec["foreground"] = foreground(pid, img, TABLES[pid])
        if pid in SCREENS:
            scr, lamps = [], []
            for i, (x, y, w, h) in enumerate(SCREENS[pid]):
                num = 0 if pid == "podium_closeup" else i + 1
                scr.append({"podium": num, "quad": quad(x, y, w, h)})
                lq = lamp_for(img, x, y, w, h)
                if lq and num > 0:
                    lamps.append({"podium": num, "quad": lq})
            spec["screens"] = scr
            spec["lamps"] = lamps
        if not pid.startswith(("audience", "floor", "podium_closeup")):
            spec["lights"] = rig_lights(img, LIGHT_YMAX.get(pid, 0.45))
        plates[pid] = spec
        print("%-24s graham=%s screens=%d lamps=%d lights=%d" % (pid, "graham" in spec, len(spec.get("screens", [])),
              len(spec.get("lamps", [])), len(spec.get("lights", []))))
    out = {"version": 2,
           "_comment": "Photographic studio plates (D026), batch v1 from the ChatGPT request. Authored by tools/art/author_plates.py from plates prepared by tools/art/prepare_plates.py. Coordinates normalised to the 4:3 frame. graham.anchor = bottom-centre of Graham's cut-out frame; graham.height = cut-out frame height / frame height. screens[].podium 0 = the contestant currently framed.",
           "cameras": CAMERAS, "plates": plates}
    with open(os.path.join(ROOT, "config", "studio_plates.json"), "w") as fh:
        json.dump(out, fh, indent=1)


if __name__ == "__main__":
    main()
