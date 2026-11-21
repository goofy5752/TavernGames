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
-- Failures: a shuffle not dealt FAIR_WAIT after its open is opened again
-- (a new h, fresh seeds, the same dealer), and a stand during the shuffle
-- reopens it at once. A shuffle that had every commit and was not dealt
-- although nobody left closes "bad", "nodeal" (the dealer saw the seeds).
-- A player missing faces of its hand asks the dealer again (PRQ): at once
-- after adopting a dealt hand, else after FAIR_ASK_GAP. A dealer without its
-- deck (a reload) or whose seat stands mid-hand: the hand is void (EV seat 0
-- {k="void"}), nothing scores, and the deal is asked for again - from the
-- next seat (the count of deals is kept), so a void never buys the same
-- dealer another deck. Voids and no-deals are counted per dealer name and
-- match (s.fairVoids) and the status line names the dealer.
-- Fouls (fair.foul, see Deal.close): "mine" (my commit or seed was replaced),
-- "commit" (a commit changed), "round" (a snapshot changed the round or
-- skipped events unasked), "play" (an event my engine refused), "forged" (a
-- move or a void in my name that I did not make).
-- A member whose snapshot shows that a hand it held open was closed or
-- replaced closes it "unseen" (it missed the end). A snapshot of the same
-- dealt hand makes a reveal or void I asked for due again (it may have gone to
-- a host that is gone); a new host voids a dealt hand whose dealer left.
-- Seeds, decks and private faces live in the session only; the round that
-- leaves the client (SNP.fr) is public: h, d, p, the commits, the stage, n
-- (with no round open, only n).
--
-- Session fields: s.fair = the round {h, d, p, dealer (name), commits, stage
-- ("commit"|"seed"|"dealt"|"done"), seed, seedSent, seeds, deck, dealing, sent,
-- pub, priv, lied, base, log, q, fresh (adopted from a snapshot, not asked
-- yet), voidAsked, revealed, out (the published seeds), wantOpen (host: the
-- engine asked for the next deal), replaced (the round an open replaced while
-- still "dealt")}; s.fairEarly[h][sender] = seeds that reached the dealer
-- before its last commit event; s.fairN = hands dealt in this match;
-- s.fairTimer (host) = the round's wait (FAIR_WAIT): for a shuffle from the
-- open until the deal, for a reveal from the end of the hand. s.askTimer =
-- my next PRQ. s.fairLast = {h, verdict, why, dealer, n (the dealer's count
-- of voids and no-deals, on such a verdict)} of the last closed hand;
-- s.fairSeen = {ok, bad} hands closed so far in this match; s.fairVoids =
-- dealer name -> hands voided or not dealt; s.fairCry = {h, seat, name, why}
-- the last complaint of a seat (op "protest"), s.fairCries their count.
-- Nothing is sent from the `table` hook: an event sent from inside
-- Session:apply would overtake the one being applied. Sending happens in
-- `applied`, `adopted`, the act hook and the message handlers.
local Deal = {}
ns.Deal = Deal

local C = ns.Const
local Fair, Session = ns.Fair, ns.Session
local copy, seatOf, contains = ns.Util.copy, ns.Util.seatOf, ns.Util.contains

local STAGES = { commit = true, seed = true, dealt = true, done = true }

-- Reasons of "bad" that only the cheated client can see: it tells the table.
local PRIVATE = { mine = true, dealt = true, forged = true }

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

-- Evidence against the round, kept until it closes (the first one wins).
local function foul(fair, why)
  fair.foul = fair.foul or why
end

