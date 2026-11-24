"""Headless screenshots, part 2: draws the draw lists of tools/shots/scenes.lua.

Each tools/shots/build/<scene>.json holds the visible textures and font strings
of one scene in the client's draw order, with their screen rects (UI units,
y up) and every drawing attribute. They are drawn here with the addon's own
textures (media/**/*.tga) and fonts (media/fonts/*.ttf) at SS x the output
scale, then scaled down, over a dark neutral backdrop, and cropped to the
scene's window(s). Run from the repo root:
    python tools/shots/render.py [scene ...]
Output: docs/screenshots/<scene>.png
"""
import json
import math
import os
import re
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
BUILD = os.path.join(ROOT, "tools", "shots", "build")
OUT = os.environ.get("SHOTS_OUT") or os.path.join(ROOT, "docs", "screenshots")  # SHOTS_OUT: elsewhere (the lint shots)
SCALE = 1.25   # output px per UI unit (a scene's draw list may set its own)
SS = 2         # supersampling factor
K = SCALE * SS

_images = {}
_fonts = {}
_cap = {}


def image(path):
    """A repo texture as a premultiplied RGBa PIL image."""
    if path not in _images:
        im = Image.open(os.path.join(ROOT, path)).convert("RGBA")
        _images[path] = im.convert("RGBa")
    return _images[path]


def font(name, px):
    key = (name, round(px * 8) / 8)
    if key not in _fonts:
        _fonts[key] = ImageFont.truetype(os.path.join(ROOT, "media", "fonts", name), key[1],
                                         layout_engine=ImageFont.Layout.BASIC)
    return _fonts[key]


def cap_height(f):
    if f not in _cap:
        box = f.getbbox("H", anchor="ls")
        _cap[f] = -box[1]
    return _cap[f]


CLIENT = os.path.join(ROOT, "tools", "shots", "build", "client")
# The world behind the windows, when client_art.py took it out: a loading screen of the faction's continent.
WORLD = {
    "Alliance": "interface/glues/loadingscreens/loadscreeneasternkingdom.png",
    "Horde": "interface/glues/loadingscreens/loadscreenkalimdor.png",
}


def client_file(path):
    """A client texture path (no extension) -> its PNG under build/client, or None."""
    rel = path.lower().replace("\\", "/")
    rel = re.sub(r"\.blp$", "", rel) + ".png"
    full = os.path.join(CLIENT, *rel.split("/"))
    return os.path.relpath(full, ROOT) if os.path.exists(full) else None


class Canvas:
    def __init__(self, crop, data=None):
        self.l, self.b, self.r, self.t = crop
        self.w = int(round((self.r - self.l) * K))
        self.h = int(round((self.t - self.b) * K))
        self.px = world(self, data or {})
        if self.px is None:
            self.px = backdrop(self.w, self.h)

    def box(self, rect):
        """UI rect [l, b, r, t] -> canvas px (x0, y0, x1, y1), rounded so adjacent pieces abut."""
        l, b, r, t = rect
        return (int(round((l - self.l) * K)), int(round((self.t - t) * K)),
                int(round((r - self.l) * K)), int(round((self.t - b) * K)))

    def composite(self, rgba, x0, y0, clip=None, blend=None):
        """Draws a float RGBA patch (straight alpha, 0..1) with its top-left at x0, y0."""
        h, w = rgba.shape[:2]
        cx0, cy0, cx1, cy1 = 0, 0, self.w, self.h
        if clip is not None:
            c = self.box(clip)
            cx0, cy0, cx1, cy1 = max(cx0, c[0]), max(cy0, c[1]), min(cx1, c[2]), min(cy1, c[3])
        ax0, ay0 = max(x0, cx0), max(y0, cy0)
        ax1, ay1 = min(x0 + w, cx1), min(y0 + h, cy1)
        if ax1 <= ax0 or ay1 <= ay0:
            return
        src = rgba[ay0 - y0:ay1 - y0, ax0 - x0:ax1 - x0]
        dst = self.px[ay0:ay1, ax0:ax1]
        a = src[..., 3:4]
        if blend == "ADD":
            dst += src[..., :3] * a
            np.minimum(dst, 1.0, out=dst)
        elif blend == "MOD":
            dst *= src[..., :3] * a + (1 - a)
        else:
            dst *= (1 - a)
            dst += src[..., :3] * a


