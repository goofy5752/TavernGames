"""Remakes the games' sounds in media/sounds (see tools/sounds/README.md).

Every file but check.ogg comes from Kenney's CC0 packs "Casino Audio", "Interface Sounds", "Impact Sounds",
"RPG Audio" and "Music Jingles" (trimmed of silence, mono 44.1 kHz, normalized to a -3 dBFS peak plus a gain
each, Ogg Vorbis q4). A few are a sequence: several sources mixed into one file, each starting a given number
of milliseconds after the first. check.ogg is synthesized here.

    python tools/sounds/make_sounds.py --packs DIR [--ffmpeg DIR] [--out DIR] [--only NAME,NAME...]

--packs  (or TG_SOUND_PACKS): the folder holding the unpacked packs as casino/, iface/, impact-sounds/,
         rpg-audio/ and music-jingles/ (casino/Audio/chips-stack-1.ogg, iface/Audio/glass_001.ogg, ...)
--ffmpeg (or TG_FFMPEG): the folder of ffmpeg and ffprobe; default: the ones on PATH
--out    (or TG_SOUND_OUT): where the .ogg files go; default: media/sounds
--only   the names to make (default: all of them, check included)
"""
import argparse
import os
import re
import subprocess
import sys

PIZZI = "music-jingles/Audio/Pizzicato jingles/"

# name: (source, gain dB relative to a -3 dBFS peak, what it is). The source is a file in the packs' folder,
# or a sequence [(file, delay ms), ...]: each file trimmed, started that long after the first, mixed into one.
SOUNDS = {
    # Texas Hold'em (ui/games/HoldemSounds.lua); turn and tick also at Белот, Сантасе and chess
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
    # Белот and Сантасе (ui/games/GameSoundsCards.lua)
    "cards_deal":  ("casino/Audio/card-shuffle.ogg", -1, "a hand is dealt: the deck shuffled"),
    "card_play":   ("casino/Audio/card-place-3.ogg", 0, "a card played to the trick"),
    "trick_take":  ("casino/Audio/card-slide-5.ogg", -1, "a trick taken: the cards slid in"),
    "declare":     ("iface/Audio/confirmation_002.ogg", -10, "a declaration, a contra, a marriage"),
    "hand_end":    ("rpg-audio/Audio/handleCoins.ogg", -2, "Белот: the scores of a deal"),
    "stock_close": ("rpg-audio/Audio/bookClose.ogg", -6, "Сантасе: the stock closed"),
    "nine_swap":   ("casino/Audio/card-slide-7.ogg", 0, "Сантасе: the trump nine swapped"),
    # Табла, chess, Морски шах, Death Roll (ui/games/GameSoundsBoards.lua)
    "dice_roll":     ([("casino/Audio/dice-shake-1.ogg", 0), ("casino/Audio/dice-throw-2.ogg", 450)], 0,
                      "Табла: the dice shaken, then thrown"),
    "checker_move":  ("impact-sounds/Audio/impactWood_light_001.ogg", -3, "Табла: a checker moved"),
    "checker_hit":   ("impact-sounds/Audio/impactWood_heavy_001.ogg", -5, "Табла: a checker hit to the bar"),
    "checker_off":   ("impact-sounds/Audio/impactSoft_medium_001.ogg", -10, "Табла: a checker borne off"),
    "chess_move":    ("impact-sounds/Audio/impactWood_light_002.ogg", -4.5, "chess: a move"),
    "chess_capture": ("impact-sounds/Audio/impactWood_medium_002.ogg", -4, "chess: a capture"),
    "chess_check":   ("impact-sounds/Audio/impactMetal_light_000.ogg", -4.5, "chess: check"),
    "chess_castle":  ([("impact-sounds/Audio/impactWood_light_002.ogg", 0),
                       ("impact-sounds/Audio/impactWood_light_003.ogg", 140)], -6, "chess: castling, two pieces"),
    "chess_promote": ("iface/Audio/confirmation_004.ogg", -13, "chess: a promotion"),
    "ttt_x":         ("iface/Audio/drop_001.ogg", -2, "Морски шах: X placed"),
    "ttt_o":         ("iface/Audio/drop_002.ogg", -5, "Морски шах: O placed"),
    "ttt_line":      ("iface/Audio/maximize_006.ogg", -9, "Морски шах: a winning line"),
    "die_roll":      ("casino/Audio/die-throw-1.ogg", 0, "Death Roll: a roll shown"),
    "roll_one":      ("iface/Audio/error_006.ogg", -7, "Death Roll: a 1 rolled, the game lost"),
    "coins_pay":     ("rpg-audio/Audio/handleCoins2.ogg", -2, "Death Roll: the loss paid on the spot"),
    # every game's end (ui/games/GameSounds.lua): softer, they are music
    "game_win":  (PIZZI + "jingles_PIZZI10.ogg", -13.5, "the game is over: I won"),
    "game_lose": (PIZZI + "jingles_PIZZI07.ogg", -14.5, "the game is over: I lost"),
    "game_draw": (PIZZI + "jingles_PIZZI05.ogg", -14.5, "the game is over: a draw"),
}
TRIM = ("silenceremove=start_periods=1:start_threshold=-50dB,areverse,"
        "silenceremove=start_periods=1:start_threshold=-55dB,areverse,"
        "aformat=channel_layouts=mono:sample_rates=44100")
