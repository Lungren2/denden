#!/usr/bin/env python3
"""The Den Den mark: a Den Den Mushi in side profile, facing left, with the
receiver on its shell. Solid shapes on a 512 grid, stacked back to front;
each shape cuts a gap of one width into the shapes behind it, and smaller
cuts inside a shape draw its detail (dial, coils, eyelid).

mushi.py [COLOUR] [--small] > mushi.svg
  --small  for 32 px and below: wider gaps, a simpler dial and no eyelid"""
import math
import sys

args = [a for a in sys.argv[1:] if not a.startswith("--")]
FG = args[0] if args else "#fff"
SMALL = "--small" in sys.argv
G = 22 if SMALL else 13            # the gap width
f = lambda v: f"{v:.1f}"

BASE = 430                          # the sole
SX, SY, SR = 304, 292, 124          # shell

# Body: head, neck and foot as one shape. The front of the neck bows out
# gently into the toe; the sole is flat; the tail tapers to a soft point and
# its top curves up into the back of the shell.
TAIL = 494
body = (f'<path d="M110 {BASE} Q88 {BASE} 88 {BASE-17} Q88 {BASE-38} 118 {BASE-44} '
        f'C142 {BASE-50} 150 {BASE-66} 144 {BASE-92} '
        f'C128 {BASE-148} 86 {BASE-196} 78 {BASE-240} '
        f'C72 {BASE-276} 98 {BASE-296} 130 {BASE-294} '
        f'C166 {BASE-292} 186 {BASE-264} 192 {BASE-232} '
        f'L{SX-20} {BASE-70} L{SX+86} {BASE-80} '
        f'C{SX+112} {BASE-44} {TAIL-74} {BASE-28} {TAIL-18} {BASE-17} '
        f'Q{TAIL} {BASE-13} {TAIL} {BASE-7} Q{TAIL} {BASE} {TAIL-20} {BASE} Z"/>')

# Eye: one thick stalk straight up from the crown (the far one is hidden in
# profile), a round eye, and a heavy lid cut across it.
EX, EY, ER = 132, 58, 33
CROWN = BASE - 294
body += (f'<path d="M{EX} {CROWN+30} L{EX} {EY}" fill="none" stroke-width="24" '
         f'stroke-linecap="round"/>')
eye = f'<circle cx="{EX}" cy="{EY}" r="{ER}"/>'
lid = (f'<path d="M{EX-ER-4} {EY-3} Q{EX} {EY+9} {EX+ER+4} {EY-3}" fill="none" '
       f'stroke-width="{f(G*0.7)}" stroke-linecap="round"/>')

# Receiver: a cup standing on the top of the shell, and its cap.
def trapezoid(x0, x1, y0, x2, x3, y1, rad, grow=0):
    """Bottom edge x0..x1 at y0, top edge x2..x3 at y1. Stroking rounds the
    corners; `grow` widens the stroke, for the gap it cuts behind it."""
    return (f'<path d="M{x0} {y0} L{x1} {y0} L{x3} {y1} L{x2} {y1} Z" '
            f'stroke-width="{2*(rad+grow)}" stroke-linejoin="round"/>')
CUP = (SX-100, SX+100, 196, SX-80, SX+80, 136, 10)
CAP = (SX-50, SX+50, 136-G, SX-42, SX+42, 136-G-16, 8)

# Cord: a band around the back of the shell from the receiver down into the
# tail, with slanted cuts for its coils.
CW = 34 if SMALL else 26            # band width
CR = SR + G + CW / 2                # its centreline radius
A0, A1 = -74, 58                    # degrees, receiver end to tail end
def polar(a, r):
    return (SX + r*math.cos(math.radians(a)), SY + r*math.sin(math.radians(a)))
p0, p1 = polar(A0, CR), polar(A1, CR)
cord = (f'<path d="M{f(p0[0])} {f(p0[1])} A{f(CR)} {f(CR)} 0 0 1 {f(p1[0])} {f(p1[1])}" '
        f'fill="none" stroke-width="{CW}" stroke-linecap="round"/>')
def coils():
    step = 17 if SMALL else 10.5
    s, a = '', A0 + step
    while a < A1 - step / 2:
        i, o = polar(a - 3.5, CR - CW), polar(a + 3.5, CR + CW)
        s += (f'<path d="M{f(i[0])} {f(i[1])} L{f(o[0])} {f(o[1])}" fill="none" '
              f'stroke-width="{f(G*0.55)}"/>')
        a += step
    return s

# Dial: a ring with nine finger holes inside it, leaving the gap where the
# finger stop is, and a hub. The small mark keeps the ring and a larger hub.
def dial():
    s = f'<circle cx="{SX}" cy="{SY}" r="{f(SR*0.5)}" fill="none" stroke-width="{f(G*0.6)}"/>'
    if SMALL:
        return s + f'<circle cx="{SX}" cy="{SY}" r="{f(SR*0.2)}"/>'
    for k in range(9):
        a = math.radians(100 + k*31)
        s += (f'<circle cx="{f(SX + SR*0.33*math.cos(a))}" cy="{f(SY + SR*0.33*math.sin(a))}" '
              f'r="{f(SR*0.068)}"/>')
    return s + f'<circle cx="{SX}" cy="{SY}" r="{f(SR*0.11)}"/>'

def grown(markup):
    """A shape grown by the gap: what it cuts out of the shapes behind it."""
    return f'<g stroke-width="{2*G}" stroke-linejoin="round">{markup}</g>'

# Back to front: (shape, what it cuts behind it, its own inner cuts).
layers = [
    (cord, None, coils()),
    (body, grown(body), ''),
    (eye, grown(eye), '' if SMALL else lid),
    (f'<circle cx="{SX}" cy="{SY}" r="{SR}"/>', grown(f'<circle cx="{SX}" cy="{SY}" r="{SR}"/>'), dial()),
    (trapezoid(*CUP), trapezoid(*CUP, grow=G), ''),
    (trapezoid(*CAP), trapezoid(*CAP, grow=G), ''),
]

defs = out = ''
for i, (shape, _, inner) in enumerate(layers):
    cuts = ''.join(l[1] for l in layers[i+1:]) + inner
    defs += (f'<mask id="m{i}" maskUnits="userSpaceOnUse" x="0" y="0" width="512" height="512">'
             f'<rect width="512" height="512" fill="#fff"/>'
             f'<g fill="#000" stroke="#000">{cuts}</g></mask>')
    out += f'<g mask="url(#m{i})" fill="{FG}" stroke="{FG}" stroke-width="0">{shape}</g>'
print(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">'
      f'<defs>{defs}</defs>{out}</svg>')
