local Wow = require("wow")
local Chess = require("chess")

local A, B = "Иван Петров", "Мария Стоянова"

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
local M = w.ns.ChessModel
local sq = Chess.sq

-- A session over `st` at seat `seat` (nil: a watcher); seat 2 plays white in a new game.
-- A session as the model reads it, with the engine methods core/Clock.lua calls.
local function sess(st, seat)
  return { game = "chess", status = "live", mySeat = seat, seats = { A, B }, state = st, tid = "t#1",
    role = seat and "player" or "watcher",
    engine = function() return Chess.E end, gameOver = function(self) return Chess.E.over(self.state) end }
end
local function new(words) return Chess.play(Chess.at("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"), words or "") end

describe("ui: the chess model", function()
  it("own colour at the bottom, white for a watcher", function()
    local st = new()
    local m = M.build(sess(st, 2))
    eq({ m.bottom, m.cells[57].sq, m.cells[1].sq, m.cells[8].sq }, { 1, 1, 57, 64 })
    m = M.build(sess(st, 1))
    eq({ m.bottom, m.cells[1].sq, m.cells[64].sq, m.cells[57].sq }, { -1, 8, 57, 64 })
    m = M.build(sess(st, nil))
    eq({ m.bottom, m.cells[57].sq, m.cells[1].sq }, { 1, 1, 57 })
    eq(M.bottomSeat(sess(st, 1)), 1); eq(M.bottomSeat(sess(st, nil)), 2)
  end)

  it("targets and marks", function()
    local st = new()
    local m = M.build(sess(st, 2), sq("e2"))
    eq(m.targets, { 21, 29 })
    local by = {}
    for _, c in ipairs(m.cells) do by[c.sq] = c end
    ok(by[21].dot and by[29].dot and by[13].sel, "dots and the selection")
    ok(not by[21].ring, "no ring on a free square")
    -- a capture target has a ring
    local cap = new("e2e4 d7d5")
    m = M.build(sess(cap, 2), sq("e4"))
    by = {}
    for _, c in ipairs(m.cells) do by[c.sq] = c end
    ok(by[sq("d5")].ring and not by[sq("d5")].dot and by[sq("e5")].dot, "a capture shows a ring")
    -- the last move
    m = M.build(sess(new("e2e4"), 1))
    by = {}
    for _, c in ipairs(m.cells) do by[c.sq] = c end
    ok(by[13].last and by[29].last and not by[21].last, "the last move")
    eq(M.build(sess(new("e2e4"), 1), sq("e7")).targets, { 37, 45 }, "black's pawn on e7")
    -- the king in check
    local mate = new("f2f3 e7e5 g2g4 d8h4")
    m = M.build(sess(mate, 2))
    for _, c in ipairs(m.cells) do eq(c.check, c.sq == sq("e1"), tostring(c.sq)) end
    -- not my turn, not my piece: no targets
    eq(M.build(sess(new(), 1), sq("e7")).targets, {})
    eq(M.build(sess(new(), 2), sq("e7")).targets, {})
  end)

  it("taken and the lead", function()
    local st = new("e2e4 d7d5 e4d5 d8d5")
    local m = M.build(sess(st, 2))
    eq({ m.taken[2], m.taken[1] }, { { -1 }, { 1 } })
    eq(m.lead, {})
    st = Chess.at("4k3/8/8/3q4/8/8/8/3QK3 w - - 0 1")
    Chess.play(st, "d1d5")
    m = M.build(sess(st, 2))
    eq(m.taken, { {}, { -5 } }); eq(m.lead, { [2] = 9 })
    st = new("e2e4 d7d5 e4d5 d8d5 b1c3 d5e5")
    st.taken = { { 1, 3, 5, 2, 4, 1 }, {} }
    eq(M.build(sess(st, 2)).taken[1], { 5, 4, 3, 2, 1, 1 }, "sorted Q R B N P")
    eq(M.build(sess(st, 2)).lead, { [1] = 1 + 3 + 9 + 3 + 5 + 1 })
  end)

  it("the move list: two moves a row, each its piece and squares", function()
    local st = new("g1f3 g8f6")
    local m = M.build(sess(st, 2))
    local nf3 = { piece = 2, from = "g1", to = "f3", capture = false, check = false, mate = false, san = "Nf3" }
    local nf6 = { piece = -2, from = "g8", to = "f6", capture = false, check = false, mate = false, san = "Nf6" }
    eq(m.rows, { { no = 1, white = nf3, black = nf6, lastWhite = false, lastBlack = true } })
    eq(M.build(sess(new("g1f3"), 2)).rows, { { no = 1, white = nf3, lastWhite = true, lastBlack = false } })
    eq(M.san("e8=Q+"), "e8=Д+"); eq(M.san("O-O"), "O-O"); eq(M.san("exd5"), "exd5"); eq(M.san("Rxe1#"), "Тxe1#")
    w.ns.Locale.set("en")
    eq(M.san("e8=Q+"), "e8=Q+")
    w.ns.Locale.set("bg")
  end)

  -- The move `n` of the game played from the start: its description, the fields asked.
  local function nth(words, n, keys)
    local list = new(words).moves
    local d = w.ns.ChessMoves.describe(list)[n or #list]
    local out = {}
    for _, k in ipairs(keys) do out[k] = d[k] end
    return out
  end
  local K = { "piece", "from", "to", "take", "ep", "castle", "promo", "check", "mate", "capture" }

  it("describes every kind of move: quiet, capture, en passant, castling, promotion, check, mate", function()
    eq(nth("e2e4", 1, K), { piece = 1, from = "e2", to = "e4", capture = false, check = false, mate = false })
    eq(nth("e2e4 d7d5 e4d5", 3, K), { piece = 1, from = "e4", to = "d5", take = -1, capture = true, check = false, mate = false })
    eq(nth("e2e4 d7d5 e4d5 d8d5", 4, K), { piece = -5, from = "d8", to = "d5", take = 1, capture = true, check = false, mate = false })
    eq(nth("e2e4 a7a6 e4e5 d7d5 e5d6", 5, K), -- en passant takes the pawn beside, not the empty square
      { piece = 1, from = "e5", to = "d6", take = -1, ep = true, capture = true, check = false, mate = false })
    eq(nth("e2e4 e7e5 g1f3 b8c6 f1c4 g8f6 e1g1", 7, K),
      { piece = 6, from = "e1", to = "g1", castle = "K", capture = false, check = false, mate = false })
    eq(nth("d2d4 d7d5 b1c3 b8c6 c1f4 c8f5 d1d2 d8d7 e1c1 e8c8", 9, K),
      { piece = 6, from = "e1", to = "c1", castle = "Q", capture = false, check = false, mate = false })
    eq(nth("d2d4 d7d5 b1c3 b8c6 c1f4 c8f5 d1d2 d8d7 e1c1 e8c8", 10, K),
      { piece = -6, from = "e8", to = "c8", castle = "Q", capture = false, check = false, mate = false })
    eq(nth("a2a4 b7b5 a4b5 a7a6 b5a6 c8b7 a6b7 h7h6 b7a8q", 9, K), -- a capture that promotes
      { piece = 1, from = "b7", to = "a8", take = -4, promo = 5, capture = true, check = false, mate = false })
    eq(nth("e2e4 f7f6 d1h5", 3, K), { piece = 5, from = "d1", to = "h5", capture = false, check = true, mate = false })
    eq(nth("f2f3 e7e5 g2g4 d8h4", 4, K), { piece = -5, from = "d8", to = "h4", capture = false, check = false, mate = true })
    -- the list grows: the cached moves stay, the new one is described from the position they left
    local st = new("e2e4 d7d5")
    eq(#w.ns.ChessMoves.describe(st.moves), 2)
    Chess.play(st, "e4d5")
    eq(w.ns.ChessMoves.describe(st.moves)[3].take, -1)
  end)

  it("a list that does not start at the start position: read from its SAN", function()
    local st = Chess.at("4k3/1P6/8/8/8/8/8/4K2R w K - 0 1")
    Chess.play(st, "b7b8q e8d7 e1g1")
    local d = w.ns.ChessMoves.describe(st.moves)
    eq({ d[1].piece, d[1].promo, d[1].from, d[1].to }, { 1, 5, "b7", "b8" })
    eq({ d[2].piece, d[2].to }, { -6, "d7" })
    eq({ d[3].piece, d[3].castle }, { 6, "K" })
  end)

  it("clockText", function()
    eq(M.clockText(nil), "∞"); eq(M.clockText(2995), "5:00"); eq(M.clockText(290), "0:29")
    eq(M.clockText(6000), "10:00"); eq(M.clockText(0), "0:00")
  end)

  it("promotes", function()
    local st = Chess.at("4k3/P7/8/8/8/8/8/4K3 w - - 0 1")
    ok(M.promotes(sess(st, 2), sq("a7"), sq("a8")), "a7a8 promotes")
    ok(not M.promotes(sess(st, 2), sq("e1"), sq("e2")), "a king step does not")
  end)

  it("what I may do", function()
    local st = new()
    local m = M.build(sess(st, 2))
    ok(m.canOffer and m.canResign and not m.canClaim, "white's turn")
    eq(M.build(sess(st, 1)).canOffer, false)
    eq(M.build(sess(st, 1)).canResign, true)
    st.offer = 2
    m = M.build(sess(st, 2))
    eq({ m.canOffer, m.offerFor }, { false, 1 })
    eq(M.build(sess(st, 1)).offerFor, 1)
    st.offer, st.wait[2] = nil, 2
    eq(M.build(sess(st, 2)).canOffer, false)
    local watcher = M.build(sess(new(), nil))
    eq({ watcher.canOffer, watcher.canResign, watcher.canClaim, watcher.myTurn }, { false, false, false, false })
    -- black's time gone by my clock: I (white) may claim
    local late = sess(new("e2e4"), 2)
    late.clockAt, late.client = 0, { env = { now = function() return 6000 end } }
    eq(M.build(late).canClaim, true)
  end)

  it("the status and the end text name the seats short (ui/NameTag.lua)", function()
    local st = new()
    eq(M.build(sess(st, 2)).status, "Ти си на ход")
    eq(M.build(sess(st, 1)).status, "На ход е Мария")
    st.offer = 2
    eq(M.build(sess(st, 2)).status, "Предложи реми. Чакаме отговор.")
    local mate = new("f2f3 e7e5 g2g4 d8h4")
    local m = M.build(sess(mate, 2))
    eq(m.banner, "Мат! Иван печели")
    eq(m.status, ""); eq({ m.canOffer, m.canResign, m.myTurn }, { false, false, false })
    local resigned = new(); w.ns.Engines.chess.apply(resigned, 2, { k = "resign" })
    eq(M.build(sess(resigned, 1)).banner, "Мария се предаде")
    local drawn = new(); drawn.offer = 1; w.ns.Engines.chess.apply(drawn, 2, { k = "accept" })
    eq(M.build(sess(drawn, 1)).banner, "Реми по съгласие")
  end)
end)

describe("ui: a chess move in its cell (ns.HistoryKit.move)", function()
  local Fit = require("fit")
  local Kit = w.ns.HistoryKit
  local function pool()
    local f = w.G.CreateFrame("Frame", nil, w.G.UIParent)
    f:SetSize(400, 400)
    return Kit.pool(f, true)
  end
  -- the widest moves: a capture that promotes and mates; castling with check; a plain capture with check
  local WIDE = {
    { piece = 1, from = "b7", to = "a8", capture = true, take = -4, promo = 5, mate = true, check = false },
    { piece = -6, from = "e8", to = "c8", castle = "Q", capture = false, check = true, mate = false },
    { piece = 5, from = "d1", to = "h5", capture = true, take = -1, check = true, mate = false },
  }

  it("a quiet move is one line: the icon, from → to", function()
    local p = pool()
    p:begin()
    local h = Kit.move(p, 0, 0, 85, { piece = 2, from = "g1", to = "f3", capture = false, check = false, mate = false })
    p:finish()
    eq(h, 20)
    local texts = {}
    for _, x in ipairs(p.placed) do if x.r.objectType == "FontString" then texts[#texts + 1] = x.r.text end end
    eq(texts, { "g1", "→", "f3" })
    eq({ p.placed[1].r.texture, p.placed[2].r.texture:match("alliance_wn$") }, { w.ns.Theme.tex.chair, "alliance_wn" }) -- on its light disc
  end)

  it("the widest cells never pass their column: smaller first, then the tags on a second line; nothing dropped", function()
    for _, width in ipairs({ 83, 116, 60 }) do
      for _, d in ipairs(WIDE) do
        local p = pool()
        p:begin()
        local h = Kit.move(p, 0, 0, width, d, { paper = width == 83, last = true })
        p:finish()
        Fit.check(p, width, "cell " .. width .. " " .. d.from .. d.to)
        local icons, tags = 0, {}
        for _, x in ipairs(p.placed) do
          if x.r.texture and x.r.texture:find("chess", 1, true) then icons = icons + 1 end
          if x.r.objectType == "FontString" then tags[x.r.text] = true end
        end
        -- every part is there: the piece, the taken piece, the new piece; the tags
        eq(icons, 1 + (d.take and 1 or 0) + (d.promo and 1 or 0), "icons in " .. width)
        local L = w.ns.L
        if d.mate then ok(tags[L("chess.history.mate")], "mate tag") end
        if d.check then ok(tags[L("chess.history.check")], "check tag") end
        if d.castle then ok(tags[L("chess.history.castle")], "castle tag") end
        if width == 60 then ok(h >= 40, "two lines in a narrow cell") end
      end
    end
  end)

  it("the table's list: number, white, black; the rows grow, never widen", function()
    local p = pool()
    p:begin()
    local rows = { { no = 1, white = WIDE[1], black = WIDE[2], lastBlack = true }, { no = 2, white = WIDE[3] } }
    local h = Kit.moveRows(p, 0, 0, 192, rows, { paper = true })
    p:finish()
    Fit.check(p, 192, "the parchment list")
    ok(h > 2 * 20, "a row grew: " .. h)
  end)
end)
