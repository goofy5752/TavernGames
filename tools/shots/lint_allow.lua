-- The layout checker's allow-list (tools/shots/lint.lua): findings that are meant to be so.
-- Each entry's fields are Lua patterns matched against a finding's fields (check, scene, win,
-- site, what, detail); every field given must match. `why` says why it is fine.
return {
  { check = "inside", site = "^Widgets%.lua:%d+<Widgets%.lua:%d+$", what = "^tex cap_",
    why = "the brass knobs on a window's top corners (W.chrome) sit on its edge by design: half of each overhangs" },
  { check = "inside", site = "^Portrait%.lua:%d+<TablePlates%.lua:%d+$", what = "^tex glow$",
    why = "the soft glow round the portrait of the seat on turn: a plate at the felt's left edge lets 4 px of its faded rim pass the frame's border" },
  { check = "overlap", site = "^Widgets%.lua:%d+<HoldemCashView%.lua:%d+ & Widgets%.lua:%d+<TablePlates%.lua:%d+$",
    why = "„Сметка“ opens its panel over the felt's right side on a solid ground (W.SOLID): the plates under it are covered while the player keeps it open, not mixed with its text" },
  { check = "overlap", site = "^Widgets%.lua:%d+<TablePlates%.lua:%d+ under Widgets%.lua:%d+<HoldemCashView%.lua:%d+$",
    why = "the same panel over the plates: the player opens it over the felt and closes it with „Сметка“ again" },
  { check = "overlap", site = "^Widgets%.lua:%d+<BoardTab%.lua:%d+ under Portrait%.lua:%d+<BoardTab%.lua:%d+$", what = "under tex glow$",
    why = "the soft gold glow round the first three portraits of the leaderboard: its faded rim reaches 6-8 px over the place and the name, which read through it" },
  { check = "overlap", site = " under Widgets%.lua:%d+<TablePanels%.lua:%d+$", what = "under tex color$",
    why = "the „Покани“ picker and the question before „Стани“ open on a solid ground over the felt, above their button: what is under them is covered while they are open" },
  { check = "overlap", site = " under [%w%.]+:%d+<DeckPreview%.lua:%d+$",
    why = "the deck preview is a tooltip: while the pointer is on a deck tile it covers the settings left of the tile on a solid ground, and goes with the pointer" },
}
