local _, ns = ...

-- „Плащане“ (PayDialog.open(name), from „Плати“ in „Сметки“): what I owe `name`
-- (the pair's net: one transfer, spec 5.4) and the two ways to pay it. The
-- addon never moves gold: „Трейд“ opens a trade and fills the amount, „Поща“
-- fills a letter; the player presses the game's „Trade“ / „Send“ (core/Pay.lua,
-- wow/Trade.lua, wow/Mail.lua). Each way says why it is off: not next to me, no
-- unit to trade with, no open mailbox, not enough gold (by mail the fee counts),
-- or a client without the API (pay it by hand, the creditor presses „Уредено“).
-- Nothing reports a failed fill, so once a trade is opened the amount to type
-- stays on screen. Gold that has left already and is not recorded yet
-- (client.pay:guard) is said under the amount, and only the rest can be paid;
-- when all of it has left both ways are off. The fee and the economy-hold
-- warning are always shown; ⓘ is the ledger topic. The dialog redraws twice a
-- second, on "ledger" and on "paySent", and it closes when nothing is owed any more.
local Theme, W, L = ns.Theme, ns.W, ns.L
local money = ns.W.money

local P = {
  name = nil,   -- the creditor shown
  typed = false, -- a trade was opened from here: show the amount to type
}
ns.PayDialog = P

local DLG_W, DLG_H = 420, 360
local BTN_W, LINE_W = 120, 420 - 24 - 120 - 12 - 24
local REDRAW = 0.5 -- s

local function enable(b, on)
  b:SetEnabled(on)
  b:SetAlpha(on and 1 or 0.5)
end

local function line(f, style, size, width)
  local fs = W.Label(f, style, "", size)
  fs:SetWidth(width)
  fs:SetWordWrap(true)
  fs:SetJustifyH("LEFT")
  return fs
end

local function build()
  local f = CreateFrame("Frame", nil, UIParent)
  P.frame = f
  ns.Resize.follow(f, "main")
  f:SetSize(DLG_W, DLG_H)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:EnableMouse(true)
  W.chrome(f, DLG_W, DLG_H)
  P.title = W.Label(f, "heading", L("pay.title"), 17)
  P.title:SetJustifyH("CENTER")
  P.title:SetPoint("TOP", f, "TOP", 0, -20)
  P.info = W.Info(f, "ledger")
  P.info:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -18)
  P.close = W.Close(f)
  P.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -16)
  P.to = W.Label(f, "ui", "", 13)
  P.to:SetJustifyH("CENTER")
  P.to:SetPoint("TOP", f, "TOP", 0, -48)
  P.amount = W.Label(f, "heading", "", 22)
  P.amount:SetTextColor(Theme.rgb("gold"))
  P.amount:SetJustifyH("CENTER")
  P.amount:SetPoint("TOP", f, "TOP", 0, -68)
  P.sent = W.Label(f, "dim", "", 11)
  P.sent:SetJustifyH("CENTER")
  P.sent:SetPoint("TOP", f, "TOP", 0, -93)

  P.tradeButton = W.Button(f, L("pay.trade"), function() P.trade() end)
  P.tradeButton:SetSize(BTN_W, 26)
  P.tradeButton:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -108)
  P.tradeLine = line(f, "ui", 12, LINE_W)
  P.tradeLine:SetPoint("TOPLEFT", P.tradeButton, "TOPRIGHT", 12, 0)
  P.tradeType = line(f, "ui", 12, LINE_W)
  P.tradeType:SetTextColor(Theme.rgb("gold"))
  P.tradeType:SetPoint("TOPLEFT", P.tradeLine, "BOTTOMLEFT", 0, -4)

  P.mailButton = W.Button(f, L("pay.mail"), function() P.mail() end)
  P.mailButton:SetSize(BTN_W, 26)
  P.mailButton:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -190)
  P.mailLine = line(f, "ui", 12, LINE_W)
  P.mailLine:SetPoint("TOPLEFT", P.mailButton, "TOPRIGHT", 12, 0)

  P.fee = line(f, "dim", 11, DLG_W - 48)
  P.fee:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -256)
  P.hold = line(f, "dim", 11, DLG_W - 48)
  P.hold:SetText(L("pay.hold"))
  P.hold:SetPoint("TOPLEFT", P.fee, "BOTTOMLEFT", 0, -6)

  local since = 0
  f:SetScript("OnUpdate", function(_, elapsed)
    since = since + (elapsed or 0)
    if since < REDRAW then return end
    since = 0
    P.render()
  end)
  f:SetScript("OnHide", function() P.name, P.typed = nil, false end)
  f:Hide()
