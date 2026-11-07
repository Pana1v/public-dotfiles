#!/usr/bin/env python3
"""Recolour the Ares-authored boot / greeter assets for another palette.

    recolor-assets.py <from.palette> <to.palette> <src_dir> <dst_dir>

Copies src_dir to dst_dir, then:
  PNG       hue-rotated from the source accent to the target accent; grey and
            near-grey pixels keep their hue, so black stays black.
  text      every source palette hex swapped for the same role's target hex,
            and Plymouth's float triples (r, g, b in 0..1) the same way.
Same palette on both sides: a plain copy.
"""

import colorsys
import re
import shutil
import sys
from pathlib import Path

from PIL import Image


def palette(path):
    roles = {}
    for line in open(path):
        parts = line.split()
        if len(parts) >= 2 and not parts[0].startswith(("#", "@")) and parts[1].startswith("#"):
            roles[parts[0]] = parts[1].lower()
    return roles


def rgb(h):
    return tuple(int(h[i:i + 2], 16) / 255 for i in (1, 3, 5))


def hue(h):
    return colorsys.rgb_to_hsv(*rgb(h))[0]


def recolor_png(path, shift):
    img = Image.open(path).convert("RGBA")
    r, g, b, a = img.split()
    h, s, v = Image.merge("RGB", (r, g, b)).convert("HSV").split()
    # Rotate hue only where there is colour (s > ~6%): greys and black stay put.
    turn = int(round(shift * 255)) % 256
    h_px, s_px = h.load(), s.load()
    for y in range(img.height):
        for x in range(img.width):
            if s_px[x, y] > 15:
                h_px[x, y] = (h_px[x, y] + turn) % 256
    out = Image.merge("HSV", (h, s, v)).convert("RGB")
    out.putalpha(a)
    out.save(path)


def recolor_text(path, swap, src, dst):
    text = path.read_text()
    new = re.sub("|".join(map(re.escape, swap)), lambda m: swap[m.group(0).lower()], text, flags=re.I)

    # Plymouth colours: "0.04, 0.02, 0.024" style triples close to a palette colour.
    def float_triple(m):
        vals = tuple(float(m.group(i)) for i in (1, 2, 3))
        for role, hx in src.items():
            if all(abs(a - b) < 0.012 for a, b in zip(vals, rgb(hx))):
                return "%.3f, %.3f, %.3f" % rgb(dst[role])
        return m.group(0)
    new = re.sub(r"(\d*\.\d+|[01])\s*,\s*(\d*\.\d+|[01])\s*,\s*(\d*\.\d+|[01])", float_triple, new)
    if new != text:
        path.write_text(new)


def main():
    src, dst = palette(sys.argv[1]), palette(sys.argv[2])
    src_dir, dst_dir = Path(sys.argv[3]), Path(sys.argv[4])
    if dst_dir.exists():
        shutil.rmtree(dst_dir)
    shutil.copytree(src_dir, dst_dir)
    if src == dst:
        return
    swap = {src[r]: dst[r] for r in src if r in dst}
    shift = (hue(dst["accent"]) - hue(src["accent"])) % 1.0
    for p in dst_dir.rglob("*"):
        if p.suffix.lower() == ".png":
            recolor_png(p, shift)
        elif p.suffix.lower() in (".css", ".txt", ".script", ".plymouth"):
            recolor_text(p, swap, src, dst)


if __name__ == "__main__":
    main()
