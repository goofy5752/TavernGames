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
local function idx(s, face)
  for i = 1, 32 do
    if s.deck[i] == face then return i end
  end
end
local function play(s, face, b) return E.apply(s, s.turn, { k = "play", i = idx(s, face), c = face, b = b }) end
local function plays(s, str)
  for face in str:gmatch("%S+") do
    local okay, why = play(s, face)
    ok(okay, "play " .. face .. " rejected: " .. tostring(why))
  end
end
-- The faces the seat may play, sorted (7 8 9 A J K Q T).
local function legalCards(s, seat)
  local out = {}
  for _, a in ipairs(E.legal(s, seat)) do
    if a.k == "play" and not a.b then out[#out + 1] = a.c end
  end
  table.sort(out)
  return table.concat(out, " ")
end
-- The announce actions open to the seat, e.g. "s3:9C | s3:9C+s3:KD | s3:KD".
local function legalAnns(s, seat)
  local out = {}
  for _, a in ipairs(E.legal(s, seat)) do
    if a.k == "ann" then
      local parts = {}
      for n, x in ipairs(a.a) do parts[n] = x.t .. ":" .. s.deck[x.i] end
      out[#out + 1] = table.concat(parts, "+")
    end
  end
  return table.concat(out, " | ")
end
local function ann(s, str)
  local list = {}
  for t, face in str:gmatch("(%w+):(%w+)") do list[#list + 1] = { t = t, i = idx(s, face) } end
  return E.apply(s, s.turn, { k = "ann", a = list })
end
-- A deck dealing the given hands ({[seat] = "8 faces"}); the other seats get the remaining
-- cards in E.DECK order.
local function deckWith(given)
  local used, rest, hands = {}, {}, {}
  for _, str in pairs(given) do
    for face in str:gmatch("%S+") do used[face] = true end
  end
  for _, face in ipairs(E.DECK) do
    if not used[face] then rest[#rest + 1] = face end
  end
  for seat = 1, 4 do
    if given[seat] then
      hands[seat] = given[seat]
    else
      local t = {}
      for _ = 1, 8 do t[#t + 1] = table.remove(rest, 1) end
      hands[seat] = table.concat(t, " ")
    end
  end
  return deckOf(hands[1], hands[2], hands[3], hands[4])
end
local function started(deck, bidStr, first)
  local s = E.new { first = first }
  deal(s, deck); bids(s, bidStr)
  return s
end

local DECK_A = deckOf(
  "AH KH 7H 8C JS 9S 7D 8D",
  "TH QH 9H 7C QS KS AD TD",
  "JH 8H 9C TC 7S 8S JD QD",
  "AC KC QC JC AS TS KD 9D")
local DECK_C = deckOf(
  "TH KH 7C 8C 9C TC JC QC",
  "7H 8H 7D 8D 9D TD JD QD",
  "AH QH KC AC KD AD 7S 8S",
  "9H JH 9S TS JS QS KS AS")

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

describe("belot tricks", function()
  it("suit contract: follow suit, trump when void, over-trump, free when partner wins", function()
    local s = started(DECK_A, "S P P P")
    eq(legalCards(s, 1), "7D 7H 8C 8D 9S AH JS KH"); eq(E.legal(s, 2), {})
    plays(s, "AH"); eq(legalCards(s, 2), "9H QH TH")
    plays(s, "9H"); eq(legalCards(s, 3), "8H JH")
    plays(s, "8H"); eq(legalCards(s, 4), "AS TS") -- void, no trump played yet: must trump
    plays(s, "TS")
    eq(s.pts, { 0, 21 }); eq(s.took, { 0, 1 }); eq(s.turn, 4); eq(s.lead, 4); eq(s.trickNo, 2)
    eq(faces(s, s.last.cards), { "AH", "9H", "8H", "TS" }); eq(s.last.lead, 1); eq(s.last.win, 4)
    eq(s.trick, {}); eq(#s.hands[1], 7)
    eq(legalCards(s, 4), "9D AC AS JC KC KD QC")
    plays(s, "AC"); eq(legalCards(s, 1), "8C")
    plays(s, "8C 7C"); eq(legalCards(s, 3), "9C TC")
    plays(s, "9C"); eq(s.pts, { 0, 32 }); eq(s.turn, 4)
    plays(s, "KC"); eq(legalCards(s, 1), "9S JS")
    -- the opponent trumped with the 9, no higher trump in hand: anything goes
    plays(s, "9S"); eq(legalCards(s, 2), "AD KS QH QS TD TH")
    plays(s, "TD"); eq(legalCards(s, 3), "TC")
    plays(s, "TC"); eq(s.pts, { 38, 32 }); eq(s.turn, 1)
    plays(s, "7H"); eq(legalCards(s, 2), "QH TH")
    plays(s, "TH JH"); eq(legalCards(s, 4), "9D AS JC KD QC") -- partner's ten is winning
    plays(s, "QC"); eq(s.pts, { 38, 47 }); eq(s.turn, 2)
    plays(s, "QH"); eq(legalCards(s, 3), "7S 8S")
    plays(s, "8S"); eq(legalCards(s, 4), "AS") -- must over-trump
    plays(s, "AS"); eq(legalCards(s, 1), "KH")
    plays(s, "KH"); eq(s.pts, { 38, 65 }); eq(s.turn, 4)
    plays(s, "JC"); eq(legalCards(s, 1), "JS")
    plays(s, "JS"); eq(legalCards(s, 2), "AD KS QS")
  end)
  it("trump led in a suit contract: follow, higher if possible", function()
    local s = started(DECK_A, "S P P P")
    plays(s, "9S"); eq(legalCards(s, 2), "KS QS")
    plays(s, "QS"); eq(legalCards(s, 3), "7S 8S")
    plays(s, "7S"); eq(legalCards(s, 4), "AS TS")
    plays(s, "TS"); eq(s.turn, 1); eq(s.pts, { 27, 0 })
    plays(s, "7D"); eq(legalCards(s, 2), "AD TD")
  end)
  it("all trumps: must play higher in the led suit, also over the partner", function()
    local s = started(DECK_A, "A P P P")
    plays(s, "7H"); eq(legalCards(s, 2), "9H QH TH")
    plays(s, "QH"); eq(legalCards(s, 3), "JH")
    plays(s, "JH"); eq(legalCards(s, 4), "9D AC AS JC KC KD QC TS")
    plays(s, "AC"); eq(s.turn, 3); eq(s.pts, { 34, 0 })
    plays(s, "9C"); eq(legalCards(s, 4), "JC")
    plays(s, "JC"); eq(legalCards(s, 1), "8C")
    plays(s, "8C 7C"); eq(s.turn, 4); eq(s.pts, { 34, 34 })
    local c = started(DECK_C, "A P P P")
    plays(c, "TH"); eq(legalCards(c, 2), "7H 8H")
    plays(c, "7H"); eq(legalCards(c, 3), "AH")
  end)
  it("no trumps: follow suit only, plain order wins", function()
    local s = started(DECK_A, "N P P P")
    plays(s, "7H"); eq(legalCards(s, 2), "9H QH TH")
    plays(s, "9H"); eq(legalCards(s, 3), "8H JH")
    plays(s, "8H"); eq(legalCards(s, 4), "9D AC AS JC KC KD QC TS")
    plays(s, "AS"); eq(s.turn, 2); eq(s.pts, { 0, 11 })
    plays(s, "TH JH KC KH"); eq(s.turn, 2); eq(s.pts, { 0, 31 })
  end)
  it("rejects illegal plays and leaves the state alone", function()
    local s = started(DECK_A, "S P P P")
    plays(s, "AH")
    local before = E.snapshot(s)
    eq({ play(s, "7C") }, { nil, "rule" })
    eq({ E.apply(s, 2, { k = "play", i = idx(s, "KH"), c = "KH" }) }, { nil, "card" })
    eq({ E.apply(s, 2, { k = "play", i = idx(s, "TH"), c = "QH" }) }, { nil, "card" })
    eq({ E.apply(s, 2, { k = "play", i = idx(s, "TH") }) }, { nil, "card" })
    eq({ E.apply(s, 2, { k = "play", c = "TH" }) }, { nil, "card" })
    eq({ E.apply(s, 3, { k = "play", i = idx(s, "JH"), c = "JH" }) }, { nil, "turn" })
    eq({ E.apply(s, 0, { k = "play", i = idx(s, "TH"), c = "TH" }) }, { nil, "seat" })
    eq({ play(s, "TH", true) }, { nil, "belot" })
    eq(E.snapshot(s), before)
    local d = E.new {}
    deal(d)
    eq({ E.apply(d, 1, { k = "play", i = 1, c = "7C" }) }, { nil, "phase" })
  end)
  it("belote in a suit contract: trump K or Q while holding the other", function()
    local s = started(DECK_A, "S P P P")
    plays(s, "AH 9H 8H TS AC 8C 7C 9C KC 9S")
    local withBelote = {}
    for _, a in ipairs(E.legal(s, 2)) do
      if a.b then withBelote[#withBelote + 1] = a.c end
    end
    eq(withBelote, { "QS", "KS" })
    eq({ play(s, "TH", true) }, { nil, "belot" })
    ok(play(s, "QS", true))
    eq(s.ann, { { s = 2, t = "b", i = idx(s, "QS") } })
    plays(s, "TC") -- seat 2 wins with the queen of trumps
    eq(s.turn, 1)
    plays(s, "7D"); eq({ play(s, "AD", true) }, { nil, "belot" })
    plays(s, "AD JD KD"); eq(s.turn, 2)
    eq({ play(s, "KS", true) }, { nil, "belot" }) -- the queen is gone
  end)
  it("belote in all trumps: when leading or in the led suit; never in no trumps", function()
    local s = started(DECK_A, "A P P P")
    plays(s, "7H QH JH")
    eq({ play(s, "KC", true) }, { nil, "belot" })
    plays(s, "AC 9C JC 8C 7C")
    ok(play(s, "QC", true)); eq(s.ann[1].s, 4); eq(s.ann[1].t, "b")
    local n = started(DECK_A, "N P P P")
    plays(n, "7H 9H 8H AS")
    eq({ play(n, "QS", true) }, { nil, "belot" })
  end)
  it("plays on a view carry the face; rules are checked only for a known hand", function()
    local s = started(DECK_A, "S P P P")
    local v = E.view(s, 3)
    eq(v.deck[idx(s, "AH")], nil); eq(#v.hands[3], 8); eq(v.deck[idx(s, "JH")], "JH")
    local ah, th, c7 = idx(s, "AH"), idx(s, "TH"), idx(s, "7C")
    eq({ E.apply(v, 1, { k = "play", i = ah, c = "JH" }) }, { nil, "card" }) -- seat 3 holds the JH
    ok(E.apply(v, 1, { k = "play", i = ah, c = "AH" })); eq(v.deck[ah], "AH")
    eq({ E.apply(v, 2, { k = "play", i = th, c = "AH" }) }, { nil, "card" })
    ok(E.apply(v, 2, { k = "play", i = c7, c = "7C" })) -- cannot tell it breaks the rules
    eq({ E.apply(v, 3, { k = "play", i = idx(s, "9C"), c = "9C" }) }, { nil, "rule" })
    eq(legalCards(v, 3), "8H JH"); eq(E.legal(v, 1), {})
    ok(E.apply(v, 3, { k = "play", i = idx(s, "8H"), c = "8H" }))
    ok(E.apply(v, 4, { k = "play", i = idx(s, "TS"), c = "TS" }))
    eq(v.pts, { 0, 21 }); eq(v.turn, 4)
  end)
  it("a view shows the current and the last trick only", function()
    local s = started(DECK_A, "S P P P")
    plays(s, "AH 9H 8H TS AC 8C 7C 9C KC 9S")
    local seen = {}
    for _, face in pairs(E.view(s, 0).deck) do seen[#seen + 1] = face end
    table.sort(seen)
    eq(seen, { "7C", "8C", "9C", "9S", "AC", "KC" })
    eq(E.hidden(s, 1), s.hands[1])
  end)
end)

describe("belot announces", function()
  local function hand1(str, bid) return started(deckWith { [1] = str }, (bid or "A") .. " P P P") end
  it("offers the fours, the free sequences, then the sequences through a four", function()
    eq(legalAnns(hand1("JC JD JH JS 9C TC QC KC"), 1), "cJ:JS | s5:KC")
    eq(legalAnns(hand1("7C 8C 9C JD QD KD AS TS"), 1), "s3:9C | s3:9C+s3:KD | s3:KD")
    eq(legalAnns(hand1("7C 7D 7H 7S 8C 8D 8H 8S"), 1), "")
    eq(legalAnns(hand1("7H 8H 9H TH JH QH KH AH"), 1), "s8:AH")
    eq(legalAnns(hand1("TC TD TH TS AC AD AH AS"), 1), "c:TS | c:TS+c:AS | c:AS")
    eq(legalAnns(hand1("9C 9D 9H 9S TC JC TD JD"), 1), "c9:9S | s3:JC | s3:JC+s3:JD | s3:JD")
    eq(legalAnns(hand1("7S 8S 9S TS QS KS AS 7C"), 1), "s4:TS | s4:TS+s3:AS | s3:AS")
    eq(legalAnns(hand1("QC QD QH QS KC KD KH KS"), 1), "c:QS | c:QS+c:KS | c:KS")
    eq(legalAnns(hand1("7H 8H 9H TH JH QH KH AH", "N"), 1), "")
  end)
  it("announces once, at the seat's turn in the first trick, before its card", function()
    local s = hand1("7C 8C 9C JD QD KD AS TS")
    eq({ E.apply(s, 2, { k = "ann", a = { { t = "s3", i = idx(s, "9C") } } }) }, { nil, "turn" })
    eq({ E.apply(s, 0, { k = "ann", a = {} }) }, { nil, "seat" })
    ok(ann(s, "s3:KD s3:9C"))
    eq(s.ann, { { s = 1, t = "s3", i = idx(s, "KD") }, { s = 1, t = "s3", i = idx(s, "9C") } })
    eq({ ann(s, "s3:9C") }, { nil, "phase" }); eq(legalAnns(s, 1), "")
    plays(s, "AS")
    eq(s.announced, false); eq(s.turn, 2)
    for _ = 1, 3 do ok(E.apply(s, s.turn, E.legal(s, s.turn)[1])) end
    eq(s.trickNo, 2); eq({ E.apply(s, s.turn, { k = "ann", a = { { t = "s3", i = 1 } } }) }, { nil, "phase" })
    local n = hand1("7C 8C 9C JD QD KD AS TS", "N")
    eq({ ann(n, "s3:9C") }, { nil, "phase" })
    local d = E.new {}
    deal(d); eq({ E.apply(d, 1, { k = "ann", a = {} }) }, { nil, "phase" })
  end)
  it("rejects what is not offered, a card used twice, and junk", function()
    local s = hand1("JC JD JH JS 9C TC QC KC")
    local before = E.snapshot(s)
    eq({ ann(s, "cJ:JS s5:KC") }, { nil, "announce" })
    eq({ ann(s, "s4:KC") }, { nil, "announce" })
    eq({ ann(s, "cJ:JC") }, { nil, "announce" })
    eq({ ann(s, "cJ:JS cJ:JS") }, { nil, "announce" })
    eq({ ann(s, "b:KC") }, { nil, "announce" })
    eq({ ann(s, "zz:KC") }, { nil, "announce" })
    eq({ ann(s, "s3:7D") }, { nil, "announce" }) -- not in the hand
    eq({ E.apply(s, 1, { k = "ann", a = {} }) }, { nil, "announce" })
    eq({ E.apply(s, 1, { k = "ann" }) }, { nil, "announce" })
    eq({ E.apply(s, 1, { k = "ann", a = { 5 } }) }, { nil, "announce" })
    eq(E.snapshot(s), before)
    ok(ann(s, "s5:KC"))
  end)
  it("on a view an announce of an unseen hand is taken on trust", function()
    local s = hand1("7C 8C 9C JD QD KD AS TS")
    local v = E.view(s, 2)
    local a = { k = "ann", a = { { t = "s3", i = idx(s, "9C") } } }
    eq({ E.apply(v, 1, { k = "ann", a = { { t = "s3", i = s.hands[2][1] } } }) }, { nil, "announce" })
    ok(E.apply(v, 1, a)); ok(E.apply(s, 1, a))
    eq(v.ann, s.ann); eq(E.legal(v, 1), {})
  end)
end)
