local _, ns = ...

-- The tab „Тефтер“ (spec 5.6, mockup 06, the right half): every debt of the
-- guild as a line in the innkeeper's book, all derived from the ledger
-- (core/LedgerView.lua). The open debts come first, then the pending, the
-- contested, the paid (struck through) and the denied entries (a D or a P its
-- author denied: „отречено“, or „отречено от автора си“ when I got it straight
-- from that author), each group newest first. A partly paid debt shows what is
-- left of it. Each line: „длъжник → кредитор“ (names in a darkened class colour
-- when presence knows the class, else in the ink of the page), its mark, the
-- amount and the age in calendar days, each in a fixed one-line column (a long
-- name is clipped); its tooltip gives the whole line, the game and the day,
-- and says „пренесено“ when an entry it rests on reached me only through a
-- third player. The head counts the open debts, the foot names the biggest
-- debtor (hidden when nobody owes). The lines are ordered once per redraw (one
-- View.of, the denials as the view found them, never L:denied per row); the
-- list is virtualized: only the rows on screen have widgets, and a line gets its
-- text when it first comes on screen, so a large ledger costs one sort. The page
-- redraws on "ledger" (on the next frame, only while it is shown) and on show;
-- while it is shown the ⓘ of the title bar opens the ledger topic.
local Theme, W, L = ns.Theme, ns.W, ns.L
local View, Ledger, money = ns.LedgerView, ns.Ledger, ns.W.money

local LedgerTab = {
  view = nil,
  DARK = 0.55, -- class colours darkened for the cream paper (mockup 06)
}
ns.LedgerTab = LedgerTab

local BOOK_W, PAD, HEAD_H, ROW_H, ROWS, FOOT_H = 760, 14, 52, 26, 16, 24
local AGE_W, MARGIN = 56, 22
-- Fixed columns, one line each (clipped, never wrapped): 22 + 286 + 8 + 120 + 196 + 10 + 56 + 6 <= the row.
-- The amount fits „остават 99g 98s от 99g 99s“ with a coin for each letter.
local WHO_W, MARK_W, AMOUNT_W = 286, 120, 196
local GROUP = { open = 1, pending = 2, contested = 3, paid = 4, denied = 5 }
local MARK = { pending = "ledger.pending", contested = "ledger.contested" }
local HOW = { trade = "pay.trade", mail = "pay.mail", hand = "accounts.settle" }
local RULE, AGE, PAID = { 0xd9 / 255, 0xc4 / 255, 0x9a / 255 }, { 0x7a / 255, 0x5a / 255, 0x3a / 255 },
  { 0x4a / 255, 0x6a / 255, 0x2a / 255 }

---------------------------------------------------------------------------
-- The lines
---------------------------------------------------------------------------

