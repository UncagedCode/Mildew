#!/usr/bin/env python3
"""
Imports Graham's alpha cut-outs (references/graham/cutouts_v1, cutouts_v2[/alternates]) into
runtime assets for the composited Camera 1 shot (D022), and writes config/graham_cutouts.json.

  * every frame is registered (sub-pixel translation) to the base body `talk_closed`;
  * talking frames contribute ONLY a feathered lower-face patch pasted onto the base body, and
    blink frames ONLY an eye-band patch -> the body never shimmers between frames;
  * output is scaled for the 1440x1080 programme and imported as lossy WebP with alpha.

    python3 tools/art/import_graham_cutouts.py
Masters are never modified.
"""
import json
import os

import cv2
import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
REF = os.path.join(ROOT, "references", "graham")
OUT = os.path.join(ROOT, "assets", "graham", "cut")
SCALE = 0.75                      # 1086x1448 -> 815x1086 (Graham fills a medium close-up)
BASE = "talk_closed"
# face geometry in the base frame (1086x1448 master space)
LOWER_FACE = ((552, 388), (142, 108), 22)   # centre, radii, feather
EYES = ((552, 268), (132, 44), 14)
FACE_BOX = (380, 120, 340, 380)             # x, y, w, h used for face registration

SOURCES = {
    # name: (batch path, kind)  kind: base | talk | blink:<onto> | whole
    "talk_closed": ("cutouts_v2/talk_closed.png", "base"),
    "talk_half": ("cutouts_v2/talk_half.png", "talk"),
    "talk_open": ("cutouts_v2/talk_open.png", "talk"),
    "talk_open_wide": ("cutouts_v2/talk_open_wide.png", "talk"),
    "talk_round": ("cutouts_v2/talk_round.png", "talk"),
    "talk_round_alt": ("cutouts_v2/alternates/talk_round_alt.png", "talk"),
    "neutral_blink": ("cutouts_v2/neutral_blink.png", "blink:talk_closed"),
    "neutral_blink_alt": ("cutouts_v2/alternates/neutral_blink_alt.png", "blink:talk_closed"),
    "restrained_smile": ("cutouts_v2/restrained_smile.png", "whole"),
    "restrained_smile_blink": ("cutouts_v2/restrained_smile_blink.png", "blink:restrained_smile"),
    "restrained_smile_alt": ("cutouts_v2/alternates/restrained_smile_alt.png", "whole"),
    "neutral_alt": ("cutouts_v2/alternates/neutral_alt.png", "whole"),
    "presenter_smile": ("cutouts_v2/presenter_smile.png", "whole"),
    "laughing": ("cutouts_v2/laughing.png", "whole"),
    "reading_cards": ("cutouts_v2/reading_cards.png", "whole"),
    "irritated_turn": ("cutouts_v2/irritated_turn.png", "whole"),
    "irritated_hold": ("cutouts_v2/irritated_hold.png", "whole"),
    "return_tense": ("cutouts_v2/return_tense.png", "whole"),
    "recovered_presenter": ("cutouts_v2/recovered_presenter.png", "whole"),
    "presenting_gesture": ("cutouts_v2/presenting_gesture.png", "whole"),
    "look_off_left": ("cutouts_v2/look_off_left.png", "whole"),
    "podium_glance": ("cutouts_v2/podium_glance.png", "whole"),
    "talk_open_single": ("cutouts_v2/alternates/talk_open_misframed.png", "single"),
    "talk_half_single": ("cutouts_v2/alternates/talk_half_misframed.png", "single"),
    "disappointed": ("cutouts_v1/disappointed.png", "whole"),
    "amused": ("cutouts_v1/amused.png", "whole"),
    "stare": ("cutouts_v1/stare.png", "whole"),
    "look_off": ("cutouts_v1/look_off.png", "whole"),
    "neutral_v1": ("cutouts_v1/neutral.png", "whole"),
    "eyes_closed": ("cutouts_v1/eyes_closed.png", "whole"),
    "embarrassed": ("cutouts_v1/embarrassed.png", "whole"),
    "irritated_front": ("cutouts_v1/irritated_front.png", "whole"),
    "off_air": ("cutouts_v1/off_air.png", "whole"),
    "rattled": ("cutouts_v1/rattled.png", "whole"),
}

