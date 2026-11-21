local _, ns = ...

-- The fair deal at the table (spec 6.3), extension "fair" of the card engines:
-- the shuffle round, the private deal, the reveal and the audit.
--   Round h: the host opens it (EV {k="fair", op="open", h, d, p}); every
--   participant (the occupied seats, ascending) commits to a fresh seed (ACT ->
--   EV op "commit"); once every commit is in, each whispers its seed to the
--   dealer (SED), who checks it against the commit, builds the deck from all
--   seeds and deals: the deal EV carries only the faces a watcher may see.
--   The dealer whispers each player the faces only that seat sees (PRV) and
--   asks the host to show faces that turn public outside a play.
--   After the hand the dealer publishes every seed (EV op "reveal"); each
--   client replays the hand on the full deck (Fair.audit) and closes the round
--   with a verdict: "ok", "bad" (why), or "unseen" (I did not see it all).
--   Seeds still out FAIR_WAIT after the hand ended: the hand is "bad",
--   "noreveal" - closed by the next open, or after the last hand of a match by
--   EV {k="fair", op="noreveal", h} (host only) or at the latest by the next start.
-- Seeds, decks and private faces live in the session only; the round that
-- leaves the client (SNP.fr) is public: h, d, p, the commits, the stage, n.
--
-- Session fields: s.fair = the round {h, d, p, dealer (name), commits, stage
-- ("commit"|"seed"|"dealt"|"done"), seed, seedSent, seeds, deck, dealing, sent,
-- pub, priv, lied, base, log, q, fresh, revealed, out (the published seeds),
-- wantOpen (host: the engine asked for the next deal), replaced (the round an
-- open replaced while still "dealt")}; s.fairEarly[h][sender] = seeds that
-- reached the dealer before its last commit event; s.fairN = hands dealt in
-- this match; s.fairTimer (host) = the round's wait (FAIR_WAIT): for a
-- shuffle from the open until the deal, for a reveal from the engine's ask for
-- the next deck. s.fairLast = {h, verdict, why, dealer} of the last closed
-- hand; s.fairSeen = {ok, bad} hands closed so far in this match.
-- Nothing is sent from the `table` hook: an event sent from inside
-- Session:apply would overtake the one being applied. Sending happens in
-- `applied`, `adopted`, the act hook and the message handlers.
local Deal = {}
ns.Deal = Deal

local C = ns.Const
local Fair, Session = ns.Fair, ns.Session
local copy, seatOf, contains = ns.Util.copy, ns.Util.seatOf, ns.Util.contains

local STAGES = { commit = true, seed = true, dealt = true, done = true }

local function isInt(x) return type(x) == "number" and x % 1 == 0 end

