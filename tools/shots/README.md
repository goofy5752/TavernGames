# Headless screenshots

The pictures in `docs/screenshots/` are drawn from the addon's own UI code, without the game.

```
luajit tools/shots/scenes.lua && python tools/shots/render.py
```

Run it from the repo root. You can also name scenes, for example `luajit tools/shots/scenes.lua hall belot` followed by
`python tools/shots/render.py hall belot`. It needs LuaJIT, and Python with Pillow and numpy.

## How it works

1. `scenes.lua` boots the tests' fake WoW client (`tests/helpers/wow.lua`, `frames.lua`) with the `ui/` files, in
   English, as the player "Brannoc". Each scene is then set up through the addon's own code paths. The player opens
   tables and the "Add bots" and "Start" buttons seat the bots. Bots host tables and play real games on the fake
   clock. The player's own moves are the ones the engine's bot (or its automatic move) would make. A Death Roll roll
   is answered by the server's chat line. At the end the visible frame tree is written to
   `tools/shots/build/<scene>.json` (git-ignored) as a draw list: every visible texture and font string with its
   screen rect and its draw attributes, in the client's draw order.
2. `shim.lua` adds two things to the fake (only in this process; the tests never load it):
   - Text is measured with the real fonts' glyph advances (`metrics.lua`, made by `metrics.py`), so the addon's own
     shrink-to-fit and wrapping decide what the real client would.
   - Layout follows WoW: `SetPoint` resolves with its 9 points, offsets, relative regions and two-point sizing,
     `SetAllPoints` works, and frame scale is applied. `GetWidth`/`GetLeft`/... report the laid-out rect.
   It also orders the draw list by strata, frame level, draw layer and sublayer, then creation order. HIGHLIGHT is
   skipped, alpha is multiplied down the parent chain, and scroll frames clip their children.
3. `render.py` draws the list with Pillow at 2x supersampling. Textures are cropped by tex-coords (tiled when they
   use REPEAT), tinted by vertex colour, and use ADD blend and masks. Text uses the real TTF and supports `|c..|r`
   colours, `|T..|t` inline textures (the coins), shadows and outlines. The page is drawn over a dark neutral
   backdrop, cropped to the scene's window(s) and saved as a PNG. An image over 600 KB gets a fitted 256-colour palette.

`metrics.lua` is generated and committed. Remake it with `python tools/shots/metrics.py` when a font changes.
