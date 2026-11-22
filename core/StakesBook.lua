local _, ns = ...

-- The money half of a staked table (core/Stakes.lua plays it, finds forfeits):
-- client.stakes, for a client with a ledger. An outcome of mine (gid = tid
-- .. "/" .. q) is noted first, db.stakeSeen[gid] = {at, g, sk, pairs, why,
-- foul, tid, q, wait}: the foul after the event's hooks, Rolls.audit folded
-- in (pending reads "unseen"; wait: final ROLL_FINAL_WAIT later). Then the
-- host writes R (a fun table: nothing else), each creditor a D per pair, a
-- debtor with a clean final note and no claim in STAKE_OWE_WAIT its own D;
-- nothing at a bot table (env.noLedger). A claim against me (stakes:review):
-- my „Стани“ there (db.stakeLeft, once per creditor) -> C; my note: pending
-- -> wait, foul forged/roll/stand -> N, another amount -> N "amount", my pair
-- clean -> C (own D when its id holds another debt too); an event of my table
-- not applied yet -> wait; the newest open note there with a foul -> N; else
-- it is put to me (asks, answer, "debtAsk"). Not while my login queue is open.
local Stakes, C = ns.Stakes, ns.Const
local View, copy = ns.LedgerView, ns.Util.copy

local Book = {}; Book.__index = Book
local BAD = { forged = true, roll = true, stand = true }

