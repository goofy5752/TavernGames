local _, ns = ...

-- The cash table of a sealed engine (Холдем), extension "cash" (ns.Ext.cash;
-- engine.ext = {"fair", "cash"}: the fair hooks run first). The shuffle is
-- core/Deal.lua's, the book core/Book.lua's; this file plays the table around
-- them:
-- - a player sits down in a running game: the engine seats it on every client
--   ({k="join", seat, who}: its name at a staked table), with chips at once (a staked one's by its buy) and cards from the next hand (on a
--   chair whose player stood up during this hand the engine marks the
--   leaver's hand gone: the newcomer owes no face of it and asks for none);
-- - the dealer deals every street (rule 4 of the sealed deal): on a view the
--   engine's next step needs its faces (E.system: {k, need = "faces"}), so
--   the dealer, which holds the deck, asks the host for it (ACT {k="book",
--   op="step", h, a = {k, cards}}) E.STREET_DELAY after it is due and again
--   every FAIR_ASK_GAP while the table stands there (s.stepTimer; staked: s.stepAsks); the host
--   plays `a` at seat 0 when it is the step the engine waits for, it carries
--   every face the step deals (a street without them is refused) and it
--   publishes only faces a watcher may then see (allPublic). One event a
--   street; a folded or unshown hand is in no event. A street event that
--   lacks a face of its own cards is the foul "deal" on every client (only a
--   modified host plays one);
-- - a hand that is over is sealed into the book (Book.seal), a shuffle whose
--   hand was settled before the deal (leaves) is dropped; every client that
--   saw a hand end emits "hand" once (Book.told);
-- - silence (host): a shuffle not dealt in FAIR_WAIT (hook `lapsed`) sits out
--   the participants whose commit is missing, or in stage seed its dealer and
--   the seats it named as missing, the hand void first (staked: always) ({k="away", seat});
--   the step and the book actions: Book.request; a step not come FAIR_WAIT
--   after it was due voids the hand and sits the dealer out. A seat that sees
--   itself away asks {k="back"} once its hand is over (Member.comeBack); a
--   member flags an away or a void no honest host plays now (Member.unasked).
--   The turn clock: Session:armTimers and Member.timedOut.
-- - the book's keys and the close of the game: core/BookKeys.lua (op "key", hooks table, leaving).
-- Nothing is sent from the `table` hook (core/DealHooks.lua says why).
-- Session fields: s.stepTimer, s.stepWaits, s.dueKey, s.dueAt (armStep);
-- s.handSeen, s.handNames (the seats when the last hand began); s.backAsked;
-- s.forgedNext (a forged event before the round opened); the round's fair.who
-- = {[seat] = name} at the open, fair.openedAt (my clock), fair.missing.
local Cash = {}
ns.Cash = Cash

local C = ns.Const
local copy, contains = ns.Util.copy, ns.Util.contains
local int = ns.Deal.int
local handDone, stopWait, foul, revise = int.handDone, int.stopWait, int.foul, int.revise

-- A book action to the host (Book.submit); the host's „Приключи“ (Book.closeGame).
Cash.submit, Cash.close = ns.Book.submit, ns.Book.closeGame

-- The names of the participants p as the table sits now -> {[seat] = name}.
local function namesOf(s, p)
  local who = {}
  for _, q in ipairs(p) do who[q] = s.seats[q] or nil end
  return who
end

-- Dealer: the step the engine waits for, from my deck, to the host now and
-- every FAIR_ASK_GAP after it while the table stands at the same event.
local function ask(s, fair, seq)
  s.stepTimer = nil
  if s.client.session ~= s or s.fair ~= fair or s.seq ~= seq or fair.stage ~= "dealt" then return end
  local due = s:engine().system(ns.Fair.full(s.state, fair.deck))
  if due and not due.need and due.cards then
    Cash.submit(s, { k = "book", op = "step", h = fair.h, a = { k = due.k, cards = copy(due.cards) } }); if s.stake then ns.Stakes.stepAsked(s) end
  end
  if s.fair == fair and s.seq == seq then
    s.stepTimer = s.client:after(C.FAIR_ASK_GAP, function() ask(s, fair, seq) end)
  end
end

-- The step my state waits for, the faces of a street or of the showdown of
-- a dealt round, as a key "h:k:board size" -> string | nil.
local function dueKey(s)
  local fair = s.fair
  if not (fair and fair.stage == "dealt" and s.status == "live" and s.state) then return nil end
  local want = s:engine().system(s.state)
  return want and want.need == "faces" and (fair.h .. ":" .. want.k .. ":" .. #s.state.board) or nil
end

-- Host: the step is FAIR_WAIT overdue and still the one due: the dealer is
-- gone; the hand is void (every chip back) and the dealer sits out.
local function overdue(s, fair, key)
  s.stepTimer = nil
  if s.client.session ~= s or s.role ~= "host" or s.fair ~= fair or dueKey(s) ~= key then return end
  local d = fair.d
  s:play(0, { k = "void" })
  s:play(0, { k = "away", seat = d })
end

-- Dealer, stage seed: the participants whose seed has not reached me, to the
-- host (op "missing"), FAIR_WAIT / 2 after the open.
local function name(s, fair)
  s.stepTimer = nil
  if s.client.session ~= s or s.fair ~= fair or fair.stage ~= "seed" or s.mySeat ~= fair.d then return end
  local missing = {}
  for _, q in ipairs(fair.p) do
    if q ~= fair.d and not (fair.seeds and fair.seeds[q]) then missing[#missing + 1] = q end
  end
  if #missing > 0 then Cash.submit(s, { k = "book", op = "missing", h = fair.h, seats = missing }) end
end

-- My round's timer (s.stepTimer), on every react. s.dueKey/s.dueAt: the step
-- due and my env.now() when it became due (nil: due already in a snapshot).
-- - The dealer that holds the deck asks for the step STREET_DELAY after every
--   event, again every FAIR_ASK_GAP (`ask`).
-- - The host, unless it deals with its deck, voids the hand FAIR_WAIT after
--   the step became due; other events (a sit, a stand) do not restart that
--   wait (s.stepWaits = the key it waits on).
-- - The dealer of a round in stage seed names the seats whose seed it lacks.
local function armStep(s)
  local fair, key, now = s.fair, dueKey(s), s.client.env.now()
  if key ~= s.dueKey then s.dueKey, s.dueAt = key, now end
  local dealing = key and fair.deck and s.mySeat == fair.d
  local waits = key and not dealing and s.role == "host" and key
  local names = fair and fair.stage == "seed" and s.mySeat == fair.d and s.status == "live" and ("seed:" .. fair.h)
  local keep = waits or names or nil
  if keep and s.stepTimer and s.stepWaits == keep then return end
  if s.stepTimer then s.stepTimer.cancel(); s.stepTimer = nil end
  s.stepWaits = keep
  if waits then
    s.stepTimer = s.client:after(math.max(0, (s.dueAt or now) + C.FAIR_WAIT - now), function() overdue(s, fair, key) end)
  elseif names then
    local at = math.max(C.FAIR_ASK_GAP, (fair.openedAt or now) + C.FAIR_WAIT / 2 - now)
    s.stepTimer = s.client:after(at, function() name(s, fair) end)
  elseif dealing then
    local seq = s.seq
    s.stepTimer = s.client:after(s:engine().STREET_DELAY or 0, function() ask(s, fair, seq) end)
  end
end

-- Host: the shuffle was not dealt in FAIR_WAIT (hook `lapsed`, before it is
-- opened again). In stage commit every participant whose commit is missing
-- sits out (its blind stays in the pot; staked: the hand is void first); in
-- stage seed the dealer does, and when it named seats as missing (op "missing";
-- staked: always) the hand is void first: naming seats takes nobody's blind (E5).
local function lapsed(s)
  local fair = s.fair
  if s.role ~= "host" or not fair then return end
  if fair.stage == "commit" then
    -- A round I took over as the new host has no fair.pend (its commits went
    -- to the old one): nobody is known to be silent. My own seat is here.
    for _, q in ipairs(fair.pend and fair.p or {}) do
      if not fair.pend[q] and q ~= s.mySeat then if s.stake and s:engine().inHand(s.state) then s:play(0, { k = "void" }) end; s:play(0, { k = "away", seat = q }) end
    end
  elseif fair.stage == "seed" then
    local named = fair.missing or {}
    s.lapseOut = s.lapseOut or {}
    if #named > 0 or s.stake then s:play(0, { k = "void" }) end
    s:play(0, { k = "away", seat = fair.d })
    for _, q in ipairs(named) do
      -- Back only once a hand has been dealt without it (the act hook holds its back).
      if q ~= s.mySeat then s.lapseOut[q] = { h = s.state.hand }; s:play(0, { k = "away", seat = q }) end
    end
  end
end

-- Host: no hand can start without the seats a lapse holds out (heads-up; the
-- rest named or sitting out): those that asked are back, until one can.
local function release(s)
  local e = s:engine()
  for q, out in pairs(s.role == "host" and s.lapseOut or {}) do
    if out.back and not (e.inHand(s.state) or e.system(s.state)) then s.lapseOut[q] = nil; s:play(q, { k = "back" }) end
  end
end

-- Whatever the table owes my round now: a dealt hand that is over goes into
-- the book; a shuffle whose hand is over (leaves settled it before the deal)
-- is dropped; then the step, and my seat comes back if it sits out.
local function react(s)
  local fair = s.fair
  if fair and handDone(s) then
    if fair.stage == "dealt" then
      ns.Book.seal(s)
    elseif fair.stage == "commit" or fair.stage == "seed" then
      s.fair = nil
      ns.DealKeep.clear(s, fair)
      if s.role == "host" then stopWait(s) end
    end
  end
  armStep(s)
  ns.Member.comeBack(s)
  release(s)
  ns.Book.due(s)
  -- A forged event that ended the hand before any shuffle opened: my last hand carries it.
  local last = s.fairLast
  local open = s.fair and s.fair.stage ~= "done"
  if s.forgedNext and not open and not s:engine().inHand(s.state) and last then
    s.forgedNext = nil
    if last.verdict ~= "bad" then revise(s) end
  end
end

ns.Ext.cash = {
  -- Host: a book action is handled here and never played as it is. A seat
  -- dealt into the running hand is back only once it is over (comeBack).
  act = function(s, seat, a)
    local st = s.state
    if a.k == "back" and st and s:engine().inHand(st) and contains(st.order or {}, seat) then return nil end
    local out = a.k == "back" and s.lapseOut and s.lapseOut[seat]
    if out then out.back = true; release(s); return nil end
    if a.k ~= "book" then return a end
    if a.op == "key" then ns.Book.take(s, seat, a) else ns.Book.request(s, seat, a) end
    return nil
  end,

  -- Everyone, after every event (after the fair hooks).
  applied = function(s, seat, a)
    local k, engine = seat == 0 and a.k, s:engine()
    if k == "start" then
      -- A new game, a new book (Book.of replaces the old one).
      s.state.g = s.seq
      ns.Book.of(s)
      s.forgedNext, s.lapseOut = nil, nil
    elseif k == "sit" and s.status == "live" and s.state then
      engine.apply(s.state, 0, { k = "join", seat = a.seat, who = s.stake and a.name or nil }) -- a staked seat's name
      ns.Book.of(s).given[a.seat] = nil
      if s.lapseOut then s.lapseOut[a.seat] = nil end -- a newcomer is not the seat a lapse named
      -- A sit does not re-arm the timers, and two players may now be enough for a hand.
      if s.role == "host" and not s.state.turn then s:armTimers() end
    elseif k == "hand" then
      s.handNames = copy(s.seats)
    elseif k == "fair" and a.op == "open" and s.fair then
      s.fair.who = namesOf(s, s.fair.p)
      s.fair.openedAt = s.client.env.now()
      -- Host: the commits of a round I opened are collected here (a round I take over has none).
      if s.role == "host" then s.fair.pend = s.fair.pend or {} end
      if s.forgedNext then foul(s.fair, "forged"); s.forgedNext = nil end
    elseif k == "deal" and s.lapseOut and s.role == "host" then
      -- Host: a hand dealt without the seats a lapse named; they are back now if they asked.
      for q, out in pairs(s.lapseOut) do
        if s.state.hand > out.h then s.lapseOut[q] = nil; if out.back then s:play(q, { k = "back" }) end end
      end
    elseif k == "street" and s.fair and s.fair.stage == "dealt" and ns.Book.faceless(s.state, a.cards) then
      foul(s.fair, "deal")
    end
    ns.Book.event(s, seat, a)
    react(s)
    ns.Book.told(s)
  end,
  table = ns.Book.table, -- a keys event (Book.event applies it)
  still = function(_, seat, a) return seat == 0 and a.k == "book" or nil end, -- a key leaves the clock alone
  leaving = ns.Book.leaving,

  lapsed = lapsed,

  -- A new host waits for an overdue step itself; a demoted one stops.
  -- A member's state may come from the new host's snapshot: a step due only
  -- there is undated (Member.unasked accepts its void).
  hostChanged = function(s)
    if not s.state then return end
    local key = dueKey(s)
    if key ~= s.dueKey then s.dueKey, s.dueAt = key, nil end
    armStep(s)
    if s.role == "host" then s.backAsked, s.lapseOut = nil, nil; ns.Member.comeBack(s) end -- a held seat that hosts now asks itself
    ns.Book.hostChanged(s)
  end,

  -- Member: a forged event while no round runs (the hand is dealt in, its
  -- shuffle not open yet, Member.unasked): the round that opens next carries it.
  forged = function(s)
    if not (s.fair and s.fair.stage ~= "done") then s.forgedNext = true end
  end,

  -- Member: the state of a snapshot (a book of another game is replaced by Book.of) and its keys.
  adopted = function(s, _, m)
    local st = s.state
    if not st then return end
    ns.Book.adopt(s, type(m) == "table" and type(m.fr) == "table" and m.fr.k or nil)
    s.handSeen = st.last and st.last.hand
    s.handNames = s.handNames or copy(s.seats)
    if s.fair and not s.fair.who then s.fair.who = namesOf(s, s.fair.p) end
    s.backAsked = nil
    local key = dueKey(s)
    if key ~= s.dueKey then s.dueKey, s.dueAt = key, nil end
    react(s)
  end,
}

return Cash
