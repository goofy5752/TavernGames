local Wow = require("wow")

local A, B, C, D = "Иван Петров", "Мария Стоянова", "Kiro Barley", "Пешо Тодоров"

-- In a guild, booted with the ui/ files, own name resolved, PLAYER_LOGIN fired.
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
local M, E = w.ns.BelotModel, w.ns.Engines.belot

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

local function deal(s, deck) ok(E.apply(s, 0, { k = "deal", deck = deck })) end
local function bids(s, str)
  for b in str:gmatch("%S+") do
    local okay, why = E.apply(s, s.turn, { k = "bid", b = b })
    ok(okay, "bid " .. b .. " rejected: " .. tostring(why))
  end
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
local function ann(s, str)
  local list = {}
  for t, face in str:gmatch("(%w+):(%w+)") do list[#list + 1] = { t = t, i = idx(s, face) } end
  return E.apply(s, s.turn, { k = "ann", a = list })
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

-- Every card face anywhere in v (keys and values), sorted.
local function faces(v)
  local out = {}
  local function walk(x)
    if type(x) == "string" then
      if x:match("^[789TJQKA][CDHS]$") then out[#out + 1] = x end
    elseif type(x) == "table" then
      for k, y in pairs(x) do walk(k); walk(y) end
    end
  end
  walk(v)
  table.sort(out)
  return out
end

-- A session at seat `seat` (nil: a watcher) over `state` (a view).
local function sess(state, seat)
  return { game = "belot", status = "live", mySeat = seat, seats = { A, B, C, D }, state = state }
end
local function at(st, q) return M.build(sess(E.view(st, q), q)) end

-- The state of the summary tests: a view at seat 1 after a scored deal.
local function scored()
  local st = E.view(started(DECK_A, "S P P P"), 1); st.phase, st.score, st.hang = "deal", { 32, 0 }, 0
  st.res = { round = 1, contract = { seat = 2, b = "H", x = 2 }, raw = { 102, 60 }, pts = { 32, 0 }, hang = 0, valat = false,
    ann = { { s = 1, t = "s3", i = 9, v = 20, on = true }, { s = 2, t = "s3", i = 10, v = 20, on = false }, { s = 4, t = "b", i = 20, v = 20, on = true } } }
  return st
end

describe("ui: the Белот model", function()
  it("the auction: my five cards sorted, only the legal bids, what each seat said", function()
    local st = E.new {}; ok(E.apply(st, 0, { k = "deal", deck = DECK_A })); local m = at(st, 1)
    local ids = {}; for k, c in ipairs(m.hand) do ids[k] = c.i; eq(c.mode, "plain") end; eq(ids, { 13, 1, 5, 9, 17 })       -- 8C | AH KH 7H | JS
    eq(m.bids, { P = true, C = true, D = true, H = true, S = true, N = true, A = true }); eq(m.text, { "belot.yourBid" })
    eq({ m.me, m.team, m.mine, m.dealer, m.pos, m.bubbles, m.score }, { 1, 1, true, 4, { 0, 1, 2, 3 }, {}, { us = 0, them = 0, hang = 0 } })
    ok(E.apply(st, 1, { k = "bid", b = "H" })); eq(at(st, 2).bids, { P = true, S = true, N = true, A = true, X = true })
    ok(E.apply(st, 2, { k = "bid", b = "P" })); m = at(st, 3)
    eq(m.bids, { P = true, S = true, N = true, A = true }); eq(m.pos, { 2, 3, 0, 1 }); eq(m.bubbles, { [1] = { "belot.bid.H" }, [2] = { "belot.bid.P" } })
    eq(at(st, 1).bids, {}); eq(at(st, 1).text, { "belot.waitFor", C })
    local x = started(DECK_A, "H X"); eq(at(x, 3).bids, { P = true, S = true, N = true, A = true, R = true })
  end)

  it("the tricks: trumps sorted as trumps, unplayable cards dimmed, the trick by seat, the last trick on request", function()
    local st = started(DECK_A, "S P P P"); local m = at(st, 1)
    local ids = {}; for k, c in ipairs(m.hand) do ids[k] = c.i; eq(c.mode, "plain") end; eq(ids, { 13, 29, 25, 1, 5, 9, 17, 21 })   -- 8C | 8D 7D | AH KH 7H | JS 9S
    eq({ m.contract, m.announce, m.canPeek, m.text }, { { seat = 1, b = "S", x = 1 }, nil, false, { "belot.yourTurn" } })
    plays(st, "AH"); m = at(st, 2); local modes = {}; ids = {}
    for k, c in ipairs(m.hand) do ids[k], modes[k] = c.i, c.mode end
    eq(ids, { 14, 26, 30, 2, 6, 10, 22, 18 }); eq(modes, { "dim", "dim", "dim", "raised", "raised", "raised", "dim", "dim" })   -- 7C | AD TD | TH QH 9H | KS QS
    plays(st, "9H 8H"); ok(ann(st, "s4:AC")); plays(st, "TS AC 8C"); m = at(st, 1)
    eq(m.trick, { { seat = 4, i = 4, face = "AC" }, { seat = 1, i = 13, face = "8C" } }); eq({ m.canPeek, m.peeking }, { true, nil })
    m = M.build(sess(E.view(st, 1), 1), true); eq(m.peeking, true)
    eq(m.trick, { { seat = 1, i = 1, face = "AH" }, { seat = 2, i = 10, face = "9H" }, { seat = 3, i = 7, face = "8H" }, { seat = 4, i = 24, face = "TS" } })
  end)

  it("bubbles are the engine's record: bids, announces of the first two tricks, a belote on the table", function()
    local st = started(DECK_A, "S P P P"); plays(st, "AH 9H 8H")
    local m = at(st, 4); eq(m.announce, { k = "ann", a = { { t = "s4", i = 4 } } }); eq(m.bubbles, {})        -- offered, not said yet
    ok(ann(st, "s4:AC")); eq(at(st, 4).announce, nil)
    for q = 0, 4 do eq(M.build(sess(E.view(st, q), q > 0 and q or nil)).bubbles, { [4] = { "belot.ann.s4" } }) end
    plays(st, "TS AC 8C"); eq(at(st, 2).bubbles, { [4] = { "belot.ann.s4" } })                                  -- trick 2: still shown
    plays(st, "7C 9C KC 9S"); eq(at(st, 2).bubbles, {})
    ok(E.apply(st, 2, { k = "play", i = 18, c = "QS", b = true })); eq(at(st, 1).bubbles, { [2] = { "belot.ann.b" } })
  end)

  it("the model holds no face outside my hand and the cards on the table", function()
    local st = started(DECK_A, "S P P P"); plays(st, "AH 9H 8H"); ok(ann(st, "s4:AC")); plays(st, "TS AC 8C")
    eq(faces(M.build(sess(E.view(st, 0), nil))), { "8C", "AC" }); eq(faces(M.build(sess(E.view(st, 0), nil), true)), { "8H", "9H", "AH", "TS" })
    eq(faces(at(st, 2)), { "7C", "8C", "AC", "AD", "KS", "QH", "QS", "TD", "TH" })                                 -- its seven cards and the trick
    for _, c in ipairs(M.build(sess(E.view(st, 0), nil)).hand) do eq(c.face, nil) end
  end)

  it("the summary says who is вътре, the doubling and each side's points", function()
    local st = scored()
    local m = M.build(sess(st, 1)); local sum = m.summary
    eq({ sum.passed, sum.contract, sum.us, sum.them, sum.hang, sum.valat, sum.inside, sum.hanging }, { false, { seat = 2, b = "H", x = 2 }, 32, 0, 0, false, true, false })
    eq(M.build(sess(st, 2)).summary.us, 0); eq(M.build(sess(st, 2)).summary.them, 32); eq(m.score, { us = 32, them = 0, hang = 0 }); eq(m.text, nil)
    st.res.raw, st.res.pts, st.res.hang = { 81, 81 }, { 8, 0 }, 11; sum = M.build(sess(st, 1)).summary; eq({ sum.inside, sum.hanging, sum.hang }, { false, true, 11 })
    st.res = { round = 1, raw = { 0, 0 }, pts = { 0, 0 }, hang = 0, valat = false, ann = {} }
    eq(M.build(sess(st, 1)).summary.passed, true); eq(M.build(sess(st, 1)).text, { "belot.passed" })
  end)

  it("the summary names an announce that lost as not counted", function()
    local st = scored()
    eq(M.build(sess(st, 1)).summary.anns, {
      { seat = 1, t = "s3", v = 20, on = true }, { seat = 2, t = "s3", v = 20, on = false }, { seat = 4, t = "b", v = 20, on = true } })
    eq(M.build(sess(st, 2)).summary.anns[2].on, false)
  end)

  it("the end of the match: us, them, the names for a watcher, the one who left", function()
    local st = scored(); st.phase, st.winner = "match", 2
    eq(M.build(sess(st, 1)).text, { "belot.match.them" }); eq(M.build(sess(st, 4)).text, { "belot.match.us" })
    eq(M.build(sess(st, nil)).text, { "belot.match.names", B, D })
    eq(M.build(sess(st, 1)).dealer, nil)
    st.left = 3
    local s = sess(st, 1); s.seats[3] = false
    local m = M.build(s, nil, { A, B, C, D })
    eq(m.text, { "belot.left", C }); eq(m.summary.us, 32); eq(m.summary.inside, true)
  end)
end)
