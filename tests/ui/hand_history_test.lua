local Wow = require("wow")

-- The table's hand history (ui/HandHistory.lua): a memory-only recorder fed by the client's
-- "session" event and the „История“ panel inside the table frame, for Белот, Сантасе and Холдем.
-- What matters most: it never shows a card the table has not seen face up.
local A, B, C, D = "Иван Петров", "Мария Стоянова", "Kiro Barley", "Пешо Тодоров"
local BOT = "Бот Иванов"

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

local function withBots()
  local w = guildWow()
  w:slash("bots")
  w:advance(0); w:advance(0)
  return w
end

local NS = guildWow().ns
local EB, ES, EH = NS.Engines.belot, NS.Engines.santase, NS.Engines.holdem
local HH = require("holdem")(EH)

-- `text` without inline colour codes (|cAARRGGBB … |r).
local function plain(text) return (tostring(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

-- Every visible font string's text in the sandbox.
local function allTexts(w)
  local out = {}
  for _, f in ipairs(w.frames) do
    for _, r in ipairs(f.regions) do
      if r.objectType == "FontString" and r.text and r:IsVisible() then out[#out + 1] = r.text end
    end
  end
  return out
end

-- The panel's lines, top to bottom, colour codes stripped.
local function lines(panel)
  local out = {}
  for i, fs in ipairs(panel.lines) do
    if i > panel.used then break end
    out[#out + 1] = plain(fs:GetText())
  end
  return out
end

-- The first line of the panel containing every needle (plain), or nil.
local function lineWith(panel, ...)
  local needles = { ... }
  for _, text in ipairs(lines(panel)) do
    local all = true
    for _, n in ipairs(needles) do all = all and text:find(plain(n), 1, true) ~= nil end
    if all then return text end
  end
  return nil
end

-- No visible font string anywhere shows the card `face` as the history prints it.
local function neverShown(w, face, why)
  local tag = plain(w.ns.HandHistory.card(face))
  for _, text in ipairs(allTexts(w)) do
    ok(not plain(text):find(tag, 1, true), (why or "hidden card") .. " " .. face .. " shown in: " .. plain(text))
  end
end

-- No face string `face` anywhere in the recorder's memory (deep).
local function notRecorded(w, face)
  local seen = {}
  local function scan(t)
    if seen[t] then return end
    seen[t] = true
    for k, v in pairs(t) do
      ok(v ~= face and k ~= face, "recorded " .. face)
      if type(v) == "table" then scan(v) end
    end
  end
  scan(w.ns.HandHistory.tables)
end

-- The panel over a parent of the table's felt size.
local function setup(wi, hi)
  local w = guildWow()
  local parent = w.G.CreateFrame("Frame", nil, w.G.UIParent)
  parent:SetSize(wi or 532, hi or 340)
  local panel = w.ns.HandHistory.buildPanel(parent)
  panel:Show()
  return w, panel
end

---------------------------------------------------------------------------
-- Белот
---------------------------------------------------------------------------

local function deckOf(h1, h2, h3, h4)
  local hands, deck = {}, {}
  for seat, str in ipairs({ h1, h2, h3, h4 }) do
    hands[seat] = {}
    for face in str:gmatch("%S+") do hands[seat][#hands[seat] + 1] = face end
  end
  for j = 1, 20 do deck[j] = hands[(j - 1) % 4 + 1][math.floor((j - 1) / 4) + 1] end
  for j = 21, 32 do deck[j] = hands[(j - 1) % 4 + 1][6 + math.floor((j - 21) / 4)] end
  return deck
end
local DECK_A = deckOf(
  "AH KH 7H 8C JS 9S 7D 8D",
  "TH QH 9H 7C QS KS AD TD",
  "JH 8H 9C TC 7S 8S JD QD",
  "AC KC QC JC AS TS KD 9D")

-- FULL: the sessions carry the engine's whole state, every face, instead of my seat's view: what the
-- history shows must then still be only what the table saw face up (its own gate, not the view's).
local FULL = false
-- Runs body() on views, then on full states.
local function bothWays(body) return function() for _, full in ipairs({ false, true }) do FULL = full; body() end; FULL = false end end

local function bsess(st, seat)
  return { game = "belot", status = "live", mySeat = seat, seats = { A, B, C, D }, state = FULL and EB.snapshot(st) or EB.view(st, seat),
    tid = "t#1", epoch = 1, seq = 1, role = seat and "player" or "watcher", gameNo = 1 }
end
local function bidx(st, face) for i = 1, 32 do if st.deck[i] == face then return i end end end

describe("ui: hand history — Белот", function()
  it("two tricks: each seat's card in turn order, the winner named, the contract; nothing unplayed", bothWays(function()
    local w, panel = setup()
    local H = w.ns.HandHistory
    local sent = #w.sent
    local st = EB.new{ first = 1 }
    ok(EB.apply(st, 0, { k = "deal", deck = DECK_A }))
    local played = {}
    -- after every event: no card that is not on the table yet, on screen or in memory
    local function see()
      H.observe(bsess(st, 1)); H.draw(panel, bsess(st, 1))
      for _, face in ipairs(DECK_A) do
        if not played[face] then neverShown(w, face); notRecorded(w, face) end
      end
    end
    see()
    for _, b in ipairs({ "H", "P", "P", "P" }) do ok(EB.apply(st, st.turn, { k = "bid", b = b })); see() end
    for _, face in ipairs({ "8C", "7C", "TC", "AC", "AS", "JS", "KS", "7S" }) do
      ok(EB.apply(st, st.turn, { k = "play", i = bidx(st, face), c = face }), "play " .. face)
      played[face] = true
      see()
    end
    H.draw(panel, bsess(st, 1))
    local L, card = w.ns.L, H.card
    eq(lines(panel)[1], plain(L("table.historyHand", 1)))
    ok(lineWith(panel, L("belot.contract", L("belot.bid.H"))), "no contract line")
    local t1 = lineWith(panel, "1.", "Иван " .. card("8C"), "Мария " .. card("7C"), "Kiro " .. card("TC"), "Пешо " .. card("AC"))
    ok(t1, "trick 1: " .. table.concat(lines(panel), " / "))
    ok(t1:find(plain(L("table.historyWon", "Пешо")), 1, true), "trick 1's winner: " .. t1)
    local t2 = lineWith(panel, "2.", "Пешо " .. card("AS"), "Иван " .. card("JS"), "Мария " .. card("KS"), "Kiro " .. card("7S"))
    ok(t2, "trick 2"); ok(t2:find(plain(L("table.historyWon", "Пешо")), 1, true), "trick 2's winner")
    -- the order of the lines: the hand, the contract, trick 1, trick 2
    local ls = lines(panel)
    eq({ ls[3] == t1, ls[4] == t2 }, { true, true })
    for _, face in ipairs(DECK_A) do
      if not played[face] then neverShown(w, face); notRecorded(w, face) end
    end
    eq(#w.sent, sent)
  end))

  it("a new hand goes on top; at most 10 hands, the oldest dropped", function()
    local w, panel = setup()
    local H, L = w.ns.HandHistory, w.ns.L
    for round = 1, 12 do
      local st = EB.new{ first = 1 }
      ok(EB.apply(st, 0, { k = "deal", deck = DECK_A }))
      st.round = round
      H.observe(bsess(st, 1))
      H.draw(panel, bsess(st, 1))
      eq(lines(panel)[1], plain(L("table.historyHand", round)))
    end
    local heads = {}
    for _, text in ipairs(lines(panel)) do
      local n = text:match("^" .. plain(L("table.historyHand", 0)):gsub("0", "(%%d+)") .. "$")
      if n then heads[#heads + 1] = tonumber(n) end
    end
    eq(heads, { 12, 11, 10, 9, 8, 7, 6, 5, 4, 3 })
    eq(#H.tables["t#1"].hands, 10)
  end)
end)

---------------------------------------------------------------------------
-- Сантасе
---------------------------------------------------------------------------

-- DM[i] = the face of deck index i: seat 1 (me, the non-dealer) holds 1–3 and 7–9, seat 2 4–6
-- and 10–12, the trump card is JH (hearts).
local DM = { "KH", "QH", "TS", "AS", "JC", "QC", "JD", "AD", "9S", "KC", "TC", "AC",
             "JH", "9D", "QD", "KD", "TD", "9H", "TH", "AH", "JS", "QS", "KS", "9C" }

-- I open Сантасе „Само поканени“ and „Бот Иванов“ takes the invitation: a real table.
local function santaseWithBot()
  local w = withBots()
  w.ns.client:openTable{ game = "santase", access = "invite", turn = 45 }
  w:advance(0)
  local v = w.ns.TableFrame.view
  w:click(v.inviteButton)
  local row
  for _, r in ipairs(v.picker.rows) do
    if r.frame:IsVisible() and r.name:GetText() == BOT then row = r end
  end
  assert(row, "no row for the bot in the picker")
  w:click(row.frame)
  w:advance(2)
  return w, v
end

describe("ui: hand history — Сантасе", function()
  it("tricks with their winners, 40 declared, the close, the result; never the stock nor a hand", bothWays(function()
    local w, v = santaseWithBot()
    local H, L, card, client = w.ns.HandHistory, w.ns.L, w.ns.HandHistory.card, w.ns.client
    local s = client.session
    eq({ s.game, s.seats[1], s.seats[2], v.historyButton:IsVisible() }, { "santase", A, BOT, true })
    H.tables = {}
    local sent = #w.sent
    local st = ES.new{ first = 1 }
    ok(ES.apply(st, 0, { k = "deal", deck = DM }))
    local played = {}
    w:click(v.historyButton)
    -- after every event: no card that is not on the table yet, on screen or in memory
    local function see()
      s.state = FULL and ES.snapshot(st) or ES.view(st, 1)
      client.events:emit("session", s)
      w.ns.TableFrame.render()
      for _, face in ipairs(DM) do if not played[face] then neverShown(w, face, "unplayed"); notRecorded(w, face) end end
    end
    local function play(seat, face)
      for i = 1, 24 do if st.deck[i] == face then ok(ES.apply(st, seat, { k = "play", i = i, c = face }), face) end end
      played[face] = true
      see()
    end
    see()
    play(1, "AD"); play(2, "JC")                                           -- trick 1: Иван
    ok(ES.apply(st, 1, { k = "marry", i = 1, c = "KH", j = 2, d = "QH" })); played.KH = true; see() -- 40 in trumps
    play(2, "QC")                                                          -- trick 2: Иван
    ok(ES.apply(st, 1, { k = "close" })); see()
    play(1, "QH"); play(2, "AS")                                           -- trick 3: Иван, 74 points
    eq(st.phase, "hand")
    eq(H.lastError, nil)
    eq(v.history:IsShown(), true)
    local panel = v.history
    eq(lines(panel)[1], plain(L("table.historyHand", 1)))
    ok(lineWith(panel, L("santase.trump", w.ns.Cards.suitName("H"))), "no trump line")
    local t1 = lineWith(panel, "1.", "Иван " .. card("AD"), "Бот " .. card("JC"), L("table.historyWon", "Иван"))
    local marry = lineWith(panel, L("santase.historyMarry", "Иван", 40))
    local t2 = lineWith(panel, "2.", "Иван " .. card("KH"), "Бот " .. card("QC"), L("table.historyWon", "Иван"))
    local closed = lineWith(panel, L("santase.historyClose", "Иван"))
    local t3 = lineWith(panel, "3.", "Иван " .. card("QH"), "Бот " .. card("AS"), L("table.historyWon", "Иван"))
    local res = lineWith(panel, L("santase.hand.won", "Иван", 3))
    ok(t1 and marry and t2 and closed and t3 and res, table.concat(lines(panel), " / "))
    local ls, at = lines(panel), {}
    for i, text in ipairs(ls) do at[text] = at[text] or i end
    ok(at[t1] < at[marry] and at[marry] < at[t2] and at[t2] < at[closed] and at[closed] < at[t3] and at[t3] < at[res], "order")
    -- the match ends (the bot leaves): every face is in the view now, still none in the history
    ES.leave(st, 2); see()
    eq(st.phase, "match")
    for _, face in ipairs(DM) do if not played[face] then neverShown(w, face, "after the match"); notRecorded(w, face) end end
    eq(#w.sent, sent)
  end))

  it("the button only at Белот, Сантасе and Холдем tables; standing up drops the table's history", function()
    local w, v = santaseWithBot()
    local H = w.ns.HandHistory
    ok(next(H.tables) ~= nil, "the dealt hand is not recorded")
    ok(v.historyButton:IsVisible(), "no button")
    w:click(v.historyButton); ok(v.history:IsVisible(), "panel not shown")
    w:click(v.historyButton); eq(v.history:IsVisible(), false)
    w:click(v.historyButton)
    w:click(v.standButton)
    w:advance(0)
    eq(w.ns.client.session, nil); eq(next(H.tables), nil)
    w.ns.client:openTable{ game = "ttt", access = "guild", turn = 45 }
    w:advance(0)
    eq({ v.historyButton:IsShown(), v.history:IsShown() }, { false, false })
  end)
end)

---------------------------------------------------------------------------
-- Холдем
---------------------------------------------------------------------------

-- Seats 1-3 dealt from E.DECK as it is: seat 2 holds 2C 5C, seat 3 3C 6C, seat 1 4C 7C; the board
-- 9C TC JC, KC, 2D. Button seat 1, small blind seat 2 (5), big blind seat 3 (10).
local function hand3()
  local st = EH.new{ seats = { true, true, true } }
  ok(EH.apply(st, 0, { k = "hand" }))
  return st
end
local function hsess(st, seat, stake)
  return { game = "holdem", status = "live", mySeat = seat, role = seat == 1 and "host" or "player",
    seats = { A, B, C, false, false, false }, state = FULL and EH.snapshot(st) or EH.view(st, seat or 0), tid = "t#1", epoch = 1, seq = 1,
    stake = stake, engine = function() return EH end, gameNo = 1 }
end

-- The hand above: seat 1 raises to 30, seat 2 folds, seat 3 calls; flop: check, seat 1 bets 40, call;
-- turn and river checked; seat 1's flush beats seat 3's. Observed as `seat` after every event, then each(st).
local function playHand(H, seat, stake, each)
  local st = hand3()
  local function see() H.observe(hsess(st, seat, stake)); if each then each(st) end end
  see()
  ok(EH.apply(st, 0, { k = "deal", deck = EH.DECK })); see()
  local function act(a) HH.apply(st, st.turn, a); see() end
  local function sys() HH.apply(st, 0, (EH.system(st))); see() end
  act({ k = "raise", to = 30 }); act({ k = "fold" }); act({ k = "call" })
  sys(); act({ k = "check" }); act({ k = "bet", to = 40 }); act({ k = "call" })
  sys(); act({ k = "check" }); act({ k = "check" })
  sys(); act({ k = "check" }); act({ k = "check" })
  sys()
  eq(st.phase, "done")
  return st
end

-- The faces of the full state st the whole table has seen (the board, the hands shown at the
-- showdown) and `seat`'s own two.
local function public(st, seat)
  local pub = {}
  for _, i in ipairs(st.board) do pub[st.deck[i]] = true end
  local last = st.last and st.last.hand == st.hand and st.last
  local function hole(q) for _, i in ipairs(st.p[q] and st.p[q].cards or {}) do pub[st.deck[i]] = true end end
  for _, q in ipairs(last and last.shown or {}) do hole(q) end
  if seat then hole(seat) end
  return pub
end
-- After every event: no other face of the deck on screen or in memory.
local function onlyPublic(w, panel, seat)
  return function(st)
    w.ns.HandHistory.draw(panel, hsess(st, seat))
    local pub = public(st, seat)
    for _, face in ipairs(EH.DECK) do
      if not pub[face] then neverShown(w, face, "not public"); notRecorded(w, face) end
    end
  end
end

describe("ui: hand history — Холдем", function()
  it("blinds, actions per street with amounts, the board, the shown hands, the winner and pot", bothWays(function()
    local w, panel = setup(240, 400)
    local H, L, card = w.ns.HandHistory, w.ns.L, w.ns.HandHistory.card
    local sent = #w.sent
    local st = playHand(H, 1, nil, onlyPublic(w, panel, 1))
    H.draw(panel, hsess(st, 1))
    local ls = lines(panel)
    eq(ls[1], plain(L("table.historyHand", 1)) .. " · " .. plain(L("holdem.historyBlinds", "5", "10")))
    local want = {
      plain(L("holdem.historyMine", card("4C") .. " " .. card("7C"))),
      plain(L("holdem.historyPreflop")),
      "Мария: " .. plain(L("holdem.hist.sb", "5")),
      "Kiro: " .. plain(L("holdem.hist.bb", "10")),
      "Иван: " .. plain(L("holdem.hist.raise", "30")),
      "Мария: " .. plain(L("holdem.hist.fold")),
      "Kiro: " .. plain(L("holdem.hist.call", "20")),
      plain(L("holdem.historyFlop", card("9C") .. " " .. card("TC") .. " " .. card("JC"))),
      "Kiro: " .. plain(L("holdem.hist.check")),
      "Иван: " .. plain(L("holdem.hist.bet", "40")),
      "Kiro: " .. plain(L("holdem.hist.call", "40")),
      plain(L("holdem.historyTurn", card("KC"))),
      "Kiro: " .. plain(L("holdem.hist.check")),
      "Иван: " .. plain(L("holdem.hist.check")),
      plain(L("holdem.historyRiver", card("2D"))),
      "Kiro: " .. plain(L("holdem.hist.check")),
      "Иван: " .. plain(L("holdem.hist.check")),
      plain(L("holdem.historyShow", "Kiro", card("3C") .. " " .. card("6C"), L("holdem.cat.6"))),
      plain(L("holdem.historyShow", "Иван", card("4C") .. " " .. card("7C"), L("holdem.cat.6"))),
      plain(L("holdem.historyWon", "Иван", "145")),
    }
    local got = {}
    for i = 2, #ls do got[#got + 1] = ls[i] end
    -- the shown hands in showdown order: the river was checked, so the first live seat left of the button (Kiro)
    eq(got, want)
    -- the folded seat's cards are nowhere, neither on screen nor in memory
    neverShown(w, "2C", "folded"); neverShown(w, "5C", "folded"); notRecorded(w, "2C"); notRecorded(w, "5C")
    eq(#w.sent, sent)
  end))

  it("a watcher and the folder: only shown cards, mine only to me; a fold-win shows no card", bothWays(function()
    local w, panel = setup(240, 400)
    local H, L, card = w.ns.HandHistory, w.ns.L, w.ns.HandHistory.card
    local st = playHand(H, nil, nil, onlyPublic(w, panel, nil))
    H.draw(panel, hsess(st, nil))
    ok(not lineWith(panel, plain(L("holdem.historyMine", ""))), "a watcher has no cards of his own")
    neverShown(w, "2C"); neverShown(w, "5C"); notRecorded(w, "2C"); notRecorded(w, "5C")
    ok(lineWith(panel, card("4C") .. " " .. card("7C")) and lineWith(panel, card("3C") .. " " .. card("6C")), "the shown hands")
    -- seat 2 folded: its own cards are its own, marked as mine
    local w2, panel2 = setup(240, 400)
    local H2 = w2.ns.HandHistory
    local st2 = playHand(H2, 2, nil, onlyPublic(w2, panel2, 2))
    H2.draw(panel2, hsess(st2, 2))
    ok(lineWith(panel2, plain(L("holdem.historyMine", card("2C") .. " " .. card("5C")))), "my folded cards, mine")
    -- everybody folds to the big blind: nobody shows; it wins the called 10 (its uncalled 5 goes back)
    local w3, panel3 = setup(240, 400)
    local H3 = w3.ns.HandHistory
    local s3 = hand3()
    H3.observe(hsess(s3, 3))
    ok(EH.apply(s3, 0, { k = "deal", deck = EH.DECK })); H3.observe(hsess(s3, 3))
    HH.apply(s3, s3.turn, { k = "fold" }); H3.observe(hsess(s3, 3))
    HH.apply(s3, s3.turn, { k = "fold" }); H3.observe(hsess(s3, 3))
    eq(s3.phase, "done")
    H3.draw(panel3, hsess(s3, 3))
    ok(lineWith(panel3, plain(L("holdem.historyWonFold", "Kiro", "10"))), table.concat(lines(panel3), " / "))
    for _, face in ipairs({ "2C", "5C", "4C", "7C" }) do neverShown(w3, face); notRecorded(w3, face) end
    ok(lineWith(panel3, plain(L("holdem.historyMine", card("3C") .. " " .. card("6C")))), "my own cards")
  end))

  it("coins at a cash table, chips at a fun one (the table's own amounts)", function()
    local w, panel = setup(240, 400)
    local H, L = w.ns.HandHistory, w.ns.L
    local coins = w.ns.HoldemCashView.coins
    local st = playHand(H, 1, 1000)
    H.draw(panel, hsess(st, 1, 1000))
    ok(lineWith(panel, "Иван: " .. L("holdem.hist.raise", coins(30))), table.concat(lines(panel), " / "))
    ok(lineWith(panel, L("holdem.historyWon", "Иван", coins(145))), "the pot in coins")
    ok(coins(30) ~= "30", "a coin amount")
    local w2, panel2 = setup(240, 400)
    local st2 = playHand(w2.ns.HandHistory, 1)
    w2.ns.HandHistory.draw(panel2, hsess(st2, 1))
    ok(lineWith(panel2, "Иван: " .. L("holdem.hist.raise", "30")), "chips")
    ok(not table.concat(lines(panel2), " "):find(plain(coins(30)), 1, true), "no coins at a fun table")
  end)

  it("leaving the table drops its history; another table starts empty", function()
    local w, panel = setup(240, 400)
    local H = w.ns.HandHistory
    playHand(H, 1)
    ok(H.tables["t#1"], "recorded")
    H.observe(nil)
    eq(next(H.tables), nil)
    playHand(H, 1)
    local s = hsess(hand3(), 1); s.tid = "t#2"
    H.observe(s)
    eq({ H.tables["t#1"], H.tables["t#2"] ~= nil }, { nil, true })
    H.draw(panel, s)
    ok(lineWith(panel, w.ns.L("table.historyHand", 1)), "the new table's hand")
    eq(#H.tables["t#2"].hands, 1)
  end)
end)
