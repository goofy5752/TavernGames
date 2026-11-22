local _, ns = ...

-- The check of a sealed table's book (core/Book.lua, rule 7): every hand
-- against the published keys (core/BookKeys.lua), the end of a closed book
-- ("book"), and the book's line under the felt.
local Book = ns.Book

local C = ns.Const
local Fair = ns.Fair
local copy = ns.Util.copy

-- Rule 7, hand h of my book -> "ok" | "bad" (a face that is not the deck's)
-- | nil, missing (the participants without a key giving the commit held).
function Book.check(s, h, book)
  book = book or s.book
  local rec, hid, seeds, missing = book.rec[h], Fair.handId(s.tid, h), {}, {}
  for i, q in ipairs(rec.p) do
    for _, k in ipairs(book.keys) do
      local seed = k.seat == q and k.q >= h and Fair.handSeed(k.m, hid)
      if seed and Fair.commit(seed) == rec.c[q] then seeds[i] = seed; break end
    end
    if not seeds[i] then missing[#missing + 1] = q end
  end
  if missing[1] then return nil, missing end
  local deck = Fair.deck(s:engine().DECK, seeds, hid)
  for i, x in pairs(rec.f) do
    if deck[i] ~= x then return "bad" end
  end
  return "ok"
end

-- BOOK_BATCH hands not tried with this many keys (all of them with `all`): a
-- verdict takes the record out and is counted; a bad one is a "fair" event.
local function tick(s, book, all)
  local n, i, client = 0, 1, s.client
  while book.open[i] and (all or n < C.BOOK_BATCH) do
    local h, v, lack = book.open[i], nil, nil
    if book.rec[h] and book.tried[h] ~= #book.keys then
      n, book.tried[h], v, lack = n + 1, #book.keys, Book.check(s, h, book)
      book.lack[h] = lack -- the seats without a key, for the end
    end
    if not book.rec[h] then
      table.remove(book.open, i) -- no record: nothing to check
    elseif v then
      table.remove(book.open, i)
      book.rec[h], book.tried[h], book.seen[v] = nil, nil, book.seen[v] + 1
      if book.final then book.seen.open, book.dirty = book.seen.open - 1, true end -- a late key: the end again
      if v == "bad" then client.events:emit("fair", { tid = s.tid, game = s.game, h = h, verdict = "bad", why = "deal", at = client.env.epoch() }) end
    else
      i = i + 1
    end
  end
end

-- The end of a closed book (every hand tried): the hands left are open and
-- their players without a key named (sorted by bytes); "book", "session" (`quiet`: neither).
local function finish(s, book, quiet)
  if book.final and not book.dirty then return end
  local names, seen, client = {}, {}, s.client
  for _, h in ipairs(book.open) do
    for _, q in ipairs(book.lack[h] or {}) do
      local name = book.rec[h].who[q]
      if name and not seen[name] then seen[name], names[#names + 1] = true, name end
    end
  end
  table.sort(names, ns.Util.byteLess)
  book.final, book.dirty, book.missing, book.seen.open = true, nil, names, #book.open
  if quiet then return end
  client.events:emit("book", { tid = s.tid, game = s.game, hands = book.n, ok = book.seen.ok, bad = book.seen.bad,
    open = #book.open, missing = copy(names), at = client.env.epoch() })
  ns.Session.emit(client)
end

-- The check runs (s.bookTimer, 0.1 s) while a hand waits to be tried; then a closed book ends.
function Book.run(s, book)
  book = book or Book.of(s)
  for _, h in ipairs(book.open) do
    if book.tried[h] ~= #book.keys then
      s.bookTimer = s.bookTimer or s.client:after(0.1, function()
        s.bookTimer = nil
        if s.client.session == s and s.book == book then tick(s, book); Book.run(s, book) end
      end)
      return
    end
  end
  if book.closed then finish(s, book) end
end

-- The book closes; `now` (the old game's book at a new game): every hand tried and the end at once.
function Book.close(s, book, now)
  book = book or Book.of(s)
  book.closed = true
  if now then tick(s, book, true); finish(s, book) else Book.run(s, book) end
end

-- Does a published key already give the commit of seat q in hand h?
local function covered(book, h, q, hid, c)
  for _, k in ipairs(book.keys) do
    if k.seat == q and k.q >= h and Fair.commit(Fair.handSeed(k.m, hid)) == c then return true end
  end
  return false
end

-- A late key (core/StakesCashLate.lua): `name`'s table key, published by its own client after the
-- close, for its seats of the hands still open in my ended book that no published key covers.
-- A key is committed: one that gives none of those commits is a lie, not a gap, and those hands
-- are bad (book.cashBad too); one that gives some is published under those seats. The open hands
-- are then tried again and the book ends again ("book") -> true when it changed.
function Book.late(s, book, name, key)
  local tag = name .. "|" .. key
  book.lateSeen = book.lateSeen or {}
  if not book.final or book.lateSeen[tag] then return false end
  book.lateSeen[tag] = true
  local his, seats, hit = {}, {}, false
  for _, h in ipairs(book.open) do
    local rec, hid = book.rec[h], Fair.handId(s.tid, h)
    for _, q in ipairs(rec and rec.p or {}) do
      if rec.who[q] == name and not covered(book, h, q, hid, rec.c[q]) then
        his[h] = true
        if Fair.commit(Fair.handSeed(key, hid)) == rec.c[q] and not seats[q] then
          hit, seats[q] = true, true
          book.keys[#book.keys + 1] = { seat = q, q = s.seq, m = key }
        end
      end
    end
  end
  if not next(his) then return false end
  local i = 1
  while book.open[i] do
    local h = book.open[i]
    local v, lack
    if his[h] and not hit then v = "bad" else v, lack = Book.check(s, h, book) end
    if v then
      table.remove(book.open, i)
      book.rec[h], book.tried[h], book.seen[v] = nil, nil, book.seen[v] + 1
      if v == "bad" then book.cashBad = book.cashBad or {}; book.cashBad[h] = true end
    else
      book.lack[h], book.tried[h], i = lack, #book.keys, i + 1
    end
  end
  book.dirty = true
  finish(s, book, not (s.client.session == s and s.book == book)) -- another game's "book" would end its notes
  return true
end

-- The book's line under the felt -> key, tone, arg, arg2 | nil (not sealed, no
-- book, or no hand ended yet); a book that ended: bad, else open (the first missing name), else ok.
function Book.status(s)
  local book = s.book
  if not (s:engine().sealed and book) then return nil end
  if book.seen.bad > 0 then return "seal.bad", "red", book.seen.bad end
  if book.final and book.seen.open > 0 then return "seal.open", "gold", book.seen.open, book.missing[1] or "" end
  if book.final then return "seal.ok", "good", book.seen.ok end
  if book.n == 0 then return nil end
  return "seal.sealed", "inkDim", #book.open, book.seen.ok
end

-- The tooltip of the line -> {{tone, key, arg}, ...} | nil.
function Book.tip(s)
  local book = s:engine().sealed and s.book
  if not book then return nil end
  local out = { { "ink", "seal.tip" } }
  if book.seen.bad > 0 then out[#out + 1] = { "red", "seal.tip.bad", book.seen.bad } end
  for _, name in ipairs(book.final and book.missing or {}) do out[#out + 1] = { "gold", "seal.tip.open", name } end
  return out
end

return Book
