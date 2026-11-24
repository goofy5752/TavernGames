"""Chess textures: the faction-styled pieces ("Б · Фракционни" of docs/mockups/09-chess.html),
the board squares and the markers, as 32-bit TGAs in media/chess/.

Standard library only; reuses the shared rasteriser helpers by import (importing writes nothing).
Deterministic (fixed seed), so reruns write identical files. Run from anywhere:
    python tools/gen_chess_textures.py
"""
import math
import os
import random
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from gen_textures import write_tga, read_tga_header, hex_rgb, mix, over, clamp, cover  # noqa: E402
from gen_faction_textures import flatten_path, circle_poly, fill_cov, stroke_cov, grad  # noqa: E402
from gen_game_icons import parse  # noqa: E402  (handles every arc / curve command of the fill paths)

OUT = os.path.join(ROOT, "media", "chess")
SEED = 20261124
PIECE_PX = 128
SQUARE_PX = 64
VIEW = 100.0            # the mockup's piece view box
SHADOW_DY = 2.5         # px, at 128
SHADOW_ALPHA = 0.65
SHADOW_SIGMA = 1.5      # px, "blurred about 2 px"

# ---- piece shapes, copied from the mockup (viewBox 0..100), element by element in drawing order
BASE = '<path class="b" d="M19 80 h62 a3 3 0 0 1 3 3 v7 h-68 v-7 a3 3 0 0 1 3 -3 z"/>'
P_BODY = '<path class="b" d="M40 52 h20 c0 12 6 20 14 28 h-48 c8 -8 14 -16 14 -28 z"/><path class="b" d="M35 46 h30 a3 3 0 0 1 0 6 h-30 a3 3 0 0 1 0 -6 z"/>'
B_BODY = '<path class="b" d="M41 62 h18 c0 8 4 13 12 18 h-42 c8 -5 12 -10 12 -18 z"/><path class="b" d="M35 56 h30 a3 3 0 0 1 0 6 h-30 a3 3 0 0 1 0 -6 z"/>'
Q_BODY = '<path class="b" d="M38 64 h24 c0 7 4 11 12 16 h-48 c8 -5 12 -9 12 -16 z"/><path class="b" d="M32 58 h36 a3 3 0 0 1 0 6 h-36 a3 3 0 0 1 0 -6 z"/>'
K_BODY = '<path class="b" d="M38 62 h24 c0 8 4 13 12 18 h-48 c8 -5 12 -10 12 -18 z"/><path class="b" d="M32 56 h36 a3 3 0 0 1 0 6 h-36 a3 3 0 0 1 0 -6 z"/>'
R_BODY = '<path class="b" d="M33 37 h34 l3 37 h-40 z"/><path class="b" d="M27 74 h46 l4 6 h-54 z"/>'
MITRE = '<path class="b" d="M50 18 c11 8 16 18 14 28 c-1 6 -6 10 -14 10 c-8 0 -13 -4 -14 -10 c-2 -10 3 -20 14 -28 z"/><circle class="b" cx="50" cy="13" r="5.5"/>'
HORSE = '<path class="b" d="M30 80 C28 66 34 56 44 48 C36 51 30 54 26 51 C22 48 23 42 27 38 C33 32 37 26 41 18 L42 10 L49 16 C65 19 75 34 75 52 C75 62 73 72 71 80 Z"/><circle class="e" cx="46" cy="30" r="2.8"/>'

