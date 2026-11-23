"""Generates the addon textures in media/ as 32-bit uncompressed TGA.

Standard library only. Procedural and deterministic: a fixed random seed,
so reruns write identical files. Run from anywhere:
    python tools/gen_textures.py
"""
import math
import os
import random
import struct

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MEDIA = os.path.join(ROOT, "media")
SEED = 20261120


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


# Palette (global constraints, spec 5.1).
WOOD_LIGHT = hex_rgb("#4a2c1a")
WOOD_DARK = hex_rgb("#2e190e")
FELT_CENTER = hex_rgb("#7a1f24")
FELT_EDGE = hex_rgb("#2c090b")
BRASS = hex_rgb("#b0813f")
BRASS_LIGHT = hex_rgb("#e9c98a")
BRASS_DARK = tuple(c * 0.55 for c in BRASS)
INK = hex_rgb("#f3e2c0")
GOLD = hex_rgb("#f2c94c")
CREAM = hex_rgb("#fbf3e2")
RED_PAINT = hex_rgb("#a3161c")
WHITE = (1.0, 1.0, 1.0)
# Cards (mockup 07, variant 1 "Кръчмата на гилдията").
CARD_EDGE = hex_rgb("#c7ad82")
GILT = hex_rgb("#c19350")
WALNUT_DARK = hex_rgb("#3b1d10")
WALNUT = hex_rgb("#5c311a")
WALNUT_DEEP = hex_rgb("#2e190e")


# ---------------------------------------------------------------- helpers

def clamp(v, lo=0.0, hi=1.0):
    return lo if v < lo else hi if v > hi else v


def mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def smooth(t):
    return t * t * (3.0 - 2.0 * t)


def cover(sd):
    """Anti-aliased coverage from a signed distance in pixels (negative = inside)."""
    return clamp(0.5 - sd)


def over(dst, src, alpha):
    """Composites colour `src` with coverage `alpha` over premultiplied-free RGBA `dst`."""
    r, g, b, a = dst
    out_a = alpha + a * (1.0 - alpha)
    if out_a <= 0.0:
        return (0.0, 0.0, 0.0, 0.0)
    k = a * (1.0 - alpha)
    return ((src[0] * alpha + r * k) / out_a,
            (src[1] * alpha + g * k) / out_a,
            (src[2] * alpha + b * k) / out_a,
            out_a)


def brass_at(t):
    """Brass shade for a vertical position t in [0, 1]: light top edge, dark bottom edge."""
    if t < 0.5:
        return mix(BRASS_LIGHT, BRASS, smooth(t * 2.0))
    return mix(BRASS, BRASS_DARK, smooth((t - 0.5) * 2.0))


class PeriodicNoise:
    """Value noise on a wrapping lattice, so textures built from it tile seamlessly."""

    def __init__(self, rng, gx, gy):
        self.gx, self.gy = gx, gy
        self.v = [[rng.random() for _ in range(gx)] for _ in range(gy)]

    def at(self, u, v):
        """u, v in lattice units (wrap at gx, gy)."""
        x0, y0 = int(math.floor(u)), int(math.floor(v))
        fx, fy = smooth(u - x0), smooth(v - y0)
        x0 %= self.gx
        y0 %= self.gy
        x1, y1 = (x0 + 1) % self.gx, (y0 + 1) % self.gy
        a = self.v[y0][x0] + (self.v[y0][x1] - self.v[y0][x0]) * fx
        b = self.v[y1][x0] + (self.v[y1][x1] - self.v[y1][x0]) * fx
        return a + (b - a) * fy


def fbm(layers, x, y, w, h):
    """Sum of noise layers [(noise, weight)], sampled at pixel (x, y) of a w x h tile."""
    total, norm = 0.0, 0.0
    for noise, weight in layers:
        total += noise.at(x * noise.gx / w, y * noise.gy / h) * weight
        norm += weight
    return total / norm


def sd_circle(x, y, cx, cy, r):
    return math.hypot(x - cx, y - cy) - r


def sd_round_rect(x, y, x0, y0, x1, y1, r):
    cx, cy = (x0 + x1) / 2.0, (y0 + y1) / 2.0
    hx, hy = (x1 - x0) / 2.0 - r, (y1 - y0) / 2.0 - r
    qx, qy = abs(x - cx) - hx, abs(y - cy) - hy
    outside = math.hypot(max(qx, 0.0), max(qy, 0.0))
    return outside + min(max(qx, qy), 0.0) - r


