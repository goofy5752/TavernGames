local Sim = require("sim")
local ns = Sim.ns
local Ledger, View, Pay, U = ns.Ledger, ns.LedgerView, ns.Pay, ns.Util

local I, M, P = "Иван Петров", "Мария Колева", "Петър Иванов"
local MS = "Мария Стоянова"
local EPOCH0 = 1700000000
local G5 = 50000 -- 5g
local TAGGED = "Tavern Games: Морски шах 14.11"

local gids = 0
-- f's own D (confirmed by its own word): f owes t c for a game g.
local function owe(sim, f, t, c, g)
  gids = gids + 1
  local e = sim.clients[f].ledgerNet:make("D", { gid = "T#1/" .. gids, g = g or "ttt", f = f, t = t, c = c, why = "lost" })
  sim:run(2)
  return e
end

-- И and М in the guild, past the login queue; М (opts mo) owes И 5g, confirmed.
local function setup(mo, more)
  ns.Locale.set("bg")
  local sim = Sim.new()
  mo = mo or { near = { I }, mailbox = true }
  local i, m = sim:add(I), sim:add(M, mo)
  for _, name in ipairs(more or {}) do sim:add(name) end
  sim:run(1)
  sim:settle()
  owe(sim, M, I, G5)
  return sim, i, m, mo
end