-- A name in its class colour, darkened for the paper; plain (the page's ink) without a known class.
local function name(client, who)
  local p = who ~= client.env.me and client.presence:get(who)
  local cls = who == client.env.me and client.env.cls or p and p.cls
  local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
  if not (cls and colors and colors[cls]) then return who end
  local r, g, b = ns.classColor(cls)
  return W.paint(who, r * LedgerTab.DARK, g * LedgerTab.DARK, b * LedgerTab.DARK)
end

local function date(client, t) return (client.env.date or ns.Pay.utc)(t) end
local function today(client) return date(client, client.env.epoch()).day end

-- „днес“, „вчера“ or „N дни“: calendar days between `at` and `now` (a day number; default:
-- today), by my own clock and zone.
function LedgerTab.age(client, at, now)
  local n = (now or today(client)) - date(client, at).day
  if n <= 0 then return L("ledger.age.today") end
  if n == 1 then return L("ledger.age.yesterday") end
  return L("ledger.age.days", n)
end

-- Did any body under these ids that passes `keep` reach me only through a third player?
local function relayed(ledger, ids, keep)
  for _, id in ipairs(ids) do
    local a, n = Ledger.author(id)
    for _, b in ipairs(a and ledger:bodies(a, n) or {}) do if b.rl and keep(b) then return true end end
  end
  return false
end

-- The entries debt d rests on: its claims, and the debtor's word that decided it.
local function debtRelayed(ledger, d)
  local claims = {}
  local function claim(b)
    local ok = b.k == "D" and b.gid == d.gid and b.f == d.f and b.t == d.t
    if ok then claims[b.h] = true end
    return ok
  end
  if relayed(ledger, d.ids, claim) then return true end
  return d.said ~= nil and relayed(ledger, { d.said }, function(b) return b.k ~= "D" and claims[b.dh] end)
end

-- The text parts of line l (who, amount, mark, what, age, relayed), made once, when first needed.
local function dress(client, l, now)
  if l.who then return l end
  local d, e = l.debt, l.entry
  if d then
    local marks = { MARK[l.state] and L(MARK[l.state]) }
    if d.clash then marks[#marks + 1] = L("ledger.clash") end
    l.who = L("ledger.row", name(client, d.f), name(client, d.t))
    l.amount = l.state == "open" and l.open < d.c and L("ledger.part", money(l.open), money(d.c)) or money(d.c)
    l.mark = #marks > 0 and table.concat(marks, " · ") or nil
    l.what, l.relayed = d.why == "cash" and L("why.cash") or W.gameName(d.g), debtRelayed(client.ledger, d) -- a Холдем debt of its debtor's own word
  else
    l.who = L("ledger.row", name(client, e.f), name(client, l.t))
    l.amount, l.mark = money(e.c), L(e.dr and "ledger.reneged" or "ledger.denied")
    l.what, l.relayed = e.k == "D" and W.gameName(e.g) or L(HOW[e.how] or "accounts.settle"), e.rl == true
  end
  l.age = LedgerTab.age(client, l.at, now)
  return l
end

-- The lines without their text, in order: the open debts, then pending,
-- contested, paid and denied (a D, or a P: payer → its author), each newest first.
local function bare(client)
  local out = {}
  if not (client and client.ledger) then return out end
  local v = View.of(client.ledger)
  for _, row in ipairs(View.rows(v)) do
    local d = row.debt
    local state = d.status ~= "confirmed" and d.status or row.open > 0 and "open" or "paid"
    out[#out + 1] = { state = state, at = d.at, debt = d, open = row.open }
  end
  for _, e in ipairs(View.denied(v)) do
    local t = e.k == "D" and e.t or e.k == "P" and Ledger.author(e.i) or nil
    if type(t) == "string" and type(e.f) == "string" and type(e.c) == "number" and type(e.at) == "number" then
      out[#out + 1] = { state = "denied", at = e.at, entry = e, t = t }
    end
  end
  for j, l in ipairs(out) do l.order = j end
  table.sort(out, function(p, q)
    if p.state ~= q.state then return GROUP[p.state] < GROUP[q.state] end
    if p.at ~= q.at then return p.at > q.at end
    return p.order > q.order
  end)
  return out
end

-- {{state, who, amount, mark, age, what, relayed, at, debt | entry}}: every line, in order, with its text.
function LedgerTab.lines(client)
  local out = bare(client)
  local now = #out > 0 and today(client)
  for _, l in ipairs(out) do dress(client, l, now) end
  return out
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

local function rowWidget(v, j)
  local r = v.rows[j]
  if r then return r end
  local f = CreateFrame("Frame", nil, v.scroll.content)
  f:SetSize(v.rowW, ROW_H)
  f:EnableMouse(true)
  local rule = f:CreateTexture(nil, "BACKGROUND")
  rule:SetColorTexture(RULE[1], RULE[2], RULE[3], 1)
  rule:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
  rule:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
  rule:SetHeight(1)
  local who = W.Label(f, "paperNote", "", 14)
  who:SetPoint("LEFT", f, "LEFT", MARGIN, 0)
  who:SetWidth(WHO_W)
  who:SetWordWrap(false)
  local mark = W.Label(f, "paperNote", "", 11)
  mark:SetTextColor(Theme.rgb("felt"))
  mark:SetPoint("LEFT", f, "LEFT", MARGIN + WHO_W + 8, 0)
  mark:SetWidth(MARK_W)
  mark:SetWordWrap(false)
  local age = W.Label(f, "paper", "", 11)
  age:SetTextColor(AGE[1], AGE[2], AGE[3])
  age:SetJustifyH("RIGHT")
  age:SetWidth(AGE_W)
  age:SetPoint("RIGHT", f, "RIGHT", -6, 0)
  local amount = W.Label(f, "paper", "", 13)
  Theme.setFont(amount, "uiBold", 13)
  amount:SetJustifyH("RIGHT")
  amount:SetWidth(AMOUNT_W)
  amount:SetWordWrap(false)
  amount:SetPoint("RIGHT", age, "LEFT", -10, 0)
  local strike = f:CreateTexture(nil, "OVERLAY")
  strike:SetColorTexture(Theme.color.felt[1], Theme.color.felt[2], Theme.color.felt[3], 1)
  strike:SetPoint("LEFT", who, "LEFT", -2, 0)
  strike:SetPoint("RIGHT", amount, "RIGHT", 2, 0)
  strike:SetHeight(2)
  r = { frame = f, who = who, mark = mark, age = age, amount = amount, strike = strike }
  W.tooltip(f, function(tip)
    local l, t = r.line, date(ns.client, r.line.at)
    tip:SetText(l.who)
    tip:AddLine(l.what .. " · " .. string.format("%02d.%02d", t.d, t.m))
    if l.mark then tip:AddLine(l.mark) end
    if l.relayed then tip:AddLine(L("ledger.relayed")) end
  end)
  v.rows[j] = r
  return r
end

-- Line i of the list into row widget r.
local function fillRow(v, r, i)
  local l = dress(ns.client, v.lines[i], v.today)
  r.line, r.index = l, i
  r.frame:ClearAllPoints()
  r.frame:SetPoint("TOPLEFT", v.scroll.content, "TOPLEFT", 0, -(i - 1) * ROW_H)
  r.who:SetText(l.who)
  r.mark:SetText(l.mark or "")
  r.mark:SetShown(l.mark ~= nil)
  W.fit(r.amount, l.amount, AMOUNT_W)
  if l.state == "paid" then r.amount:SetTextColor(PAID[1], PAID[2], PAID[3]) else r.amount:SetTextColor(Theme.rgb("felt")) end
  r.age:SetText(l.age)
  r.strike:SetShown(l.state == "paid")
  r.frame:SetAlpha((l.state == "paid" or l.state == "denied") and 0.6 or 1)
  r.frame:Show()
end

-- The row widgets of the lines on screen (a widget is made only when a line needs it).
function LedgerTab.fill()
  local v = LedgerTab.view
  if not v then return end
  local first = math.floor(v.scroll:GetVerticalScroll() / ROW_H) + 1
  local used = 0
  for i = first, math.min(#v.lines, first + ROWS) do
    used = used + 1
    fillRow(v, rowWidget(v, used), i)
  end
  for j = used + 1, #v.rows do v.rows[j].frame:Hide() end
end

-- Redraws the page now (only while it is on screen; OnShow redraws it).
function LedgerTab.render()
  local v = LedgerTab.view
  if not v or not v.page:IsVisible() then return end
  local client = ns.client
  v.lines = bare(client)
  local any = #v.lines > 0
  v.today = any and today(client)
  v.empty:SetShown(not any)
  v.head:SetShown(any)
  local totals = any and View.totals(View.of(client.ledger))
  if any then v.head:SetText(L("ledger.head", money(totals.open), totals.count)) end
  v.foot:SetShown(any and totals.top ~= nil)
  if any and totals.top then v.foot:SetText(L("ledger.top", name(client, totals.top), money(totals.topSum))) end
  v.scroll:setContentHeight(#v.lines * ROW_H)
  LedgerTab.fill()
end

-- Redraws on the next frame; several calls in one frame draw once.
function LedgerTab.refresh()
  if LedgerTab.scheduled then return end
  LedgerTab.scheduled = true
  C_Timer.After(0, function()
    LedgerTab.scheduled = false
    LedgerTab.render()
  end)
end

local function topic(id) if ns.MainWindow.info then ns.MainWindow.info.topic = id end end

function LedgerTab.build(page)
  local bodyH = ns.MainWindow.BODY_H
  local panel = W.Panel(page)
  panel:SetSize(BOOK_W, bodyH)
  panel:SetPoint("TOP", page, "TOP", 0, 0)
  local title = W.Label(panel, "heading", L("tab.ledger"), 15)
  title:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -10)
  local head = W.Label(panel, "dim", "", 12)
  head:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
  local book = CreateFrame("Frame", nil, panel)
  book:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -HEAD_H)
  book:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -10, 10)
  W.paper(book)
  local seal = W.seal(book, 56)
  local margin = book:CreateTexture(nil, "BORDER")
  margin:SetColorTexture(Theme.color.felt[1], Theme.color.felt[2], Theme.color.felt[3], 0.25)
  margin:SetPoint("TOPLEFT", book, "TOPLEFT", PAD + MARGIN - 8, -12)
  margin:SetPoint("BOTTOMLEFT", book, "BOTTOMLEFT", PAD + MARGIN - 8, 12)
  margin:SetWidth(1)
  local scroll = W.Scroll(book)
  scroll:SetPoint("TOPLEFT", book, "TOPLEFT", PAD, -PAD)
  scroll:SetSize(BOOK_W - 20 - 2 * PAD, ROWS * ROW_H)
  local rowW = BOOK_W - 20 - 2 * PAD - 6
  scroll.content:SetWidth(rowW)
  scroll:HookScript("OnMouseWheel", function() LedgerTab.fill() end)
  local empty = W.Label(book, "paperNote", L("ledger.empty"), 14)
  empty:SetPoint("TOPLEFT", book, "TOPLEFT", PAD + MARGIN, -PAD - 6)
  local foot = W.Label(book, "paperNote", "", 13)
  foot:SetPoint("BOTTOMLEFT", book, "BOTTOMLEFT", PAD + MARGIN, PAD)
  foot:SetHeight(FOOT_H - 6)
  LedgerTab.view = { seal = seal, page = page, panel = panel, title = title, head = head, book = book, scroll = scroll,
    empty = empty, foot = foot, rows = {}, lines = {}, rowW = rowW, ROWS = ROWS, ROW_H = ROW_H }
  page:SetScript("OnShow", function() topic("ledger"); LedgerTab.render() end)
  page:SetScript("OnHide", function() topic("hall") end)
  topic("ledger")
  LedgerTab.render()
end

ns.MainWindow.addTab("ledger", "tab.ledger", LedgerTab.build)

ns.ready(function(client)
  client:on("ledger", LedgerTab.refresh)
end)
