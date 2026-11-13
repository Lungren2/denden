#!/usr/bin/env python3
"""Den Den Mushi silhouette in side profile, facing left: the Den Den mark.

mushi.py [COLOUR] > mushi.svg"""
import math
import sys

FG = sys.argv[1] if len(sys.argv) > 1 else "#fff"

def zigzag(points, amp, waves):
    """Coiled cord: a zigzag along a quadratic Bezier."""
    (x0, y0), (cx, cy), (x1, y1) = points
    out = []
    n = waves * 2
    for i in range(n + 1):
        t = i / n
        x = (1-t)**2*x0 + 2*(1-t)*t*cx + t**2*x1
        y = (1-t)**2*y0 + 2*(1-t)*t*cy + t**2*y1
        dx = 2*(1-t)*(cx-x0) + 2*t*(x1-cx)
        dy = 2*(1-t)*(cy-y0) + 2*t*(y1-cy)
        l = math.hypot(dx, dy)
        nx, ny = -dy/l, dx/l
        s = 0 if i in (0, n) else (amp if i % 2 else -amp)
        out.append((x + nx*s, y + ny*s))
    return "M" + " L".join(f"{x:.1f} {y:.1f}" for x, y in out)

SX, SY, SR = 570, 530, 262          # shell
dial = []
for k in range(10):
    a = math.radians(-60 + k*30)     # finger holes, leaving a gap at the bottom right
    dial.append(f'<circle cx="{SX+68*math.cos(a):.1f}" cy="{SY+68*math.sin(a):.1f}" r="15" fill="black"/>')

svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <defs>
    <mask id="cut">
      <rect width="1024" height="1024" fill="white"/>
      <!-- rotary dial on the side of the shell -->
      <circle cx="{SX}" cy="{SY}" r="108" fill="none" stroke="black" stroke-width="16"/>
      {"".join(dial)}
      <circle cx="{SX}" cy="{SY}" r="30" fill="black"/>
      <!-- shell rim, separating the shell from the head and the foot -->
      <path d="M{SX-SR-9} {SY} A{SR+9} {SR+9} 0 0 0 {SX+SR*0.62:.0f} {SY+SR*0.83:.0f}" fill="none" stroke="black" stroke-width="16"/>
      <!-- handset resting on the shell -->
      <path d="M{SX-200} {SY-SR+58} A{SR+12} {SR+12} 0 0 1 {SX+200} {SY-SR+58}" fill="none" stroke="black" stroke-width="16"/>
      <!-- mouth -->
      <path d="M80 610 Q150 602 214 614" fill="none" stroke="black" stroke-width="16" stroke-linecap="round"/>
    </mask>
  </defs>
  <g fill="{FG}" mask="url(#cut)">
    <!-- foot: flat sole, rounded front, tapering tail -->
    <path d="M150 820 Q120 820 124 792 Q130 760 190 752 L820 742 Q900 740 960 790 Q975 806 950 812 L870 822 Z"/>
    <!-- head and neck -->
    <path d="M168 790 Q150 700 140 650 Q112 640 108 612 Q108 588 140 576 Q150 520 170 470
             Q190 410 250 400 Q320 396 336 470 Q348 560 340 760 Z"/>
    <!-- lips -->
    <ellipse cx="138" cy="584" rx="64" ry="34"/>
    <ellipse cx="150" cy="636" rx="58" ry="32"/>
    <!-- eye stalks and eyes -->
    <path d="M222 420 Q200 340 168 270" fill="none" stroke="{FG}" stroke-width="34" stroke-linecap="round"/>
    <circle cx="160" cy="248" r="46"/>
    <path d="M280 412 Q282 330 270 262" fill="none" stroke="{FG}" stroke-width="30" stroke-linecap="round"/>
    <circle cx="268" cy="238" r="40"/>
    <!-- shell -->
    <circle cx="{SX}" cy="{SY}" r="{SR}"/>
    <!-- handset along the top of the shell -->
    <path d="M{SX-150} {SY-SR-22} Q{SX} {SY-SR-110} {SX+150} {SY-SR-22}" fill="none" stroke="{FG}" stroke-width="44" stroke-linecap="round"/>
    <ellipse cx="{SX-172}" cy="{SY-SR+8}" rx="64" ry="34" transform="rotate(22 {SX-172} {SY-SR+8})"/>
    <ellipse cx="{SX+172}" cy="{SY-SR+8}" rx="64" ry="34" transform="rotate(-22 {SX+172} {SY-SR+8})"/>
    <!-- coiled cord from the handset down the back of the shell to the tail -->
    <path d="{zigzag(((SX+226, SY-SR+30), (SX+340, SY-40), (SX+330, 770)), 18, 8)}"
          fill="none" stroke="{FG}" stroke-width="13" stroke-linejoin="round" stroke-linecap="round"/>
  </g>
</svg>'''
print(svg)
