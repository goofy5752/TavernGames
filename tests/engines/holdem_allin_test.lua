local ns = Loader.ns()
local E, H = ns.Engines.holdem, ns.HoldemEval

-- Rule 11a: once nobody can bet any more, every live hand is face up before the board runs out.
local HH = require("holdem")(E)
local deckFor, apply = HH.deckFor, HH.apply

local function mk(seatList, stacks, staked)
  local seats = {}
  for _, i in ipairs(seatList) do seats[i] = true end
  local s = E.new{ seats = seats, staked = staked }
  for i, c in pairs(stacks or {}) do s.seats[i].chips = c end
  return s
end
local function start(s, holes, board)
  apply(s, 0, { k = "hand" }); apply(s, 0, { k = "deal", deck = deckFor(s, holes, board) })
end
local function acts(s, list) for _, a in ipairs(list) do apply(s, a[1], { k = a[2], to = a[3] }) end end
local function sys(s) local a = E.system(s); ok(a and not a.need, "no step in " .. s.phase); apply(s, 0, a); return a end
-- the faces of `seats`' hands on the full state
local function holes(s, seats)
  local t = {}
  for _, seat in ipairs(seats) do for _, i in ipairs(s.p[seat].cards) do t[i] = s.deck[i] end end
  return t
end
local function plus(a, b) local t = {} for k, v in pairs(a) do t[k] = v end for k, v in pairs(b) do t[k] = v end return t end
local function board(s) local t = {} for _, i in ipairs(s.board) do t[i] = s.deck[i] end return t end

