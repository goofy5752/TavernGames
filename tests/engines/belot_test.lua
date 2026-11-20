local E = Loader.ns().Engines.belot

-- Four hands of eight faces each (the first five are dealt before the auction) -> the deck
-- that deals them.
local function deckOf(h1, h2, h3, h4)
  local hands, deck = {}, {}
  for seat, str in ipairs({ h1, h2, h3, h4 }) do
    hands[seat] = {}
    for face in str:gmatch("%S+") do hands[seat][#hands[seat] + 1] = face end
    assert(#hands[seat] == 8, "a hand has 8 cards")
  end
  for j = 1, 20 do deck[j] = hands[(j - 1) % 4 + 1][math.floor((j - 1) / 4) + 1] end
  for j = 21, 32 do deck[j] = hands[(j - 1) % 4 + 1][6 + math.floor((j - 21) / 4)] end
  local seen = {}
  for _, face in ipairs(deck) do
    assert(not seen[face], "duplicate " .. face)
    seen[face] = true
  end
  return deck
end

local DECK1 = deckOf(
  "7C 8C 9C TC JC QC KC AC",
  "7D 8D 9D TD JD QD KD AD",
  "7H 8H 9H TH JH QH KH AH",
  "7S 8S 9S TS JS QS KS AS")

local function deal(s, deck) ok(E.apply(s, 0, { k = "deal", deck = deck or DECK1 })) end
local function bids(s, str)
  for b in str:gmatch("%S+") do
    local okay, why = E.apply(s, s.turn, { k = "bid", b = b })
    ok(okay, "bid " .. b .. " rejected: " .. tostring(why))
  end
end
local function faces(s, list)
  local out = {}
  for n, i in ipairs(list) do out[n] = s.deck[i] end
  return out
end
local function legalBids(s, seat)
  local str = ""
  for _, a in ipairs(E.legal(s, seat)) do str = str .. a.b end
  return str
end

describe("belot core", function()
  it("is registered with the canonical deck", function()
    eq(E.id, "belot"); eq(E.minSeats, 4); eq(E.maxSeats, 4); eq(#E.DECK, 32)
    eq(E.DECK[1], "7C"); eq(E.DECK[8], "AC"); eq(E.DECK[9], "7D"); eq(E.DECK[32], "AS")
    eq(E.options, {})
  end)
  it("starts waiting for a deal", function()
    local s = E.new { first = 3 }
    eq(s.phase, "deal"); eq(s.first, 3); eq(s.turn, nil); eq(s.score, { 0, 0 })
    eq({ E.system(s) }, { { k = "deal" }, 0 })
    eq(E.new {}.first, 1); eq(E.over(s), false)
  end)
  it("deals five cards each, one at a time from seat 1", function()
    local s = E.new { first = 2 }
    deal(s)
    eq(s.phase, "bid"); eq(s.turn, 2)
    eq(s.hands, { { 1, 5, 9, 13, 17 }, { 2, 6, 10, 14, 18 }, { 3, 7, 11, 15, 19 }, { 4, 8, 12, 16, 20 } })
    eq(faces(s, s.hands[1]), { "7C", "8C", "9C", "TC", "JC" })
    eq(faces(s, s.hands[4]), { "7S", "8S", "9S", "TS", "JS" })
  end)
  it("deals three more after the auction", function()
    local s = E.new {}
    deal(s); bids(s, "C P P P")
    eq(s.phase, "play"); eq(s.turn, 1)
    eq(faces(s, s.hands[1]), { "7C", "8C", "9C", "TC", "JC", "QC", "KC", "AC" })
    eq(faces(s, s.hands[2]), { "7D", "8D", "9D", "TD", "JD", "QD", "KD", "AD" })
    eq(s.hands[4], { 4, 8, 12, 16, 20, 24, 28, 32 })
  end)
  it("rejects a bad deal and leaves the state alone", function()
    local s = E.new {}
    local before = E.snapshot(s)
    eq({ E.apply(s, 1, { k = "deal", deck = DECK1 }) }, { nil, "seat" })
    local dup = { unpack(DECK1) }
    dup[2] = dup[1]
    eq({ E.apply(s, 0, { k = "deal", deck = dup }) }, { nil, "deck" })
    eq({ E.apply(s, 0, { k = "deal", deck = { "ZZ" } }) }, { nil, "deck" })
    eq({ E.apply(s, 0, { k = "deal", deck = "x" }) }, { nil, "deck" })
    eq({ E.apply(s, 0, { k = "deal", deck = { [33] = "7C" } }) }, { nil, "deck" })
    eq(E.snapshot(s), before)
    deal(s)
    eq({ E.apply(s, 0, { k = "deal", deck = DECK1 }) }, { nil, "phase" })
    eq({ E.apply(s, 1, nil) }, { nil, "action" })
    eq({ E.apply(s, 1, { k = "bogus" }) }, { nil, "action" })
  end)
end)

describe("belot auction", function()
  it("offers pass and every contract at the start", function()
    local s = E.new {}
    deal(s)
    eq(legalBids(s, 1), "PCDHSNA"); eq(E.legal(s, 2), {}); eq(E.legal(s, 0), {})
    eq(E.legal(s, 1)[2], { k = "bid", b = "C" })
  end)
  it("allows only higher contracts, and doubling by the opponents", function()
    local s = E.new {}
    deal(s); bids(s, "H")
    eq(legalBids(s, 2), "PSNAX")
    bids(s, "P"); eq(legalBids(s, 3), "PSNA")
    eq({ E.apply(s, 3, { k = "bid", b = "D" }) }, { nil, "bid" })
    eq({ E.apply(s, 3, { k = "bid", b = "H" }) }, { nil, "bid" })
    eq({ E.apply(s, 3, { k = "bid", b = "X" }) }, { nil, "bid" })
    eq({ E.apply(s, 3, { k = "bid", b = "R" }) }, { nil, "bid" })
    eq({ E.apply(s, 3, { k = "bid" }) }, { nil, "bid" })
    eq({ E.apply(s, 4, { k = "bid", b = "P" }) }, { nil, "turn" })
    eq({ E.apply(s, 0, { k = "bid", b = "P" }) }, { nil, "seat" })
    eq(s.turn, 3); eq(#s.bids, 2)
  end)
  it("redouble is for the declaring team after a double; nothing after it but higher bids", function()
    local s = E.new {}
    deal(s); bids(s, "D X")
    eq(s.contract, { seat = 1, b = "D", x = 2 })
    eq(legalBids(s, 3), "PHSNAR")
    bids(s, "P"); eq(legalBids(s, 4), "PHSNA")
    bids(s, "P"); eq(legalBids(s, 1), "PHSNAR")
    bids(s, "R")
    eq(s.contract, { seat = 1, b = "D", x = 4 }); eq(legalBids(s, 2), "PHSNA")
    bids(s, "S")
    eq(s.contract, { seat = 2, b = "S", x = 1 }); eq(legalBids(s, 3), "PNAX")
  end)
  it("all trumps leaves the declaring team only a pass", function()
    local s = E.new {}
    deal(s); bids(s, "A")
    eq(legalBids(s, 2), "PX"); bids(s, "P"); eq(legalBids(s, 3), "P")
    bids(s, "P X"); eq(legalBids(s, 1), "PR"); bids(s, "R"); eq(legalBids(s, 2), "P")
  end)
  it("ends after three passes once there is a contract", function()
    local s = E.new { first = 4 }
    deal(s); bids(s, "P P C P P")
    eq(s.phase, "bid"); eq(s.turn, 1)
    bids(s, "P")
    eq(s.phase, "play"); eq(s.turn, 4); eq(s.contract, { seat = 2, b = "C", x = 1 })
    eq(s.bids[3], { s = 2, b = "C" }); eq(#s.bids, 6)
    eq({ E.apply(s, 4, { k = "bid", b = "P" }) }, { nil, "phase" })
  end)
  it("a double resets the pass count", function()
    local s = E.new {}
    deal(s); bids(s, "C P P X P P")
    eq(s.phase, "bid"); bids(s, "P"); eq(s.phase, "play"); eq(s.contract.x, 2)
  end)
  it("four passes pass the deal out: no score, first moves on", function()
    local s = E.new { first = 2 }
    deal(s); bids(s, "P P P")
    eq(s.phase, "bid"); bids(s, "P")
    eq(s.phase, "deal"); eq(s.round, 2); eq(s.first, 3); eq(s.turn, nil); eq(s.score, { 0, 0 })
    eq(s.res.pts, { 0, 0 }); eq(s.res.contract, nil)
    eq({ E.system(s) }, { { k = "deal" }, 5 })
    deal(s); eq(s.turn, 3); eq(#s.hands[1], 5); eq(s.bids, {})
  end)
end)

describe("belot views", function()
  it("a view shows only the seat's own cards", function()
    local s = E.new {}
    deal(s)
    local v = E.view(s, 2)
    for i = 1, 32 do
      local mine = i <= 20 and (i - 1) % 4 + 1 == 2
      eq(v.deck[i], mine and s.deck[i] or nil)
    end
    eq(v.hands, s.hands); eq(v.turn, 1)
    eq(E.view(s, 0).deck, {}); eq(E.view(s, nil).deck, {})
    v.hands[1][1] = 99; eq(s.hands[1][1], 1)
    eq(E.hidden(s, 2), { 2, 6, 10, 14, 18 }); eq(E.hidden(s, 0), {})
  end)
  it("deal and show work on a view", function()
    local v = E.new {}
    ok(E.apply(v, 0, { k = "deal" }))
    eq(v.deck, {}); eq(v.phase, "bid"); eq(#v.hands[3], 5)
    ok(E.apply(v, 0, { k = "show", cards = { [3] = "7H", [7] = "8H" } }))
    eq(v.deck, { [3] = "7H", [7] = "8H" })
    ok(E.apply(v, 0, { k = "show", cards = { [3] = "7H" } }))
    eq({ E.apply(v, 0, { k = "show", cards = { [3] = "9H" } }) }, { nil, "card" })
    eq({ E.apply(v, 0, { k = "show", cards = { [11] = "9H", [4] = "7H" } }) }, { nil, "card" })
    eq({ E.apply(v, 0, { k = "show", cards = { [11] = "9H", [12] = "9H" } }) }, { nil, "card" })
    eq({ E.apply(v, 0, { k = "show", cards = { [40] = "9H" } }) }, { nil, "card" })
    eq({ E.apply(v, 0, { k = "show", cards = { [11] = "1H" } }) }, { nil, "card" })
    eq({ E.apply(v, 1, { k = "show", cards = { [11] = "9H" } }) }, { nil, "seat" })
    eq({ E.apply(v, 0, { k = "show" }) }, { nil, "action" })
    eq(v.deck, { [3] = "7H", [7] = "8H" })
  end)
  it("show on the full state is a no-op when the faces match", function()
    local s = E.new {}
    deal(s)
    local before = E.snapshot(s)
    ok(E.apply(s, 0, { k = "show", cards = { [1] = "7C", [32] = "AS" } }))
    eq({ E.apply(s, 0, { k = "show", cards = { [1] = "8C" } }) }, { nil, "card" })
    eq(E.snapshot(s), before)
  end)
  it("snapshot round-trips and is a copy", function()
    local s = E.new {}
    deal(s); bids(s, "C P")
    local t = E.snapshot(s)
    t.hands[1][1] = 99; t.deck[1] = "AS"
    eq(s.hands[1][1], 1); eq(s.deck[1], "7C")
    eq(E.snapshot(E.restore(E.snapshot(s))), E.snapshot(s))
  end)
end)