-- The PAY messages `from` sent after sim.sent[mark].
local function pays(sim, from, mark)
  local out = {}
  for j, s in ipairs(sim.sent) do
    if j > mark and s.from == from and s.msg.t == "PAY" then out[#out + 1] = s end
  end
  return out
end

-- The P entries `client` authored.
local function ps(client)
  local out = {}
  for _, b in ipairs(client.ledger:above(client.env.me, 0)) do if b.k == "P" then out[#out + 1] = b end end
  return out
end

local function net(client, a, b) return View.net(View.of(client.ledger), a, b) end

local function record(client, event)
  local list = {}
  client:on(event, function(...) list[#list + 1] = { ... } end)
  return list
end

-- The questions without their ids.
local function asks(client)
  local out = {}
  for j, q in ipairs(client.pay:asks()) do
    out[j] = U.copy(q)
    out[j].id = nil
  end
  return out
end

-- М pays И by trade and И's client sees the trade complete.
local function trade(sim, i, m, gave, got, items)
  eq(m.pay:byTrade(I), true)
  sim:run(0)
  i.pay:traded({ name = M, gave = gave, got = got, items = items or false })
  sim:run(2)
end

describe("pay: the two sides of a debt", function()
  it("owed and due are the two sides of the net", function()
    local _, i, m = setup()
    eq(i.pay:due(M), G5); eq(i.pay:owed(M), 0)
    eq(m.pay:owed(I), G5); eq(m.pay:due(I), 0)
    eq(i.pay:due(P), 0); eq(i.pay:owed(P), 0)
  end)
end)

describe("pay: by trade", function()
  it("byTrade announces the payment and opens the trade for the net", function()
    local sim, i, m = setup()
    local mark = #sim.sent
    eq(m.pay:waiting(I), false)
    eq(m.pay:byTrade(I), true)
    sim:run(0)
    eq(sim.trades, { { from = M, name = I, c = G5 } })
    local l = pays(sim, M, mark)
    eq(#l, 1); eq(l[1].channel, "WHISPER"); eq(l[1].target, I)
    eq(l[1].msg.c, G5); eq(l[1].msg.how, "trade")
    eq(m.pay:waiting(I), true)
    eq(#ps(i), 0); eq(#ps(m), 0) -- an announcement records nothing
  end)

  it("byTrade: far, nothing owed, not enough gold, no API", function()
    local sim, i, m, mo = setup({ near = {} })
    local mark = #sim.sent
    eq({ m.pay:byTrade(I) }, { nil, "far" })
    eq(m.pay:options(I).trade, "far")
    local state = m.env.trade.state
    m.env.trade.state = function() return "none" end -- no unit of И: not targeted, not grouped
    eq({ m.pay:byTrade(I) }, { nil, "nounit" })
    eq(m.pay:options(I).trade, "none")
    m.env.trade.state = state
    mo.near = { I }
    eq({ i.pay:byTrade(M) }, { nil, "none" }) -- И owes М nothing
    mo.money = 49999
    eq({ m.pay:byTrade(I) }, { nil, "short" })
    mo.money = nil
    local trade = m.env.trade
    m.env.trade = nil
    eq({ m.pay:byTrade(I) }, { nil, "off" })
    eq(m.pay:options(I).trade, "off")
    m.env.trade = trade
    sim:run(1)
    eq(sim.trades, {}); eq(#pays(sim, M, mark), 0); eq(m.pay:waiting(I), false)
  end)

  it("a finished trade after a PAY records the payment", function()
    local sim, i, m = setup()
    trade(sim, i, m, 0, G5)
    local l = ps(i)
    eq(#l, 1); eq(l[1].f, M); eq(l[1].c, G5); eq(l[1].how, "trade")
    eq(net(i, M, I), 0); eq(net(m, M, I), 0)
    eq(i.pay:due(M), 0); eq(m.pay:owed(I), 0)
    eq(m.pay:waiting(I), false)
    eq(i.pay:asks(), {})
  end)

  it("more gold than owed records only the debt", function()
    local sim, i, m = setup()
    trade(sim, i, m, 0, 80000)
    eq(#ps(i), 1); eq(ps(i)[1].c, G5)
    eq(net(m, M, I), 0)
  end)

  it("less gold than owed is a part payment", function()
    local sim, i, m = setup()
    trade(sim, i, m, 0, 20000)
    eq(#ps(i), 1); eq(ps(i)[1].c, 20000)
    eq(m.pay:owed(I), 30000); eq(i.pay:due(M), 30000)
    eq(m.pay:waiting(I), false)
  end)

  it("gold both ways counts the difference", function()
    local sim, i, m = setup()
    trade(sim, i, m, 10000, 30000)
    eq(#ps(i), 1); eq(ps(i)[1].c, 20000)
    trade(sim, i, m, 30000, 30000)
    trade(sim, i, m, 30000, 10000)
    eq(#ps(i), 1); eq(i.pay:asks(), {})
    eq(m.pay:owed(I), 30000)
  end)

  it("gold without a PAY is put to me", function()
    local sim, i, m = setup()
    local seen = record(i, "payAsk")
    i.pay:traded({ name = M, gave = 0, got = G5, items = false })
    sim:run(2)
    eq(#ps(i), 0); eq(net(i, M, I), G5)
    eq(asks(i), { { name = M, c = G5, how = "trade" } })
    eq(#seen, 1)
    local id = i.pay:asks()[1].id
    eq(i.pay:answer(id, P), nil) -- not a name of that question
    eq(i.pay:answer(id, M), true)
    eq(#seen, 2); eq(i.pay:asks(), {})
    eq(#ps(i), 1); eq(ps(i)[1].f, M); eq(ps(i)[1].c, G5); eq(ps(i)[1].how, "trade")
    eq(i.pay:answer(id, M), nil) -- answered already
    sim:run(2)
    eq(net(m, M, I), 0)
    owe(sim, M, I, G5)
    i.pay:traded({ name = M, gave = 0, got = G5, items = false })
    id = i.pay:asks()[1].id
    eq(i.pay:answer(id, false), true)
    eq(#ps(i), 1); eq(i.pay:asks(), {}); eq(#seen, 4)
    eq(net(i, M, I), G5)
  end)

  it("a PAY older than 300 s does not count", function()
    local sim, i, m = setup()
    eq(m.pay:byTrade(I), true)
    sim:run(0)
    sim:run(301)
    i.pay:traded({ name = M, gave = 0, got = G5, items = false })
    eq(#ps(i), 0); eq(asks(i), { { name = M, c = G5, how = "trade" } })
    -- within the window it counts
    local sim2, i2, m2 = setup()
    eq(m2.pay:byTrade(I), true)
    sim2:run(0)
    sim2:run(300)
    i2.pay:traded({ name = M, gave = 0, got = G5, items = false })
    eq(#ps(i2), 1); eq(i2.pay:asks(), {})
  end)

  it("one PAY completes one trade; the next one is put to me", function()
    local sim, i, m = setup()
    trade(sim, i, m, 0, 20000)
    i.pay:traded({ name = M, gave = 0, got = 20000, items = false })
    eq(#ps(i), 1); eq(asks(i), { { name = M, c = 20000, how = "trade" } })
  end)

  it("a trade with an item is put to me, never recorded", function()
    local sim, i, m = setup()
    trade(sim, i, m, 0, G5, true)
    eq(#ps(i), 0); eq(net(i, M, I), G5)
    eq(asks(i), { { name = M, c = G5, how = "trade" } })
  end)

  it("a trade that does not say whether an item changed hands is put to me", function()
    local sim, i, m = setup()
    eq(m.pay:byTrade(I), true)
    sim:run(0)
    i.pay:traded({ name = M, gave = 0, got = G5 })
    eq(#ps(i), 0); eq(asks(i), { { name = M, c = G5, how = "trade" } })
  end)

  it("a PAY from a peer listed as incompatible is ignored", function()
    local sim, i, m = setup()
    i.presence:incompatible(M)
    eq(m.pay:byTrade(I), true)
    sim:run(0)
    i.pay:traded({ name = M, gave = 0, got = G5, items = false })
    eq(#ps(i), 0); eq(#i.pay:asks(), 1)
  end)

  it("gold from somebody who owes me nothing is ignored", function()
    local sim, i = setup(nil, { P })
    local seen = record(i, "payAsk")
    i.pay:traded({ name = P, gave = 0, got = G5, items = false })
    i.pay:traded({ name = "Някой Непознат", gave = 0, got = G5, items = false })
    sim:run(2)
    eq(#ps(i), 0); eq(i.pay:asks(), {}); eq(#seen, 0)
  end)

  it("only the creditor records", function()
    local sim, i, m = setup()
    eq(m.pay:byTrade(I), true)
    sim:run(0)
    m.pay:traded({ name = I, gave = G5, got = 0, items = false })
    m.pay:traded({ name = I, gave = 0, got = G5, items = false }) -- gold from И, who owes М nothing
    eq(m.pay:settle(I), nil) -- „Уредено“ by the debtor: nothing is due to it
    sim:run(2)
    eq(#ps(m), 0); eq(m.pay:asks(), {})
    eq(#ps(i), 0); eq(net(i, M, I), G5); eq(net(m, M, I), G5)
  end)

  it("mutual debts: paying the net by trade clears both", function()
    local sim, i, m = setup()
    owe(sim, I, M, 30000)
    eq(m.pay:owed(I), 20000); eq(i.pay:due(M), 20000); eq(i.pay:owed(M), 0)
    eq(m.pay:byTrade(I), true)
    sim:run(0)
    eq(sim.trades, { { from = M, name = I, c = 20000 } })
    i.pay:traded({ name = M, gave = 0, got = 20000, items = false })
    sim:run(2)
    eq(#ps(i), 1); eq(ps(i)[1].c, 20000)
    for _, c in ipairs({ i, m }) do eq(net(c, M, I), 0); eq(net(c, I, M), 0) end
    eq(View.accounts(View.of(i.ledger), I), {}); eq(View.accounts(View.of(m.ledger), M), {})
  end)
end)

describe("pay: by mail", function()
  it("byMail fills the letter and announces it", function()
    local sim, i, m = setup()
    local mark = #sim.sent
    eq(m.pay:options(I).mail, "open")
    eq(m.pay:byMail(I), true)
    sim:run(0)
    eq(sim.mails, { { from = M, to = I, subject = TAGGED, body = ns.L("pay.mail.body"), c = G5 } })
    eq(ns.L("pay.mail.body"), "Изплатено през Tavern Games. Наздраве!")
    local l = pays(sim, M, mark)
    eq(#l, 1); eq(l[1].target, I); eq(l[1].msg.c, G5); eq(l[1].msg.how, "mail")
    eq(m.pay:waiting(I), true)
    eq(#ps(i), 0)
    -- И is not listed online: the letter is filled, no PAY
    m.presence:remove(I)
    mark = #sim.sent
    eq(m.pay:byMail(I), true)
    sim:run(0)
    eq(#sim.mails, 2); eq(#pays(sim, M, mark), 0)
  end)

  it("byMail: a closed mailbox, nothing owed, no API", function()
    local sim, i, m, mo = setup({ mailbox = false })
    eq({ m.pay:byMail(I) }, { nil, "closed" })
    eq(m.pay:options(I).mail, "closed")
    mo.mailbox = true
    eq({ i.pay:byMail(M) }, { nil, "none" })
    local mail = m.env.mail
    m.env.mail = nil
    eq({ m.pay:byMail(I) }, { nil, "off" })
    eq(m.pay:options(I).mail, "off"); eq(m.pay:options(I).fee, 30)
    m.env.mail = mail
    eq(sim.mails, {})
  end)

  it("byMail needs the fee on top", function()
    local sim, _, m, mo = setup()
    mo.money = 50029
    eq({ m.pay:byMail(I) }, { nil, "short" })
    eq(m.pay:options(I).short, 1); eq(m.pay:options(I).fee, 30)
    eq(sim.mails, {})
    mo.money = 50030
    eq(m.pay:options(I).short, 0)
    eq(m.pay:byMail(I), true)
    eq(#sim.mails, 1)
    mo.fee = 100 -- the game's own price
    eq(m.pay:options(I).short, 70); eq(m.pay:options(I).fee, 100)
    eq({ m.pay:byMail(I) }, { nil, "short" })
  end)

  it("subject: several games, newest first, cut at 64 bytes on a character boundary", function()
    ns.Locale.set("bg")
    local L = Ledger.new({}, "Наблюдател", function() return EPOCH0 + 10 * 86400 end)
    local n = 0
    local function d(f, t, c, g, at)
      n = n + 1
      eq(L:add({ i = Ledger.id(f, n), k = "D", at = at, gid = "T#1/" .. n, g = g, f = f, t = t, c = c, why = "lost" }, f), "new")
    end
    local DAY = 86400
    d(M, I, G5, "ttt", EPOCH0)               -- 14.11
    d(M, I, G5, "ttt", EPOCH0 + 2 * DAY)     -- 16.11
    d(M, I, G5, "deathroll", EPOCH0 + DAY)   -- 15.11
    d(I, M, 100, "ttt", EPOCH0 + 3 * DAY)    -- the other way: not M's
    d(M, P, G5, "ttt", EPOCH0 + 3 * DAY)     -- to somebody else
    local s = Pay.subject(View.of(L), M, I)
    eq(s, "Tavern Games: Морски шах 16.11 + Death Roll 15.11 + М")
    eq(#s, 63) -- byte 64 is the first byte of „о“
    eq(Pay.TAG, "Tavern Games:")
    -- one game; a cleared debt is not in it
    local L2 = Ledger.new({}, "Наблюдател", function() return EPOCH0 + 10 * 86400 end)
    L, n = L2, 10
    d(M, I, G5, "ttt", EPOCH0 - 3 * DAY)       -- 11.11, paid
    d(M, I, G5, "deathroll", EPOCH0)           -- 14.11
    eq(L:add({ i = Ledger.id(I, 1), k = "P", at = EPOCH0, f = M, c = G5, how = "hand" }, I), "new")
    eq(Pay.subject(View.of(L), M, I), "Tavern Games: Death Roll 14.11")
    eq(Pay.subject(View.of(L), M, P), "Tavern Games:")
  end)

  it("the UTC date of the fallback", function()
    eq(Pay.utc(EPOCH0), { d = 14, m = 11, day = 19675 })
    eq(Pay.utc(0), { d = 1, m = 1, day = 0 })
    eq(Pay.utc(951782400), { d = 29, m = 2, day = 11016 })  -- 2000-02-29
    eq(Pay.utc(1709251199).d, 29)                           -- 2024-02-29 23:59:59
    eq(Pay.utc(1709251200), { d = 1, m = 3, day = 19783 }) -- 2024-03-01
    eq(Pay.utc(1735689599).m, 12)                           -- 2024-12-31 23:59:59
  end)

  it("money taken from a tagged letter of my one debtor records the payment", function()
    local sim, i, m = setup()
    i.pay:mailed({ shown = M, subject = TAGGED, c = G5 })
    eq(#ps(i), 1); eq(ps(i)[1].f, M); eq(ps(i)[1].c, G5); eq(ps(i)[1].how, "mail")
    sim:run(2)
    eq(net(m, M, I), 0); eq(i.pay:asks(), {})
    local _, i2 = setup()
    i2.pay:mailed({ shown = "Мария", subject = TAGGED, c = G5 }) -- first name only
    eq(#ps(i2), 1); eq(ps(i2)[1].f, M); eq(ps(i2)[1].how, "mail")
    local _, i3 = setup()
    i3.pay:mailed({ shown = "Мария Колева-Forever", subject = "Tavern Games:", c = G5 }) -- with the realm
    eq(#ps(i3), 1)
  end)

  it("a letter from a first name that fits two debtors is put to me with both", function()
    local sim, i = setup(nil, { MS })
    owe(sim, MS, I, G5)
    local seen = record(i, "payAsk")
    i.pay:mailed({ shown = "Мария", subject = TAGGED, c = G5 })
    eq(#ps(i), 0); eq(#seen, 1)
    eq(asks(i), { { names = { M, MS }, c = G5, how = "mail" } })
    local id = i.pay:asks()[1].id
    eq(i.pay:answer(id, I), nil)
    eq(i.pay:answer(id, MS), true)
    eq(#ps(i), 1); eq(ps(i)[1].f, MS); eq(ps(i)[1].c, G5); eq(ps(i)[1].how, "mail")
    eq(i.pay:due(M), G5); eq(i.pay:due(MS), 0)
    -- the full name of one of them is that one alone
    i.pay:mailed({ shown = M, subject = TAGGED, c = 20000 })
    eq(#ps(i), 2); eq(ps(i)[2].f, M); eq(ps(i)[2].c, 20000)
  end)

  it("an untagged letter from a debtor is put to me; from anybody else ignored", function()
    local _, i = setup(nil, { P })
    i.pay:mailed({ shown = "Мария", subject = "Подарък", c = G5 })
    eq(#ps(i), 0); eq(asks(i), { { name = M, c = G5, how = "mail" } })
    i.pay:mailed({ shown = P, subject = "Подарък", c = G5 })
    i.pay:mailed({ shown = "Петър", subject = TAGGED, c = G5 }) -- no full name the guild knows
    i.pay:mailed({ shown = "Аукционна къща", subject = TAGGED, c = G5 })
    i.pay:mailed({ shown = "Мария", subject = TAGGED, c = 0 })
    eq(#ps(i), 0); eq(#i.pay:asks(), 1)
    eq(i.pay:answer(i.pay:asks()[1].id, M), true)
    eq(#ps(i), 1); eq(ps(i)[1].how, "mail")
  end)

  it("a first name that fits a namesake with a pending claim is put to me (the C has not synced yet)", function()
    local sim, i = setup()
    -- my claim against „Мария Стоянова“: her C is still on its way, so it is pending on my client
    i.ledgerNet:make("D", { gid = "T#2/1", g = "ttt", f = MS, t = I, c = G5, why = "lost" })
    sim:run(2)
    eq(View.of(i.ledger).debts[2].status, "pending"); eq(i.pay:due(MS), 0)
    i.pay:mailed({ shown = "Мария", subject = TAGGED, c = G5 })
    eq(#ps(i), 0); eq(i.pay:due(M), G5)
    eq(asks(i), { { names = { M, MS }, c = G5, how = "mail" } })
    -- the full name is no namesake
    i.pay:mailed({ shown = M, subject = TAGGED, c = G5 })
    eq(#ps(i), 1); eq(ps(i)[1].f, M)
  end)

  it("a first name that fits a namesake whose debt is settled is put to me", function()
    local sim, i = setup(nil, { MS })
    owe(sim, MS, I, 20000) -- „Мария Стоянова“ owes me 2g
    eq(i.pay:settle(MS)[1].c, 20000); eq(i.pay:due(MS), 0)
    i.pay:mailed({ shown = "Мария", subject = TAGGED, c = 20000 })
    eq(#ps(i), 1); eq(i.pay:due(M), G5)
    eq(asks(i), { { names = { M, MS }, c = 20000, how = "mail" } })
    -- a name I only owe to counts as well
    local sim2, i2 = setup()
    owe(sim2, I, MS, 100)
    i2.pay:mailed({ shown = "Мария", subject = TAGGED, c = G5 })
    eq(#ps(i2), 0); eq(#i2.pay:asks(), 1)
  end)

  it("a letter with more than is owed records only the debt", function()
    local _, i = setup()
    i.pay:mailed({ shown = M, subject = TAGGED, c = 80000 })
    eq(#ps(i), 1); eq(ps(i)[1].c, G5)
    i.pay:mailed({ shown = M, subject = TAGGED, c = 80000 }) -- nothing is due any more
    eq(#ps(i), 1); eq(i.pay:asks(), {})
  end)
end)

describe("pay: gold that comes before the debt is confirmed on my client (final review I1)", function()
  -- И's claim against М is pending on И's client: М's C is held back on its way.
  local function pending(mo)
    ns.Locale.set("bg")
    local sim = Sim.new()
    local i, m = sim:add(I), sim:add(M, mo or { near = { I }, mailbox = true })
    sim:add(P)
    sim:run(1); sim:settle()
    local held = {}
    sim.bus.filter = function(from, _, _, msg)
      if from == M and msg.t == "LEV" then held[#held + 1] = msg; return {} end
      return { msg }
    end
    local d = i.ledgerNet:make("D", { gid = "T#7/7", g = "ttt", f = M, t = I, c = G5, why = "offline" })
    sim:run(3)
    eq(m.stakes:answer(m.stakes:asks()[1].key, true), true) -- М confirms; И does not hear it yet
    sim:run(3)
    eq(m.pay:owed(I), G5); eq(i.pay:due(M), 0); eq(View.of(i.ledger).debts[1].status, "pending")
    local function sync() -- the C arrives
      sim.bus.filter = nil
      for _, msg in ipairs(held) do i:receive("GUILD", M, msg) end
      sim:run(3)
    end
    return sim, i, m, sync, d, held
  end

  it("a tagged letter taken before the C has synced is recorded; the balance is right once the C syncs", function()
    local sim, i, m, sync = pending()
    local seen = record(i, "payAsk")
    i.pay:mailed({ shown = "Мария", subject = TAGGED, c = G5 })
    eq(#ps(i), 1); eq({ ps(i)[1].f, ps(i)[1].c, ps(i)[1].how }, { M, G5, "mail" }); eq(#seen, 0)
    eq(i.pay:due(M), 0); eq(net(i, M, I), 0)
    sim:run(3)
    eq(net(m, M, I), 0) -- М holds its C and И's P
    sync()
    eq(View.of(i.ledger).debts[1].status, "confirmed")
    eq(net(i, M, I), 0); eq(net(m, M, I), 0); eq(i.pay:due(M), 0); eq(m.pay:owed(I), 0)
    eq(View.rows(View.of(i.ledger))[1].open, 0)
    -- a second letter: nothing is left to pay
    i.pay:mailed({ shown = "Мария", subject = TAGGED, c = G5 })
    eq(#ps(i), 1); eq(i.pay:asks(), {})
  end)

  it("a trade announced by PAY before the C has synced is recorded; more than the claim records only the claim", function()
    local sim, i, m, sync = pending()
    eq(m.pay:byTrade(I), true); sim:run(0)
    i.pay:traded({ name = M, gave = 0, got = 80000, items = false })
    eq(#ps(i), 1); eq({ ps(i)[1].f, ps(i)[1].c, ps(i)[1].how }, { M, G5, "trade" })
    sync()
    eq(net(i, M, I), 0); eq(net(m, M, I), 0)
  end)

  it("the credit clears that debtor's debts oldest first as they are confirmed", function()
    local sim, i, m, sync, _, held = pending()
    owe(sim, M, I, 30000) -- a later debt, confirmed at once
    i:receive("GUILD", M, table.remove(held)); sim:run(1)
    eq(i.pay:due(M), 30000)
    i.pay:mailed({ shown = M, subject = TAGGED, c = G5 }) -- 5g: the room is the pending 5g and the confirmed 3g
    eq(#ps(i), 1); eq(ps(i)[1].c, G5); eq(i.pay:due(M), 0)
    sync()
    eq(i.pay:due(M), 30000); eq(net(m, M, I), 30000)
    local rows = View.rows(View.of(i.ledger))
    eq({ rows[1].debt.gid, rows[1].open }, { "T#7/7", 0 }); eq(rows[2].open, 30000) -- first in, first out
  end)

  it("untagged or unannounced gold from a name with only a pending claim is put to me, never dropped", function()
    local _, i = pending()
    i.pay:mailed({ shown = "Мария", subject = "Подарък", c = G5 })
    i.pay:traded({ name = M, gave = 0, got = G5, items = false })
    eq(#ps(i), 0)
    eq(asks(i), { { name = M, c = G5, how = "mail" }, { name = M, c = G5, how = "trade" } })
    eq(i.pay:answer(i.pay:asks()[1].id, M), true)
    eq(#ps(i), 1); eq(ps(i)[1].c, G5)
    eq(i.pay:answer(i.pay:asks()[1].id, M), true) -- nothing is left of that claim
    eq(#ps(i), 1)
  end)

  it("with no debt row at all a tagged letter or an announced trade is a question; yes records the whole as credit", function()
    ns.Locale.set("bg")
    local sim = Sim.new()
    local i, m = sim:add(I), sim:add(M)
    sim:run(1); sim:settle()
    i.pay:mailed({ shown = M, subject = TAGGED, c = G5 })
    eq(#ps(i), 0); eq(asks(i), { { name = M, c = G5, how = "mail", credit = true } })
    m:send("WHISPER", I, { v = 1, t = "PAY", c = 20000, how = "trade" }); sim:run(0)
    i.pay:traded({ name = M, gave = 0, got = 20000, items = false })
    eq(#i.pay:asks(), 2); eq(asks(i)[2], { name = M, c = 20000, how = "trade", credit = true })
    -- neither a letter that is not tagged, nor a name the guild does not know, nor a trade nobody announced
    i.pay:mailed({ shown = M, subject = "Подарък", c = G5 })
    i.pay:mailed({ shown = "Мария", subject = TAGGED, c = G5 })
    i.pay:mailed({ shown = "Аукционна къща", subject = TAGGED, c = G5 })
    i.pay:traded({ name = M, gave = 0, got = 20000, items = false })
    eq(#i.pay:asks(), 2)
    eq(i.pay:answer(i.pay:asks()[2].id, false), true)
    eq(i.pay:answer(i.pay:asks()[1].id, M), true)
    eq(#ps(i), 1); eq({ ps(i)[1].f, ps(i)[1].c, ps(i)[1].how }, { M, G5, "mail" })
    -- М's own D (its creditor never claimed) arrives later: the credit has paid it
    owe(sim, M, I, G5)
    eq(net(i, M, I), 0); eq(net(m, M, I), 0)
  end)
end)

describe("pay: „Уредено“ and „Напомни“", function()
  it("Уредено clears the whole net by hand", function()
    local sim, i, m = setup()
    local out = i.pay:settle(M)
    eq(#out, 1); eq(out[1].k, "P"); eq(out[1].f, M); eq(out[1].c, G5); eq(out[1].how, "hand")
    sim:run(2)
    eq(net(i, M, I), 0); eq(net(m, M, I), 0)
    eq(i.pay:settle(M), nil)
    eq(i.pay:settle(P), nil)
  end)

  it("a payment with copper is valid; Уредено over the cap splits", function()
    local sim, i, m = setup()
    trade(sim, i, m, 0, 1500)
    eq(#ps(i), 1); eq(ps(i)[1].c, 1500); eq(i.pay:due(M), G5 - 1500)
    local sim2, i2, m2 = setup()
    owe(sim2, M, I, 99999990000)
    owe(sim2, M, I, 49999960000)
    eq(i2.pay:due(M), 150000000000)
    local out = i2.pay:settle(M)
    eq(#out, 2); eq(out[1].c, 99999999999); eq(out[2].c, 50000000001)
    sim2:run(2)
    eq(net(i2, M, I), 0); eq(net(m2, M, I), 0)
  end)

  it("Уредено in my login queue counts at once and is made once", function()
    local sim, i, m = setup()
    i:stop()
    i = sim:relog(I)
    sim:run(1)
    eq(i.pay:settle(M), { "queued" })
    eq(i.pay:due(M), 0)
    eq(i.pay:settle(M), nil)
    i.pay:traded({ name = M, gave = 0, got = G5, items = false }) -- nothing is due any more
    eq(i.pay:asks(), {})
    sim:settle()
    sim:run(2)
    eq(#ps(i), 1); eq(ps(i)[1].c, G5); eq(ps(i)[1].how, "hand")
    eq(net(m, M, I), 0); eq(i.pay:due(M), 0)
  end)

  it("Напомни: one whisper an hour", function()
    local sim, i, m = setup()
    local seen, mine = record(m, "nudge"), record(i, "nudge")
    local mark = #sim.sent
    eq(i.pay:nudge(M), true)
    sim:run(0)
    local l = pays(sim, I, mark)
    eq(#l, 1); eq(l[1].channel, "WHISPER"); eq(l[1].target, M)
    eq(l[1].msg.c, G5); eq(l[1].msg.how, "nudge")
    eq(seen, { { I, G5 } })
    eq({ i.pay:nudge(M) }, { nil, "wait" })
    sim:run(3599)
    eq({ i.pay:nudge(M) }, { nil, "wait" })
    sim:run(1)
    eq(i.pay:nudge(M), true)
    sim:run(0)
    eq(#seen, 2)
    -- a nudge from somebody I owe nothing emits nothing
    eq({ m.pay:nudge(I) }, { nil, "none" })
    m:send("WHISPER", I, { v = 1, t = "PAY", c = G5, how = "nudge" })
    sim:run(0)
    eq(mine, {})
    eq(#ps(i), 0); eq(#ps(m), 0)
    -- a debtor that is not listed online is not whispered
    local sim2, i2 = setup()
    i2.presence:remove(M)
    mark = #sim2.sent
    eq({ i2.pay:nudge(M) }, { nil, "offline" })
    eq(#pays(sim2, I, mark), 0)
  end)

  it("a PAY from a peer that is not in presence, or with a bad c or how, is ignored", function()
    local bad = { { c = 0 }, { c = 1.5 }, { c = "50000" }, { c = 100000000000 }, { how = "hand" }, { how = 1 } }
    for _, b in ipairs(bad) do
      local sim, i, m = setup()
      local msg = { v = 1, t = "PAY", c = G5, how = "trade" }
      for k, v in pairs(b) do msg[k] = v end
      m:send("WHISPER", I, msg)
      sim:run(0)
      i.pay:traded({ name = M, gave = 0, got = G5, items = false })
      eq(#ps(i), 0, tostring(b.c) .. "/" .. tostring(b.how)); eq(#i.pay:asks(), 1)
    end
    local sim, i, m = setup()
    i.presence:remove(M)
    eq(m.pay:byTrade(I), true)
    sim:run(0)
    eq(i.presence:get(M), nil)
    i.pay:traded({ name = M, gave = 0, got = G5, items = false })
    eq(#ps(i), 0); eq(#i.pay:asks(), 1)
    -- a nudge of a peer not listed emits nothing
    local seen = record(m, "nudge")
    m.presence:remove(I)
    i.pay:nudge(M) -- not listed on И either: not sent
    i:send("WHISPER", M, { v = 1, t = "PAY", c = G5, how = "nudge" })
    sim:run(0)
    eq(seen, {})
  end)
end)