-- The occupied seats, ascending.
local function occupiedSeats(seats)
  local out = {}
  for i = 1, #seats do
    if seats[i] then out[#out + 1] = i end
  end
  return out
end

-- The dealer's seat of the next hand: p[(n + 1) % #p + 1].
local function dealerOf(p, n)
  return p[(n + 1) % #p + 1]
end

-- May `seat` commit `c` to this round now?
local function commitFits(fair, seat, c)
  return fair.stage == "commit" and contains(fair.p, seat) and fair.commits[seat] == nil
    and type(c) == "string" and #c == 64
end

-- An open event's participants: exactly the occupied seats, strictly ascending.
local function participantsFit(s, p)
  if type(p) ~= "table" then return false end
  local want = occupiedSeats(s.seats)
  if #p ~= #want or #p < 2 then return false end
  for k = 1, #want do
    if p[k] ~= want[k] then return false end
  end
  return true
end

-- A round in stage "dealt" whose hand is finished: the match is over, or the
-- engine asks for the next deck.
function Deal.handOver(s)
  local fair = s.fair
  if not fair or fair.stage ~= "dealt" or not s.state then return false end
  if s:gameOver() then return true end
  local action = s:engine().system(s.state)
  return action ~= nil and action.need == "deck"
end

-- May the seeds `list` be revealed for my round now? An array of #p strings,
-- after the hand, for a round still "dealt" (a closed one takes no verdict).
local function revealFits(s, list)
  local fair = s.fair
  if fair.stage ~= "dealt" or type(list) ~= "table" or #list ~= #fair.p or not Deal.handOver(s) then return false end
  for k = 1, #fair.p do
    if type(list[k]) ~= "string" then return false end
  end
  return true
end

---------------------------------------------------------------------------
-- Requests to the host
---------------------------------------------------------------------------

-- Host: a fair action by `seat` (rule 4); it never reaches the engine.
local function request(s, seat, a)
  local fair, op = s.fair, a.op
  if not fair or s.status ~= "live" or a.h ~= fair.h then return end
  if op == "commit" then
    if commitFits(fair, seat, a.c) then s:play(0, { k = "fair", op = "commit", h = fair.h, seat = seat, c = a.c }) end
  elseif op == "deal" then
    if seat == fair.d and fair.stage == "seed" and type(a.deck) == "table" then
      s:play(0, { k = "deal", deck = a.deck })
    end
  elseif op == "show" then
    if seat == fair.d and fair.stage == "dealt" and type(a.cards) == "table" then
      s:play(0, { k = "show", cards = a.cards })
    end
  elseif op == "reveal" then
    if seat == fair.d and revealFits(s, a.s) then s:play(0, { k = "fair", op = "reveal", h = fair.h, s = copy(a.s) }) end
  end
end

-- A request to the host: handled at once when I host, else whispered as ACT.
function Deal.submit(s, a)
  if s.role == "host" then
    if s.mySeat then request(s, s.mySeat, a) end
  else
    s.client:send("WHISPER", s.host, Session.message("ACT", { tid = s.tid, a = a }))
  end
end

---------------------------------------------------------------------------
-- The round
---------------------------------------------------------------------------

local function stopWait(s)
  if s.fairTimer then s.fairTimer.cancel(); s.fairTimer = nil end
end

-- The one handler of s.fairTimer: it acts only on my own table, as its host,
-- for the same round. A hand whose reveal never came is given up: the next
-- round opens (and its open closes this one "noreveal"); after the last hand
-- of a match, which opens no round, EV {k="fair", op="noreveal", h} closes it.
-- While the wait is armed, `need` does not reopen a running shuffle.
local function fairWaitOver(s, h)
  s.fairTimer = nil
  local fair = s.fair
  if s.client.session ~= s or s.role ~= "host" or not fair or fair.h ~= h or fair.stage ~= "dealt" then return end
  if fair.wantOpen then
    Deal.open(s)
  elseif Deal.handOver(s) then
    s:play(0, { k = "fair", op = "noreveal", h = h })
  end
end

-- Host: the round's wait (FAIR_WAIT) for round h.
local function armWait(s, h)
  s.fairTimer = s.client:after(C.FAIR_WAIT, function() fairWaitOver(s, h) end)
end

-- Host: opens round h = seq + 1; always replaces the round's wait.
function Deal.open(s)
  local p = occupiedSeats(s.seats)
  if #p < 2 then return end
  local h = s.seq + 1
  stopWait(s)
  armWait(s, h)
  s:play(0, { k = "fair", op = "open", h = h, d = dealerOf(p, s.fairN or 0), p = p })
end

-- Closes `round` (default s.fair; false = no round) with a verdict "ok",
-- "bad" (why), "unseen" or "void"; emits "fair" and "session".
function Deal.close(s, verdict, why, round)
  local fair = round
  if fair == nil then fair = s.fair end
  local h, dealer
  if fair then h, dealer = fair.h, fair.dealer end
  s.fairLast = { h = h, verdict = verdict, why = why, dealer = dealer }
  local seen = s.fairSeen or { ok = 0, bad = 0 }
  if seen[verdict] then seen[verdict] = seen[verdict] + 1 end
  s.fairSeen = seen
  if fair then fair.stage = "done" end
  local client = s.client
  client.events:emit("fair", {
    tid = s.tid, game = s.game, h = h, verdict = verdict, why = why, dealer = dealer, at = client.env.epoch(),
  })
  Session.emit(client)
end

-- Everyone, once the seeds are out: the hand judged on what I saw of it.
local function judge(s)
  local fair = s.fair
  if fair.lied then return Deal.close(s, "bad", "dealt") end
  if not fair.base then return Deal.close(s, "unseen") end
  local verdict, why = Fair.audit(s:engine(), {
    tid = s.tid, h = fair.h, p = fair.p, commits = fair.commits, seeds = fair.out,
    base = fair.base, log = fair.log, priv = fair.priv,
  })
  Deal.close(s, verdict, why)
end

-- A deck index of my hidden cards whose face I do not know?
function Deal.missing(s)
  local engine, st = s:engine(), s.state
  if not (s.mySeat and st and engine.hidden) then return false end
  for _, i in ipairs(engine.hidden(st, s.mySeat)) do
    if st.deck[i] == nil then return true end
  end
  return false
end

-- Faces only I may see (from the dealer, or the dealer's own): kept in
-- fair.priv and, once dealt, shown on my state. Refused by the engine: the
-- dealer lied to me.
function Deal.learn(s, cards)
  local fair = s.fair
  if not fair then return end
  for i, f in pairs(cards) do fair.priv[i] = f end
  if fair.stage ~= "dealt" or next(fair.priv) == nil then return end
  local trial = copy(s.state)
  if s:engine().apply(trial, 0, { k = "show", cards = copy(fair.priv) }) then
    local changed = not ns.Util.same(trial, s.state)
    s.state = trial
    if changed then Session.emit(s.client) end
  else
    fair.lied = true
  end
end

-- Dealer: a seed from `sender`, taken when it matches the sender's commit.
local function takeSeed(s, sender, seed)
  local fair = s.fair
  local seat = seatOf(s.seats, sender)
  if type(seed) == "string" and seat and contains(fair.p, seat) and fair.commits[seat] ~= nil
      and Fair.commit(seed) == fair.commits[seat] then
    fair.seeds[seat] = seed
  end
end

-- Dealer: every participant's seed is in -> the deck, and the deal is asked for
-- with the faces a watcher sees.
local function tryDeal(s)
  local fair, engine = s.fair, s:engine()
  if fair.dealing or fair.stage ~= "seed" or s.mySeat ~= fair.d then return end
  local list = {}
  for k = 1, #fair.p do
    list[k] = fair.seeds[fair.p[k]]
    if not list[k] then return end
  end
  local deck = Fair.deck(engine.DECK, list, Fair.handId(s.tid, fair.h))
  local full = Fair.full(s.state, s.state.deck)
  if not engine.apply(full, 0, { k = "deal", deck = deck }) then return end
  local pub = engine.view(full, 0).deck
  fair.deck, fair.pub, fair.sent, fair.dealing = deck, pub, {}, true
  Deal.submit(s, { k = "fair", op = "deal", h = fair.h, deck = copy(pub) })
end

-- Dealer: the early seeds of my round are taken; older buckets are dropped.
local function takeEarly(s)
  local early, h = s.fairEarly, s.fair.h
  if not early then return end
  for sender, seed in pairs(early[h] or {}) do takeSeed(s, sender, seed) end
  for k in pairs(early) do
    if k <= h then early[k] = nil end
  end
end

-- Dealer, stage "dealt": faces public outside a play go to the host as one
-- show; every seated participant gets the faces only it sees, once.
function Deal.sync(s)
  local fair, engine = s.fair, s:engine()
  if not fair or fair.stage ~= "dealt" or not fair.deck or s.mySeat ~= fair.d then return end
  local full = Fair.full(s.state, fair.deck)
  local known = engine.view(s.state, 0).deck
  local function unsent(i, sent)
    return known[i] == nil and fair.pub[i] == nil and (sent == nil or sent[i] == nil)
  end
  local show = {}
  for i, f in pairs(engine.view(full, 0).deck) do
    if unsent(i) then show[i] = f end
  end
  if next(show) then
    for i, f in pairs(show) do fair.pub[i] = f end
    Deal.submit(s, { k = "fair", op = "show", h = fair.h, cards = copy(show) })
  end
  for _, q in ipairs(fair.p) do
    local name = s.seats[q]
    if name then
      local sent = fair.sent[q] or {}
      fair.sent[q] = sent
      local out = {}
      for i, f in pairs(engine.view(full, q).deck) do
        if unsent(i, sent) then out[i] = f end
      end
      if next(out) then
        for i, f in pairs(out) do sent[i] = f end
        if q == s.mySeat then
          Deal.learn(s, out)
        else
          s.client:send("WHISPER", name, Session.message("PRV", { tid = s.tid, h = fair.h, cards = out }))
        end
      end
    end
  end
end

-- Dealer, after the hand: every seed, in p order, to the host (once).
local function reveal(s)
  local fair, list = s.fair, {}
  for k = 1, #fair.p do
    list[k] = fair.seeds and fair.seeds[fair.p[k]]
    if not list[k] then return end
  end
  fair.revealed = true
  Deal.submit(s, { k = "fair", op = "reveal", h = fair.h, s = list })
end

-- Whatever my role owes the round now (idempotent).
function Deal.react(s)
  local fair = s.fair
  if not fair then return end
  local me = s.mySeat
  local part = me ~= nil and contains(fair.p, me)
  if fair.stage == "commit" then
    if part and not fair.seed and fair.commits[me] == nil then
      local env = s.client.env
      fair.seed = Fair.seed(function(lo, hi) return env.random(lo, hi) end)
      Deal.submit(s, { k = "fair", op = "commit", h = fair.h, c = Fair.commit(fair.seed) })
    end
  elseif fair.stage == "seed" then
    if not (part and fair.seed) then return end
    if me == fair.d then
      fair.seeds = fair.seeds or {}
      fair.seeds[me] = fair.seed
      takeEarly(s)
      tryDeal(s)
    elseif not fair.seedSent and fair.dealer then
      fair.seedSent = true
      s.client:send("WHISPER", fair.dealer, Session.message("SED", { tid = s.tid, h = fair.h, s = fair.seed }))
    end
  elseif fair.stage == "dealt" then
    Deal.learn(s, {})
    if me == fair.d and fair.deck then Deal.sync(s) end
    if me == fair.d and not fair.revealed and Deal.handOver(s) then reveal(s) end
  end
end

---------------------------------------------------------------------------
-- Messages
---------------------------------------------------------------------------

-- A seed I cannot take yet: one per sender, the latest.
local function keepEarly(s, sender, h, seed)
  local early = s.fairEarly or {}
  s.fairEarly = early
  for k, bucket in pairs(early) do
    bucket[sender] = nil
    if next(bucket) == nil then early[k] = nil end
  end
  early[h] = early[h] or {}
  early[h][sender] = seed
end

-- SED{tid, h, s}: a seed for the dealer.
local function onSeed(client, sender, m)
  local s = client.session
  if not s or s.tid ~= m.tid or not isInt(m.h) or type(m.s) ~= "string" then return end
  local fair = s.fair
  if fair and fair.h == m.h then
    if s.mySeat ~= fair.d or not seatOf(s.seats, sender) then return end
    if fair.stage == "commit" then return keepEarly(s, sender, m.h, m.s) end
    if fair.stage == "seed" then
      fair.seeds = fair.seeds or {}
      takeSeed(s, sender, m.s)
      tryDeal(s)
    end
  elseif (not fair or m.h > fair.h) and s.mySeat and seatOf(s.seats, sender) then
    keepEarly(s, sender, m.h, m.s)
  end
end

-- PRV{tid, h, cards}: faces only I see, from the dealer of my round.
local function onPrivate(client, sender, m)
  local s = client.session
  if not s or s.tid ~= m.tid then return end
  local fair = s.fair
  if not fair or fair.h ~= m.h or fair.dealer ~= sender or type(m.cards) ~= "table" then return end
  Deal.learn(s, m.cards)
end

ns.Member.handlers.SED = onSeed
ns.Member.handlers.PRV = onPrivate

---------------------------------------------------------------------------
-- Hooks
---------------------------------------------------------------------------

-- A round as SNP.fr carries it: {h, d, p, c, st, n}.
local function wellFormed(fr)
  if type(fr) ~= "table" or not isInt(fr.h) or type(fr.d) ~= "number" or type(fr.c) ~= "table"
      or not STAGES[fr.st] or type(fr.n) ~= "number" or type(fr.p) ~= "table" or #fr.p < 2 then
    return false
  end
  for k = 1, #fr.p do
    if type(fr.p[k]) ~= "number" or (k > 1 and fr.p[k] <= fr.p[k - 1]) then return false end
  end
  return contains(fr.p, fr.d)
end

ns.Ext.fair = {
  -- Host: the engine wants a deck. A shuffle still running with its wait armed
  -- is not opened again (the session offers `need` after every event).
  need = function(s, action)
    if action.need ~= "deck" or s.role ~= "host" then return end
    local fair = s.fair
    if fair and (fair.stage == "commit" or fair.stage == "seed") and s.fairTimer then return end
    -- The hand is over and its reveal is due: the next round waits for it
    -- (the wait is normally armed already, when the hand ended).
    if fair and fair.stage == "dealt" then
      fair.wantOpen = true
      if not s.fairTimer then armWait(s, fair.h) end
      return
    end
    Deal.open(s)
  end,

  -- Everyone: open, commit and reveal change only s.fair; anything else of k
  -- "fair" is refused. A round an open replaces while still "dealt" is closed
  -- by `applied`, not here.
  table = function(s, a)
    if a.k ~= "fair" then return nil end
    if a.op == "open" then
      if not isInt(a.h) or not participantsFit(s, a.p) or a.d ~= dealerOf(a.p, s.fairN or 0) then return nil end
      local old = s.fair
      s.fair = {
        h = a.h, d = a.d, p = copy(a.p), dealer = s.seats[a.d], commits = {}, stage = "commit",
        priv = {}, base = s:engine().snapshot(s.state), log = {},
        replaced = old and old.stage == "dealt" and old or nil,
      }
      return true
    elseif a.op == "reveal" then
      local fair = s.fair
      if not fair or a.h ~= fair.h or not revealFits(s, a.s) then return nil end
      fair.out = copy(a.s)
      return true
    elseif a.op == "noreveal" then
      local fair = s.fair
      if not fair or a.h ~= fair.h or fair.stage ~= "dealt" or not Deal.handOver(s) then return nil end
      return true
    elseif a.op == "commit" then
      local fair = s.fair
      if not fair or a.h ~= fair.h or not commitFits(fair, a.seat, a.c) then return nil end
      fair.commits[a.seat] = a.c
      for k = 1, #fair.p do
        if fair.commits[fair.p[k]] == nil then return true end
      end
      fair.stage = "seed"
      return true
    end
    return nil
  end,

  -- Host: a member's fair action is handled here and never played as it is.
  act = function(s, seat, a)
    if a.k ~= "fair" then return a end
    request(s, seat, a)
    return nil
  end,

  -- Everyone, after every event.
  applied = function(s, seat, a)
    local k = seat == 0 and a.k
    if k == "start" or k == "abort" then
      -- A new match while the last hand's seeds are still out: that hand is нередовна.
      if k == "start" and s.fair and s.fair.stage == "dealt" then Deal.close(s, "bad", "noreveal") end
      s.fair, s.fairN, s.fairEarly = nil, 0, nil
      if k == "start" then s.fairLast, s.fairSeen = nil, nil end
      stopWait(s)
      return
    end
    local fair = s.fair
    local op = k == "fair" and a.op
    -- A hand whose seeds never came out: closed before anything else.
    if op == "open" and fair.replaced then
      local old = fair.replaced
      fair.replaced = nil
      Deal.close(s, "bad", "noreveal", old)
    end
    -- A deal without a shuffle round holding every commit (a closed round is
    -- not judged again: the verdict belongs to no round).
    if k == "deal" and not (fair and fair.stage == "seed") then
      Deal.close(s, "bad", "commit", fair and fair.stage ~= "done" and fair or false)
      s.fair = nil
      return
    end
    if not fair then return end
    if a.k ~= "fair" and fair.log then fair.log[#fair.log + 1] = { seat, copy(a) } end
    if k == "deal" then
      fair.stage = "dealt"
      s.fairN = (s.fairN or 0) + 1
      stopWait(s) -- the shuffle's wait is over; the reveal's starts when the hand ends
    end
    fair.q = s.seq
    if op == "reveal" then
      judge(s)
      if s.role == "host" and fair.wantOpen then Deal.open(s) end
      return
    elseif op == "noreveal" then
      return Deal.close(s, "bad", "noreveal")
    end
    Deal.react(s)
    -- Host: the hand (or the match) is over and no reveal yet: its wait starts.
    if s.role == "host" and not s.fairTimer and s.fair == fair and Deal.handOver(s) then armWait(s, fair.h) end
  end,

  -- Member: the round from the host's snapshot (rule 10b).
  adopted = function(s, prev, m)
    local fr = m and m.fr
    if not wellFormed(fr) then
      s.fair = nil
      return
    end
    local fair = s.fair
    if fair and fair.h == fr.h then
      fair.commits, fair.stage = copy(fr.c), fr.st
      -- Events I missed: I cannot replay this hand.
      if m.q ~= fair.q then fair.base, fair.log = nil, nil end
    else
      fair = {
        h = fr.h, d = fr.d, p = copy(fr.p), dealer = s.seats[fr.d] or nil, commits = copy(fr.c),
        stage = fr.st, priv = {}, fresh = true,
      }
      s.fair = fair
    end
    fair.q = s.seq
    s.fairN = fr.n
    Deal.react(s)
  end,

  -- Host: the round as SNP.fr (public data only).
  snap = function(s)
    local fair = s.fair
    if not fair then return nil end
    return { h = fair.h, d = fair.d, p = copy(fair.p), c = copy(fair.commits), st = fair.stage, n = s.fairN or 0 }
  end,
}

return Deal
