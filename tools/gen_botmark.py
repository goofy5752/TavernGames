"""Draws the bot mark, media/botmark.tga: a small brass cog with a dark rim and
a dark hub, the sign after a bot's name wherever the addon shows a short name
(ui/NameTag.lua). 32 x 32, 32-bit, drawn with Pillow at 8x and scaled down.
Deterministic, so reruns write identical files. Run from anywhere:
    python tools/gen_botmark.py
"""
import math
import os
import sys

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from gen_textures import write_tga  # noqa: E402

SIZE, SS = 32, 8
TEETH = 8
BRASS_LIGHT, BRASS, BRASS_DARK, RIM = (0xf0, 0xd0, 0x8a), (0xc8, 0x96, 0x4a), (0x8a, 0x5e, 0x2b), (0x2a, 0x17, 0x0c)


def cog(r_out, r_in, half_tooth):
    """The cog's outline: TEETH teeth of angular half-width `half_tooth` (at the tip) from r_in out to r_out."""
    c, pts = SIZE * SS / 2, []
    step = 2 * math.pi / TEETH
    for k in range(TEETH):
        a = k * step - math.pi / 2
        for da, r in ((-step / 2 + 0.02, r_in), (-half_tooth * 1.35, r_in), (-half_tooth, r_out), (half_tooth, r_out),
                      (half_tooth * 1.35, r_in), (step / 2 - 0.02, r_in)):
            pts.append((c + r * math.cos(a + da), c + r * math.sin(a + da)))
    return pts


def main():
    big = SIZE * SS
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    s = SS
    c = big / 2
    # the dark rim: the cog drawn 1.4 px larger
    d.polygon(cog(15.6 * s, 11.6 * s, 0.30), fill=RIM + (255,))
    d.polygon(cog(14.2 * s, 10.3 * s, 0.26), fill=BRASS + (255,))
    # light from the top left: a lighter disc offset up-left, clipped to the body by drawing it smaller
    d.ellipse((c - 9.6 * s, c - 9.6 * s, c + 9.6 * s, c + 9.6 * s), fill=BRASS_DARK + (255,))
    d.ellipse((c - 9.6 * s, c - 9.6 * s, c + 8.4 * s, c + 8.4 * s), fill=BRASS_LIGHT + (255,))
    d.ellipse((c - 8.4 * s, c - 8.4 * s, c + 8.4 * s, c + 8.4 * s), fill=BRASS + (255,))
    # the hub: a dark hole with a thin bright ring
    d.ellipse((c - 4.6 * s, c - 4.6 * s, c + 4.6 * s, c + 4.6 * s), fill=BRASS_LIGHT + (255,))
    d.ellipse((c - 3.6 * s, c - 3.6 * s, c + 3.6 * s, c + 3.6 * s), fill=RIM + (255,))
    small = img.resize((SIZE, SIZE), Image.LANCZOS)
    px = small.load()
    rows = [[tuple(v / 255.0 for v in px[x, y]) for x in range(SIZE)] for y in range(SIZE)]
    # straight (not premultiplied) colour: the edge pixels keep the brass, only their alpha fades
    write_tga(os.path.join(ROOT, "media", "botmark.tga"), SIZE, SIZE, rows)


if __name__ == "__main__":
    main()
