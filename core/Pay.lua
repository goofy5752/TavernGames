local _, ns = ...

-- Payment (spec 5.4): client.pay. The addon never moves gold: it opens a trade
-- or fills a letter (env.trade, env.mail); the player presses the game's button.
-- Amounts are the pair's net (View.net): owed (I owe) or due (owed to me, less my
-- P waiting in my login queue). Only the creditor's client writes a P, min(gold, room):
-- room is what that name may still pay me, its debts to me in any state (a pending
-- one too: its C may not have reached me yet) less what I recorded and what I owe
-- it. A P ahead of the C is credit of that pair: it clears that debtor's debts
-- oldest first as they are confirmed (core/LedgerView.lua). With room:
-- a completed trade, no item on either side, within PAY_WINDOW s of the payer's
-- whispered PAY "trade" (one PAY, one trade) -> P "trade"; money taken from a
-- letter tagged Pay.TAG whose sender fits exactly one name I have any debt with
-- (Names.matches) -> P "mail"; other gold from such a name is put to me (asks,
-- answer, "payAsk"). With no debt row at all, an announced trade or a tagged
-- letter of a full name the guild knows is put to me as well (credit: yes records
-- the whole amount); anything else is ignored. „Уредено“ (settle): P "hand" for
-- the whole due; over the gold cap a P splits. „Напомни“ (nudge): PAY "nudge",
-- once per NUDGE_GAP s. The login queue keeps a P; the payer's guard against
-- paying twice (guard, waiting, left, sent) is in core/PayGuard.lua.
local C, Names, View, Util = ns.Const, ns.Names, ns.LedgerView, ns.Util
local floor, min, max = math.floor, math.min, math.max

local Pay = {}; Pay.__index = Pay
ns.Pay = Pay
Pay.TAG = "Tavern Games:"

local PAID_MAX = 99999999999 -- copper: the gold cap, the largest P
local HOW = { trade = true, mail = true, nudge = true }

local function copper(v) return type(v) == "number" and v >= 1 and v <= PAID_MAX and v == floor(v) end

function Pay.new(client)
  return setmetatable({ client = client, env = client.env, heard = {}, nudged = {}, nudgeHeard = {},
    questions = {}, seq = 0 }, Pay)
end

function Pay:view() return View.of(self.client.ledger) end

-- The copper of my P entries for `name` waiting in my login queue.
function Pay:queued(name)
  local net, s = self.client.ledgerNet, 0
  if not (net and net.waiting) then return 0 end
  for _, q in ipairs(net:pending()) do
    if q.a == self.env.me and q.k == "P" and q.f.f == name and copper(q.f.c) then s = s + q.f.c end
  end
  return s
end

-- What I owe `name`, and what `name` owes me (copper, never below 0).
function Pay:owed(name) return max(0, View.net(self:view(), self.env.me, name)) end
function Pay:due(name) return max(0, View.net(self:view(), name, self.env.me) - self:queued(name)) end

-- What `name` may still pay me (see the header), and whether I have any debt row with it, either way.
function Pay:room(name)
  local v, me, all, any = self:view(), self.env.me, 0, false
  for _, d in ipairs(v.debts) do
    if d.f == name and d.t == me then all = all + d.c end
    any = any or (d.f == name and d.t == me) or (d.f == me and d.t == name)
  end
  return max(0, all - View.paid(v, name, me) - View.gross(v, me, name) - self:queued(name)), any
end

-- Is `name` a full name the guild knows (env.member; without it, a peer presence lists)?
function Pay:member(name)
  local member = self.env.member
  if member then return member(name) == true end
  return self.client.presence:get(name) ~= nil
end

-- The ways to pay `name`: {trade = "ok" | "far" | "none" | "off", mail = "open" |
-- "closed" | "off", fee, short} ("off": the client lacks the API; short: the
-- copper I lack for what is left to pay plus the fee of a letter, 0 when I have enough).
function Pay:options(name)
  local env, c = self.env, self:left(name)
  local fee = env.mail and env.mail.fee() or C.MAIL_FEE
  local money = env.money and env.money()
  return { trade = env.trade and env.trade.state(name) or "off", mail = env.mail and env.mail.state() or "off",
    fee = fee, short = (c > 0 and money) and max(0, c + fee - money) or 0 }
end

-- PAY {c, how} to `name` when presence lists it -> true | nil.
function Pay:whisper(name, c, how)
  local p = self.client.presence:get(name)
  if not p or p.incompatible then return nil end
  self.client:send("WHISPER", name, { v = C.PROTOCOL, t = "PAY", c = c, how = how })
  return true
end

