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

  it("a passed-out deal says so; a deal voided in the auction does not", function()
    local w, panel = setup()
    local H, L = w.ns.HandHistory, w.ns.L
    local st = EB.new{ first = 1 }
    ok(EB.apply(st, 0, { k = "deal", deck = DECK_A })); H.observe(bsess(st, 1))
    ok(EB.apply(st, st.turn, { k = "bid", b = "P" })); H.observe(bsess(st, 1))
    ok(EB.apply(st, 0, { k = "void" })); H.observe(bsess(st, 1))
    H.draw(panel, bsess(st, 1))
    eq(lineWith(panel, L("belot.passed")), nil)
    ok(EB.apply(st, 0, { k = "deal", deck = DECK_A })); H.observe(bsess(st, 1))
    for _ = 1, 4 do ok(EB.apply(st, st.turn, { k = "bid", b = "P" })); H.observe(bsess(st, 1)) end
    eq(st.phase, "deal")
    H.draw(panel, bsess(st, 1))
    local ls = lines(panel)
    -- newest first: the passed-out deal (#1 again: a void keeps the round), then the voided one
    eq({ ls[1], ls[2], ls[3], ls[4] }, { plain(L("table.historyHand", 1)), plain(L("belot.passed")), " ", plain(L("table.historyHand", 1)) })
    eq(#H.tables["t#1"].hands, 2)
  end)

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
    local tid = w.ns.client.session.tid
    w:click(v.standButton)
    w:advance(0)
    eq(w.ns.client.session, nil); eq(next(H.tables), nil)
    eq(v.history:IsShown(), false) -- closed with the table, not left open for the next one
    w.ns.client:openTable{ game = "santase", access = "guild", turn = 45 }
    w:advance(0)
    ok(w.ns.client.session.tid ~= tid, "another table")
    eq({ v.historyButton:IsShown(), v.history:IsShown() }, { true, false })
    w:click(v.historyButton); eq(v.history:IsShown(), true)
    -- another table while it is open (a snapshot of a new tid): closed again
    w.ns.client.session.tid = "t#other"; w.ns.TableFrame.render()
    eq(v.history:IsShown(), false)
    w:click(v.standButton); w:advance(0)
    w.ns.client:openTable{ game = "ttt", access = "guild", turn = 45 }
    w:advance(0)
    eq({ v.historyButton:IsShown(), v.history:IsShown() }, { false, false })
  end)
end)

---------------------------------------------------------------------------
-- The panel beside the table, never over it
---------------------------------------------------------------------------

-- The rect {l, b, r, t} of region r, from its anchors (the fake has no layout engine):
-- UIParent is 1920 x 1080 at the origin; a font string without a width is as wide as its text.
local POS = { TOPLEFT = { 0, 1 }, TOP = { 0.5, 1 }, TOPRIGHT = { 1, 1 }, LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 },
  RIGHT = { 1, 0.5 }, BOTTOMLEFT = { 0, 0 }, BOTTOM = { 0.5, 0 }, BOTTOMRIGHT = { 1, 0 } }
