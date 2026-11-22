local Wow = require("wow")

local A, B, C, D = "Иван Петров", "Мария Стоянова", "Kiro Barley", "Пешо Тодоров"
local BOTS = { "Бот Иванов", "Bot Barleybrew", "Бот Петрова" }

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

local E = guildWow().ns.Engines.belot -- the engine's code, for states built by hand

local current -- the view of the running test's sandbox, for draw()

-- The view's frame over a 532 x 328 parent; every click is recorded in `acts`.
local function setup()
  local w = guildWow()
  local parent = w.G.CreateFrame("Frame", nil, w.G.UIParent)
  parent:SetSize(532, 328)
  local View = w.ns.TableFrame.views.belot
  assert(View, "no view registered for belot")
  local f = View.build(parent)
  current = View
  local acts = {}
  w.ns.client.act = function(_, a) acts[#acts + 1] = a; return true end
  return w, View, f, acts
end

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
local function plays(s, str)
  for face in str:gmatch("%S+") do
    local okay, why = E.apply(s, s.turn, { k = "play", i = idx(s, face), c = face })
    ok(okay, "play " .. face .. " rejected: " .. tostring(why))
  end
end
local function started(deck, bidStr, first)
  local s = E.new { first = first }
  ok(E.apply(s, 0, { k = "deal", deck = deck })); bids(s, bidStr)
  return s
end

local DECK_A = deckOf(
  "AH KH 7H 8C JS 9S 7D 8D",
  "TH QH 9H 7C QS KS AD TD",
  "JH 8H 9C TC 7S 8S JD QD",
  "AC KC QC JC AS TS KD 9D")
-- Seat 1 holds the кварта AC KC QC JC (AC is deck index 1).
local DECK_Q = deckOf(
  "AC KC QC JC AS TS KD 9D",
  "AH KH 7H 8C JS 9S 7D 8D",
  "TH QH 9H 7C QS KS AD TD",
  "JH 8H 9C TC 7S 8S JD QD")

-- A session at seat `seat` (nil: a watcher) over `state` (a view).
local function sess(state, seat)
  return { game = "belot", status = "live", mySeat = seat, seats = { A, B, C, D }, state = state,
    tid = "t#1", epoch = 1, seq = 1, role = seat and "player" or "watcher" }
end
local function draw(f, st, q) current.update(f, sess(E.view(st, q), q)) end

-- The sorted list of bids whose button is visible.
local function shown(f)
  local out = {}
  for b, button in pairs(f.bidButtons) do
    if button:IsVisible() then out[#out + 1] = b end
  end
  table.sort(out)
  return out
end

-- `text` without inline colour codes (|cAARRGGBB … |r).
local function plain(text) return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

-- Visible font strings whose text, colour codes stripped, contains the plain `needle`.
local function plainTexts(w, needle)
  local out = {}
  for _, f in ipairs(w.frames) do
    for _, r in ipairs(f.regions) do
      if r.objectType == "FontString" and r.text and r:IsVisible() and plain(r.text):find(needle, 1, true) then
        out[#out + 1] = r
      end
    end
  end
  return out
end

-- The state of the summary tests: a view at seat 1 after a scored deal (Task 7's summary test).
local function scored()
  local st = E.view(started(DECK_A, "S P P P"), 1); st.phase, st.score, st.hang = "deal", { 32, 0 }, 0
  st.res = { round = 1, contract = { seat = 2, b = "H", x = 2 }, raw = { 102, 60 }, pts = { 32, 0 }, hang = 0, valat = false,
    ann = { { s = 1, t = "s3", i = 9, v = 20, on = true }, { s = 2, t = "s3", i = 10, v = 20, on = false }, { s = 4, t = "b", i = 20, v = 20, on = true } } }
  return st
end

describe("ui: Белот view", function()
  local boot = setup

  it("the auction shows only the legal bids; a click bids; the others' bids are bubbles", function()
    local w, View, f, acts = boot(); local st = E.new {}; ok(E.apply(st, 0, { k = "deal", deck = DECK_A })); draw(f, st, 1)
    eq(shown(f), { "A", "C", "D", "H", "N", "P", "S" }); eq(f.text:GetText(), "Кажи игра или пас"); eq(#f.myFan.cards, 5)
    eq(f.bidButtons.C.points[1], { "TOPLEFT", f, "TOPLEFT", 180, -60 }); eq(f.bidButtons.R.points[1], { "TOPLEFT", f, "TOPLEFT", 268, -116 })
    w:click(f.bidButtons.H); eq(acts, { { k = "bid", b = "H" } })
    ok(E.apply(st, 1, { k = "bid", b = "H" })); ok(E.apply(st, 2, { k = "bid", b = "X" })); draw(f, st, 3)
    eq(shown(f), { "A", "N", "P", "R", "S" }); eq(f.bidButtons.P.text:GetText(), "Пас"); eq(f.bidButtons.R.text:GetText(), "Реконтра")
    eq({ f.bubbles[2].text:GetText(), f.bubbles[3].text:GetText() }, { "Купа", "Контра" })       -- seat 1 is my partner on top, seat 2 on my left
    eq({ f.bubbles[0]:IsVisible(), f.bubbles[1]:IsVisible() }, { false, false })
    draw(f, st, 1); eq(shown(f), {}); eq(#w:texts("Изчакай "), 1)
  end)

  it("„Обяви“ sends the engine's set and shows no bubble until the table recorded it", function()
    local w, View, f, acts = boot(); local st = started(DECK_Q, "S P P P"); draw(f, st, 1)
    ok(f.announceButton:IsVisible()); eq(f.announceButton.text:GetText(), "Обяви: Кварта"); eq(f.bubbles[0]:IsVisible(), false)
    w:click(f.announceButton); eq(acts, { { k = "ann", a = { { t = "s4", i = 1 } } } }); eq(f.bubbles[0]:IsVisible(), false)
    ok(E.apply(st, 1, acts[1])); draw(f, st, 1); eq(f.announceButton:IsVisible(), false); eq(f.bubbles[0].text:GetText(), "Кварта")
    draw(f, st, 3); eq(f.bubbles[2].text:GetText(), "Кварта"); eq(f.announceButton:IsVisible(), false)
  end)

  it("cards I may not play are dimmed; a click plays, with the belote when it is one", function()
    local w, View, f, acts = boot(); local st = started(DECK_A, "S P P P"); plays(st, "AH"); draw(f, st, 2)
    eq({ f.myFan.cards[1].mode, f.myFan.cards[4].mode, f.myFan.cards[4].face, f.myFan.cards[4].y }, { "dim", "raised", "TH", 8 })
    w:click(f.myFan.cards[1].frame); eq(acts, {}); w:click(f.myFan.cards[4].frame); eq(acts, { { k = "play", i = 2, c = "TH" } })
    plays(st, "9H 8H TS AC 8C 7C 9C KC 9S"); draw(f, st, 2); eq(f.myFan.cards[6].face, "QS")
    w:click(f.myFan.cards[6].frame); eq(acts[2], { k = "play", i = 18, c = "QS", b = true })
  end)

  it("the trick lies in a cross by seat; „Последна взятка“ shows the last one until the table moves", function()
    local w, View, f = boot(); local st = started(DECK_A, "S P P P")
    draw(f, st, 1); eq(f.peekButton:IsVisible(), false)                                         -- the first trick: nothing to peek at
    plays(st, "AH 9H"); draw(f, st, 3); eq(f.peekButton:IsVisible(), false)
    plays(st, "8H TS AC 8C"); draw(f, st, 1)
    eq({ f.trick[3].face, f.trick[0].face }, { "AC", "8C" }); eq({ f.trick[1].frame:IsVisible(), f.trick[2].frame:IsVisible() }, { false, false })
    eq(f.trick[2].frame.points[1], { "TOPLEFT", f, "TOPLEFT", 246, -56 }); eq(f.trick[1].frame.points[1], { "TOPLEFT", f, "TOPLEFT", 292, -89 })
    eq(f.trick[0].frame.points[1], { "TOPLEFT", f, "TOPLEFT", 246, -122 }); eq(f.trick[3].frame.points[1], { "TOPLEFT", f, "TOPLEFT", 200, -89 })
    eq(f.peekButton.text:GetText(), "Последна взятка"); eq(f.trick[0].mode, "plain")
    w:click(f.peekButton); eq({ f.trick[0].face, f.trick[1].face, f.trick[2].face, f.trick[3].face }, { "AH", "9H", "8H", "TS" }); eq(f.trick[0].mode, "dim")
    eq(f.peekButton.lit, true)
    local s = sess(E.view(st, 1), 1); s.seq = 2; View.update(f, s); eq(f.trick[3].face, "AC")       -- an event closes the peek
    eq({ f.trick[0].mode, f.peekButton.lit, f.trick[1].frame:IsVisible() }, { "plain", false, false })
    local st2 = E.new {}; ok(E.apply(st2, 0, { k = "deal", deck = DECK_A })); draw(f, st2, 1); eq(f.peekButton:IsVisible(), false)  -- the auction
  end)

  it("the score, the contract and the deal's summary: вътре, контра, an announce that did not count", function()
    local w, View, f = boot(); local st = scored(); View.update(f, sess(st, 1))
    eq(#plainTexts(w, "Ние 32 · Вие 0"), 1); eq(#plainTexts(w, "до 151"), 1)
    ok(f.summary:IsVisible())
    eq(plain(f.summary:GetText()), table.concat({ "Игра: Купа, контра  каза Мария Стоянова", "Ние +32 · Вие +0", "Вътре са!",
      "Иван Петров: Терца, 20", "Мария Стоянова: Терца (не се брои)", "Пешо Тодоров: Белот, 20" }, "\n"))
    for k = 0, 3 do eq(f.trick[k].frame:IsVisible(), false) end
    eq(f.summary:GetWidth(), 170); eq(select(2, f.summary:GetFont()), 11)
    eq(f.summary.points[1], { "TOP", f, "TOPLEFT", 266, -64 })
    st.hang = 9; View.update(f, sess(st, 1)); eq(#plainTexts(w, "до 151 · висят 9"), 1)

    local mid = started(DECK_A, "S P P P"); local ms = sess(E.view(mid, 1), 1); View.update(f, ms)
    ok(f.contract:IsVisible()); eq(plain(f.contract:GetText()), "Игра: Пика\nказа Иван Петров")
    eq(f.summary:IsVisible(), false)
    eq(View.seatNote(ms, 4), "разд."); eq(View.seatNote(ms, 1), "")
    local over = sess(scored(), 1); over.state.phase = "match"
    for seat = 1, 4 do eq(View.seatNote(over, seat), "") end

    -- a leaver: the seat is empty by the end of the match, the view still names him
    local w2, View2, f2 = boot(); local st2 = scored(); View2.update(f2, sess(st2, 1))
    st2.phase, st2.winner, st2.left = "match", 2, 3
    local s2 = sess(st2, 1); s2.seats[3] = false; View2.update(f2, s2)
    eq(plain(f2.text:GetText()), "Kiro Barley стана от масата. Отборът му губи.")
  end)

  it("the end line of the match hides under the bill of a staked match (StakePanels.shown); nothing else does", function()
    local w, View, f = boot(); local P = w.ns.StakePanels
    local mid = E.view(started(DECK_A, "S P P P"), 1)
    P.shown = true; View.update(f, sess(mid, 1))
    eq({ f.text:IsVisible(), f.text:GetText() }, { true, "Твой ход" }) -- a running match keeps its line
    local st = scored()
    st.phase, st.winner = "match", 1
    P.shown = false; View.update(f, sess(st, 1))
    eq({ f.text:IsVisible(), f.text:GetText() }, { true, "Печелим партията!" })
    P.shown = true; View.update(f, sess(st, 1))
    eq(f.text:IsVisible(), false)
    P.shown = false; View.update(f, sess(st, 1))
    eq({ f.text:IsVisible(), f.text:GetText() }, { true, "Печелим партията!" })
  end)

  it("a deal everybody passed says so once", function()
    local w, View, f = boot(); local st = scored()
    st.res = { round = 1, raw = { 0, 0 }, pts = { 0, 0 }, hang = 0, valat = false, ann = {} }; View.update(f, sess(st, 1))
    eq(#plainTexts(w, "Всички казаха пас. Раздава се отново."), 1); eq(f.summary:IsVisible(), false)
    eq(f.text:GetText(), "Всички казаха пас. Раздава се отново.")
  end)

  it("the suit bids are their suit on the gold face: red for hearts and diamonds, the dark label colour for clubs and spades", function()
    local w, View, f = boot(); local T = w.ns.Theme
    local function rgba(token) return { T.color[token][1], T.color[token][2], T.color[token][3], 1 } end
    for b, token in pairs({ C = "woodDark", D = "red", H = "red", S = "woodDark" }) do
      local icon = f.bidButtons[b].suit
      eq(icon.vertex, rgba(token), b); eq(icon.texture, T.tex.suits, b); eq({ icon:GetSize() }, { 16, 16 }, b)
      eq(icon.texCoord, { w.ns.Cards.COORD[b][1], w.ns.Cards.COORD[b][2], 0, 1 }, b)
      eq({ f.bidButtons[b].text:GetTextColor() }, rgba("woodDark"), b)
    end
  end)

  it("a watcher sees backs, no button and the teams by place", function()
    local w, View, f = boot(); local st = E.view(started(DECK_A, "S P P P"), 0); View.update(f, sess(st, nil))
    eq(#f.myFan.cards, 8); for k = 1, 8 do eq(f.myFan.cards[k].face, nil) end
    eq(shown(f), {}); eq(f.announceButton:IsVisible(), false)
    eq(#plainTexts(w, "Долу и горе 0 · Ляво и дясно 0"), 1)
  end)

  it("solo with three bots from a real deal: my five cards face up, my bid stands, three more cards come", function()
    local w = guildWow(); w:slash("bots"); w:advance(0); w:advance(0)
    local client, T = w.ns.client, w.ns.TableFrame
    client:openTable{ game = "belot", access = "invite", turn = 45 }; w:advance(0)
    local v = T.view
    for _, bot in ipairs(BOTS) do
      w:click(v.inviteButton)
      local row
      for _, r in ipairs(v.picker.rows) do
        if r.frame:IsVisible() and r.name:GetText() == bot then row = r end
      end
      assert(row, "no row for " .. bot .. " in the picker")
      w:click(row.frame); w:advance(2)
    end
    w:advance(2)
    local V, s = T.built.belot, client.session
    eq(#s.state.hands[1], 5); for k = 1, 5 do ok(V.myFan.cards[k].face, "no face on card " .. k) end
    eq(v.plates[3].frame.points[1], { "TOPLEFT", v.area, "TOPLEFT", 183.5, -10 })
    w:click(V.bidButtons.S); w:advance(8)
    eq(s.state.phase, "play"); eq(s.state.contract, { seat = 1, b = "S", x = 1 })
    for k = 1, 8 do ok(V.myFan.cards[k].frame:IsVisible() and V.myFan.cards[k].face, "no face on card " .. k) end
    local T_ = w.ns.Theme
    ok(not v.fairLine:IsVisible() or (function() local r, g, b = v.fairLine.text:GetTextColor(); return r == T_.color.inkDim[1] and g == T_.color.inkDim[2] and b == T_.color.inkDim[3] end)(),
      "the fairness line has a verdict already")
    eq(v.info.topic, "belot")
  end)

  it("„Стани“ in a running match asks first: „Отборът ви губи мача“; „Остани“ keeps the seat, „Стани“ there stands", function()
    local w = guildWow(); w:slash("bots"); w:advance(0); w:advance(0)
    local client, T = w.ns.client, w.ns.TableFrame
    client:openTable{ game = "belot", access = "invite", turn = 45 }; w:advance(0)
    local v = T.view
    eq(v.confirm:IsVisible(), false); eq(T.standCosts(client.session), false)                 -- alone at the table: nothing to lose
    for _, bot in ipairs(BOTS) do
      w:click(v.inviteButton)
      for _, r in ipairs(v.picker.rows) do
        if r.frame:IsVisible() and r.name:GetText() == bot then w:click(r.frame) end
      end
      w:advance(2)
    end
    w:advance(2)
    local s = client.session; eq({ s.status, s:seatedCount(), T.standCosts(s) }, { "live", 4, true })
    local results = 0; client:on("result", function() results = results + 1 end)
    w:click(v.standButton); w:advance(0)
    eq(client.session, s); eq(results, 0); ok(v.confirm:IsVisible(), "no question")
    ok(v.confirm.text:GetText():find("Отборът ви губи мача", 1, true), v.confirm.text:GetText())
    eq({ v.confirm.yes.text:GetText(), v.confirm.no.text:GetText() }, { "Стани", "Остани" })
    eq(v.confirm.points[1], { "BOTTOMLEFT", v.standButton, "TOPLEFT", 0, 6 })
    w:click(v.confirm.no); w:advance(0)
    eq(client.session, s); eq(v.confirm:IsVisible(), false); eq(results, 0)
    w:click(v.standButton); w:advance(0); ok(v.confirm:IsVisible(), "no question the second time")
    w:click(v.confirm.yes); w:advance(1)
    eq(client.session, nil); eq(v.confirm:IsVisible(), false)
    -- a watcher, a table that is not live and a game without teams stand at once
    eq(T.standCosts(nil), false)
    eq(T.standCosts({ status = "live", mySeat = nil, engine = function() return E end, gameOver = function() return false end }), false)
    eq(T.standCosts({ status = "aborted", mySeat = 1, engine = function() return E end, gameOver = function() return false end }), false)
    eq(T.standCosts({ status = "live", mySeat = 1, engine = function() return E end, gameOver = function() return true end }), false)
    eq(T.standCosts({ status = "live", mySeat = 1, engine = function() return w.ns.Engines.santase end, gameOver = function() return false end }), false)
    eq(T.standCosts({ status = "live", mySeat = 1, engine = function() return E end, gameOver = function() return false end }), true)
    for _, lang in ipairs{ "bg", "en" } do
      for _, key in ipairs{ "table.standWarn", "table.standYes", "table.standNo" } do ok(w.ns.Locale.tables[lang][key], lang .. ": " .. key) end
    end
  end)
end)