end

-- The trade way: its line, and whether „Трейд“ is enabled.
local function tradeWay(o, who, short)
  if o.trade == "ok" then
    if short > 0 then return L("pay.short", money(short)), false end
    return L("pay.trade.text", who), true
  end
  if o.trade == "far" then return L("pay.trade.far", who), false end
  if o.trade == "none" then return L("pay.trade.none", who), false end
  return L("pay.off", who), false
end

-- The mail way; nil line when both ways are off (the trade line says it once).
local function mailWay(o, who)
  if o.mail == "open" then
    if o.short > 0 then return L("pay.short", money(o.short)), false end
    return L("pay.mail.text"), true
  end
  if o.mail == "closed" then return L("pay.mail.closed"), false end
  return o.trade ~= "off" and L("pay.off", who) or nil, false
end

-- Redraws the open dialog; closes it when nothing is owed any more.
function P.render()
  local client, name = ns.client, P.name
  if not (P.frame and P.frame:IsShown() and name and client and client.pay) then return end
  local pay = client.pay
  local c = pay:owed(name)
  if c == 0 then return P.frame:Hide() end
  local o, who = pay:options(name), W.colored(client, name, name)
  local left, g = pay:left(name), pay:guard(name) -- what has not left me yet; what has, unrecorded
  P.to:SetText(L("pay.to", who))
  P.amount:SetText(money(left > 0 and left or c))
  P.sent:SetShown(g ~= nil)
  if g then
    local t = (client.env.date or ns.Pay.utc)(g.at)
    P.sent:SetText(L("pay.sent", money(g.c), string.format("%02d.%02d", t.d, t.m)))
  end
  local text, on = tradeWay(o, who, math.max(0, o.short - o.fee))
  if left == 0 then text, on = L("pay.sent.all"), false end
  P.tradeLine:SetText(text)
  enable(P.tradeButton, on)
  P.tradeType:SetText(L("pay.trade.type", money(left)))
  P.tradeType:SetShown(P.typed and left > 0)
  text, on = mailWay(o, who)
  if left == 0 then text, on = nil, false end
  P.mailLine:SetText(text or "")
  P.mailLine:SetShown(text ~= nil)
  enable(P.mailButton, on)
  P.fee:SetText(L("pay.fee", money(o.fee)))
end

-- „Трейд“: opens the trade with the amount (the player presses „Trade“).
function P.trade()
  local client = ns.client
  if not (client and client.pay and P.name) then return end
  if client.pay:byTrade(P.name) then P.typed = true end
  P.render()
  ns.Hall.refresh()
end

-- „Поща“: fills the letter (the player presses „Send“).
function P.mail()
  local client = ns.client
  if not (client and client.pay and P.name) then return end
  client.pay:byMail(P.name)
  P.render()
  ns.Hall.refresh()
end

-- The dialog for paying `name` what I owe it.
function P.open(name)
  if not P.frame then build() end
  if P.frame:IsShown() and P.name ~= name then P.frame:Hide() end
  P.name = name
  P.frame:Show()
  P.frame:Raise()
  P.render()
end

ns.ready(function(client)
  client:on("ledger", P.render)
  client:on("paySent", P.render)
end)