local function rectOf(w, r)
  if r == w.G.UIParent then return { 0, 0, 1920, 1080 } end
  local pts = r.points or {}
  if #pts == 0 then return nil end
  if pts[1][1] == "ALL" then return rectOf(w, pts[1][2] or r.parent) end
  local width, height = r.width, r.height
  if r.objectType == "FontString" then
    width = (r.fixedWidth and r.fixedWidth > 0) and math.min(r.fixedWidth, r:GetUnboundedStringWidth()) or r:GetUnboundedStringWidth()
    height = r:GetStringHeight()
  end
  local hx, vy = {}, {}
  for _, a in ipairs(pts) do
    local point, rel, relPoint, x, y = a[1], a[2], a[3], a[4], a[5]
    if type(rel) == "number" or rel == nil then rel, relPoint, x, y = r.parent, point, rel, relPoint end
    if type(relPoint) == "number" then relPoint, x, y = point, relPoint, x end
    local rr = rectOf(w, rel or r.parent)
    if not rr then return nil end
    local rp, sp = POS[relPoint or point], POS[point]
    local px = rr[1] + rp[1] * (rr[3] - rr[1]) + (x or 0)
    local py = rr[2] + rp[2] * (rr[4] - rr[2]) + (y or 0)
    hx[#hx + 1] = { sp[1], px }; vy[#vy + 1] = { sp[2], py }
  end
  local function solve(list, size)
    for _, a in ipairs(list) do
      for _, b in ipairs(list) do
        if a[1] < b[1] then local span = (b[2] - a[2]) / (b[1] - a[1]); local lo = a[2] - a[1] * span; return lo, lo + span end
      end
    end
    local lo = list[1][2] - list[1][1] * (size or 0)
    return lo, lo + (size or 0)
  end
  local l, rgt = solve(hx, width)
  local b, t = solve(vy, height)
  return { l, b, rgt, t }
end
local function overlap(a, b) return a[1] < b[3] and b[1] < a[3] and a[2] < b[4] and b[2] < a[4] end

-- Every shown frame under `root` (itself included), deep.
local function framesUnder(root)
  local out = {}
  local function walk(f) if f:IsShown() then out[#out + 1] = f; for _, c in ipairs(f.children or {}) do walk(c) end end end
  walk(root)
  return out
end

describe("ui: hand history — the panel beside the table", function()
  for _, game in ipairs({ "holdem", "santase", "belot" }) do
    it(game .. ": the open panel lies outside the table window; no play control under it", function()
      local w = guildWow()
      w.ns.client:openTable{ game = game, access = "guild", turn = 45 }
      w:advance(0)
      local TF = w.ns.TableFrame
      local v = TF.view
      -- a game under way with me on turn, so the board shows its play controls
      local s = w.ns.client.session
      local st
      if game == "holdem" then
        s.seats = { A, B, C, false, false, false }; st = EH.new{ seats = { true, true, true } }
        ok(EH.apply(st, 0, { k = "hand" })); ok(EH.apply(st, 0, { k = "deal", deck = EH.DECK }))
      elseif game == "santase" then
        s.seats = { A, BOT }; st = ES.new{ first = 1 }; ok(ES.apply(st, 0, { k = "deal", deck = DM }))
      else
        s.seats = { A, B, C, D }; st = EB.new{ first = 1 }; ok(EB.apply(st, 0, { k = "deal", deck = DECK_A }))
      end
      s.status, s.state = "live", w.ns.Engines[game].view(st, 1)
      TF.render()
      ok(v.historyButton:IsVisible(), "no button")
      w:click(v.historyButton)
      ok(v.history:IsVisible(), "not open")
      eq(v.history:GetParent(), TF.frame) -- a child of the window: it moves and scales with it
      local panel, win = rectOf(w, v.history), rectOf(w, TF.frame)
      ok(panel and win, "unresolved")
      eq({ panel[1], panel[2], panel[4] }, { win[3], win[2], win[4] }) -- beside it, as tall as it
      ok(not overlap(panel, win), "over the table window")
      -- every control of the board (the action buttons, the cash panel, the fan) and the bottom row
      local board, n = TF.built[game], 0
      ok(board, "no board")
      for _, x in ipairs(framesUnder(board)) do
        local r = rectOf(w, x)
        if r then n = n + 1; ok(not overlap(panel, r), game .. ": a control under the panel") end
      end
      for _, b in ipairs({ v.standButton, v.inviteButton, v.startButton, v.botsButton }) do
        local r = b and rectOf(w, b)
        if r then ok(not overlap(panel, r), "a bottom button under the panel") end
      end
      ok(n > 3, "board frames resolved: " .. n)
      local named = { holdem = { "foldButton", "callButton", "raiseButton", "allinButton", "plusButton" }, santase = { "marryButton", "closeButton" }, belot = {} }
      for _, key in ipairs(named[game]) do ok(board[key]:IsVisible() and rectOf(w, board[key]), key .. " not drawn") end
      ok(not overlap(panel, rectOf(w, v.area)), "over the felt")
    end)
  end

  it("at the screen's right edge the window opens on the table's left; back right once there is room", function()
    local w = guildWow()
    w.ns.client:openTable{ game = "santase", access = "guild", turn = 45 }
    w:advance(0)
    local TF = w.ns.TableFrame
    local v, f = TF.view, TF.frame
    -- the frame where the client has it (the fake has no layout: its left edge, in its own units)
    f.left = 1920 - f:GetWidth() - 10
    w:click(v.historyButton)
    eq(v.history.points, { { "TOPRIGHT", f, "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", f, "BOTTOMLEFT", 0, 0 } })
    -- scaled up (ui/Resize.lua) the same frame needs more room still: left; moved to the middle: right
    f.left = 600; f:SetScale(1.5); w.ns.TableFrame.render()
    eq(v.history.points[1], { "TOPRIGHT", f, "TOPLEFT", 0, 0 })
    f:SetScale(1); f:GetScript("OnDragStop")(f) -- a drag ends: placed again
    eq(v.history.points, { { "TOPLEFT", f, "TOPRIGHT", 0, 0 }, { "BOTTOMLEFT", f, "BOTTOMRIGHT", 0, 0 } })
    -- dragged by its title bar to the right edge: left again
    f.left = 1900 - f:GetWidth()
    v.title:GetParent():GetScript("OnDragStop")(v.title:GetParent())
    eq(v.history.points[1], { "TOPRIGHT", f, "TOPLEFT", 0, 0 })
  end)

  it("the title bar's options line stops before the watchers and „История“", function()
    local w = guildWow()
    w.ns.client:openTable{ game = "belot", access = "guild", turn = 45 }
    w:advance(0)
    local TF, H = w.ns.TableFrame, w.ns.HandHistory
    local v = TF.view
    v.meta:SetText(string.rep("Опция 99 · ", 30))
    v.stake:SetText("Залог: 5g"); v.stake:Show()
    v.watchers:SetText("Гледат: 3"); v.watchers:Show()
    H.render(v, w.ns.client.session)
    local meta, stake, button, watchers = rectOf(w, v.meta), rectOf(w, v.stake), rectOf(w, v.historyButton), rectOf(w, v.watchers)
    eq(v.meta.wordWrap, false)
    ok(meta[3] <= watchers[1] and stake[3] <= watchers[1] and watchers[3] <= button[1], "the title bar crowds: " ..
      table.concat({ meta[3], stake[3], watchers[1], watchers[3], button[1] }, " "))
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
local function hsess(st, seat, stake, seq, gameNo)
  return { game = "holdem", status = "live", mySeat = seat, role = seat == 1 and "host" or "player",
    seats = { A, B, C, false, false, false }, state = FULL and EH.snapshot(st) or EH.view(st, seat or 0), tid = "t#1", epoch = 1, seq = seq or 1,
    stake = stake, engine = function() return EH end, gameNo = gameNo or 1 }
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

  it("a snapshot mid-hand (my events jumped, gameNo moved on): one record, later actions where they belong", function()
    local w, panel = setup(240, 400)
    local H, L = w.ns.HandHistory, w.ns.L
    local st, q = hand3(), 1
    local function see(jump, gameNo) q = q + (jump or 1); H.observe(hsess(st, 1, nil, q, gameNo)) end
    see()
    ok(EH.apply(st, 0, { k = "deal", deck = EH.DECK })); see()
    HH.apply(st, st.turn, { k = "raise", to = 30 }); see()
    -- missed: the fold, the call, the flop, a check and Иван's bet of 40
    HH.apply(st, st.turn, { k = "fold" }); HH.apply(st, st.turn, { k = "call" })
    HH.apply(st, 0, (EH.system(st))); HH.apply(st, st.turn, { k = "check" }); HH.apply(st, st.turn, { k = "bet", to = 40 })
    see(6, 2) -- the snapshot: s.seq jumps, Member.adopt moves s.gameNo on
    HH.apply(st, st.turn, { k = "call" }); see(nil, 2)
    HH.apply(st, 0, (EH.system(st))); see(nil, 2)
    HH.apply(st, st.turn, { k = "check" }); see(nil, 2)
    eq(#H.tables["t#1"].hands, 1)
    H.draw(panel, hsess(st, 1))
    local got = {}
    for _, a in ipairs(H.tables["t#1"].hands[1].acts) do got[#got + 1] = table.concat({ a.street, a.seat, a.k, tostring(a.amt) }, " ") end
    eq(got, { "0 2 sb 5", "0 3 bb 10", "0 1 raise 30", "1 3 call 40", "2 3 check nil" })
    ok(lineWith(panel, "Kiro: " .. L("holdem.hist.call", "40")), "the call after the snapshot")
  end)

  it("a game that ends after its first hand: the next game's hand 1 is a record of its own", function()
    local w, panel = setup(240, 400)
    local H, L = w.ns.HandHistory, w.ns.L
    local st = playHand(H, 1) -- game 1: hand 1, then the game ends
    eq(#H.tables["t#1"].hands, 1)
    local st2 = EH.new{ seats = { true, true, true } } -- game 2 at the same table (no state.g)
    H.observe(hsess(st2, 1))
    ok(EH.apply(st2, 0, { k = "hand" })); H.observe(hsess(st2, 1))
    ok(EH.apply(st2, 0, { k = "deal", deck = EH.DECK })); H.observe(hsess(st2, 1))
    HH.apply(st2, st2.turn, { k = "fold" }); H.observe(hsess(st2, 1))
    local hands = H.tables["t#1"].hands
    eq(#hands, 2)
    eq({ hands[1].no, hands[2].no, #hands[1].acts, hands[1].done, hands[2].done }, { 1, 1, 12, true, nil })
    eq(hands[2].acts[3], { street = 0, seat = 1, k = "fold" })
    -- the same when the new game is first seen at its hand 1 (no idle state in between)
    local st3 = EH.new{ seats = { true, true, true } }
    ok(EH.apply(st3, 0, { k = "hand" })); ok(EH.apply(st3, 0, { k = "deal", deck = EH.DECK }))
    local w2 = setup(240, 400)
    local H2 = w2.ns.HandHistory
    playHand(H2, 1)
    -- a game 1 that reached hand 3, then game 2 at hand 1: the count went back
    H2.tables["t#1"].hands[1].no = 3; H2.tables["t#1"].hands[1].key = ":3"
    H2.observe(hsess(st3, 1))
    eq(#H2.tables["t#1"].hands, 2)
    H.draw(panel, hsess(st2, 1))
    eq(lines(panel)[1], plain(L("table.historyHand", 1)) .. " · " .. plain(L("holdem.historyBlinds", "5", "10")))
  end)

  it("a record begun mid-hand: a short blind posts what it had", function()
    local w, panel = setup(240, 400)
    local H, L = w.ns.HandHistory, w.ns.L
    local st = EH.new{ seats = { true, true, true } }
    st.seats[2].chips = 3
    ok(EH.apply(st, 0, { k = "hand" })); ok(EH.apply(st, 0, { k = "deal", deck = EH.DECK }))
    HH.apply(st, st.turn, { k = "raise", to = 30 })
    H.observe(hsess(st, 1)) -- the first state this client sees
    H.draw(panel, hsess(st, 1))
    ok(lineWith(panel, "Мария: " .. L("holdem.hist.sb", "3")), table.concat(lines(panel), " / "))
    ok(lineWith(panel, "Kiro: " .. L("holdem.hist.bb", "10")), "the big blind")
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
