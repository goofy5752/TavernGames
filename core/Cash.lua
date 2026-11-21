local _, ns = ...

-- The cash table of a sealed engine (Холдем), extension "cash" (ns.Ext.cash;
-- engine.ext = {"fair", "cash"}: the fair hooks run first). The shuffle is
-- core/Deal.lua's, the book core/Book.lua's; this file plays the table around
-- them:
-- - a player sits down in a running game: the engine seats it on every client
--   ({k="join", seat}), with chips at once and cards from the next hand (on a
--   chair whose player stood up during this hand the engine marks the
--   leaver's hand gone: the newcomer owes no face of it and asks for none);
-- - the dealer deals every street (rule 4 of the sealed deal): on a view the
--   engine's next step needs its faces (E.system: {k, need = "faces"}), so
--   the dealer, which holds the deck, asks the host for it (ACT {k="book",
--   op="step", h, a = {k, cards}}) E.STREET_DELAY after it is due and again
--   every FAIR_ASK_GAP while the table stands there (s.stepTimer); the host
--   plays `a` at seat 0 when it is the step the engine waits for, it carries
--   every face the step deals (a street without them is refused) and it
--   publishes only faces a watcher may then see (allPublic). One event a
--   street; a folded or unshown hand is in no event. A street event that
--   lacks a face of its own cards is the foul "deal" on every client (only a
--   modified host plays one);
-- - a hand that is over is sealed into the book (Book.seal), a shuffle whose
--   hand was settled before the deal (leaves) is dropped; every client that
--   saw a hand end emits "hand" once (its state.last, the chips after it, the
--   names when it began);
-- - silence (host): a shuffle not dealt in FAIR_WAIT (hook `lapsed`) sits out
--   the participants whose commit is missing, or in stage seed its dealer
--   ({k="away", seat}); a step still not come FAIR_WAIT after it was due voids
--   the hand (every chip back) and sits the dealer out. A client that sees its
--   own seat away is here: it asks {k="back"} and is dealt in from the next
--   hand. The turn clock: core/Session.lua (armTimers) and Member.timedOut.
-- Nothing is sent from the `table` hook (core/DealHooks.lua says why).
-- Session fields: s.stepTimer (the dealer's step; on a host that does not
-- deal, the step's wait); s.handSeen (the hand number of the last state.last
-- I saw), s.handNames (the seats when the last hand began); s.backAsked (my
-- back is asked while my seat stays away); the round's fair.who = {[seat] =
-- name} of its participants at the open.
local Cash = {}
ns.Cash = Cash

local C = ns.Const
local Session = ns.Session
local copy, contains = ns.Util.copy, ns.Util.contains
local int = ns.Deal.int
local handDone, stopWait, allPublic, foul = int.handDone, int.stopWait, int.allPublic, int.foul

