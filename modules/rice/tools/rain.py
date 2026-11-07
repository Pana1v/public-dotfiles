#!/usr/bin/env python3
"""Digital rain for the lock screen: one seamless loop of falling glyph columns.

    rain.py frames DIR [W H N]     writes DIR/f000.png ... (N frames, default 240)
    rain.py still OUT.png [W H]    one frame, for previews

Glyphs sit on a fixed grid; each column has a few drops whose bright heads fall
an exact whole number of loop lengths over the N frames, so frame N wraps to
frame 0 with no jump. A soft dark veil sits where GNOME's unlock prompt draws
(centre column), so the name and entry stay readable.

Colours come from the palette file (~/.config/rice/palette), like grid.py.
Needs Pillow and a font with katakana (Noto Sans CJK).
"""
import os
import random
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

GLYPHS = "ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ0123456789Z:."
CELL = 24          # px per glyph cell at 1200 high; scales with the image height
TRAIL = 22         # glyphs lit behind each head
SEED = 1999


def palette():
    cols = {"accent": "#00ff41", "bg": "#000000", "fg": "#b6ffb6"}
    path = os.environ.get("RICE_PALETTE") or os.path.expanduser("~/.config/rice/palette")
    if os.path.exists(path):
        for line in open(path):
            p = line.split()
            if len(p) >= 2 and p[0] in cols and p[1].startswith("#"):
                cols[p[0]] = p[1]
    rgb = lambda h: tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))
    return rgb(cols["accent"]), rgb(cols["bg"]), rgb(cols["fg"])


def cjk_font(size):
    try:
        path = subprocess.run(["fc-match", "-f", "%{file}", ":lang=ja"],
                              capture_output=True, text=True).stdout.strip()
        return ImageFont.truetype(path, size)
    except Exception:
        return ImageFont.load_default()


def mix(a, b, t):
    return tuple(int(x + (y - x) * t) for x, y in zip(a, b))


class Rain:
    def __init__(self, w, h, n):
        self.w, self.h, self.n = w, h, n
        self.cell = max(12, round(CELL * h / 1200))
        self.cols, self.rows = w // self.cell + 1, h // self.cell + 1
        self.accent, self.bg, self.fg = palette()
        rnd = random.Random(SEED)
        self.grid = [[rnd.choice(GLYPHS) for _ in range(self.rows)] for _ in range(self.cols)]
        # flicker: a few cells swap glyph at fixed frames inside the loop
        # (start frame, length) inside the loop, wrapping, so frame n == frame 0
        self.flips = {(rnd.randrange(self.cols), rnd.randrange(self.rows)):
                      (rnd.randrange(n), rnd.randint(n // 8, n // 3), rnd.choice(GLYPHS))
                      for _ in range(self.cols * self.rows // 25)}
        span = self.rows + TRAIL
        self.drops = []
        for c in range(self.cols):
            for _ in range(rnd.choice((1, 1, 2))):
                laps = rnd.choice((1, 1, 2, 2, 3))   # whole loops per video: seamless
                self.drops.append((c, rnd.uniform(0, span), laps, rnd.randint(TRAIL // 2, TRAIL)))
        self.span = span
        # glyph sprites per brightness level, drawn once
        f = cjk_font(int(self.cell * 0.9))
        self.levels = 24
        self.sprites = {}
        for g in set(GLYPHS):
            for lv in range(self.levels + 1):
                t = lv / self.levels
                col = self.fg if lv == self.levels else mix(self.bg, self.accent, 0.12 + 0.88 * t ** 1.6)
                im = Image.new("RGB", (self.cell, self.cell), self.bg)
                ImageDraw.Draw(im).text((self.cell / 2, self.cell / 2), g, font=f, fill=col, anchor="mm")
                self.sprites[g, lv] = im
        self.veil = self._veil()

    def _veil(self):
        """Dark soft panel where the unlock prompt sits (alpha mask)."""
        m = Image.new("L", (self.w, self.h), 0)
        d = ImageDraw.Draw(m)
        cx = self.w / 2
        d.rectangle((cx - self.w * 0.21, self.h * 0.36, cx + self.w * 0.21, self.h * 0.76), fill=235)
        d.rectangle((cx - self.w * 0.17, self.h * 0.12, cx + self.w * 0.17, self.h * 0.33), fill=170)  # clock
        return m.filter(ImageFilter.GaussianBlur(self.h * 0.04))

    def frame(self, i):
        img = Image.new("RGB", (self.w, self.h), self.bg)
        lit = {}
        i %= self.n
        for c, start, laps, length in self.drops:
            head = (start + laps * self.span * i / self.n) % self.span
            hr = int(head)
            for k in range(length):
                r = hr - k
                if 0 <= r < self.rows:
                    lv = self.levels if k == 0 else int((self.levels - 1) * (1 - k / length))
                    if lv > lit.get((c, r), -1):
                        lit[c, r] = lv
        for (c, r), lv in lit.items():
            g = self.grid[c][r]
            flip = self.flips.get((c, r))
            if flip and (i - flip[0]) % self.n < flip[1]:
                g = flip[2]
            img.paste(self.sprites[g, lv], (c * self.cell, r * self.cell))
        dark = Image.new("RGB", (self.w, self.h), self.bg)
        return Image.composite(dark, img, self.veil)


def main(argv):
    if len(argv) < 3 or argv[1] not in ("frames", "still"):
        sys.exit(__doc__)
    w = int(argv[3]) if len(argv) > 4 else 1920
    h = int(argv[4]) if len(argv) > 4 else 1200
    if argv[1] == "still":
        Rain(w, h, 240).frame(90).save(argv[2])
        return
    n = int(argv[5]) if len(argv) > 5 else 240
    os.makedirs(argv[2], exist_ok=True)
    rain = Rain(w, h, n)
    for i in range(n):
        rain.frame(i).save(os.path.join(argv[2], f"f{i:03d}.png"))


if __name__ == "__main__":
    main(sys.argv)
