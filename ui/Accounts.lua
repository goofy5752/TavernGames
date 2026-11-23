local _, ns = ...

-- The hall column „Сметки“ (above „В кръчмата сега“), all derived from the
-- ledger: first the questions put to me, then the nets I owe, then the nets
-- owed to me, one row per person (spec 5.4: debts to one person are one
-- transfer). The questions:
-- * "mine": my own entries the guild holds that a crash kept off my saved
--   variables (client.ledgerNet:asks, the first LEDGER_MINE_ASK and how many
--   more wait): one line each under one heading, each with its own „Мои са“
--   (keeps that body) and „Не са мои“ (denies it), so a forgery mixed in among
--   my lost entries is denied alone; „… и още N“ for those waiting.
-- * "ask": a claim against me my client could not decide (client.stakes:asks):
--   who claims what from which game and day, and why it is put to me (a forfeit
--   of mine, or a game I did not see whole); „Потвърждавам“ / „Оспорвам“.
-- * "owing": a Холдем sitting my client did not see whole, whose debt of mine nobody claimed
--   (client.stakes:owing()): „Да, към сметката“ writes my own D (why "cash"), „Не“ asks no more; a claim
--   against me from such a sitting says so too (ask.cash.unseen).
-- * "payAsk": gold that came from a debtor without proof (client.pay:asks): from
--   one name „Да, към сметката“ / „Не“, from namesakes one button per name and „Не“.
-- A row I owe has „Плати“ (ns.PayDialog); while gold of mine has left for that
-- creditor and no P of its has answered it yet (client.pay:guard, saved, 24 h; 30 days by
-- letter), the row says what left, how and when, and „Плати“ is off unless more is owed than
-- has left. A row owed to me has „Напомни“
-- (online debtors only, the tooltip says why; „Напомнено“ for NUDGE_GAP s) and
-- „Уредено“, which asks once more and records a P "hand" only for the amount it
-- asked about (a due changed meanwhile is asked again). The column redraws on "ledger",
-- "payAsk", "debtAsk", "mineAsk" and "paySent"; a reminder ("nudge") is said in the chat frame.
local W, L, C = ns.W, ns.L, ns.Const
local View, money = ns.LedgerView, ns.W.money

local A = {
  nudged = {}, -- name -> env.now() of my last „Напомни“ (this session)
}
ns.Accounts = A

local ROW_GAP, BTN_H, BTN_GAP, BTN_MIN = 8, 20, 6, 64
local SURE_W, SURE_H = 340, 140
local HOW = { trade = "pay.trade", mail = "pay.mail", hand = "accounts.settle" }

local function refresh() ns.Hall.refresh() end
local function who(client, name) return W.colored(client, name, name) end

local function ddmm(client, at)
  local t = (client.env.date or ns.Pay.utc)(at)
  return string.format("%02d.%02d", t.d, t.m)
end

---------------------------------------------------------------------------
-- The rows
---------------------------------------------------------------------------

