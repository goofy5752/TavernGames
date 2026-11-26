"""Releases of Tavern Games: one script for the local bump and for the release workflow
(.github/workflows/release.yml). Python 3 standard library only. Run from the repo root:

    python tools/release/release.py bump 1.0.2      # a release PR: the toc, Const.VERSION, CHANGELOG, README
    python tools/release/release.py version         # the toc's version (checked against Const.VERSION)
    python tools/release/release.py notes 1.0.2     # the CHANGELOG section of that version
    python tools/release/release.py body 1.0.2      # the GitHub release text: how to install, then the notes
    python tools/release/release.py zip 1.0.2 dist  # dist/TavernGames-1.0.2.zip, the addon in TavernGames/
    python tools/release/release.py curseforge dist/TavernGames-1.0.2.zip 1.0.2
                                                    # uploads it (env CF_API_KEY; the project is the toc's
                                                    # X-Curse-Project-ID; CF_GAME_VERSION overrides the
                                                    # game version, else the toc's Interface: 16001 -> 1.60.1)
"""
import datetime
import io
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request
import uuid
import zipfile

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
TOC = "TavernGames.toc"
CONST = os.path.join("core", "Const.lua")
NAME = "TavernGames"
# What the zip carries: these files and every tracked file under these folders.
SHIP_FILES = [TOC, "LICENSE", "LICENSE-THIRD-PARTY.md", "README.md", "CHANGELOG.md"]
SHIP_DIRS = ["Libs", "core", "engines", "locale", "media", "ui", "wow"]
CF_SITE = "https://wow.curseforge.com"
CF_FOREVER = 88568  # CurseForge's game version type of WoW Forever
REPO = "https://github.com/goofy5752/TavernGames"
VERSION_RE = re.compile(r"^\d+\.\d+\.\d+$")


def fail(msg):
    print("release: " + msg, file=sys.stderr)
    sys.exit(1)


def read(path):
    with io.open(os.path.join(ROOT, path), encoding="utf-8", newline="") as f:
        return f.read()


def write(path, text):
    with io.open(os.path.join(ROOT, path), "w", encoding="utf-8", newline="") as f:
        f.write(text)


def toc_field(name):
    m = re.search(r"^## " + re.escape(name) + r":[ \t]*(.+?)[ \t]*\r?$", read(TOC), re.M)
    return m and m.group(1)


def const_version():
    m = re.search(r'^\s*VERSION = "([^"]+)",', read(CONST), re.M)
    return m and m.group(1)


def version():
    v, c = toc_field("Version"), const_version()
    if not v or not VERSION_RE.match(v):
        fail("the toc has no ## Version: X.Y.Z (%r)" % v)
    if v != c:
        fail("the toc says %s but core/Const.lua's VERSION says %s" % (v, c))
    return v


def game_version():
    """The toc's Interface as WoW writes the game version: 16001 -> 1.60.1."""
    i = toc_field("Interface")
    if not i or not i.isdigit():
        fail("the toc has no ## Interface")
    n = int(i)
    return "%d.%d.%d" % (n // 10000, n // 100 % 100, n % 100)


def notes(v):
    """The CHANGELOG section `## v ...` up to the next `## ` heading, trimmed."""
    lines = read("CHANGELOG.md").replace("\r\n", "\n").split("\n")
    out, inside = [], False
    for line in lines:
        if line.startswith("## "):
            if inside:
                break
            inside = re.match(r"^## " + re.escape(v) + r"(\s|$)", line) is not None
            continue
        if inside:
            out.append(line)
    text = "\n".join(out).strip()
    if not text:
        fail("CHANGELOG.md has no section `## %s` (or it is empty)" % v)
    return text


def body(v):
    return (
        "**Tavern Games %s for WoW Forever (game version %s).**\n\n"
        "Download `%s-%s.zip` below and unpack it into `World of Warcraft\\_forever_\\Interface\\AddOns\\`, "
        "so that you get `AddOns\\TavernGames\\TavernGames.toc`.\n\n%s\n\n"
        "Everything that came before is in [CHANGELOG.md](%s/blob/master/CHANGELOG.md).\n"
    ) % (v, game_version(), NAME, v, notes(v), REPO)


def tracked(paths):
    out = subprocess.run(["git", "ls-files", "-z", "--"] + paths, cwd=ROOT, check=True,
                         capture_output=True).stdout.decode("utf-8")
    return sorted(p for p in out.split("\0") if p)


def build_zip(v, out_dir):
    files = tracked(SHIP_FILES + SHIP_DIRS)
    missing = [f for f in SHIP_FILES if f not in files]
    if missing:
        fail("not tracked: " + ", ".join(missing))
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, "%s-%s.zip" % (NAME, v))
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for f in files:
            z.write(os.path.join(ROOT, f), NAME + "/" + f)
    print(path)
    return path


