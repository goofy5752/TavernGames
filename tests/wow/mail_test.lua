local Wow = require("wow")

local ME, M = "Иван Петров", "Мария Колева"
local M_GUID = "Player-1-00000002"
local SUBJECT = "Tavern Games: Морски шах 14.11"

local function guildWow(opts)
  local w = Wow.new(opts)
  w.inGuild = true
  w.roster = {
    { name = ME .. "-Forever", online = true, guid = Wow.GUID },
    { name = M .. "-Forever", online = true, guid = M_GUID },
  }
  w:boot()
  w:fire("GUILD_ROSTER_UPDATE")
  return w
end

-- What client.pay:mailed was given.
local function mailedLog(w)
  local got = {}
  w.ns.client.pay.mailed = function(_, m) got[#got + 1] = m end
  return got
end

-- At the mailbox with these inbox rows, seen by one MAIL_INBOX_UPDATE.
local function atMailbox(w, inbox)
  w.inbox = inbox
  w:fireMail("MAIL_SHOW")
  w:fireMail("MAIL_INBOX_UPDATE")
end

-- The game's answer to a take: the row loses its money and my bags gain it.
local function moneyTaken(w, i)
  w.money = w.money + w.inbox[i].money
  w.inbox[i].money = 0
  w:fireMail("MAIL_INBOX_UPDATE")
end

-- What client.pay:sent was given.
local function sentLog(w)
  local got = {}
  w.ns.client.pay.sent = function(_, m) got[#got + 1] = m end
  return got
end

describe("wow mail: a letter that left (final review I2)", function()
  it("the player's „Send“ and the game's MAIL_SEND_SUCCESS report the recipient and the money", function()
    local w = guildWow()
    local got = sentLog(w)
    w:fireMail("MAIL_SHOW")
    eq(w.ns.Mail.fill(M, SUBJECT, "Наздраве!", 50000), true)
    eq(got, {}) -- filled: nothing has left
    w:playerCalls("SendMail", M, SUBJECT, "Наздраве!")
    eq(got, {}) -- the game has not answered yet
    w:fireMail("MAIL_SEND_SUCCESS")
    eq(got, { { shown = M, c = 50000, how = "mail" } })
    w:fireMail("MAIL_SEND_SUCCESS") -- another letter, not seen through the hook: nothing
    eq(#got, 1)
    eq(w:called("SendMail"), 0) -- the addon itself never sends
    for name in pairs(w.forbidden) do eq(w:called(name), 0, name) end
  end)

  it("a letter the game refused, one without money, and one filled but never sent report nothing", function()
    local w = guildWow()
    local got = sentLog(w)
    w:fireMail("MAIL_SHOW")
    eq(w.ns.Mail.fill(M, SUBJECT, "Наздраве!", 50000), true)
    w:playerCalls("SendMail", M, SUBJECT, "Наздраве!")
    w:fireMail("MAIL_FAILED")
    w:fireMail("MAIL_SEND_SUCCESS") -- of some later letter
    eq(got, {})
    w.sendMoney = 0
    w:playerCalls("SendMail", M, "Здрасти", "")
    w:fireMail("MAIL_SEND_SUCCESS")
    eq(got, {})
    eq(w.ns.Mail.fill(M, SUBJECT, "Наздраве!", 50000), true)
    w:fireMail("MAIL_CLOSED"); w:fireMail("MAIL_SHOW")
    w:fireMail("MAIL_SEND_SUCCESS")
    eq(got, {})
  end)

  it("the player may change the letter: what is reported is what was sent", function()
    local w = guildWow()
    local got = sentLog(w)
    w:fireMail("MAIL_SHOW")
    eq(w.ns.Mail.fill(M, SUBJECT, "Наздраве!", 50000), true)
    w.sendMoney = 20000 -- the player lowered the amount; the game's „Send“ sets it
    w:playerCalls("SendMail", "Мария", SUBJECT, "Наздраве!")
    w:fireMail("MAIL_SEND_SUCCESS")
    eq(got, { { shown = "Мария", c = 20000, how = "mail" } })
  end)

  it("with neither hook nothing is guarded: the letter the addon filled is not taken on trust (residual 27)", function()
    local w = guildWow({ noHooks = true, late = { "SendMailMailButton" } }) -- no send button to hook
    local got = sentLog(w)
    w:fireMail("MAIL_SHOW")
    eq(w.ns.Mail.fill(M, SUBJECT, "Наздраве!", 50000), true)
    w:fireMail("MAIL_SEND_SUCCESS")
    eq(got, {})
    -- A send button the client makes later is hooked at the next mailbox.
    w.G.SendMailMailButton = w.late.SendMailMailButton
    w:fireMail("MAIL_CLOSED"); w:fireMail("MAIL_SHOW")
    eq(w.ns.Mail.fill(M, SUBJECT, "Наздраве!", 50000), true)
    w.G.SendMailMailButton:Click()
    w:fireMail("MAIL_SEND_SUCCESS")
    eq(got, { { shown = M, c = 50000, how = "mail" } })
    w:fireMail("MAIL_CLOSED"); w:fireMail("MAIL_SHOW")
    eq(#w.G.SendMailMailButton.hooks, 1) -- hooked once
  end)

  it("end to end: the sent letter guards my debt", function()
    local w = guildWow()
    local client = w.ns.client
    w:advance(w.ns.Const.LEDGER_ADOPT_WAIT + 1)
    client.ledgerNet:make("D", { gid = "T#1/1", g = "ttt", f = ME, t = M, c = 50000, why = "lost" })
    w:advance(3)
    eq(client.pay:owed(M), 50000); eq(client.pay:waiting(M), false)
    w.money = 1000000
    w:fireMail("MAIL_SHOW")
    eq(client.pay:byMail(M), true)
    eq(client.pay:waiting(M), false)
    w:playerCalls("SendMail", M, w.G.SendMailSubjectEditBox:GetText(), "")
    w:fireMail("MAIL_SEND_SUCCESS")
    eq(client.pay:waiting(M), true); eq(client.pay:left(M), 0)
    eq(w.G.TavernGamesDB.char[next(w.G.TavernGamesDB.char)].paySent[M].c, 50000) -- saved per character
  end)
end)

-- body(opts, order, source, label) for each click order of the game's „Send“ and
-- each way the letter's money is read (GetSendMailMoney, or the money box when
-- the client has no GetSendMailMoney); `hooks` = false: a client without hooksecurefunc.
local function eachClick(hooks, body)
  for _, order in ipairs({ "default", "hooks first" }) do
    for _, source in ipairs({ "GetSendMailMoney", "MoneyInputFrame_GetCopper" }) do
      body({ noHooks = not hooks }, order, source, order .. " / " .. source)
    end
  end
end

-- A mailbox with that click order and money source, and the log of client.pay:sent.
local function clickWow(opts, order, source)
  local w = guildWow(opts)
  w.clickOrder = order
  if source == "MoneyInputFrame_GetCopper" then w.G.GetSendMailMoney = nil end
  local got = sentLog(w)
  w:fireMail("MAIL_SHOW")
  return w, got
end

-- The addon called nothing it must never call.
local function clean(w, label)
  for name in pairs(w.forbidden) do eq(w:called(name), 0, label .. ": " .. name) end
end

describe("wow mail: the click on the game's „Send“ (residual 27)", function()
  it("without hooksecurefunc the click on Send tells what left", function()
    eachClick(false, function(opts, order, source, label)
      local w, got = clickWow(opts, order, source)
      local G = w.G
      eq(w.ns.Mail.fill(M, SUBJECT, "Наздраве!", 50000), true, label)
      G.SendMailNameEditBox:SetText("Петър") -- the player changes the letter
      G.SendMailMoney.copper = 20000
      G.SendMailMailButton:Click()
      eq(got, {}, label) -- the game has not answered yet
      w:fireMail("MAIL_SEND_SUCCESS")
      eq(got, { { shown = "Петър", c = 20000, how = "mail" } }, label)
      clean(w, label)
    end)
  end)

  it("the SendMail hook still wins, whatever the boxes say", function()
    eachClick(true, function(opts, order, source, label)
      local w, got = clickWow(opts, order, source)
      local G, hooks = w.G, w.G.SendMailMailButton.hooks
      eq(w.ns.Mail.fill(M, SUBJECT, "Наздраве!", 50000), true, label)
      -- Another addon's script on the button changes the boxes between the game's SendMail and my click hook.
      local function change()
        G.SendMailNameEditBox:SetText("Петър"); G.SendMailMoney.copper = 20000; w.sendMoney = 20000
      end
      if order == "hooks first" then hooks[#hooks + 1] = change else table.insert(hooks, 1, change) end
      G.SendMailMailButton:Click()
      w:fireMail("MAIL_SEND_SUCCESS")
      local to, c = M, 50000 -- the game sent before the change
      if order == "hooks first" then to, c = "Петър", 20000 end
      local call
      for _, x in ipairs(w.calls) do if x.name == "SendMail" and x.player then call = x end end
      eq(call.args[1], to, label)
      eq(got, { { shown = to, c = c, how = "mail" } }, label)
      clean(w, label)
    end)
  end)

  it("the click reads the money box first: the game's money is stale before its own script ran", function()
    local w = guildWow({ noHooks = true })
    w.clickOrder = "hooks first"
    local got = sentLog(w)
    w:fireMail("MAIL_SHOW")
    eq(w.ns.Mail.fill(M, SUBJECT, "Наздраве!", 50000), true)
    w.G.SendMailMoney.copper = 20000 -- the player lowers the box to 2g
    w.G.SendMailMailButton:Click()
    w:fireMail("MAIL_SEND_SUCCESS")
    eq(got, { { shown = M, c = 20000, how = "mail" } })
    clean(w, "box first")
  end)

  it("the SendMail hook needs no send-money button; only a known COD is refused", function()
    local w = guildWow()
    local got = sentLog(w)
    w:fireMail("MAIL_SHOW")
    eq(w.ns.Mail.fill(M, SUBJECT, "Наздраве!", 50000), true)
    w.G.SendMailSendMoneyButton = nil -- the client has no such button
    w.G.SendMailMailButton:Click()
    w:fireMail("MAIL_SEND_SUCCESS")
    eq(got, { { shown = M, c = 50000, how = "mail" } })
    got[1] = nil
    w.G.GetSendMailCOD = function() return 10000 end -- a known COD letter
    w.G.SendMailMailButton:Click()
    w:fireMail("MAIL_SEND_SUCCESS")
    eq(got, {})
    clean(w, "no button")
  end)

  it("a SendMail hook consumes a pending click note: it is never reported for a later letter", function()
    local w = guildWow()
    local got = sentLog(w)
    w:fireMail("MAIL_SHOW")
    eq(w.ns.Mail.fill(M, SUBJECT, "Наздраве!", 50000), true)
    -- A click whose SendMail never came (the money popup cancelled): the note stays.
    w.G.SendMailMailButton.hooks[1](w.G.SendMailMailButton)
    -- Another addon then sends a letter with no money at all; the game says it left.
    w.G.SetSendMailMoney(0)
    w.byPlayer = true
    w.G.SendMail("Петър", "x", "y")
    w.byPlayer = false
    w:fireMail("MAIL_SEND_SUCCESS")
    eq(got, {})
  end)

  it("a COD letter sets no guard", function()
    for _, hooks in ipairs({ false, true }) do
      eachClick(hooks, function(opts, order, source, label)
        local w, got = clickWow(opts, order, source)
        local G = w.G
        eq(w.ns.Mail.fill(M, SUBJECT, "Наздраве!", 50000), true, label)
        G.SendMailSendMoneyButton:SetChecked(false); G.SendMailCODButton:SetChecked(true) -- the player asks M for 5g
        G.SendMailMailButton:Click()
        w:fireMail("MAIL_SEND_SUCCESS")
        eq(got, {}, label)
        clean(w, label)
      end)
    end
  end)

  it("a failed or cancelled send leaves no note; one success uses a note once; a fill clears it", function()
    eachClick(false, function(opts, order, source, label)
      local w, got = clickWow(opts, order, source)
      local G, Mail = w.G, w.ns.Mail
      eq(Mail.fill(M, SUBJECT, "Наздраве!", 50000), true, label)
      G.SendMailMailButton:Click()
      w:fireMail("MAIL_FAILED")
      w:fireMail("MAIL_SEND_SUCCESS") -- of a letter that had no click
      eq(got, {}, label)
      G.SendMailMailButton:Click()
      w:fireMail("MAIL_CLOSED"); w:fireMail("MAIL_SHOW")
      w:fireMail("MAIL_SEND_SUCCESS")
      eq(got, {}, label)
      G.SendMailMailButton:Click()
      eq(Mail.fill(M, SUBJECT, "Наздраве!", 30000), true, label)
      w:fireMail("MAIL_SEND_SUCCESS")
      eq(got, {}, label)
      G.SendMailMailButton:Click()
      w:fireMail("MAIL_SEND_SUCCESS")
      w:fireMail("MAIL_SEND_SUCCESS") -- the next success without a click
      eq(got, { { shown = M, c = 30000, how = "mail" } }, label)
      clean(w, label)
    end)
  end)

  it("the addon still never calls SendMail: the hook only watches the player's click", function()
    eachClick(true, function(opts, order, source, label)
      local w = clickWow(opts, order, source)
      eq(w.ns.Mail.fill(M, SUBJECT, "Наздраве!", 50000), true, label)
      w.G.SendMailMailButton:Click()
      w:fireMail("MAIL_SEND_SUCCESS")
      eq(w:called("SendMail"), 0, label)
      local player = 0
      for _, x in ipairs(w.calls) do if x.name == "SendMail" and x.player then player = player + 1 end end
      eq(player, 1, label) -- the game's own button sent it
      clean(w, label)
    end)
  end)
end)

describe("wow mail: the send frame", function()
  it("state follows MAIL_SHOW and MAIL_CLOSED", function()
    local w = guildWow()
    local Mail = w.ns.Mail
    eq(Mail.state(), "closed")
    w:fireMail("MAIL_SHOW"); eq(Mail.state(), "open")
    w:fireMail("MAIL_CLOSED"); eq(Mail.state(), "closed")
    eq(w.ns.client.pay:options(M).mail, "closed")
    w.G.SetSendMailMoney, w.G.MoneyInputFrame_SetCopper = nil, nil
    eq(Mail.state(), "off")
  end)

  it("fill writes recipient, subject, body and money and sends nothing", function()
    local w = guildWow()
    local G = w.G
    G.SendMailSendMoneyButton:SetChecked(false); G.SendMailCODButton:SetChecked(true) -- COD was chosen last time
    w:fireMail("MAIL_SHOW")
    eq(w.ns.Mail.fill(M, SUBJECT, "Наздраве!", 50000), true)
    eq(w:called("MailFrameTab_OnClick"), 1); eq(w:argsOf("MailFrameTab_OnClick"), { [2] = 2 })
    eq(G.SendMailNameEditBox:GetText(), M); eq(G.SendMailSubjectEditBox:GetText(), SUBJECT)
    eq(G.SendMailBodyEditBox:GetText(), "Наздраве!")
    eq(w:argsOf("SetSendMailMoney"), { 50000 }); eq(G.SendMailMoney.copper, 50000)
    eq(G.SendMailSendMoneyButton:GetChecked(), true); eq(G.SendMailCODButton:GetChecked(), false)
    eq(w:called("SendMail"), 0); eq(w:called("SetSendMailCOD"), 0)
    for name in pairs(w.forbidden) do eq(w:called(name), 0, name) end
  end)

  it("fill uses whichever body box exists", function()
    local w = guildWow()
    w:fireMail("MAIL_SHOW")
    eq(w.ns.Mail.fill(M, SUBJECT, "тяло", 100), true)
    eq(w.G.SendMailBodyEditBox:GetText(), "тяло")
    local w2 = guildWow()
    w2.G.SendMailBodyEditBox, w2.G.MailEditBox = nil, Wow.editBox()
    w2:fireMail("MAIL_SHOW")
    eq(w2.ns.Mail.fill(M, SUBJECT, "тяло", 100), true)
    eq(w2.G.MailEditBox:GetText(), "тяло")
    -- The money box refuses the amount: the game's „Send“ would send 0, so nothing is filled.
    local w4 = guildWow()
    w4.G.MoneyInputFrame_SetCopper = function() error("no money box") end
    w4:fireMail("MAIL_SHOW")
    eq(w4.ns.Mail.fill(M, SUBJECT, "тяло", 100), nil)
    -- Without a recipient box nothing can be filled.
    local w3 = guildWow()
    w3.G.SendMailNameEditBox = nil
    w3:fireMail("MAIL_SHOW")
    eq(w3.ns.Mail.fill(M, SUBJECT, "тяло", 100), nil)
  end)

  it("fee is the game's price, 30 without it", function()
    local w = guildWow()
    eq(w.ns.Mail.fee(), 30)
    w.mailPrice = 45
    eq(w.ns.Mail.fee(), 45); eq(w.ns.client.pay:options(M).fee, 45)
    w.G.GetSendMailPrice = function() error("no mailbox") end
    eq(w.ns.Mail.fee(), 30)
    w.G.GetSendMailPrice = function() return nil end
    eq(w.ns.Mail.fee(), 30)
    w.G.GetSendMailPrice = nil
    eq(w.ns.Mail.fee(), 30)
  end)
end)

describe("wow mail: money taken from a letter", function()
  it("taking the money of a letter reports it once", function()
    local w = guildWow()
    local got = mailedLog(w)
    atMailbox(w, { { sender = "Мария", subject = SUBJECT, money = 50000 } })
    w:playerCalls("TakeInboxMoney", 1)
    eq(#got, 0)
    w:fireMail("MAIL_INBOX_UPDATE") -- the server has not answered yet: the money is still there
    eq(#got, 0)
    moneyTaken(w, 1)
    eq(got, { { shown = "Мария", subject = SUBJECT, c = 50000 } })
    w:fireMail("MAIL_INBOX_UPDATE")
    eq(#got, 1)
  end)

  it("auto-loot of a letter with money reports it too", function()
    local w = guildWow()
    local got = mailedLog(w)
    atMailbox(w, { { sender = "Мария", subject = SUBJECT, money = 50000 }, { sender = "Мария", subject = SUBJECT, money = 50000 } })
    w:playerCalls("AutoLootMailItem", 1)
    table.remove(w.inbox, 1) -- the emptied letter is gone; the other one moves up
    w.money = w.money + 50000
    w:fireMail("MAIL_INBOX_UPDATE")
    eq(got, { { shown = "Мария", subject = SUBJECT, c = 50000 } })
  end)

  it("a letter deleted with its money untaken reports nothing", function()
    local w = guildWow()
    local got = mailedLog(w)
    atMailbox(w, { { sender = "Мария", subject = SUBJECT, money = 50000 } })
    w.inbox = {} -- returned to its sender
    w:fireMail("MAIL_INBOX_UPDATE")
    eq(got, {})
  end)

  it("a letter without money reports nothing", function()
    local w = guildWow()
    local got = mailedLog(w)
    atMailbox(w, { { sender = "Мария", subject = SUBJECT, money = 0 } })
    w:playerCalls("TakeInboxMoney", 1)
    w:playerCalls("AutoLootMailItem", 1)
    w.inbox = {}
    w:fireMail("MAIL_INBOX_UPDATE")
    eq(got, {})
  end)

  it("a take the game refused is forgotten after a while", function()
    local w = guildWow()
    local got = mailedLog(w)
    atMailbox(w, { { sender = "Мария", subject = SUBJECT, money = 50000 } })
    w:playerCalls("TakeInboxMoney", 1)
    w:fireMail("MAIL_INBOX_UPDATE") -- still there: the take failed (gold cap)
    w:advance(11)
    w.inbox = {} -- later returned to its sender
    w:fireMail("MAIL_INBOX_UPDATE")
    eq(got, {})
  end)

  it("a returned letter of my own is not a payment", function()
    local w = guildWow()
    local got = mailedLog(w)
    atMailbox(w, { { sender = "Мария", subject = SUBJECT, money = 50000, returned = true } })
    w:playerCalls("TakeInboxMoney", 1)
    moneyTaken(w, 1)
    eq(got, {})
  end)

  it("without hooksecurefunc the bag money decides", function()
    local w = guildWow({ noHooks = true })
    local got = mailedLog(w)
    atMailbox(w, { { sender = "Мария", subject = SUBJECT, money = 50000 }, { sender = "Петър", subject = "Здрасти", money = 700 } })
    w:playerCalls("TakeInboxMoney", 1)
    moneyTaken(w, 1)
    eq(got, { { shown = "Мария", subject = SUBJECT, c = 50000 } })
    w:fireMail("MAIL_INBOX_UPDATE")
    eq(#got, 1)
    -- A letter that loses its money while my bags do not gain it: returned, not taken.
    w.inbox[2].money = 0
    w:fireMail("MAIL_INBOX_UPDATE")
    eq(#got, 1)
  end)

  it("the hooks are set once however often the mailbox opens", function()
    local w = guildWow()
    local got = mailedLog(w)
    atMailbox(w, { { sender = "Мария", subject = SUBJECT, money = 50000 }, { sender = "Мария", subject = SUBJECT, money = 50000 } })
    w:fireMail("MAIL_CLOSED")
    atMailbox(w, w.inbox)
    w:playerCalls("TakeInboxMoney", 1)
    moneyTaken(w, 1)
    eq(#got, 1)
    table.remove(w.inbox, 2) -- the other letter is returned to its sender
    w:fireMail("MAIL_INBOX_UPDATE")
    eq(#got, 1)
  end)

  it("each take function is hooked by itself: one the client defines late is hooked at the next mailbox (Task 10 N1)", function()
    local w = guildWow({ late = { "AutoLootMailItem" } }) -- not there when the addon loads
    local got = mailedLog(w)
    w.G.AutoLootMailItem = w.late.AutoLootMailItem -- the mail UI loads on demand
    atMailbox(w, { { sender = "Мария", subject = SUBJECT, money = 50000 }, { sender = "Петър", subject = "Здрасти", money = 700 } })
    w:playerCalls("AutoLootMailItem", 1)
    w.money = w.money + 50000; w.inbox[1].money = 0 -- another letter is returned meanwhile: the bags alone would not tell
    w.inbox[2].money = 0
    w:fireMail("MAIL_INBOX_UPDATE")
    eq(got, { { shown = "Мария", subject = SUBJECT, c = 50000 } })
  end)

  it("the hooks are set when the file loads: a take through a copy made before the mailbox opened is seen", function()
    local w = guildWow()
    local take = w.G.TakeInboxMoney -- another mail addon keeps its own copy of the function
    local got = mailedLog(w)
    atMailbox(w, { { sender = "Мария", subject = SUBJECT, money = 50000 } })
    w.byPlayer = true
    take(1)
    w.byPlayer = false
    moneyTaken(w, 1)
    eq(got, { { shown = "Мария", subject = SUBJECT, c = 50000 } })
  end)

  it("a forbidden call from a hook fails the test even inside the player's click", function()
    local w = guildWow()
    w.G.hooksecurefunc("TakeInboxMoney", function() w.G.SendMail() end)
    raises(function() w:playerCalls("TakeInboxMoney", 1) end, "called SendMail")
    eq(w:called("SendMail"), 1)
  end)

  it("the addon never takes the money itself", function()
    local w = guildWow()
    local got = mailedLog(w)
    atMailbox(w, { { sender = "Мария", subject = SUBJECT, money = 50000 } })
    w:fireMail("MAIL_CLOSED")
    w:fireMail("MAIL_SHOW")
    w:playerCalls("TakeInboxMoney", 1)
    moneyTaken(w, 1)
    eq(#got, 1)
    eq(w:called("TakeInboxMoney"), 0); eq(w:called("AutoLootMailItem"), 0)
    for name in pairs(w.forbidden) do eq(w:called(name), 0, name) end
    local player = 0
    for _, c in ipairs(w.calls) do if c.player then player = player + 1 end end
    eq(player, 1) -- the player's own click only
  end)
end)
