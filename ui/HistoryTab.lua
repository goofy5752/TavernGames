local _, ns = ...

-- The tab „История“ (spec 5.6): every game and every payment my ledger knows, newest first
-- (core/LedgerHistory.lua), never stored. A game line reads „Морски шах: A победи B“ with a
-- mark for how far its word is backed: „потвърдено“ (a staked result its loser confirmed),
-- „чака потвърждение“, „оспорен“, „за удоволствие“ (a fun result: the host's word) or „само
-- твърдение“ (a staked result nobody backs); the tooltip says whose word a result is („по
-- думите на“), the game, the day and why a player left. A payment reads „A плати на B“ with
-- how it was paid; a denied entry keeps its text and is marked „отречено“. With a name (from
-- a row of „Класация“, HistoryTab.open) only that player's lines show, and the head lists
-- up to five opponents with the wins, the losses and the gold between them. The list is
-- virtual (ui/BookList.lua): a line gets its text when it first comes on screen. The page
-- redraws on "ledger", on the next frame and at most once per 2 s, only while shown (J3).
local Theme, W, L = ns.Theme, ns.W, ns.L
local Stats, money = ns.LedgerStats, ns.W.money

local HistoryTab = {
  view = nil,
  state = { name = nil },
  DARK = 0.55, -- class colours darkened for the cream paper, as in „Тефтер“
  GAP = 2,     -- seconds between two rebuilds from the ledger's events
  VERSUS = 5,  -- opponents in the head
}
ns.HistoryTab = HistoryTab

local BOOK_W, PAD, HEAD_H, ROW_H, ROWS, LINE_H = 760, 14, 108, 26, 16, 14
local ROW_W = BOOK_W - 20 - 2 * PAD - 6
local TEXT_W, MARK_W, AMOUNT_W, AGE_W = 400, 110, 110, 56 -- the amount fits the gold cap in coins
local RULE, AGE = { 0xd9 / 255, 0xc4 / 255, 0x9a / 255 }, { 0x7a / 255, 0x5a / 255, 0x3a / 255 }
local STATE = {
  fun = "history.mark.fun", claim = "history.mark.claim", confirmed = "history.mark.confirmed",
  pending = "ledger.pending", contested = "ledger.contested",
}
local HOW = { trade = "pay.trade", mail = "pay.mail", hand = "accounts.settle" }

---------------------------------------------------------------------------
-- The lines
---------------------------------------------------------------------------

-- A name in its class colour, darkened for the paper; plain without a known class.
local function name(client, who)
  if type(who) ~= "string" then return "?" end
  local p = who ~= client.env.me and client.presence:get(who)
  local cls = who == client.env.me and client.env.cls or p and p.cls
  local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
  if not (cls and colors and colors[cls]) then return who end
  local r, g, b = ns.classColor(cls)
  return W.paint(who, r * HistoryTab.DARK, g * HistoryTab.DARK, b * HistoryTab.DARK)
end

local function join(client, names)
  local out = {}
  for i, n in ipairs(names) do out[i] = name(client, n) end
  return table.concat(out, L("history.and"))
end

local function plainName(who) return type(who) == "string" and who or "?" end
local function joinPlain(names)
  local out = {}
  for i, n in ipairs(names) do out[i] = plainName(n) end
  return table.concat(out, L("history.and"))
end

local function date(client, t) return (client.env.date or ns.Pay.utc)(t) end
local function age(client, at, now) return ns.LedgerTab.age(client, at, now) end

-- „+5g“, „−3g 20s“ or „0“ (the board's).
local function signed(copper)
  if copper > 0 then return "+" .. money(copper) end
  if copper < 0 then return "−" .. money(-copper) end
  return "0"
end

-- The text of a game of entry e (an R, or a Холдем S when cash; counts: what counted for a cash S) and its
-- game name: who won, lost or left, written by name; names, win and lose are Stats.dress's.
local function gameText(client, e, cash, counts, why)
  local names, win, lose = Stats.dress({ e = e, cash = cash, counts = counts })
  local game = W.gameName(e.g)
  local winners, losers = {}, {}
  for _, n in ipairs(names) do
    if win[n] then winners[#winners + 1] = n elseif lose[n] then losers[#losers + 1] = n end
  end
  if cash then return L("history.sat", game, join(client, names)) end
  if why and #losers > 0 then return L("history.left", game, join(client, losers)) end
  if #winners > 0 and #losers > 0 then return L("history.won", game, join(client, winners), join(client, losers)) end
  return L("history.draw", game, join(client, names))
end

local function put(t, s) if s then t[#t + 1] = s end end
local function whyLine(why)
  return (why == "left" or why == "offline" or why == "idle") and L("history.why." .. why) or nil
end

-- Fills line l (made by bare) with its text, mark, amount, age and tooltip.
local function dress(client, l, now)
  if l.text then return l end
  local src = l.src
  local tip = {}
  if l.kind == "game" then
    local rec = src.rec
    l.text = gameText(client, rec.e, rec.cash, rec.counts, rec.why)
    l.mark = L(STATE[rec.state] or "history.mark.claim")
    l.amount = rec.sk and money(rec.sk) or ""
    put(tip, l.text)
    if rec.state == "fun" or rec.state == "claim" then put(tip, L("history.by", joinPlain(rec.by))) end
    put(tip, W.gameName(rec.g)); put(tip, whyLine(rec.why))
  elseif l.kind == "pay" then
    l.text = L("history.paid", name(client, src.f), name(client, src.t))
    l.mark, l.amount = L(HOW[src.how] or "accounts.settle"), money(src.c)
    put(tip, l.text); put(tip, src.rl and L("ledger.relayed"))
  else
    local e = src.entry
    l.mark = L(e.dr and "ledger.reneged" or "ledger.denied")
    if e.k == "P" then
      l.text, l.amount = L("history.paid", name(client, e.f), name(client, ns.Ledger.author(e.i))), money(e.c)
    else
      l.text = gameText(client, e, e.k == "S", {}, e.why)
      l.amount = type(e.sk) == "number" and money(e.sk) or ""
    end
    put(tip, l.text); if e.k ~= "P" then put(tip, W.gameName(e.g)); put(tip, whyLine(e.why)) end
  end
  local t = date(client, l.at)
  tip[#tip + 1] = string.format("%02d.%02d", t.d, t.m)
  l.tip = table.concat(tip, "\n")
  l.age = age(client, l.at, now)
  return l
end

-- The lines without their text, newest first: one small table per line over the cached history.
local function bare(client, who)
  local out = {}
  if not (client and client.ledger) then return out end
  for i, src in ipairs(ns.LedgerHistory.lines(client.ledger, who)) do
    out[i] = { kind = src.kind, at = src.at, src = src }
  end
  return out
end

local function today(client) return date(client, client.env.epoch()).day end

-- {{kind, text, mark, amount, age, tip, at, src}}: every line of `who` (nil: everyone), with its text.
function HistoryTab.lines(client, who)
  local out = bare(client, who)
  local now = #out > 0 and today(client)
  for _, l in ipairs(out) do dress(client, l, now) end
  return out
end

-- The head-to-head of `who`: {{text}}, at most VERSUS opponents (none without a name).
function HistoryTab.head(client, who)
  local out = {}
  if not (who and client and client.ledger) then return out end
  local rows = Stats.versus(client.ledger, who, { period = "all", now = client.env.epoch() })
  for i = 1, math.min(#rows, HistoryTab.VERSUS) do
    local r = rows[i]
    out[i] = { text = L("history.versus", name(client, r.name), r.won, r.lost, signed(r.net)) }
  end
  return out
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

local function makeRow(r)
  local f = r.frame
  local rule = f:CreateTexture(nil, "BACKGROUND")
  rule:SetColorTexture(RULE[1], RULE[2], RULE[3], 1)
  rule:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
  rule:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
  rule:SetHeight(1)
  r.text = W.Label(f, "paperNote", "", 14)
  r.text:SetPoint("LEFT", f, "LEFT", 8, 0)
  r.text:SetWidth(TEXT_W)
  r.text:SetWordWrap(false)
  r.mark = W.Label(f, "paperNote", "", 11)
  r.mark:SetTextColor(Theme.rgb("felt"))
  r.mark:SetPoint("LEFT", f, "LEFT", 8 + TEXT_W + 6, 0)
  r.mark:SetWidth(MARK_W)
  r.mark:SetWordWrap(false)
  r.age = W.Label(f, "paper", "", 11)
  r.age:SetTextColor(AGE[1], AGE[2], AGE[3])
  r.age:SetJustifyH("RIGHT")
  r.age:SetWidth(AGE_W)
  r.age:SetPoint("RIGHT", f, "RIGHT", -6, 0)
  r.amount = W.Label(f, "paper", "", 13)
  Theme.setFont(r.amount, "uiBold", 13)
  r.amount:SetTextColor(Theme.rgb("felt"))
  r.amount:SetJustifyH("RIGHT")
  r.amount:SetWidth(AMOUNT_W)
  r.amount:SetWordWrap(false)
  r.amount:SetPoint("RIGHT", r.age, "LEFT", -10, 0)
  W.tooltip(f, function(tip)
    if not r.line then return end
    local first = true
    for part in (r.line.tip .. "\n"):gmatch("(.-)\n") do
      if first then tip:SetText(part) else tip:AddLine(part) end
      first = false
    end
  end)
end

local function fillRow(r, line)
  local l = dress(ns.client, line, HistoryTab.view.today)
  r.line = l
  r.text:SetText(l.text)
  r.mark:SetText(l.mark or "")
  W.fit(r.amount, l.amount, AMOUNT_W)
  r.age:SetText(l.age)
  r.frame:SetAlpha(l.kind == "denied" and 0.6 or 1)
end

-- Redraws the page now (only while it is on screen; OnShow redraws it).
function HistoryTab.render()
  local v = HistoryTab.view
  if not v or not v.page:IsVisible() then return end
  v.drawn, v.draws = GetTime(), (v.draws or 0) + 1
  local client, who = ns.client, HistoryTab.state.name
  local lines = bare(client, who)
  v.today = #lines > 0 and today(client)
  v.list:set(lines)
  v.empty:SetShown(#lines == 0)
  v.title:SetText(who and L("history.of", who) or L("tab.history"))
  v.all:SetShown(who ~= nil)
  local head = HistoryTab.head(client, who)
  for i, fs in ipairs(v.versus) do
    fs:SetShown(head[i] ~= nil)
    fs:SetText(head[i] and head[i].text or "")
  end
end

-- Shows the lines of `who` (nil: everyone), now: drawn once (by the page's show, else here).
function HistoryTab.open(who)
  local v = HistoryTab.view
  local draws = v and v.draws
  HistoryTab.state.name = who
  ns.MainWindow.show("history")
  if HistoryTab.view and HistoryTab.view.draws == draws then HistoryTab.render() end
end

function HistoryTab.clear()
  HistoryTab.state.name = nil
  HistoryTab.render()
end

-- Redraws on a ledger event: on the next frame, at most once per GAP s, only while shown.
-- When the timer fires the gap is checked again (as ui/BoardTab.lua): what drew the page meanwhile counts.
local function arm()
  local v = HistoryTab.view
  HistoryTab.scheduled = true
  local wait = math.max(0, (v.drawn or -HistoryTab.GAP) + HistoryTab.GAP - GetTime())
  C_Timer.After(wait, function()
    if not v.page:IsVisible() then HistoryTab.scheduled = false; return end
    if GetTime() - (v.drawn or -HistoryTab.GAP) < HistoryTab.GAP - 1e-6 then return arm() end
    HistoryTab.scheduled = false
    HistoryTab.render()
  end)
end
function HistoryTab.refresh()
  local v = HistoryTab.view
  if not HistoryTab.scheduled and v and v.page:IsVisible() then arm() end
end

function HistoryTab.build(page)
  local panel = W.Panel(page)
  panel:SetSize(BOOK_W, ns.MainWindow.BODY_H)
  panel:SetPoint("TOP", page, "TOP", 0, 0)
  local v = { page = page, panel = panel, versus = {} }
  v.title = W.Label(panel, "heading", L("tab.history"), 15)
  v.title:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -10)
  v.all = W.Button(panel, L("history.all"), function() HistoryTab.clear() end, true)
  v.all:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, -8)
  for i = 1, HistoryTab.VERSUS do
    local fs = W.Label(panel, "dim", "", 12)
    fs:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -(32 + (i - 1) * LINE_H))
    v.versus[i] = fs
  end
  local book = CreateFrame("Frame", nil, panel)
  book:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -HEAD_H)
  book:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -10, 8)
  W.paper(book); v.seal = W.seal(book, 56)
  v.list = ns.BookList.new(book, { width = ROW_W, rowH = ROW_H, rows = ROWS, make = makeRow, fill = fillRow })
  v.list.scroll:SetPoint("TOPLEFT", book, "TOPLEFT", PAD, -8)
  v.empty = W.Label(book, "paperNote", L("history.empty"), 14)
  v.empty:SetPoint("TOPLEFT", book, "TOPLEFT", PAD + 8, -PAD - 6)
  HistoryTab.view = v
  -- The ⓘ of the title bar opens this tab's topic while it is shown, the hall's after.
  local function topic(id) if ns.MainWindow.info then ns.MainWindow.info.topic = id end end
  page:SetScript("OnShow", function() topic("history"); HistoryTab.render() end)
  page:SetScript("OnHide", function() topic("hall") end)
  topic("history")
  HistoryTab.render()
end

ns.MainWindow.addTab("history", "tab.history", HistoryTab.build)

ns.ready(function(client)
  client:on("ledger", HistoryTab.refresh)
end)
