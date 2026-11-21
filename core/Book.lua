local _, ns = ...

-- The book of a sealed table (an engine with E.sealed: Холдем), the fair
-- deal of core/Deal.lua without a reveal a hand.
-- Rule 2, key and seeds: every seated client has one table key per sitting,
--   Fair.seed of its own (Book.key), kept in env.db.bookKeep = {tid, me, key,
--   g, h} so that it survives a /reload and a relog; g is the seq of the running
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
-- Rule 6a, my live hand: a member's key reveals, with the others', the deck of
-- every hand it committed a seed to, so it leaves at the game's end only when
-- I saw the hand I committed to last end event by event (the events come in
-- order, on the state they change; a snapshot is the host's bare word).
-- client.bookHot = {tid, g, n} is that hand (n = state.hand; kept as
-- bookKeep.h): set with my seed (Book.heat), dropped by the event that ends it
-- on a state where it ran (book.ran), by no snapshot. The game over with it
-- still set: my key stays (book.held) and the book is forged. After a /reload
-- only bookKeep.h is left: a snapshot that shows hand h running makes it hot
-- again, one whose hand count shows it ended is believed. My key left at the
-- end (book.done) and the same game runs on under the same host: forged too.
-- Rule 7, the check (core/BookCheck.lua): a hand is checked once, for every participant, a key
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
-- tried = {[h] = #keys}, lack = {[h] = seats}, did = {[h] = true} (sealed), closed, final, dirty, missing; BookKeys'};
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
    s.book = { rec = {}, open = {}, keys = {}, seen = { ok = 0, bad = 0, open = 0 }, n = 0, given = {}, g = g, wait = {}, tried = {}, lack = {}, did = {} }
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

-- My kept key of this game (env.db.bookKeep), or nil.
function Book.kept(s, book)
  local env = s.client.env
  local k = env.db and env.db.bookKeep
  if type(k) == "table" and k.tid == s.tid and k.me == env.me and k.g == book.g and Book.isKey(k.key) then return k.key end
end

-- The hand of this game I committed to and have not seen end -> n | nil.
function Book.hot(s, book)
  local h = s.client.bookHot
  return h and h.tid == s.tid and h.g == book.g and h.n or nil
end

-- My seed of the running hand is taken (Book.seedFor).
function Book.heat(s)
  local book, n = Book.of(s), s.state.hand
  s.client.bookHot = { tid = s.tid, g = book.g, n = n }
  if Book.kept(s, book) then s.client.env.db.bookKeep.h = n end
end

-- After every event, and every snapshot (`snap`): rule 6a.
function Book.watch(s, book, snap)
  local st, n, keep = s.state, Book.hot(s, book), Book.kept(s, book) and s.client.env.db.bookKeep
  local run = st ~= nil and s:engine().inHand(st)
  if snap and st and not n and keep and keep.h then
    if st.hand > keep.h or (st.hand == keep.h and not run) then keep.h = nil else s.client.bookHot = { tid = s.tid, g = book.g, n = keep.h } end
  elseif not snap and n and book.ran and not run and st.hand == n then
    s.client.bookHot = nil
    if keep then keep.h = nil end
  end
  book.ran = run
end

function Book.forge(book) book.forged, book.seen.bad = true, book.seen.bad + 1 end

-- My seed of hand h -> 32 hex | nil (an engine that is not sealed, or no seat).
function Book.seedFor(s, h)
  local key = s:engine().sealed and s.mySeat and Book.key(s)
  if not key then return nil end
  Book.heat(s) -- its commit binds my key to the hand that runs (core/BookKeys.lua, rule 6a)
  return Fair.handSeed(key, Fair.handId(s.tid, h))
end

-- The hand of my round is over (rule 5): its record goes into the book and the
-- round closes `verdict` ("sealed"; "void" for a hand the host annulled, whose
-- record holds the faces dealt before the void); with a foul or a lie against
-- it, "bad" at once. A hand is recorded and counted once (book.did): a
-- snapshot of a host that had not seen it end brings its round back, and it
-- ends again.
function Book.seal(s, verdict)
  local fair, book = s.fair, Book.of(s)
  local bad = (fair.foul or fair.lied) and (fair.foul or "dealt") or nil
  if book.did[fair.h] then return ns.Deal.close(s, bad and "bad" or verdict or "sealed", bad) end
  book.did[fair.h] = true
  book.n = book.n + 1
  if bad then
    book.seen.bad = book.seen.bad + 1
    return ns.Deal.close(s, "bad", bad)
  end
  local f = copy(s.state and s.state.deck or {})
  for i, x in pairs(fair.priv or {}) do f[i] = x end
  book.rec[fair.h] = { p = copy(fair.p), c = copy(fair.held), f = f, who = copy(fair.who) }
  book.open[#book.open + 1] = fair.h
  ns.Deal.close(s, verdict or "sealed")
end

-- The book actions (ACT {k="book"}, core/Cash.lua): the step's check and the host's handling.
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

-- Host: a book action by `seat`; it never reaches the engine. op "step": the
-- dealer of my round gives the faces of the step the engine waits for. op
-- "missing": the dealer of a shuffle in stage seed names the participants
-- whose seed it lacks (fair.missing; they sit out with it if the shuffle lapses).
function Book.request(s, seat, a)
  local fair, step = s.fair, a.a
  if not fair or s.status ~= "live" or a.h ~= fair.h or seat ~= fair.d then return end
  if a.op == "missing" and fair.stage == "seed" and type(a.seats) == "table" then
    local out = {}
    for _, q in ipairs(a.seats) do
      if q ~= seat and ns.Util.contains(fair.p, q) and not ns.Util.contains(out, q) then out[#out + 1] = q end
    end
    fair.missing = out
  end
  if a.op ~= "step" or fair.stage ~= "dealt" then return end
  local want = s:engine().system(s.state)
  if not (want and want.need == "faces" and type(step) == "table" and step.k == want.k and type(step.cards) == "table") then
    return
  end
  local ev = { k = step.k, cards = step.cards }
  local trial = copy(s.state)
  if not s:engine().apply(trial, 0, ev) or (ev.k == "street" and Book.faceless(trial, ev.cards)) then return end
  if ns.Deal.int.allPublic(s, ev, ev.cards) then s:play(0, ev) end
end

-- The hand on my state ended and I have not told it yet: event "hand" (Cash).
function Book.told(s)
  local st = s.state
  local last = st and st.last
  if not last or last.hand == s.handSeen then return end
  s.handSeen = last.hand
  local chips = {}
  for i, x in pairs(st.seats) do
    if x then chips[i] = x.chips end
  end
  local client = s.client
  client.events:emit("hand", {
    tid = s.tid, game = s.game, opt = copy(s.opt), n = last.hand, last = copy(last), chips = chips,
    names = copy(s.handNames or s.seats), at = client.env.epoch(),
  })
end

return Book
