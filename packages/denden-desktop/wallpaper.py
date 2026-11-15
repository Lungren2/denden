#!/usr/bin/env python3
"""Den Den wallpaper: near black, with the lit edge of one huge ring (the
dial's ring, seen up close) curving across the lower right. Light falls off
softly inside the ring and sharply outside it, with a crisp rim, and fine
grain dithers the gradients so they don't band.

wallpaper.py WIDTH HEIGHT > wallpaper.ppm   (16-bit binary PPM)"""
import sys
import numpy as np

W, H = (int(a) for a in sys.argv[1:3])
rng = np.random.default_rng(7)
y, x = np.mgrid[0:H, 0:W].astype(np.float64) / H     # height units

def rgb(h):
    return np.array([int(h[i:i+2], 16) for i in (1, 3, 5)]) / 255.0

# The ring: centre below and right of the screen, so its top-left arc shows.
cx, cy, R = W / H * 0.86, 1.62, 1.18
dx, dy = x - cx, y - cy
d = np.hypot(dx, dy) - R                    # signed: >0 outside the ring
theta = np.arctan2(dy, dx)                  # -pi..0 across the visible arc

inner = np.exp(-np.clip(-d, 0, None) / 0.22) * (d < 0)     # light falling inward
outer = np.exp(-(np.clip(d, 0, None) / 0.035) ** 2) * (d >= 0)
halo = np.exp(-np.abs(d) / 0.42) * 0.22                    # wide, faint
# The crisp edge, brightest where the arc crests and fading towards its ends.
crest = np.clip(np.cos((theta + np.pi * 0.47) * 1.25), 0, 1) ** 1.6
rim = (np.exp(-(d / 0.0045) ** 2) * 0.30 + np.exp(-(d / 0.016) ** 2) * 0.10) * crest
glow = (inner + outer) * 0.62 + halo

# Colour along the arc: violet low on the left, blue over the top, a cooler
# cyan-blue as it turns down the right.
t = np.clip((theta + np.pi) / (np.pi * 0.62), 0, 1)[..., None]
violet, blue, cyan = rgb('#6b4bff'), rgb('#3f6bff'), rgb('#4fa8ff')
col = np.where(t < 0.55, violet + (blue - violet) * (t / 0.55),
               blue + (cyan - blue) * ((t - 0.55) / 0.45))

base = rgb('#06070b') + (rgb('#0b0d14') - rgb('#06070b')) * (y / y.max())[..., None]
img = base + col * glow[..., None] * 0.55 + rgb('#d9e2ff') * rim[..., None]
img = np.clip(img, 0, 1)
img += rng.normal(0, 1.4 / 255, (H, W, 1))                  # grain, luma only
out = np.clip(np.round(img * 65535), 0, 65535).astype('>u2')
sys.stdout.buffer.write(f'P6 {W} {H} 65535\n'.encode() + out.tobytes())
