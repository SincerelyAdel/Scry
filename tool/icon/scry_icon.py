"""Draws the Scry icon on white: an unfinished circle built from many
separate gold and purple brush strokes with splatter, and sparkles painted
as strokes too."""
import math
import random
import sys

SEED = int(sys.argv[2]) if len(sys.argv) > 2 else 11
random.seed(SEED)
CX, CY, R = 512, 470, 265

GOLDS = ['#c9a227', '#d4ae3a', '#b8892a', '#e0b93e', '#a87f1f']
PURPLES = ['#7b4fc9', '#8a5cd6', '#6a3fb5', '#9b6bdf', '#5b33a0']

out = []


def poly_stroke(center, widths, color, opacity=1.0):
    """A filled brush shape around a centre line, width varying per point."""
    left, right = [], []
    n = len(center)
    for i, (x, y) in enumerate(center):
        x0, y0 = center[max(i - 1, 0)]
        x1, y1 = center[min(i + 1, n - 1)]
        dx, dy = x1 - x0, y1 - y0
        L = math.hypot(dx, dy) or 1
        nx, ny = -dy / L, dx / L
        w = widths[i] / 2
        # Ragged edges: each side jitters on its own.
        wl = w * random.uniform(0.85, 1.12)
        wr = w * random.uniform(0.85, 1.12)
        left.append((x + nx * wl, y + ny * wl))
        right.append((x - nx * wr, y - ny * wr))
    pts = left + right[::-1]
    d = 'M' + ' L'.join(f'{x:.1f} {y:.1f}' for x, y in pts) + ' Z'
    out.append(f'<path d="{d}" fill="{color}" opacity="{opacity:.2f}"/>')


def profile(t, peak, press, lift, wob):
    """Brush pressure along a stroke: lands, swells, lifts off."""
    a = min(1.0, t / press) ** 0.7
    b = 1.0 if t < 1 - lift else max(0.0, (1 - t) / lift) ** 1.3
    return max(0.6, peak * a * b * (1 + wob * math.sin(t * random.uniform(7, 13))))


def arc_stroke(color, r, start, sweep, peak, n=160, dry=True, opacity=1.0,
               sx=1.0, sy=1.0, ox=0.0, oy=0.0, splash=True):
    """One brush stroke around part of an ellipse (sx, sy squash it;
    ox, oy move it)."""
    press = random.uniform(0.03, 0.12)
    lift = random.uniform(0.2, 0.45)
    wob = random.uniform(0.08, 0.25)
    wr = random.uniform(4, 14)
    fr = random.uniform(3, 7)
    ph = random.uniform(0, 6)
    pts, ws = [], []
    for i in range(n + 1):
        t = i / n
        a = start + sweep * t
        rr = r + wr * math.sin(t * fr + ph)
        pts.append((CX + ox + sx * rr * math.cos(a), CY + oy + sy * rr * math.sin(a)))
        ws.append(profile(t, peak, press, lift, wob))
    poly_stroke(pts, ws, color, opacity)
    if dry:
        # Bristle gaps: white hairlines through the drying tail.
        for _ in range(random.randint(2, 5)):
            off = random.uniform(-0.35, 0.35)
            b = random.uniform(0.4, 0.75)
            e = random.uniform(b + 0.15, 1.0)
            seg = []
            for i in range(int(n * b), int(n * e)):
                t = i / n
                a = start + sweep * t
                rr = r + wr * math.sin(t * fr + ph) + ws[i] * off
                seg.append((CX + ox + sx * rr * math.cos(a), CY + oy + sy * rr * math.sin(a)))
            if len(seg) > 2:
                d = 'M' + ' L'.join(f'{x:.1f} {y:.1f}' for x, y in seg)
                out.append(f'<path d="{d}" fill="none" stroke="#fff" '
                           f'stroke-width="{random.uniform(1.5, 4.5):.1f}" stroke-linecap="round" '
                           f'opacity="{random.uniform(0.5, 0.95):.2f}"/>')
    if not splash:
        return
    # Where the brush lands, it throws paint; where it lifts, it flicks.
    a0 = start
    splat(CX + r * math.cos(a0), CY + r * math.sin(a0), color, peak * 1.4, random.randint(5, 12), 3, 11)
    a1 = start + sweep
    tang = a1 + math.copysign(math.pi / 2, sweep)
    flick(CX + r * math.cos(a1), CY + r * math.sin(a1), tang, color, peak)