def bump(v):
    if not VERSION_RE.match(v):
        fail("a version is X.Y.Z, not %r" % v)
    old = version()
    if v == old:
        fail("the version is %s already" % v)
    today = datetime.date.today().isoformat()
    toc = read(TOC)
    write(TOC, re.sub(r"^## Version:[ \t]*\S+", "## Version: " + v, toc, count=1, flags=re.M))
    const = read(CONST)
    write(CONST, const.replace('VERSION = "%s",' % old, 'VERSION = "%s",' % v, 1))
    log = read("CHANGELOG.md")
    if not re.search(r"^## Unreleased[ \t]*\r?$", log, re.M):
        fail("CHANGELOG.md has no `## Unreleased` section to release")
    write("CHANGELOG.md", re.sub(r"^## Unreleased[ \t]*(?=\r?$)", "## %s (%s)" % (v, today), log, count=1, flags=re.M))
    notes(v)  # the section must say something
    readme = read("README.md")
    write("README.md", readme.replace("**Version %s**" % old, "**Version %s**" % v))
    print("%s -> %s (%s): toc, core/Const.lua, CHANGELOG.md, README.md" % (old, v, today))


def cf_request(url, token, data=None, content_type=None):
    req = urllib.request.Request(url, data=data, method="POST" if data is not None else "GET")
    req.add_header("X-Api-Token", token)
    req.add_header("User-Agent", "TavernGames-release (+%s)" % REPO)
    if content_type:
        req.add_header("Content-Type", content_type)
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        fail("CurseForge %s -> HTTP %d: %s" % (url, e.code, e.read().decode("utf-8", "replace")[:500]))


def curseforge(zip_path, v):
    token = os.environ.get("CF_API_KEY", "").strip()
    if not token:
        fail("no CF_API_KEY")
    project = os.environ.get("CF_PROJECT_ID", "").strip() or toc_field("X-Curse-Project-ID")
    if not project:
        fail("no project: the toc has no ## X-Curse-Project-ID")
    want = os.environ.get("CF_GAME_VERSION", "").strip() or game_version()
    versions = [g for g in cf_request(CF_SITE + "/api/game/wow/versions", token)
                if g.get("gameVersionTypeID") == CF_FOREVER]
    ids = [g["id"] for g in versions if g.get("name") == want]
    if not ids:
        names = ", ".join(sorted(g.get("name", "?") for g in versions)) or "none"
        fail("CurseForge has no WoW Forever game version %s (it has: %s); set the repo variable "
             "CF_GAME_VERSION to one of them" % (want, names))
    meta = {
        "changelog": notes(v), "changelogType": "markdown", "displayName": "Tavern Games " + v,
        "gameVersions": ids[:1], "releaseType": os.environ.get("CF_RELEASE_TYPE", "release"),
    }
    boundary = uuid.uuid4().hex
    with open(zip_path, "rb") as f:
        data = f.read()
    parts = [
        b"--" + boundary.encode() + b"\r\nContent-Disposition: form-data; name=\"metadata\"\r\n"
        b"Content-Type: application/json\r\n\r\n" + json.dumps(meta).encode("utf-8") + b"\r\n",
        b"--" + boundary.encode() + b"\r\nContent-Disposition: form-data; name=\"file\"; filename=\""
        + os.path.basename(zip_path).encode() + b"\"\r\nContent-Type: application/zip\r\n\r\n" + data + b"\r\n",
        b"--" + boundary.encode() + b"--\r\n",
    ]
    res = cf_request("%s/api/projects/%s/upload-file" % (CF_SITE, project), token, b"".join(parts),
                     "multipart/form-data; boundary=" + boundary)
    print("CurseForge: project %s, file id %s (game version %s, %s)" % (project, res.get("id"), want, meta["releaseType"]))


def main(argv):
    if not argv:
        fail(__doc__)
    cmd, args = argv[0], argv[1:]
    sys.stdout.reconfigure(encoding="utf-8")
    if cmd == "version" and not args:
        print(version())
    elif cmd == "game-version" and not args:
        print(game_version())
    elif cmd == "notes" and len(args) == 1:
        print(notes(args[0]))
    elif cmd == "body" and len(args) == 1:
        print(body(args[0]), end="")
    elif cmd == "zip" and len(args) == 2:
        build_zip(args[0], args[1])
    elif cmd == "bump" and len(args) == 1:
        bump(args[0])
    elif cmd == "curseforge" and len(args) == 2:
        curseforge(args[0], args[1])
    else:
        fail(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
