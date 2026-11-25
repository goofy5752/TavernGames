"""media/dropdown.tga: the small arrow of a drop-down (ui/Widgets.lua W.Dropdown), white on
transparent, 32 x 32, tinted by the caller. Drawn at 8x and scaled down for smooth edges.
Run from the repo root: python tools/gen_dropdown.py"""
from PIL import Image, ImageDraw

K = 8
S = 32 * K
img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(img)
# a chevron pointing down, rounded by a thick stroke
w = 4.2 * K
pts = [(8 * K, 12 * K), (16 * K, 21 * K), (24 * K, 12 * K)]
d.line(pts, fill=(255, 255, 255, 255), width=int(w), joint="curve")
for x, y in (pts[0], pts[2]):
    d.ellipse((x - w / 2, y - w / 2, x + w / 2, y + w / 2), fill=(255, 255, 255, 255))
img.resize((32, 32), Image.LANCZOS).save("media/dropdown.tga")
