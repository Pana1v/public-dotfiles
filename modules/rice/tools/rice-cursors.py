#!/usr/bin/env python3
"""Build the "Rice" cursor theme: a cursor theme recoloured to the palette accent.

    rice-cursors.py <palette> <source theme dir> [<out dir>]

Default out dir: ~/.local/share/icons/Rice-cursors. Xcursor files hold plain
premultiplied ARGB frames, so each coloured pixel is hue-rotated from the
source theme's main hue to the accent; greys (outlines, shadows) are left
alone. Shapes, hotspots and animation timing are untouched. Symlinked cursor
names are copied as links.
"""

import colorsys
import os
import shutil
import struct
import sys
from pathlib import Path

IMAGE = 0xFFFD0002


def accent(palette):
    for line in open(palette):
        p = line.split()
        if len(p) >= 2 and p[0] == "accent":
            return colorsys.rgb_to_hsv(*(int(p[1][i:i + 2], 16) / 255 for i in (1, 3, 5)))
    raise SystemExit("palette has no accent")


def frames(data):
    """Yield (pixel offset, pixel count) for every image chunk."""
    _magic, _hsize, _ver, ntoc = struct.unpack_from("<4sIII", data, 0)
    for i in range(ntoc):
        typ, _sub, pos = struct.unpack_from("<III", data, 16 + 12 * i)
        if typ == IMAGE:
            hsize, _t, _s, _v, w, h = struct.unpack_from("<IIIIII", data, pos)
            yield pos + hsize, w * h


def pixels(data):
    for off, n in frames(data):
        for i in range(n):
            yield off + 4 * i, struct.unpack_from("<I", data, off + 4 * i)[0]


def unpremul(px):
    a = px >> 24
    if a == 0:
        return 0, 0, 0, 0
    return a, min(255, ((px >> 16) & 255) * 255 // a), min(255, ((px >> 8) & 255) * 255 // a), min(255, (px & 255) * 255 // a)


def main_hue(files):
    """Average hue (circular mean) and saturation of the theme's coloured pixels."""
    import math
    sx = sy = st = 0.0
    n = 0
    for f in files:
        data = f.read_bytes()
        for _o, px in pixels(data):
            a, r, g, b = unpremul(px)
            if a < 128:
                continue
            h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            if s > 0.35 and v > 0.3:
                sx += math.cos(2 * math.pi * h) * s
                sy += math.sin(2 * math.pi * h) * s
                st += s
                n += 1
    return (math.atan2(sy, sx) / (2 * math.pi)) % 1.0, (st / n if n else 1.0)


def recolor(data, shift, sat_scale):
    buf = bytearray(data)
    for off, px in pixels(data):
        a, r, g, b = unpremul(px)
        if a == 0:
            continue
        h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
        if s < 0.12:
            continue  # greys: outline, shadow, white fill
        h = (h + shift) % 1.0
        s = min(1.0, s * sat_scale)
        r2, g2, b2 = (round(c * 255) for c in colorsys.hsv_to_rgb(h, s, v))
        pm = lambda c: c * a // 255
        struct.pack_into("<I", buf, off, (a << 24) | (pm(r2) << 16) | (pm(g2) << 8) | pm(b2))
    return bytes(buf)


def main():
    palette, src = sys.argv[1], Path(sys.argv[2])
    out = Path(sys.argv[3]) if len(sys.argv) > 3 else Path.home() / ".local/share/icons/Rice-cursors"
    th, ts, _tv = accent(palette)
    src_cursors = src / "cursors"
    real = [f for f in src_cursors.iterdir() if f.is_file() and not f.is_symlink()]
    src_h, src_s = main_hue(real)
    shift = (th - src_h) % 1.0
    sat_scale = ts / src_s if src_s else 1.0

    tmp = out.with_name(out.name + ".tmp")
    shutil.rmtree(tmp, ignore_errors=True)
    (tmp / "cursors").mkdir(parents=True)
    for f in src_cursors.iterdir():
        dst = tmp / "cursors" / f.name
        if f.is_symlink():
            os.symlink(os.readlink(f), dst)
        elif f.read_bytes()[:4] == b"Xcur":
            dst.write_bytes(recolor(f.read_bytes(), shift, sat_scale))
        else:
            shutil.copy2(f, dst)
    (tmp / "index.theme").write_text(
        "[Icon Theme]\nName=Rice-cursors\nComment=%s recoloured to the rice accent\n" % src.name)
    shutil.rmtree(out, ignore_errors=True)
    tmp.rename(out)
    print(f"    cursors Rice-cursors from {src.name}")


if __name__ == "__main__":
    main()