def sd_convex(x, y, pts):
    """Distance to a convex polygon (points clockwise on screen, y down): the largest
    edge-line distance. Exact inside and along edges, slightly sharp past corners."""
    d = -1e9
    for i in range(len(pts)):
        (ax, ay), (bx, by) = pts[i], pts[(i + 1) % len(pts)]
        ex, ey = bx - ax, by - ay
        length = math.hypot(ex, ey)
        d = max(d, ((x - ax) * ey - (y - ay) * ex) / length)
    return d


def render(w, h, fn):
    """fn(px, py) -> (r, g, b, a) with px, py at pixel centres; rows top to bottom."""
    return [[fn(x + 0.5, y + 0.5) for x in range(w)] for y in range(h)]


# ---------------------------------------------------------------- textures

def tex_wood(rng):
    w = h = 256
    grain = [(PeriodicNoise(rng, 4, 32), 1.0), (PeriodicNoise(rng, 8, 64), 0.5),
             (PeriodicNoise(rng, 16, 128), 0.25)]
    warp = PeriodicNoise(rng, 4, 4)

    def px(x, y):
        # Grain runs horizontally: stretched noise plus warped sine streaks.
        n = fbm(grain, x, y, w, h)
        bend = warp.at(x * 4 / w, y * 4 / h) * 6.0
        streak = 0.5 + 0.5 * math.sin((y / h * 24.0 + bend) * 2.0 * math.pi)
        t = clamp(0.65 * n + 0.35 * streak * n * 1.4)
        return mix(WOOD_DARK, WOOD_LIGHT, t) + (1.0,)
    return w, h, render(w, h, px)


def tex_felt(rng):
    w = h = 256
    fine = [(PeriodicNoise(rng, 128, 128), 1.0), (PeriodicNoise(rng, 64, 64), 0.5)]
    cx = cy = w / 2.0
    rmax = math.hypot(cx, cy)

    def px(x, y):
        # Radial gradient (symmetric, so opposite edges match) under fine fibre noise.
        t = smooth(clamp(math.hypot(x - cx, y - cy) / rmax))
        base = mix(FELT_CENTER, FELT_EDGE, t)
        k = 0.88 + 0.24 * fbm(fine, x, y, w, h)
        return tuple(clamp(c * k) for c in base) + (1.0,)
    return w, h, render(w, h, px)


def tex_frame(rng):
    w = h = 64
    band = 12.0

    def px(x, y):
        outer = sd_round_rect(x, y, 0.0, 0.0, w, h, 6.0)
        inner = sd_round_rect(x, y, band, band, w - band, h - band, 2.0)
        a = cover(outer) * cover(-inner)
        if a <= 0.0:
            return (0.0, 0.0, 0.0, 0.0)
        col = brass_at(y / h)
        # Bevel: lighter near the outer edge, a dark line along the inner edge.
        col = mix(col, BRASS_LIGHT, 0.35 * clamp(1.0 + outer / 2.5))
        col = mix(col, BRASS_DARK, 0.6 * clamp(1.0 + inner / 1.5))
        return col + (a,)
    return w, h, render(w, h, px)


def tex_ring(rng):
    w = h = 128
    c, r_out, r_in = 64.0, 62.0, 50.0

    def px(x, y):
        d = math.hypot(x - c, y - c)
        a = cover(d - r_out) * cover(r_in - d)
        if a <= 0.0:
            return (0.0, 0.0, 0.0, 0.0)
        col = brass_at((y - (c - r_out)) / (2.0 * r_out))
        mid = (r_out + r_in) / 2.0
        col = mix(col, BRASS_LIGHT, 0.3 * clamp(1.0 - abs(d - mid) / 3.0))
        return col + (a,)
    return w, h, render(w, h, px)


def tex_tabletop(rng):
    w = h = 128
    c, r, rim = 64.0, 62.0, 5.0
    grain = [(PeriodicNoise(rng, 4, 24), 1.0), (PeriodicNoise(rng, 8, 48), 0.5)]

    def px(x, y):
        d = math.hypot(x - c, y - c)
        a = cover(d - r)
        if a <= 0.0:
            return (0.0, 0.0, 0.0, 0.0)
        if d > r - rim:
            col = brass_at(y / h)
        else:
            col = mix(WOOD_DARK, WOOD_LIGHT, fbm(grain, x, y, w, h))
            # Soft light from the top, shadow near the rim.
            col = mix(col, WOOD_LIGHT, 0.25 * clamp((c - y) / r))
            col = mix(col, WOOD_DARK, 0.5 * clamp((d - (r - rim - 12.0)) / 12.0))
        return col + (a,)
    return w, h, render(w, h, px)


