local _, ns = ...

-- The late key of a cash table (Stakes.cash). A player stood up while its
-- client was gone never sent its table key, so every hand it was dealt into
-- stays open in the books and every note at or after such a hand reads unseen.
--   Mine: my kept key of a staked table (db.bookKeep, its sk set by Book.key)
--     goes out once a login, LEDGER_ADOPT_WAIT after it, unless I sit in that
--     game again (then its own keys path): GUILD {v, t = "KEY", tid, g, m}.
--     It is spent first (db.bookSpent: it never deals again), and given up
--     CASH_BOOK_WAIT after its first late send.
--   Theirs: a key from the sender's own name for a book of that table and
--     game I hold (my table's, or one a note of mine waits on) is kept
--     (client.cashKeys, one per name, only a name in an open hand there), and
--     taken into every ended book of that game (Book.late; one not ended yet
--     takes it at its "book" event). Then my notes of that game whose final
--     verdict is unseen are read again on the book, as at the close: clean ->
--     my own D (Book:owe) and my word on the claims; bad -> contested; still
--     unseen -> unchanged. Never a note CASH_BOOK_WAIT old, one still waiting
--     (its own final reads the book), one with a question answered or a
--     debt of mine at its gid not pending (a C, D or N of mine stands).
--   What a note waits on (client.cashLate[gid] = {s, book, base, read}) lives
--     in memory only: a /reload since the close forgets it (the note stays).
local Stakes, C = ns.Stakes, ns.Const
local Book, View, worse = Stakes.Book, ns.LedgerView, Stakes.worse
local Late = {}
Stakes.Late = Late

local sealed = Stakes.sealedAudit
function Stakes.sealedAudit(s, gid)
  local a = sealed(s, gid)
  a.late = { s = s, book = ns.Book.of(s) }
  return a
end

local pending = Book.pending
function Book:pending(gid, note, base, a)
  if a and a.late then
    local c = self.client
    c.cashLate = c.cashLate or {}
    c.cashLate[gid] = { s = a.late.s, book = a.late.book, base = base, read = a.read }
  end
  return pending(self, gid, note, base, a)
end

local function sorted(t)
  local out = {}
  for k in pairs(t or {}) do out[#out + 1] = k end
  table.sort(out)
  return out
end

-- The books of table tid, game g that I hold -> {{s, book}, ...}.
local function books(client, tid, g)
  local out, seen, s = {}, {}, client.session
  local function add(x, book) if not seen[book] then seen[book] = true; out[#out + 1] = { x, book } end end
  if s and s.tid == tid and s.book and s.book.g == g and Stakes.cash(s) then add(s, s.book) end
  for _, gid in ipairs(sorted(client.cashLate)) do
    local w = client.cashLate[gid]
    if w.s.tid == tid and w.book.g == g then add(w.s, w.book) end
  end
  return out
end

-- Is there a question of my note gid I answered, or a debt of mine at gid that is not pending?
local function decided(stakes, gid)
  for k in pairs(stakes.answered) do if k:sub(1, #gid + 1) == gid .. "|" then return true end end
  for _, d in ipairs(View.of(stakes.client.ledger).debts) do
    if d.gid == gid and d.f == stakes.env.me and d.status ~= "pending" then return true end
  end
  return false
end

-- My notes of table tid, game g, read again on their book (see the header).
local function judge(client, tid, g)
  local stakes, reg, now, any = client.stakes, client.cashLate or {}, client.env.epoch(), false
  for _, gid in ipairs(sorted(reg)) do
    local w, note = reg[gid], stakes:seen()[gid]
    if w.s.tid == tid and w.book.g == g then
      if type(note) ~= "table" or type(note.at) ~= "number" or note.at + C.CASH_BOOK_WAIT < now then
        reg[gid] = nil
      elseif note.wait then -- its own final reads this book
      elseif note.foul ~= "unseen" or note.open or decided(stakes, gid) then
        reg[gid] = nil
      else
        local v = worse(w.base, w.read())
        if v ~= "unseen" then
          reg[gid], note.foul, any = nil, v, true
          if not v and not (type(note.owe) == "number" and note.owe > now) then stakes:owe(gid) end
        end
      end
    end
  end
  if any then stakes:review(); client.events:emit("debtAsk") end
end

-- The keys kept for table tid, game g go into its ended books; my notes of that game are read again.
local function apply(client, tid, g)
  local x = client.cashKeys and client.cashKeys[tid .. "|" .. g]
  if not x then return end
  for _, b in ipairs(books(client, tid, g)) do
    for _, name in ipairs(sorted(x.by)) do ns.Book.late(b[1], b[2], name, x.by[name]) end
  end
  judge(client, tid, g)
end

local function named(book, name)
  for _, h in ipairs(book.open) do
    local rec = book.rec[h]
    for _, n in pairs(rec and rec.who or {}) do if n == name then return true end end
  end
  return false
end

-- A KEY of `sender`.
function Late.heard(client, sender, m)
  if not (type(m.tid) == "string" and type(m.g) == "number" and ns.Book.isKey(m.m)) then return end
  local hit = false
  for _, b in ipairs(books(client, m.tid, m.g)) do hit = hit or named(b[2], sender) end
  if not hit then return end
  local at = m.tid .. "|" .. m.g
  client.cashKeys = client.cashKeys or {}
  client.cashKeys[at] = client.cashKeys[at] or { tid = m.tid, g = m.g, by = {} }
  client.cashKeys[at].by[sender] = m.m
  apply(client, m.tid, m.g)
end

-- My kept key of a staked table -> bool.
local function due(env, kept)
  return type(kept) == "table" and kept.sk ~= nil and kept.me == env.me and type(kept.tid) == "string"
    and type(kept.g) == "number" and ns.Book.isKey(kept.key)
end

-- My kept key goes out late (see the header).
function Late.send(client)
  local env = client.env
  local db, now = env.db, env.epoch()
  local kept, s = db.bookKeep, client.session
  if not due(env, kept) then return end
  if type(kept.late) ~= "number" then kept.late = now end
  if now > kept.late + C.CASH_BOOK_WAIT then db.bookKeep = nil; return end
  if s and s.tid == kept.tid and s.mySeat and s.state and s.state.g == kept.g then return end
  local spent, have = type(db.bookSpent) == "table" and db.bookSpent or {}, false
  db.bookSpent = spent
  for _, x in ipairs(spent) do have = have or (x.tid == kept.tid and x.me == env.me and x.key == kept.key) end
  if not have then
    spent[#spent + 1] = { tid = kept.tid, me = env.me, key = kept.key }
    while #spent > ns.Book.SPENT_KEPT do table.remove(spent, 1) end
  end
  client:send("GUILD", nil, { v = C.PROTOCOL, t = "KEY", tid = kept.tid, g = kept.g, m = kept.key })
end

local start = Book.start
function Book:start()
  start(self)
  local client = self.client
  if due(self.env, self.env.db.bookKeep) then client:after(C.LEDGER_ADOPT_WAIT, function() Late.send(client) end) end
end

local new = Stakes.new
function Stakes.new(client)
  local self = new(client)
  client:on("book", function(v)
    for _, at in ipairs(sorted(client.cashKeys)) do
      local x = client.cashKeys[at]
      if x.tid == v.tid then apply(client, x.tid, x.g) end
    end
  end)
  return self
end

local receive = ns.Client.receive
function ns.Client:receive(channel, sender, msg)
  receive(self, channel, sender, msg)
  if self.running and self.stakes and channel == "GUILD" and type(msg) == "table" and msg.v == C.PROTOCOL
      and msg.t == "KEY" and type(sender) == "string" and sender ~= self.env.me then
    Late.heard(self, sender, msg)
  end
end

return Late
