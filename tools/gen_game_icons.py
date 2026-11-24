"""Renders the game icons (tools/game-icons/*.svg, from game-icons.net,
CC BY 3.0) into media/games/<game>.tga: 64 x 64, white with the shape in
the alpha channel, so the addon tints them with SetVertexColor.

Standard library only: a small SVG path parser (M L H V C S Q T A Z, absolute
and relative) and a supersampled non-zero scanline fill. Deterministic, so
reruns write identical files. Run from anywhere:
    python tools/gen_game_icons.py
"""
import math
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "tools", "game-icons")
OUT = os.path.join(ROOT, "media", "games")
sys.path.insert(0, os.path.join(ROOT, "tools"))
from gen_textures import write_tga, read_tga_header  # noqa: E402

SIZE = 64        # output pixels
SS = 8           # samples per pixel along each axis
VIEW = 512.0     # the icons' viewBox side
CURVE_STEPS = 24

# game id -> source file (author/name.svg as on game-icons.net)
ICONS = {
    "belot": "aussiesim/card-jack-clubs.svg",
    "santase": "aussiesim/card-queen-hearts.svg",
    "tabla": "delapouite/backgammon.svg",
    "holdem": "lorc/poker-hand.svg",
    "ttt": "delapouite/tic-tac-toe.svg",
    "deathroll": "lorc/skull-crossed-bones.svg",
    "chess": "own/chess-knight.svg",
}

TOKEN = re.compile(r"[MmLlHhVvCcSsQqTtAaZz]|[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?")


def tokens(d):
    return TOKEN.findall(d)