# alliance: footman helm, Stormwind tower, Light-star mitre, plumed charger, arched crown, crowned king
# horde: grunt helm, spiked palisade, skull totem, wolf, spiked crown, horned crown
ALLIANCE = {
    "p": (P_BODY + '<path class="b" d="M33 46 C33 28 40 18 50 18 C60 18 67 28 67 46 Z"/><path class="t" d="M30 42 h40 v6 h-40 z"/><path class="t" d="M47.5 25 h5 v20 h-5 z"/><circle class="t" cx="50" cy="15" r="4.2"/>' + BASE),
    "r": (R_BODY + '<path class="t" d="M28 32 h44 v6 h-44 z"/><path class="b" d="M30 33 L50 9 L70 33 Z"/><path class="tl" d="M50 10 V2"/><path class="t" d="M50 1.5 l14 4.5 l-14 4.5 z"/><path class="e" d="M45.5 52 a4.5 4.5 0 0 1 9 0 v11 h-9 z" opacity=".55"/>' + BASE),
    "b": (B_BODY + MITRE + '<path class="t" d="M50 27 l2.6 6 l6.2 .8 l-4.6 4.2 l1.4 6.2 l-5.6 -3.2 l-5.6 3.2 l1.4 -6.2 l-4.6 -4.2 l6.2 -.8 z"/>' + BASE),
    "n": (HORSE + '<path class="t" d="M42 13 C43 3 56 0 62 7 C55 6 49 9 46 15 Z"/><path class="tl" d="M27 40 L45 35 L55 49"/>' + BASE),
    "q": (Q_BODY + '<path class="b" d="M29 58 L24 30 Q37 17 50 30 Q63 17 76 30 L71 58 Z"/><path class="t" d="M30 49 h40 v5 h-40 z"/><circle class="t" cx="24" cy="28" r="4.6"/><circle class="t" cx="76" cy="28" r="4.6"/><circle class="t" cx="50" cy="27" r="4.2"/><circle class="b" cx="50" cy="12" r="6"/>' + BASE),
    "k": (K_BODY + '<path class="b" d="M32 56 L28 42 C24 30 34 22 43 26 C46 27 48 29 50 32 C52 29 54 27 57 26 C66 22 76 30 72 42 L68 56 Z"/><path class="t" d="M30 46 h40 v6 h-40 z"/><circle class="gm" cx="50" cy="49" r="3"/><path class="t" d="M47 4 h6 v6 h6 v6 h-6 v11 h-6 v-11 h-6 v-6 h6 z"/>' + BASE),
}
HORDE = {
    "p": (P_BODY + '<path class="b" d="M35 46 C35 30 41 22 50 22 C59 22 65 30 65 46 Z"/><path class="t" d="M36 34 C26 32 21 24 23 13 C27 21 31 25 38 27 Z"/><path class="t" d="M64 34 C74 32 79 24 77 13 C73 21 69 25 62 27 Z"/><path class="e" d="M41 37 h18 v3.5 h-18 z"/>' + BASE),
    "r": ('<path class="b" d="M32 33 h36 l-2 41 h-32 z"/><path class="b" d="M27 74 h46 l4 6 h-54 z"/><path class="b" d="M30 35 L33 14 L39 28 L44 7 L50 26 L56 7 L61 28 L67 14 L70 35 Z"/><path class="t" d="M32 46 h36 v5 h-36 z"/><path class="t" d="M33 61 h34 v5 h-34 z"/>' + BASE),
    "b": (B_BODY + '<path class="b" d="M45 30 h10 v27 h-10 z"/><path class="t" d="M44 40 L33 54 L39 54 Z"/><path class="t" d="M56 40 L67 54 L61 54 Z"/><path class="b" d="M50 7 C39 7 34 14 34 22 C34 28 37 31 41 32 V37 H59 V32 C63 31 66 28 66 22 C66 14 61 7 50 7 Z"/><circle class="e" cx="44" cy="22" r="3.8"/><circle class="e" cx="56" cy="22" r="3.8"/>' + BASE),
    "n": ('<path class="b" d="M30 80 C30 66 34 58 40 52 L24 50 L11 43 L28 34 L38 26 L42 7 L50 20 L58 7 L61 26 C71 34 76 44 76 56 C76 64 74 72 72 80 Z"/><path class="e" d="M33 32 L43 29 L40 35 Z"/><path class="t" d="M19 45 L23 52 L26 46 Z"/><path class="sl" d="M58 30 C66 38 70 48 70 60"/>' + BASE),
    "q": (Q_BODY + '<path class="b" d="M24 21 L35 52 L38 15 L44 50 L50 6 L56 50 L62 15 L65 52 L76 21 L67 58 H33 Z"/><path class="t" d="M33 51 h34 v6 h-34 z"/>' + BASE),
    "k": (K_BODY + '<path class="b" d="M33 56 V36 H67 V56 Z"/><path class="b" d="M33 37 L36 22 L42 34 L50 10 L58 34 L64 22 L67 37 Z"/><path class="t" d="M33 41 C20 39 14 27 17 12 C21 24 26 30 34 32 Z"/><path class="t" d="M67 41 C80 39 86 27 83 12 C79 24 74 30 66 32 Z"/><circle class="gm" cx="50" cy="46" r="4"/>' + BASE),
}

