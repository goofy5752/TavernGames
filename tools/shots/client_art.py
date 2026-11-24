"""Headless screenshots, step 0 (optional): the client's own art, from your WoW install.

In the game the addon shows some of the client's art: the faction crests, the race
leaders on the face cards, race and class icons on the seats, the coin icons. The
fake client has none of it, so without this step the shots show the addon's own
stand-ins. This reads exactly the files the addon asks for (wow/Art.lua's candidates,
listed by `luajit tools/shots/scenes.lua --art`), plus a loading screen per faction
for the world behind the windows, out of the local CASC storage, and writes them as
PNG under tools/shots/build/client/ (git-ignored: Blizzard's art is never committed;
only the finished screenshots are). Run from the repo root:
    python tools/shots/client_art.py [--wow "C:/Program Files (x86)/World of Warcraft"] [--product wowf]
Env: WOW_DIR, WOW_PRODUCT, LUAJIT (the luajit binary, default "luajit").
"""
import argparse
import io
import os
import subprocess
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from casc import Casc  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(ROOT, "tools", "shots", "build", "client")

# The world behind the windows (render.py): one loading screen per faction.
WORLD = [
    "Interface\\Glues\\LoadingScreens\\LoadScreenEasternKingdom",
    "Interface\\Glues\\LoadingScreens\\LoadScreenKalimdor",
]


def wanted():
    luajit = os.environ.get("LUAJIT", "luajit")
    out = subprocess.run([luajit, "tools/shots/scenes.lua", "--art"], cwd=ROOT, check=True,
                         capture_output=True, text=True).stdout
    paths = [line.strip() for line in out.splitlines() if line.strip()]
    return paths + WORLD


def target(path):
    return os.path.join(OUT, *path.lower().replace("\\", "/").split("/")) + ".png"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--wow", default=os.environ.get("WOW_DIR", r"C:\Program Files (x86)\World of Warcraft"))
    ap.add_argument("--product", default=os.environ.get("WOW_PRODUCT", "wowf"))
    args = ap.parse_args()
    paths = wanted()
    store = Casc(args.wow, args.product)
    have, missing = [], []
    for path in paths:
        try:
            data = store.read_path(path + ".blp")
        except (KeyError, ValueError):
            data = None
        if not data:
            missing.append(path)
            continue
        img = Image.open(io.BytesIO(data)).convert("RGBA")
        dst = target(path)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        img.save(dst)
        have.append(path)
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, "have.txt"), "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(have) + "\n")
    print("client art: %d files from %s (%s), %d not in this client" % (len(have), args.wow, args.product, len(missing)))
    for m in missing:
        print("  not found:", m)


if __name__ == "__main__":
    main()
