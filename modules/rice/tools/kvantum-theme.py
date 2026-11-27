#!/usr/bin/env python3
"""Build the "Rice" Kvantum theme: a stock Kvantum theme recoloured to the palette.

    kvantum-theme.py <palette> <base theme dir> [<out dir>]

e.g. kvantum-theme.py ~/.config/rice/palette /usr/share/Kvantum/KvFlat
Default out dir: ~/.config/Kvantum/Rice (Rice.kvconfig + Rice.svg).

qt5ct only colours Qt widgets; Kvantum draws them from an SVG, so this is
what makes Qt apps look like the GTK side. Every colour in the base SVG and
kvconfig is mapped onto the palette:
  greys      by brightness onto the palette's dark-to-light ramp (black ...
             fg), interpolated between anchors, so the base theme's depth
             order (shadow < view < window < button < border < text) holds.
  colours    (the base theme's blue focus and selection) get the accent hue,
             their own brightness, and no more saturation than the accent,
             so a grey-accent palette stays grey.
[GeneralColors] is then set role by role, matching qt5ct's rice.conf.
"""

import colorsys
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

# Base theme grey level -> palette role. Anchors sit on KvFlat's own
# GeneralColors (dark 17, base 2e, window 3d, button 55, light 62, disabled a0).
RAMP = [
    (0x00, "black"), (0x17, "black"), (0x2e, "bg2"), (0x3d, "bg"), (0x46, "bg3"),
    (0x55, "card"), (0x64, "surface"), (0x7d, "select"), (0x96, "bright_black"),
    (0xa0, "dim"), (0xc8, "dim2"), (0xe6, "fg2"), (0xff, "fg"),
]

# Same role choices as files/qt5ct/colors/rice.conf, so Kvantum and qt5ct agree.
GENERAL = {
    "window.color": "bg", "base.color": "bg2", "alt.base.color": "bg",
    "button.color": "card", "light.color": "select", "mid.light.color": "surface",
    "dark.color": "black", "mid.color": "bg3",
    "highlight.color": "select", "inactive.highlight.color": "surface",
    "text.color": "fg", "window.text.color": "fg", "button.text.color": "fg",
    "disabled.text.color": "dim", "tooltip.text.color": "fg",
    "highlight.text.color": "fg", "link.color": "cyan", "link.visited.color": "teal",
}

GREY_SATURATION = 0.2
HEX = re.compile(r"#([0-9a-fA-F]{8}|[0-9a-fA-F]{6}|[0-9a-fA-F]{3})\b")
NAMED = re.compile(r"(?<==)(white|black)\b")


def palette(path):
    roles = {}
    for line in open(path):
        p = line.split()
        if len(p) >= 2 and not p[0].startswith(("#", "@")) and p[1].startswith("#"):
            roles[p[0]] = tuple(int(p[1][i:i + 2], 16) for i in (1, 3, 5))
    return roles


def hexrgb(rgb):
    return "#%02x%02x%02x" % tuple(round(c) for c in rgb)


def grey_to_palette(level, pal):
    for (lo, a), (hi, b) in zip(RAMP, RAMP[1:]):
        if level <= hi:
            t = (level - lo) / (hi - lo) if hi > lo else 0
            return tuple(x + (y - x) * t for x, y in zip(pal[a], pal[b]))
    return pal["fg"]


def mapper(pal):
    ah, as_, _ = colorsys.rgb_to_hsv(*(c / 255 for c in pal["accent"]))

    def colour(rgb):
        h, s, v = colorsys.rgb_to_hsv(*(c / 255 for c in rgb))
        if s < GREY_SATURATION:
            return grey_to_palette(sum(rgb) / 3, pal)
        return tuple(c * 255 for c in colorsys.hsv_to_rgb(ah, min(s, as_), v))

    def sub(m):
        h = m.group(1)
        if len(h) == 3:
            h = "".join(c * 2 for c in h)
        return hexrgb(colour(tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)))) + h[6:]

    return colour, sub


def build(pal_path, base, out):
    pal = palette(pal_path)
    base, out = Path(base), Path(out)
    name = base.name
    colour, sub = mapper(pal)

    svg = HEX.sub(sub, (base / f"{name}.svg").read_text())

    conf = HEX.sub(sub, (base / f"{name}.kvconfig").read_text())
    conf = NAMED.sub(lambda m: hexrgb(colour((255,) * 3 if m.group(1) == "white" else (0,) * 3)), conf)
    for key, role in GENERAL.items():
        line = f"{key}={hexrgb(pal[role])}"
        conf, n = re.subn(rf"^{re.escape(key)}=.*$", line, conf, flags=re.M)
        if not n:
            conf = conf.replace("[GeneralColors]\n", f"[GeneralColors]\n{line}\n", 1)

    out.mkdir(parents=True, exist_ok=True)
    (out / "Rice.svg").write_text(svg)
    (out / "Rice.kvconfig").write_text(conf)
    check(out, pal)
    print(f"    kvantum {out} from {name}")


def check(out, pal):
    """Kvantum silently falls back to its default theme on a bad file, so fail here instead."""
    ET.parse(out / "Rice.svg")
    conf = (out / "Rice.kvconfig").read_text()
    assert "[%General]" in conf and "[GeneralColors]" in conf, "kvconfig lost its sections"
    assert f"window.color={hexrgb(pal['bg'])}" in conf
    assert not NAMED.search(conf), "named colour left unmapped"


if __name__ == "__main__":
    if len(sys.argv) not in (3, 4):
        sys.exit(__doc__)
    build(sys.argv[1], sys.argv[2],
          sys.argv[3] if len(sys.argv) == 4 else Path.home() / ".config/Kvantum/Rice")