-- I am about to pay `name`: announced to it (the creditor's client waits for the trade).
function Pay:paying(name, c, how) return self:whisper(name, c, how) or true end

-- „Трейд“: opens a trade with `name` for what I owe and has not left me yet -> true | nil,
-- code ("none": nothing owed; "sent": all of it has left already (Pay:guard); "far",
-- "nounit" (trade state "none") or "off"; "short": not enough gold).
function Pay:byTrade(name)
  local env, c = self.env, self:left(name)
  if c == 0 then return nil, self:owed(name) > 0 and "sent" or "none" end
  local state = env.trade and env.trade.state(name) or "off"
  if state ~= "ok" then return nil, state == "none" and "nounit" or state end
  local money = env.money and env.money()
  if money and money < c then return nil, "short" end
  if not env.trade.open(name, c) then return nil, "off" end
  return self:paying(name, c, "trade")
end

-- „Поща“: fills a letter to `name` for the same amount -> true | nil, code ("none",
-- "sent", "closed", "off", "short": not enough gold for the amount and the fee).
function Pay:byMail(name)
  local env, c = self.env, self:left(name)
  if c == 0 then return nil, self:owed(name) > 0 and "sent" or "none" end
  local o = self:options(name)
  if o.mail ~= "open" then return nil, o.mail == "closed" and "closed" or "off" end
  if o.short > 0 then return nil, "short" end
  if not env.mail.fill(name, Pay.subject(self:view(), env.me, name, env.date), ns.L("pay.mail.body"), c) then return nil, "off" end
  return self:paying(name, c, "mail")
end

-- My P for debtor `name`: min(gold, room) (whole: all of it, credit), split at the gold cap
-- -> {entry | "queued", ...} | nil.
function Pay:record(name, gold, how, whole)
  local left, out = whole and gold or min(gold, (self:room(name))), {}
  while left > 0 do
    local c = min(left, PAID_MAX)
    local e = self.client.ledgerNet:make("P", { f = name, c = c, how = how })
    if not e then break end
    out[#out + 1], left = e, left - c
  end
  return #out > 0 and out or nil
end

-- Puts gold that came to me to me: q = {name | names, c, how}.
function Pay:ask(q)
  self.seq = self.seq + 1
  q.id = self.seq
  self.questions[#self.questions + 1] = q
  self.client.events:emit("payAsk")
end

-- A completed trade with guild member t.name: the copper I gave and got, items =
-- an item on either side (anything but false is put to me). Gold I gave a creditor
-- has left me (Pay:sent).
function Pay:traded(t)
  if type(t) ~= "table" or type(t.name) ~= "string" or type(t.got) ~= "number" or type(t.gave) ~= "number" then return end
  local name, gold = t.name, t.got - t.gave
  if copper(-gold) then self:sent({ name = name, c = -gold, how = "trade" }) end
  if not copper(gold) then return end
  local heard, room, any = self.heard[name], self:room(name)
  self.heard[name] = nil
  local told = t.items == false and heard ~= nil and self.env.now() - heard <= C.PAY_WINDOW
  if room == 0 then -- nothing it may pay me: ignored, unless it announced the payment of a debt I do not hold yet
    if told and not any then self:ask({ name = name, c = gold, how = "trade", credit = true }) end
    return
  end
  if told then return self:record(name, gold, "trade") end
  self:ask({ name = name, c = gold, how = "trade" })
end

-- Money m.c taken from a letter of m.shown (the sender as the inbox shows it):
-- it may be any name I have a debt with, either way and in any state (pending,
-- contested, confirmed or paid); ignored when none of them may still pay me.
function Pay:mailed(m)
  if type(m) ~= "table" or not copper(m.c) then return end
  local me, shown, fit, owing = self.env.me, Names.normalize(m.shown), {}, false
  for _, d in ipairs(self:view().debts) do
    local who = d.f == me and d.t or d.t == me and d.f
    if who and not Util.contains(fit, who) and Names.matches(who, shown) then fit[#fit + 1], owing = who, owing or self:room(who) > 0 end
  end
  local tagged = type(m.subject) == "string" and m.subject:sub(1, #Pay.TAG) == Pay.TAG
  if #fit == 0 and tagged and shown and self:member(shown) then return self:ask({ name = shown, c = m.c, how = "mail", credit = true }) end
  if not owing then return end
  table.sort(fit, Util.byteLess)
  if tagged and #fit == 1 then return self:record(fit[1], m.c, "mail") end
  self:ask(#fit == 1 and { name = fit[1], c = m.c, how = "mail" } or { names = fit, c = m.c, how = "mail" })
end

-- The gold put to me: {{id, name | names, c, how}}, oldest first.
function Pay:asks() return Util.copy(self.questions) end

-- My answer to question `id`: the debtor it came from (a name of the question),
-- whose P it records, or false (not a payment) -> true | nil.
function Pay:answer(id, name)
  for j, q in ipairs(self.questions) do
    if q.id == id then
      if name ~= false and not (name == q.name or (q.names and Util.contains(q.names, name))) then return nil end
      table.remove(self.questions, j)
      if name then self:record(name, q.c, q.how, q.credit and not select(2, self:room(name))) end
      self.client.events:emit("payAsk")
      return true
    end
  end
  return nil
end

-- „Уредено“: `name` paid me all it owes, by hand -> {entry | "queued", ...} | nil (nothing due).
function Pay:settle(name) return self:record(name, self:due(name), "hand") end

-- „Напомни“ -> true | nil, code ("none": nothing due; "wait": reminded within
-- NUDGE_GAP s; "offline": presence does not list it).
function Pay:nudge(name)
  local c, now = self:due(name), self.env.now()
  if c == 0 then return nil, "none" end
  if self.nudged[name] and now - self.nudged[name] < C.NUDGE_GAP then return nil, "wait" end
  if not self:whisper(name, c, "nudge") then return nil, "offline" end
  self.nudged[name] = now
  return true
end

-- A whispered PAY from `sender`, a peer presence lists: a payment announced to
-- me, or a reminder of what I owe it (at most one per NUDGE_GAP s).
function Pay:receive(sender, msg)
  local p = self.client.presence:get(sender)
  if not p or p.incompatible or not copper(msg.c) or not HOW[msg.how] then return end
  local now = self.env.now()
  if msg.how == "trade" then self.heard[sender] = now end
  if msg.how ~= "nudge" then return end
  local c, last = self:owed(sender), self.nudgeHeard[sender]
  if c == 0 or (last and now - last < C.NUDGE_GAP) then return end
  self.nudgeHeard[sender] = now
  self.client.events:emit("nudge", sender, c)
end

return Pay
