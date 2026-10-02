#!/usr/bin/env python3
"""
Adds <category android:name="android.intent.category.LEANBACK_LAUNCHER"/> to the launcher
intent-filter of a Godot Android template APK's binary AndroidManifest.xml.

WHY: Godot 4.7's *non-Gradle* Android export ignores the `package/show_in_android_tv`
option (it is applied only by Gradle builds). The Mildew container cannot run Gradle (no
Android SDK access), so we patch the prebuilt template once; Godot then exports, aligns and
signs from it normally. On a machine with the Android SDK, a Gradle build with
show_in_android_tv=true makes this unnecessary. See DECISIONS.md.

usage: patch_tv_template.py <in.apk> <out.apk>
"""
import struct
import sys
import zipfile

LEANBACK = "android.intent.category.LEANBACK_LAUNCHER"
LAUNCHER = "android.intent.category.LAUNCHER"


def read_pool(buf, off):
    typ, hsize, size, count, styles, flags, sstart, stystart = struct.unpack_from("<HHIIIIII", buf, off)
    assert typ == 1 and styles == 0, "unexpected string pool"
    utf8 = bool(flags & 0x100)
    offs = list(struct.unpack_from("<%dI" % count, buf, off + hsize))
    base = off + sstart
    strings, raw = [], []
    for o in offs:
        p = base + o
        if utf8:
            start = p
            n = buf[p]; p += 2 if n & 0x80 else 1
            n = buf[p]
            if n & 0x80:
                n = ((n & 0x7F) << 8) | buf[p + 1]; p += 2
            else:
                p += 1
            s = buf[p:p + n].decode("utf-8"); end = p + n + 1
        else:
            start = p
            n = struct.unpack_from("<H", buf, p)[0]; p += 2
            s = buf[p:p + n * 2].decode("utf-16le"); end = p + n * 2 + 2
        strings.append(s); raw.append(bytes(buf[start:end]))
    return {"off": off, "size": size, "hsize": hsize, "flags": flags, "utf8": utf8, "strings": strings, "raw": raw}


def encode(s, utf8):
    if utf8:
        b = s.encode("utf-8")
        assert len(s) < 128 and len(b) < 128
        return bytes([len(s), len(b)]) + b + b"\x00"
    return struct.pack("<H", len(s)) + s.encode("utf-16le") + b"\x00\x00"


def build_pool(pool, extra):
    raws = pool["raw"] + [encode(extra, pool["utf8"])]
    count = len(raws)
    offs, data, cur = [], b"", 0
    for r in raws:
        offs.append(cur); data += r; cur += len(r)
    while len(data) % 4:
        data += b"\x00"
    hsize = 28
    sstart = hsize + 4 * count
    body = struct.pack("<%dI" % count, *offs) + data
    size = hsize + len(body)
    head = struct.pack("<HHIIIIII", 1, hsize, size, count, 0, pool["flags"], sstart, 0)
    return head + body, count - 1


def patch(manifest: bytes) -> bytes:
    buf = bytearray(manifest)
    pool = read_pool(buf, 8)
    if LEANBACK in pool["strings"]:
        return manifest
    new_pool, new_idx = build_pool(pool, LEANBACK)
    rest = bytes(buf[8 + pool["size"]:])
    out = bytearray(buf[:8]) + new_pool
    launcher_idx = pool["strings"].index(LAUNCHER)
    off = 0
    inserted = False
    while off < len(rest):
        typ, hsize, size = struct.unpack_from("<HHI", rest, off)
        chunk = rest[off:off + size]
        out += chunk
        if typ == 0x0102 and not inserted:
            attr_start, attr_size, attr_count = struct.unpack_from("<HHH", chunk, 24)
            for a in range(attr_count):
                ap = 16 + attr_start + a * attr_size
                raw_val = struct.unpack_from("<I", chunk, ap + 8)[0]
                if raw_val == launcher_idx:
                    end_size = struct.unpack_from("<I", rest, off + size + 4)[0]
                    end_chunk = rest[off + size:off + size + end_size]
                    clone = bytearray(chunk)
                    struct.pack_into("<I", clone, ap + 8, new_idx)
                    if clone[ap + 15] == 0x03:  # TYPE_STRING: data is the string index
                        struct.pack_into("<I", clone, ap + 16, new_idx)
                    out += end_chunk  # close the original LAUNCHER element
                    out += clone + end_chunk  # sibling LEANBACK_LAUNCHER element
                    off += size + end_size
                    inserted = True
                    break
            else:
                off += size
                continue
            continue
        off += size
    assert inserted, "LAUNCHER category not found"
    struct.pack_into("<I", out, 4, len(out))
    return bytes(out)


def main(src, dst):
    zin = zipfile.ZipFile(src)
    with zipfile.ZipFile(dst, "w") as zout:
        for info in zin.infolist():
            data = zin.read(info.filename)
            if info.filename == "AndroidManifest.xml":
                data = patch(data)
            zout.writestr(info, data, compress_type=info.compress_type)
    print("patched", dst)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
