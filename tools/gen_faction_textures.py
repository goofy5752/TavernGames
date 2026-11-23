"""Generates the faction skin textures in media/skin/ as 32-bit uncompressed TGA.

Standard library only; deterministic (fixed seed). Reuses the writer and the
drawing helpers of gen_textures.py, which it never modifies. Run from anywhere:
    python tools/gen_faction_textures.py [--preview <dir>]
Colours come from docs/mockups/08-faction-tavern.html. The crests are our own
drawings (a shield with a crown, a spiked circle), not the Blizzard emblems.
"""
import math
import os
import random
import re
import struct
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_textures as gt  # noqa: E402
from gen_textures import (PeriodicNoise, clamp, cover, fbm, hex_rgb, is_pow2, make_button,  # noqa: E402
                          mix, over, read_tga_header, render, sd_card, sd_circle,
                          sd_round_rect, smooth, write_tga, CARD_W, CARD_H, CARD_STRETCH, WHITE)

ROOT = gt.ROOT
OUT = os.path.join(ROOT, "media", "skin")
SEED = 20261127
CLEAR = (0.0, 0.0, 0.0, 0.0)

# Faction palettes (mockup :root / [data-faction] blocks).
PAL = {
    "alliance": dict(felt_hi=hex_rgb("#1f4c8a"), felt=hex_rgb("#13325e"), felt_lo=hex_rgb("#071226"),
                     metal_hi=hex_rgb("#f6d98c"), metal=hex_rgb("#d8ab4a"), metal_lo=hex_rgb("#6f4f18"),
                     banner_hi=hex_rgb("#2c5ea6"), banner=hex_rgb("#1b3f75")),
    "horde": dict(felt_hi=hex_rgb("#84201a"), felt=hex_rgb("#5a0f0e"), felt_lo=hex_rgb("#2a0605"),
                  metal_hi=hex_rgb("#d6ccc0"), metal=hex_rgb("#9a8f86"), metal_lo=hex_rgb("#3a3431"),
                  banner_hi=hex_rgb("#a3241b"), banner=hex_rgb("#6e1410")),
}


def grad(stops, t):
    """Colour at t along [(pos, rgb), ...] (sorted); clamps outside."""
    if t <= stops[0][0]:
        return stops[0][1]
    for (p0, c0), (p1, c1) in zip(stops, stops[1:]):
        if t <= p1:
            return mix(c0, c1, (t - p0) / (p1 - p0))
    return stops[-1][1]


def metal_stops(p):
    return [(0.0, p["metal_hi"]), (0.5, p["metal"]), (1.0, p["metal_lo"])]


def felt_stops(p, mid=0.45):
    return [(0.0, p["felt_hi"]), (mid, p["felt"]), (1.0, p["felt_lo"])]


# ------------------------------------------------------------ tiny vector rasteriser

