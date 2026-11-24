local _, ns = ...

-- The „Уредено“ toast (spec 5.4), top centre like an achievement, with a coin
-- sound: a payment that names me became confirmed in my ledger while I play
-- (core/LedgerNet.lua "paid": my own record, or the creditor's live one; never
-- the sync's). „Уредено: Мария ти плати 5g“ or „Уредено: плати 5g на Мария“,
-- and under it how it was paid and what is left between us now: „сметката ви е
-- чиста“ at zero; else the hall's net (View.net) or, when that is zero, the
-- pair's one-sided credit (a payment beyond the debt: never „чиста“), as a
-- positive Z: „остават Z“ while the payer still owes, „надплатени Z“ when the
-- rest is in the payer's favour.
-- Once per id; a record more than FRESH s old is ignored; at most MAX wait and
-- the rest are dropped. The head of the queue is shown on the next frame for
-- SECONDS, then the next; its balance is read when it is shown (one view per
-- toast). A click closes it.
local Theme, W, L = ns.Theme, ns.W, ns.L

local SettleToast = {
  FRESH = 300, SECONDS = 6, MAX = 5, WIDTH = 360, HEIGHT = 64,
  seen = {},  -- id -> true: announced (or queued) once
  queue = {}, -- "paid" records waiting, oldest first
  frame = nil, title = nil, sub = nil, icon = nil, -- built on the first toast
}
ns.SettleToast = SettleToast

local PAD, COIN = 10, 44

-- What f owes t on its confirmed debts less what t recorded as paid by f;
-- below 0 when t holds more of f's than f owed (a credit, which the view's
-- gross leaves out).
local function owed(v, f, t) return (v.sum[f] and v.sum[f][t] or 0) - ns.LedgerView.paid(v, f, t) end

-- The two lines of the toast for "paid" record p -> title, sub.
function SettleToast.text(client, p)
  local me = client.ledger.me
  local other = p.to == me and p.from or p.to
  local v = ns.LedgerView.of(client.ledger)
  -- > 0: I owe other. The hall's net when it has one, else the pair's one-sided credit.
  local net = ns.LedgerView.net(v, me, other)
  if net == 0 then net = owed(v, me, other) - owed(v, other, me) end
  local title
  if p.to == me then
    title = L("settle.got", W.shortColored(client, p.from), W.money(p.c))
  else
    title = L("settle.paid", W.money(p.c), W.shortColored(client, p.to))
  end
  -- The payer still owes the receiver: „остават“; the rest is in the payer's favour: „надплатени“.
  local payerOwes = (p.from == me) == (net > 0)
  local rest = net == 0 and L("settle.clean") or L(payerOwes and "settle.left" or "settle.over", W.money(math.abs(net)))
  return title, L("settle.how." .. tostring(p.how)) .. " · " .. rest
end

local function build()
  local t = SettleToast
  local f = CreateFrame("Button", nil, UIParent)
  t.frame = f
  f:SetSize(t.WIDTH, t.HEIGHT)
  f:SetPoint("TOP", UIParent, "TOP", 0, -160)
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:RegisterForClicks("AnyUp")
  f:SetScript("OnClick", function() SettleToast.close() end)
  ns.Resize.follow(f, "main")
  local fill = f:CreateTexture(nil, "BACKGROUND")
  fill:SetAllPoints(f)
  fill:SetColorTexture(0, 0, 0, 0.72)
  W.edges(f, 1).setColor(Theme.rgb("brass"))
  local icon = f:CreateTexture(nil, "ARTWORK")
  icon:SetSize(COIN, COIN)
  icon:SetPoint("LEFT", f, "LEFT", PAD, 0)
  if not ns.Art.set(icon, "coin", "gold") then -- our gold cell of the coins strip
    icon:SetTexture(Theme.tex.coins)
    icon:SetTexCoord(0, 0.25, 0, 1)
  end
  t.icon = icon
  local title = W.Label(f, "heading", "", 14)
  title:SetTextColor(Theme.rgb("goldHi"))
  title:SetPoint("TOPLEFT", icon, "TOPRIGHT", PAD, -4)
  t.title = title
  local sub = W.Label(f, "dim", "")
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
  t.sub = sub
  -- a hover gives the other party's whole name (the title has the short one, ui/NameTag.lua)
  W.nameTip(f, function()
    local p, me = t.shown, ns.client and ns.client.ledger and ns.client.ledger.me
    return p and (p.to == me and p.from or p.to)
  end)
  f:Hide()
end

local TEXT_W = SettleToast.WIDTH - 3 * PAD - COIN

-- 160 px under the screen's top, or under the invitation toast while that shows (both stand there).
function SettleToast.place()
  local f = SettleToast.frame
  if not f then return end
  local inv = ns.InviteToast and ns.InviteToast.frame
  f:ClearAllPoints()
  if inv and inv:IsShown() then f:SetPoint("TOP", inv, "BOTTOM", 0, -8) else f:SetPoint("TOP", UIParent, "TOP", 0, -160) end
end

-- Shows record p for SECONDS, with the coin sound.
function SettleToast.show(client, p)
  local t = SettleToast
  if not t.frame then build() end
  local title, sub = SettleToast.text(client, p)
  W.fitWrap(t.title, title, TEXT_W) -- shrunk, then wrapped: never cut
  W.fitWrap(t.sub, sub, TEXT_W)
  t.shown = p
  t.timer = C_Timer.NewTimer(t.SECONDS, function() t.timer = nil; SettleToast.close() end)
  SettleToast.place()
  t.frame:Show()
  t.frame:Raise()
  ns.Art.play("settled")
end

-- The head of the queue on the next frame, unless a toast is up or due.
local function pump()
  local t = SettleToast
  if t.shown or t.due or #t.queue == 0 then return end
  t.due = true
  C_Timer.After(0, function()
    t.due = nil
    local p, client = table.remove(t.queue, 1), ns.client
    if p and client then SettleToast.show(client, p) end
  end)
end

-- Closes the toast shown; the next one follows.
function SettleToast.close()
  local t = SettleToast
  if t.timer then t.timer:Cancel(); t.timer = nil end
  t.shown = nil
  if t.frame then t.frame:Hide() end
  pump()
end

-- A "paid" record: queued unless seen, stale, not mine, or the queue is full.
function SettleToast.add(client, p)
  local t, me = SettleToast, client.ledger and client.ledger.me
  if type(p) ~= "table" or p.id == nil or t.seen[p.id] or (p.to ~= me and p.from ~= me) then return end
  if type(p.at) ~= "number" or client.env.epoch() - p.at > t.FRESH then return end
  t.seen[p.id] = true
  if #t.queue >= t.MAX then return end
  t.queue[#t.queue + 1] = p
  pump()
end

ns.ready(function(client)
  client:on("paid", function(p) SettleToast.add(client, p) end)
end)
