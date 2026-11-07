#!/usr/bin/env python3
"""Draw docs/images/themes.svg: one swatch row per rice palette.

    python3 lib/palette-svg.py     (re-run after adding or changing a palette)
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ROLES = ["bg", "card", "surface", "dim2", "fg", "accent", "cyan", "green", "yellow", "orange", "red", "magenta"]
SW, ROW, LABEL = 44, 52, 120

rows = []
for i, pal in enumerate(sorted((ROOT / "modules/rice/themes").glob("*.palette"))):
    roles = {}
    for line in pal.read_text().splitlines():
        parts = line.split()
        if len(parts) >= 2 and not parts[0].startswith(("#", "@")):
            roles[parts[0]] = parts[1]
    y = i * ROW
    rows.append(f'<rect x="0" y="{y}" width="{LABEL + SW * len(ROLES)}" height="{ROW - 6}" fill="{roles["bg"]}"/>')
    rows.append(f'<text x="14" y="{y + 29}" fill="{roles["fg"]}" font-family="monospace" font-size="15">{pal.stem}</text>')
    for j, role in enumerate(ROLES):
        if role in roles:
            rows.append(f'<rect x="{LABEL + j * SW}" y="{y + 8}" width="{SW - 6}" height="{ROW - 22}" fill="{roles[role]}"><title>{role} {roles[role]}</title></rect>')

w, h = LABEL + SW * len(ROLES), ROW * (len(rows) and i + 1) - 6
out = ROOT / "docs/images/themes.svg"
out.write_text(f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">\n' + "\n".join(rows) + "\n</svg>\n")
print(out)