def splat(x, y, color, spread, count, rmin, rmax):
    for _ in range(count):
        ang = random.uniform(0, 2 * math.pi)
        dist = spread * random.uniform(0.3, 1.3)
        rr = random.uniform(rmin, rmax) * random.choice([0.4, 0.6, 1, 1])
        out.append(f'<circle cx="{x + dist * math.cos(ang):.1f}" cy="{y + dist * math.sin(ang):.1f}" '
                   f'r="{rr:.1f}" fill="{color}" opacity="{random.uniform(0.7, 1):.2f}"/>')


def flick(x, y, ang, color, peak):
    """Droplets thrown off the end of a stroke, in the direction it moved."""
    for _ in range(random.randint(3, 7)):
        a = ang + random.uniform(-0.45, 0.45)
        d = random.uniform(20, 90)
        L = random.uniform(8, 26)
        w = random.uniform(3, 9)
        px, py = x + d * math.cos(a), y + d * math.sin(a)
        rot = math.degrees(a)
        out.append(f'<ellipse cx="{px:.1f}" cy="{py:.1f}" rx="{L:.1f}" ry="{w / 2:.1f}" '
                   f'transform="rotate({rot:.1f} {px:.1f} {py:.1f})" fill="{color}"/>')


def drip(color, ang, r, length):
    """Paint running down from the bottom of the ring."""
    x, y = CX + r * math.cos(ang), CY + r * math.sin(ang)
    pts = [(x + random.uniform(-2, 2), y + length * t) for t in [i / 30 for i in range(31)]]
    ws = [10 * (1 - t) ** 0.4 + 3 for t in [i / 30 for i in range(31)]]
    poly_stroke(pts, ws, color)
    out.append(f'<circle cx="{pts[-1][0]:.1f}" cy="{pts[-1][1] + 4:.1f}" r="7" fill="{color}"/>')


def star_strokes(cx, cy, size, colors):
    """A four-point sparkle painted as four tapered brush strokes, each
    pulled outward from the centre with a slight curve."""
    for k in range(4):
        base = k * math.pi / 2 + random.uniform(-0.06, 0.06)
        length = size * random.uniform(0.85, 1.1)
        bend = random.uniform(-0.18, 0.18)
        pts, ws = [], []
        n = 40
        for i in range(n + 1):
            t = i / n
            a = base + bend * t * t
            d = length * t
            pts.append((cx + d * math.cos(a), cy + d * math.sin(a)))
            ws.append(size * 0.36 * (1 - t) ** 1.25 + 1.2)
        poly_stroke(pts, ws, random.choice(colors))
        # Now and then a single drop just past the tip.
        tx, ty = pts[-1]
        if random.random() < 0.5:
            d = size * random.uniform(0.12, 0.25)
            out.append(f'<circle cx="{tx + d * math.cos(base):.1f}" cy="{ty + d * math.sin(base):.1f}" '
                       f'r="{size * random.uniform(0.03, 0.06):.1f}" fill="{random.choice(colors)}"/>')
    # A dab of paint at the centre where the strokes start.
    out.append(f'<circle cx="{cx}" cy="{cy}" r="{size * 0.16:.1f}" fill="{random.choice(colors)}"/>')


# ---------------------------------------------------------------- compose

# Cast shadow under the sphere: flat, soft, purple-grey.
for _ in range(5):
    arc_stroke(random.choice(['#6a5a86', '#7b4fc9', '#8c7a9f']), R * random.uniform(0.75, 0.95),
               math.radians(random.uniform(150, 200)), math.radians(random.uniform(-150, -200)),
               random.uniform(10, 26), dry=True, opacity=random.uniform(0.18, 0.32),
               sy=0.16, oy=R * 1.05 + random.uniform(-6, 10), splash=False)

# Body shading: washes laid in curved strokes, heavier and purple on the
# shadow side (lower right), thin and gold on the lit side.
for _ in range(16):
    rr = R * random.uniform(0.45, 0.93)
    s0 = math.radians(random.uniform(-30, 40))
    arc_stroke(random.choice(PURPLES), rr, s0, math.radians(random.uniform(70, 150)),
               random.uniform(18, 46) * rr / R, dry=True, opacity=random.uniform(0.18, 0.4), splash=False)
for _ in range(8):
    rr = R * random.uniform(0.35, 0.85)
    s0 = math.radians(random.uniform(160, 230))
    arc_stroke(random.choice(GOLDS), rr, s0, math.radians(random.uniform(50, 110)),
               random.uniform(8, 24), dry=True, opacity=random.uniform(0.15, 0.32), splash=False)

