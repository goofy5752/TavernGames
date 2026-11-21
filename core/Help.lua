local _, ns = ...

-- Rules-book content and the first-run intro, as data. Every text is a locale key
-- (locale/bg.lua, locale/en.lua); a title that names a UI label uses that
-- label's own key, so the book and the UI can never disagree. Block kinds: "p"
-- (text), "example" (a short story in tavern talk), "board" (a 3x3 mini board:
-- `board` holds 9 cells, 0 empty, 1 X, 2 O, and `line` the three cells that
-- glow, next to the text `key`), "ladder" (the text `key` over a row of Death
-- Roll numbers `rolls`, the last one the losing 1), "cards" (a row of card
-- faces `cards`, as in ui/Cards.lua, above the text `key`), "dice" (a row of
-- die faces `dice`, each 1..6, above the text `key`).
local Help = {}
ns.Help = Help

Help.topics = {
  { id = "hall", title = "hall.title", blocks = {
    { kind = "p", key = "help.hall.p1" },
    { kind = "p", key = "help.hall.open" },
    { kind = "p", key = "help.hall.access" },
    { kind = "example", key = "help.hall.example" },
    { kind = "p", key = "help.hall.invite" },
    { kind = "p", key = "help.hall.stand" },
    { kind = "p", key = "help.hall.offline" },
  } },
  { id = "ttt", title = "game.ttt", blocks = {
    { kind = "p", key = "help.ttt.p1" },
    { kind = "example", key = "help.ttt.example" },
    { kind = "board", key = "help.ttt.board", board = { 1, 1, 1, 2, 2, 0, 0, 0, 0 }, line = { 1, 2, 3 } },
    { kind = "p", key = "help.ttt.time" },
    { kind = "p", key = "help.ttt.draw" },
    { kind = "p", key = "help.ttt.rematch" },
  } },
  { id = "deathroll", title = "game.deathroll", blocks = {
    { kind = "p", key = "help.deathroll.p1" },
    { kind = "example", key = "help.deathroll.example" },
    { kind = "ladder", key = "help.deathroll.ladder", rolls = { 1000, 642, 87, 12, 3, 1 } },
    { kind = "p", key = "help.deathroll.roll" },
    { kind = "p", key = "help.deathroll.group" },
    { kind = "p", key = "help.deathroll.time" },
    { kind = "p", key = "help.deathroll.tags" },
    { kind = "p", key = "help.deathroll.leave" },
  } },
  { id = "santase", title = "game.santase", blocks = {
    { kind = "p", key = "help.santase.p1" },
    { kind = "example", key = "help.santase.example" },
    { kind = "cards", key = "help.santase.cards", cards = { "AS", "TS", "KS", "QS", "JS", "9S" } },
    { kind = "p", key = "help.santase.trick" },
    { kind = "p", key = "help.santase.strict" },
    { kind = "cards", key = "help.santase.marriage", cards = { "KH", "QH" } },
    { kind = "p", key = "help.santase.swap" },
    { kind = "p", key = "help.santase.close" },
    { kind = "p", key = "help.santase.score" },
    { kind = "p", key = "help.santase.time" },
    { kind = "p", key = "help.santase.fair" },
  } },
  { id = "belot", title = "game.belot", blocks = {
    { kind = "p", key = "help.belot.p1" },
    { kind = "example", key = "help.belot.example" },
    { kind = "p", key = "help.belot.bids" },
    { kind = "p", key = "help.belot.contra" },
    { kind = "cards", key = "help.belot.cards", cards = { "JH", "9H", "AH", "TH", "KH", "QH" } },
    { kind = "p", key = "help.belot.trick" },
    { kind = "cards", key = "help.belot.announce", cards = { "9H", "TH", "JH" } },
    { kind = "cards", key = "help.belot.belote", cards = { "KS", "QS" } },
    { kind = "p", key = "help.belot.score" },
    { kind = "p", key = "help.belot.valat" },
    { kind = "p", key = "help.belot.time" },
    { kind = "p", key = "help.belot.fair" },
  } },
  { id = "tabla", title = "game.tabla", blocks = {
    { kind = "p", key = "help.tabla.p1" },
    { kind = "example", key = "help.tabla.example" },
    { kind = "dice", key = "help.tabla.move", dice = { 6, 3 } },
    { kind = "p", key = "help.tabla.staging" },
    { kind = "p", key = "help.tabla.std" },
    { kind = "p", key = "help.tabla.bearoff" },
    { kind = "p", key = "help.tabla.tapa" },
    { kind = "dice", key = "help.tabla.gul", dice = { 4, 5, 6 } },
    { kind = "p", key = "help.tabla.score" },
    { kind = "p", key = "help.tabla.time" },
    { kind = "p", key = "help.tabla.fair" },
  } },
  { id = "holdem", title = "game.holdem", blocks = {
    { kind = "p", key = "help.holdem.p1" },
    { kind = "example", key = "help.holdem.example" },
    { kind = "p", key = "help.holdem.blinds" },
    { kind = "cards", key = "help.holdem.rounds", cards = { "AH", "JH", "7C", "QS", "2D" } },
    { kind = "cards", key = "help.holdem.hands", cards = { "TS", "JS", "QS", "KS", "AS" } },
    { kind = "example", key = "help.holdem.sidepot" },
    { kind = "p", key = "help.holdem.limits" },
    { kind = "p", key = "help.holdem.seats" },
    { kind = "p", key = "help.holdem.time" },
    { kind = "p", key = "help.holdem.fair" },
  } },
  -- Why the card deal (and the Табла dice) is fair; the table's fairness line opens it.
  { id = "fair", title = "help.fair.title", blocks = {
    { kind = "p", key = "help.fair.p1" },
    { kind = "example", key = "help.fair.example" },
    { kind = "p", key = "help.fair.how" },
    { kind = "p", key = "help.fair.verify" },
    { kind = "p", key = "help.fair.dealer" },
    { kind = "p", key = "help.fair.bad" },
    { kind = "p", key = "help.fair.dice" },
    { kind = "p", key = "help.fair.sealed" },
  } },
  { id = "soon", title = "games.soon", blocks = {
    { kind = "p", key = "help.soon.p" },
    { kind = "example", key = "help.soon.example" },
  } },
}

-- First-run intro: hall -> sitting -> invites -> the ⓘ book.
Help.intro = {
  { title = "hall.title", text = "intro.hall.text" },
  { title = "intro.sit.title", text = "intro.sit.text" },
  { title = "intro.invite.title", text = "intro.invite.text" },
  { title = "intro.book.title", text = "intro.book.text" },
}

-- The topic with this id, or nil.
function Help.get(id)
  for i = 1, #Help.topics do
    if Help.topics[i].id == id then return Help.topics[i] end
  end
  return nil
end