-- Does the street just dealt on `st` (the flop's three cards, else one) lack
-- a face in `cards`? The engine takes a street with any subset of its faces
-- on a view, so the table checks the step deals them all.
local function faceless(st, cards)
  local board = st.board or {}
  local n = st.street == 1 and 3 or 1
  for k = #board - n + 1, #board do
    if type(cards) ~= "table" or cards[board[k]] == nil then return true end
  end
  return false
end

-- A book action to the host: handled at once when I host, else whispered as ACT.
local request
function Cash.submit(s, a)
  if s.role == "host" then
    if s.mySeat then request(s, s.mySeat, a) end
  else
    s.client:send("WHISPER", s.host, Session.message("ACT", { tid = s.tid, a = a }))
  end
end

-- Host: a book action by `seat`; it never reaches the engine. op "step": the
-- dealer of my round gives the faces of the step the engine waits for.
function request(s, seat, a)
  local fair, step = s.fair, a.a
  if a.op ~= "step" or not fair or s.status ~= "live" or a.h ~= fair.h or seat ~= fair.d or fair.stage ~= "dealt" then return end
  local want = s:engine().system(s.state)
  if not (want and want.need == "faces" and type(step) == "table" and step.k == want.k and type(step.cards) == "table") then
    return
  end
  local ev = { k = step.k, cards = step.cards }
  local trial = copy(s.state)
  if not s:engine().apply(trial, 0, ev) or (ev.k == "street" and faceless(trial, ev.cards)) then return end
  if allPublic(s, ev, ev.cards) then s:play(0, ev) end
end

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
    Cash.submit(s, { k = "book", op = "step", h = fair.h, a = { k = due.k, cards = copy(due.cards) } })
  end
  if s.fair == fair and s.seq == seq then
    s.stepTimer = s.client:after(C.FAIR_ASK_GAP, function() ask(s, fair, seq) end)
  end
end

-- Host that does not deal: the step is FAIR_WAIT overdue and the table still
-- stands at the same event: the dealer is gone; the hand is void (every chip
-- back) and the dealer sits out.
local function overdue(s, fair, seq)
  s.stepTimer = nil
  if s.client.session ~= s or s.role ~= "host" or s.fair ~= fair or s.seq ~= seq or fair.stage ~= "dealt" then return end
  local d = fair.d
  s:play(0, { k = "void" })
  s:play(0, { k = "away", seat = d })
end

-- The step: armed again on every react, in a live game whose engine needs the
-- faces of a dealt round. The dealer that holds the deck asks; a host that
-- does not deal waits FAIR_WAIT for it.
local function armStep(s)
  if s.stepTimer then s.stepTimer.cancel(); s.stepTimer = nil end
  local fair, engine = s.fair, s:engine()
  if not (fair and fair.stage == "dealt" and s.status == "live" and s.state) then return end
  local want = engine.system(s.state)
  if not (want and want.need == "faces") then return end
  local seq = s.seq
  if fair.deck and s.mySeat == fair.d then
    s.stepTimer = s.client:after(engine.STREET_DELAY or 0, function() ask(s, fair, seq) end)
  elseif s.role == "host" and s.mySeat ~= fair.d then
    s.stepTimer = s.client:after(C.FAIR_WAIT, function() overdue(s, fair, seq) end)
  end
end

-- Host: the shuffle was not dealt in FAIR_WAIT (hook `lapsed`, before it is
-- opened again). In stage commit every participant whose commit is missing
-- sits out (its blind stays in the pot); in stage seed the dealer does, so
-- the deal passes to the next participant.
local function lapsed(s)
  local fair = s.fair
  if s.role ~= "host" or not fair then return end
  if fair.stage == "commit" then
    -- A round I took over as the new host has no fair.pend (its commits went
    -- to the old one): nobody is known to be silent. My own seat is here.
    for _, q in ipairs(fair.pend and fair.p or {}) do
      if not fair.pend[q] and q ~= s.mySeat then s:play(0, { k = "away", seat = q }) end
    end
  elseif fair.stage == "seed" then
    s:play(0, { k = "away", seat = fair.d })
  end
end

-- My seat sits out in a live game: I am here, so it is dealt in again from
-- the next hand ({k="back"}), asked once while it stays away (s.backAsked; a
-- snapshot asks again). A seat dealt into the running hand asks once that
-- hand is over: back, it would count again among the hand's players (rule
-- 18), and so in the shuffle reopened without it and in the dealer named.
local function comeBack(s)
  local st = s.state
  local mine = s.mySeat and st and st.seats[s.mySeat]
  if not (s.status == "live" and type(mine) == "table" and mine.away) then s.backAsked = nil; return end
  if s.backAsked or s:gameOver() or (s:engine().inHand(st) and contains(st.order or {}, s.mySeat)) then return end
  s.backAsked = true
  Session.act(s.client, { k = "back" })
end

-- The hand on my state ended and I have not told it yet: event "hand".
local function told(s)
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
  comeBack(s)
end

ns.Ext.cash = {
  -- Host: a book action is handled here and never played as it is.
  act = function(s, seat, a)
    if a.k ~= "book" then return a end
    request(s, seat, a)
    return nil
  end,

  -- Everyone, after every event (after the fair hooks).
  applied = function(s, seat, a)
    local k, engine = seat == 0 and a.k, s:engine()
    if k == "start" then
      -- A new game, a new book (Book.of replaces the old one).
      s.state.g = s.seq
      ns.Book.of(s)
    elseif k == "sit" and s.status == "live" and s.state then
      engine.apply(s.state, 0, { k = "join", seat = a.seat })
      ns.Book.of(s).given[a.seat] = nil
      -- A sit does not re-arm the timers, and two players may now be enough for a hand.
      if s.role == "host" and not s.state.turn then s:armTimers() end
    elseif k == "hand" then
      s.handNames = copy(s.seats)
    elseif k == "fair" and a.op == "open" and s.fair then
      s.fair.who = namesOf(s, s.fair.p)
      -- Host: the commits of a round I opened are collected here (a round I take over has none).
      if s.role == "host" then s.fair.pend = s.fair.pend or {} end
    elseif k == "street" and s.fair and s.fair.stage == "dealt" and faceless(s.state, a.cards) then
      foul(s.fair, "deal")
    end
    react(s)
    told(s)
  end,

  lapsed = lapsed,

  -- Member: the state of a snapshot (a book of another game is replaced by Book.of).
  adopted = function(s)
    local st = s.state
    if not st then return end
    ns.Book.of(s)
    s.handSeen = st.last and st.last.hand
    s.handNames = s.handNames or copy(s.seats)
    if s.fair and not s.fair.who then s.fair.who = namesOf(s, s.fair.p) end
    s.backAsked = nil
    react(s)
  end,
}

return Cash
