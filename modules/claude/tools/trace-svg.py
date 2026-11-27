"""Trace a picture into a pure-vector SVG body: brightness levels, each a
stack of 1-cell-high runs, coloured by the picture's mean colour at that level.

usage: trace-svg.py <image> <cell px> <levels> <out.svg>

blackhole-theme/hooks/ember.js was made from a 1309x1008 screenshot of the
ember wallpaper with: trace-svg.py shot.png 5 36 body.svg
"""
import sys

import numpy as np
from PIL import Image, ImageFilter

src, cell, levels, out = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
PAD = 3  # cells drawn past each edge so the blur does not darken the border

im = Image.open(src).convert('RGB')
W, H = im.size
im = im.filter(ImageFilter.GaussianBlur(cell / 3))  # drop the film grain
cols, rows = round(W / cell), round(H / cell)
small = np.asarray(im.resize((cols, rows), Image.BOX), dtype=float)
small = np.pad(small, ((PAD, PAD), (PAD, PAD), (0, 0)), mode='edge')
heat = small @ [0.3, 0.59, 0.11]

edges = np.linspace(heat.min(), heat.max(), levels + 1)
bg = small[heat < edges[1]].mean(axis=0)
hexc = lambda c: '#%02x%02x%02x' % tuple(int(round(v)) for v in c)

layers = []
for k in range(1, levels):
    band = (heat >= edges[k]) & (heat < edges[k + 1] if k + 1 < levels else True)
    if not band.any():
        continue
    colour = hexc(small[band].mean(axis=0))
    mask = heat >= edges[k]
    runs = []
    for y, row in enumerate(mask):
        d = np.diff(np.concatenate(([0], row.astype(int), [0])))
        for x0, x1 in zip(np.flatnonzero(d == 1), np.flatnonzero(d == -1)):
            runs.append(f'M{x0 - PAD} {y - PAD + 0.5}h{x1 - x0}')
    layers.append(f'<path stroke="{colour}" d="{"".join(runs)}"/>')

body = (f'<rect x="-50" y="-50" width="{W + 100}" height="{H + 100}" fill="{hexc(bg)}"/>'
        f'<g transform="scale({W / cols:.4f} {H / rows:.4f})"><g filter="url(#trace)" fill="none" stroke-width="1.02">'
        + ''.join(layers) + '</g></g>')
open(out, 'w').write(body)
print(f'{W}x{H} cells {cols}x{rows} layers {len(layers)} chars {len(body)}', file=sys.stderr)