SHAPES = {"alliance": ALLIANCE, "horde": HORDE}


# ---- palettes (mockup CSS): material gradient stops, outline, trim, eye
def _g(*stops):
    return [(p, hex_rgb(c)) for p, c in stops]


PAL = {
    ("alliance", "w"): dict(fill=_g((0, "#fffaf0"), (.55, "#efe2c0"), (1, "#c9b282")), ol="#4a3410", tr="#c8942e", ey="#4a3410"),
    ("alliance", "b"): dict(fill=_g((0, "#46639a"), (.5, "#1d2f55"), (1, "#0a1226")), ol="#a8802c", tr="#e5b850", ey="#e5b850"),
    ("horde", "w"): dict(fill=_g((0, "#fbf1da"), (.55, "#e4d1aa"), (1, "#ab9068")), ol="#2e2118", tr="#7d736b", ey="#2e2118"),
    ("horde", "b"): dict(fill=_g((0, "#5a4740"), (.5, "#2a201d"), (1, "#0c0807")), ol="#8a7a6e", tr="#c8492e", ey="#d9603e"),
}
GEM = hex_rgb("#d0302a")

# class -> (fill, stroke, stroke width) as in the mockup's .pc rules; "fill" = the material gradient,
# "gem" = #d0302a, ol / tr / ey = palette keys
CLASSES = {
    "b": ("fill", "ol", 2.4),
    "t": ("tr", "ol", 1.2),
    "e": ("ey", None, 0),
    "sl": (None, "ey", 2.6),
    "tl": (None, "tr", 2.4),
    "gm": ("gem", "ol", 1.0),
}


# ---- parsing the shape strings

def parse_elements(markup):
    """'<path class d/><circle class cx cy r/>' -> [dict] in drawing order."""
    els = []
    for tag, attrs in re.findall(r"<(path|circle)([^>]*?)/>", markup):
        a = dict(re.findall(r'(\w+)="([^"]*)"', attrs))
        fill_c, stroke_c, sw = CLASSES[a["class"]]
        el = dict(opacity=float(a.get("opacity", 1.0)), fill=fill_c, stroke=stroke_c, sw=sw, polys=[], open=None)
        if tag == "circle":
            el["polys"] = [circle_poly(float(a["cx"]), float(a["cy"]), float(a["r"]), 96)]
        elif fill_c is None:   # an open stroke (sl, tl): no arcs in these, flatten_path is enough
            el["open"] = flatten_path(a["d"])
        else:
            el["polys"] = parse(a["d"])
        els.append(el)
    return els


# ---- rasterising a piece

K = PIECE_PX / VIEW


def element_cov(el, dy=0.0):
    """(fill coverage or None, stroke coverage or None) at PIECE_PX; dy shifts the geometry (px)."""
    if el["open"] is not None:
        subs = [([(x * K, y * K + dy) for x, y in pts], closed) for pts, closed in el["open"]]
        return None, stroke_cov(PIECE_PX, PIECE_PX, subs, el["sw"] * K)
    polys = [[(x * K, y * K + dy) for x, y in p] for p in el["polys"]]
    fcov = fill_cov(PIECE_PX, PIECE_PX, polys, 4) if el["fill"] is not None else None
    scov = stroke_cov(PIECE_PX, PIECE_PX, [(p, True) for p in polys], el["sw"] * K) if el["stroke"] is not None else None
    return fcov, scov


