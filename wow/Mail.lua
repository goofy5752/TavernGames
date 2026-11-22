local _, ns = ...

-- The mail side of payment: env.mail of core/Pay.lua (Mail.state, Mail.fill,
-- Mail.fee) and the report of money the player takes from a letter to
-- client.pay:mailed. The addon only fills the send-mail frame and the player
-- presses the game's own „Send“: it never calls SendMail, a COD function,
-- TakeInboxMoney or AutoLootMailItem. A letter the player sent is reported to
-- client.pay:sent once the game says it left (MAIL_SEND_SUCCESS): its
-- recipient and money as a hook after the game's SendMail saw them, else as a
-- script hooked to the game's „Send“ (SendMailMailButton) read them from the
-- send frame at the click; with neither hook, nothing (residual 27). Only a
-- letter that sends money counts: a COD letter is never a payment.
-- Every game function is looked up at call time and skipped when absent.
local C, Adapter = ns.Const, ns.Adapter
local fn, lookup, plain = Adapter.fn, Adapter.lookup, Adapter.plain

local Mail = {}
ns.Mail = Mail

local TAKE_WAIT = 10 -- s: a take the inbox has not answered within this long is forgotten (the game refused it)
local SEND_TAB = 2   -- the send tab of the mail frame

local open = false -- between MAIL_SHOW and MAIL_CLOSED
local sending      -- {to, c}: the letter the player's „Send“ handed to the game, until the game answers
local clickedNote  -- {to, c}: what the game's „Send“ saw at the click, until the game answers
local sendHooked, clickHooked = false, false

-- "open" | "closed" | "off" (the client cannot set a letter's money).
function Mail.state()
  if not (fn("SetSendMailMoney") or (fn("MoneyInputFrame_SetCopper") and lookup("SendMailMoney"))) then return "off" end
  return open and "open" or "closed"
end

-- frame:method(...) under pcall when the frame has that method -> true, its results | false.
local function call(frame, method, ...)
  if not (type(frame) == "table" and type(frame[method]) == "function") then return false end
  return pcall(frame[method], frame, ...)
end

-- Fills the send tab: recipient, subject, body (SendMailBodyEditBox or
-- MailEditBox, whichever exists), money sent (never COD) -> true | nil. It
-- never sends: the player presses the game's button.
function Mail.fill(name, subject, body, c)
  if Mail.state() ~= "open" then return nil end
  clickedNote = nil -- a new letter: a click before it sent nothing of it
  local tab = fn("MailFrameTab_OnClick")
  if tab then pcall(tab, nil, SEND_TAB) end
  if not call(lookup("SendMailNameEditBox"), "SetText", name) then return nil end
  call(lookup("SendMailSubjectEditBox"), "SetText", subject)
  call(lookup("SendMailBodyEditBox") or lookup("MailEditBox"), "SetText", body)
  -- The game's „Send“ sends the money box as money or as COD by these two buttons.
  call(lookup("SendMailSendMoneyButton"), "SetChecked", true)
  call(lookup("SendMailCODButton"), "SetChecked", false)
  -- The game's „Send“ sends what the money box shows: where the box exists, it decides.
  local show, box, set = fn("MoneyInputFrame_SetCopper"), lookup("SendMailMoney"), fn("SetSendMailMoney")
  local boxed = show and box and pcall(show, box, c)
  local direct = set and pcall(set, c)
  local done = (show and box) and boxed or not (show and box) and direct
  return done or nil
end

-- The copper the letter being sent sends: the money the game holds for it
-- (GetSendMailMoney), else what the money box shows -> c > 0 | nil. Nil for a
-- COD letter (money not checked): its box asks for gold, it sends none.
local function letterMoney()
  local okCheck, on = call(lookup("SendMailSendMoneyButton"), "GetChecked")
  if not (okCheck and on) then return nil end
  local okMoney, c = false, nil
  local money, copper, frame = fn("GetSendMailMoney"), fn("MoneyInputFrame_GetCopper"), lookup("SendMailMoney")
  if money then okMoney, c = pcall(money)
  elseif copper and frame then okMoney, c = pcall(copper, frame) end
  return okMoney and plain(c) and c > 0 and c or nil
end

-- After the game's SendMail (the player's click): the recipient, and the money the game holds for the letter.
local function sent(recipient)
  local c = letterMoney()
  sending = type(recipient) == "string" and c and { to = recipient, c = c } or nil
end

-- A script after the game's „Send“ (its OnClick): the recipient and the money
-- the send frame shows, for a client whose SendMail cannot be hooked.
local function clicked()
  local okTo, to = call(lookup("SendMailNameEditBox"), "GetText")
  local c = letterMoney()
  clickedNote = okTo and type(to) == "string" and to ~= "" and c and { to = to, c = c } or nil
end

-- The game says a letter left: the one seen at SendMail, else the one seen at
-- the click, each used once; with neither, nothing.
local function left()
  local s = sending or clickedNote
  sending, clickedNote = nil, nil
  local client = ns.client
  if s and client and client.pay then client.pay:sent({ shown = s.to, c = s.c, how = "mail" }) end
end