-- Every loser owes every winner c -> {{f, t, c}} (names).
function Stakes.pairs(losers, winners, c)
  local out = {}
  for _, f in ipairs(losers) do for _, t in ipairs(winners) do if f ~= t then out[#out + 1] = { f = f, t = t, c = c } end end end
  return out
end

local function worse(a, b) return (not a or (b and Stakes.RANK[b] > Stakes.RANK[a])) and b or a end
local function rolls(s) return ns.Util.contains(s:engine().ext or {}, "rolls") end
local function names(seats, list)
  local out = {}
  for _, seat in ipairs(list or {}) do if type(seats[seat]) == "string" then out[#out + 1] = seats[seat] end end
  return out
end

function Stakes.new(client)
  local self = setmetatable({ client = client, env = client.env, did = {}, answered = {}, sig = "" }, Book)
  client:on("result", function(r) self:result(r) end)
  client:on("ledger", function() self:review() end)
  client:on("session", function() if self.held then self:review() end end) -- a claim waits for my table
  return self
end

-- My notes (write: made when missing; a read of none is an empty list).
function Book:seen(write) return self:keep("stakeSeen", write) end
function Book:left(write) return self:keep("stakeLeft", write) end
function Book:keep(k, write)
  local db = self.env.db
  if write and type(db[k]) ~= "table" then db[k] = {} end
  return type(db[k]) == "table" and db[k] or {}
end
function Book:bot(tid) return self.env.noLedger ~= nil and self.env.noLedger(tid) == true end

-- After a login: notes past STAKE_SEEN_KEEP go; a roll verdict my last
-- session did not live to see stays as the note has it (pending: "unseen").
function Book:start()
  local old = self.env.epoch() - C.STAKE_SEEN_KEEP
  for _, list in ipairs({ self:seen(), self:left() }) do
    for k, n in pairs(list) do
      if type(n) == "table" and (type(n.at) ~= "number" or n.at < old) then list[k] = nil elseif type(n) == "table" then n.wait = nil end
    end
  end
  self.client:after(C.LEDGER_ADOPT_WAIT, function() self:review() end) -- my login queue has closed
  self:review()
end

-- My entry, once per `key` in this run -> entry | "queued" | nil.
function Book:make(key, kind, fields)
  local net = self.client.ledgerNet
  if self.did[key] or not net then return nil end
  local e = net:make(kind, fields)
  if e then self.did[key] = true end
  return e
end

function Book:note(gid, note)
  self:seen(true)[gid] = note
  self:review()
end

-- The newest note of table tid -> note | nil (the bill reads it).
function Book:last(tid)
  local best
  for _, n in pairs(self:seen()) do
    if type(n) == "table" and n.tid == tid and (not best or n.at > best.at or (n.at == best.at and (n.q or 0) > (best.q or 0))) then best = n end
  end
  return best
end

-- "result" (inside the event's apply): the host's R; at a staked table the
-- rest after the event's hooks (Book:settle, from the stakes hook applied).
function Book:result(r)
  local s = self.client.session
  if not (s and s.tid == r.tid) or self:bot(r.tid) then return end
  local gid = r.tid .. "/" .. r.q
  if s.role == "host" then
    self:make("R" .. gid, "R", { gid = gid, g = r.game, n = copy(r.names), w = copy(r.winners), l = copy(r.losers), sk = r.sk,
      why = r.left and "left" or nil })
  end
  if r.sk ~= nil then s.stakeResult = r end
end

function Book:settle(s)
  local r = s.stakeResult
  if not r then return end
  s.stakeResult = nil
  self:outcome(s, r.tid .. "/" .. r.q, Stakes.pairs(names(r.names, r.losers), names(r.names, r.winners), r.sk), r.left and "left" or "lost")
end

-- My note of an outcome and my entries for it: my claims, the owe timer, the
-- final roll verdict. `why`: the D's; `noted`: the note's, when another.
function Book:outcome(s, gid, pairs, why, noted)
  local me, mine, owes = self.env.me, false, false
  for _, p in ipairs(pairs) do mine, owes = mine or p.f == me or p.t == me, owes or p.f == me end
  if not mine then return end
  local rec, base = rolls(s) and (ns.Rolls.auditOf(self.client, gid) or s), s.stakeFoul
  local note = { at = self.env.epoch(), g = s.game, sk = s.stake, pairs = pairs, why = noted or why, tid = s.tid,
    q = tonumber(gid:match("/(%d+)$")), foul = worse(base, rec and ns.Rolls.audit(rec) or nil), wait = rec and true or nil }
  self:seen(true)[gid] = note
  for _, p in ipairs(pairs) do
    if p.t == me then self:make("D" .. gid .. "|" .. p.f .. "|" .. me, "D", { gid = gid, g = s.game, f = p.f, t = me, c = p.c, why = why }) end
  end
  if owes then self.client:after(C.STAKE_OWE_WAIT, function() self:owe(gid) end) end
  if rec then
    self.client:after(C.ROLL_FINAL_WAIT, function()
      note.foul, note.wait = worse(base, ns.Rolls.audit(rec)), nil
      self:review()
    end)
  end
  self:review()
end

-- No claim of a creditor STAKE_OWE_WAIT after my clean loss: my own D.
function Book:owe(gid)
  local note, L, me = self:seen()[gid], self.client.ledger, self.env.me
  if type(note) ~= "table" or not L or note.wait or note.foul or note.open or type(note.pairs) ~= "table" then return end
  local have = {}
  for _, d in ipairs(View.of(L).debts) do have[d.key] = true end
  for _, p in ipairs(note.pairs) do
    local key = gid .. "|" .. me .. "|" .. p.t
    if p.f == me and not have[key] then self:make("O" .. key, "D", { gid = gid, g = note.g, f = me, t = p.t, c = p.c, why = note.why }) end
  end
end

-- What my client says to claim body b -> "C" | "N", why | "wait" | "ask" (and the leave
-- it used; `taken`: creditor -> the body a leave was used for in this scan).
function Book:judge(b, taken)
  local me, tid, q = self.env.me, b.gid:match("^(.*)/(%d+)$")
  q = tonumber(q)
  local left, note = self:left()[tid], self:seen()[b.gid]
  local used = type(left) == "table" and ((type(left.used) == "table" and left.used[b.t]) or taken[b.t])
  if type(left) == "table" and b.why == "left" and left.sk == b.c and math.abs(b.at - (left.at or 0)) <= C.STAKE_LEFT_WINDOW
      and ns.Util.contains(type(left.names) == "table" and left.names or {}, b.t) and (not used or used == b.h) then
    taken[b.t] = b.h
    return "C", nil, left
  end
  if type(note) == "table" and not note.open then
    if note.wait then return "wait" end
    if BAD[note.foul] then return "N", note.foul end
    local p
    for _, x in ipairs(note.pairs or {}) do if x.f == me and x.t == b.t then p = x end end
    if b.c ~= (p and p.c or note.sk) then return "N", "amount" end
    return (p and not note.foul) and "C" or "ask"
  end
  local s = self.client.session
  if s and s.tid == tid and q > s.seq then self.held = true; return "wait" end -- again at each change of my table
  local open
  for _, n in pairs(self:seen()) do
    if type(n) == "table" and n.open and n.tid == tid and (n.q or 0) <= q and (not open or n.at > open.at) then open = n end
  end
  if open and BAD[open.foul] then return "N", open.foul end
  local sk = (open and open.sk) or (type(left) == "table" and left.sk)
  if sk and b.c ~= sk then return "N", "amount" end
  return "ask"
end

-- The claim bodies of debt d (its creditor's D entries), and whether an id of
-- them holds bodies of another debt as well (then my word is my own D).
function Book:claims(d)
  local L, out, wide = self.client.ledger, {}, false
  for _, id in ipairs(d.ids) do
    local a, n = ns.Ledger.author(id)
    for _, b in ipairs(L:bodies(a, n)) do
      if b.k == "D" and b.gid == d.gid and b.f == d.f and b.t == d.t and a == d.t and not b.un and not L:denied(b) then
        out[#out + 1] = b
      elseif b.k == "D" and b.gid .. "|" .. tostring(b.f) .. "|" .. tostring(b.t) ~= d.key then wide = true end
    end
  end
  return out, wide
end

-- My word on body b of debt d: C (my own D, `wide`), or N why.
function Book:word(d, b, wide, kind, why)
  if kind == "N" then return self:make("W" .. b.h, "N", { r = b.i, dh = b.h, why = why }) end
  if wide then return self:make("O" .. d.key, "D", { gid = d.gid, g = b.g, f = d.f, t = d.t, c = b.c, why = b.why }) end
  return self:make("W" .. b.h, "C", { r = b.i, dh = b.h })
end

-- Every pending claim against me: decided (acts) or put to me (asks) -> asks, acts.
function Book:scan()
  local L, asks, acts, taken = self.client.ledger, {}, {}, {}
  self.held = false
  if not L then return asks, acts end
  for _, d in ipairs(View.claims(View.of(L), self.env.me)) do
    local list, wide = self:claims(d)
    local wait, mine = false, {}
    for _, b in ipairs(list) do
      local kind, why, left = self:judge(b, taken)
      wait = wait or kind == "wait"
      if kind == "C" or kind == "N" then mine[#mine + 1] = { d = d, b = b, wide = wide, kind = kind, why = why, left = left } end
    end
    table.sort(mine, function(x, y) return x.kind == "N" and y.kind == "C" end) -- my newest word is the C
    if #mine > 0 then for _, w in ipairs(mine) do acts[#acts + 1] = w end
    elseif not wait and #list > 0 and not self.answered[d.key] then asks[#asks + 1] = d end
  end
  return asks, acts
end

-- The claims against me my client could not decide: {debt, ...}.
function Book:asks() return (self:scan()) end

-- Decides what it can ("ledger", every note, start, the final roll verdict);
-- "debtAsk" when asks() changed. Idempotent.
function Book:review()
  local net = self.client.ledgerNet
  if not (net and net.running) then return end
  local asks, acts = self:scan()
  if not net.waiting then
    for _, w in ipairs(acts) do
      local u = w.left and (type(w.left.used) == "table" and w.left.used or {})
      if self:word(w.d, w.b, w.wide, w.kind, w.why) and u then w.left.used, u[w.b.t] = u, w.b.h end
    end
  end
  local keys = {}
  for i, d in ipairs(asks) do keys[i] = d.key end
  local sig = table.concat(keys, "\n")
  if sig ~= self.sig then self.sig = sig; self.client.events:emit("debtAsk") end
end

-- My answer to a debt put to me (yes: C, no: N "no", for every claim of it) -> true | nil.
function Book:answer(key, yes)
  for _, d in ipairs(self:asks()) do
    if d.key == key then
      local list, wide = self:claims(d)
      for _, b in ipairs(list) do self:word(d, b, wide, yes and "C" or "N", "no") end
      self.answered[key] = true
      self:review()
      return true
    end
  end
  return nil
end

return Book
