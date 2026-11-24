local Wow = require("wow")
local Chess = require("chess")

-- The chess table history (ui/ChessHistory.lua): one hand of the chess book is one game.
local A, B, BOT = "Иван Петров", "Мария Стоянова", "Bot Ivanov"

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
-- The sans of a recorded game's moves.
local function sans(hand)
  local out = {}
  for i, m in ipairs(hand.moves) do out[i] = m.san end
  return out
end
local function plain(t) return (tostring(t):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
-- The window's texts of table s: each game's title, its sides, its moves "1. Nf3 Nf6" (by SAN), its end.
local function texts(s)
  local out = {}
  for _, b in ipairs(H.blocks(s)) do
    out[#out + 1] = b.title
    for _, row in ipairs(b.rows) do
      if row.k == "side" then out[#out + 1] = row.list[1].name .. " · " .. row.list[2].name end
      if row.k == "moves" then
        for _, r in ipairs(row.rows) do out[#out + 1] = r.no .. ". " .. r.white.san .. (r.black and (" " .. r.black.san) or "") end
      end
      if row.text then out[#out + 1] = plain(row.text) end
    end
    if b.sum then out[#out + 1] = "= " .. plain(b.sum) end
  end
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
    eq(sans(H.tables["t#1"].hands[1]), { "f3", "e5", "g4" })
    eq(H.tables["t#1"].hands[1].res, nil)
    Chess.play(st, "d8h4")
    feed(st)
    local b = H.tables["t#1"]
    eq(#b.hands, 1)
    eq(sans(b.hands[1]), { "f3", "e5", "g4", "Qh4#" })
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
    eq(sans(hands[10]), { "e4" })
    local again = new(1) -- another game: an entry once it has its first move
    feed(again)
    eq(H.tables["t#1"].hands[10].no, 13)
    Chess.play(again, "d2d4"); feed(again)
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
    local nextGame = new()
    feed(nextGame) -- the same white, no move yet: no entry yet
    eq(#H.tables["t#1"].hands, 1)
    Chess.play(nextGame, "e2e4"); feed(nextGame)
    local hands = H.tables["t#1"].hands
    eq(#hands, 2)
    eq(hands[1].res, { winner = 1, reason = "resign" })
    eq(hands[2].res, nil)
    eq(sans(hands[2]), { "e4" })
  end)

  it("a running state between two games adds no empty entry", function()
    H.observe(nil)
    local st = new()
    feed(st); Chess.play(st, "f2f3 e7e5 g2g4 d8h4"); feed(st)
    -- the finished game seen again as running, then the rematch before its first move
    local echo = Chess.E.restore(st)
    echo.phase, echo.result, echo.turn = "play", nil, 2
    feed(echo)
    feed({ phase = "play" })
    local rematch = new(1)
    feed(rematch)
    local hands = H.tables["t#1"].hands
    eq(#hands, 1)
    eq(hands[1].res, { winner = 1, reason = "mate" })
    eq(sans(hands[1]), { "f3", "e5", "g4", "Qh4#" })
    Chess.play(rematch, "e2e4"); feed(rematch)
    eq(#hands, 2)
    eq({ hands[2].no, hands[2].white, sans(hands[2]) }, { 2, 1, { "e4" } })
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
    ok(has(bg, "2. g4 Qh4#"), "second pair")
    ok(has(bg, "Мария · Иван"), "sides: white first, short names")
    ok(has(bg, "Мат! Иван печели"), "end")
    ok(has(bg, "= Мат! Иван печели · 4 хода"), "a closed game: its end and its length")
    w.ns.Locale.set("en")
    local en = texts(s)
    ok(has(en, "Game 1"), "game head")
    ok(has(en, "Checkmate! Иван wins"), "end")
    w.ns.Locale.set("bg")
    -- an odd number of moves ends on a single move, a resignation names the one who resigned
    local g = new(); feed(g); Chess.play(g, "e2e4"); feed(g)
    g.phase, g.turn, g.result = "over", nil, { winner = 1, reason = "resign" }
    feed(g)
    local lines = texts(s)
    ok(has(lines, "1. e4"), "single move")
    ok(has(lines, "Иван се предаде") or has(lines, "Мария се предаде"), "resign line")
    ok(has(lines, "= Иван се предаде · 1 ход") or has(lines, "= Мария се предаде · 1 ход"), "one move")
  end)

  it("the window: each move its piece and squares, captures with the piece taken, castling, promotion, mate; inside the list", function()
    H.observe(nil)
    local st = new()
    feed(st)
    -- en passant (3. dxc6), a capture that promotes (5. bxa8=Q), castling (8. O-O), a bishop takes a bishop
    Chess.play(st, "e2e4 d7d5 e4d5 c7c5 d5c6 b8a6 c6b7 c8d7 b7a8q g8f6 g1f3 e7e6 f1e2 d7b5 e1g1 b5e2")
    feed(st)
    local mate = new(1) -- the rematch: fool's mate
    feed(mate); Chess.play(mate, "f2f3 e7e5 g2g4 d8h4"); feed(mate)
    local game = H.tables["t#1"].hands[1]
    local m = game.moves
    eq({ m[5].ep, m[5].take, m[5].from, m[5].to }, { true, -1, "d5", "c6" })
    eq({ m[9].take, m[9].promo, m[9].piece }, { -4, 5, 1 })
    eq({ m[15].castle, m[15].piece, m[15].from, m[15].to }, { "K", 6, "e1", "g1" })
    eq({ m[16].take, m[16].piece }, { 3, -3 })
    eq(H.tables["t#1"].hands[2].moves[4].mate, true)
    -- drawn: the newest game open, a click opens the older one; nothing past the list's right edge
    local parent = w.G.CreateFrame("Frame", nil, w.G.UIParent)
    parent:SetSize(532, 340)
    local panel = H.buildPanel(parent)
    panel:Show()
    local s = { game = "chess", tid = "t#1", mySeat = 2 }
    H.draw(panel, s)
    local buttons = {}
    for _, b in ipairs(panel.pool.kinds.button) do if b:IsShown() then buttons[#buttons + 1] = b end end
    eq(#buttons, 2)
    buttons[2]:GetScript("OnClick")(buttons[2])
    local Fit = require("fit")
    ok(Fit.check(panel.pool, panel.textW, "the chess history") > 40, "widgets checked")
    -- the icons on their light discs: every piece icon follows a disc at its place
    local discs, icons = 0, 0
    for _, p in ipairs(panel.pool.placed) do
      if p.r.texture == w.ns.Theme.tex.chair then discs = discs + 1 end
      if p.r.texture and p.r.texture:find("chess", 1, true) then icons = icons + 1 end
    end
    ok(icons > 20 and discs >= icons, "discs " .. discs .. " icons " .. icons)
    -- the tags: castling, mate
    local tags = {}
    for _, p in ipairs(panel.pool.placed) do if p.r.objectType == "FontString" and p.r:IsShown() then tags[p.r.text] = true end end
    ok(tags[w.ns.L("chess.history.castle")] and tags[w.ns.L("chess.history.mate")], "the tags")
    ok(tags["d5"] and tags["c6"] and tags["e1"] and tags["g1"], "the squares")
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
      if r.frame:IsVisible() and r.peerName == BOT then g:click(r.frame) end
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
