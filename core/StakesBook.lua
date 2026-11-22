local _, ns = ...

-- The money half of a staked table (core/Stakes.lua plays it, finds forfeits):
-- client.stakes, for a client with a ledger. An outcome of mine (gid = tid
-- .. "/" .. q) is noted first, db.stakeSeen[gid] = {at, g, sk, pairs, why,
-- foul, tid, q, wait}: the foul after the event's hooks, the verdict still
-- out folded in (Stakes.audit: pending reads "unseen"; wait: until final). Then the
-- host writes R (a fun table: nothing else), each creditor a D per pair, a
-- debtor with a clean final note and no claim by its `owe` (STAKE_OWE_WAIT
-- later; kept in the note, so a /reload or login resumes it) its own D;
-- nothing at a bot table (env.noLedger). A claim against me (stakes:review,
-- judged in core/StakesClaims.lua) is decided or put to me (asks, answer,
-- "debtAsk"); nothing is written while my login queue is open.
local Stakes, C = ns.Stakes, ns.Const
local View, copy = ns.LedgerView, ns.Util.copy

local Book = {}; Book.__index = Book
Stakes.Book = Book -- the judgment of a claim: core/StakesClaims.lua

-- Every loser owes every winner c -> {{f, t, c}} (names).
function Stakes.pairs(losers, winners, c)
  local out = {}
  for _, f in ipairs(losers) do for _, t in ipairs(winners) do if f ~= t then out[#out + 1] = { f = f, t = t, c = c } end end end
  return out
end

-- A team game (engine.teams): the i-th loser owes the i-th winner c (both
-- lists by ascending seat; the extra names of the longer list owe and are owed nothing) -> {{f, t, c}}.
function Stakes.matched(losers, winners, c)
  local out = {}
  for i = 1, math.min(#losers, #winners) do out[i] = { f = losers[i], t = winners[i], c = c } end
  return out
end

-- Whom the leaver of `seat` owes: the other players of `roster` (seat -> name)
-- but its partner (engine.partner) -> names, seats (in seat order).
function Stakes.owed(s, roster, seat)
  local engine, to, w = s:engine(), {}, {}
  local partner = engine.partner and engine.partner(seat)
  for i = 1, #s.seats do
    if i ~= seat and i ~= partner and roster[i] then to[#to + 1], w[#w + 1] = roster[i], i end
  end
  return to, w
end

-- The worse of two fouls by Stakes.RANK (either may be nil) -> foul | nil.
function Stakes.worse(a, b) return (not a or (b and Stakes.RANK[b] > Stakes.RANK[a])) and b or a end
local worse = Stakes.worse
local function names(seats, list)
  local out = {}
  for _, seat in ipairs(list or {}) do if type(seats[seat]) == "string" then out[#out + 1] = seats[seat] end end
  return out
end

function Stakes.new(client)
  local self = setmetatable({ client = client, env = client.env, did = {}, answered = {}, sig = "", finals = {} }, Book)
  client:on("fair", function(v) Stakes.fairHeard(client, v) end) -- a hand or throw closed (core/StakesFair.lua)
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
-- session did not live to see stays as the note has it (pending: "unseen");
-- a debtor's `owe` still due resumes, not before the sync could bring the claim.
function Book:start()
  local now = self.env.epoch()
  local old, resume = now - C.STAKE_SEEN_KEEP, C.LEDGER_ADOPT_WAIT + C.LEDGER_JITTER_MAX + C.LEDGER_SYNC_TIMEOUT
  for gid, n in pairs(self:seen()) do
    if type(n) == "table" and type(n.owe) == "number" then self.client:after(math.max(resume, n.owe - now), function() self:owe(gid) end) end
  end
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

-- The host's R of a "result".
local function hostR(self, s, r)
  if s.role ~= "host" then return end
  local gid = r.tid .. "/" .. r.q
  self:make("R" .. gid, "R", { gid = gid, g = r.game, n = copy(r.names), w = copy(r.winners), l = copy(r.losers), sk = r.sk,
    why = r.left and "left" or nil })
end

-- "result" (inside the event's apply): a fun table's R, the host's; at a
-- staked table everything after the event's hooks (Book:settle, from the stakes hook applied).
function Book:result(r)
  local s = self.client.session
  if not (s and s.tid == r.tid) or self:bot(r.tid) then return end
  if r.sk == nil then return hostR(self, s, r) end
  s.stakeResult = r
end

-- The outcome of the event's "result" and the host's R. `quits`: the event is
-- the stand of a seat of the running game, which the forfeit settles (core/Stakes.lua):
-- the result is dropped, one outcome per game. A team game's losers pay by
-- Stakes.matched, every other game's by Stakes.pairs.
function Book:settle(s, quits)
  local r = s.stakeResult
  if not r then return end
  s.stakeResult = nil
  if quits then return end
  hostR(self, s, r)
  local function by(list) local out = copy(list or {}); table.sort(out); return names(r.names, out) end
  local pair = s:engine().teams and Stakes.matched or Stakes.pairs
  self:outcome(s, r.tid .. "/" .. r.q, pair(by(r.losers), by(r.winners), r.sk), r.left and "left" or "lost")
end

-- My note of an outcome and my entries for it: my claims, the owe timer, the
-- verdict still out (a forfeit's: none but the rolls'; its running hand's held foul, Stakes.openFoul). `why`: the D's; `noted`: the note's, when another.
function Book:outcome(s, gid, pairs, why, noted)
  local me, mine, owes = self.env.me, false, false
  for _, p in ipairs(pairs) do mine, owes = mine or p.f == me or p.t == me, owes or p.f == me end
  if not mine then return end
  local note = { at = self.env.epoch(), g = s.game, sk = s.stake, pairs = pairs, why = noted or why, tid = s.tid,
    q = tonumber(gid:match("/(%d+)$")) }
  self:seen(true)[gid] = note
  local left = why ~= "lost" -- a forfeit: the foul held against its running hand counts at once
  self:pending(gid, note, left and worse(s.stakeFoul, Stakes.openFoul(s.fair)) or s.stakeFoul, Stakes.audit(s, gid, left))
  for _, p in ipairs(pairs) do
    if p.t == me then self:make("D" .. gid .. "|" .. p.f .. "|" .. me, "D", { gid = gid, g = s.game, f = p.f, t = me, c = p.c, why = why }) end
  end
  if owes then note.owe = note.at + C.STAKE_OWE_WAIT; self.client:after(C.STAKE_OWE_WAIT, function() self:owe(gid) end) end
  self:review()
end

-- The note of my „Стани“ as a member (core/Stakes.lua's quit): the foul my client
-- holds of that game (its running hand's held foul too) with the rolls' audit folded in, as in Book:outcome, so a claim of that stand is judged with it.
function Book:quit(s, gid, note)
  self:seen(true)[gid] = note
  self:pending(gid, note, worse(note.foul, Stakes.openFoul(s.fair)), Stakes.audit(s, gid, true))
end

-- Note of gid: its foul the worse of base and the verdict a (Stakes.audit) reads now; with a,
-- note.wait until it is final (a.wait later, or Book:final sooner: once), then judged again.
function Book:pending(gid, note, base, a)
  note.foul, note.wait = worse(base, a and a.read() or nil), a and true or nil
  if not a then return end
  local function final()
    if self.finals[gid] ~= final then return end
    self.finals[gid], note.foul, note.wait = nil, worse(base, a.read()), nil
    self:review()
  end
  self.finals[gid] = final
  self.client:after(a.wait, final)
end
function Book:final(gid) if self.finals[gid] then self.finals[gid]() end end

-- No claim of a creditor STAKE_OWE_WAIT after my clean loss: my own D. Done once (note.owe goes).
function Book:owe(gid)
  local note, L, me = self:seen()[gid], self.client.ledger, self.env.me
  if type(note) ~= "table" or not L or note.wait then return end
  note.owe = nil
  if note.foul or note.open or type(note.pairs) ~= "table" then return end
  local have = {}
  for _, d in ipairs(View.of(L).debts) do have[d.key] = true end
  for _, p in ipairs(note.pairs) do
    local key = gid .. "|" .. me .. "|" .. p.t
    if p.f == me and not have[key] then self:make("O" .. key, "D", { gid = gid, g = note.g, f = me, t = p.t, c = p.c, why = note.why }) end
  end
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