def arc_points(x0, y0, rx, ry, phi, large, sweep, x1, y1):
    """Endpoint arc (SVG F.6.5) flattened, without the start point."""
    if rx == 0 or ry == 0:
        return [(x1, y1)]
    rx, ry = abs(rx), abs(ry)
    cp, sp = math.cos(math.radians(phi)), math.sin(math.radians(phi))
    dx, dy = (x0 - x1) / 2, (y0 - y1) / 2
    x1p, y1p = cp * dx + sp * dy, -sp * dx + cp * dy
    lam = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
    if lam > 1:
        s = math.sqrt(lam)
        rx, ry = rx * s, ry * s
    num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
    den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
    co = math.sqrt(max(0.0, num / den)) if den else 0.0
    if large == sweep:
        co = -co
    cxp, cyp = co * rx * y1p / ry, -co * ry * x1p / rx
    cx = cp * cxp - sp * cyp + (x0 + x1) / 2
    cy = sp * cxp + cp * cyp + (y0 + y1) / 2

    def ang(ux, uy, vx, vy):
        a = math.atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        return a

    t1 = ang(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
    dt = ang((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
    if not sweep and dt > 0:
        dt -= 2 * math.pi
    elif sweep and dt < 0:
        dt += 2 * math.pi
    n = max(4, int(abs(dt) / (math.pi / 32)))
    pts = []
    for i in range(1, n + 1):
        t = t1 + dt * i / n
        ex, ey = rx * math.cos(t), ry * math.sin(t)
        pts.append((cp * ex - sp * ey + cx, sp * ex + cp * ey + cy))
    pts[-1] = (x1, y1)
    return pts


def cubic(p0, p1, p2, p3):
    out = []
    for i in range(1, CURVE_STEPS + 1):
        t = i / CURVE_STEPS
        u = 1 - t
        out.append((u * u * u * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t * t * t * p3[0],
                    u * u * u * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t * t * t * p3[1]))
    return out


def quad(p0, p1, p2):
    out = []
    for i in range(1, CURVE_STEPS + 1):
        t = i / CURVE_STEPS
        u = 1 - t
        out.append((u * u * p0[0] + 2 * u * t * p1[0] + t * t * p2[0],
                    u * u * p0[1] + 2 * u * t * p1[1] + t * t * p2[1]))
    return out


def parse(d):
    """Path data -> a list of closed polygons (lists of (x, y))."""
    tk = tokens(d)
    i, cmd = 0, None
    x = y = sx = sy = 0.0
    last_c = last_q = None
    polys, cur = [], []

    def num():
        nonlocal i
        v = float(tk[i])
        i += 1
        return v

    def flush():
        nonlocal cur
        if len(cur) > 2:
            polys.append(cur)
        cur = []

    while i < len(tk):
        if re.match(r"[A-Za-z]", tk[i]):
            cmd = tk[i]
            i += 1
            if cmd in "Zz":
                x, y = sx, sy
                flush()
                last_c = last_q = None
                continue
        rel = cmd.islower()
        c = cmd.upper()
        if not cur and c != "M":  # drawing on after a Z starts at the subpath's start
            cur = [(x, y)]
        ox, oy = (x, y) if rel else (0.0, 0.0)
        if c == "M":
            flush()
            x, y = ox + num(), oy + num()
            sx, sy = x, y
            cur = [(x, y)]
            cmd = "l" if rel else "L"  # later pairs are line-tos
            last_c = last_q = None
        elif c == "L":
            x, y = ox + num(), oy + num()
            cur.append((x, y))
            last_c = last_q = None
        elif c == "H":
            x = ox + num()
            cur.append((x, y))
            last_c = last_q = None
        elif c == "V":
            y = (y if rel else 0.0) + num()
            cur.append((x, y))
            last_c = last_q = None
        elif c == "C":
            p1 = (ox + num(), oy + num())
            p2 = (ox + num(), oy + num())
            p3 = (ox + num(), oy + num())
            cur += cubic((x, y), p1, p2, p3)
            x, y = p3
            last_c, last_q = p2, None
        elif c == "S":
            p1 = (2 * x - last_c[0], 2 * y - last_c[1]) if last_c else (x, y)
            p2 = (ox + num(), oy + num())
            p3 = (ox + num(), oy + num())
            cur += cubic((x, y), p1, p2, p3)
            x, y = p3
            last_c, last_q = p2, None
        elif c == "Q":
            p1 = (ox + num(), oy + num())
            p2 = (ox + num(), oy + num())
            cur += quad((x, y), p1, p2)
            x, y = p2
            last_q, last_c = p1, None
        elif c == "T":
            p1 = (2 * x - last_q[0], 2 * y - last_q[1]) if last_q else (x, y)
            p2 = (ox + num(), oy + num())
            cur += quad((x, y), p1, p2)
            x, y = p2
            last_q, last_c = p1, None
        elif c == "A":
            rx, ry, phi = num(), num(), num()
            large, sweep = num() != 0, num() != 0
            nx, ny = ox + num(), oy + num()
            cur += arc_points(x, y, rx, ry, phi, large, sweep, nx, ny)
            x, y = nx, ny
            last_c = last_q = None
        else:
            raise ValueError("unsupported path command " + cmd)
    flush()
    return polys


def white_paths(svg):
    """The d of every white path (the black background square is left out)."""
    out = []
    for attrs in re.findall(r"<path([^>]*)/?>", svg):
        d = re.search(r'\sd="([^"]+)"', attrs)
        fill = re.search(r'fill="([^"]+)"', attrs)
        if d and fill and fill.group(1).lower() in ("#fff", "#ffffff", "white"):
            out.append(d.group(1))
    return out


def rasterize(polys):
    """Non-zero coverage of the polygons -> SIZE x SIZE alpha rows (0..1)."""
    n = SIZE * SS
    k = n / VIEW
    edges = []
    for poly in polys:
        for j in range(len(poly)):
            (x0, y0), (x1, y1) = poly[j], poly[(j + 1) % len(poly)]
            if y0 != y1:
                edges.append((x0 * k, y0 * k, x1 * k, y1 * k))
    cover = [[0] * SIZE for _ in range(SIZE)]
    for sy in range(n):
        yc = sy + 0.5
        xs = []
        for x0, y0, x1, y1 in edges:
            if (y0 <= yc < y1) or (y1 <= yc < y0):
                xs.append((x0 + (yc - y0) * (x1 - x0) / (y1 - y0), 1 if y1 > y0 else -1))
        if not xs:
            continue
        xs.sort()
        wind, row = 0, cover[sy // SS]
        for idx in range(len(xs) - 1):
            wind += xs[idx][1]
            if wind != 0:
                a = max(0, int(math.ceil(xs[idx][0] - 0.5)))
                b = min(n - 1, int(math.ceil(xs[idx + 1][0] - 0.5)) - 1)
                for sx in range(a, b + 1):
                    row[sx // SS] += 1
    total = SS * SS
    return [[min(1.0, c / total) for c in r] for r in cover]


def render(src, dst):
    with open(src, "r", encoding="utf-8") as f:
        svg = f.read()
    polys = []
    for d in white_paths(svg):
        polys += parse(d)
    alpha = rasterize(polys)
    rows = [[(1.0, 1.0, 1.0, a) for a in r] for r in alpha]
    write_tga(dst, SIZE, SIZE, rows)


def main(argv):
    if len(argv) == 3:  # one file: gen_game_icons.py in.svg out.tga (for previews)
        render(argv[1], argv[2])
        return
    os.makedirs(OUT, exist_ok=True)
    for game, rel in sorted(ICONS.items()):
        dst = os.path.join(OUT, game + ".tga")
        render(os.path.join(SRC, *rel.split("/")), dst)
        kind, w, h, bpp, desc, size = read_tga_header(dst)
        assert kind == 2 and bpp == 32 and (desc & 0x0F) == 8 and w == h == SIZE, game
        assert size == 18 + w * h * 4, game
        print("media/games/%s.tga %dx%d  <- %s" % (game, w, h, rel))


if __name__ == "__main__":
    main(sys.argv)