-- {{kind = "mine", entry, head} (one per asked body; head: the first, under
--  „Тези записи …“) | {kind = "mine", more} (how many more wait unshown)
--  | {kind = "ask", debt, note} | {kind = "payAsk", ask}
--  | {kind = "owe", name, c, sent (my live guard or nil), left} | {kind = "owed", name, c}}: questions first,
-- then what I owe, then what I am owed (each largest first).
function A.rows(client)
  local out, owed = {}, {}
  if not (client and client.ledger and client.pay and client.stakes) then return out end
  local pay = client.pay
  local mine, more = client.ledgerNet:asks()
  for i, b in ipairs(mine) do out[#out + 1] = { kind = "mine", entry = b, head = i == 1 } end
  if #mine > 0 and (more or 0) > 0 then out[#out + 1] = { kind = "mine", more = more } end
  for _, d in ipairs(client.stakes:asks()) do out[#out + 1] = { kind = "ask", debt = d, note = client.stakes:seen()[d.gid] } end
  for _, o in ipairs(client.stakes:owing()) do out[#out + 1] = { kind = "owing", owing = o } end
  for _, q in ipairs(pay:asks()) do out[#out + 1] = { kind = "payAsk", ask = q } end
  for _, a in ipairs(View.accounts(View.of(client.ledger), client.env.me)) do
    if a.net > 0 then
      out[#out + 1] = { kind = "owe", name = a.name, c = a.net, sent = pay:guard(a.name), left = pay:left(a.name) }
    elseif pay:due(a.name) > 0 then
      owed[#owed + 1] = { kind = "owed", name = a.name, c = pay:due(a.name) }
    end
  end
  for _, r in ipairs(owed) do out[#out + 1] = r end
  return out
end

-- One line about my own entry e: what it is, the day, the names, the amount;
-- an X says what it denies (the body it names, when I hold it).
local function entryLine(client, e, deep)
  local parts = {}
  if e.k == "P" then
    parts = { L(HOW[e.how] or "accounts.settle"), ddmm(client, e.at), who(client, e.f), money(e.c) }
  elseif e.k == "D" then
    parts = { W.gameName(e.g), ddmm(client, e.at), L("bill.row", who(client, e.f), who(client, e.t), money(e.c)) }
  elseif e.k == "C" or e.k == "N" then
    local d = client.ledger:get(e.r)
    parts = { L(e.k == "C" and "ask.yes" or "ask.no"), ddmm(client, e.at) }
    if d and d.k == "D" then parts[3] = L("bill.row", who(client, d.f), who(client, d.t), money(d.c)) end
  elseif e.k == "R" then
    parts = { W.gameName(e.g), ddmm(client, e.at) }
  elseif e.k == "S" then
    parts = { L("accounts.entry.S", who(client, e.f), money(e.c)), ddmm(client, e.at) }
  elseif e.k == "X" then
    local a, n = ns.Ledger.author(e.r)
    local what = tostring(e.r)
    for _, t in ipairs(a and not deep and client.ledger:bodies(a, n) or {}) do
      if t.h == e.rh then what = entryLine(client, t, true) end
    end
    parts = { ddmm(client, e.at), L("ask.mine.deny", what) }
  else
    parts = { ddmm(client, e.at) }
  end
  return table.concat(parts, " · ")
end
A.entryLine = entryLine

-- The claim put to me: who, how much, which game and day, and why I am asked.
local function debtText(client, d, note)
  local s = L("ask.debt", who(client, d.t), money(d.c), W.gameName(d.g), ddmm(client, d.at))
  local foul = type(note) == "table" and note.foul
  if type(note) == "table" and note.why == "cash" and foul == "unseen" and d.why == "lost" then -- a Холдем sitting my client did not see whole
    return s .. " " .. L("ask.debt.unseen") .. " " .. L("ask.cash.unseen")
  end
  if d.why ~= "lost" then -- my own „Стани“ is put to me only when my client holds a foul of that game
    return s .. " " .. L("ask.debt.left") .. (foul and " " .. L(foul == "unseen" and "ask.debt.unseen" or "ask.debt.foul") or "")
  end
  if type(note) ~= "table" or note.foul == "unseen" then return s .. " " .. L("ask.debt.unseen") end
  return s
end

local function nudgedNow(client, name)
  local at = A.nudged[name]
  return at ~= nil and client.env.now() - at < C.NUDGE_GAP
end

local timers = {} -- name -> the redraw when its „Напомнено“ ends
local function nudge(client, name)
  local done, why = client.pay:nudge(name)
  if done or why == "wait" then
    A.nudged[name] = client.env.now()
    if timers[name] then timers[name]:Cancel() end
    timers[name] = C_Timer.NewTimer(C.NUDGE_GAP, function()
      timers[name] = nil
      refresh()
    end)
  end
  refresh()
end

local function online(client, name)
  local p = client.presence:get(name)
  return p ~= nil and not p.incompatible
end

-- The row's content: {text (nil: none), sub, inline (its one button right of the text), buttons = {{label, act, on, tip}}}.
local SPEC = {
  mine = function(client, r) -- each body answered alone (a forgery mixed in is denied, my own kept)
    if not r.entry then return { sub = L("bill.more", r.more), buttons = {} } end
    local net, b = client.ledgerNet, r.entry
    return { text = r.head and L("ask.mine") or nil, sub = entryLine(client, b), buttons = {
      { L("ask.mine.yes"), function() net:answer(b, true) end },
      { L("ask.mine.no"), function() net:answer(b, false) end } } }
  end,
  ask = function(client, r)
    local key, stakes = r.debt.key, client.stakes
    return { text = debtText(client, r.debt, r.note), buttons = {
      { L("ask.yes"), function() stakes:answer(key, true) end },
      { L("ask.no"), function() stakes:answer(key, false) end } } }
  end,
  owing = function(client, r) -- a Холдем debt of mine nobody claimed: my own D, why "cash", when I say yes
    local o, stakes = r.owing, client.stakes
    return { text = L("ask.cash.owe", who(client, o.t), money(o.c)), buttons = {
      { L("ask.pay.yes"), function() stakes:admit(o.key, true) end },
      { L("ask.pay.no"), function() stakes:admit(o.key, false) end } } }
  end,
  payAsk = function(client, r)
    local q, pay = r.ask, client.pay
    local no = { L("ask.pay.no"), function() pay:answer(q.id, false) end }
    if q.name then
      return { text = L("ask.pay", who(client, q.name), money(q.c)), buttons = {
        { L("ask.pay.yes"), function() pay:answer(q.id, q.name) end }, no } }
    end
    local buttons = {}
    for i, name in ipairs(q.names or {}) do buttons[i] = { who(client, name), function() pay:answer(q.id, name) end } end
    buttons[#buttons + 1] = no
    return { text = L("ask.pay.who", money(q.c)), buttons = buttons }
  end,
  owe = function(client, r)
    local g = r.sent
    local sub = g and L(g.how == "mail" and "accounts.sent.mail" or "accounts.sent.trade", money(g.c), ddmm(client, g.at), who(client, r.name)) or nil
    local tip = g and g.how == "mail" and "accounts.sent.tip.mail" or "accounts.sent.tip"
    local gone = r.left == 0 and function(t) t:SetText(L(tip)) end or nil
    return { text = L("accounts.owe", who(client, r.name), money(r.c)), inline = true, sub = sub,
      buttons = { { L("accounts.pay"), function() ns.PayDialog.open(r.name) end, r.left > 0, gone } } }
  end,
  owed = function(client, r)
    local done, on = nudgedNow(client, r.name), online(client, r.name)
    local away = not on and function(tip) tip:SetText(L("accounts.nudge.offline", who(client, r.name))) end or nil
    return { text = L("accounts.owed", who(client, r.name), money(r.c)), buttons = {
      { L(done and "accounts.nudged" or "accounts.nudge"), function() nudge(client, r.name) end, not done and on, away },
      { L("accounts.settle"), function() A.askSettle(r.name, r.c) end, true,
        function(tip) tip:SetText(L("accounts.settle")); tip:AddLine(L("accounts.settle.tip")) end } } }
  end,
}

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

local function rowWidget(acc, i)
  local r = acc.rows[i]
  if r then return r end
  local f = CreateFrame("Frame", nil, acc.scroll.content)
  f:SetWidth(acc.rowW)
  local text = W.Label(f, "ui", "", 12)
  text:SetWordWrap(true)
  text:SetJustifyH("LEFT")
  text:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  local sub = W.Label(f, "dim", "", 11)
  sub:SetWordWrap(true)
  sub:SetJustifyH("LEFT")
  r = { frame = f, text = text, sub = sub, buttons = {} }
  acc.rows[i] = r
  return r
end

local function buttonOf(r, j)
  local b = r.buttons[j]
  if b then return b end
  b = W.Button(r.frame, "", function(self)
    if self.act then self.act() end
    refresh()
  end, true)
  b:HookScript("OnEnter", function(self)
    if not self.tip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    self.tip(GameTooltip)
    GameTooltip:Show()
  end)
  b:HookScript("OnLeave", function(self) if self.tip then GameTooltip:Hide() end end)
  r.buttons[j] = b
  return b
end

-- Fills row widget r from spec at `y` in the list -> its height.
local function place(acc, r, spec, y)
  local rowW, f = acc.rowW, r.frame
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", acc.scroll.content, "TOPLEFT", 0, -y)
  local widths = {}
  for j, s in ipairs(spec.buttons) do
    local b = buttonOf(r, j)
    b.text:SetText(s[1])
    widths[j] = math.min(rowW, math.max(BTN_MIN, math.ceil(b.text:GetStringWidth()) + 16))
    b:SetSize(widths[j], BTN_H)
    b.act, b.tip = s[2], s[4]
    local on = s[3] ~= false
    b:SetEnabled(on)
    b:SetAlpha(on and 1 or 0.5)
    b:ClearAllPoints()
    b:Show()
  end
  for j = #spec.buttons + 1, #r.buttons do r.buttons[j]:Hide() end
  local textW = spec.inline and rowW - widths[1] - BTN_GAP or rowW
  local h = 0
  r.text:SetShown(spec.text ~= nil)
  if spec.text then
    r.text:SetWidth(textW)
    r.text:SetText(spec.text)
    h = r.text:GetStringHeight()
  end
  if spec.inline then
    r.buttons[1]:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 2)
    h = math.max(h, BTN_H - 2)
  end
  r.sub:SetShown(spec.sub ~= nil)
  if spec.sub then
    r.sub:ClearAllPoints()
    local top = h > 0 and h + 2 or 0
    r.sub:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -top)
    r.sub:SetWidth(textW)
    r.sub:SetText(spec.sub)
    h = top + r.sub:GetStringHeight()
  end
  if not spec.inline then -- the buttons under the text, in rows as they fit
    local x, top = 0, h + 4
    for j = 1, #spec.buttons do
      if x > 0 and x + widths[j] > rowW then x, top = 0, top + BTN_H + 4 end
      r.buttons[j]:SetPoint("TOPLEFT", f, "TOPLEFT", x, -top)
      x = x + widths[j] + BTN_GAP
    end
    if #spec.buttons > 0 then h = top + BTN_H end
  end
  f:SetHeight(h)
  return h
end

-- Fills the column (empty without a client or a ledger).
function A.render(v, client)
  local acc = v.accounts
  if not acc then return end
  local rows, y = A.rows(client), 0
  for i, row in ipairs(rows) do
    local r = rowWidget(acc, i)
    y = y + place(acc, r, SPEC[row.kind](client, row), y) + ROW_GAP
    r.frame:Show()
  end
  for i = #rows + 1, #acc.rows do acc.rows[i].frame:Hide() end
  acc.scroll:setContentHeight(math.max(0, y - ROW_GAP))
  acc.empty:SetShown(#rows == 0)
end

-- The column's panel at (x, y below the top) on `page`, w x h.
function A.build(v, page, x, y, w, h)
  local panel = W.Panel(page)
  panel:SetPoint("TOPLEFT", page, "TOPLEFT", x, -y)
  panel:SetSize(w, h)
  local title = W.Label(panel, "heading", L("accounts.title"))
  title:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -10)
  local info = W.Info(panel, "ledger")
  info:SetPoint("LEFT", title, "RIGHT", 6, 0)
  local scroll = W.Scroll(panel)
  scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -32)
  scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, 8)
  local rowW = w - 16 - 6
  scroll.content:SetWidth(rowW)
  local empty = W.Label(panel, "dim", L("accounts.none"), 12)
  empty:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -34)
  v.accounts = { panel = panel, title = title, info = info, scroll = scroll, empty = empty, rows = {}, rowW = rowW }
end

---------------------------------------------------------------------------
-- „Уредено“: once more before it clears
---------------------------------------------------------------------------

local function buildSure()
  local Theme = ns.Theme
  local f = CreateFrame("Frame", nil, UIParent)
  A.sure = f
  ns.Resize.follow(f, "main")
  f:SetSize(SURE_W, SURE_H)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:EnableMouse(true)
  W.chrome(f, SURE_W, SURE_H)
  A.sureText = W.Label(f, "ui", "", 13)
  A.sureText:SetWidth(SURE_W - 48)
  A.sureText:SetWordWrap(true)
  A.sureText:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -24)
  A.sureYes = W.Button(f, L("accounts.settle"), function()
    local client, name, c = ns.client, A.sureName, A.sureC
    f:Hide()
    if not (client and client.pay and name) then return end
    local due = client.pay:due(name)
    if due == c then client.pay:settle(name)
    elseif due > 0 then A.askSettle(name, due) end -- the debt changed meanwhile: asked again, nothing recorded
    refresh()
  end)
  A.sureYes:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -24, 20)
  A.sureNo = W.Button(f, L("stake.ask.no"), function() f:Hide() end)
  A.sureNo:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 24, 20)
  f:SetScript("OnHide", function() A.sureName, A.sureC = nil, nil end)
  f:Hide()
end

-- „Получи ли 5g от Мария? …“ before „Уредено“ records the P.
function A.askSettle(name, c)
  if not A.sure then buildSure() end
  A.sure:Hide()
  A.sureName, A.sureC = name, c
  A.sureText:SetText(L("accounts.settle.sure", money(c), who(ns.client, name)))
  A.sure:Show()
  A.sure:Raise()
end

ns.ready(function(client)
  for _, event in ipairs({ "ledger", "payAsk", "debtAsk", "mineAsk", "paySent" }) do client:on(event, refresh) end
  client:on("nudge", function(name, c)
    if ns.Adapter and ns.Adapter.say then ns.Adapter.say(L("nudge.say", who(client, name), money(c))) end
  end)
end)
