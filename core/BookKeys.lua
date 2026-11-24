local _, ns = ...

-- The traffic of a sealed table's book (core/Book.lua): the handlers
-- core/Cash.lua dispatches to. Rule 6, keys: a player who stands up (hook
-- `leaving`) sends its key first (ACT {k="book", op="key", m, g}), published at
-- once while the game runs (EV {k="book", op="keys", m = {[seat] = key}, g}).
-- g is the game's (book.g): a key of another game is refused by the host and
-- by every client (a late key of the last game touches nothing of this one).
-- Once the game is over (the host's „Приключи“ {k="close"}, the hand played
-- out: E.over) every seated client sends its key once (book.sent); the host
-- keeps them (book.wait) and publishes them with its own when every seated
-- seat's is in, BOOK_WAIT after the game was over at the latest (s.keysTimer;
-- book.published); that event and every later one is final (f = true): only
-- a final event closes the book. A STD meanwhile publishes the keys kept
-- first (not final); a member that sees a final event without the key it sent
-- sends it once more (book.resent; a snapshot of the game over: book.synced). The last player but one
-- stands up: the host's key goes out before the table stops. A key leaves
-- only spent (Book.spend), always the one this game's commits came from. A
-- published key under my seat is mine (book.out, my kept key dropped) or
-- forged (book.forged, a bad hand). Also book.overAt (my clock when the game was over).
-- Rule 6a (core/Book.lua): my key stays while a hand I committed to has not
-- ended by an event (book.held); my key left at the end (book.done) and the
-- same game runs on under the same host: forged.
local Book = ns.Book

local C = ns.Const
local copy = ns.Util.copy
local kept, hot, watch, forge = Book.kept, Book.hot, Book.watch, Book.forge

-- Is my sealed game over (my key is then due)?
local function over(s)
  local e = s:engine()
  return e.sealed and s.status == "live" and s.state ~= nil and e.over(s.state) or false
end

-- A book action to the host: handled at once when I host, else whispered as ACT.
function Book.submit(s, a)
  if s.role == "host" then
    if s.mySeat then ns.Book.request(s, s.mySeat, a) end
  else
    s.client:send("WHISPER", s.host, ns.Session.message("ACT", { tid = s.tid, a = a }))
  end
end

-- The key of my commits of this game: sent, the book's, kept (spent or not), else Book.key.
local function myKey(s, book)
  book.key = book.sent or book.key or kept(s, book) or Book.key(s)
  return book.key
end

local function known(book, seat, m)
  for _, k in ipairs(book.keys) do if k.seat == seat and k.m == m then return true end end
end

-- A published key under my seat: mine is out (the kept key goes); another, from an event, is forged.
local function mine(s, book, m, judge)
  if m == book.sent or m == book.key or m == kept(s, book) then
    book.out = true
    if s.client.env.db then s.client.env.db.bookKeep = nil end
  elseif judge then
    forge(book)
  end
end

