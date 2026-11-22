local Wow = require("wow")

-- The hall column „Сметки“ (ui/Accounts.lua) and the payment dialog
-- „Плащане“ (ui/PayDialog.lua): my nets, the questions put to me, „Плати“,
-- „Напомни“, „Уредено“, trade and mail.
local ME, B, C, D = "Иван Петров", "Мария Стоянова", "Тодор Ангелов", "Дара Колева"
local K = "Мария Колева"

-- In a guild, booted with the ui/ files, my login queue closed, the hall shown, gold in my bags.
local function readyWow()
  local w = Wow.new{ ui = true }
  w.inGuild = true
  w.roster = { { name = ME .. "-Forever", online = true, guid = Wow.GUID } }
  w:boot()
  w:firstRunDone()
  w:fire("GUILD_ROSTER_UPDATE")
  w:fire("PLAYER_LOGIN")
  w:advance(w.ns.Const.LEDGER_ADOPT_WAIT + 1)
  w.money = 1000000000
  w.ns.MainWindow.show()
  w:advance(0)
  return w
end

-- `text` without inline colour codes.
local function plain(text) return (tostring(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

local function settle(w)
  w:advance(1)
  w:advance(0)
end

-- A real player says HI (with a GUID) so Presence knows him.
local function hello(w, name)
  w:member(name)
  w:deliver("GUILD", name, { v = 1, t = "HI", ver = "0.1.0", cls = "PRIEST", id = "Player-1-" .. name })
  w:advance(0)
end

local counters = {}
-- `author`'s entry of kind k, delivered live by GUILD (the author is the sender).
local function lev(w, author, k, fields)
  w:member(author)
  counters[w] = counters[w] or {}
  local n = (counters[w][author] or 0) + 1
  counters[w][author] = n
  local e = { i = author .. ":" .. n, k = k, at = w.G.GetServerTime() }
  for key, value in pairs(fields) do e[key] = value end
  w:deliver("GUILD", author, { v = 1, t = "LEV", ev = { e } })
  settle(w)
  return e
end

local games = 0
local function gid() games = games + 1; return "Мария Стоянова#1/" .. games end

-- `f` owes `t` c copper, confirmed: f's own D (f is not me), or mine.
local function debt(w, f, t, c, why)
  local fields = { gid = gid(), g = "ttt", f = f, t = t, c = c, why = why or "lost" }
  if f == ME then
    local e = w.ns.client.ledgerNet:make("D", fields)
    settle(w)
    return e
  end
  return lev(w, f, "D", fields)
end

local function V(w) return w.ns.Hall.view end
local function A(w) return V(w).accounts end

-- The visible rows of the column, as {text, sub, buttons = {label...}}.
local function shown(w)
  local out = {}
  for _, r in ipairs(A(w).rows) do
    if r.frame:IsVisible() then
      local labels = {}
      for _, b in ipairs(r.buttons) do if b:IsVisible() then labels[#labels + 1] = plain(b.text:GetText()) end end
      out[#out + 1] = { text = r.text:IsVisible() and plain(r.text:GetText()) or nil, sub = r.sub:IsVisible() and plain(r.sub:GetText()) or nil, buttons = labels }
    end
  end
  return out
end

-- The visible button of the column labelled `label` (in row `i` when given).
local function button(w, label, i)
  for j, r in ipairs(A(w).rows) do
    if r.frame:IsVisible() and (i == nil or i == j) then
      for _, b in ipairs(r.buttons) do
        if b:IsVisible() and plain(b.text:GetText()) == label then return b end
      end
    end
  end
  error("no button " .. label)
end

local function kinds(w)
  local out = {}
  for _, r in ipairs(w.ns.Accounts.rows(w.ns.client)) do out[#out + 1] = r.kind end
  return out
end

-- Calls to obj:method are recorded in the returned list, then made as before.
local function spy(obj, method)
  local calls, orig = {}, obj[method]
  obj[method] = function(self, ...)
    calls[#calls + 1] = { ... }
    return orig(self, ...)
  end
  return calls
end

local function ddmm(at)
  local t = os.date("!*t", at)
  return string.format("%02d.%02d", t.day, t.month)
end

describe("ui: the hall column „Сметки“", function()
  it("no accounts: the empty line", function()
    local w = readyWow()
    local L = w.ns.L
    eq(L("accounts.title"), "Сметки")
    ok(A(w).title:IsVisible(), "no header"); eq(A(w).title:GetText(), "Сметки")
    ok(A(w).empty:IsVisible(), "no empty line"); eq(A(w).empty:GetText(), "Нямаш сметки.")
    eq(#shown(w), 0)
    eq(w.ns.Accounts.rows(w.ns.client), {})
  end)

  it("I owe: the row and „Плати“", function()
    local w = readyWow()
    debt(w, ME, B, 50000)
    eq(shown(w), { { text = "Дължиш на Мария Стоянова 5g", buttons = { "Плати" } } })
    eq(A(w).empty:IsVisible(), false)
  end)

  it("I am owed: the row with „Напомни“ and „Уредено“", function()
    local w = readyWow()
    debt(w, B, ME, 50000)
    eq(shown(w), { { text = "Мария Стоянова ти дължи 5g", buttons = { "Напомни", "Уредено" } } })
  end)

  it("rows are the nets, one per person, questions first", function()
    local w = readyWow()
    debt(w, ME, B, 50000); debt(w, ME, B, 30000); debt(w, B, ME, 20000)
    debt(w, C, ME, 20000)
    lev(w, D, "D", { gid = gid(), g = "ttt", f = ME, t = D, c = 30000, why = "lost" }) -- her claim, put to me
    eq(kinds(w), { "ask", "owe", "owed" })
    local rows = w.ns.Accounts.rows(w.ns.client)
    eq({ rows[2].name, rows[2].c }, { B, 60000 })
    eq({ rows[3].name, rows[3].c }, { C, 20000 })
    local list = shown(w)
    eq(#list, 3)
    eq(list[2].text, "Дължиш на Мария Стоянова 6g")
    eq(list[3].text, "Тодор Ангелов ти дължи 2g")
  end)

  it("the column follows the ledger without a reload", function()
    local w = readyWow()
    eq(#shown(w), 0)
    debt(w, B, ME, 50000)
    eq(#shown(w), 1)
    debt(w, B, ME, 10000)
    eq(shown(w)[1].text, "Мария Стоянова ти дължи 6g")
  end)

  it("the column header and the payment dialog carry an ⓘ", function()
    local w = readyWow()
    local info = A(w).info
    ok(info:IsVisible(), "no ⓘ on „Сметки“"); eq(info.topic, "ledger")
    w:click(info)
    ok(w.ns.HelpBook.frame:IsVisible(), "the book did not open")
    w.ns.HelpBook.frame:Hide()
    debt(w, ME, B, 50000)
    w:click(button(w, "Плати"))
    local P = w.ns.PayDialog
    ok(P.info:IsVisible(), "no ⓘ on „Плащане“"); eq(P.info.topic, "ledger")
  end)

  it("the peers list still shows below the accounts and scrolls", function()
    local w = readyWow()
    local v, Hall = V(w), w.ns.Hall
    local panel, peers = A(w).panel, v.peerPanel
    local colH = w.ns.MainWindow.BODY_H - 22
    eq(panel:GetHeight(), 190); eq(panel:GetWidth(), Hall.RIGHT_W)
    eq(peers:GetHeight(), colH - 190 - 10); eq(peers:GetWidth(), Hall.RIGHT_W)
    local p1, a1 = peers.points[1], panel.points[1]
    eq({ p1[1], p1[3], p1[4], p1[5] }, { "TOPLEFT", "TOPLEFT", a1[4], -200 })
    eq({ a1[1], a1[3], a1[5] }, { "TOPLEFT", "TOPLEFT", 0 })
    for i = 1, 20 do hello(w, "Гост" .. i .. " Тестов") end
    w:advance(0)
    local n = 0
    for _, r in ipairs(v.peers) do if r.frame:IsVisible() then n = n + 1 end end
    eq(n, 20)
    eq(v.peerScroll.content:GetHeight(), 20 * 20)
    eq(v.peers[1].frame.points[1][5], 0)
  end)
end)

describe("ui: the questions of „Сметки“", function()
  it("a debt question has two buttons and they answer it", function()
    local w = readyWow()
    local client = w.ns.client
    local claim = lev(w, D, "D", { gid = gid(), g = "ttt", f = ME, t = D, c = 30000, why = "lost" })
    local rows = w.ns.Accounts.rows(client)
    eq(#rows, 1); eq(rows[1].kind, "ask")
    local list = shown(w)
    eq(list[1].text, "Дара Колева казва, че му дължиш 3g от Морски шах (" .. ddmm(claim.at) .. "). Не видях цялата игра.")
    eq(list[1].buttons, { "Потвърждавам", "Оспорвам" })
    local calls = spy(client.stakes, "answer")
    w:click(button(w, "Потвърждавам"))
    eq(calls, { { rows[1].debt.key, true } })
    settle(w)
    eq(kinds(w), { "owe" })
    eq(shown(w)[1].text, "Дължиш на Дара Колева 3g")

    -- „Оспорвам“: false, and the debt stays out of my balance.
    local w2 = readyWow()
    lev(w2, D, "D", { gid = gid(), g = "ttt", f = ME, t = D, c = 30000, why = "lost" })
    local calls2 = spy(w2.ns.client.stakes, "answer")
    w2:click(button(w2, "Оспорвам"))
    eq(#calls2, 1); eq(calls2[1][2], false)
    settle(w2)
    eq(kinds(w2), {}); eq(#shown(w2), 0)
  end)

  it("a forfeit says I left; a clean note's game says nothing more; an unseen one says so", function()
    local w = readyWow()
    local claim = lev(w, D, "D", { gid = gid(), g = "deathroll", f = ME, t = D, c = 10000, why = "left" })
    eq(shown(w)[1].text, "Дара Колева казва, че му дължиш 1g от Death Roll (" .. ddmm(claim.at) .. "). Напуснал си масата и губиш служебно.")

    local w2 = readyWow()
    local g, now = gid(), w2.G.GetServerTime()
    local tid, q = g:match("^(.*)/(%d+)$")
    w2.ns.client.stakes:seen(true)[g] = { at = now, g = "ttt", sk = 30000, pairs = { { f = ME, t = D, c = 30000 } }, why = "lost",
                                          foul = "unseen", tid = tid, q = tonumber(q) }
    local c2 = lev(w2, D, "D", { gid = g, g = "ttt", f = ME, t = D, c = 30000, why = "lost" })
    eq(shown(w2)[1].text, "Дара Колева казва, че му дължиш 3g от Морски шах (" .. ddmm(c2.at) .. "). Не видях цялата игра.")

    -- My own „Стани“ in a game my client holds a foul of is put to me, and the line says why (final review C1).
    for foul, tail in pairs({ forged = " Аддонът ти видя нередност в тази игра.", unseen = " Не видях цялата игра." }) do
      local w3 = readyWow()
      local g3, now3 = gid(), w3.G.GetServerTime()
      local tid3, q3 = g3:match("^(.*)/(%d+)$")
      w3.ns.client.stakes:seen(true)[g3] = { at = now3, g = "ttt", sk = 30000, pairs = { { f = ME, t = D, c = 30000 } }, why = "left",
                                             foul = foul, tid = tid3, q = tonumber(q3) }
      w3.ns.client.env.db.stakeLeft = { [tid3] = { at = now3, sk = 30000, names = { D }, q = tonumber(q3), used = {} } }
      local c3 = lev(w3, D, "D", { gid = g3, g = "ttt", f = ME, t = D, c = 30000, why = "left" })
      eq(shown(w3)[1].text, "Дара Колева казва, че му дължиш 3g от Морски шах (" .. ddmm(c3.at) .. "). Напуснал си масата и губиш служебно." .. tail)
    end
  end)

  it("the own-entries question: one „Мои са“ / „Не са мои“ per entry, each answering its own body", function()
    local w = readyWow()
    local client, net = w.ns.client, w.ns.client.ledgerNet
    debt(w, B, ME, 50000)
    debt(w, C, ME, 20000)
    hello(w, B)
    -- My real P of a session that crashed before its logout, and a forged one, both relayed back by Мария.
    local now = w.G.GetServerTime()
    eq(net:take({ i = ME .. ":1", k = "P", at = now, f = B, c = 50000, how = "trade" }, B), "new")
    eq(net:take({ i = ME .. ":2", k = "P", at = now, f = C, c = 20000, how = "hand" }, B), "new")
    settle(w)
    local asked = net:asks()
    eq(#asked, 2)
    eq(kinds(w), { "mine", "mine", "owed", "owed" })
    local rows = shown(w)
    eq(rows[1].text, "Тези записи на твое име не са запазени на този компютър. Твои ли са?")
    ok(rows[1].sub:find("Трейд", 1, true) and rows[1].sub:find("Мария Стоянова", 1, true) and rows[1].sub:find("5g", 1, true), rows[1].sub)
    eq(rows[1].buttons, { "Мои са", "Не са мои" })
    eq(rows[2].text, nil)
    ok(rows[2].sub:find("Уредено", 1, true) and rows[2].sub:find("Тодор Ангелов", 1, true) and rows[2].sub:find("2g", 1, true), rows[2].sub)
    eq(rows[2].buttons, { "Мои са", "Не са мои" })
    local calls = spy(net, "answer")
    w:click(button(w, "Мои са", 1))
    eq(#calls, 1); ok(calls[1][1] == asked[1], "not the first body"); eq(calls[1][2], true)
    settle(w)
    eq(kinds(w), { "mine", "owed" })
    eq(shown(w)[1].text, "Тези записи на твое име не са запазени на този компютър. Твои ли са?")
    w:click(button(w, "Не са мои", 1))
    eq(#calls, 2); ok(calls[2][1] == asked[2], "not the second body"); eq(calls[2][2], false)
    w:advance(3)
    settle(w)
    -- The net counts my P to Мария only; Тодор still owes 2g; one X went out, for :2 only.
    eq(kinds(w), { "owed" })
    eq(shown(w)[1].text, "Тодор Ангелов ти дължи 2g")
    local xs = {}
    for _, s in ipairs(w:sentOf("LEV")) do
      for _, e in ipairs(s.msg.ev or {}) do if e.k == "X" then xs[#xs + 1] = e end end
    end
    eq(#xs, 1); eq(xs[1].r, ME .. ":2"); eq(xs[1].h, asked[2].h)
  end)

  it("the own-entries question tells twins apart: each answer names its body", function()
    local w = readyWow()
    local client, net = w.ns.client, w.ns.client.ledgerNet
    hello(w, B)
    local now = w.G.GetServerTime()
    eq(net:take({ i = ME .. ":1", k = "P", at = now, f = B, c = 50000, how = "trade" }, B), "new")
    -- A twin under the same id, both put to me (as after a collision).
    local _, twin = client.ledger:add({ i = ME .. ":1", k = "P", at = now, f = B, c = 90000, how = "trade" }, B)
    twin.un = true
    client.ledger.rev = client.ledger.rev + 1
    client.events:emit("mineAsk")
    settle(w)
    eq(#net:asks(), 2); eq(kinds(w), { "mine", "mine" })
    local first = net:asks()[1]
    local row = first == twin and 1 or 2
    w:click(button(w, "Не са мои", row))
    settle(w)
    local left = net:asks()
    eq(#left, 1); ok(left[1] ~= twin, "the twin is still asked"); ok(left[1].un, "the other body was answered")
  end)

  it("the own-entries question lists what waits beyond the shown ones; \"mineAsk\" redraws the column", function()
    local w = readyWow()
    local net = w.ns.client.ledgerNet
    net.asks = function() return {}, 0 end
    eq(#shown(w), 0)
    local at = w.G.GetServerTime()
    net.asks = function() return { { i = ME .. ":7", k = "P", at = at, f = B, c = 10000, how = "hand" } }, 3 end
    w.ns.client.events:emit("mineAsk")
    w:advance(0)
    local rows = shown(w)
    eq(#rows, 2)
    eq(rows[1].text, "Тези записи на твое име не са запазени на този компютър. Твои ли са?")
    ok(rows[1].sub:find("Уредено", 1, true) and rows[1].sub:find("1g", 1, true), rows[1].sub)
    eq(rows[2], { sub = "… и още 3", buttons = {} })
  end)

  it("a denial of mine in the question says what it denies", function()
    local w = readyWow()
    local net = w.ns.client.ledgerNet
    local p = net:make("P", { f = B, c = 30000, how = "mail" })
    settle(w)
    local at = w.G.GetServerTime()
    net.asks = function() return { { i = ME .. ":9", k = "X", at = at, r = p.i, rh = p.h } }, 0 end
    w.ns.client.events:emit("mineAsk")
    w:advance(0)
    local sub = shown(w)[1].sub
    ok(sub:find("отрича: Поща", 1, true) and sub:find("Мария Стоянова", 1, true) and sub:find("3g", 1, true), sub)
  end)

  it("a payment question with one name has „Да, към сметката“ / „Не“; with several, one button per name and „Не“", function()
    local w = readyWow()
    local client = w.ns.client
    debt(w, B, ME, 50000)
    debt(w, K, ME, 50000)
    client.pay:traded{ name = B, gave = 0, got = 30000, items = true }
    settle(w)
    eq(kinds(w), { "payAsk", "owed", "owed" })
    eq(shown(w)[1].text, "Мария Стоянова ти даде 3g. Към сметката ли е?")
    eq(shown(w)[1].buttons, { "Да, към сметката", "Не" })
    local calls = spy(client.pay, "answer")
    w:click(button(w, "Да, към сметката"))
    eq(#calls, 1); eq(calls[1][2], B)
    settle(w)
    eq(kinds(w), { "owed", "owed" })
    eq(shown(w)[2].text, "Мария Стоянова ти дължи 2g")

    client.pay:mailed{ shown = "Мария", subject = "Tavern Games: Морски шах", c = 10000 }
    settle(w)
    eq(shown(w)[1].text, "От кого са тези 1g?")
    eq(shown(w)[1].buttons, { K, B, "Не" })
    w:click(button(w, K))
    eq(calls[2][2], K)
    settle(w)
    eq(kinds(w), { "owed", "owed" })
    eq(shown(w)[1].text, "Мария Колева ти дължи 4g")

    client.pay:traded{ name = B, gave = 0, got = 10000, items = true }
    settle(w)
    w:click(button(w, "Не"))
    eq(calls[3][2], false)
    settle(w)
    eq(kinds(w), { "owed", "owed" })
  end)
end)

describe("ui: „Уредено“ and „Напомни“", function()
  it("„Уредено“ asks once more before it clears", function()
    local w = readyWow()
    local client, Acc = w.ns.client, w.ns.Accounts
    debt(w, B, ME, 50000)
    local calls = spy(client.pay, "settle")
    w:click(button(w, "Уредено"))
    eq(#calls, 0)
    ok(Acc.sure:IsVisible(), "no question")
    eq(plain(Acc.sureText:GetText()), "Получи ли 5g от Мария Стоянова? Това изчиства сметката.")
    w:click(Acc.sureNo)
    eq(#calls, 0); eq(Acc.sure:IsVisible(), false)
    eq(#shown(w), 1)
    w:click(button(w, "Уредено"))
    w:click(Acc.sureYes)
    eq(calls, { { B } })
    eq(Acc.sure:IsVisible(), false)
    settle(w)
    eq(#shown(w), 0)
    local P
    client.ledger:each(function(e) if e.k == "P" then P = e end end)
    eq({ P.f, P.c, P.how }, { B, 50000, "hand" })
  end)

  it("„Уредено“ records only the amount it asked about: a debt that grew meanwhile is asked again", function()
    local w = readyWow()
    local client, Acc = w.ns.client, w.ns.Accounts
    debt(w, B, ME, 50000)
    local calls = spy(client.pay, "settle")
    w:click(button(w, "Уредено"))
    eq(plain(Acc.sureText:GetText()), "Получи ли 5g от Мария Стоянова? Това изчиства сметката.")
    debt(w, B, ME, 30000) -- her own D of another game arrives while the question is open
    w:click(Acc.sureYes)
    eq(#calls, 0)
    local paid = 0
    client.ledger:each(function(e) if e.k == "P" then paid = paid + 1 end end)
    eq(paid, 0)
    ok(Acc.sure:IsVisible(), "not asked again")
    eq(plain(Acc.sureText:GetText()), "Получи ли 8g от Мария Стоянова? Това изчиства сметката.")
    w:click(Acc.sureYes)
    eq(calls, { { B } })
    settle(w)
    local P
    client.ledger:each(function(e) if e.k == "P" then P = e end end)
    eq({ P.f, P.c }, { B, 80000 })
    eq(#shown(w), 0)
  end)

  it("„Уредено“ says what it is for: a payment the addon could not see", function()
    local w = readyWow()
    debt(w, B, ME, 50000)
    w:hover(button(w, "Уредено"))
    eq(w.G.GameTooltip.lines[1], "Уредено")
    eq(plain(w.G.GameTooltip.lines[2]), "Натисни, ако са ти платили на ръка или по начин, който аддонът не вижда.")
  end)

  it("„Напомни“ turns into „Напомнено“ for an hour; the debtor's chat frame gets nudge.say once", function()
    local w = readyWow()
    debt(w, B, ME, 50000)
    hello(w, B)
    w:click(button(w, "Напомни"))
    local pays = w:sentOf("PAY")
    eq(#pays, 1); eq(pays[1].target, B); eq({ pays[1].msg.how, pays[1].msg.c }, { "nudge", 50000 })
    w:advance(0)
    local b = button(w, "Напомнено")
    eq(b:IsEnabled(), false)
    w:advance(w.ns.Const.NUDGE_GAP - 2)
    eq(button(w, "Напомнено"):IsEnabled(), false)
    w:advance(3)
    -- Only the timer redraws now (her presence ran out long ago): „Напомни“, off while she is away.
    eq(button(w, "Напомни"):IsEnabled(), false)
    hello(w, B)
    ok(button(w, "Напомни"):IsEnabled(), "still reminded")

    -- The debtor's side.
    local d = readyWow()
    debt(d, ME, B, 50000)
    hello(d, B)
    local from = #d.chat + 1
    d:deliver("WHISPER", B, { v = 1, t = "PAY", c = 50000, how = "nudge" })
    d:advance(0)
    d:deliver("WHISPER", B, { v = 1, t = "PAY", c = 50000, how = "nudge" })
    d:advance(0)
    local said = d:chatWith("ти напомня", from)
    eq(#said, 1)
    ok(plain(said[1]):find("Мария Стоянова ти напомня: дължиш 5g.", 1, true), said[1])
  end)

  it("„Напомни“ waits for the debtor to be online", function()
    local w = readyWow()
    debt(w, B, ME, 50000)
    eq(button(w, "Напомни"):IsEnabled(), false)
    w:hover(button(w, "Напомни"))
    eq(plain(w.G.GameTooltip.lines[1]), "Мария Стоянова не е на линия с Tavern Games. Ще можеш да напомниш, когато влезе.")
    hello(w, B)
    ok(button(w, "Напомни"):IsEnabled(), "not enabled online")
  end)
end)

describe("ui: the payment dialog „Плащане“", function()
  -- I owe Мария 5g and she is online; the dialog is open.
  local function paying(money)
    local w = readyWow()
    if money then w.money = money end
    debt(w, ME, B, 50000)
    hello(w, B)
    w:click(button(w, "Плати"))
    return w, w.ns.PayDialog
  end

  local function redraw(w) w:render(1) end

  it("„Плати“ opens the dialog with the net and the two ways", function()
    local w, P = paying()
    local L = w.ns.L
    ok(P.frame:IsVisible(), "no dialog")
    eq(P.title:GetText(), "Плащане")
    eq(plain(P.to:GetText()), "на Мария Стоянова")
    eq(P.amount:GetText(), "5g")
    eq(P.tradeButton.text:GetText(), "Трейд"); eq(P.mailButton.text:GetText(), "Поща")
    -- No unit for her: target her or invite her.
    eq(P.tradeButton:IsEnabled(), false)
    eq(plain(P.tradeLine:GetText()), "Избери Мария Стоянова за цел или го покани в група.")
    -- Far.
    w.units.target = "Player-1-" .. B
    redraw(w)
    eq(P.tradeButton:IsEnabled(), false)
    eq(plain(P.tradeLine:GetText()), "Мария Стоянова не е до теб.")
    -- Next to me.
    w.near.target = true
    redraw(w)
    ok(P.tradeButton:IsEnabled(), "trade disabled")
    eq(plain(P.tradeLine:GetText()), "Отваря трейд с Мария Стоянова и попълва сумата. Ти натискаш „Trade“.")
    -- The mailbox.
    eq(P.mailButton:IsEnabled(), false)
    eq(P.mailLine:GetText(), "Отвори пощенска кутия.")
    w:fireMail("MAIL_SHOW")
    redraw(w)
    ok(P.mailButton:IsEnabled(), "mail disabled")
    eq(P.mailLine:GetText(), "Писмото е попълнено. Ти натискаш „Send“.")
    eq(w.ns.Util.money(30), "30c")
    eq(P.fee:GetText(), "Трейдът е без такса. Пощата взима 30c и писмото може да пътува до час.")
    ok(P.hold:IsVisible(), "no hold line"); eq(P.hold:GetText(), L("pay.hold"))
    w:click(P.mailButton)
    eq(w:called("MoneyInputFrame_SetCopper"), 1); eq(w.G.SendMailMoney.copper, 50000)
    eq(w.G.SendMailNameEditBox:GetText(), B)
    for _, name in ipairs({ "SendMail", "AcceptTrade", "TakeInboxMoney", "AutoLootMailItem", "SetSendMailCOD" }) do eq(w:called(name), 0, name) end
  end)

  it("not enough gold says how much is missing and disables that way (by mail the fee counts)", function()
    local w, P = paying(40000)
    w.units.target, w.near.target = "Player-1-" .. B, true
    w:fireMail("MAIL_SHOW")
    redraw(w)
    eq(P.tradeButton:IsEnabled(), false); eq(P.tradeLine:GetText(), "Не ти достигат 1g.")
    eq(P.mailButton:IsEnabled(), false); eq(P.mailLine:GetText(), "Не ти достигат 1g 30c.")
    w.money = 50010
    redraw(w)
    ok(P.tradeButton:IsEnabled(), "trade disabled with enough gold")
    eq(P.mailButton:IsEnabled(), false); eq(P.mailLine:GetText(), "Не ти достигат 20c.")
  end)

  it("a client without the API shows pay.off", function()
    local w = readyWow()
    debt(w, ME, B, 50000)
    w.ns.client.env.trade, w.ns.client.env.mail = nil, nil
    w:click(button(w, "Плати"))
    local P = w.ns.PayDialog
    eq(P.tradeButton:IsEnabled(), false); eq(P.mailButton:IsEnabled(), false)
    eq(plain(P.tradeLine:GetText()), "Този клиент не позволява това. Плати ръчно и помоли Мария Стоянова да натисне „Уредено“.")
    eq(#w:texts("Този клиент не позволява това"), 1)
  end)

  it("after „Трейд“ the row says who is to confirm, until the P arrives; the amount to type stays shown", function()
    local w, P = paying()
    w.units.target, w.near.target = "Player-1-" .. B, true
    redraw(w)
    eq(P.tradeType:IsVisible(), false)
    w:click(P.tradeButton)
    eq(w:called("InitiateTrade"), 1); eq(w:called("AcceptTrade"), 0)
    local pays = w:sentOf("PAY")
    eq(#pays, 1); eq({ pays[1].target, pays[1].msg.how, pays[1].msg.c }, { B, "trade", 50000 })
    ok(P.tradeType:IsVisible(), "no amount to type"); eq(P.tradeType:GetText(), "Впиши сумата сам: 5g.")
    w:click(P.close)
    w:advance(0)
    eq(shown(w)[1].sub, "чака Мария Стоянова да потвърди")
    lev(w, B, "P", { f = ME, c = 20000, how = "trade" })
    eq(shown(w)[1].text, "Дължиш на Мария Стоянова 3g")
    eq(shown(w)[1].sub, nil)
  end)

  it("the dialog closes when the debt is gone", function()
    local w, P = paying()
    ok(P.frame:IsVisible(), "no dialog")
    lev(w, B, "P", { f = ME, c = 20000, how = "trade" })
    ok(P.frame:IsVisible(), "closed with 3g left")
    eq(P.amount:GetText(), "3g")
    lev(w, B, "P", { f = ME, c = 30000, how = "trade" })
    eq(P.frame:IsVisible(), false)
    eq(#shown(w), 0)
  end)
end)
