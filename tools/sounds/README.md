# Hold'em sounds

`media/sounds/*.ogg` are Texas Hold'em's sounds (`ui/games/HoldemSounds.lua`). `make_sounds.py` makes them again:

1. Get Kenney's "Casino Audio" (https://kenney.nl/assets/casino-audio) and "Interface Sounds"
   (https://kenney.nl/assets/interface-sounds). Both are CC0. Unpack them into one folder as `casino/` and `iface/`,
   so that `casino/Audio/chips-stack-1.ogg` and `iface/Audio/glass_001.ogg` exist.
2. Run it from the repo root. It needs Python 3 and ffmpeg with libvorbis:

```
python tools/sounds/make_sounds.py --packs <the packs' folder> [--ffmpeg <ffmpeg's bin folder>] [--out media/sounds]
```

You can set the environment variables `TG_SOUND_PACKS`, `TG_FFMPEG` and `TG_SOUND_OUT` instead of the options.
Without `--ffmpeg` the script uses the `ffmpeg` and `ffprobe` on PATH. `--out` defaults to `media/sounds`.

Each source is trimmed of its silence, made mono at 44.1 kHz, set to a -3 dBFS peak plus its own gain (the table in
the script), and saved as Ogg Vorbis (quality 4). `check.ogg`, a double knock on wood, is synthesized by the script
itself. Its noise is random, so its bytes change on every run. The script prints each file's length, size and
peak. Which pack file each sound comes from is listed in `LICENSE-THIRD-PARTY.md`.