# Contours: an equator and a meridian, painted, so the ball reads as round.
arc_stroke('#b8892a', R * 0.97, math.radians(-10), math.radians(200), 10, opacity=0.75, sy=0.3, splash=False)
arc_stroke('#8a5cd6', R * 0.97, math.radians(-200), math.radians(110), 7, opacity=0.4, sy=0.3, splash=False)
arc_stroke('#7b4fc9', R * 0.97, math.radians(-80), math.radians(170), 9, opacity=0.7, sx=0.42, splash=False)
arc_stroke('#c9a227', R * 0.97, math.radians(100), math.radians(100), 6, opacity=0.4, sx=0.42, splash=False)

# Highlight: pale strokes on the upper left, where the light hits.
for k in range(3):
    arc_stroke(random.choice(['#fffaf0', '#fff3cc', '#ffffff']), R * (0.72 - k * 0.07),
               math.radians(198 + k * 6), math.radians(58 - k * 12), 22 - k * 6,
               dry=False, opacity=0.9, splash=False)

# The ring: many separate strokes, gold and purple each on their own,
# overlapping like layered brushwork. The gap stays at the top.
GAP_START = math.radians(-62)    # strokes run clockwise from here...
GAP_END = math.radians(-105)     # ...and stop short of here.
total = (2 * math.pi) - (GAP_START - GAP_END)

strokes = []
for i in range(9):   # big gold sweeps
    s = GAP_START + random.uniform(0, total * 0.55)
    sw = random.uniform(0.25, 0.6) * total
    sw = min(sw, GAP_START + total - s)
    strokes.append((random.choice(GOLDS), R + random.uniform(-30, 30), s, sw, random.uniform(24, 62)))
for i in range(8):   # purple sweeps, weighted toward the far end of the ring
    s = GAP_START + random.uniform(total * 0.3, total * 0.8)
    sw = random.uniform(0.15, 0.4) * total
    sw = min(sw, GAP_START + total - s)
    strokes.append((random.choice(PURPLES), R + random.uniform(-34, 34), s, sw, random.uniform(16, 46)))
for i in range(10):  # thin fast strokes on top, both colours
    s = GAP_START + random.uniform(0, total * 0.85)
    sw = random.uniform(0.1, 0.3) * total
    sw = min(sw, GAP_START + total - s)
    strokes.append((random.choice(GOLDS + PURPLES), R + random.uniform(-48, 48), s, sw, random.uniform(5, 14)))
random.shuffle(strokes)
for c, r, s, sw, peak in strokes:
    arc_stroke(c, r, s, sw, peak, dry=peak > 14, opacity=random.uniform(0.82, 1))

# Drips off the bottom and loose splatter around the ring.
for _ in range(3):
    drip(random.choice(GOLDS + PURPLES), math.radians(random.uniform(60, 120)),
         R + random.uniform(10, 30), random.uniform(40, 95))
for _ in range(60):
    a = random.uniform(0, 2 * math.pi)
    rr = R + random.gauss(0, 70)
    out.append(f'<circle cx="{CX + rr * math.cos(a):.1f}" cy="{CY + rr * math.sin(a):.1f}" '
               f'r="{random.uniform(1.5, 8):.1f}" fill="{random.choice(GOLDS + PURPLES)}" '
               f'opacity="{random.uniform(0.6, 1):.2f}"/>')

# Sparkles, painted.
star_strokes(500, 478, 112, GOLDS)
star_strokes(616, 368, 42, PURPLES)

body = '\n  '.join(out)
svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <radialGradient id="mist" cx="50%" cy="50%" r="50%">
      <stop offset="0" stop-color="#9b6bdf" stop-opacity="0.16"/>
      <stop offset="0.7" stop-color="#9b6bdf" stop-opacity="0.04"/>
      <stop offset="1" stop-color="#9b6bdf" stop-opacity="0"/>
    </radialGradient>
    <filter id="rough" x="-10%" y="-10%" width="120%" height="120%">
      <feTurbulence type="fractalNoise" baseFrequency="0.07" numOctaves="2" seed="{SEED}"/>
      <feDisplacementMap in="SourceGraphic" scale="6"/>
    </filter>
    <clipPath id="tile"><rect x="32" y="32" width="960" height="960" rx="200"/></clipPath>
  </defs>
  <rect x="32" y="32" width="960" height="960" rx="200" fill="#ffffff"/>
  <g clip-path="url(#tile)">
  <circle cx="{CX}" cy="{CY}" r="{R - 10}" fill="url(#mist)"/>
  <g filter="url(#rough)">
  {body}
  </g>
  </g>
</svg>
'''
open(sys.argv[1], 'w', encoding='utf-8').write(svg)
print('ok', len(out), 'shapes')