-- The copper the post takes for one letter: the game's price, C.MAIL_FEE without it.
function Mail.fee()
  local price = fn("GetSendMailPrice")
  local okPrice, c = false, nil
  if price then okPrice, c = pcall(price) end
  if okPrice and plain(c) then return c end
  return C.MAIL_FEE
end

-- The inbox as the last MAIL_INBOX_UPDATE showed it: rows[i] = {sender, subject,
-- money, returned} or false (unreadable); `bags` = my money at that update.
local rows, bags = {}, nil
local taken = {} -- {row, at}: the letters whose money the player took, not yet seen without it
local hooked = false -- a take function is hooked: the hook, not my bags, tells what was taken
local hooks = {}     -- name -> true: that game function is hooked (each by itself, one defined late at a later try)

local function inbox()
  local count, header = fn("GetInboxNumItems"), fn("GetInboxHeaderInfo", "C_Mail.GetInboxHeaderInfo")
  local out = {}
  if not (count and header) then return out end
  local okCount, n = pcall(count)
  if not (okCount and type(n) == "number") then return out end
  for i = 1, n do
    local okRow, _, _, sender, subject, money, _, _, _, _, returned = pcall(header, i)
    out[i] = okRow and type(sender) == "string" and plain(money)
      and { sender = sender, subject = type(subject) == "string" and subject or "", money = money, returned = returned and true or false }
  end
  return out
end

-- A letter that brings money: not one of mine returned to me.
local function brings(r) return r and r.money > 0 and not r.returned end
local function key(r) return r.sender .. "\n" .. r.subject .. "\n" .. r.money end

-- How many letters of each key bring money.
local function counts(list)
  local out = {}
  for _, r in ipairs(list) do
    if brings(r) then out[key(r)] = (out[key(r)] or 0) + 1 end
  end
  return out
end

-- The hook of TakeInboxMoney and AutoLootMailItem runs after the call, while the
-- game has not changed the row yet: it notes the row as the cache shows it.
-- Residual: several takes between two updates (another addon opening all
-- letters) can note a row by a stale index; that misses a payment, and credits
-- a wrong one only when a letter of the noted key is returned within TAKE_WAIT s.
local function took(i)
  local r = rows[i]
  if brings(r) then taken[#taken + 1] = { row = r, at = GetTime() } end
end

local function hook()
  -- A frame script hook needs no hooksecurefunc; the button is looked up now, as the mail UI may load late.
  local button = not clickHooked and lookup("SendMailMailButton")
  if button and call(button, "HookScript", "OnClick", clicked) then clickHooked = true end
  local secure = fn("hooksecurefunc")
  if secure and not sendHooked and fn("SendMail") and pcall(secure, "SendMail", sent) then sendHooked = true end
  if not secure then return end
  for _, name in ipairs({ "TakeInboxMoney", "AutoLootMailItem" }) do
    if not hooks[name] and fn(name) and pcall(secure, name, took) then hooks[name], hooked = true, true end
  end
end

local function report(r)
  local client = ns.client
  if client and client.pay then client.pay:mailed({ shown = r.sender, subject = r.subject, c = r.money }) end
end

-- Each letter that brings money is reported once, when an update shows it
-- without money or gone: with the hook, a letter the player took; without it,
-- the letters that lost their money while my bags rose by exactly their sum.
local function update()
  local now, money = inbox(), Adapter.money()
  local before, after, lost = counts(rows), counts(now), {}
  for k, n in pairs(before) do
    if n > (after[k] or 0) then lost[k] = n - (after[k] or 0) end
  end
  if hooked then
    local keep, t = {}, GetTime()
    for _, m in ipairs(taken) do
      local k = key(m.row)
      if t - m.at > TAKE_WAIT then
        -- refused by the game: forgotten
      elseif lost[k] then
        lost[k] = lost[k] > 1 and lost[k] - 1 or nil
        report(m.row)
      else
        keep[#keep + 1] = m
      end
    end
    taken = keep
  elseif bags and money then
    local sum, gone = 0, {}
    for _, r in ipairs(rows) do
      local k = brings(r) and key(r)
      if k and lost[k] then
        lost[k] = lost[k] > 1 and lost[k] - 1 or nil
        sum, gone[#gone + 1] = sum + r.money, r
      end
    end
    if sum > 0 and money - bags == sum then
      for _, r in ipairs(gone) do report(r) end
    end
  end
  rows, bags = now, money
end

-- At load, so that a mail addon that copies TakeInboxMoney later still goes
-- through the hook; again at the mailbox for a client that defines it late.
hook()

local EVENTS = {
  MAIL_SHOW = function()
    open = true
    hook()
  end,
  MAIL_CLOSED = function() open, clickedNote = false, nil end,
  MAIL_SEND_SUCCESS = left,
  MAIL_FAILED = function() sending, clickedNote = nil, nil end,
  MAIL_INBOX_UPDATE = function()
    hook()
    update()
  end,
}

local frame = CreateFrame("Frame")
-- A client that does not know an event refuses to register it: left out.
for event in pairs(EVENTS) do pcall(frame.RegisterEvent, frame, event) end
frame:SetScript("OnEvent", function(_, event, ...) EVENTS[event](...) end)
