local Chess = require("chess")
local E, R = Chess.E, Chess.R

local CODES = { action = true, seat = true, phase = true, turn = true, move = true, promo = true,
  dt = true, time = true, offer = true, clock = true, claim = true }

local function copy(v)
  if type(v) ~= "table" then return v end
  local t = {}
  for k, x in pairs(v) do t[k] = copy(x) end
  return t
end
local function timed() return E.new{ first = 2, opt = { clock = 10 } } end
local function untimed() return E.new{ first = 2, opt = { clock = 0 } } end
local function refused(s, seat, a, dt, code)
  local before = copy(s)
  eq({ E.apply(s, seat, a, dt) }, { nil, code })
  eq(s, before, "state changed by a refused " .. tostring(type(a) == "table" and a.k or a))
end
local DRAW = { winners = {}, losers = {} }

describe("chess engine", function()
  it("the contract", function()
    eq(E.id, "chess"); eq(E.minSeats, 2); eq(E.maxSeats, 2); eq(E.stakes, true); eq(E.again, true)
    eq(E.clock, true); eq(E.firstSeat, 2); eq(E.INC, 50)
    eq(E.options, {
      { id = "clock", at = "fun",   choices = { 5, 10, 15, 30, 0 }, default = 10 },
      { id = "clock", at = "stake", choices = { 5, 10, 15, 30 },    default = 10 },
    })
    ok(E.view == nil and E.ext == nil and E.hidden == nil, "no view, ext or hidden")
    eq(#E.legal(E.new{ first = 2 }, 2), 20); eq(#E.legal(E.new{ first = 2 }, 1), 0)
    eq(E.legal(E.new{ first = 2 }, 2)[1].k, "move")
    local s = E.new{ first = 2 }
    for _, k in ipairs({ "round", "rolls", "start", "rematch", "max" }) do eq(s[k], nil, k) end
    eq(s.phase, "play"); eq(s.moves, {}); eq(s.taken, { {}, {} }); eq(s.wait, { 0, 0 })
    eq(s.seen, { [R.key(R.start())] = 1 }); eq(E.over(s), false); eq(E.result(s), nil)
    eq({ E.system(s) }, {})
  end)

  it("white is the seat it is given, seat 2 by default", function()
    eq(E.new{}.white, 2); eq(E.new{}.turn, 2); eq(E.new().turn, 2)
    eq(E.new{ first = 1 }.turn, 1); eq(E.new{ first = 1 }.white, 1)
    eq(E.nextFirst({ white = 2 }, { true, true }), 1); eq(E.nextFirst({ white = 1 }, { true, true }), 2)
  end)

  it("the clock", function()
    local s = E.new{ first = 2, opt = { clock = 5 } }
    eq(s.base, 3000); eq(s.clock, { 3000, 3000 })
    Chess.play(s, "e2e4", 120); eq(s.clock, { 3000, 2930 }); eq(s.moves[1].dt, 120)
    s = E.new{ first = 2, opt = { clock = 5 } }
    refused(s, 2, { k = "move", f = 13, t = 29 }, 3000, "time")
    Chess.play(s, "e2e4", 2999); eq(s.clock[2], 51)
    s = E.new{ first = 2, opt = { clock = 5 } }
    Chess.play(s, "e2e4"); eq(s.clock[2], 3050); eq(s.moves[1].dt, nil)
    eq(E.new{ first = 2 }.base, 6000)
    s = untimed()
    eq(s.base, nil); eq(s.clock, nil)
    refused(s, 2, { k = "flag" }, nil, "clock")
    eq(E.auto(s, 2), nil)
    Chess.play(s, "e2e4", 99999); eq(s.moves[1].dt, 99999); eq(s.clock, nil)
    s = timed()
    eq(E.auto(s, 2), { k = "flag" }); eq(E.auto(s, 1), nil)
  end)

  it("the flag", function()
    local s = timed()
    refused(s, 1, { k = "flag" }, nil, "turn")
    ok(E.apply(s, 2, { k = "flag" }))
    eq(s.phase, "over"); eq(s.result, { winner = 1, reason = "flag" }); eq(s.turn, nil)
    eq(s.clock[2], 0, "the flagged clock shows no time left"); eq(s.clock[1], 6000)
    eq(E.result(s), { winners = { 1 }, losers = { 2 } }); eq(E.over(s), true); eq(E.auto(s, 2), nil)
    refused(s, 2, { k = "flag" }, nil, "phase")
    s = Chess.at("8/8/8/8/8/2k5/P7/K7 w - - 0 1")
    ok(E.apply(s, 2, { k = "flag" }))
    eq(s.result, { reason = "flagdraw" }); eq(E.result(s), DRAW)
    eq(s.clock[2], 0)
  end)

  it("a claim", function()
    local s = timed()
    local before = copy(s)
    ok(E.apply(s, 1, { k = "claim" })); eq(s.claimed, 0)
    before.claimed = 0; eq(s, before)
    refused(s, 1, { k = "claim" }, nil, "claim")
    refused(s, 2, { k = "claim" }, nil, "turn")
    Chess.play(s, "e2e4")
    ok(E.apply(s, 2, { k = "claim" })); eq(s.claimed, 1)
    refused(untimed(), 1, { k = "claim" }, nil, "clock")
  end)

  it("draw offers", function()
    local s = timed()
    refused(s, 1, { k = "offer" }, nil, "turn")
    refused(s, 1, { k = "accept" }, nil, "offer"); refused(s, 1, { k = "decline" }, nil, "offer")
    ok(E.apply(s, 2, { k = "offer" })); eq(s.offer, 2)
    refused(s, 2, { k = "offer" }, nil, "offer")
    refused(s, 2, { k = "accept" }, nil, "offer"); refused(s, 2, { k = "decline" }, nil, "offer")
    Chess.play(s, "e2e4"); eq(s.offer, 2)
    Chess.play(s, "e7e5"); eq(s.offer, nil); eq(s.wait, { 0, 3 })
    for _, pair in ipairs({ "g1f3 b8c6", "f1c4 g8f6", "b1c3 f8c5" }) do
      refused(s, 2, { k = "offer" }, nil, "offer")
      Chess.play(s, pair)
    end
    eq(s.wait, { 0, 0 })
    ok(E.apply(s, 2, { k = "offer" }))
    local clock = copy(s.clock)
    ok(E.apply(s, 1, { k = "decline" })); eq(s.offer, nil); eq(s.wait, { 0, 3 }); eq(s.clock, clock)
    refused(s, 2, { k = "offer" }, nil, "offer")
    s = timed()
    Chess.play(s, "e2e4", 40)
    ok(E.apply(s, 1, { k = "offer" }))
    clock = copy(s.clock)
    ok(E.apply(s, 2, { k = "accept" }))
    eq(s.phase, "over"); eq(s.result, { reason = "agreed" }); eq(s.turn, nil); eq(s.clock, clock)
    eq(E.result(s), DRAW)
  end)

  it("resign and leave", function()
    local s = timed()
    ok(E.apply(s, 1, { k = "resign" }))
    eq(s.result, { winner = 2, reason = "resign" }); eq(s.phase, "over"); eq(s.turn, nil)
    eq(E.result(s), { winners = { 2 }, losers = { 1 } })
    refused(s, 2, { k = "resign" }, nil, "phase")
    local before = copy(s)
    E.leave(s, 2); eq(s, before)
    s = timed()
    E.leave(s, 2)
    eq(s.result, { winner = 1, reason = "left", left = 2 }); eq(s.phase, "over"); eq(s.turn, nil)
    eq(E.result(s).left, 2); eq(E.result(s), { winners = { 1 }, losers = { 2 }, left = 2 })
    refused(s, 1, { k = "resign" }, nil, "phase")
    before = copy(s)
    E.leave(s, 1); eq(s, before)
  end)

  it("the automatic draws", function()
    local s = Chess.play(timed(), "g1f3 g8f6 f3g1 f6g8 g1f3 g8f6 f3g1 f6g8")
    eq(s.phase, "over"); eq(s.result, { reason = "repetition" }); eq(E.result(s), DRAW)
    s = Chess.play(Chess.at("8/8/8/8/8/4k3/8/R3K3 w - - 99 80"), "a1a2")
    eq(s.result, { reason = "fifty" }); eq(E.result(s), DRAW)
    s = Chess.play(Chess.at("7k/8/6K1/8/8/8/8/R7 w - - 99 80"), "a1a8")
    eq(s.half, 100); eq(s.result, { winner = 2, reason = "mate" })
    eq(E.result(s), { winners = { 2 }, losers = { 1 } })
    s = Chess.play(Chess.at("4k3/8/8/8/8/8/3r4/3BK3 w - - 0 1"), "e1d2")
    eq(s.result, { reason = "material" }); eq(E.result(s), DRAW)
    s = Chess.play(Chess.at("7k/8/5QK1/8/8/8/8/8 w - - 0 1"), "f6f7")
    eq(s.result, { reason = "stalemate" }); eq(E.result(s), DRAW); eq(s.turn, nil)
    refused(s, 1, { k = "move", f = 64, t = 63 }, nil, "phase")
  end)

  it("seen is emptied by a pawn move or a capture", function()
    local s = Chess.play(timed(), "g1f3 g8f6")
    local n = 0; for _ in pairs(s.seen) do n = n + 1 end
    eq(n, 3)
    Chess.play(s, "e2e4")
    n = 0; for _, c in pairs(s.seen) do n = n + 1; eq(c, 1) end
    eq(n, 1); eq(s.seen[R.key(s)], 1)
  end)

  it("taken", function()
    local s = Chess.play(timed(), "e2e4 d7d5 e4d5")
    eq(s.taken, { {}, { -1 } })
    Chess.play(s, "d8d5")
    eq(s.taken, { { 1 }, { -1 } })
  end)

  it("garbage is refused and changes nothing", function()
    local s = timed()
    local function code(a, dt)
      local before = copy(s)
      local r, why = E.apply(s, 2, a, dt)
      eq(r, nil); ok(CODES[why], "code " .. tostring(why)); eq(s, before)
    end
    for _, a in ipairs({
      { k = "move", f = "e2", t = 29 }, { k = "move", f = 0, t = 29 }, { k = "move", f = 65, t = 29 },
      { k = "move", f = 13.5, t = 29 }, { k = "move", f = 13, t = 29, p = "q" }, { k = "move", f = 13 },
      { k = "move", f = 13, t = 30 }, { k = "move", f = 13, t = 1 / 0 }, { k = "fly" }, { k = 7 }, {},
    }) do code(a) end
    code("x"); code(nil); code(7)
    for _, dt in ipairs({ -1, 0.5, "7", 1 / 0, true }) do code({ k = "move", f = 13, t = 29 }, dt) end
    refused(s, 3, { k = "move", f = 13, t = 29 }, nil, "seat")
    refused(s, 0, { k = "resign" }, nil, "seat")
    refused(s, 1, { k = "move", f = 53, t = 37 }, nil, "turn")
    refused(s, 2, { k = "move", f = 13, t = 29 }, -1, "dt")
    refused(s, 2, { k = "fly" }, nil, "action"); refused(s, 2, "x", nil, "action")
    s = Chess.at("4k3/P7/8/8/8/8/8/4K3 w - - 0 1")
    refused(s, 2, { k = "move", f = 49, t = 57 }, nil, "promo")
    refused(s, 2, { k = "move", f = 49, t = 57, p = "k" }, nil, "promo")
    refused(s, 2, { k = "move", f = 49, t = 57, p = 5 }, nil, "promo")
    ok(E.apply(s, 2, { k = "move", f = 49, t = 57, p = "n" })); eq(s.board[57], 2)
  end)

  it("snapshot and restore", function()
    local s = Chess.play(timed(), "e2e4 d7d5 e4d5 g8f6", 33)
    ok(E.apply(s, 2, { k = "offer" })); ok(E.apply(s, 1, { k = "claim" }))
    local back = E.restore(E.snapshot(s))
    eq(back, s)
    local mine = {}
    local function walk(t, into) into[t] = true; for _, v in pairs(t) do if type(v) == "table" then walk(v, into) end end end
    walk(s, mine)
    local theirs = {}; walk(back, theirs)
    local shared = false; for t in pairs(theirs) do if mine[t] then shared = true end end
    ok(not shared, "restore shares a table with the state")
    -- An en passant square that the side to move could not have (a forged snapshot) is dropped.
    s = Chess.play(timed(), "e2e4 a7a6 e4e5 d7d5")
    eq(s.ep, 44); eq(E.restore(E.snapshot(s)).ep, 44)
    s.ep = 20; eq(E.restore(s).ep, nil)
    s.ep = 44.5; eq(E.restore(s).ep, nil)
    s.ep = "d6"; eq(E.restore(s).ep, nil)
    s = Chess.play(timed(), "e2e4"); eq(E.restore(s).ep, 21)
    s.ep = 45; eq(E.restore(s).ep, nil)
  end)
end)