-- Everyone: the keys of a keys event {[seat] = key} of game g, seats ascending, under its seq.
function Book.addKeys(s, map, g)
  local book, seats = Book.of(s), {}
  if g ~= book.g then return end -- a key of another game
  for q in pairs(map) do seats[#seats + 1] = q end
  table.sort(seats)
  for _, q in ipairs(seats) do
    book.keys[#book.keys + 1] = { seat = q, q = s.seq, m = map[q], who = s.stake and s.seats[q] or nil } -- who (a staked table): local, never sent (Book.late)
    book.given[q] = true -- this seat's player's key is in (a sit renews it)
    if q == s.mySeat then mine(s, book, map[q], true) end
  end
  Book.run(s)
end

-- The newest BOOK_KEYS published keys as SNP.fr.k -> {{seat, q, m}, ...} | nil.
function Book.snap(s)
  local book, out = s:engine().sealed and s.book, {}
  if not (book and book.keys[1]) then return nil end
  for i = math.max(1, #book.keys - C.BOOK_KEYS + 1), #book.keys do
    out[#out + 1] = { book.keys[i].seat, book.keys[i].q, book.keys[i].m }
  end
  return out
end

-- The table hook: a keys event, every key under an occupied seat -> true.
function Book.table(s, a)
  if a.k ~= "book" or a.op ~= "keys" or type(a.m) ~= "table" then return nil end
  for q, m in pairs(a.m) do if not (s.seats[q] and Book.isKey(m)) then return nil end end
  return true
end

-- Host: a keys event of the keys kept; `final`: the publish, with my own key.
local function publish(s, book, final)
  local m, me = book.wait, s.mySeat or 0
  book.wait = {}
  if final then
    book.published = true
    if s.keysTimer then s.keysTimer.cancel(); s.keysTimer = nil end
    if s.seats[me] == s.client.env.me and not book.out and myKey(s, book) then
      Book.spend(s)
      book.sent, m[me] = book.key, book.key
    end
  end
  for q in pairs(m) do if not s.seats[q] then m[q] = nil end end
  s:play(0, { k = "book", op = "keys", m = m, g = book.g, f = final or nil })
end

-- Member: `key` to the host, spent first; `once` ("resent", "synced"): the
-- resend of the game over, once each.
local function send(s, book, key, once)
  if not key or once and (s.role == "host" or not over(s) or book.out or book[once]) then return end
  if once then book[once] = true end
  Book.spend(s)
  book.sent = key
  Book.submit(s, { k = "book", op = "key", m = key, g = book.g })
end

-- Host: ACT a = {k="book", op="key", m, g} of `seat`, the first of this game since its player sat.
function Book.take(s, seat, a)
  local book, m = Book.of(s), a.m
  if s.status ~= "live" or a.g ~= book.g or not Book.isKey(m) or book.given[seat] or known(book, seat, m) then return end
  book.given[seat] = true
  if not over(s) or book.published then
    return s:play(0, { k = "book", op = "keys", m = { [seat] = m }, g = book.g, f = book.published or nil })
  end
  book.wait[seat] = m
  Book.due(s)
end

-- Cash's react: once the game is over my key is due. Host: the publish when
-- every seated seat's is in, else BOOK_WAIT after the game was over (book.overAt:
-- the hand running at „Приключи“ is played out first, however long it takes).
function Book.due(s)
  if not over(s) then
    local old = s.book
    local runsOn = old ~= nil and s.status == "live" and s.state ~= nil and s.state.g == old.g -- the end I was told was false
    if old and old.done and runsOn then forge(old); old.sent, old.out = nil, nil end
    -- A held book stays a question (book.held: "unseen", not "forged") when the table merely
    -- stops being live (aborted, open: e2e soak seed 1300886); only the same game running on clears it.
    if old and (runsOn or not old.forged) then old.done, old.held = nil, nil end
    return
  end
  local book, now = Book.of(s), s.client.env.now()
  book.overAt = book.overAt or now
  if s.role ~= "host" then
    if s.mySeat and not (book.sent or book.out or book.held) and myKey(s, book) then
      if hot(s, book) then book.held = true; forge(book) else book.done = s.host; send(s, book, book.key) end
    end
    return
  end
  if book.published then return end
  local all = true
  for q, name in ipairs(s.seats) do all = all and (not name or q == s.mySeat or book.given[q]) end
  if all then return publish(s, book, true) end
  s.keysTimer = s.keysTimer or s.client:after(math.max(0, book.overAt + C.BOOK_WAIT - now), function()
    s.keysTimer = nil
    if s.client.session == s and s.role == "host" and s.book == book and not book.published then publish(s, book, true) end
  end)
end

-- Everyone, after every event (Cash's `applied`): keys (a final event of a
-- game over closes the book), the close, an abort, a stand that leaves fewer than minSeats.
function Book.event(s, seat, a)
  local k, book = seat == 0 and a.k, Book.of(s)
  watch(s, book)
  if k == "book" and a.op == "keys" then
    Book.addKeys(s, a.m, a.g)
    if a.f and over(s) then Book.close(s); send(s, book, book.sent, "resent") end
  elseif k == "abort" then
    book.published = s.role == "host" or nil -- nothing is waited for
    Book.close(s)
  elseif k == "stand" and s.role == "host" and s.status == "live" and s:seatedCount() < s:engine().minSeats
      and not book.out and s.seats[s.mySeat or 0] == s.client.env.me then
    publish(s, book, true)
  end
end

-- Member: a snapshot's keys (SNP.fr.k) not known yet (never judged: after a
-- relog my kept key may be gone); with the game over, a key I sent and lack goes again.
function Book.adopt(s, list)
  local book = Book.of(s)
  watch(s, book, true)
  for _, e in ipairs(type(list) == "table" and list or {}) do
    if type(e) == "table" and s.seats[e[1]] ~= nil and type(e[2]) == "number" and Book.isKey(e[3]) and not known(book, e[1], e[3]) then
      book.keys[#book.keys + 1] = { seat = e[1], q = e[2], m = e[3] }
      if e[1] == s.mySeat then mine(s, book, e[3]) end
    end
  end
  table.sort(book.keys, function(x, y) return x.q < y.q or (x.q == y.q and x.seat < y.seat) end)
  Book.run(s)
  send(s, book, book.sent, "synced")
end

-- Hook `leaving` (before my STD), seated in a live game: my key goes first (a host's with all it keeps).
function Book.leaving(s)
  local book = s:engine().sealed and s.status == "live" and s.mySeat and Book.of(s)
  if not book then return end
  if s.role == "host" and not book.out then
    publish(s, book, true)
  elseif s.role ~= "host" and not (book.sent or book.out) and myKey(s, book) then
    send(s, book, book.key)
  end
  s.client.bookHot = nil -- my key is out by my own will (rule 6a)
  if s.client.env.db then s.client.env.db.bookKeep = nil end
end

-- My table changed host: my wait ends; a key I sent and did not see published is due again.
function Book.hostChanged(s)
  if s.keysTimer then s.keysTimer.cancel(); s.keysTimer = nil end
  local book = s.book
  if not book then return end
  -- book.done names the host my key went to: only another host's name clears it (not its own new epoch).
  book.wait, book.sent, book.done = {}, book.out and book.sent or nil, book.done == s.host and book.done or nil
  if s.role == "host" then book.overAt = nil; Book.due(s) end -- my wait starts with my empty wait list
end

-- Host: „Приключи“, {k="close"} -> true | nil, code ("none", "nothost", "live": none or closing).
function Book.closeGame(client)
  local s = client.session
  if not s or s.role ~= "host" then return nil, s and "nothost" or "none" end
  if s.status ~= "live" or not s.state or not s:engine().apply(copy(s.state), 0, { k = "close" }) then return nil, "live" end
  s:play(0, { k = "close" })
  return true
end

-- Host: a STD while the game is over publishes the keys kept first (wrapped: no hook comes before the stand).
local onStand = ns.Session.onStand
function ns.Session:onStand(sender)
  local book = over(self) and ns.Util.seatOf(self.seats, sender) and self.book
  if book and next(book.wait) then publish(self, book, false) end
  return onStand(self, sender)
end

return Book
