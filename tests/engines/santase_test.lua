local E = Loader.ns().Engines.santase

-- Fixed deck from hands: deck[1..3] non-dealer, [4..6] dealer, [7..9] non-dealer, [10..12] dealer,
-- [13] face-up trump, [14..] stock in draw order (spec.stock first, then the rest in E.DECK order).
local function deckOf(spec)
  local d = {}
  local function put(f) d[#d + 1] = f end
  for k = 1, 3 do put(spec.non[k]) end
  for k = 1, 3 do put(spec.dealer[k]) end
  for k = 4, 6 do put(spec.non[k]) end
  for k = 4, 6 do put(spec.dealer[k]) end
  put(spec.trump)
  for _, f in ipairs(spec.stock or {}) do put(f) end
  local used = {}
  for _, f in ipairs(d) do used[f] = true end
  for _, f in ipairs(E.DECK) do if not used[f] then put(f) end end
  assert(#d == 24, "deck size")
  return d
end

-- Seat 1 leads the first hand (first = 1), seat 2 deals. Trump hearts, JH face-up.
local STD = {
  non    = {"AS", "TS", "KH", "QH", "9C", "JD"},
  dealer = {"AC", "TC", "KC", "9H", "JS", "QD"},
  trump  = "JH",
  stock  = {"9S", "KS", "QS", "9D", "KD", "TD", "AD", "QC", "JC", "TH", "AH"},
}

local function idx(s, f) for i = 1, 24 do if s.deck[i] == f then return i end end end
local function dealt(spec, first)
  local s = E.new{ first = first or 1 }
  ok(E.apply(s, 0, { k = "deal", deck = deckOf(spec or STD) }))
  return s
end
local function P(s, seat, f) return E.apply(s, seat, { k = "play", i = idx(s, f), c = f }) end
local function plays(s, seq) for n = 1, #seq, 2 do ok(P(s, seq[n], seq[n + 1]), "play " .. seq[n + 1]) end end
local function faces(s, list)
  local out = {}
  for n, i in ipairs(list) do out[n] = s.deck[i] or "?" end
  table.sort(out)
  return out
end
local function sorted(t) local c = {} for n, v in ipairs(t) do c[n] = v end table.sort(c) return c end
local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
local function has(list, a)
  for _, x in ipairs(list) do
    local same = true
    for k, v in pairs(a) do if x[k] ~= v then same = false end end
    for k in pairs(x) do if a[k] == nil then same = false end end
    if same then return true end
  end
  return false
end

-- A full STD state reduced to an end position: given hands (faces), empty stock, given points/tricks.
local function craft(h1, h2, o)
  local s = dealt()
  o = o or {}
  s.hands = { {}, {} }
  for _, f in ipairs(h1) do table.insert(s.hands[1], idx(s, f)) end
  for _, f in ipairs(h2) do table.insert(s.hands[2], idx(s, f)) end
  s.stock = o.stock or {}
  s.trumpI = o.trumpI
  s.pts = o.pts or { 0, 0 }
  s.ntr = o.ntr or { 1, 1 }
  s.mar = o.mar or { 0, 0 }
  s.lead = o.lead or 1
  s.turn = s.lead
  return s
end

describe("santase: deck and deal", function()
  it("has 24 distinct cards 9..A in four suits and the documented values", function()
    eq(#E.DECK, 24)
    local seen = {}
    for _, f in ipairs(E.DECK) do seen[f] = true end
    eq(count(seen), 24)
    eq(E.DECK[1], "9C"); eq(E.DECK[6], "AC"); eq(E.DECK[24], "AS")
    eq({ E.VALUE["9"], E.VALUE.J, E.VALUE.Q, E.VALUE.K, E.VALUE.T, E.VALUE.A }, { 0, 2, 3, 4, 10, 11 })
    eq(E.id, "santase"); eq(E.minSeats, 2); eq(E.maxSeats, 2); eq(E.options, {})
  end)
  it("waits for a deal, then deals 3+3, turns the trump and stacks the stock", function()
    local s = E.new{ first = 1 }
    eq(s.phase, "deal"); eq(s.turn, nil); eq({ E.system(s) }, { { k = "deal" }, 0 })
    ok(E.apply(s, 0, { k = "deal", deck = deckOf(STD) }))
    eq(s.phase, "play"); eq(s.dealer, 2); eq(s.turn, 1); eq(s.lead, 1); eq(s.hand, 1)
    eq(s.hands[1], { 1, 2, 3, 7, 8, 9 }); eq(s.hands[2], { 4, 5, 6, 10, 11, 12 })
    eq(s.trumpI, 13); eq(s.tsuit, "H"); eq(#s.stock, 12); eq(s.stock[1], 14); eq(s.stock[12], 13)
    eq(E.system(s), nil)
  end)
  it("first = 2 makes seat 2 the leader and seat 1 the dealer", function()
    local s = dealt(STD, 2)
    eq(s.dealer, 1); eq(s.turn, 2); eq(faces(s, s.hands[2]), sorted(STD.non))
  end)
  it("rejects a deal that is not a permutation of the deck, at seat 0 only, in the deal phase only", function()
    local s = E.new{}
    local bad = deckOf(STD); bad[24] = bad[1]
    eq({ E.apply(s, 0, { k = "deal", deck = bad }) }, { nil, "deck" })
    local short = deckOf(STD); short[24] = nil
    eq({ E.apply(s, 0, { k = "deal", deck = short }) }, { nil, "deck" })
    local junk = deckOf(STD); junk[3] = "2C"
    eq({ E.apply(s, 0, { k = "deal", deck = junk }) }, { nil, "deck" })
    eq({ E.apply(s, 0, { k = "deal" }) }, { nil, "deck" })
    eq({ E.apply(s, 1, { k = "deal", deck = deckOf(STD) }) }, { nil, "seat" })
    eq(s.phase, "deal")
    ok(E.apply(s, 0, { k = "deal", deck = deckOf(STD) }))
    eq({ E.apply(s, 0, { k = "deal", deck = deckOf(STD) }) }, { nil, "phase" })
  end)
end)

describe("santase: tricks with the stock open", function()
  it("a trump beats the led suit; the winner draws first and leads", function()
    local s = dealt()
    plays(s, { 1, "AS", 2, "9H" })
    eq(s.pts, { 0, 11 }); eq(s.ntr, { 0, 1 }); eq(s.turn, 2); eq(s.lead, 2)
    eq(s.last, { idx(s, "AS"), idx(s, "9H") }); eq(s.trick, {})
    eq(s.hands[2][6], 14); eq(s.hands[1][6], 15); eq(#s.stock, 10)
  end)
  it("no duty to follow: an off-suit card loses, a higher card of the suit wins", function()
    local s = dealt()
    plays(s, { 1, "9C", 2, "JS" })
    eq(s.pts, { 2, 0 }); eq(s.turn, 1)
    plays(s, { 1, "JD", 2, "QD" })
    eq(s.pts, { 2, 5 }); eq(s.turn, 2)
  end)
  it("rejects play off turn, a card not in hand, a wrong face, and the table seat", function()
    local s = dealt()
    eq({ P(s, 2, "AC") }, { nil, "turn" })
    eq({ P(s, 1, "AC") }, { nil, "card" })
    eq({ E.apply(s, 1, { k = "play", i = idx(s, "AS"), c = "TS" }) }, { nil, "card" })
    eq({ E.apply(s, 1, { k = "play", i = 99, c = "AS" }) }, { nil, "card" })
    eq({ E.apply(s, 0, { k = "play", i = idx(s, "AS"), c = "AS" }) }, { nil, "seat" })
    eq({ E.apply(s, 3, { k = "play", i = idx(s, "AS"), c = "AS" }) }, { nil, "seat" })
    eq({ E.apply(s, 1, { k = "bogus" }) }, { nil, "action" })
    eq({ E.apply(s, 1, nil) }, { nil, "action" })
    eq(#s.hands[1], 6); eq(s.trick, {})
  end)
  it("the last two stock cards: the winner takes the hidden one, the loser the face-up trump", function()
    local s = dealt()
    s.stock = { 24, 13 }
    plays(s, { 1, "AS", 2, "9H" })
    eq(s.hands[2][6], 24); eq(s.hands[1][6], 13); eq(s.stock, {}); eq(s.trumpI, nil); eq(s.shown[13], true)
  end)
end)

describe("santase: obligations once the stock is closed or gone", function()
  local function legalFaces(s, seat)
    local out = {}
    for _, a in ipairs(E.legal(s, seat)) do if a.k == "play" then out[#out + 1] = a.c end end
    table.sort(out)
    return out
  end
  it("must head the led card when able", function()
    local s = craft({ "QS" }, { "9S", "AS", "9H" }); ok(P(s, 1, "QS"))
    eq(legalFaces(s, 2), { "AS" })
    eq({ P(s, 2, "9S") }, { nil, "move" }); eq({ P(s, 2, "9H") }, { nil, "move" })
  end)
  it("must follow with a lower card when it cannot head", function()
    local s = craft({ "QS" }, { "9S", "9H" }); ok(P(s, 1, "QS"))
    eq(legalFaces(s, 2), { "9S" })
  end)
  it("must trump when void in the led suit", function()
    local s = craft({ "QS" }, { "9H", "AC" }); ok(P(s, 1, "QS"))
    eq(legalFaces(s, 2), { "9H" })
  end)
  it("plays anything when void in the led suit and in trumps", function()
    local s = craft({ "QS" }, { "AC", "AD" }); ok(P(s, 1, "QS"))
    eq(legalFaces(s, 2), { "AC", "AD" })
  end)
  it("a trump lead must be headed with a higher trump", function()
    local s = craft({ "QH" }, { "9H", "KH", "AS" }); ok(P(s, 1, "QH"))
    eq(legalFaces(s, 2), { "KH" })
  end)
end)

describe("santase: end of the hand and scoring", function()
  it("the last trick of a played-out stock is worth 10", function()
    local s = craft({ "9C" }, { "JC" }, { pts = { 40, 30 } })
    plays(s, { 1, "9C", 2, "JC" })
    eq(s.pts, { 40, 42 })
  end)
  it("65:65 is a tie: no game points, the same dealer deals again", function()
    local s = craft({ "9C" }, { "JC" }, { pts = { 65, 53 } })
    plays(s, { 1, "9C", 2, "JC" })
    eq(s.phase, "hand"); eq(s.gp, { 0, 0 }); eq(s.res, { winner = 0, gp = 0, reason = "tie" })
    eq(s.dealer, 2); eq(s.turn, nil); eq({ E.system(s) }, { { k = "deal" }, 3 })
    ok(E.apply(s, 0, { k = "deal", deck = deckOf(STD) }))
    eq(s.hand, 2); eq(s.dealer, 2); eq(s.turn, 1); eq(s.res, nil); eq(s.pts, { 0, 0 })
  end)
  it("loser with 33 or more scores the winner 1, under 33 scores 2, without a trick 3", function()
    local a = craft({ "9C" }, { "JC" }, { pts = { 33, 60 } }); plays(a, { 1, "9C", 2, "JC" })
    eq(a.res, { winner = 2, gp = 1, reason = "66" }); eq(a.gp, { 0, 1 })
    local b = craft({ "9C" }, { "JC" }, { pts = { 32, 60 } }); plays(b, { 1, "9C", 2, "JC" })
    eq(b.res, { winner = 2, gp = 2, reason = "66" })
    local c = craft({ "9C" }, { "JC" }, { pts = { 0, 60 }, ntr = { 0, 5 } }); plays(c, { 1, "9C", 2, "JC" })
    eq(c.res, { winner = 2, gp = 3, reason = "66" })
  end)
  it("reaching 66 mid-hand ends it at once; the winner deals the next hand", function()
    local s = craft({ "AS", "9D" }, { "TS", "9C" }, { pts = { 50, 40 }, stock = { 23, 24 }, trumpI = 24 })
    plays(s, { 1, "AS", 2, "TS" })
    eq(s.pts[1], 71); eq(s.phase, "hand"); eq(s.res, { winner = 1, gp = 1, reason = "66" }); eq(s.dealer, 1)
    ok(E.apply(s, 0, { k = "deal", deck = deckOf(STD) }))
    eq(s.dealer, 1); eq(s.turn, 2); eq(faces(s, s.hands[2]), sorted(STD.non))
  end)
  it("loser's marriage counts toward 33 only if he has a trick", function()
    local a = craft({ "9C" }, { "JC" }, { pts = { 13, 60 }, mar = { 20, 0 } }); plays(a, { 1, "9C", 2, "JC" })
    eq(a.res.gp, 1)
    local b = craft({ "9C" }, { "JC" }, { pts = { 0, 60 }, ntr = { 0, 5 }, mar = { 40, 0 } }); plays(b, { 1, "9C", 2, "JC" })
    eq(b.res.gp, 3)
  end)
end)

describe("santase: marriages", function()
  it("the leader may declare by playing K or Q and showing the partner", function()
    local s = dealt()
    local l = E.legal(s, 1)
    ok(has(l, { k = "marry", i = idx(s, "KH"), c = "KH", j = idx(s, "QH"), d = "QH" }))
    ok(has(l, { k = "marry", i = idx(s, "QH"), c = "QH", j = idx(s, "KH"), d = "KH" }))
    eq(#l, 6 + 2 + 1)  -- six plays, two marriage leads, close
  end)
  it("trump marriage is 40 and counts once the declarer wins a trick", function()
    local s = dealt()
    ok(E.apply(s, 1, { k = "marry", i = idx(s, "QH"), c = "QH", j = idx(s, "KH"), d = "KH" }))
    eq(s.mar, { 40, 0 }); eq(s.shown[idx(s, "KH")], true); eq(s.turn, 2)
    ok(P(s, 2, "TC"))
    eq(s.pts, { 13, 0 }); eq(E.points(s, 1), 53)
  end)
  it("a non-trump marriage is 20 and stays pending while the declarer has no trick", function()
    local spec = { non = { "KS", "QS", "9C", "JD", "TD", "9D" }, dealer = { "AS", "AC", "TC", "9H", "JS", "QD" }, trump = "JH" }
    local s = dealt(spec)
    ok(E.apply(s, 1, { k = "marry", i = idx(s, "KS"), c = "KS", j = idx(s, "QS"), d = "QS" }))
    ok(P(s, 2, "AS"))
    eq(s.mar, { 20, 0 }); eq(E.points(s, 1), 0); eq(E.points(s, 2), 15)
    plays(s, { 2, "JS", 1, "QS" })
    eq(E.points(s, 1), 25)
  end)
  it("reaching 66 by declaring ends the hand at once", function()
    local s = craft({ "KH", "QH", "9D" }, { "9C", "AC", "TC" }, { pts = { 30, 40 }, stock = { 22, 23, 24, 13 }, trumpI = 13 })
    ok(E.apply(s, 1, { k = "marry", i = idx(s, "KH"), c = "KH", j = idx(s, "QH"), d = "QH" }))
    eq(s.phase, "hand"); eq(s.res, { winner = 1, gp = 1, reason = "66" }); eq(s.trick, { idx(s, "KH") })
  end)
  it("rejects a marriage when responding or with the wrong partner", function()
    local s = dealt()
    eq({ E.apply(s, 1, { k = "marry", i = idx(s, "KH"), c = "KH", j = idx(s, "AS"), d = "AS" }) }, { nil, "move" })
    ok(P(s, 1, "9C"))
    s.hands[2][1] = idx(s, "QC")
    eq({ E.apply(s, 2, { k = "marry", i = idx(s, "KC"), c = "KC", j = idx(s, "QC"), d = "QC" }) }, { nil, "move" })
    eq(s.mar, { 0, 0 })
  end)
end)

describe("santase: exchanging the trump nine", function()
  it("needs a won trick, the lead and more than two stock cards", function()
    local s = dealt()
    plays(s, { 1, "9C", 2, "AC" })
    local a = { k = "swap9", i = idx(s, "9H"), c = "9H" }
    ok(has(E.legal(s, 2), a))
    ok(E.apply(s, 2, a))
    eq(s.trumpI, idx(s, "9H")); eq(s.stock[#s.stock], idx(s, "9H")); eq(s.shown[13], true)
    local held = false
    for _, i in ipairs(s.hands[2]) do if i == 13 then held = true end end
    ok(held, "JH taken into the hand")
    eq({ E.apply(s, 2, a) }, { nil, "card" })
  end)
  it("is refused without a trick, off the lead, with two stock cards or after closing", function()
    local spec = { non = { "9H", "AS", "TS", "KC", "9C", "JD" }, dealer = { "AC", "TC", "KH", "QH", "JS", "QD" }, trump = "JH" }
    local s = dealt(spec)
    local a = { k = "swap9", i = idx(s, "9H"), c = "9H" }
    eq({ E.apply(s, 1, a) }, { nil, "move" })
    plays(s, { 1, "AS", 2, "JS" })
    s.stock = { 23, 13 }
    eq({ E.apply(s, 1, a) }, { nil, "move" })
    s.stock = { 21, 22, 23, 13 }
    ok(E.apply(s, 1, { k = "close" }))
    eq({ E.apply(s, 1, a) }, { nil, "move" })
  end)
end)

describe("santase: closing", function()
  it("the closer fails: the opponent scores 3 when he had no trick at the closing", function()
    local s = dealt()
    ok(has(E.legal(s, 1), { k = "close" }))
    ok(E.apply(s, 1, { k = "close" }))
    eq(s.closed, 1); eq(s.closeOpp, false); eq(s.turn, 1)
    eq({ E.apply(s, 1, { k = "close" }) }, { nil, "move" })
    ok(P(s, 1, "AS"))
    eq({ P(s, 2, "9H") }, { nil, "move" })
    plays(s, { 2, "JS" })
    eq(#s.stock, 12); eq(#s.hands[1], 5)
    plays(s, { 1, "9C", 2, "AC", 2, "QD", 1, "JD", 2, "TC", 1, "QH", 1, "KH", 2, "9H", 1, "TS", 2, "KC" })
    eq(s.pts, { 44, 16 })
    eq(s.phase, "hand"); eq(s.res, { winner = 2, gp = 3, reason = "fail" }); eq(s.gp, { 0, 3 }); eq(s.dealer, 2)
  end)
  it("closeOpp records whether the opponent had a trick at the closing", function()
    local s = dealt()
    plays(s, { 1, "JD", 2, "QD", 2, "9S", 1, "KS" })
    ok(E.apply(s, 1, { k = "close" }))
    eq(s.closed, 1); eq(s.closeOpp, true)
  end)
  it("the closer fails: 2 when the opponent had a trick at the closing, 3 when not, no last-trick 10", function()
    local a = craft({ "9C" }, { "JC" }, { pts = { 40, 30 } }); a.closed, a.closeOpp = 1, true
    plays(a, { 1, "9C", 2, "JC" })
    eq(a.pts, { 40, 32 }); eq(a.res, { winner = 2, gp = 2, reason = "fail" })
    local b = craft({ "9C" }, { "JC" }, { pts = { 40, 30 } }); b.closed, b.closeOpp = 1, false
    plays(b, { 1, "9C", 2, "JC" })
    eq(b.res, { winner = 2, gp = 3, reason = "fail" })
  end)
  it("the opponent of the closer who reaches 66 first scores 2 or 3, not the 1/2/3 table", function()
    local a = craft({ "9C", "AD" }, { "JC", "9D" }, { pts = { 40, 64 } }); a.closed, a.closeOpp = 1, true
    plays(a, { 1, "9C", 2, "JC" })
    eq(a.res, { winner = 2, gp = 2, reason = "66" })
  end)
  it("the closer who reaches 66 scores normally", function()
    local s = dealt()
    ok(E.apply(s, 1, { k = "close" }))
    ok(E.apply(s, 1, { k = "marry", i = idx(s, "KH"), c = "KH", j = idx(s, "QH"), d = "QH" }))
    plays(s, { 2, "9H", 1, "AS", 2, "JS", 1, "TS", 2, "QD" })
    eq(s.pts, { 30, 0 }); eq(E.points(s, 1), 70)
    eq(s.res, { winner = 1, gp = 3, reason = "66" })
  end)
  it("is refused with two stock cards left or while a trick is open", function()
    local s = dealt()
    ok(P(s, 1, "9C"))
    eq({ E.apply(s, 2, { k = "close" }) }, { nil, "move" })
    local t = dealt(); t.stock = { 24, 13 }
    eq({ E.apply(t, 1, { k = "close" }) }, { nil, "move" })
    ok(not has(E.legal(t, 1), { k = "close" }))
  end)
end)