# Semantic states -> frames. Missing states fall back; Director logic never sees filenames.
STATES = {
    "neutral": {"frame": "talk_closed", "blink": ["neutral_blink", "neutral_blink_alt"], "variants": ["neutral_alt"], "camera_motion": "quiet"},
    "restrained_smile": {"frame": "restrained_smile", "blink": ["restrained_smile_blink"], "variants": ["restrained_smile_alt"], "camera_motion": "quiet"},
    "presenter_smile": {"frame": "presenter_smile", "camera_motion": "standard"},
    "laughing": {"frame": "laughing", "camera_motion": "standard"},
    "amused": {"frame": "amused", "camera_motion": "quiet"},
    "presenting": {"frame": "talk_half", "talk": True, "camera_motion": "standard"},
    "reading_cards": {"frame": "reading_cards", "camera_motion": "quiet"},
    "irritated_turn": {"frame": "irritated_turn", "camera_motion": "none"},
    "irritated_hold": {"frame": "irritated_hold", "camera_motion": "none"},
    "irritated_front": {"frame": "irritated_front", "camera_motion": "none"},
    "angry": {"frame": "irritated_front", "camera_motion": "none"},
    "return_tense": {"frame": "return_tense", "camera_motion": "quiet"},
    "recovered_presenter": {"frame": "recovered_presenter", "camera_motion": "quiet"},
    "presenting_gesture": {"frame": "presenting_gesture", "camera_motion": "standard"},
    "open_hand_gesture": {"frame": "presenting_gesture", "camera_motion": "standard"},
    "disappointed": {"frame": "disappointed", "camera_motion": "quiet"},
    "stare": {"frame": "stare", "camera_motion": "none"},
    "look_off": {"frame": "look_off", "camera_motion": "none"},
    "look_off_left": {"frame": "look_off_left", "camera_motion": "quiet"},
    "podium_glance": {"frame": "podium_glance", "camera_motion": "quiet"},
    "applause_ack": {"frame": "podium_glance", "camera_motion": "quiet"},
    "embarrassed": {"frame": "embarrassed", "camera_motion": "quiet"},
    "rattled": {"frame": "rattled", "camera_motion": "quiet"},
    "off_air": {"frame": "off_air", "camera_motion": "none"},
    "eyes_closed": {"frame": "eyes_closed", "camera_motion": "none"},
}
TALK_CYCLE = ["talk_closed", "talk_half", "talk_open", "talk_open_wide", "talk_round", "talk_round_alt"]


def load(rel):
    im = cv2.imread(os.path.join(REF, rel), cv2.IMREAD_UNCHANGED)
    assert im is not None and im.shape[2] == 4, rel
    return im.astype(np.float32)


def gray(im, box=None):
    g = cv2.cvtColor(im[..., :3].astype(np.uint8), cv2.COLOR_BGR2GRAY).astype(np.float32)
    if box:
        x, y, w, h = box
        g = g[y:y + h, x:x + w]
    return g


def shift(im, dx, dy):
    M = np.float32([[1, 0, dx], [0, 1, dy]])
    return cv2.warpAffine(im, M, (im.shape[1], im.shape[0]), flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT, borderValue=0)


def register(im, ref, box=None):
    """Translate im so it lines up with ref (phase correlation, optionally on a sub-box)."""
    (dx, dy), _ = cv2.phaseCorrelate(gray(ref, box), gray(im, box))
    return shift(im, -dx, -dy), (dx, dy)


def ellipse_mask(h, w, spec):
    (cx, cy), (rx, ry), feather = spec
    m = np.zeros((h, w), np.float32)
    cv2.ellipse(m, (cx, cy), (rx, ry), 0, 0, 360, 1.0, -1)
    return cv2.GaussianBlur(m, (0, 0), feather)[..., None]


def paste(base, patch, spec):
    m = ellipse_mask(base.shape[0], base.shape[1], spec)
    out = base.copy()
    out[..., :3] = base[..., :3] * (1 - m) + patch[..., :3] * m
    return out


def save(name, im):
    os.makedirs(OUT, exist_ok=True)
    small = cv2.resize(im, (int(im.shape[1] * SCALE), int(im.shape[0] * SCALE)), interpolation=cv2.INTER_AREA)
    p = os.path.join(OUT, name + ".png")
    cv2.imwrite(p, np.clip(small, 0, 255).astype(np.uint8))
    open(p + ".import", "w").write('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n\ncompress/mode=1\ncompress/lossy_quality=0.9\nmipmaps/generate=false\nprocess/fix_alpha_border=true\n')
    return "res://assets/graham/cut/%s.png" % name


def main():
    base = load(SOURCES[BASE][0])
    done = {}
    report = {}
    paths = {}
    for name, (rel, kind) in SOURCES.items():
        im = load(rel)
        if kind == "base":
            out = im
            report[name] = "base"
        elif kind == "talk":
            reg, (dx, dy) = register(im, base, FACE_BOX)
            out = paste(base, reg, LOWER_FACE)
            report[name] = "lower-face patch, face shift (%.1f, %.1f)" % (dx, dy)
        elif kind.startswith("blink:"):
            onto = kind.split(":")[1]
            tgt = done.get(onto)
            if tgt is None:
                tgt = load(SOURCES[onto][0]) if onto == BASE else register(load(SOURCES[onto][0]), base)[0]
            reg, (dx, dy) = register(im, tgt, FACE_BOX)
            out = paste(tgt, reg, EYES)
            report[name] = "eye patch onto %s, face shift (%.1f, %.1f)" % (onto, dx, dy)
        elif kind == "single":
            out = im
            report[name] = "unregistered single shot (misframed; never in a loop)"
        else:
            out, (dx, dy) = register(im, base)
            report[name] = "whole-frame registration (%.1f, %.1f)" % (dx, dy)
        done[name] = out
        paths[name] = save(name, out)
    cfg = {
        "version": 1,
        "_comment": "Generated by tools/art/import_graham_cutouts.py. Composited Graham (D022): alpha cut-outs over the Mildew studio. Semantic states -> frames; full-frame pack plates (graham_states.json) remain the fallback.",
        "frame_size": [int(1086 * SCALE), int(1448 * SCALE)],
        "frames": paths,
        "states": STATES,
        "talk_cycle": TALK_CYCLE,
        "singles": ["talk_open_single", "talk_half_single"],
        "registration": report,
    }
    json.dump(cfg, open(os.path.join(ROOT, "config", "graham_cutouts.json"), "w"), indent=1)
    for k, v in report.items():
        print("%-24s %s" % (k, v))


if __name__ == "__main__":
    main()
