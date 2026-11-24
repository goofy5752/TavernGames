local Wow = require("wow")
local Chess = require("chess")

-- The chess table history (ui/ChessHistory.lua): one hand of the chess book is one game.
local A, B, BOT = "Иван Петров", "Мария Стоянова", "Бот Иванов"

local function guildWow()
  local w = Wow.new{ ui = true }
  w.inGuild = true
  w.roster = { { name = A .. "-Forever", online = true, guid = Wow.GUID } }
  w.G.RAID_CLASS_COLORS.PRIEST = { r = 1, g = 1, b = 1 }
  w:boot()
  w:firstRunDone()
  w:fire("GUILD_ROSTER_UPDATE")
  w:fire("PLAYER_LOGIN")
  return w
end

local w = guildWow()
local H = w.ns.HandHistory
local seq = 0

-- Feeds the recorder a session of table "t#1" over state st (one event per call).
local function feed(st)
  seq = seq + 1
  H.observe({ game = "chess", tid = "t#1", state = st, seats = { A, B }, seq = seq, epoch = 1, mySeat = 2 })
end
local function new(first) return Chess.E.new{ first = first or 2, opt = { clock = 10 } } end
local function texts(s)
  local out = {}
  for i, x in ipairs(H.lines(s)) do out[i] = x[2] end
  return out
end
local function has(list, text)
  for _, t in ipairs(list) do if t == text then return true end end
  return false
end

describe("ui: the chess table history", function()
  it("a finished game is kept with its moves and result", function()
    local st = new()
    feed(st)
    Chess.play(st, "f2f3 e7e5 g2g4")
    feed(st)
    eq(H.tables["t#1"].hands[1].moves, { "f3", "e5", "g4" })
    eq(H.tables["t#1"].hands[1].res, nil)
    Chess.play(st, "d8h4")
    feed(st)
    local b = H.tables["t#1"]
    eq(#b.hands, 1)
    eq(b.hands[1].moves, { "f3", "e5", "g4", "Qh4#" })
    eq(b.hands[1].white, 2)
    eq(b.hands[1].names, { A, B })
    eq(b.hands[1].res, { winner = 1, reason = "mate" })
  end)

  it("a snapshot of the same game is not a new entry", function()
    H.observe(nil)
    local st = new()
    feed(st); Chess.play(st, "f2f3 e7e5"); feed(st)
    H.observe({ game = "chess", tid = "t#1", state = st, seats = { A, B }, seq = seq + 40, epoch = 2, mySeat = 2 })
    eq(#H.tables["t#1"].hands, 1)
  end)

  it("the next game is a new entry; ten are kept", function()
    H.observe(nil)
    local first = new()
    feed(first); Chess.play(first, "f2f3 e7e5 g2g4 d8h4"); feed(first)
    for game = 2, 13 do
      local st = new(game % 2 == 0 and 1 or 2) -- a rematch: white changes
      feed(st); Chess.play(st, "e2e4"); feed(st)
    end
    local hands = H.tables["t#1"].hands
    eq(#hands, 10)
    eq(hands[10].no, 13)
    eq(hands[1].no, 4)
    eq(hands[10].moves, { "e4" })
    local again = new(1) -- the same white again: the move list is shorter, so it is another game
    feed(again)
    eq(#H.tables["t#1"].hands, 10)
    eq(H.tables["t#1"].hands[10].no, 14)
  end)

  it("a game that ends with no move is not overwritten by the next one of the same white", function()
    H.observe(nil)
    local st = new()
    feed(st)
    st.phase, st.turn, st.result = "over", nil, { winner = 1, reason = "resign" }
    feed(st)
    eq(#H.tables["t#1"].hands, 1)
    eq(H.tables["t#1"].hands[1].res, { winner = 1, reason = "resign" })
    feed(new()) -- the same white, no move yet
    local hands = H.tables["t#1"].hands
    eq(#hands, 2)
    eq(hands[1].res, { winner = 1, reason = "resign" })
    eq(hands[2].res, nil)
  end)

  it("the panel prints it in my language", function()
    H.observe(nil)
    local st = new()
    feed(st); Chess.play(st, "f2f3 e7e5 g2g4 d8h4"); feed(st)
    local s = { game = "chess", tid = "t#1" }
    w.ns.Locale.set("bg")
    local bg = texts(s)
    ok(has(bg, "Партия 1"), "game head")
    ok(has(bg, "1. f3 e5"), "first pair")
    ok(has(bg, "2. g4 Дh4#"), "second pair")
    ok(has(bg, "Бели: " .. B .. " · Черни: " .. A), "sides")
    ok(has(bg, "Мат! " .. A .. " печели"), "end")
    w.ns.Locale.set("en")
    local en = texts(s)
    ok(has(en, "Game 1"), "game head")
    ok(has(en, "2. g4 Qh4#"), "second pair")
    ok(has(en, "Checkmate! " .. A .. " wins"), "end")
    w.ns.Locale.set("bg")
    -- an odd number of moves ends on a single move, a resignation names the one who resigned
    local g = new(); feed(g); Chess.play(g, "e2e4"); feed(g)
    g.phase, g.turn, g.result = "over", nil, { winner = 1, reason = "resign" }
    feed(g)
    local lines = texts(s)
    ok(has(lines, "1. e4"), "single move")
    ok(has(lines, A .. " се предаде") or has(lines, B .. " се предаде"), "resign line")
  end)

  it("the history button stands at a chess table", function()
    ok(H.GAMES.chess == true)
    local g = guildWow()
    local client, T = g.ns.client, g.ns.TableFrame
    g:slash("bots")
    g:advance(0); g:advance(0)
    client:openTable{ game = "chess", access = "invite", turn = 45, opt = { clock = 10 } }
    g:advance(0)
    g:click(T.view.inviteButton)
    for _, r in ipairs(T.view.picker.rows) do
      if r.frame:IsVisible() and r.name:GetText() == BOT then g:click(r.frame) end
    end
    g:advance(0)
    g:advance(3)
    ok(client.session and client.session.game == "chess", "no chess table")
    T.render()
    ok(T.view.historyButton:IsShown(), "no history button")
  end)

  it("the rules book has the chess chapter in both languages", function()
    local topic = w.ns.Help.get("chess")
    ok(topic, "no chess topic")
    eq(topic.title, "game.chess")
    local T = w.ns.Locale.tables
    local examples = 0
    for _, b in ipairs(topic.blocks) do
      ok(type(T.bg[b.key]) == "string" and T.bg[b.key] ~= "", "bg " .. b.key)
      ok(type(T.en[b.key]) == "string" and T.en[b.key] ~= "", "en " .. b.key)
      if b.kind == "example" then examples = examples + 1 end
    end
    eq(examples, 1)
    for _, k in ipairs({ "p1", "special", "ends", "draw", "clock", "stake", "example" }) do
      local found = false
      for _, b in ipairs(topic.blocks) do if b.key == "help.chess." .. k then found = true end end
      ok(found, "help.chess." .. k .. " is not in the chapter")
    end
  end)

  it("chess has its picture", function()
    local T = w.ns.Theme
    local path = T.gameIcon("chess")
    ok(path, "no picture")
    local rel = path:gsub("^Interface\\AddOns\\TavernGames\\", "")
    local f = io.open((rel:gsub("\\", "/")) .. ".tga", "rb")
    ok(f, "file missing")
    local d = f:read(18)
    f:close()
    local wd, ht, bpp = d:byte(13) + d:byte(14) * 256, d:byte(15) + d:byte(16) * 256, d:byte(17)
    eq({ wd, ht, bpp }, { 64, 64, 32 })
  end)
end)
