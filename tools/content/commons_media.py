#!/usr/bin/env python3
"""
Real-photo sourcing for Mildew content (D020): Wikimedia Commons only, permissive licences only.

  search  python3 tools/content/commons_media.py search OUTDIR "query one" "query two" ...
          -> OUTDIR/candidates.json + OUTDIR/sheet.jpg (numbered contact sheet for human review)
  fetch   python3 tools/content/commons_media.py fetch MANIFEST.json
          -> downloads each chosen file at 1600 px, crops to 4:3 around the manifest's focus,
             writes assets/content/<game>/<id>.jpg and prints the media metadata block.

Licence policy (docs/07, D020): accept Public Domain, CC0, CC BY (any version). Reject
share-alike, non-commercial, no-derivatives, GFDL-only and anything unknown. Every accepted file
keeps: Commons page, original URL, author, licence, licence URL, attribution text.
Requires network access to commons.wikimedia.org and upload.wikimedia.org.
"""
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request

import cv2
import numpy as np

UA = "MildewContentBot/0.2 (https://github.com/UncagedCode/mildew; content licensing review)"
API = "https://commons.wikimedia.org/w/api.php"
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


_last = [0.0]


def _polite(url, timeout):
    """Serial, paced requests with Retry-After handling (Wikimedia API etiquette)."""
    import urllib.error
    gap = 3.0 if "upload.wikimedia.org" in url else 1.0   # media host throttles hardest
    for attempt in range(8):
        wait = gap - (time.time() - _last[0])
        if wait > 0:
            time.sleep(wait)
        _last[0] = time.time()
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            if e.code in (429, 503) and attempt < 7:
                ra = e.headers.get("Retry-After")
                time.sleep(min(60.0, float(ra) if ra and ra.isdigit() else 5.0 * (attempt + 1)))
                continue
            raise
        except Exception:  # noqa: BLE001  (network refusal: don't hammer, fail fast)
            if attempt >= 1:
                raise
            time.sleep(2.0)


def api(params):
    params = dict(params, format="json", formatversion="2", maxlag="5")
    return json.loads(_polite(API + "?" + urllib.parse.urlencode(params), 30).decode())


def get_bytes(url):
    return _polite(url, 60)


def strip_html(s):
    s = re.sub(r"<[^>]+>", "", s or "")
    return re.sub(r"\s+", " ", s).strip()


def licence_ok(short):
    s = (short or "").lower().strip()
    if not s:
        return False
    if any(bad in s for bad in ["sa", "nc", "nd", "gfdl", "fal", "art libre"]):
        # "sa" would also match e.g. "usage"... licence short names are short, so this is fine
        if not (s.startswith("public domain") or s in ("pd", "cc0")):
            return False
    return s.startswith("public domain") or s.startswith("pd") or s.startswith("cc0") or s.startswith("cc by ") or s.startswith("cc-by-") or s in ("cc by", "cc-by")


def file_info(titles, thumb_width=None):
    p = {"action": "query", "prop": "imageinfo", "titles": "|".join(titles),
         "iiprop": "url|size|mime|extmetadata"}
    if thumb_width:
        p["iiurlwidth"] = str(thumb_width)
    out = {}
    for page in api(p).get("query", {}).get("pages", []):
        ii = (page.get("imageinfo") or [{}])[0]
        md = ii.get("extmetadata", {})
        val = lambda k: strip_html(md.get(k, {}).get("value", ""))
        out[page["title"]] = {
            "title": page["title"],
            "page": "https://commons.wikimedia.org/wiki/" + urllib.parse.quote(page["title"].replace(" ", "_")),
            # thumbnails are served from thumb.wikimedia.org by the API but are equally available
            # from upload.wikimedia.org/.../thumb/ (one allow-listed host for all downloads)
            "url": ii.get("url", "").split("?")[0], "thumb": ii.get("thumburl", "").split("?")[0].replace("https://thumb.wikimedia.org/", "https://upload.wikimedia.org/"), "width": ii.get("width", 0), "height": ii.get("height", 0),
            "mime": ii.get("mime", ""), "licence": val("LicenseShortName"), "licence_url": val("LicenseUrl"),
            "author": val("Artist"), "credit": val("Credit"), "attribution_required": val("AttributionRequired"),
            "description": val("ImageDescription")[:300],
        }
    return out


