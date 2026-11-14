#!/usr/bin/env python3
"""Ember black hole for the rice: a ray-traced Schwarzschild hole sitting off
right of centre, light focus blur, fine film grain.

    blackhole.py base OUT.png [W H]      clean frame, no grain (the shader's input)
    blackhole.py still OUT.png [W H]     grained frame (wallpaper, GRUB, GDM)
    blackhole.py frames DIR [W H N]      one 10 s loop for the lock-screen video

The desktop and login screen run the same motion live in a shader
(blackhole-live@pan.local). animate() below is that shader written in numpy;
keep the two in step. Every motion term completes whole cycles in LOOP
seconds, so the video loops without a seam.

Units: Schwarzschild radius = 1. Rays follow a = -1.5 h^2 x / r^5, the
Newtonian form of the Schwarzschild null geodesic. The thin disk in y = 0 is
sampled on every crossing, so the lensed far side comes out on its own.
Colours come from ~/.config/rice/palette when present. Needs numpy and Pillow.
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

# Where the hole lands on screen (fractions of width / height) and the
# shadow's apparent radius (fraction of height), measured on base()'s output.
CENTER = (0.631, 0.570)
SHADOW_R = 0.240
LOOP = 10.0


def palette():
    cols = {"accent": "#ff1f3d", "bg": "#0a0506", "fg": "#ffe9eb", "orange": "#ff7a29"}
    path = os.path.expanduser("~/.config/rice/palette")
    if os.path.exists(path):
        for line in open(path):
            parts = line.split()
            if len(parts) >= 2 and parts[0] in cols and parts[1].startswith("#"):
                cols[parts[0]] = parts[1]
    return {k: np.array([int(v[i:i + 2], 16) for i in (1, 3, 5)], np.float32) / 255
            for k, v in cols.items()}


def ramp(t, pal):
    """Intensity to colour: black, ember, accent, orange, near white."""
    a, o, fg = pal["accent"], pal["orange"], pal["fg"]
    stops = [(0.00, np.zeros(3, np.float32)), (0.12, a * 0.23), (0.32, a * 0.64),
             (0.52, a), (0.72, o), (0.88, (o + fg) / 2), (1.00, fg)]
    t = np.clip(t, 0, 1)
    out = np.zeros(t.shape + (3,), np.float32)
    for (t0, c0), (t1, c1) in zip(stops[:-1], stops[1:]):
        m = (t >= t0) & (t <= t1)
        f = ((t[m] - t0) / (t1 - t0))[:, None]
        out[m] = c0 * (1 - f) + c1 * f
    return out


def smooth(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def disk_texture(rc, phi, seed=1):
    """Streaky turbulence, periodic in phi."""
    rng = np.random.default_rng(seed)
    lr = np.log(rc)
    f = np.zeros_like(rc)
    for _ in range(14):
        m = rng.integers(1, 24)
        k = rng.uniform(4, 30)
        f += rng.uniform(0.3, 1.0) / math.sqrt(m) * np.sin(m * phi + k * lr + rng.uniform(0, 6.28))
    fine = 0.5 + 0.5 * np.sin(90 * lr + 3 * np.sin(5 * phi))
    return np.clip(0.55 + 0.45 * f / 4.0, 0.05, 1.5) * (0.8 + 0.2 * fine)


def trace(W, H, dist=22.0, elev=9.0, fov=27.0, cx=0.42, cy=-0.30, rin=3.0, rout=16.0,
          gain=1.2, roll=-14.0):
    """Disk intensity per pixel (H x W)."""
    el = math.radians(elev)
    C = np.array([0, dist * math.sin(el), -dist * math.cos(el)], np.float32)
    f = -C / np.linalg.norm(C)
    right = np.cross([0, 1, 0], f).astype(np.float32)
    right /= np.linalg.norm(right)
    upc = np.cross(f, right)
    cr, sr = math.cos(math.radians(roll)), math.sin(math.radians(roll))
    right, upc = cr * right + sr * upc, -sr * right + cr * upc
    th = math.tan(math.radians(fov) / 2)
    xs = (np.arange(W) + 0.5) / W * 2 - 1
    ys = 1 - (np.arange(H) + 0.5) / H * 2
    u, v = np.meshgrid(xs * (W / H) * th - cx * th, ys * th - cy * th)
    d = f + u[..., None] * right + v[..., None] * upc
    d /= np.linalg.norm(d, axis=-1, keepdims=True)
    x = np.broadcast_to(C, d.shape).reshape(-1, 3).copy()
    vel = d.reshape(-1, 3).copy()
    N = x.shape[0]
    h2 = np.sum(np.cross(x, vel) ** 2, axis=1)
    I = np.zeros(N, np.float32)
    trans = np.ones(N, np.float32)
    alive = np.ones(N, bool)

    def acc(p, hh):
        r = np.linalg.norm(p, axis=1)
        return -1.5 * hh[:, None] * p / (r ** 5)[:, None]

    a = acc(x, h2)
    for _ in range(700):
        idx = np.nonzero(alive)[0]
        if idx.size == 0:
            break
        p, w, aa, hh = x[idx], vel[idx], a[idx], h2[idx]
        dt = np.clip((np.linalg.norm(p, axis=1) - 0.95) * 0.1, 0.015, 1.5)[:, None]
        pn = p + w * dt + 0.5 * aa * dt ** 2
        an = acc(pn, hh)
        wn = w + 0.5 * (aa + an) * dt
        ci = np.nonzero(p[:, 1] * pn[:, 1] < 0)[0]
        if ci.size:
            s = (p[ci, 1] / (p[ci, 1] - pn[ci, 1]))[:, None]
            pc = p[ci] + s * (pn[ci] - p[ci])
            rc = np.hypot(pc[:, 0], pc[:, 2])
            ok = (rc > rin * 0.92) & (rc < rout)
            ci, pc, rc = ci[ok], pc[ok], rc[ok]
            if ci.size:
                phi = np.arctan2(pc[:, 2], pc[:, 0])
                base = (rin / rc) ** 2 * smooth(rin * 0.92, rin * 1.25, rc) * (1 - smooth(rout * 0.6, rout, rc))
                tex = disk_texture(rc, phi)
                # Doppler beaming and gravitational redshift
                beta = np.minimum(np.sqrt(0.5 / np.maximum(rc - 0.5, 0.5)), 0.7)
                tang = np.stack([-pc[:, 2], np.zeros_like(rc), pc[:, 0]], 1) / rc[:, None]
                n = -w[ci] / np.linalg.norm(w[ci], axis=1, keepdims=True)
                g = np.sqrt(1 - beta ** 2) / (1 - beta * np.sum(tang * n, 1))
                g = g * np.sqrt(np.maximum(1 - 1 / rc, 0.05))
                gi = idx[ci]
                I[gi] += trans[gi] * gain * 2.2 * base * tex * g ** 3
                trans[gi] *= 1 - np.clip(0.9 * base * tex, 0, 0.95)
        x[idx], vel[idx], a[idx] = pn, wn, an
        rn = np.linalg.norm(pn, axis=1)
        alive[idx[(rn < 1.0) | ((rn > dist + 25) & (np.sum(pn * wn, 1) > 0))]] = False
    return I.reshape(H, W)


def base(W, H):
    """Clean Ember frame as floats (H x W x 3)."""
    pal = palette()
    w, h = W // 2, H // 2
    col = ramp(1 - np.exp(-trace(w, h) * 1.1), pal)
    im = Image.fromarray((np.clip(col, 0, 1) * 255).astype(np.uint8))
    b1 = np.asarray(im.filter(ImageFilter.GaussianBlur(w / 120)), np.float32) / 255
    b2 = np.asarray(im.filter(ImageFilter.GaussianBlur(w / 30)), np.float32) / 255
    col = col + 0.9 * (0.5 * b1 + 0.6 * b2) * pal["accent"] * 1.4
    yy, xx = np.mgrid[0:h, 0:w]
    rr = np.hypot((xx - w / 2) / (w / 2), (yy - h / 2) / (h / 2))
    col *= (1 - 0.2 * smooth(0.6, 1.5, rr))[..., None]
    col = np.maximum(col, pal["bg"] * 0.6)
    im = Image.fromarray((np.clip(col, 0, 1) * 255).astype(np.uint8))
    im = im.resize((W, H), Image.BICUBIC).filter(ImageFilter.GaussianBlur(W / 480))
    return np.asarray(im, np.float32) / 255


def grain(col, rng):
    n = rng.normal(0, 1, col.shape[:2]).astype(np.float32)[..., None]
    return col * (1 + 0.07 * n) + 0.004 * n


def animate(b, t, pal):
    """The shader in blackhole-live@pan.local, minus the grain."""
    H, W = b.shape[:2]
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    dx = ((xx + 0.5) / W - CENTER[0]) * (W / H) / SHADOW_R
    dy = ((yy + 0.5) / H - CENTER[1]) / SHADOW_R
    r = np.maximum(np.hypot(dx, dy), 0.05)
    phi = np.arctan2(dy, dx)
    lr = np.log(r)
    w = 2 * math.pi * t / LOOP
    # slow wobble of the whole glow around the hole
    a = 0.010 * np.sin(w + 3.0 * lr)
    ca, sa = np.cos(a), np.sin(a)
    sx = CENTER[0] * W + (ca * dx - sa * dy) * SHADOW_R * H - 0.5
    sy = CENTER[1] * H + (sa * dx + ca * dy) * SHADOW_R * H - 0.5
    x0 = np.clip(sx.astype(int), 0, W - 2); y0 = np.clip(sy.astype(int), 0, H - 2)
    fx = np.clip(sx - x0, 0, 1)[..., None]; fy = np.clip(sy - y0, 0, 1)[..., None]
    s = (b[y0, x0] * (1 - fx) * (1 - fy) + b[y0, x0 + 1] * fx * (1 - fy)
         + b[y0 + 1, x0] * (1 - fx) * fy + b[y0 + 1, x0 + 1] * fx * fy)
    # streaks orbiting the hole, inner ones faster
    st = (0.5 * np.sin(3 * phi + 5 * lr + 1.3 - 1 * w)
          + 0.3 * np.sin(7 * phi + 9 * lr + 4.1 - 3 * w)
          + 0.2 * np.sin(13 * phi + 14 * lr + 2.2 - 7 * w))
    # only on the glow: none inside the shadow, fading with distance
    m = smooth(0.85, 1.25, r) * np.exp(-np.maximum(r - 1.0, 0) / 3.0)
    lum = s @ np.array([0.3, 0.59, 0.11], np.float32)
    col = s * (1 + 0.5 * st * m)[..., None]
    col += pal["accent"] * (0.08 * np.maximum(st, 0) * m * smooth(0.05, 0.5, lum))[..., None]
    return col * (1 + 0.04 * math.sin(w))


def save(col, path):
    Image.fromarray((np.clip(col, 0, 1) * 255).astype(np.uint8)).save(path, optimize=True)


def main():
    cmd, out = sys.argv[1], sys.argv[2]
    W = int(sys.argv[3]) if len(sys.argv) > 3 else 1920
    H = int(sys.argv[4]) if len(sys.argv) > 4 else 1200
    if cmd == "base":
        save(base(W, H), out)
    elif cmd == "still":
        save(grain(base(W, H), np.random.default_rng(11)), out)
    elif cmd == "frames":
        n = int(sys.argv[5]) if len(sys.argv) > 5 else 240
        os.makedirs(out, exist_ok=True)
        b, pal, rng = base(W, H), palette(), np.random.default_rng(11)
        for i in range(n):
            save(grain(animate(b, i * LOOP / n, pal), rng), os.path.join(out, f"f{i:03d}.png"))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
