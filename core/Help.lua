local _, ns = ...

-- Rules-book content and the first-run intro, as data. Every text is a locale key
-- (locale/bg.lua, locale/en.lua); a title that names a UI label uses that
-- label's own key, so the book and the UI can never disagree. Block kinds: "p"
-- (text), "example" (a short story in tavern talk), "board" (a 3x3 mini board:
-- `board` holds 9 cells, 0 empty, 1 X, 2 O, and `line` the three cells that
-- glow, next to the text `key`), "ladder" (the text `key` over a row of Death
-- Roll numbers `rolls`, the last one the losing 1).
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