def search(outdir, queries, per_query=40, min_px=1000):
    os.makedirs(outdir, exist_ok=True)
    titles = []
    for q in queries:
        res = api({"action": "query", "list": "search", "srnamespace": "6", "srlimit": str(per_query), "srsearch": q + " filetype:bitmap"})
        for hit in res.get("query", {}).get("search", []):
            if hit["title"] not in titles:
                titles.append(hit["title"])
    infos = {}
    for i in range(0, len(titles), 40):
        infos.update(file_info(titles[i:i + 40], thumb_width=330))
    cands = []
    for t in titles:
        inf = infos.get(t)
        if not inf or inf["mime"] not in ("image/jpeg", "image/png"):
            continue
        if min(inf["width"], inf["height"]) < min_px * 0.75 or max(inf["width"], inf["height"]) < min_px:
            continue
        if not licence_ok(inf["licence"]):
            continue
        cands.append(inf)
    tiles = []
    for n, c in enumerate(cands[:8]):
        try:
            data = np.frombuffer(get_bytes(c["thumb"]), np.uint8)
            img = cv2.imdecode(data, cv2.IMREAD_COLOR)
            img = cv2.resize(img, (320, 240), interpolation=cv2.INTER_AREA)
        except Exception:  # noqa: BLE001
            img = np.zeros((240, 320, 3), np.uint8)
        cv2.rectangle(img, (0, 0), (320, 26), (0, 0, 0), -1)
        cv2.putText(img, "%d %s" % (n, c["licence"][:20]), (4, 19), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (255, 255, 255), 1, cv2.LINE_AA)
        tiles.append(img)
        c["n"] = n
    while len(tiles) % 4:
        tiles.append(np.zeros((240, 320, 3), np.uint8))
    if tiles:
        sheet = np.vstack([np.hstack(tiles[i:i + 4]) for i in range(0, len(tiles), 4)])
        cv2.imwrite(os.path.join(outdir, "sheet.jpg"), sheet, [cv2.IMWRITE_JPEG_QUALITY, 80])
    json.dump(cands[:8], open(os.path.join(outdir, "candidates.json"), "w"), indent=1)
    print("%d licence-ok candidates (%d searched)" % (len(cands), len(titles)))


def crop43(img, fx, fy, zoom=1.0):
    """Largest 4:3 crop (optionally zoomed) centred as near as possible to (fx, fy) in 0..1."""
    h, w = img.shape[:2]
    if w / h > 4 / 3:
        cw, ch = int(h * 4 / 3), h
    else:
        cw, ch = w, int(w * 3 / 4)
    cw, ch = int(cw / zoom), int(ch / zoom)
    x0 = int(min(max(fx * w - cw / 2, 0), w - cw))
    y0 = int(min(max(fy * h - ch / 2, 0), h - ch))
    return img[y0:y0 + ch, x0:x0 + cw]


def fetch(manifest_path):
    man = json.load(open(manifest_path))
    game = man["game"]
    outdir = os.path.join(ROOT, "assets", "content", game)
    os.makedirs(outdir, exist_ok=True)
    titles = [e["file"] for e in man["items"].values()]
    infos = {}
    for i in range(0, len(titles), 40):
        infos.update(file_info(titles[i:i + 40], thumb_width=1920))
    media = {}
    for iid, e in man["items"].items():
        inf = infos.get(e["file"])
        if inf is None or not inf["url"]:
            print("MISSING", iid, e["file"])
            continue
        if not licence_ok(inf["licence"]):
            print("LICENCE REJECTED", iid, inf["licence"])
            continue
        src = inf["thumb"] if (inf["thumb"] and inf["width"] > 1920) else inf["url"]
        img = cv2.imdecode(np.frombuffer(get_bytes(src), np.uint8), cv2.IMREAD_COLOR)
        if e.get("rotate"):
            img = np.rot90(img, int(e["rotate"]) // 90 * -1).copy()
        img = crop43(img, e.get("fx", 0.5), e.get("fy", 0.5), e.get("zoom", 1.0))
        img = cv2.resize(img, (1600, 1200), interpolation=cv2.INTER_AREA if img.shape[1] >= 1600 else cv2.INTER_CUBIC)
        path = os.path.join(outdir, iid + ".jpg")
        cv2.imwrite(path, img, [cv2.IMWRITE_JPEG_QUALITY, 88])
        imp = path + ".import"
        if not os.path.exists(imp):
            open(imp, "w").write('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n\ncompress/mode=1\ncompress/lossy_quality=0.85\nmipmaps/generate=false\n')
        author = inf["author"] or "Unknown"
        media[iid] = {
            "asset_path": "res://assets/content/%s/%s.jpg" % (game, iid),
            "source": "Wikimedia Commons",
            "source_page": inf["page"],
            "original_url": inf["url"],
            "creator": author,
            "licence": inf["licence"],
            "licence_url": inf["licence_url"],
            "attribution_required": not inf["licence"].lower().startswith(("public domain", "pd", "cc0")),
            "attribution": "%s, %s, via Wikimedia Commons" % (author, inf["licence"]),
            "derivative_notes": "cropped to 4:3 and resized to 1600x1200 (tools/content/commons_media.py)",
            "approval_status": "approved",
            "art_status": "real_photo",
            "retrieved": time.strftime("%Y-%m-%d"),
        }
        print("ok", iid, inf["licence"], "-", author[:60])
    out = os.path.splitext(manifest_path)[0] + ".media.json"
    json.dump(media, open(out, "w"), indent=1, ensure_ascii=False)
    print("wrote", out)


if __name__ == "__main__":
    if sys.argv[1] == "search":
        search(sys.argv[2], sys.argv[3:])
    elif sys.argv[1] == "fetch":
        fetch(sys.argv[2])
