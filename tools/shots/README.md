# Headless screenshots

The pictures in `docs/screenshots/` are drawn from the addon's own UI code, without the game.

```
python tools/shots/client_art.py      # once, needs a local WoW install (see below)
luajit tools/shots/scenes.lua && python tools/shots/render.py
```

Run it from the repo root. You can also name scenes, for example `luajit tools/shots/scenes.lua hall belot` followed by
`python tools/shots/render.py hall belot`. It needs LuaJIT, and Python with Pillow and numpy.
The scenes `history_belot`, `history_long` (the longest names), `history_santase` and `history_chess` show the „История“
window open beside a table, to check it against mockup 10; they are made only when named and are not README pictures.
The scenes `names_hall`, `names_belot`, `names_deathroll` and `names_ledger` (which also writes `names_board`) show
long two-word names, two players with one first word and bots, to check the short names, the bot mark and that no text
is cut; they too are made only when named.

## The layout checker

```
luajit tools/shots/lint.lua                 # every lint scene, both languages, both factions: about 20 s
luajit tools/shots/lint.lua --quick belot   # English and the Alliance only; named scenes only
luajit tools/shots/lint.lua --shots hall    # also writes lint_<scene>_<lang>_<faction>_{min,max,one}.json
SHOTS_OUT=some/dir python tools/shots/render.py lint_hall_bg_h_min   # draws one of them elsewhere
```

`lint.lua` builds every window of the addon with long two-word names, two players with one first word at
one table, bots, a 24-letter guild name and the biggest amounts (`lint_scenes.lua`: the hall and its list,
every game table with the „История“ window, a cash Hold'em, the tavern window's tabs, the rules book, the
new-table dialog of every game, the pay dialog, the stake questions, the toasts, the bill, the intro, the
„Покани“ picker, the question before „Стани“). Each runs in English with the Alliance and in Bulgarian with
the Horde (the hall and Belot also the other way round), then on four screens (1024x768, 1365x768, 1820x768,
1920x1080 UI units; a 1080p screen) at the window scales 0.6, 0.8, 1, 1.3, 1.6 and 2, as `Resize.set` caps
them. It checks:

- **fit**: no text is cut or ends in "..." in its box (the shim's line breaking, `Shim.cut`);
- **overlap**: no two texts of one window overlap, and no text lies under a texture drawn after it;
- **inside**: every region lies inside its window (the „История“ window and the new-table dialog count as
  windows of their own);
- **screen**: every window lies on the screen (clamped frames are moved back on it, as the client does);
- **readable**: no text is under 8 px on screen (font size x scale x 1080 / UIParent's height);
- **sideways**: no scroll child is wider than its scroll frame, and nothing is clipped at its sides.

What is meant to be so is in `lint_allow.lua`, each entry with its reason. The findings go to stdout and
`tools/shots/build/lint.txt`; the last line counts them, and the exit code is 0 only when none is open.

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
   colours, `|T..|t` inline textures (the coins), shadows and outlines. The page is drawn over the world (below) or,
   without client art, a dark neutral backdrop, cropped to the scene's window(s) and saved as a PNG. An image over
   600 KB gets a fitted 256-colour palette.

## The client's art

In the game the addon shows some of the client's own art: the faction crests, the race leaders on the face cards,
race and class icons on the seats, the coin icons. `client_art.py` reads exactly the files the addon asks for
(`wow/Art.lua`'s file candidates, listed by `luajit tools/shots/scenes.lua --art`) out of your WoW install's CASC
storage (`casc.py`, no third-party tools), plus one loading screen per faction (Eastern Kingdoms for the Alliance,
Kalimdor for the Horde), and writes them as PNG to `tools/shots/build/client/`. That folder is git-ignored: Blizzard's
art is never committed, only the finished screenshots. The scenes then run with a client that has those files
(`GetFileIDFromPath` finds them), so the addon picks the same art as in the game. Atlases are left out (their
coordinates live in the client's database); every asset also has a file candidate, which the addon takes instead.
The loading screen is laid over the whole screen as the client shows it, softened and dimmed, as the world behind the
open window. Without this step the shots show the addon's own stand-ins over the neutral backdrop.

Options: `--wow DIR` (default `C:\Program Files (x86)\World of Warcraft`, or `WOW_DIR`), `--product` (default `wowf`,
WoW Forever, or `WOW_PRODUCT`), `LUAJIT` for the luajit binary.

Still different from the game: the player's own seat shows the race icon, not the client's 3-D portrait of the
character, and the world behind the window is a loading screen, not the 3-D world.

`metrics.lua` is generated and committed. Remake it with `python tools/shots/metrics.py` when a font changes.
