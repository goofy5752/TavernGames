local _, ns = ...

-- The `ns.Ext.fair` hooks of the fair deal (core/Deal.lua describes the round
-- and its session fields) and the checks of a snapshot's round (SNP.fr):
-- wellFormed, fits, agrees. Deal's private helpers come only through
-- Deal.int; this file is loaded right after core/Deal.lua. The dealer of a
-- round is Deal's dealerFor (the engine's E.dealer, else the count of hands),
-- in the open event's check and in `fits`.
-- Nothing is sent from the `table` hook: an event sent from inside
-- Session:apply would overtake the one being applied. Sending happens in
-- `applied`, `adopted`, the act hook and the message handlers.
local Deal = ns.Deal
local int = Deal.int

local copy, contains = ns.Util.copy, ns.Util.contains
local isInt, STAGES, PRIVATE, foul = int.isInt, int.STAGES, int.PRIVATE, int.foul
local sawCommit, commitFits, participantsFit, revealFits = int.sawCommit, int.commitFits, int.participantsFit, int.revealFits
local dealerOf, dealerFor, handDone = int.dealerOf, int.dealerFor, int.handDone
local armWait, stopWait, revise = int.armWait, int.stopWait, int.revise
local seedsIn, takeOver, request, judge = int.seedsIn, int.takeOver, int.request, int.judge

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
-- to (rule 10b)? Its seats exist and it is not from the future. The dealer,
-- for a shuffle and for a dealt hand still running, is dealerFor on the
-- snapshot's state (s.state is already the snapshot's) and count of hands.
-- Once the hand is over, or the round done, an engine naming the dealer has
-- moved on (after the score or a pass-out `first` is the next deal's): the
-- dealer need only be a participant; without E.dealer the count still names
-- it. A round new to me, from the host I know: its number is above every
-- round I have seen, and events I did not see lie between. While a round new
-- to me is still being shuffled its participants are seated, and I am one of
-- them unless I sat down after it opened.
local function fits(s, m, how)
  local fr, fair = m.fr, s.fair
  if not wellFormed(fr) or fr.h > m.q or fr.p[1] < 1 or fr.p[#fr.p] > #s.seats then return false end
  local known = fair ~= nil and fair.h == fr.h
  if not known and not (how.fresh or how.changed) then
    if m.q == how.q or fr.h <= math.max(fair and fair.h or 0, s.fairLast and s.fairLast.h or 0) then return false end
  end
  if fr.st == "dealt" or fr.st == "done" then
    if fr.n < 1 then return false end
    if fr.st == "dealt" and not handDone(s) then return fr.d == dealerFor(s, fr.p, fr.n - 1) end
    return s:engine().dealer ~= nil or fr.d == dealerOf(fr.p, fr.n - 1) -- wellFormed: d is in p
  end
  if not known then
    for k = 1, #fr.p do
      if not s.seats[fr.p[k]] then return false end
    end
    if s.mySeat and not contains(fr.p, s.mySeat) and not (how.fresh or how.sat) then return false end
  end
  return fr.d == dealerFor(s, fr.p, fr.n)
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
      if a.h ~= s.seq + 1 or not participantsFit(s, a.p) or a.d ~= dealerFor(s, a.p) then return nil end
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
        s.fairLast, s.fairSeen, s.fairVoids, s.fairCry, s.fairCried, s.fairSaid = nil, nil, nil, nil, nil, nil
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
      -- A seat claims its own check of hand h failed where mine cannot see
      -- it. Nobody can verify that: it is kept as a claim about that hand
      -- (Deal.claim) and changes no verdict of mine. Under my own seat it is
      -- mine only if I sent it; otherwise somebody speaks in my name: the
      -- running round is marked, or the hand I closed last turns "forged".
      if fair then fair.q = s.seq end
      s.fairCry = { h = a.h, seat = a.seat, name = s.seats[a.seat], why = a.why }
      if a.seat == s.mySeat and not (s.fairSaid and s.fairSaid[a.h]) then
        local last = s.fairLast
        if fair and fair.stage ~= "done" and (fair.h == a.h or not (last and last.h == a.h)) then
          foul(fair, "forged")
        elseif last and last.h == a.h and last.verdict ~= "bad" then
          revise(s)
        end
      end
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