def tex_chair(rng):
    w = h = 64
    c, r = 32.0, 28.0

    def px(x, y):
        a = cover(sd_circle(x, y, c, c, r))
        if a <= 0.0:
            return (0.0, 0.0, 0.0, 0.0)
        # Near-white so the class-colour tint stays true; a faint shade at the bottom.
        shade = 1.0 - 0.18 * clamp((y - (c - r)) / (2.0 * r))
        return (shade, shade, shade, a)
    return w, h, render(w, h, px)


def tex_chair_empty(rng):
    w = h = 64
    c, r, half, dashes = 32.0, 26.0, 1.75, 12

    def px(x, y):
        d = math.hypot(x - c, y - c)
        ring = cover(abs(d - r) - half)
        if ring <= 0.0:
            return (0.0, 0.0, 0.0, 0.0)
        ang = (math.atan2(y - c, x - c) / (2.0 * math.pi)) % 1.0
        phase = (ang * dashes) % 1.0
        # Dash on for 60 % of each period; distance to the gap converted to pixels.
        arc = 2.0 * math.pi * r / dashes
        sd_dash = (abs(phase - 0.3) - 0.3) * arc
        a = ring * cover(sd_dash)
        if a <= 0.0:
            return (0.0, 0.0, 0.0, 0.0)
        return BRASS_LIGHT + (a,)
    return w, h, render(w, h, px)


def make_button(fill_top, fill_bottom, border):
    w, h = 128, 32

    def px(x, y):
        outer = sd_round_rect(x, y, 0.0, 0.0, w, h, 6.0)
        a = cover(outer)
        if a <= 0.0:
            return (0.0, 0.0, 0.0, 0.0)
        inner = sd_round_rect(x, y, 2.0, 2.0, w - 2.0, h - 2.0, 4.0)
        fill = mix(fill_top, fill_bottom, smooth(y / h))
        col = mix(border(y / h), fill, cover(inner))
        return col + (a,)
    return w, h, render(w, h, px)


def tex_button(rng):
    return make_button(RED_PAINT, tuple(c * 0.6 for c in RED_PAINT), brass_at)


def tex_button_hi(rng):
    bright = tuple(clamp(c * 1.35) for c in RED_PAINT)
    return make_button(bright, RED_PAINT, lambda t: mix(BRASS_LIGHT, GOLD, t))


def tex_glow(rng):
    w = h = 128
    c = 64.0

    def px(x, y):
        d = math.hypot(x - c, y - c) / c
        a = math.exp(-d * d * 4.0) * clamp((1.0 - d) * 4.0)
        return GOLD + (a,)
    return w, h, render(w, h, px)


def tex_info(rng):
    w = h = 32
    c = 16.0

    def px(x, y):
        d = math.hypot(x - c, y - c)
        ring = cover(abs(d - 13.5) - 1.25)
        dot = cover(sd_circle(x, y, c, 9.5, 1.9))
        stem = cover(sd_round_rect(x, y, c - 1.6, 13.0, c + 1.6, 23.5, 1.0))
        a = max(ring, dot, stem)
        if a <= 0.0:
            return (0.0, 0.0, 0.0, 0.0)
        return BRASS_LIGHT + (a,)
    return w, h, render(w, h, px)