-- A commit for `seat` as the host shows it to me, in an event or a snapshot.
-- The first one seen is held for good (fair.held; the audit checks the seeds
-- against these): another value later is a foul. The commit under my own seat
-- must be the one of my seed; with no seed of mine it is taken only in a round
-- I got from a snapshot after a reload (fair.reload).
local function sawCommit(s, fair, seat, c)
  local mine = seat == s.mySeat
  local held = fair.held[seat]
  if held ~= nil then
    if held ~= c then foul(fair, mine and "mine" or "commit") end
    return
  end
  fair.held[seat] = c
  if mine and (fair.own or not fair.reload) and fair.own ~= c then foul(fair, "mine") end
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
  if op == "protest" then
    -- A seat says a hand was not fair to it: once per hand, for the round
    -- running or the last one closed.
    local last, cried = s.fairLast, s.fairCried or {}
    if s.status == "live" and PRIVATE[a.why] and isInt(a.h) and cried[seat] ~= a.h
        and ((fair and a.h == fair.h) or (last and a.h == last.h)) then
      cried[seat], s.fairCried = a.h, cried
      s:play(0, { k = "fair", op = "protest", h = a.h, seat = seat, why = a.why })
    end
    return
  end
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
  elseif op == "void" then
    -- The dealer lost its deck while the hand runs.
    if seat == fair.d and fair.stage == "dealt" and not Deal.handOver(s) then s:play(0, { k = "void" }) end
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
-- for the same round. A shuffle not dealt yet is opened again (a participant
-- is silent; Deal.open checks the engine still wants a deck). A hand whose
-- reveal never came is given up: the next round opens (and its open closes
-- this one "noreveal"); after the last hand of a match, which opens no round,
-- EV {k="fair", op="noreveal", h} closes it. While the wait is armed, `need`
-- does not reopen a running shuffle.
local function fairWaitOver(s, h)
  s.fairTimer = nil
  local fair = s.fair
  if s.client.session ~= s or s.role ~= "host" or not fair or fair.h ~= h then return end
  if fair.stage == "commit" or fair.stage == "seed" then
    Deal.open(s)
  elseif fair.stage == "dealt" then
    if fair.wantOpen then
      Deal.open(s)
    elseif Deal.handOver(s) then
      s:play(0, { k = "fair", op = "noreveal", h = h })
    end
  end
end

-- Host: the round's wait (FAIR_WAIT) for round h.
local function armWait(s, h)
  s.fairTimer = s.client:after(C.FAIR_WAIT, function() fairWaitOver(s, h) end)
end

-- Host: opens round h = seq + 1 while the engine wants a deck; always
-- replaces the round's wait.
function Deal.open(s)
  local p = occupiedSeats(s.seats)
  local action = s.state and s:engine().system(s.state)
  if #p < 2 or not (action and action.need == "deck") then return end
  local h = s.seq + 1
  stopWait(s)
  armWait(s, h)
  s:play(0, { k = "fair", op = "open", h = h, d = dealerOf(p, s.fairN or 0), p = p })
end

-- Closes `round` (default s.fair; false = no round) with a verdict "ok",
-- "bad" (why), "unseen" or "void"; emits "fair" and "session". A foul noted
-- against the round decides: "bad" with that reason, whatever else happened.
-- A reason only I can see is told to the table (ACT/EV op "protest").
function Deal.close(s, verdict, why, round)
  local fair = round
  if fair == nil then fair = s.fair end
  local h, dealer
  if fair then h, dealer = fair.h, fair.dealer end
  if fair and fair.foul then verdict, why = "bad", fair.foul end
  s.fairLast = { h = h, verdict = verdict, why = why, dealer = dealer }
  -- A hand the dealer gave up, or did not deal: counted against its name.
  if dealer and (verdict == "void" or why == "nodeal") then
    local voids = s.fairVoids or {}
    voids[dealer], s.fairVoids = (voids[dealer] or 0) + 1, voids
    s.fairLast.n = voids[dealer]
  end
  local seen = s.fairSeen or { ok = 0, bad = 0 }
  if seen[verdict] then seen[verdict] = seen[verdict] + 1 end
  s.fairSeen = seen
  if fair then fair.stage = "done" end
  local client = s.client
  client.events:emit("fair", {
    tid = s.tid, game = s.game, h = h, verdict = verdict, why = why, dealer = dealer, at = client.env.epoch(),
  })
  Session.emit(client)
  if verdict == "bad" and PRIVATE[why] and fair and s.mySeat then
    Deal.submit(s, { k = "fair", op = "protest", h = h, why = why })
  end
end

