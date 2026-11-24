"""Remakes Texas Hold'em's sounds in media/sounds (see tools/sounds/README.md).

Eleven files come from Kenney's CC0 packs "Casino Audio" and "Interface Sounds" (trimmed of silence,
mono 44.1 kHz, normalized to a -3 dBFS peak plus a gain each, Ogg Vorbis q4); check.ogg is synthesized here.

    python tools/sounds/make_sounds.py --packs DIR [--ffmpeg DIR] [--out DIR]

--packs  (or TG_SOUND_PACKS): the folder holding the unpacked packs as casino/ and iface/
         (casino/Audio/chips-stack-1.ogg, iface/Audio/glass_001.ogg, ...)
--ffmpeg (or TG_FFMPEG): the folder of ffmpeg and ffprobe; default: the ones on PATH
--out    (or TG_SOUND_OUT): where the .ogg files go; default: media/sounds
"""
import argparse
import os
import re
import subprocess
import sys

# name: (source in the packs' folder, gain dB relative to a -3 dBFS peak, what it is)
SOUNDS = {
    "turn":     ("iface/Audio/glass_001.ogg", -2, "my turn: a soft glass chime"),
    "tick":     ("iface/Audio/tick_002.ogg", -8, "a second of my last ten"),
    "tickLast": ("iface/Audio/tick_004.ogg", -3, "a second of my last five"),
    "timeout":  ("iface/Audio/bong_001.ogg", -2, "my time ran out"),
    "call":     ("casino/Audio/chips-stack-1.ogg", -2, "call: chips laid down"),
    "bet":      ("casino/Audio/chips-handle-6.ogg", -2, "bet or raise: a handful of chips"),
    "allin":    ("casino/Audio/chips-handle-5.ogg", 0, "all-in: a big push of chips"),
    "fold":     ("casino/Audio/card-slide-3.ogg", -3, "fold: cards slid away"),
    "deal":     ("casino/Audio/card-place-1.ogg", -3, "the hole cards dealt"),
    "board":    ("casino/Audio/card-place-2.ogg", -3, "flop, turn, river: a card turned on the board"),
    "win":      ("casino/Audio/chips-handle-1.ogg", -1, "the pot pushed to the winner"),
}
TRIM = ("silenceremove=start_periods=1:start_threshold=-50dB,areverse,"
        "silenceremove=start_periods=1:start_threshold=-55dB,areverse,"
        "aformat=channel_layouts=mono:sample_rates=44100")
# check: our own double knock on wood (two short decaying low tones with a click)
KNOCK = ("aevalsrc='0.9*sin(2*PI*190*t)*exp(-38*t)+0.5*sin(2*PI*410*t)*exp(-60*t)"
         "+0.35*(random(0)-0.5)*exp(-250*t)':s=44100:d=0.16")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--packs", default=os.environ.get("TG_SOUND_PACKS"))
    ap.add_argument("--ffmpeg", default=os.environ.get("TG_FFMPEG", ""))
    ap.add_argument("--out", default=os.environ.get("TG_SOUND_OUT", os.path.join("media", "sounds")))
    args = ap.parse_args()
    if not args.packs:
        ap.error("the packs' folder is needed: --packs DIR or TG_SOUND_PACKS")
    os.makedirs(args.out, exist_ok=True)

    def run(tool, *rest):
        exe = os.path.join(args.ffmpeg, tool) if args.ffmpeg else tool
        return subprocess.run([exe, *rest], capture_output=True, text=True)

    def must(r):
        if r.returncode:
            print(r.stderr)
            sys.exit(1)

    def peak(path):
        r = run("ffmpeg", "-hide_banner", "-nostats", "-i", path, "-af", "volumedetect", "-f", "null", "-")
        return float(re.search(r"max_volume: (-?[0-9.]+)", r.stderr).group(1))

    def vorbis(src, gain_db, dst, extra=""):
        must(run("ffmpeg", "-y", "-hide_banner", "-i", src, "-af", "volume=%.2fdB%s" % (gain_db, extra),
                 "-c:a", "libvorbis", "-q:a", "4", dst))

    for name, (src, gain, _) in SOUNDS.items():
        tmp = os.path.join(args.out, "_" + name + ".wav")
        must(run("ffmpeg", "-y", "-hide_banner", "-i", os.path.join(args.packs, src), "-af", TRIM, tmp))
        vorbis(tmp, -3 - peak(tmp) + gain, os.path.join(args.out, name + ".ogg"))
        os.remove(tmp)

    one = os.path.join(args.out, "_knock.wav")
    two = os.path.join(args.out, "_knock2.wav")
    must(run("ffmpeg", "-y", "-hide_banner", "-f", "lavfi", "-i", KNOCK, "-af", "lowpass=f=1800", one))
    must(run("ffmpeg", "-y", "-hide_banner", "-i", one, "-i", one, "-filter_complex",
             "[1]adelay=115[b];[0][b]amix=inputs=2:normalize=0", two))
    vorbis(two, -3 - peak(two) - 1, os.path.join(args.out, "check.ogg"), ",aformat=channel_layouts=mono:sample_rates=44100")
    os.remove(one)
    os.remove(two)

    for f in sorted(os.listdir(args.out)):
        p = os.path.join(args.out, f)
        d = run("ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", p).stdout.strip()
        print("%-14s %5.2fs %6d B  peak %5.1f dB" % (f, float(d), os.path.getsize(p), peak(p)))


if __name__ == "__main__":
    main()
