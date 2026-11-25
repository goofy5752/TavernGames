# The games' sounds

`media/sounds/*.ogg` are the games' sounds: Texas Hold'em's (`ui/games/HoldemSounds.lua`) and every other game's
(`ui/games/GameSounds.lua`). `make_sounds.py` makes them again:

1. Get Kenney's "Casino Audio" (https://kenney.nl/assets/casino-audio), "Interface Sounds"
   (https://kenney.nl/assets/interface-sounds), "Impact Sounds" (https://kenney.nl/assets/impact-sounds), "RPG Audio"
   (https://kenney.nl/assets/rpg-audio) and "Music Jingles" (https://kenney.nl/assets/music-jingles). All are CC0.
   Unpack them into one folder as `casino/`, `iface/`, `impact-sounds/`, `rpg-audio/` and `music-jingles/`, so that
   `casino/Audio/chips-stack-1.ogg`, `iface/Audio/glass_001.ogg`, `impact-sounds/Audio/impactWood_light_001.ogg`,
   `rpg-audio/Audio/handleCoins.ogg` and `music-jingles/Audio/Pizzicato jingles/jingles_PIZZI10.ogg` exist.
2. Run it from the repo root. It needs Python 3 and ffmpeg with libvorbis:

```
python tools/sounds/make_sounds.py --packs <the packs' folder> [--ffmpeg <ffmpeg's bin folder>] [--out media/sounds] [--only name,name]
```

You can set the environment variables `TG_SOUND_PACKS`, `TG_FFMPEG` and `TG_SOUND_OUT` instead of the options.
Without `--ffmpeg` the script uses the `ffmpeg` and `ffprobe` on PATH. `--out` defaults to `media/sounds`. `--only`
makes just the files named (without `.ogg`; `check` is the knock), all of them by default.

Each source is trimmed of its silence, made mono at 44.1 kHz, set to a -3 dBFS peak plus its own gain (the table in
the script), and saved as Ogg Vorbis (quality 4). A sequence (`dice_roll`, `chess_castle`) is several sources mixed
into one file, each with its leading silence trimmed and started its delay in milliseconds after the first; the mix
is then trimmed and normalized as one. The end jingles (`game_win`, `game_lose`, `game_draw`) have a lower gain so
the music does not drown the table. `check.ogg`, a double knock on wood, is synthesized by the script itself. Its
noise is random, so its bytes change on every run; the Ogg stream serials change too, so a run gives files of the
same sizes and sound, not the same bytes. The script prints each file's length, size, peak and mean volume. Which
pack file each sound comes from is listed in `LICENSE-THIRD-PARTY.md`.
