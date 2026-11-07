#!/usr/bin/env python3
"""Tron grid renderer for the rice: wallpaper, lock-screen video frames, the
Plymouth splash pieces and the GDM background all come from here, so they
share one horizon and one perspective.

    grid.py wallpaper OUT.png [W H]
    grid.py frames DIR [W H N]        one loop of the grid sliding toward you
    grid.py plymouth DIR              static sky + vertical lines, one line sprite
    grid.py avatar OUT.png            the X profile picture, arms at 90 degrees

Colours come from the palette file (~/.config/rice/palette) when present.
Only needs Pillow.
"""
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

# Geometry, all as fractions of the image so every size looks the same.
HORIZON = 0.55        # horizon height, from the top
CELL = 0.42           # cell size in world units; the camera sits 1 unit up and
                      # the nearest visible ground is 1 unit ahead
N_VERT = 80           # vertical lines each side of the centre
N_HORIZ = 120         # horizontal lines (the far ones fade into the horizon)
SS = 2                # supersampling for clean thin lines


def palette():
    """accent, bg, fg as RGB tuples."""
    cols = {"accent": "#ff1f3d", "bg": "#0a0506", "fg": "#ffe9eb"}
    path = os.path.expanduser("~/.config/rice/palette")
    if os.path.exists(path):
        for line in open(path):
            parts = line.split()
            if len(parts) >= 2 and parts[0] in cols and parts[1].startswith("#"):
                cols[parts[0]] = parts[1]
    rgb = lambda h: tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))
    return rgb(cols["accent"]), rgb(cols["bg"]), rgb(cols["fg"])


def horiz_rows(h, phase):
    """Screen y of each horizontal line for a phase in [0, 1). The nearest
    line starts just below the screen and the rest recede to the horizon."""
    hz = h * HORIZON
    below = h - hz          # focal length, so depth 1 lands on the bottom edge
    rows = []
    for k in range(N_HORIZ):
        z = 1 + (k - phase) * CELL
        if z > 0:
            rows.append(hz + below / z)
    return rows


def depth_fade(w, h):
    """Mask that dims lines toward the horizon, where they bunch up."""
    hz = int(h * HORIZON)
    col = Image.new("L", (1, h), 0)
    px = col.load()
    for y in range(hz, h):
        t = (y - hz) / max(h - hz, 1)
        px[0, y] = int(255 * min(1.0, 0.05 + 1.1 * t ** 0.7))
    return col.resize((w, h))


def lines_mask(w, h, phase, horizontal=True, vertical=True):
    """White-on-black line art at supersampled size, downscaled."""
    W, H = w * SS, h * SS
    hz = H * HORIZON
    img = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(img)
    lw = max(1, round(1.2 * SS * w / 1920))
    if vertical:
        for i in range(-N_VERT, N_VERT + 1):
            x_bottom = W / 2 + i * CELL * (H - hz)
            d.line([(W / 2, hz), (x_bottom, H)], fill=255, width=lw)
    if horizontal:
        for y in horiz_rows(H, phase):
            d.line([(0, y), (W, y)], fill=255, width=lw)
    return img.resize((w, h), Image.LANCZOS)


def glow(mask, w):
    """Soft halo plus the sharp line."""
    r = w / 1920
    wide = mask.filter(ImageFilter.GaussianBlur(9 * r))
    near = mask.filter(ImageFilter.GaussianBlur(2.5 * r))
    out = ImageChops.add(wide, wide)
    out = ImageChops.add(out, near)
    return ImageChops.lighter(out, mask)


def tint(mask, colour, gain=1.0):
    layer = Image.new("RGB", mask.size, colour)
    m = mask.point(lambda v: min(255, int(v * gain)))
    black = Image.new("RGB", mask.size, (0, 0, 0))
    return Image.composite(layer, black, m)


def sky(w, h, accent, bg):
    """Background with a faint red haze rising off the horizon."""
    img = Image.new("RGB", (w, h), bg)
    hz = int(h * HORIZON)
    haze = Image.new("L", (1, h), 0)
    px = haze.load()
    for y in range(h):
        dist = abs(y - hz) / h
        px[0, y] = int((70 if y < hz else 40) * max(0.0, 1 - dist * (6 if y < hz else 14)) ** 2)
    haze = haze.resize((w, h))
    return ImageChops.add(img, tint(haze, accent))


def horizon_line(w, h, accent, fg):
    hz = h * HORIZON
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).line([(0, hz), (w, hz)], fill=255, width=max(2, round(2 * w / 1920)))
    halo = m.filter(ImageFilter.GaussianBlur(14 * w / 1920))
    out = ImageChops.add(tint(halo, accent, 3.0), tint(m, accent))
    core = m.filter(ImageFilter.GaussianBlur(0.6))
    return ImageChops.add(out, tint(core, fg, 0.5))