def flatten_path(d, n=10):
    """SVG path data -> [(points, closed)]. Supports M L H V C Z (and lower case h v l m c) and
    the tiny-chord 'a' arcs the mockup uses for full circles / ellipses."""
    toks = re.findall(r"[A-Za-z]|-?\d*\.?\d+", d)
    subs, cur, pts, i, cmd = [], (0.0, 0.0), [], 0, None

    def num():
        nonlocal i
        i += 1
        return float(toks[i - 1])

    def close(closed):
        nonlocal pts
        if pts:
            subs.append((pts, closed))
        pts = []

    while i < len(toks):
        if re.match(r"[A-Za-z]", toks[i]):
            cmd = toks[i]
            i += 1
            if cmd in "zZ":
                close(True)
                continue
        rel = cmd.islower()
        c = cmd.upper()
        ox, oy = cur if rel else (0.0, 0.0)
        if c == "M":
            close(False)
            cur = (ox + num(), oy + num())
            pts = [cur]
            cmd = "l" if rel else "L"
        elif c == "L":
            cur = (ox + num(), oy + num())
            pts.append(cur)
        elif c == "H":
            cur = ((cur[0] if rel else 0.0) + num(), cur[1])
            pts.append(cur)
        elif c == "V":
            cur = (cur[0], (cur[1] if rel else 0.0) + num())
            pts.append(cur)
        elif c == "C":
            p1 = (ox + num(), oy + num())
            p2 = (ox + num(), oy + num())
            p3 = (ox + num(), oy + num())
            p0 = cur
            for k in range(1, n + 1):
                t = k / n
                u = 1.0 - t
                pts.append((u ** 3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t ** 3 * p3[0],
                            u ** 3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t ** 3 * p3[1]))
            cur = p3
        elif c == "A":
            rx, ry, _rot, _large, sweep = num(), num(), num(), num(), num()
            end = (ox + num(), oy + num())
            assert abs(end[0] - cur[0]) < 1 and abs(end[1] - cur[1]) < 1, "only full-ellipse arcs"
            cy = cur[1] + (ry if sweep else -ry)
            cx = (cur[0] + end[0]) / 2.0
            close(False)
            subs.append(([(cx + rx * math.cos(a * math.pi / 24), cy + ry * math.sin(a * math.pi / 24))
                          for a in range(48)], True))
            cur = end
            pts = [cur]
        else:
            raise ValueError("path command " + cmd)
    close(False)
    return subs


def circle_poly(cx, cy, r, n=96):
    return [(cx + r * math.cos(2 * math.pi * k / n), cy + r * math.sin(2 * math.pi * k / n)) for k in range(n)]