def tex_icon(rng, bare=False):
    """The mug on dark wood; `bare`: the mug alone on a clear background."""
    w = h = 64
    grain = [(PeriodicNoise(rng, 2, 16), 1.0), (PeriodicNoise(rng, 4, 32), 0.5)]

    def px(x, y):
        # Dark wood background (square: the minimap button crops it round).
        col = mix(WOOD_DARK, WOOD_LIGHT, 0.6 * fbm(grain, x, y, w, h))
        out = col + ((0.0 if bare else 1.0),)
        # Handle: a brass ring on the right.
        handle = cover(abs(math.hypot(x - 44.0, y - 34.0) - 8.0) - 2.5) * (1.0 if x > 40.0 else 0.0)
        out = over(out, brass_at((y - 24.0) / 20.0), handle)
        # Body: wooden staves with brass hoops.
        body = cover(sd_round_rect(x, y, 14.0, 20.0, 42.0, 54.0, 3.0))
        stave = mix(WOOD_LIGHT, tuple(c * 1.5 for c in WOOD_LIGHT), 0.5 + 0.5 * math.cos((x - 14.0) / 28.0 * math.pi * 4.0))
        stave = mix(stave, WOOD_DARK, clamp((x - 28.0) / 16.0) * 0.6)
        hoop = 1.0 if (24.0 <= y <= 27.0 or 46.0 <= y <= 49.0) else 0.0
        body_col = mix(stave, brass_at((x - 14.0) / 28.0), hoop)
        out = over(out, body_col, body)
        # Foam: cream bubbles over the rim.
        foam = max(cover(sd_round_rect(x, y, 12.0, 14.0, 44.0, 22.0, 4.0)),
                   cover(sd_circle(x, y, 20.0, 14.0, 5.0)),
                   cover(sd_circle(x, y, 29.0, 12.0, 6.0)),
                   cover(sd_circle(x, y, 38.0, 14.0, 5.0)))
        out = over(out, mix(CREAM, INK, clamp((y - 8.0) / 14.0)), foam)
        return out
    return w, h, render(w, h, px)


def tex_mug(rng):
    return tex_icon(rng, bare=True)


# Cards are drawn at 40x58 on screen from a 64x128 file, so one file pixel is
# 0.625 screen px across and 0.453 down. Shapes that must look round on screen
# (the medallion) measure y in units of x by dividing by CARD_STRETCH.
CARD_W, CARD_H = 64, 128
CARD_STRETCH = (CARD_H / 58.0) / (CARD_W / 40.0)


def sd_card(x, y):
    return sd_round_rect(x, y, 0.0, 0.0, CARD_W, CARD_H, 8.0)


def tex_card(rng):
    def px(x, y):
        sd = sd_card(x, y)
        # Cream face inside a 2 px edge, a thin gilt line 4 px further in.
        col = mix(CARD_EDGE, CREAM, cover(sd + 2.0))
        col = mix(col, GILT, cover(abs(sd + 4.5) - 0.5))
        return col + (cover(sd),)
    return CARD_W, CARD_H, render(CARD_W, CARD_H, px)


def tex_card_back(rng):
    cx, cy = CARD_W / 2.0, CARD_H / 2.0
    root2 = math.sqrt(2.0)

    def px(x, y):
        sd = sd_card(x, y)
        # 45 degree stripes, 8 px wide: q runs across the stripes, centred on a light one.
        q = ((x + y) / root2 - 4.0) % 16.0 - 8.0
        col = mix(WALNUT_DARK, WALNUT, cover(abs(q) - 4.0))
        # Medallion: a gilt ring round a quiet walnut field (the guild emblem, when
        # the client has one, is drawn over this centre; the ring is the fallback).
        r = math.hypot(x - cx, (y - cy) / CARD_STRETCH)
        col = mix(col, WALNUT_DEEP, 0.7 * cover(r - 15.0))
        col = mix(col, GILT, cover(abs(r - 16.5) - 1.5))
        col = mix(col, GILT, 0.6 * cover(abs(r - 12.0) - 0.5))
        col = mix(GILT, col, cover(sd + 2.0))
        return col + (cover(sd),)
    return CARD_W, CARD_H, render(CARD_W, CARD_H, px)


def sd_heart(x, y):
    """Heart in a 32x32 cell: two circles over a downward triangle."""
    return min(sd_circle(x, y, 10.5, 11.5, 6.2), sd_circle(x, y, 21.5, 11.5, 6.2),
               sd_convex(x, y, [(4.5, 13.5), (27.5, 13.5), (16.0, 28.0)]))


def sd_stem(x, y, top, half, bottom):
    return sd_convex(x, y, [(16.0, top), (16.0 + half, bottom), (16.0 - half, bottom)])


def sd_club(x, y):
    return min(sd_circle(x, y, 16.0, 9.0, 5.6), sd_circle(x, y, 9.2, 17.5, 5.6),
               sd_circle(x, y, 22.8, 17.5, 5.6), sd_circle(x, y, 16.0, 15.5, 3.5),
               sd_stem(x, y, 15.0, 4.5, 29.5))