def backdrop(w, h):
    """A dark, neutral, faintly textured backdrop with a soft vignette."""
    rng = np.random.default_rng(5)
    base = np.array([0.085, 0.080, 0.078], dtype=np.float32)
    small = rng.normal(0, 1, (max(2, h // 24), max(2, w // 24))).astype(np.float32)
    blot = np.array(Image.fromarray(small).resize((w, h), Image.BICUBIC))
    grain = rng.normal(0, 1, (h, w)).astype(np.float32)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    d = np.sqrt(((xx - w / 2) / (w / 2)) ** 2 + ((yy - h / 2) / (h / 2)) ** 2)
    vign = 1.0 - 0.35 * np.clip(d - 0.3, 0, 1)
    lum = (1 + 0.07 * blot + 0.012 * grain) * vign
    return (base[None, None, :] * lum[..., None]).astype(np.float32)


def world(cv, data):
    """The faction's loading screen laid over the whole screen as the game shows it (4:3,
    covering the 16:9 screen), the part behind the crop, softened and dimmed like a world
    behind an open window -> float RGB, or None without client art."""
    rel = WORLD.get(data.get("faction") or "Alliance")
    path = rel and os.path.join(CLIENT, *rel.split("/"))
    if not path or not os.path.exists(path):
        return None
    sw, sh = data.get("screen") or (1920, 1080)
    img = Image.open(path).convert("RGB")
    iw, ih = img.size
    # The texture is square; the client stretches it to a 4:3 frame. Cover the screen with that frame.
    fw = max(sw, sh * 4 / 3)
    fh = fw * 3 / 4
    ox, oy = (fw - sw) / 2, (fh - sh) / 2

    def px(x, y_up):
        return (x + ox) / fw * iw, (sh - y_up + oy) / fh * ih

    x0, y0 = px(cv.l, cv.t)
    x1, y1 = px(cv.r, cv.b)
    patch = img.transform((cv.w, cv.h), Image.EXTENT, (x0, y0, x1, y1), resample=Image.BICUBIC)
    patch = patch.filter(ImageFilter.GaussianBlur(radius=max(1.0, cv.w / 900)))
    arr = np.asarray(patch, dtype=np.float32) / 255.0
    yy, xx = np.mgrid[0:cv.h, 0:cv.w].astype(np.float32)
    d = np.sqrt(((xx - cv.w / 2) / (cv.w / 2)) ** 2 + ((yy - cv.h / 2) / (cv.h / 2)) ** 2)
    dim = 0.62 * (1.0 - 0.35 * np.clip(d - 0.4, 0, 1))
    return (arr * dim[..., None]).astype(np.float32)


def sample(path, tc, wrap, w, h):
    """The part tc (l, r, t, b) of texture `path` scaled to w x h -> float RGBA (straight alpha)."""
    src = image(path)
    tw, th = src.size
    if tc and len(tc) == 8:  # ULx, ULy, LLx, LLy, URx, URy, LRx, LRy: axis-aligned forms only
        tc = [tc[0], tc[4], tc[1], tc[3]]
    l, r, t, b = tc if tc else (0, 1, 0, 1)
    x0, x1, y0, y1 = l * tw, r * tw, t * th, b * th
    rep_h = bool(wrap) and len(wrap) > 0 and wrap[0] == "REPEAT"
    rep_v = bool(wrap) and len(wrap) > 1 and wrap[1] == "REPEAT"
    lo_x, hi_x, lo_y, hi_y = min(x0, x1), max(x0, x1), min(y0, y1), max(y0, y1)
    if (rep_h and (lo_x < -0.01 or hi_x > tw + 0.01)) or (rep_v and (lo_y < -0.01 or hi_y > th + 0.01)):
        ix0 = math.floor(lo_x / tw) if rep_h else 0
        ix1 = math.ceil(hi_x / tw) if rep_h else 1
        iy0 = math.floor(lo_y / th) if rep_v else 0
        iy1 = math.ceil(hi_y / th) if rep_v else 1
        tiled = Image.new("RGBa", ((ix1 - ix0) * tw, (iy1 - iy0) * th))
        for i in range(ix1 - ix0):
            for j in range(iy1 - iy0):
                tiled.paste(src, (i * tw, j * th))
        src = tiled
        x0, x1, y0, y1 = x0 - ix0 * tw, x1 - ix0 * tw, y0 - iy0 * th, y1 - iy0 * th
    cw, ch = abs(x1 - x0), abs(y1 - y0)
    iw = int(min(4096, max(w, math.ceil(cw))))
    ih = int(min(4096, max(h, math.ceil(ch))))
    patch = src.transform((iw, ih), Image.EXTENT, (x0, y0, x1, y1), resample=Image.BILINEAR)
    if (iw, ih) != (w, h):
        patch = patch.resize((w, h), Image.LANCZOS if (iw > w * 1.5 or ih > h * 1.5) else Image.BILINEAR)
    arr = np.asarray(patch.convert("RGBA"), dtype=np.float32) / 255.0
    return arr


def draw_texture(cv, it):
    x0, y0, x1, y1 = cv.box(it["r"])
    w, h = x1 - x0, y1 - y0
    if w < 1 or h < 1:
        return
    if it.get("color"):
        c = it["color"]
        arr = np.empty((h, w, 4), dtype=np.float32)
        arr[...] = [c[0], c[1], c[2], c[3] if len(c) > 3 else 1]
    else:
        arr = sample(it["path"], it.get("tc"), it.get("wrap"), w, h)
    vc = it.get("vc")
    if vc:
        arr[..., 0] *= vc[0]
        arr[..., 1] *= vc[1]
        arr[..., 2] *= vc[2]
        arr[..., 3] *= vc[3] if len(vc) > 3 else 1
    arr[..., 3] *= it.get("a", 1)
    for m in it.get("masks") or []:
        mx0, my0, mx1, my1 = cv.box(m["r"])
        mw, mh = mx1 - mx0, my1 - my0
        alpha = np.zeros((h, w), dtype=np.float32)
        if mw >= 1 and mh >= 1:
            ma = sample(m["path"], m.get("tc"), None, mw, mh)[..., 3]
            ox0, oy0 = max(x0, mx0), max(y0, my0)
            ox1, oy1 = min(x1, mx1), min(y1, my1)
            if ox1 > ox0 and oy1 > oy0:
                alpha[oy0 - y0:oy1 - y0, ox0 - x0:ox1 - x0] = ma[oy0 - my0:oy1 - my0, ox0 - mx0:ox1 - mx0]
        arr[..., 3] *= alpha
    cv.composite(arr, x0, y0, it.get("clip"), it.get("blend"))


TOKEN = re.compile(r"\|c([0-9a-fA-F]{8})|\|r|\|T(.*?)\|t|\|\||([^|]+)|(\|)")


def runs(line, base):
    """A line with WoW codes -> [(kind, value, rgb)]: ("text", s, rgb) | ("tex", spec, None)."""
    out, rgb = [], base
    for m in TOKEN.finditer(line):
        if m.group(1):
            hx = m.group(1)
            rgb = (int(hx[2:4], 16) / 255, int(hx[4:6], 16) / 255, int(hx[6:8], 16) / 255)
        elif m.group(0) == "|r":
            rgb = base
        elif m.group(2) is not None:
            out.append(("tex", m.group(2), None))
        elif m.group(0) == "||":
            out.append(("text", "|", rgb))
        elif m.group(3):
            out.append(("text", m.group(3), rgb))
        elif m.group(4):
            out.append(("text", "|", rgb))
    return out


def inline_spec(spec, size):
    """|T path:h:w:x:y:tw:th:l:r:t:b|t -> (path, w, h, dx, dy, tc) in canvas px (size: font px)."""
    parts = spec.split(":")
    path = parts[0]

    def num(i, d=0.0):
        try:
            return float(parts[i])
        except (IndexError, ValueError):
            return d

    h, w = num(1), num(2)
    dx, dy = num(3), num(4)
    if h == 0:
        h = size / K
    if w == 0:
        w = h
    tc = None
    if len(parts) >= 11:
        tw, th = num(5, 1), num(6, 1)
        tc = (num(7) / tw, num(8) / tw, num(9) / th, num(10) / th)
    low = path.lower().replace("/", "\\")
    prefix = "interface\\addons\\taverngames\\"
    file = None
    if low.startswith(prefix):
        file = path[len(prefix):].replace("\\", "/")
        if not re.search(r"\.\w+$", file):
            file += ".tga"
    else:
        file = client_file(path)
    return file, w * K, h * K, dx * K, dy * K, tc


def draw_text(cv, it):
    size = it["size"] * K
    if size < 1:
        return
    f = font(it["font"], size)
    flags = it.get("flags") or ""
    stroke = 0
    if "THICKOUTLINE" in flags:
        stroke = max(1, round(2 * K))
    elif "OUTLINE" in flags:
        stroke = max(1, round(1 * K))
    color = it.get("color") or [1, 1, 1, 1]
    base = (color[0], color[1], color[2])
    alpha = (color[3] if len(color) > 3 else 1) * it.get("a", 1)
    x0, y0, x1, y1 = cv.box(it["r"])
    lh = it["lh"] * K
    lines = it["lines"]
    total = lh * len(lines)
    jv = (it.get("jv") or "MIDDLE").upper()
    if jv == "TOP":
        top = y0
    elif jv == "BOTTOM":
        top = y1 - total
    else:
        top = y0 + ((y1 - y0) - total) / 2
    jh = (it.get("jh") or "CENTER").upper()
    # A local layer around the rect, wide enough for overhanging glyphs and the shadow.
    pad = int(size * 1.5) + 4
    lx0, ly0 = int(min(x0, x0) - pad), int(min(y0, top) - pad)
    lx1, ly1 = int(x1 + pad), int(max(y1, top + total) + pad)
    lw, lh_px = lx1 - lx0, ly1 - ly0
    if lw <= 0 or lh_px <= 0 or lw * lh_px > 40_000_000:
        return
    layer = Image.new("RGBA", (lw, lh_px), (0, 0, 0, 0))
    shadow = it.get("shadow")
    capx = cap_height(f)
    placed = []
    for n, line in enumerate(lines):
        parts = runs(line, base)
        width = 0.0
        for kind, val, _ in parts:
            if kind == "text":
                width += f.getlength(val)
            else:
                width += inline_spec(val, size)[1]
        if jh == "LEFT":
            x = x0
        elif jh == "RIGHT":
            x = x1 - width
        else:
            x = x0 + ((x1 - x0) - width) / 2
        baseline = top + n * lh + lh / 2 + capx / 2
        placed.append((parts, x, baseline))

    def put(dx, dy, fixed, a_mul):
        d = ImageDraw.Draw(layer)
        for parts, x, baseline in placed:
            for kind, val, rgb in parts:
                if kind == "text":
                    c = fixed or rgb
                    fill = (int(c[0] * 255 + 0.5), int(c[1] * 255 + 0.5), int(c[2] * 255 + 0.5), int(255 * a_mul + 0.5))
                    kw = {}
                    if stroke and not fixed:
                        kw = {"stroke_width": stroke, "stroke_fill": (0, 0, 0, fill[3])}
                    d.text((x - lx0 + dx, baseline - ly0 + dy), val, font=f, fill=fill, anchor="ls", **kw)
                    x += f.getlength(val)
                else:
                    file, w, h, ox, oy, tc = inline_spec(val, size)
                    if file and not fixed and w >= 1 and h >= 1:
                        patch = sample(file, tc, None, int(round(w)), int(round(h)))
                        patch[..., 3] *= a_mul
                        img = Image.fromarray((np.clip(patch, 0, 1) * 255).astype(np.uint8), "RGBA")
                        py = baseline - capx / 2 - h / 2 - oy
                        layer.alpha_composite(img, (int(round(x - lx0 + ox)), int(round(py - ly0))))
                    x += w

    if shadow:
        sc = shadow[2:5]
        sa = shadow[5] if len(shadow) > 5 else 1
        put(shadow[0] * K, -shadow[1] * K, sc, sa)
    put(0, 0, None, 1)
    arr = np.asarray(layer, dtype=np.float32) / 255.0
    arr[..., 3] *= alpha
    cv.composite(arr, lx0, ly0, it.get("clip"))


LIMIT_KB = 600


def palettize(img, colors=256):
    """img with a 256-colour palette fitted by k-means (so a small patch of a
    strong colour, such as a class-coloured name, keeps its colour), dithered."""
    px = np.asarray(img, dtype=np.float32).reshape(-1, 3)
    rng = np.random.default_rng(1)
    sample = px[rng.choice(len(px), size=min(len(px), 60000), replace=False)]
    # Seeds spread over the sample, plus the most saturated pixels (small, vivid areas).
    sat = sample.max(axis=1) - sample.min(axis=1)
    seeds = np.concatenate([sample[rng.choice(len(sample), colors - 32, replace=False)],
                            sample[np.argsort(sat)[-32:]]])
    centers = seeds.copy()
    for _ in range(12):
        d = ((sample[:, None, :] - centers[None, :, :]) ** 2).sum(axis=2)
        lab = d.argmin(axis=1)
        for k in range(colors):
            m = sample[lab == k]
            if len(m):
                centers[k] = m.mean(axis=0)
    pal = Image.new("P", (1, 1))
    pal.putpalette(np.clip(centers, 0, 255).astype(np.uint8).flatten().tolist())
    return img.quantize(palette=pal, dither=Image.Dither.FLOYDSTEINBERG)


def render(name):
    with open(os.path.join(BUILD, name + ".json"), encoding="utf-8") as fh:
        data = json.load(fh)
    crop = data["crop"]
    global K
    K = data.get("scale", SCALE) * SS
    cv = Canvas(crop, data)
    for it in data["items"]:
        if it["k"] == "tex":
            draw_texture(cv, it)
        else:
            draw_text(cv, it)
    img = Image.fromarray((np.clip(cv.px, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB")
    img = img.resize((int(round(cv.w / SS)), int(round(cv.h / SS))), Image.LANCZOS)
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".png")
    img.save(path, optimize=True)
    kb = os.path.getsize(path) // 1024
    if kb > LIMIT_KB:
        palettize(img).save(path, optimize=True)
        kb = os.path.getsize(path) // 1024
    print("%-12s %dx%d  %d KB" % (name, img.width, img.height, kb))


def main():
    names = sys.argv[1:]
    if not names:
        names = sorted(f[:-5] for f in os.listdir(BUILD) if f.endswith(".json"))
    for n in names:
        render(n)


if __name__ == "__main__":
    main()