-- Everyone, once the seeds are out: the hand judged on what I saw of it. The
-- seed revealed for the seat I committed at must be the one I made.
local function judge(s)
  local fair = s.fair
  if fair.seed then
    for k = 1, #fair.p do
      if fair.p[k] == fair.seat and fair.out[k] ~= fair.seed then foul(fair, "mine") end
    end
  end
  if fair.foul then return Deal.close(s, "bad", fair.foul) end
  if fair.lied then return Deal.close(s, "bad", "dealt") end
  local verdict, why = Fair.audit(s:engine(), {
    tid = s.tid, h = fair.h, p = fair.p, commits = fair.held, seeds = fair.out,
    base = fair.base, log = fair.log, priv = fair.priv, faces = s.state and s.state.deck,
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

-- Dealer: the seeds of the round in p order, once every one is in.
local function seedsIn(fair)
  local list = {}
  for k = 1, #fair.p do
    list[k] = fair.seeds and fair.seeds[fair.p[k]]
    if not list[k] then return nil end
  end
  return list
end

-- Dealer: every participant's seed is in -> the deck, and the deal is asked for
-- with the faces a watcher sees.
local function tryDeal(s)
  local fair, engine = s.fair, s:engine()
  if fair.dealing or fair.stage ~= "seed" or s.mySeat ~= fair.d then return end
  local list = seedsIn(fair)
  if not list then return end
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
  local fair = s.fair
  local list = seedsIn(fair)
  if not list then return end
  fair.revealed = true
  Deal.submit(s, { k = "fair", op = "reveal", h = fair.h, s = list })
end

-- Participant: PRQ{tid, h}, send me all my faces again.
local function ask(s)
  local fair = s.fair
  if not fair.dealer then return end -- the dealer's seat is empty: the hand is void soon
  s.client:send("WHISPER", fair.dealer, Session.message("PRQ", { tid = s.tid, h = fair.h }))
end

-- Participant: asks again FAIR_ASK_GAP from now, and every FAIR_ASK_GAP after
-- that while a face of this round's hand is still missing (one timer).
local function askLater(s)
  if s.askTimer then return end
  local fair = s.fair
  s.askTimer = s.client:after(C.FAIR_ASK_GAP, function()
    s.askTimer = nil
    if s.client.session ~= s or s.fair ~= fair or fair.stage ~= "dealt" or not Deal.missing(s) then return end
    ask(s)
    askLater(s)
  end)
end

-- Whatever my role owes the round now (idempotent).
function Deal.react(s)
  local fair = s.fair
  if not fair then return end
  local me = s.mySeat
  local part = me ~= nil and contains(fair.p, me)
  if fair.stage ~= "dealt" then fair.fresh = nil end -- I see this deal happen: nothing to ask for
  if fair.stage == "commit" then
    if part and not fair.seed and fair.commits[me] == nil then
      local env = s.client.env
      fair.seed = Fair.seed(function(lo, hi) return env.random(lo, hi) end)
      fair.seat, fair.own = me, Fair.commit(fair.seed)
      Deal.submit(s, { k = "fair", op = "commit", h = fair.h, c = fair.own })
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
    if me == fair.d then
      if fair.deck then
        Deal.sync(s)
        if not fair.revealed and Deal.handOver(s) then reveal(s) end
      elseif not fair.voidAsked and not Deal.handOver(s) then
        -- My deck is gone (a reload): nobody can be dealt the rest of this hand.
        fair.voidAsked = true
        Deal.submit(s, { k = "fair", op = "void", h = fair.h })
      end
    elseif part and Deal.missing(s) then
      if fair.fresh then
        fair.fresh = nil
        ask(s)
      else
        askLater(s)
      end
    end
  end
end

-- New host with a dealt hand, on the next tick (an event sent before my
-- snapshots would reach members still waiting for one): a dealer whose seat no
-- longer holds it took the deck along and the hand is void (its own stand and
-- void may never have reached me); otherwise my reveal may have gone to the
-- old host, so I owe it again.
local function takeOver(s)
  local client, fair = s.client, s.fair
  client:after(0, function()
    if client.session ~= s or s.role ~= "host" or s.fair ~= fair then return end
    -- A shuffle goes on: my own deal, if I am its dealer, is asked for again.
    if fair.stage ~= "dealt" then return Deal.react(s) end
    if s.seats[fair.d] ~= fair.dealer then
      if not Deal.handOver(s) and s:seatedCount() >= s:engine().minSeats then s:play(0, { k = "void" }) end
      return
    end
    fair.revealed = nil
    Deal.react(s)
  end)
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

-- PRQ{tid, h}: a participant of my round lost its faces; the dealer with the
-- deck sends them all again.
local function onAsk(client, sender, m)
  local s = client.session
  if not s or s.tid ~= m.tid then return end
  local fair = s.fair
  if not fair or fair.h ~= m.h or fair.stage ~= "dealt" or not fair.deck or s.mySeat ~= fair.d then return end
  local seat = seatOf(s.seats, sender)
  if not seat or not contains(fair.p, seat) then return end
  fair.sent[seat] = {}
  Deal.sync(s)
end

ns.Member.handlers.SED = onSeed
ns.Member.handlers.PRV = onPrivate
ns.Member.handlers.PRQ = onAsk

---------------------------------------------------------------------------
-- Hooks
---------------------------------------------------------------------------

-- A round as SNP.fr carries it: {h, d, p, c, st, n}.
local function wellFormed(fr)
  if type(fr) ~= "table" or not isInt(fr.h) or not isInt(fr.d) or type(fr.c) ~= "table"
      or not STAGES[fr.st] or not isInt(fr.n) or fr.n < 0 or type(fr.p) ~= "table" or #fr.p < 2 then
    return false
  end
  for k = 1, #fr.p do
    if not isInt(fr.p[k]) or (k > 1 and fr.p[k] <= fr.p[k - 1]) then return false end
  end
  return contains(fr.p, fr.d)
end

-- Does the round of the snapshot m fit my table, as an open event would have
-- to (rule 10b)? Its seats exist and it is not from the future; the dealer is
-- the one the count of hands gives. A round new to me, from the host I know:
-- its number is above every round I have seen, and events I did not see lie
-- between. While a round new to me is still being shuffled its participants
-- are seated, and I am one of them unless I sat down after it opened.
local function fits(s, m, how)
  local fr, fair = m.fr, s.fair
  if not wellFormed(fr) or fr.h > m.q or fr.p[1] < 1 or fr.p[#fr.p] > #s.seats then return false end
  local known = fair ~= nil and fair.h == fr.h
  if not known and not (how.fresh or how.changed) then
    if m.q == how.q or fr.h <= math.max(fair and fair.h or 0, s.fairLast and s.fairLast.h or 0) then return false end
  end
  if fr.st == "dealt" or fr.st == "done" then
    return fr.n >= 1 and fr.d == dealerOf(fr.p, fr.n - 1)
  end
  if not known then
    for k = 1, #fr.p do
      if not s.seats[fr.p[k]] then return false end
    end
    if s.mySeat and not contains(fr.p, s.mySeat) and not (how.fresh or how.sat) then return false end
  end
  return fr.d == dealerOf(fr.p, fr.n)
end

-- Is the snapshot's round of my number the round I hold: the same
-- participants and dealer, and no commit I hold changed?
local function agrees(fair, fr)
  if fr.d ~= fair.d or not ns.Util.same(fr.p, fair.p) then return false, "round" end
  for seat, c in pairs(fr.c) do
    if fair.held[seat] ~= nil and fair.held[seat] ~= c then return false, "commit" end
  end
  return true
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
      -- Its number is its own place in the order of events (h = seq + 1).
      if a.h ~= s.seq + 1 or not participantsFit(s, a.p) or a.d ~= dealerOf(a.p, s.fairN or 0) then return nil end
      local old = s.fair
      s.fair = {
        h = a.h, d = a.d, p = copy(a.p), dealer = s.seats[a.d], commits = {}, held = {}, stage = "commit",
        priv = {}, base = s:engine().snapshot(s.state), log = {},
        replaced = old and (old.stage == "dealt" or old.stage == "seed" or (old.foul and old.stage ~= "done")) and old or nil,
      }
      return true
    elseif a.op == "protest" then
      return isInt(a.h) and type(a.seat) == "number" and s.seats[a.seat] and PRIVATE[a.why] and true or nil
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
      sawCommit(s, fair, a.seat, a.c)
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
      if k == "start" then
        s.fairLast, s.fairSeen, s.fairVoids, s.fairCry, s.fairCries, s.fairCried = nil, nil, nil, nil, nil, nil
      end
      stopWait(s)
      return
    end
    local fair = s.fair
    if k == "void" then
      -- The hand is annulled; the host's timers ask for the deal again. The
      -- count of deals stays, so the next seat deals it, not the same dealer.
      if s.role == "host" then stopWait(s) end
      local round = fair and fair.stage ~= "done" and fair or false
      -- I deal this hand, hold its deck and did not give it up: not my void.
      if round and round.d == s.mySeat and round.deck and not round.voidAsked then foul(round, "forged") end
      Deal.close(s, "void", nil, round)
      s.fair = nil
      return
    end
    local op = k == "fair" and a.op
    if op == "protest" then
      -- Somebody's own check of a hand failed where mine could not see it.
      if fair then fair.q = s.seq end
      s.fairCry = { h = a.h, seat = a.seat, name = s.seats[a.seat], why = a.why }
      s.fairCries = (s.fairCries or 0) + 1
      return
    end
    -- The round this open replaces, closed before anything else: a hand whose
    -- seeds never came out; a shuffle with every commit in that was not dealt
    -- although nobody left (the dealer saw the seeds and may be fishing for
    -- another deck: "nodeal" - but not on a client that knows a seed was
    -- missing, mine or one the dealer never got, or that its own deal was
    -- asked for and lost); a shuffle with a foul against it.
    if op == "open" and fair.replaced then
      local old = fair.replaced
      fair.replaced = nil
      if old.stage == "dealt" then
        Deal.close(s, "bad", "noreveal", old)
      elseif old.stage == "seed" and ns.Util.same(old.p, fair.p) then
        local me = s.mySeat
        local excused = me ~= nil and contains(old.p, me)
          and ((me ~= old.d and not old.seedSent) or (me == old.d and (old.dealing or not seedsIn(old))))
        Deal.close(s, excused and "unseen" or "bad", not excused and "nodeal" or nil, old)
      elseif old.foul then
        Deal.close(s, "unseen", nil, old)
      end
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
    if k == "stand" and s.role == "host" then
      -- A stand during the shuffle: the round restarts without that seat.
      if fair.stage == "commit" or fair.stage == "seed" then return Deal.open(s) end
      -- The dealer's seat stands mid-hand, taking the deck with it.
      if a.seat == fair.d and fair.stage == "dealt" and not Deal.handOver(s) and not s:gameOver()
          and s:seatedCount() >= s:engine().minSeats then
        return s:play(0, { k = "void" })
      end
    end
    Deal.react(s)
    -- Host: the hand (or the match) is over and no reveal yet: its wait starts.
    if s.role == "host" and not s.fairTimer and s.fair == fair and Deal.handOver(s) then armWait(s, fair.h) end
  end,

  -- Member: the round from the host's snapshot (rule 10b), checked as an open
  -- would be (fits). "unseen" is honest only when I came or logged in again
  -- mid-hand, the host changed, or I asked for the snapshot after losing an
  -- event (how.fresh / how.changed / how.asked, see Member.adopt). A snapshot
  -- my own host pushes on me that skips events is a foul ("round") on the
  -- round I hold and on the one it brings. So is my round coming back with
  -- other participants or another dealer, or gone or at another stage in a
  -- snapshot of the very event I am at.
  adopted = function(s, prev, m, how)
    how = how or { fresh = true }
    local fr, fair = m and m.fr, s.fair
    local good = fits(s, m, how)
    local pushed = not (how.fresh or how.changed or how.asked) and m.q ~= how.q
    local same = good and fair ~= nil and fr.h == fair.h
    if same then
      local ok, why = agrees(fair, fr)
      if not ok and how.changed then
        same = false -- a new host's round under my round's number: another round
      elseif not ok and why == "round" then
        foul(fair, "round")
      end
    end
    if fair and fair.stage ~= "done" then
      local still = m.q == how.q and not how.changed and not (same and fr.st == fair.stage)
      if pushed or still then foul(fair, "round") end
      -- A hand I still held open that the host has closed or replaced: I missed its end.
      local gone = not same or (fair.stage == "dealt" and fr.st ~= "dealt")
      if gone and (fair.stage == "dealt" or fair.foul) then Deal.close(s, "unseen", nil, fair) end
    end
    if not good then
      s.fair = nil
      -- No round open: the hands dealt so far still decide the next dealer.
      if type(fr) == "table" and isInt(fr.n) and fr.n >= 0 then s.fairN = fr.n end
      return
    end
    if same then
      for seat, c in pairs(fr.c) do sawCommit(s, fair, seat, c) end
      fair.commits, fair.stage = copy(fr.c), fr.st
      -- Events I missed: I cannot replay this hand.
      if m.q ~= fair.q then fair.base, fair.log = nil, nil end
      -- A reveal or void I asked for may have gone to a host that is gone:
      -- asked again (the host refuses a second one).
      fair.voidAsked = nil
      if fr.st == "dealt" then fair.revealed = nil end
    else
      fair = {
        h = fr.h, d = fr.d, p = copy(fr.p), dealer = s.seats[fr.d] or nil, commits = copy(fr.c),
        stage = fr.st, priv = {}, fresh = true, held = {}, reload = how.fresh or nil,
        foul = pushed and "round" or nil,
      }
      for seat, c in pairs(fr.c) do sawCommit(s, fair, seat, c) end
      s.fair = fair
    end
    fair.q = s.seq
    s.fairN = fr.n
    Deal.react(s)
  end,

  -- Host: the round as SNP.fr (public data only); with no round, only n.
  snap = function(s)
    local fair = s.fair
    if not fair then return { n = s.fairN or 0 } end
    return { h = fair.h, d = fair.d, p = copy(fair.p), c = copy(fair.commits), st = fair.stage, n = s.fairN or 0 }
  end,

  -- My table changed host. A demoted host drops its wait. A new host whose
  -- hand is over waits for the reveal (after the last hand of a match nothing
  -- else would; mid-match `need` finds the wait armed), and takes over a
  -- dealt hand once its snapshots are out.
  -- Member: an event of my host that does not apply. In a hand I have seen
  -- whole so far that is evidence, not bad luck: the resync that follows must
  -- not turn the hand into "unseen".
  refused = function(s)
    local fair = s.fair
    if fair and fair.stage == "dealt" and fair.base then foul(fair, "play") end
  end,

  -- Member: the host ordered a move for my seat that I did not send.
  forged = function(s)
    local fair = s.fair
    if fair and fair.stage ~= "done" then foul(fair, "forged") end
  end,

  hostChanged = function(s)
    local fair = s.fair
    -- The deal I asked for may have gone to the host that is gone: asked again
    -- (a member's next snapshot, or takeOver, makes my role react).
    if fair and fair.stage == "seed" then fair.dealing = nil end
    if s.role ~= "host" then return stopWait(s) end
    if not fair then return end
    -- A shuffle with every commit in goes on under a fresh wait (`need` would
    -- open it again at once, and that would read as the dealer not dealing).
    if not s.fairTimer and (Deal.handOver(s) or fair.stage == "seed") then armWait(s, fair.h) end
    if fair.stage == "seed" or fair.stage == "dealt" then takeOver(s) end
  end,
}

-- The table frame's fairness line -> locale key, argument | nil: nil for an
-- engine without the extension "fair".
function Deal.status(s)
  if not contains(s:engine().ext or {}, "fair") then return nil end
  local fair = s.fair
  if fair and fair.stage == "commit" then
    for _, q in ipairs(fair.p) do
      local name = s.seats[q]
      if q ~= s.mySeat and fair.commits[q] == nil and name then return "fair.waiting", name end
    end
    return "fair.shuffle"
  elseif fair and fair.stage == "seed" then
    return "fair.dealing", fair.dealer
  end
  local last, cry = s.fairLast, s.fairCry
  -- Another seat's complaint, unless my own last verdict is bad already.
  if cry and cry.name and cry.seat ~= s.mySeat and not (last and last.verdict == "bad") then
    return "fair.protest", cry.name
  end
  if not last then return nil end
  if last.verdict == "void" then
    -- By name; with the count from the dealer's second one in this match.
    if not last.dealer then return "fair.void" end
    if (last.n or 1) > 1 then return "fair.voidMany", last.dealer, last.n end
    return "fair.voidBy", last.dealer
  end
  return "fair.last", last.verdict
end

-- Does the fairness line warn (red)? A bad hand or a complaint in this match,
-- or a dealer who gave up or did not deal a second hand.
function Deal.alarm(s)
  local last, seen = s.fairLast, s.fairSeen
  for _, n in pairs(s.fairVoids or {}) do
    if n > 1 then return true end
  end
  return (last and last.verdict == "bad") or (seen and seen.bad > 0) or (s.fairCries or 0) > 0 or false
end

return Deal
