#!/usr/bin/env python3
"""Build the "Rice" icon theme: Papirus-Dark with folders in the palette accent.

    folder-icons.py PALETTE [OUT_DIR]     default OUT_DIR ~/.local/share/icons/Rice

Papirus ships folders in fixed colours (folder.svg -> folder-blue.svg). This
takes its red set, swaps the red hexes for the palette's accent, and writes
them under the generic names (folder.svg, user-home.svg, folder-documents.svg;
16px folders are single-colour in Papirus, so they are left alone)
in a small theme that inherits Papirus-Dark for every other icon. Papirus
itself stays untouched in /usr/share, so no root and no papirus-folders tool.
"""
import configparser
import os
import re
import shutil
import sys

SRC = "/usr/share/icons/Papirus-Dark"
# Papirus red folder colours: front, back flap, emblem, paper.
FRONT, BACK, EMBLEM, PAPER = "#e25252", "#bf4b4b", "#4f1d1d", "#e4e4e4"


def palette(path):
    roles = {}
    for line in open(path):
        p = line.split()
        if len(p) > 1 and not p[0].startswith(("#", "@")):
            roles[p[0]] = p[1].lower()
    return roles


def shade(hex_, f):
    """Scale a colour toward black (f < 1) for the back flap."""
    r, g, b = (int(hex_[i:i + 2], 16) for i in (1, 3, 5))
    return "#%02x%02x%02x" % tuple(max(0, min(255, round(c * f))) for c in (r, g, b))


def main():
    roles = palette(sys.argv[1])
    out = os.path.expanduser(sys.argv[2] if len(sys.argv) > 2 else "~/.local/share/icons/Rice")
    accent = roles["accent"]
    swap = {
        FRONT: accent,
        BACK: shade(accent, 0.72),
        EMBLEM: shade(accent, 0.28),
        PAPER: roles.get("fg2", PAPER),
    }
    pattern = re.compile("|".join(map(re.escape, swap)), re.IGNORECASE)

    src_index = configparser.ConfigParser(interpolation=None)
    src_index.optionxform = str
    src_index.read(os.path.join(SRC, "index.theme"))

    # Rebuild from scratch so a palette switch leaves nothing stale.
    shutil.rmtree(out, ignore_errors=True)
    dirs = []
    for section in src_index.sections():
        if not section.endswith("/places") or "symbolic" in section:
            continue
        src_dir = os.path.join(SRC, section)
        if not os.path.isdir(src_dir):
            continue
        dst_dir = os.path.join(out, section)
        os.makedirs(dst_dir)
        written = 0
        for name in os.listdir(src_dir):
            link = os.path.join(src_dir, name)
            if not os.path.islink(link):
                continue
            target = os.readlink(link)
            # folder.svg -> folder-blue.svg, user-home.svg -> user-blue-home.svg.
            # Coloured aliases (folder-blue-desktop.svg) stay with Papirus.
            if "-blue" not in target or "-blue" in name:
                continue
            red = os.path.join(src_dir, target.replace("-blue", "-red", 1))
            if not os.path.isfile(red):
                continue
            svg = open(red).read()
            with open(os.path.join(dst_dir, name), "w") as f:
                f.write(pattern.sub(lambda m: swap[m.group(0).lower()], svg))
            written += 1
        if written:
            dirs.append(section)

    index = configparser.ConfigParser(interpolation=None)
    index.optionxform = str
    index["Icon Theme"] = {
        "Name": "Rice",
        "Comment": "Papirus-Dark with folders in the rice accent",
        "Inherits": "Papirus-Dark,Papirus,breeze-dark,hicolor",
        "Directories": ",".join(d for d in dirs if "@" not in d),
        "ScaledDirectories": ",".join(d for d in dirs if "@" in d),
    }
    for d in dirs:
        index[d] = dict(src_index[d])
    with open(os.path.join(out, "index.theme"), "w") as f:
        index.write(f, space_around_delimiters=False)
    print(f"    icons   {out} ({len(dirs)} dirs, folders {accent})")


if __name__ == "__main__":
    main()