def fill_cov(w, h, polys, ss=4):
    """Even-odd coverage grid [h][w] of closed polygons in pixel space; exact in x, ss samples in y."""
    cov = [[0.0] * w for _ in range(h)]
    edges = []
    for pts in polys:
        for k in range(len(pts)):
            (ax, ay), (bx, by) = pts[k], pts[(k + 1) % len(pts)]
            if ay != by:
                edges.append((min(ay, by), max(ay, by), ax, (bx - ax) / (by - ay), ay))
    for sy in range(h * ss):
        y = (sy + 0.5) / ss
        xs = sorted(ax + (y - ay) * k for (y0, y1, ax, k, ay) in edges if y0 <= y < y1)
        row = cov[sy // ss]
        for a in range(0, len(xs) - 1, 2):
            xa, xb = max(xs[a], 0.0), min(xs[a + 1], float(w))
            if xb <= xa:
                continue
            for ix in range(int(xa), min(int(xb), w - 1) + 1):
                row[ix] += (min(xb, ix + 1.0) - max(xa, float(ix))) / ss
    return cov


def stroke_cov(w, h, subs, width):
    """Coverage of a round-capped stroke along the polylines (distance to the nearest segment)."""
    segs = []
    for pts, closed in subs:
        n = len(pts)
        for k in range(n if closed else n - 1):
            segs.append((pts[k], pts[(k + 1) % n]))
    half = width / 2.0
    cov = [[0.0] * w for _ in range(h)]
    for (ax, ay), (bx, by) in segs:
        x0, x1 = max(int(min(ax, bx) - half - 1), 0), min(int(max(ax, bx) + half + 1), w - 1)
        y0, y1 = max(int(min(ay, by) - half - 1), 0), min(int(max(ay, by) + half + 1), h - 1)
        ex, ey = bx - ax, by - ay
        ln2 = ex * ex + ey * ey or 1e-9
        for y in range(y0, y1 + 1):
            row = cov[y]
            for x in range(x0, x1 + 1):
                px, py = x + 0.5, y + 0.5
                t = clamp(((px - ax) * ex + (py - ay) * ey) / ln2)
                v = cover(math.hypot(px - ax - t * ex, py - ay - t * ey) - half)
                if v > row[x]:
                    row[x] = v
    return cov


class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.px = [[CLEAR] * w for _ in range(h)]

    def paint(self, cov, color, alpha=1.0, ox=0, oy=0):
        """color: an rgb tuple or fn(x, y) -> rgb (canvas pixel centre)."""
        for y, row in enumerate(cov):
            cy = y + oy
            if not 0 <= cy < self.h:
                continue
            for x, a in enumerate(row):
                if a <= 0.001:
                    continue
                cx = x + ox
                if not 0 <= cx < self.w:
                    continue
                col = color(cx + 0.5, cy + 0.5) if callable(color) else color
                self.px[cy][cx] = over(self.px[cy][cx], col, clamp(a) * alpha)

    def rows(self):
        return self.px


class Symbol:
    """An SVG-like symbol drawn into a square cell of a canvas: viewBox (vw, vh) fitted and centred."""

    def __init__(self, canvas, ox, oy, size, vw, vh):
        self.cv, self.ox, self.oy, self.size = canvas, ox, oy, size
        self.sc = size / max(vw, vh)
        self.dx, self.dy = (size - vw * self.sc) / 2.0, (size - vh * self.sc) / 2.0

    def tf(self, pts):
        return [(self.dx + x * self.sc, self.dy + y * self.sc) for x, y in pts]

    def path(self, d, fill=None, stroke=None, sw=0.0, opacity=1.0, sopacity=1.0):
        """fill / stroke: a vertical gradient (stop list, over the geometry's bbox) or an rgb tuple."""
        subs = [(self.tf(p), c) for p, c in flatten_path(d)]
        self.shape(subs, fill, stroke, sw, opacity, sopacity)

    def circle(self, cx, cy, r, fill=None, stroke=None, sw=0.0):
        self.shape([(self.tf(circle_poly(cx, cy, r)), True)], fill, stroke, sw, 1.0, 1.0)

    def shape(self, subs, fill, stroke, sw, opacity, sopacity):
        ys = [p[1] for pts, _ in subs for p in pts]
        y0, y1 = min(ys), max(ys)

        def colour(spec):
            if isinstance(spec, list):
                return lambda x, y: grad(spec, (y - self.oy - y0) / (y1 - y0 or 1.0))
            return spec
        s = self.size
        if fill is not None:
            cov = fill_cov(s, s, [p for p, _ in subs])
            self.cv.paint(cov, colour(fill), opacity, self.ox, self.oy)
        if stroke is not None:
            cov = stroke_cov(s, s, subs, sw * self.sc)
            self.cv.paint(cov, colour(stroke), sopacity, self.ox, self.oy)


G_GOLD = [(0.0, hex_rgb("#fff0b8")), (0.5, hex_rgb("#e0b24e")), (1.0, hex_rgb("#7a5418"))]
G_IRON = [(0.0, hex_rgb("#e2d8cc")), (0.5, hex_rgb("#8e837a")), (1.0, hex_rgb("#3a3431"))]
G_BLUE = [(0.0, hex_rgb("#3b6fc0")), (1.0, hex_rgb("#0f2a55"))]
G_RED = [(0.0, hex_rgb("#b4281e")), (1.0, hex_rgb("#4a0a08"))]
GOLD_LINE = hex_rgb("#e0b24e")


# ---------------------------------------------------------------- textures

def tex_felt(faction):
    p = PAL[faction]

    def make(rng):
        w = h = 256
        cx, cy = w * 0.5, h * 0.45
        rmax = math.hypot(w / 2.0, h * 0.55)
        stops = felt_stops(p)
        blot = [(PeriodicNoise(rng, 6, 6), 1.0), (PeriodicNoise(rng, 14, 14), 0.6), (PeriodicNoise(rng, 40, 40), 0.3)]
        fine = [(PeriodicNoise(rng, 128, 128), 1.0), (PeriodicNoise(rng, 64, 64), 0.5)]

        def px(x, y):
            col = grad(stops, math.hypot(x - cx, y - cy) / rmax)
            if faction == "alliance":
                # Fine woven grain: two diagonal thread sets over/under, 4 px pitch.
                a = 0.5 + 0.5 * math.sin((x + y) * math.pi / 2.0)
                b = 0.5 + 0.5 * math.sin((x - y) * math.pi / 2.0)
                weave = a * b + (1.0 - a) * (1.0 - b)
                k = 0.93 + 0.10 * weave + 0.04 * (fbm(fine, x, y, w, h) - 0.5)
            else:
                # Blotched leather: dark blotches over a fine pitted grain.
                n = fbm(blot, x, y, w, h)
                k = 0.78 + 0.42 * smooth(clamp((n - 0.30) / 0.45)) + 0.06 * (fbm(fine, x, y, w, h) - 0.5)
            return tuple(clamp(c * k) for c in col) + (1.0,)
        return w, h, render(w, h, px)
    return make


def tex_frame(faction):
    p = PAL[faction]
    stops = metal_stops(p)

    def make(rng):
        w = h = 64
        band = 12.0
        hammer = [(PeriodicNoise(rng, 8, 8), 1.0), (PeriodicNoise(rng, 16, 16), 0.5)]
        dark = p["metal_lo"]

        def px(x, y):
            outer = sd_round_rect(x, y, 0.0, 0.0, w, h, 6.0)
            inner = sd_round_rect(x, y, band, band, w - band, h - band, 2.0)
            a = cover(outer) * cover(-inner)
            if a <= 0.0:
                return CLEAR
            col = grad(stops, y / h)
            col = mix(col, p["metal_hi"], 0.35 * clamp(1.0 + outer / 2.5))
            col = mix(col, dark, 0.6 * clamp(1.0 + inner / 1.5))
            if faction == "horde":
                # Wrought iron: hammered grain and a rivet in each corner block.
                k = 0.88 + 0.24 * fbm(hammer, x, y, w, h)
                col = tuple(clamp(c * k) for c in col)
                for rx, ry in ((6, 6), (58, 6), (6, 58), (58, 58)):
                    rv = sd_circle(x, y, rx, ry, 2.4)
                    shade = clamp(0.5 - ((x - rx) + (y - ry)) / 6.0)
                    col = mix(col, mix(p["metal"], p["metal_hi"], shade), cover(rv))
                    col = mix(col, dark, 0.8 * cover(abs(rv) - 0.4))
            return col + (a,)
        return w, h, render(w, h, px)
    return make


def tex_cap(faction):
    p = PAL[faction]
    stops = [(0.0, p["metal_hi"]), (0.45, p["metal"]), (0.8, p["metal_lo"])]

    def make(rng):
        w = h = 64
        fx, fy = w * 0.4, h * 0.35
        rmax = math.hypot(w * 0.6, h * 0.65)
        if faction == "horde":
            # mockup clip-path: an eight-point spike
            base = [(50, 0), (64, 36), (100, 50), (64, 64), (50, 100), (36, 64), (0, 50), (36, 36)]
            cov = fill_cov(w, h, [[(2.0 + x * 0.60, 2.0 + y * 0.60) for x, y in base]])
        else:
            cov = [[cover(sd_circle(x + 0.5, y + 0.5, 32.0, 32.0, 29.0)) for x in range(w)] for y in range(h)]
        cv = Canvas(w, h)
        cv.paint(cov, lambda x, y: grad(stops, math.hypot(x - fx, y - fy) / rmax))
        return w, h, cv.rows()
    return make


def tex_stone(rng):
    a, b = hex_rgb("#6e6a60"), hex_rgb("#5c584f")
    return 128, 128, render(128, 128, lambda x, y: (a if (x < 64) == (y < 64) else b) + (1.0,))


def sd_ellipse(x, y, cx, cy, ax, ay):
    """First-order distance to an ellipse."""
    dx, dy = x - cx, y - cy
    f = math.sqrt((dx / ax) ** 2 + (dy / ay) ** 2)
    if f < 1e-9:
        return -min(ax, ay)
    return (f - 1.0) * f / math.hypot(dx / (ax * ax), dy / (ay * ay))


def tex_oval(faction):
    p = PAL[faction]
    stops = felt_stops(p, 0.5)
    ms = metal_stops(p)

    def make(rng):
        w, h = 512, 256
        cx, cy, rx, ry = 256.0, 128.0, 256.0, 128.0
        rim, line = 14.0, 3.0
        wood_a, wood_b = hex_rgb("#4a2c1a"), hex_rgb("#2a170c")
        fine = [(PeriodicNoise(rng, 128, 64), 1.0), (PeriodicNoise(rng, 64, 32), 0.5)]

        def px(x, y):
            a = cover(sd_ellipse(x, y, cx, cy, rx, ry))
            if a <= 0.0:
                return CLEAR
            wood = mix(wood_a, wood_b, clamp((y - (cy - ry)) / (2.0 * ry)))
            brass_edge = sd_ellipse(x, y, cx, cy, rx - rim, ry - rim)
            inner = sd_ellipse(x, y, cx, cy, rx - rim - line, ry - rim - line)
            dx, dy = (x - cx) / (rx - rim - line), (y - cy) / (ry - rim - line)
            felt = grad(stops, math.hypot(dx, dy) / 1.1)
            k = 0.95 + 0.10 * fbm(fine, x, y, w, h)
            felt = tuple(clamp(c * k) for c in felt)
            metal = grad(ms, clamp((y - (cy - ry + rim)) / (2.0 * (ry - rim))))
            col = mix(wood, metal, cover(brass_edge))
            col = mix(col, felt, cover(inner))
            return col + (a,)
        return w, h, render(w, h, px)
    return make


def tex_crest(faction):
    def make(rng):
        s = 128
        cv = Canvas(s, s)
        if faction == "alliance":
            sy = Symbol(cv, 0, 0, s, 100, 120)
            sy.path("M50 4 L92 16 V58 C92 86 72 104 50 116 C28 104 8 86 8 58 V16 Z", G_BLUE, G_GOLD, 5)
            sy.path("M50 18 L80 26 V58 C80 78 66 92 50 101 C34 92 20 78 20 58 V26 Z", None, GOLD_LINE, 1.5, sopacity=0.6)
            sy.path("M32 40 L38 30 L44 38 L50 26 L56 38 L62 30 L68 40 L66 48 H34 Z", G_GOLD)
            sy.path("M50 52 C40 52 34 60 36 70 C38 80 46 86 50 92 C54 86 62 80 64 70 C66 60 60 52 50 52 Z "
                    "M44 66 a3 3 0 1 0 0.1 0 M56 66 a3 3 0 1 0 0.1 0", G_GOLD)
            sy.path("M38 62 C30 58 26 66 30 72 M62 62 C70 58 74 66 70 72", None, GOLD_LINE, 3)
        else:
            sy = Symbol(cv, 0, 0, s, 120, 120)
            sy.circle(60, 60, 50, G_RED, G_IRON, 6)
            for d in ("M60 6 L68 26 L60 22 L52 26 Z", "M60 114 L68 94 L60 98 L52 94 Z",
                      "M6 60 L26 52 L22 60 L26 68 Z", "M114 60 L94 52 L98 60 L94 68 Z",
                      "M30 34 L60 46 L90 34 L80 60 L90 86 L60 74 L30 86 L40 60 Z"):
                sy.path(d, G_IRON)
            sy.path("M44 56 L60 64 L76 56 L70 70 L60 66 L50 70 Z", hex_rgb("#2a0806"))
            sy.path("M46 72 C44 80 46 86 50 90 M74 72 C76 80 74 86 70 90", None, hex_rgb("#efe2c2"), 4)
        return s, s, cv.rows()
    return make


def tex_coins(rng):
    w, h = 128, 32
    cv = Canvas(w, h)
    specs = [("#fff3c0", "#e8b53c", "#8a5a10", "#5a3a08"), ("#ffffff", "#c9ccd2", "#6b6e75", "#45474c"),
             ("#ffd2a8", "#c06a2c", "#6a3208", "#4a2206")]
    disc = [[cover(sd_circle(x + 0.5, y + 0.5, 16.0, 16.0, 14.5)) for x in range(32)] for y in range(32)]
    for i, (c0, c1, c2, rimc) in enumerate(specs):
        stops = [(0.0, hex_rgb(c0)), (0.5, hex_rgb(c1)), (1.0, hex_rgb(c2))]
        ox = i * 32.0
        fx, fy = ox + 32.0 * 0.35, 32.0 * 0.30
        rmax = math.hypot(32.0 * 0.65, 32.0 * 0.7) * 0.5

        def col(x, y, stops=stops, fx=fx, fy=fy, rimc=hex_rgb(rimc), ox=ox):
            d = math.hypot(x - ox - 16.0, y - 16.0)
            body = grad(stops, math.hypot(x - fx, y - fy) / rmax)
            return mix(rimc, body, cover(d - 13.0))
        cv.paint(disc, col, 1.0, i * 32, 0)
    # empty slot: a dim dark disc with a thin rim
    cv.paint(disc, (0.0, 0.0, 0.0), 0.4, 96, 0)
    ring = [[cover(abs(sd_circle(x + 0.5, y + 0.5, 16.0, 16.0, 14.0)) - 0.5) for x in range(32)] for y in range(32)]
    cv.paint(ring, (0.55, 0.5, 0.45), 0.5, 96, 0)
    return w, h, cv.rows()


def tex_parchment(rng):
    w = h = 256
    stops = [(0.0, hex_rgb("#f7ecd2")), (0.6, hex_rgb("#ead8b0")), (1.0, hex_rgb("#d8bf8a"))]
    burn = hex_rgb("#78501e")
    fx, fy = w * 0.3, h * 0.2
    rmax = math.hypot(w * 0.7, h * 0.8)
    grain = [(PeriodicNoise(rng, 8, 8), 1.0), (PeriodicNoise(rng, 32, 32), 0.5), (PeriodicNoise(rng, 96, 96), 0.25)]

    def px(x, y):
        col = grad(stops, math.hypot(x - fx, y - fy) / rmax)
        k = 0.96 + 0.08 * fbm(grain, x, y, w, h)
        col = tuple(clamp(c * k) for c in col)
        edge = min(x, y, w - x, h - y)
        e = clamp(1.0 - edge / 26.0)
        n = fbm(grain, x, y, w, h)
        col = mix(col, burn, clamp(0.55 * e * e * (0.7 + 0.6 * n)))
        return col + (1.0,)
    return w, h, render(w, h, px)


def tex_pring(rng):
    def px(x, y):
        d = math.hypot(x - 64.0, y - 64.0)
        a = max(cover(abs(d - 60.0) - 2.0), cover(abs(d - 51.0) - 1.0))
        return WHITE + (a,) if a > 0.0 else CLEAR
    return 128, 128, render(128, 128, px)


def tex_mask(rng):
    return 64, 64, render(64, 64, lambda x, y: WHITE + (cover(sd_circle(x, y, 32.0, 32.0, 31.0)),))


def tex_button(faction, hi):
    p = PAL[faction]
    ms = metal_stops(p)

    def lift(c):
        return mix(c, WHITE, 0.15) if hi else c

    def make(rng):
        return make_button(lift(p["banner_hi"]), lift(p["banner"]), lambda t: lift(grad(ms, t)))
    return make


def tex_chip(rng):
    grey = (0.72, 0.72, 0.72)

    def px(x, y):
        d = math.hypot(x - 16.0, y - 16.0)
        a = cover(d - 14.0)
        if a <= 0.0:
            return CLEAR
        col = mix(grey, WHITE, cover(d - 12.0))
        ang = (math.atan2(y - 16.0, x - 16.0) / (2.0 * math.pi)) % 1.0
        phase = (ang * 8) % 1.0
        arc = 2.0 * math.pi * 9.0 / 8
        ring = cover(abs(d - 9.0) - 1.0) * cover((abs(phase - 0.5) - 0.25) * arc)
        return mix(col, grey, ring) + (a,)
    return 32, 32, render(32, 32, px)


def tex_card_back(faction):
    p = PAL[faction]
    stops = felt_stops(p, 0.5)
    ms = metal_stops(p)

    def make(rng):
        cx, cy = CARD_W / 2.0, CARD_H / 2.0
        root2 = math.sqrt(2.0)

        def px(x, y):
            sd = sd_card(x, y)
            r = math.hypot(x - cx, (y - cy) / CARD_STRETCH)
            col = grad(stops, math.hypot(x - cx, (y - cy) / 2.0) / 40.0)
            metal = grad(ms, y / CARD_H)
            # Diamond lattice at half strength; kept off the centre (the crest) and the border.
            q1 = ((x + y) / root2) % 8.0
            q2 = ((x - y) / root2) % 8.0
            line = max(cover(abs(q1 - 4.0) - 0.4), cover(abs(q2 - 4.0) - 0.4))
            keep = smooth(clamp((r - 17.0) / 4.0)) * cover(-(sd + 8.0))
            col = mix(col, metal, 0.5 * line * keep)
            col = mix(col, metal, cover(abs(sd + 5.0) - 1.0))
            col = mix(p["metal_lo"], col, cover(sd + 2.0))
            return col + (cover(sd),)
        return CARD_W, CARD_H, render(CARD_W, CARD_H, px)
    return make


def tex_cameo(rng):
    def px(x, y):
        a = cover(abs(math.hypot(x - 32.0, y - 32.0) - 29.5) - 1.5)
        return WHITE + (a,) if a > 0.0 else CLEAR
    return 64, 64, render(64, 64, px)


def tex_ribbon(rng):
    w, h = 64, 16
    poly = [(0.0, 0.0), (64.0, 0.0), (64 * 0.94, 8.0), (64.0, 16.0), (0.0, 16.0), (64 * 0.06, 8.0)]
    cv = Canvas(w, h)
    cv.paint(fill_cov(w, h, [poly]), WHITE)
    return w, h, cv.rows()


def tex_sil(rng):
    """Eight 64 px cells: bust, crown, horns, ears, hood, beard, tusks, hair (mockup symbols)."""
    cv = Canvas(512, 64)

    def draw(i, d, fill, opacity=1.0):
        Symbol(cv, i * 64, 0, 64, 100, 100).path(d, fill, opacity=opacity)
    draw(0, "M50 22 a17 19 0 1 1 -0.1 0 Z M14 100 C16 72 30 62 50 62 C70 62 84 72 86 100 Z", hex_rgb("#0b0f15"), 0.88)
    draw(1, "M32 26 L36 12 L43 22 L50 8 L57 22 L64 12 L68 26 Z", G_GOLD)
    draw(2, "M34 30 C20 26 14 14 18 6 C22 16 30 20 38 22 Z M66 30 C80 26 86 14 82 6 C78 16 70 20 62 22 Z", hex_rgb("#e9dcc0"))
    draw(3, "M34 40 L6 24 L34 34 Z M66 40 L94 24 L66 34 Z", hex_rgb("#0b0f15"), 0.88)
    draw(4, "M50 12 C28 12 24 34 26 52 L34 64 H66 L74 52 C76 34 72 12 50 12 Z", hex_rgb("#1a0e14"), 0.9)
    draw(4, "M42 40 h4 v4 h-4z M54 40 h4 v4 h-4z", hex_rgb("#ff4a3a"))
    draw(5, "M36 42 C36 66 44 76 50 80 C56 76 64 66 64 42 C58 50 42 50 36 42 Z", hex_rgb("#b8742a"))
    draw(6, "M40 48 C36 40 36 34 38 30 C40 38 42 42 44 46 Z M60 48 C64 40 64 34 62 30 C60 38 58 42 56 46 Z", hex_rgb("#f4ecd8"))
    draw(7, "M30 34 C28 14 72 14 70 34 C72 52 76 66 80 74 C70 70 66 60 66 44 C60 30 40 30 34 44 "
            "C34 60 30 70 20 74 C24 66 28 52 30 34 Z", hex_rgb("#d8c08a"))
    return 512, 64, cv.rows()


# Append-last: new textures go at the end so the shared rng stays where it was for every file above.
TEXTURES = [
    ("felt_alliance", tex_felt("alliance")), ("felt_horde", tex_felt("horde")),
    ("frame_alliance", tex_frame("alliance")), ("frame_horde", tex_frame("horde")),
    ("cap_alliance", tex_cap("alliance")), ("cap_horde", tex_cap("horde")),
    ("stone", tex_stone),
    ("oval_alliance", tex_oval("alliance")), ("oval_horde", tex_oval("horde")),
    ("crest_alliance", tex_crest("alliance")), ("crest_horde", tex_crest("horde")),
    ("coins", tex_coins), ("parchment", tex_parchment), ("pring", tex_pring), ("mask", tex_mask),
    ("button_alliance", tex_button("alliance", False)), ("button_hi_alliance", tex_button("alliance", True)),
    ("button_horde", tex_button("horde", False)), ("button_hi_horde", tex_button("horde", True)),
    ("chip", tex_chip),
    ("card_back_alliance", tex_card_back("alliance")), ("card_back_horde", tex_card_back("horde")),
    ("cameo", tex_cameo), ("ribbon", tex_ribbon), ("sil", tex_sil),
]


# ---------------------------------------------------------------- preview

def write_png(path, w, h, rgb_rows):
    raw = b"".join(b"\x00" + bytes(c for px in row for c in px) for row in rgb_rows)

    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def contact_sheet(items, width=1100, pad=8):
    """items: [(w, h, rows)] laid out left to right, wrapping, over dark grey."""
    x = y = pad
    row_h = 0
    place = []
    for w, h, rows in items:
        if x + w + pad > width:
            x, y, row_h = pad, y + row_h + pad, 0
        place.append((x, y, w, h, rows))
        x += w + pad
        row_h = max(row_h, h)
    height = y + row_h + pad
    bg = (42, 42, 46)
    img = [[bg] * width for _ in range(height)]
    for ox, oy, w, h, rows in place:
        for j in range(h):
            for i in range(w):
                r, g, b, a = rows[j][i]
                img[oy + j][ox + i] = tuple(int(round(clamp(c * a + bgc / 255.0 * (1 - a)) * 255))
                                            for c, bgc in zip((r, g, b), bg))
    return width, height, img


def main():
    preview = None
    if "--preview" in sys.argv:
        preview = sys.argv[sys.argv.index("--preview") + 1]
    os.makedirs(OUT, exist_ok=True)
    rng = random.Random(SEED)
    made = []
    for name, fn in TEXTURES:
        w, h, rows = fn(rng)
        write_tga(os.path.join(OUT, name + ".tga"), w, h, rows)
        made.append((w, h, rows))
        print("media/skin/%s.tga %dx%d" % (name, w, h))

    # Self-check: every file is uncompressed 32-bit RGBA with power-of-two sides.
    for name, _ in TEXTURES:
        kind, w, h, bpp, desc, size = read_tga_header(os.path.join(OUT, name + ".tga"))
        assert kind == 2, "%s: not uncompressed true-colour" % name
        assert bpp == 32 and (desc & 0x0F) == 8, "%s: not RGBA" % name
        assert is_pow2(w) and is_pow2(h), "%s: %dx%d is not a power of two" % (name, w, h)
        assert size == 18 + w * h * 4, "%s: unexpected file size" % name

    if preview:
        os.makedirs(preview, exist_ok=True)
        w, h, img = contact_sheet(made)
        write_png(os.path.join(preview, "skin.png"), w, h, img)
        print("preview " + os.path.join(preview, "skin.png"))


if __name__ == "__main__":
    main()
