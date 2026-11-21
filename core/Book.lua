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
--   none is waited for. A round with a foul against it, or private faces the
--   engine refused, closes "bad" as in stage B.
-- Rule 6, keys: a player who stands up publishes its key first (ACT
--   {k="book", op="key"} -> EV {k="book", op="keys", m = {[seat] = key}}); at
--   the close of the game every seated client sends its key, and the host
--   publishes them in one event (at the latest BOOK_WAIT after the close).
-- Rule 7, the check: a hand is checked once, for every participant, a key
--   published for its seat at or after the hand gives a seed whose commit is
--   the one held; every recorded face must then be the deck's ("ok", else
--   "bad", "deal"). BOOK_BATCH hands a tick of 0.1 s. Hands still without a
--   key when the book closes stay `open`, and their missing players are named.
-- Session fields: s.book = {key (mine), g, rec = {[h] = {p, c, f, who}},
-- open = {h, ...} (hands sealed and not checked yet, oldest first), keys =
-- {{seat, q, m}, ...} (the published keys), seen = {ok, bad, open}, n (hands
-- sealed or found bad in this game), given (host: seat -> its key came since
-- it sat)}; s.handSeen, s.handNames (the seats when the last hand began). The
-- engine state carries g too (state.g, set at `start` by core/Cash.lua), so a
-- snapshot tells which game it is of; a book of another game is ended and
-- replaced the first time it is asked for (Book.of).
local Book = {}
ns.Book = Book

local C = ns.Const
local Fair = ns.Fair
local copy = ns.Util.copy

-- The book of my game is replaced: the old one is dropped with what belongs to
-- that game (its hand names, its timer, my kept key).
local function drop(s)
  if s.bookTimer then s.bookTimer.cancel(); s.bookTimer = nil end
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
    s.book = { rec = {}, open = {}, keys = {}, seen = { ok = 0, bad = 0, open = 0 }, n = 0, given = {}, g = g }
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
-- round closes "sealed"; with a foul or a lie against it, "bad" at once.
function Book.seal(s)
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
  ns.Deal.close(s, "sealed")
end

-- The book's line under the felt -> key, tone, arg, arg2 | nil (nil for an
-- engine that is not sealed, without a book, or before the first hand ends).
function Book.status(s)
  local book = s.book
  if not (s:engine().sealed and book) then return nil end
  if book.seen.bad > 0 then return "seal.bad", "red", book.seen.bad end
  if book.n == 0 then return nil end
  return "seal.sealed", "inkDim", #book.open, book.seen.ok
end

return Book
