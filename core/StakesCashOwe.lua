local _, ns = ...

-- A cash table's settlements become debts (Stakes.cash; the rest of the
-- extension `stakes` there is core/StakesCash.lua, which this file wraps
-- again, outermost). The one rule: a debt counts only once the debtor's own
-- client confirmed it, and it confirms by itself only what it saw whole,
-- clean and checked against the book's keys.
--   Out records (engines/holdem_cash.lua, state.cash.outs): after every
--     applied event, each record above s.cashOutSeen, in order, at gid = tid
--     .. "/" .. seq: the client event "cashout" {tid, gid, seat, name, chips,
--     bought, pairs, why, at} (why: nil for the seat's own cashout, the
--     stand's "left"/"offline" (s.cashWhy[seat], kept until the hand the stand
--     folded ends), "close" at the close); the seat leaves s.cashNames; the
--     host at that event writes the STAND record S, one per record. My pairs
--     of all the event's records go into one Book:outcome (why "lost" for the
--     creditor's D, "cash" for the note). A snapshot only moves the counter:
--     a settlement my client did not apply itself has no note (its claims are
--     put to me). Nothing of the ledger at a bot table.
--   The pairs come from the record alone (Stakes.cashPairs, H1): the engine's
--     own names, never the chairs.
--   The note waits for the book (Stakes.sealedAudit, from Stakes.audit):
--     final at the "book" event of its table, or when my session is no longer
--     there (then the book is not final: "unseen"), or after CASH_BOOK_WAIT;
--     with its owe time passed, Book:owe at once. Its verdict (cashVerdict) is
--     read on the book of that game: forged (or unseen, my own key held), deal
--     (a bad hand I was dealt into), unseen (the book not final; an open hand
--     at or before the note's that I was dealt into; any other bad hand).
--     The hands: book.cashIn[h] (my name among the hand's players at its
--     close) and book.cashBad[h] (closed "bad"), kept on that game's book, so a
--     verdict read after the next start reads its own game. A bad hand that
--     was not mine gives no foul at once (H16a).
--   My word on a cash claim is my own D, why "cash" (never a C: an F1/F2
--     client keeps it pending). A cash note without a pair for the creditor
--     (H13): contested "no" when clean, asked when unseen. An unseen note's
--     debt nobody claimed is put to me (Book:owing, Book:admit).
--   F1's open note of a cash table (SNO "gone", END) carries no stake: a cash
--     claim's amount is no big blind; it never replaces my note of that event.
local Stakes, C = ns.Stakes, ns.Const
local Book, View, copy = Stakes.Book, ns.LedgerView, ns.Util.copy

local function cashGame(g)
  local E = ns.Games.engine(g)
  return E ~= nil and E.cashGame == true
end

local function named(who, me)
  for _, n in pairs(type(who) == "table" and who or {}) do if n == me then return true end end
  return false
end

-- The pairs of out record rec, by its seats ascending -> {{f, t, c}}: net n > 0, the seat owes
-- the record's own seat n chips; a name missing, or a chip count that is no whole number, is left out.
function Stakes.cashPairs(rec)
  local out, who, chip = {}, rec.who, ns.HoldemCash.CHIP
  local net, names = type(rec.net) == "table" and rec.net or {}, type(rec.names) == "table" and rec.names or {}
  for j = 1, C.MAX_SEATS do
    local n, name = net[j], names[j]
    if type(who) == "string" and type(name) == "string" and type(n) == "number" and n ~= 0 and n % 1 == 0 then
      out[#out + 1] = n > 0 and { f = name, t = who, c = n * chip } or { f = who, t = name, c = -n * chip }
    end
  end
  return out
end

-- The verdict of the book on a note of mine written at event h -> foul | nil.
function Stakes.cashVerdict(s, book, h)
  local me = s.client.env.me
  if book.forged then return book.held and "unseen" or "forged" end
  local bad, mine = book.cashBad or {}, book.cashIn or {}
  for x in pairs(bad) do if mine[x] then return "deal" end end
  if not book.final then return "unseen" end
  for _, x in ipairs(book.open) do
    if x <= h and book.rec[x] and named(book.rec[x].who, me) then return "unseen" end
  end
  return next(bad) ~= nil and "unseen" or nil
end

-- The verdict still out for my note gid at a cash table (Stakes.audit) -> {read, wait}. A hand
-- of the book is its round's h, the number of the event that opened it: the hands at or before
-- my note are those up to its event, s.seq.
function Stakes.sealedAudit(s, gid)
  local book, h, client = ns.Book.of(s), s.seq, s.client
  client.cashWaits = client.cashWaits or {}
  client.cashWaits[gid] = s.tid
  return { read = function() return Stakes.cashVerdict(s, book, h) end, wait = C.CASH_BOOK_WAIT }
end

-- A hand of my cash table closed: whether it held me, whether it was bad; only a bad hand of mine is a foul now.
local heard = Stakes.fairHeard
function Stakes.fairHeard(client, v)
  local s = client.session
  local book = s and s.tid == v.tid and v.h ~= nil and Stakes.cash(s) and s.book
  if not book then return heard(client, v) end
  local fair = s.fair
  if fair and fair.h == v.h and named(fair.who, client.env.me) then book.cashIn = book.cashIn or {}; book.cashIn[v.h] = true end
  if v.verdict ~= "bad" then return heard(client, v) end
  book.cashBad = book.cashBad or {}
  book.cashBad[v.h] = true
  if book.cashIn and book.cashIn[v.h] then return heard(client, v) end
end

-- The host's STAND record of rec at gid.
local function stand(s, book, gid, rec, why)
  if type(rec.who) ~= "string" then return end
  local n, w, l, top = {}, {}, {}, math.max(#s.seats, rec.seat)
  for j = 1, C.MAX_SEATS do
    local x = rec.net[j]
    if type(x) == "number" and x ~= 0 then top = math.max(top, j) end
    if type(x) == "number" and x > 0 then w[#w + 1] = j elseif type(x) == "number" and x < 0 then l[#l + 1] = j end
  end
  for i = 1, top do n[i] = (i == rec.seat and rec.who) or (type(rec.names[i]) == "string" and rec.names[i]) or false end
  book:make("S" .. gid .. "|" .. rec.seat, "S", { gid = gid, g = s.game, f = rec.who, c = rec.bought * ns.HoldemCash.CHIP,
    sk = s.stake, n = n, w = w, l = l, why = why })
end

-- The out records of the event just applied (seat, a): see the header.
local function settled(s, seat, a)
  local st, client = s.state, s.client
  local cash, book, env = st and st.cash, client.stakes, client.env
  if type(cash) ~= "table" or type(cash.outs) ~= "table" then return end
  local seen = s.cashOutSeen
  if seen == nil then s.cashOutSeen = cash.outN; return end -- no count of mine yet: nothing I can call mine
  local gid, mine, bot = s.tid .. "/" .. s.seq, {}, not book or book:bot(s.tid)
  for _, rec in ipairs(cash.outs) do
    if type(rec) == "table" and type(rec.n) == "number" and rec.n > seen then
      s.cashOutSeen = math.max(s.cashOutSeen, rec.n)
      local why = s.cashWhy and s.cashWhy[rec.seat] or (st.closing and "close") or "left"
      if seat ~= 0 and seat == rec.seat and a.k == "cashout" then why = nil end
      local list = Stakes.cashPairs(rec)
      if s.cashWhy then s.cashWhy[rec.seat] = nil end
      if s.cashNames then s.cashNames[rec.seat] = nil end -- H2: a settled seat leaves my names
      client.events:emit("cashout", { tid = s.tid, gid = gid, seat = rec.seat, name = rec.who, chips = rec.chips,
        bought = rec.bought, pairs = copy(list), why = why, at = env.epoch() })
      if not bot then
        if s.role == "host" then stand(s, book, gid, rec, why) end
        for _, p in ipairs(list) do if p.f == env.me or p.t == env.me then mine[#mine + 1] = p end end
      end
    end
  end
  if #mine > 0 then book:outcome(s, gid, mine, "lost", "cash") end -- H3: one note per event
end

local ext = ns.Ext.stakes
local applied, adopted, gone, ended = ext.applied, ext.adopted, ext.gone, ext.ended

ext.applied = function(s, seat, a)
  if not Stakes.cash(s) then return applied(s, seat, a) end
  applied(s, seat, a)
  local k = seat == 0 and a.k
  if k == "start" then s.cashOutSeen, s.cashWhy = 0, nil end
  if k == "stand" and type(a.seat) == "number" then
    s.cashWhy = s.cashWhy or {}
    s.cashWhy[a.seat] = a.why == "offline" and "offline" or "left"
  end
  settled(s, seat, a)
  if not (s.state and s:engine().inHand(s.state)) then s.cashWhy = nil end -- the hand a stand folded has ended
end

ext.adopted = function(s, prev, m, how)
  if not Stakes.cash(s) then return adopted(s, prev, m, how) end
  adopted(s, prev, m, how)
  local cash = s.state and s.state.cash
  s.cashOutSeen = type(cash) == "table" and cash.outN or nil
end

-- F1's open note (f: the hook `gone` or `ended`) at a cash table: no stake in it, and my note of that event stays.
local function openNote(s, f, ...)
  local db, gid = s.client.env.db, s.tid .. "/" .. s.seq
  local was = type(db.stakeSeen) == "table" and db.stakeSeen[gid] or nil
  local r = f(s, ...)
  local note = type(db.stakeSeen) == "table" and db.stakeSeen[gid] or nil
  if type(note) == "table" and note ~= was and note.open then
    note.sk = nil
    if was ~= nil then db.stakeSeen[gid], db.stakeSeen[gid .. "+open"] = was, note end
  end
  return r
end
ext.gone = function(s) if not Stakes.cash(s) then return gone(s) end return openNote(s, gone) end
ext.ended = function(s, by) if not Stakes.cash(s) then return ended(s, by) end return openNote(s, ended, by) end

-- The waiting notes of the tables `done` names (tid -> bool) become final.
local function finals(client, done)
  local waits, book = client.cashWaits, client.stakes
  if not (waits and book) then return end
  local due = {}
  for gid, tid in pairs(waits) do if done(tid) then due[#due + 1] = gid end end
  if #due == 0 then return end
  table.sort(due)
  local now = client.env.epoch()
  for _, gid in ipairs(due) do
    waits[gid] = nil
    book:final(gid)
    local note = book:seen()[gid]
    if type(note) == "table" and type(note.owe) == "number" and note.owe <= now then book:owe(gid) end
  end
  client.events:emit("debtAsk")
end

local new = Stakes.new
function Stakes.new(client)
  local self = new(client)
  client:on("book", function(v) finals(client, function(tid) return tid == v.tid end) end)
  client:on("session", function(s) finals(client, function(tid) return not (s and s.tid == tid) end) end)
  return self
end

-- My word on a claim of a cash game: my own D (why "cash"), never a C.
local word = Book.word
function Book:word(d, b, wide, kind, why)
  if kind ~= "C" or not cashGame(b.g) then return word(self, d, b, wide, kind, why) end
  return self:make("O" .. d.key, "D", { gid = d.gid, g = b.g, f = d.f, t = d.t, c = b.c, why = "cash" })
end

-- H13: a final cash note of mine without a pair f = me, t = the creditor.
local judge = Book.judge
function Book:judge(b, taken)
  local note, me = self:seen()[b.gid], self.env.me
  if type(note) == "table" and not note.open and not note.wait and cashGame(note.g) and (not note.foul or note.foul == "unseen") then
    for _, p in ipairs(note.pairs or {}) do if p.f == me and p.t == b.t then return judge(self, b, taken) end end
    if note.foul then return "ask" end
    return "N", "no"
  end
  return judge(self, b, taken)
end

-- My final unseen cash notes' debts nobody claimed, STAKE_OWE_WAIT after the note -> {{gid, t, c, key}} (by key).
function Book:owing()
  local L, me, now, out = self.client.ledger, self.env.me, self.env.epoch(), {}
  if not L then return out end
  local have = {}
  for _, d in ipairs(View.of(L).debts) do have[d.key] = true end
  for gid, n in pairs(self:seen()) do
    if type(n) == "table" and n.why == "cash" and n.foul == "unseen" and not n.wait and not n.open
        and type(n.at) == "number" and n.at + C.STAKE_OWE_WAIT <= now then
      for _, p in ipairs(type(n.pairs) == "table" and n.pairs or {}) do
        local key = gid .. "|" .. me .. "|" .. tostring(p.t)
        if p.f == me and not have[key] and not self.answered[key] then out[#out + 1] = { gid = gid, t = p.t, c = p.c, key = key } end
      end
    end
  end
  table.sort(out, function(x, y) return x.key < y.key end)
  return out
end

-- My answer to a debt of Book:owing (yes: my own D, why "cash"); remembered for this run -> true | nil.
function Book:admit(key, yes)
  for _, o in ipairs(self:owing()) do
    if o.key == key then
      if yes then self:make("O" .. key, "D", { gid = o.gid, g = self:seen()[o.gid].g, f = self.env.me, t = o.t, c = o.c, why = "cash" }) end
      self.answered[key] = true
      self.client.events:emit("debtAsk")
      return true
    end
  end
  return nil
end