describe("holdem: hands face up at an all-in", function()
  it("heads-up all-in preflop: both hands up before the flop, the board runs out with them, the best hand wins", function()
    local s = mk({ 1, 2 }); start(s, { [1] = "AS AD", [2] = "KS KD" }, "2C 7D 9H JS KH")
    acts(s, { { 1, "allin" } })
    eq({ s.phase, E.faceUp(s), E.view(s, 0).deck }, { "bet", {}, {} })               -- the call is still open
    acts(s, { { 2, "call" } })
    eq({ s.phase, s.street, E.faceUp(s) }, { "street", 0, { 2, 1 } })
    local up = holes(s, { 1, 2 }); eq(up, { [1] = "KS", [2] = "AS", [3] = "KD", [4] = "AD" })
    eq(E.view(s, 0).deck, up); eq(E.view(s, 2).deck, up); eq(E.view(s, 7).deck, up)
    eq(E.view(s, 0, true).deck, {}); eq(E.view(s, 2, true).deck, { [1] = "KS", [3] = "KD" }) -- what a deal itself turns up
    eq(E.hidden(s, 2), { 1, 3 })                                                      -- still his to be dealt
    for street = 1, 3 do
      sys(s); eq(#s.board, street == 1 and 3 or street + 2)
      eq(E.faceUp(s), { 2, 1 }); eq(E.view(s, 0).deck, plus(up, board(s)))
    end
    eq(s.phase, "showdown"); sys(s)
    eq({ s.phase, s.last.shown, s.last.won, s.last.cat[2] }, { "done", { 2, 1 }, { [2] = 2000 }, H.TRIPS })
    eq(E.faceUp(s), {}); eq(E.view(s, 0).deck, plus(up, board(s)))
  end)

  it("all-in on the turn with a third player folded: only the two live hands, never the folded one", function()
    local s = mk({ 1, 2, 3 }); start(s, { [1] = "QS QD", [2] = "AS AD", [3] = "KS KD" }, "2C 7D 9H JS 3C")
    local folded = holes(s, { 1 })
    acts(s, { { 1, "fold" }, { 2, "call" }, { 3, "check" } }); sys(s)
    eq(E.faceUp(s), {}); acts(s, { { 2, "check" }, { 3, "check" } }); sys(s)
    acts(s, { { 2, "allin" } }); eq(E.faceUp(s), {}); acts(s, { { 3, "call" } })
    eq({ s.phase, s.street, E.faceUp(s) }, { "street", 2, { 2, 3 } })
    local function clean(v) for i in pairs(folded) do eq(v.deck[i], nil, "the folded card " .. i) end end
    for _, seat in ipairs({ 0, 2, 3 }) do clean(E.view(s, seat)) end
    eq(E.view(s, 0).deck, plus(holes(s, { 2, 3 }), board(s)))
    sys(s); clean(E.view(s, 0)); sys(s)
    eq({ s.last.shown, s.last.won }, { { 2, 3 }, { [2] = 2000 } }); clean(E.view(s, 0)); clean(E.view(s, 3))
  end)

  it("one short all-in while two can still bet: nothing up until the other two are all-in; the pots as ever", function()
    local s = mk({ 1, 2, 3 }, { [1] = 300 }); start(s, { [1] = "AS AD", [2] = "KS KD", [3] = "QS QD" }, "2C 7D 9H JS 3C")
    acts(s, { { 1, "allin" }, { 2, "call" }, { 3, "call" } })
    eq({ s.phase, E.faceUp(s), E.view(s, 0).deck }, { "street", {}, {} })             -- seats 2 and 3 bet on
    sys(s); acts(s, { { 2, "bet", 100 } }); eq(E.faceUp(s), {}); acts(s, { { 3, "call" } })
    eq({ s.phase, E.faceUp(s) }, { "street", {} }); eq(E.view(s, 0).deck, board(s)); sys(s)
    acts(s, { { 2, "allin" }, { 3, "call" } })
    eq({ s.phase, s.street, E.faceUp(s) }, { "street", 2, { 2, 3, 1 } })
    eq(E.view(s, 0).deck, plus(holes(s, { 1, 2, 3 }), board(s)))
    sys(s); sys(s)
    eq(s.last.pots, { { amount = 900, eligible = { 2, 3, 1 }, winners = { 1 } }, { amount = 1400, eligible = { 2, 3 }, winners = { 2 } } })
    eq({ s.last.won, s.last.shown }, { { [1] = 900, [2] = 1400 }, { 2, 3, 1 } })
  end)

  it("one live player with chips left over is no betting: up at once; a river call to an all-in turns them up too", function()
    local s = mk({ 1, 2, 3 }, { [3] = 200 }); start(s, { [1] = "AS AD", [2] = "KS KD", [3] = "QS QD" }, "2C 7D 9H JS 3C")
    acts(s, { { 1, "fold" }, { 2, "call" }, { 3, "allin" }, { 2, "call" } })          -- seat 2 keeps 800 behind
    eq({ s.phase, E.faceUp(s) }, { "street", { 2, 3 } })
    local r = mk({ 1, 2 }); start(r, { [1] = "AS AD", [2] = "KS KD" }, "2C 7D 9H JS 3C")
    acts(r, { { 1, "call" }, { 2, "check" } })
    for _ = 1, 3 do sys(r); acts(r, { { 2, "check" } }); if r.street < 3 then acts(r, { { 1, "check" } }) end end
    eq({ r.phase, E.faceUp(r) }, { "bet", {} }); acts(r, { { 1, "allin" } }); eq(E.faceUp(r), {})
    acts(r, { { 2, "call" } }); eq({ r.phase, E.faceUp(r) }, { "showdown", { 2, 1 } })
    local c = mk({ 1, 2 }); start(c, {}, nil); acts(c, { { 1, "call" }, { 2, "check" } })
    for _ = 1, 3 do sys(c); acts(c, { { 2, "check" }, { 1, "check" } }) end
    eq({ c.phase, E.faceUp(c), E.view(c, 0).deck }, { "showdown", {}, board(c) })     -- checked down: up only at the showdown
  end)

  it("a short blind all-in at the deal: up from the deal on, but the deal itself turns up nothing", function()
    local s = mk({ 1, 2 }, { [1] = 5 }); start(s, { [1] = "AS AD", [2] = "KS KD" }, "2C 7D 9H JS 3C")
    eq({ s.phase, E.faceUp(s) }, { "street", { 2, 1 } })
    eq(E.view(s, 0, true).deck, {}); eq(E.view(s, 0).deck, holes(s, { 1, 2 }))
  end)

  it("a leave folds a hand that was up: it is no longer up; the last live player wins without a showdown", function()
    local s = mk({ 1, 2, 3 }); start(s, { [1] = "AS AD", [2] = "KS KD", [3] = "QS QD" }, "2C 7D 9H JS 3C")
    acts(s, { { 1, "allin" }, { 2, "call" }, { 3, "call" } }); eq(E.faceUp(s), { 2, 3, 1 })
    apply(s, 0, { k = "leave", seat = 3 }); eq(E.faceUp(s), { 2, 1 }); eq(E.view(s, 0).deck, holes(s, { 1, 2 }))
    apply(s, 0, { k = "leave", seat = 2 })
    eq({ s.phase, s.last.shown, s.last.won, E.view(s, 0).deck }, { "done", {}, { [1] = 3000 }, {} })
  end)

  it("a void during the run-out shows nothing more", function()
    local s = mk({ 1, 2 }); start(s, { [1] = "AS AD", [2] = "KS KD" }, "2C 7D 9H JS 3C")
    acts(s, { { 1, "allin" }, { 2, "call" } }); sys(s); apply(s, 0, { k = "void" })
    eq({ s.phase, E.faceUp(s), E.view(s, 0).deck }, { "done", {}, board(s) })        -- the flop dealt, no hand
  end)

  it("a staked table turns them up the same way", function()
    local s = mk({ 1, 2 }, nil, true)
    apply(s, 1, { k = "buy", n = 1000 }); apply(s, 2, { k = "buy", n = 600 })
    start(s, { [1] = "AS AD", [2] = "KS KD" }, "2C 7D 9H JS KH")
    acts(s, { { 1, "allin" }, { 2, "call" } }); eq({ s.phase, E.faceUp(s) }, { "street", { 2, 1 } })
    eq(E.view(s, 0).deck, holes(s, { 1, 2 })); sys(s); sys(s); sys(s); sys(s)
    eq({ s.last.shown, s.last.won, s.seats[1].chips }, { { 2, 1 }, { [2] = 1200 }, 400 })
  end)
end)
