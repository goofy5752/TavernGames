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
local function sess(st, seat)
  return { game = "chess", status = "live", mySeat = seat, seats = { A, B }, state = st, tid = "t#1",
    role = seat and "player" or "watcher" }
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

  it("the move list in two languages", function()
    local st = new("g1f3 g8f6")
    local m = M.build(sess(st, 2))
    eq(m.rows, { { no = 1, white = "Кf3", black = "Кf6", lastWhite = false, lastBlack = true } })
    eq(M.build(sess(new("g1f3"), 2)).rows, { { no = 1, white = "Кf3", lastWhite = true, lastBlack = false } })
    eq(M.san("e8=Q+"), "e8=Д+"); eq(M.san("O-O"), "O-O"); eq(M.san("exd5"), "exd5"); eq(M.san("Rxe1#"), "Тxe1#")
    w.ns.Locale.set("en")
    eq(M.build(sess(st, 2)).rows[1].white, "Nf3"); eq(M.build(sess(st, 2)).rows[1].black, "Nf6")
    eq(M.san("e8=Q+"), "e8=Q+")
    w.ns.Locale.set("bg")
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
  end)

  it("the status and the end text", function()
    local st = new()
    eq(M.build(sess(st, 2)).status, "Ти си на ход")
    eq(M.build(sess(st, 1)).status, "На ход е " .. B)
    st.offer = 2
    eq(M.build(sess(st, 2)).status, "Предложи реми. Чакаме отговор.")
    local mate = new("f2f3 e7e5 g2g4 d8h4")
    local m = M.build(sess(mate, 2))
    eq(m.banner, "Мат! " .. A .. " печели")
    eq(m.status, ""); eq({ m.canOffer, m.canResign, m.myTurn }, { false, false, false })
    local resigned = new(); w.ns.Engines.chess.apply(resigned, 2, { k = "resign" })
    eq(M.build(sess(resigned, 1)).banner, B .. " се предаде")
    local drawn = new(); drawn.offer = 1; w.ns.Engines.chess.apply(drawn, 2, { k = "accept" })
    eq(M.build(sess(drawn, 1)).banner, "Реми по съгласие")
  end)
end)