def blur(cov, sigma):
    r = int(math.ceil(sigma * 3))
    ker = [math.exp(-(i * i) / (2 * sigma * sigma)) for i in range(-r, r + 1)]
    s = sum(ker)
    ker = [v / s for v in ker]
    n = len(cov)
    tmp = [[sum(ker[j + r] * row[i + j] for j in range(-r, r + 1) if 0 <= i + j < n) for i in range(n)] for row in cov]
    return [[sum(ker[j + r] * tmp[y + j][x] for j in range(-r, r + 1) if 0 <= y + j < n) for x in range(n)] for y in range(n)]


def material(el, pal):
    """A colour, or fn(x, y) in piece px. The gradient runs from the top-left of the element's bounding
    box towards (0.6, 1) of it (SVG objectBoundingBox x2=.6 y2=1)."""
    if el["fill"] == "gem":
        return GEM
    if el["fill"] != "fill":
        return hex_rgb(pal[el["fill"]])
    pts = [p for poly in el["polys"] for p in poly]
    x0, x1 = min(p[0] for p in pts) * K, max(p[0] for p in pts) * K
    y0, y1 = min(p[1] for p in pts) * K, max(p[1] for p in pts) * K
    w, h = (x1 - x0) or 1e-9, (y1 - y0) or 1e-9

    def fn(x, y):
        return grad(pal["fill"], clamp((((x - x0) / w) * 0.6 + (y - y0) / h) / (0.36 + 1.0)))
    return fn


def render_piece(faction, colour, kind):
    pal = PAL[(faction, colour)]
    els = parse_elements(SHAPES[faction][kind])
    n = PIECE_PX

    # the shadow: the silhouette (fills and strokes) shifted down, blurred
    sil = [[0.0] * n for _ in range(n)]
    for el in els:
        for c in element_cov(el, SHADOW_DY):
            if c is not None:
                for y in range(n):
                    row, srow = c[y], sil[y]
                    for x in range(n):
                        if row[x] > srow[x]:
                            srow[x] = min(row[x], 1.0)
    sil = blur(sil, SHADOW_SIGMA)
    px = [[(0.0, 0.0, 0.0, SHADOW_ALPHA * min(sil[y][x], 1.0)) for x in range(n)] for y in range(n)]

    for el in els:
        fc, sc = element_cov(el)
        if fc is not None:
            col = material(el, pal)
            for y in range(n):
                for x in range(n):
                    a = fc[y][x]
                    if a > 0.001:
                        c = col(x + 0.5, y + 0.5) if callable(col) else col
                        px[y][x] = over(px[y][x], c, clamp(a) * el["opacity"])
        if sc is not None:
            col = hex_rgb(pal[el["stroke"]])
            for y in range(n):
                for x in range(n):
                    a = sc[y][x]
                    if a > 0.001:
                        px[y][x] = over(px[y][x], col, clamp(a))
    return px


# ---- squares

SQ_BASE = {"alliance_l": "#e7dec6", "alliance_d": "#3d679f", "horde_l": "#d8c19a", "horde_d": "#7c2b20"}


def lin_a(u, v, a0, stop):
    """CSS linear-gradient(135deg, a0 white, transparent stop): alpha at unit coords (u, v)."""
    return a0 * clamp(1.0 - ((u + v) / 2.0) / stop)


def radial_a(u, v, cx, cy, a0, stop, rad):
    """CSS radial-gradient(circle at (cx, cy), a0 colour, transparent stop); rad = farthest-corner radius."""
    return a0 * clamp(1.0 - math.hypot(u - cx, v - cy) / (stop * rad))