def render(w, h, phase, accent, bg, fg, horizontal=True, vertical=True, with_horizon=True):
    base = sky(w, h, accent, bg)
    mask = lines_mask(w, h, phase, horizontal, vertical)
    mask = ImageChops.multiply(glow(mask, w), depth_fade(w, h))
    out = ImageChops.add(base, tint(mask, accent))
    if with_horizon:
        out = ImageChops.add(out, horizon_line(w, h, accent, fg))
    return out


def main(argv):
    accent, bg, fg = palette()
    if len(argv) < 3:
        sys.exit(__doc__)
    mode, out = argv[1], argv[2]
    if mode == "wallpaper":
        w, h = (int(argv[3]), int(argv[4])) if len(argv) > 4 else (2560, 1600)
        render(w, h, 0.0, accent, bg, fg).save(out)
    elif mode == "frames":
        w, h = (int(argv[3]), int(argv[4])) if len(argv) > 4 else (1920, 1200)
        n = int(argv[5]) if len(argv) > 5 else 60
        os.makedirs(out, exist_ok=True)
        # Everything but the moving lines is the same in each frame: draw it once.
        still = render(w, h, 0, accent, bg, fg, horizontal=False)
        fade = depth_fade(w, h)
        for i in range(n):
            mask = ImageChops.multiply(glow(lines_mask(w, h, i / n, vertical=False), w), fade)
            ImageChops.add(still, tint(mask, accent)).save(os.path.join(out, f"f{i:03d}.png"))
    elif mode == "plymouth":
        # Plymouth moves the horizontal lines itself (script splash), so it gets
        # the still parts and one glowing line strip to clone.
        os.makedirs(out, exist_ok=True)
        w, h = 1920, 1200
        render(w, h, 0, accent, bg, fg, horizontal=False).save(os.path.join(out, "grid.png"))
        sh = 24
        m = Image.new("L", (w, sh), 0)
        ImageDraw.Draw(m).line([(0, sh / 2), (w, sh / 2)], fill=255, width=2)
        strip = tint(glow(m, w), accent).convert("RGBA")
        strip.putalpha(glow(m, w))
        strip.save(os.path.join(out, "hline.png"))
        # Text is pre-rendered: the initramfs has no Orbitron.
        label(out, "prompt.png", "P A S S W O R D", 16, accent, fg, glow_only=True)
        Image.new("RGBA", (4, 4), accent + (255,)).save(os.path.join(out, "bar.png"))
        Image.new("RGBA", (10, 10), fg + (255,)).save(os.path.join(out, "dot.png"))
    elif mode == "avatar":
        avatar(accent, bg, fg).save(out)
    else:
        sys.exit(__doc__)


def label(out, name, text, size, accent, fg, glow_only=False):
    from PIL import ImageFont
    font = None
    for f in ("~/.local/share/fonts/Orbitron-VariableFont_wght.ttf",
              "/usr/share/fonts/truetype/orbitron/Orbitron-Bold.ttf",
              "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"):
        f = os.path.expanduser(f)
        if os.path.exists(f):
            font = ImageFont.truetype(f, size)
            try:
                font.set_variation_by_name("Bold")
            except Exception:
                pass
            break
    pad = size
    l, t, r, b = font.getbbox(text)
    w, h = r - l + 2 * pad, b - t + 2 * pad
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).text((pad - l, pad - t), text, font=font, fill=255)
    halo = m.filter(ImageFilter.GaussianBlur(size * 0.3))
    colour = Image.new("RGB", (w, h), fg if not glow_only else accent)
    img = Image.composite(colour, Image.new("RGB", (w, h), accent), m)
    alpha = ImageChops.lighter(m, halo.point(lambda v: min(255, v * 2)))
    img.putalpha(alpha)
    img.save(os.path.join(out, name))


def avatar(accent, bg, fg, size=512):
    """Two glowing bars crossing at right angles, corner to corner and past the
    edge, so the round crop cuts them like the X runs out of the frame."""
    W = size * SS
    m = Image.new("L", (W, W), 0)
    d = ImageDraw.Draw(m)
    over = W * 0.2
    lw = round(W * 0.022)
    d.line([(-over, -over), (W + over, W + over)], fill=255, width=lw)
    d.line([(W + over, -over), (-over, W + over)], fill=255, width=lw)
    m = m.resize((size, size), Image.LANCZOS)
    halo = m.filter(ImageFilter.GaussianBlur(size * 0.035))
    near = m.filter(ImageFilter.GaussianBlur(size * 0.008))
    img = Image.new("RGB", (size, size), bg)
    img = ImageChops.add(img, tint(halo, accent, 2.2))
    img = ImageChops.add(img, tint(near, accent, 1.6))
    core = m.filter(ImageFilter.MinFilter(3)) if size >= 256 else m
    return ImageChops.add(img, tint(core, fg, 0.85))


if __name__ == "__main__":
    main(sys.argv)