LEAD = "silenceremove=start_periods=1:start_threshold=-50dB,aformat=channel_layouts=mono:sample_rates=44100"
# check: our own double knock on wood (two short decaying low tones with a click)
KNOCK = ("aevalsrc='0.9*sin(2*PI*190*t)*exp(-38*t)+0.5*sin(2*PI*410*t)*exp(-60*t)"
         "+0.35*(random(0)-0.5)*exp(-250*t)':s=44100:d=0.16")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--packs", default=os.environ.get("TG_SOUND_PACKS"))
    ap.add_argument("--ffmpeg", default=os.environ.get("TG_FFMPEG", ""))
    ap.add_argument("--out", default=os.environ.get("TG_SOUND_OUT", os.path.join("media", "sounds")))
    ap.add_argument("--only", default="")
    args = ap.parse_args()
    if not args.packs:
        ap.error("the packs' folder is needed: --packs DIR or TG_SOUND_PACKS")
    only = set(n for n in args.only.split(",") if n)
    unknown = only - set(SOUNDS) - {"check"}
    if unknown:
        ap.error("unknown sound: " + ", ".join(sorted(unknown)))
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

    def mean(path):
        r = run("ffmpeg", "-hide_banner", "-nostats", "-i", path, "-af", "volumedetect", "-f", "null", "-")
        return float(re.search(r"mean_volume: (-?[0-9.]+)", r.stderr).group(1))

    def vorbis(src, gain_db, dst, extra=""):
        must(run("ffmpeg", "-y", "-hide_banner", "-i", src, "-af", "volume=%.2fdB%s" % (gain_db, extra),
                 "-c:a", "libvorbis", "-q:a", "4", dst))

    # A sequence: each part's leading silence trimmed, started at its delay, mixed, then trimmed as one.
    def sequence(parts, tmp):
        cmd, chains, labels = ["ffmpeg", "-y", "-hide_banner"], [], []
        for k, (src, delay) in enumerate(parts):
            cmd += ["-i", os.path.join(args.packs, src)]
            chains.append("[%d]%s,adelay=%d[p%d]" % (k, LEAD, delay, k))
            labels.append("[p%d]" % k)
        graph = ";".join(chains) + ";%samix=inputs=%d:duration=longest:normalize=0,%s" % (
            "".join(labels), len(parts), TRIM)
        must(run(*cmd, "-filter_complex", graph, tmp))

    made = []
    for name, (src, gain, _) in SOUNDS.items():
        if only and name not in only:
            continue
        tmp = os.path.join(args.out, "_" + name + ".wav")
        if isinstance(src, list):
            sequence(src, tmp)
        else:
            must(run("ffmpeg", "-y", "-hide_banner", "-i", os.path.join(args.packs, src), "-af", TRIM, tmp))
        vorbis(tmp, -3 - peak(tmp) + gain, os.path.join(args.out, name + ".ogg"))
        os.remove(tmp)
        made.append(name + ".ogg")

    if not only or "check" in only:
        one = os.path.join(args.out, "_knock.wav")
        two = os.path.join(args.out, "_knock2.wav")
        must(run("ffmpeg", "-y", "-hide_banner", "-f", "lavfi", "-i", KNOCK, "-af", "lowpass=f=1800", one))
        must(run("ffmpeg", "-y", "-hide_banner", "-i", one, "-i", one, "-filter_complex",
                 "[1]adelay=115[b];[0][b]amix=inputs=2:normalize=0", two))
        vorbis(two, -3 - peak(two) - 1, os.path.join(args.out, "check.ogg"),
               ",aformat=channel_layouts=mono:sample_rates=44100")
        os.remove(one)
        os.remove(two)
        made.append("check.ogg")

    for f in sorted(made):
        p = os.path.join(args.out, f)
        d = run("ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", p).stdout.strip()
        print("%-18s %5.2fs %6d B  peak %5.1f dB  mean %5.1f dB" % (f, float(d), os.path.getsize(p), peak(p), mean(p)))


if __name__ == "__main__":
    main()