def sd_diamond(x, y):
    return (abs(x - 16.0) + abs(y - 16.0) - 13.0) / math.sqrt(2.0)


def sd_spade(x, y):
    return min(sd_heart(x, 30.0 - y), sd_stem(x, y, 18.0, 5.0, 30.0))


def tex_suits(rng):
    """Four 32x32 cells, left to right: club, diamond, heart, spade. White, tinted in code."""
    w, h = 128, 32
    shapes = (sd_club, sd_diamond, sd_heart, sd_spade)

    def px(x, y):
        cell = min(int(x // 32), 3)
        return WHITE + (cover(shapes[cell](x - cell * 32.0, y)),)
    return w, h, render(w, h, px)


# Табла board pieces (mockup 07, variant 1). White ones are tinted in code.
DICE_CREAM = hex_rgb("#f6ecd6")
DICE_RIM = hex_rgb("#8a6a2b")
# Pip places of the mockup's 30 px die, scaled to a 32 px cell in tex_dice.
PIPS = {1: [(15, 15)], 2: [(9, 9), (21, 21)], 3: [(9, 9), (15, 15), (21, 21)],
        4: [(9, 9), (21, 9), (9, 21), (21, 21)],
        5: [(9, 9), (21, 9), (15, 15), (9, 21), (21, 21)],
        6: [(9, 8), (21, 8), (9, 15), (21, 15), (9, 22), (21, 22)]}


def tex_point(rng):
    """A white triangle, base the whole top edge, tip at the bottom centre."""
    w, h = 32, 128
    tri = [(0.0, 0.0), (32.0, 0.0), (16.0, 128.0)]
    return w, h, render(w, h, lambda x, y: WHITE + (cover(sd_convex(x, y, tri)),))


def tex_checker(rng):
    """A white disc with a grey rim and an inner ring, tinted in code."""
    w = h = 64
    grey = (0.45, 0.45, 0.45)

    def px(x, y):
        d = math.hypot(x - 32.0, y - 32.0)
        a = cover(d - 30.0)
        if a <= 0.0:
            return (0.0, 0.0, 0.0, 0.0)
        col = mix(grey, WHITE, cover(-(d - 27.0)))
        col = mix(col, grey, cover(abs(d - 18.0) - 1.0))
        return col + (a,)
    return w, h, render(w, h, px)


def tex_dice(rng):
    """Six 32x32 faces: 1-4 on the top row, 5 and 6 below; the last two cells empty."""
    w, h = 128, 64
    k = 32.0 / 30.0

    def px(x, y):
        col, row = int(x // 32), int(y // 32)
        face = row * 4 + col + 1
        if face > 6:
            return (0.0, 0.0, 0.0, 0.0)
        lx, ly = x - col * 32.0, y - row * 32.0
        sd = sd_round_rect(lx, ly, 1.0, 1.0, 31.0, 31.0, 5.0)
        a = cover(sd)
        if a <= 0.0:
            return (0.0, 0.0, 0.0, 0.0)
        out = mix(DICE_RIM, DICE_CREAM, cover(sd + 2.0))
        for (px_, py_) in PIPS[face]:
            out = mix(out, RED_PAINT, cover(sd_circle(lx, ly, px_ * k, py_ * k, 3.0)))
        return out + (a,)
    return w, h, render(w, h, px)


def tex_oval(rng):
    """The Холдем table: a wood rim, a brass line, a radial felt; transparent outside."""
    w, h = 512, 256
    cx, cy, rx, ry = 256.0, 128.0, 256.0, 128.0
    rim, line = 14.0, 3.0
    oval_wood_a, oval_wood_b = hex_rgb("#4a2c1a"), hex_rgb("#2e190e")
    felt_in, felt_out = hex_rgb("#8d2a30"), hex_rgb("#4d1216")

    def sd_ellipse(x, y, ax, ay):
        # First-order distance to an ellipse: (f - 1) / |grad f| with f = (x/a)^2 + (y/b)^2.
        dx, dy = x - cx, y - cy
        f = math.sqrt((dx / ax) ** 2 + (dy / ay) ** 2)
        if f < 1e-9:
            return -min(ax, ay)
        gx, gy = dx / (ax * ax), dy / (ay * ay)
        return (f - 1.0) * f / math.hypot(gx, gy)

    def px(x, y):
        outer = sd_ellipse(x, y, rx, ry)
        a = cover(outer)
        if a <= 0.0:
            return (0.0, 0.0, 0.0, 0.0)
        # Wood rim (top light to bottom dark), the felt inside the brass line, the line between.
        wood = mix(oval_wood_a, oval_wood_b, clamp((y - (cy - ry)) / (2.0 * ry)))
        inner = sd_ellipse(x, y, rx - rim - line, ry - rim - line)
        brass_edge = sd_ellipse(x, y, rx - rim, ry - rim)
        dx, dy = (x - cx) / (rx - rim - line), (y - cy) / (ry - rim - line)
        felt = mix(felt_in, felt_out, smooth(clamp(math.hypot(dx, dy))))
        col = mix(wood, BRASS, cover(brass_edge))
        col = mix(col, felt, cover(inner))
        return col + (a,)
    return w, h, render(w, h, px)


def tex_chip(rng):
    """A gold chip: a 2 px dark rim and a dashed ring of eight dashes."""
    w = h = 32
    c, r, dashes = 16.0, 14.0, 8
    gold, rim, ink = GOLD, hex_rgb("#8a5a10"), hex_rgb("#7a5210")

    def px(x, y):
        d = math.hypot(x - c, y - c)
        a = cover(d - r)
        if a <= 0.0:
            return (0.0, 0.0, 0.0, 0.0)
        col = mix(rim, gold, cover(d - (r - 2.0)))
        ang = (math.atan2(y - c, x - c) / (2.0 * math.pi)) % 1.0
        phase = (ang * dashes) % 1.0
        arc = 2.0 * math.pi * 9.0 / dashes
        ring = cover(abs(d - 9.0) - 1.0) * cover((abs(phase - 0.5) - 0.25) * arc)
        col = mix(col, ink, ring)
        return col + (a,)
    return w, h, render(w, h, px)


TEXTURES = [
    ("wood", tex_wood), ("felt", tex_felt), ("frame", tex_frame), ("ring", tex_ring),
    ("tabletop", tex_tabletop), ("chair", tex_chair), ("chair_empty", tex_chair_empty),
    ("button", tex_button), ("button_hi", tex_button_hi), ("glow", tex_glow),
    ("info", tex_info), ("icon", tex_icon),
    # Appended, so the shared rng stays where it was for every file above.
    ("card", tex_card), ("card_back", tex_card_back), ("suits", tex_suits),
    ("point", tex_point), ("checker", tex_checker), ("dice", tex_dice),
    ("oval", tex_oval), ("chip", tex_chip),
    ("mug", tex_mug),  # last: the files before it keep their random draws
]


# ---------------------------------------------------------------- TGA I/O

def write_tga(path, w, h, rows):
    """Uncompressed true-colour TGA, 32 bpp BGRA, bottom-left origin."""
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 8)
    body = bytearray()
    for row in reversed(rows):
        for r, g, b, a in row:
            body += bytes((int(round(clamp(b) * 255)), int(round(clamp(g) * 255)),
                           int(round(clamp(r) * 255)), int(round(clamp(a) * 255))))
    with open(path, "wb") as f:
        f.write(header)
        f.write(body)


def read_tga_header(path):
    with open(path, "rb") as f:
        data = f.read()
    (_, _, kind, _, _, _, _, _, w, h, bpp, desc) = struct.unpack("<BBBHHBHHHHBB", data[:18])
    return kind, w, h, bpp, desc, len(data)


def is_pow2(n):
    return n > 0 and (n & (n - 1)) == 0


def main():
    os.makedirs(MEDIA, exist_ok=True)
    rng = random.Random(SEED)
    for name, fn in TEXTURES:
        w, h, rows = fn(rng)
        write_tga(os.path.join(MEDIA, name + ".tga"), w, h, rows)
        print("media/%s.tga %dx%d" % (name, w, h))

    # Self-check: every file is uncompressed 32-bit RGBA with power-of-two sides.
    for name, _ in TEXTURES:
        kind, w, h, bpp, desc, size = read_tga_header(os.path.join(MEDIA, name + ".tga"))
        assert kind == 2, "%s: not uncompressed true-colour" % name
        assert bpp == 32 and (desc & 0x0F) == 8, "%s: not RGBA" % name
        assert is_pow2(w) and is_pow2(h), "%s: %dx%d is not a power of two" % (name, w, h)
        assert size == 18 + w * h * 4, "%s: unexpected file size" % name


if __name__ == "__main__":
    main()
