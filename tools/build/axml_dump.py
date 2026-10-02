#!/usr/bin/env python3
"""Minimal Android binary XML (AXML) dumper for verifying exported APK manifests
without the Android SDK (aapt is unavailable in the Mildew build container).

Usage: axml_dump.py <apk> [--entry AndroidManifest.xml]
Prints elements with attributes, one per line, indented by depth.
"""
import struct, sys, zipfile

def parse_string_pool(buf, off):
    _type, hsize, size = struct.unpack_from('<HHI', buf, off)
    count, style_count, flags, strings_start, _styles_start = struct.unpack_from('<IIIII', buf, off + 8)
    utf8 = bool(flags & 0x100)
    offsets = struct.unpack_from('<%dI' % count, buf, off + hsize)
    base = off + strings_start
    out = []
    for o in offsets:
        p = base + o
        if utf8:
            n = buf[p]; p += 2 if n & 0x80 else 1
            n = buf[p]
            if n & 0x80:
                n = ((n & 0x7F) << 8) | buf[p + 1]; p += 2
            else:
                p += 1
            out.append(buf[p:p + n].decode('utf-8', 'replace'))
        else:
            n = struct.unpack_from('<H', buf, p)[0]; p += 2
            if n & 0x8000:
                n = ((n & 0x7FFF) << 16) | struct.unpack_from('<H', buf, p)[0]; p += 2
            out.append(buf[p:p + n * 2].decode('utf-16le', 'replace'))
    return out, off + size

def dump(buf):
    _t, hsize, _size = struct.unpack_from('<HHI', buf, 0)
    off = hsize
    strings = []
    depth = 0
    lines = []
    while off < len(buf):
        ctype, chsize, csize = struct.unpack_from('<HHI', buf, off)
        if ctype == 0x0001:
            strings, _ = parse_string_pool(buf, off)
        elif ctype == 0x0102:
            ns, name, astart, asize, acount = struct.unpack_from('<IIHHH', buf, off + 16)
            attrs = []
            p = off + 16 + astart
            for i in range(acount):
                ans, aname, araw, _sz, _r, dtype, data = struct.unpack_from('<IIIHBBI', buf, p + i * asize)
                key = strings[aname] if aname < len(strings) else '?'
                if araw != 0xFFFFFFFF:
                    val = strings[araw]
                elif dtype == 0x12:
                    val = 'true' if data else 'false'
                elif dtype in (0x10, 0x11):
                    val = str(data if data < 0x80000000 else data - 0x100000000)
                else:
                    val = '0x%x(t%d)' % (data, dtype)
                attrs.append('%s=%s' % (key, val))
            lines.append('  ' * depth + '<' + strings[name] + ' ' + ' '.join(attrs))
            depth += 1
        elif ctype == 0x0103:
            depth -= 1
        off += csize
    return lines

if __name__ == '__main__':
    entry = 'AndroidManifest.xml'
    if '--entry' in sys.argv:
        entry = sys.argv[sys.argv.index('--entry') + 1]
    data = zipfile.ZipFile(sys.argv[1]).read(entry)
    print('\n'.join(dump(data)))