def render_square(faction, tone, rng):
    base = hex_rgb(SQ_BASE[faction + "_" + tone])
    n = SQUARE_PX
    px = []
    for y in range(n):
        row = []
        for x in range(n):
            u, v = (x + 0.5) / n, (y + 0.5) / n
            col = base
            if faction == "alliance":
                a = lin_a(u, v, 0.18, 0.55) if tone == "l" else lin_a(u, v, 0.10, 0.60)
                col = mix(col, (1, 1, 1), a)
            elif tone == "l":    # first listed layer on top: the white spot over the brown one
                col = mix(col, (90 / 255, 50 / 255, 20 / 255), radial_a(u, v, .2, .8, .18, .5, math.hypot(.8, .8)))
                col = mix(col, (1, 1, 1), radial_a(u, v, .6, .4, .14, .6, math.hypot(.6, .6)))
            else:
                col = mix(col, (0, 0, 0), radial_a(u, v, .7, .8, .25, .5, math.hypot(.7, .8)))
                col = mix(col, (1, 1, 1), radial_a(u, v, .3, .3, .06, .6, math.hypot(.7, .7)))
            d = (rng.random() - 0.5) * 0.04      # light seeded noise, +-2 %
            row.append((clamp(col[0] + d), clamp(col[1] + d), clamp(col[2] + d), 1.0))
        px.append(row)
    return px


# ---- markers (64 x 64)

def render_dot():
    n = SQUARE_PX
    c, r = n / 2.0, n * 0.30 / 2
    return [[(1.0, 1.0, 1.0, cover(math.hypot(x + .5 - c, y + .5 - c) - r)) for x in range(n)] for y in range(n)]


def render_ring():
    n = SQUARE_PX
    c = n / 2.0
    ro = n * 0.92 / 2
    ri = ro - n * 0.07
    px = []
    for y in range(n):
        row = []
        for x in range(n):
            d = math.hypot(x + .5 - c, y + .5 - c)
            row.append((1.0, 1.0, 1.0, clamp(cover(d - ro) - cover(d - ri))))
        px.append(row)
    return px


def render_check():
    """radial-gradient(circle, rgba(255,40,30,.95) 0, rgba(220,20,10,.75) 35%, rgba(160,0,0,0) 72%)
    with the default farthest-corner radius; interpolated premultiplied, as CSS does."""
    n = SQUARE_PX
    c = n / 2.0
    rad = math.hypot(c, c)
    stops = [(0.0, (255 / 255, 40 / 255, 30 / 255), 0.95), (0.35, (220 / 255, 20 / 255, 10 / 255), 0.75),
             (0.72, (160 / 255, 0.0, 0.0), 0.0)]
    clear = (0.0, 0.0, 0.0, 0.0)
    px = []
    for y in range(n):
        row = []
        for x in range(n):
            t = math.hypot(x + .5 - c, y + .5 - c) / rad
            out = clear
            for (p0, c0, a0), (p1, c1, a1) in zip(stops, stops[1:]):
                if p0 <= t <= p1:
                    k = (t - p0) / (p1 - p0)
                    a = a0 + (a1 - a0) * k
                    if a > 0:
                        pm = [c0[i] * a0 + (c1[i] * a1 - c0[i] * a0) * k for i in range(3)]
                        out = (pm[0] / a, pm[1] / a, pm[2] / a, a)
                    break
            row.append(out)
        px.append(row)
    return px


# ---- output

def jobs():
    for faction in ("alliance", "horde"):
        for colour in ("w", "b"):
            for kind in "pnbrqk":
                yield "%s_%s%s" % (faction, colour, kind), PIECE_PX, lambda f=faction, c=colour, k=kind: render_piece(f, c, k)
    rng = random.Random(SEED)
    for faction in ("alliance", "horde"):
        for tone in ("l", "d"):
            yield "sq_%s_%s" % (faction, tone), SQUARE_PX, lambda f=faction, t=tone: render_square(f, t, rng)
    yield "dot", SQUARE_PX, render_dot
    yield "ring", SQUARE_PX, render_ring
    yield "check", SQUARE_PX, render_check


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, size, make in jobs():
        path = os.path.join(OUT, name + ".tga")
        write_tga(path, size, size, make())
        kind, w, h, bpp, _, length = read_tga_header(path)
        assert (kind, w, h, bpp) == (2, size, size, 32), name
        assert length == 18 + w * h * 4, name
        print("%-18s %3dx%-3d %d bytes" % (name + ".tga", w, h, length))


if __name__ == "__main__":
    main()
