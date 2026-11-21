local _, ns = ...

-- The book of a sealed table (an engine with E.sealed: Холдем), the fair
-- deal of core/Deal.lua without a reveal a hand.
-- Rule 2, key and seeds: every seated client has one table key per sitting,
--   Fair.seed of its own (Book.key), kept in env.db.bookKeep = {tid, me, key,
--   g} so that it survives a /reload and a relog; g is the seq of the running
--   game's `start` event, so a kept key is taken only for that game, and never
--   one that is already among the book's published keys. Before it is
--   published the key is in no message and never in the trace. A key I have
--   sent is spent (Book.spend: env.db.bookSpent, my own saved variables, the
--   newest SPENT_KEPT of them): Book.key never gives it again, whatever a
--   snapshot (state.g, the published keys) says. The seed of
--   hand h is Fair.handSeed(key, handId) (Book.seedFor); its commit is the
--   round's commit, as in stage B.
-- Rule 5, no reveal: when the hand ends (not E.inHand) every client writes
--   its record {p, c, f, who} (the participants, the commits it holds, every
--   face its state knows plus its private ones, the names at the open) into
--   its book and closes the round "sealed" (Book.seal). No seed is revealed,
--   none is waited for. A voided hand writes its record too (the faces dealt
--   before the void) and closes "void". A round with a foul against it, or
--   private faces the engine refused, closes "bad" as in stage B.
-- Rule 6, keys: core/BookKeys.lua (who sends its key when, the publish).
-- Rule 7, the check: a hand is checked once, for every participant, a key
--   published for its seat at or after the hand gives a seed whose commit is
--   the one held; every recorded face must then be the deck's ("ok", else
--   "bad", "deal"). A hand is tried once a count of keys, BOOK_BATCH a tick of
--   0.1 s. A closed book (the keys event of a game over, an abort) ends: the
--   hands without a key are `open`, the players whose key is missing named,
--   "book" (again after a late key). A new game's book runs the old one out.
-- Session fields: s.book = {key (mine), g, rec = {[h] = {p, c, f, who}},
-- open = {h, ...} (hands sealed and not checked yet, oldest first), keys =
-- {{seat, q, m}, ...} (the published keys), seen = {ok, bad, open}, n (hands
-- sealed or found bad in this game), given (seat -> its player's key came),
-- tried = {[h] = #keys}, closed, final, dirty, missing; core/BookKeys.lua's};
-- s.bookTimer, s.handSeen, s.handNames (the seats when the last hand began).
-- The engine state carries g too (state.g, set at `start` by core/Cash.lua),
-- so a snapshot tells which game it is of; a book of another game is ended
-- and replaced the first time it is asked for (Book.of).
local Book = {}
ns.Book = Book

local C = ns.Const
local Fair = ns.Fair
local copy = ns.Util.copy

-- The book of my game is replaced: the old one runs to its end first, then it
-- is dropped with what belongs to that game (hand names, timer, my kept key).
local function drop(s)
  if s.bookTimer then s.bookTimer.cancel(); s.bookTimer = nil end
  if s.book.n > 0 then Book.close(s, s.book, true) end
  s.book, s.handSeen, s.handNames = nil, nil, nil
  local db = s.client.env.db
  if db then db.bookKeep = nil end
end

-- The book of the game on my state, made on first use. A book of another game
-- (its g is not the state's: a `start`, or a snapshot of a new game) is
-- dropped first.
function Book.of(s)
  local g = s.state and s.state.g
  if s.book and s.book.g ~= g then drop(s) end
  if not s.book then
    s.book = { rec = {}, open = {}, keys = {}, seen = { ok = 0, bad = 0, open = 0 }, n = 0, given = {}, g = g, wait = {}, tried = {} }
  end
  return s.book
end

-- Is m a table key: 2 x SEED_BYTES lowercase hex characters?
function Book.isKey(m)
  return type(m) == "string" and #m == 2 * C.SEED_BYTES and m:find("^[0-9a-f]+$") ~= nil
end

local SPENT_KEPT = 32

-- May `key` still deal for me: neither published in the book nor spent by
-- me at this table (the spent list is mine alone; the host has no say in it)?
local function usable(s, book, key)
  for _, k in ipairs(book.keys) do
    if k.m == key then return false end
  end
  local env = s.client.env
  for _, x in ipairs(env.db and env.db.bookSpent or {}) do
    if x.tid == s.tid and x.me == env.me and x.key == key then return false end
  end
  return true
end

-- My key leaves my client: it is spent for good at this table, in my own
-- saved variables (bounded), before it is sent.
function Book.spend(s)
  local book, env = Book.of(s), s.client.env
  if not (book.key and env.db) then return end
  local spent = env.db.bookSpent or {}
  env.db.bookSpent = spent
  spent[#spent + 1] = { tid = s.tid, me = env.me, key = book.key }
  while #spent > SPENT_KEPT do table.remove(spent, 1) end
end

-- My table key for this game: the book's while it may still deal; else the
-- kept one, when it is mine, of this table and this game, and usable; else a
-- new one, kept (nil if no fresh draw is usable: a generator that repeats).
function Book.key(s)
  local book, env = Book.of(s), s.client.env
  if book.key and usable(s, book, book.key) then return book.key end
  local kept = env.db and env.db.bookKeep
  if type(kept) == "table" and kept.tid == s.tid and kept.me == env.me and kept.g == book.g
      and Book.isKey(kept.key) and usable(s, book, kept.key) then
    book.key = kept.key
  else
    book.key = nil
    for _ = 1, 4 do
      local key = Fair.seed(env, "book|" .. s.tid)
      if usable(s, book, key) then book.key = key; break end
    end
    if env.db and book.key then env.db.bookKeep = { tid = s.tid, me = env.me, key = book.key, g = book.g } end
  end
  return book.key
end

-- My seed of hand h -> 32 hex | nil (an engine that is not sealed, or no seat).
function Book.seedFor(s, h)
  local key = s:engine().sealed and s.mySeat and Book.key(s)
  if not key then return nil end
  return Fair.handSeed(key, Fair.handId(s.tid, h))
end

-- The hand of my round is over (rule 5): its record goes into the book and the
-- round closes `verdict` ("sealed"; "void" for a hand the host annulled, whose
-- record holds the faces dealt before the void); with a foul or a lie against
-- it, "bad" at once.
function Book.seal(s, verdict)
  local fair, book = s.fair, Book.of(s)
  book.n = book.n + 1
  if fair.foul or fair.lied then
    book.seen.bad = book.seen.bad + 1
    return ns.Deal.close(s, "bad", fair.foul or "dealt")
  end
  local f = copy(s.state and s.state.deck or {})
  for i, x in pairs(fair.priv or {}) do f[i] = x end
  book.rec[fair.h] = { p = copy(fair.p), c = copy(fair.held), f = f, who = copy(fair.who) }
  book.open[#book.open + 1] = fair.h
  ns.Deal.close(s, verdict or "sealed")
end

-- Does the street just dealt on `st` (the flop's three cards, else one) lack
-- a face in `cards`? The engine takes a street with any subset of its faces
-- on a view, so the table checks the step deals them all.
function Book.faceless(st, cards)
  local board = st.board or {}
  local n = st.street == 1 and 3 or 1
  for k = #board - n + 1, #board do
    if type(cards) ~= "table" or cards[board[k]] == nil then return true end
  end
  return false
end

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
    local h, v = book.open[i], nil
    if book.tried[h] ~= #book.keys then n, v, book.tried[h] = n + 1, Book.check(s, h, book), #book.keys end
    if v then
      table.remove(book.open, i)
      book.rec[h], book.seen[v] = nil, book.seen[v] + 1
      if book.final then book.seen.open, book.dirty = book.seen.open - 1, true end -- a late key: the end again
      if v == "bad" then client.events:emit("fair", { tid = s.tid, game = s.game, h = h, verdict = "bad", why = "deal", at = client.env.epoch() }) end
    else
      i = i + 1
    end
  end
end

-- The end of a closed book: the hands left are open and their players
-- without a key named (sorted by bytes); "book", "session".
local function finish(s, book)
  if book.final and not book.dirty then return end
  local names, seen, client = {}, {}, s.client
  for _, h in ipairs(book.open) do
    local _, missing = Book.check(s, h, book)
    for _, q in ipairs(missing or {}) do
      local name = book.rec[h].who[q]
      if name and not seen[name] then seen[name], names[#names + 1] = true, name end
    end
  end
  table.sort(names, ns.Util.byteLess)
  book.final, book.dirty, book.missing, book.seen.open = true, nil, names, #book.open
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

-- The book's line under the felt -> key, tone, arg, arg2 | nil (not sealed, no
-- book, or no hand ended yet); a book that ended: bad, else open (the first missing name), else ok.
function Book.status(s)
  local book = s.book
  if not (s:engine().sealed and book) then return nil end
  if book.seen.bad > 0 then return "seal.bad", "red", book.seen.bad end
  if book.final and book.seen.open > 0 then return "seal.open", "gold", book.seen.open, book.missing[1] end
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
