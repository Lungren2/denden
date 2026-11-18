#!/usr/bin/env python3
"""Den Den wallpaper: T3 Code's black canvas, with its fine grain and a faint
glow of its blue rising from below the bottom edge, behind the taskbar.

wallpaper.py WIDTH HEIGHT > wallpaper.ppm   (16-bit binary PPM)"""
import sys
import numpy as np

W, H = (int(a) for a in sys.argv[1:3])
rng = np.random.default_rng(7)
y, x = np.mgrid[0:H, 0:W].astype(np.float64)

def rgb(h):
    return np.array([int(h[i:i+2], 16) for i in (1, 3, 5)]) / 255.0

# An ellipse centred a quarter of the height below the screen, with radii
# of 70% of the width and 60% of the height, fading linearly to nothing at
# 70% of the way out (as CSS radial-gradient(70% 60% at 50% 125%, blue 45%,
# transparent 70%), eased in). The upper screen stays black.
dx = (x - W / 2) / (W * 0.70)
dy = (y - H * 1.25) / (H * 0.60)
t = np.clip(1 - np.hypot(dx, dy) / 0.70, 0, 1)
glow = t ** 1.4 * 0.45

img = rgb('#346bf1') * glow[..., None]
# The grain T3 lays over its canvas: about 3.5% noise, luma only.
img += rng.normal(0, 2.2 / 255, (H, W, 1))
img = np.clip(img, 0, 1)
out = np.round(img * 65535).astype('>u2')
sys.stdout.buffer.write(f'P6 {W} {H} 65535\n'.encode() + out.tobytes())
