local _, ns = ...

-- Dice by commit-reveal between the two players (spec 6.3), extension "dice"
-- of an engine that asks for them with {k="dice", need="dice"} (Табла): a
-- throw is three ordered seat-0 events (open with the opener's commit, the
-- other seat's commit, both seeds) and every client derives the dice itself.
-- The rules of a throw, its verdicts and fouls, what a modified host can
-- still do and the session fields (s.throw, s.dice*, s.fairTimer):
-- docs/superpowers/notes/engine-contract.md, Addendum 6.
-- Nothing is sent from the `table` hook (an event sent from inside
-- Session:apply would overtake the one being applied). The act hook plays the
-- host's seat-0 events itself and returns nil for every throw action.
-- This file: the throw itself and the host's side. The member's side (its
-- part of a throw, its seed across a /reload, snapshots, a host change) is
-- core/DiceMember.lua, which fills in Dice.part, Dice.notMine and
-- Dice.forget; what a snapshot is held against, and the records that outlive
-- the session, is core/DiceCheck.lua. Both reach the helpers here through
-- Dice.int. The dice line of the table frame is core/DiceLine.lua.
local Dice = {}
ns.Dice = Dice

local C, Fair, Session = ns.Const, ns.Fair, ns.Session
local copy, seatOf = ns.Util.copy, ns.Util.seatOf

local WHY = { forged = true } -- what a seat may complain of (op "protest")
local CRIES = 5 -- complaints of one seat passed on in a match
local function hex(x, n) return type(x) == "string" and #x == n and not x:find("[^0-9a-f]") end
local function isCommit(c) return hex(c, 64) end
local function isSeed(x) return hex(x, 2 * C.SEED_BYTES) end

-- Does the engine ask for dice now -> its system action (s: the seat that
-- throws for its turn; none in an opening throw), or nil.
local function wantsDice(s)
  local action = s.state and s:engine().system(s.state)
  return action ~= nil and action.need == "dice" and action or nil
end

-- My seed for throw h (out of my client's secret pool, core/Fair.lua).
local function newSeed(s, h)
  return Fair.seed(s.client.env, "dice|" .. Fair.handId(s.tid, h))
end

local function send(s, a)
  s.client:send("WHISPER", s.host, Session.message("ACT", { tid = s.tid, a = a }))
end

local function stopTimer(s)
  if s.fairTimer then s.fairTimer.cancel(); s.fairTimer = nil end
end

local function foul(throw, why) throw.foul = throw.foul or why end
-- A throw went on without my part although I had said it, or behind my back:
-- counted against the host (s.diceUnheard), unless my own client was away for
-- it: it shows a loading screen (env.loading) or one ended less than DICE_WAIT
-- ago (env.loadedAt); in a snapshot that resyncs me (`resync`) also one that
-- ended after the last event I heard (s.diceHeard), as long as the snapshot
-- comes within the time an honest host's tick and my request take. Then
-- nobody is blamed (s.diceAway). One loading screen excuses one throw
-- (s.diceAwayAt: its env.loadedAt, true while it still shows). The flags are
-- my own client's; no message of a host sets them. -> true: counted against the host.
local function unheard(s, resync)
  local env = s.client.env
  local at, now = env.loadedAt, env.now()
  local screen = env.loading == true or at -- which loading screen, if any
  local inside = screen == true or (at ~= nil and (now - at < C.DICE_WAIT
    or (resync and at > (s.diceHeard or now) and now - at < C.DICE_WAIT + C.PING_EVERY + C.SYN_MIN_GAP)))
  if s.diceAwayAt == true and screen ~= true then s.diceAwayAt = at end -- the screen excused while it showed is over
  local away = inside and s.diceAwayAt ~= screen
  if away then s.diceAwayAt = screen end
  local key = away and "diceAway" or "diceUnheard"
  s[key] = (s[key] or 0) + 1
  return not away
end
-- c is the commit of my seed for `throw` (s.diceOwn: every one I made at this
-- table, each good for its own throw only, with the seat it was thrown for).
local function own(s, throw, c)
  s.diceOwn = s.diceOwn or {}
  s.diceOwn[throw.h .. ":" .. c] = throw.r
end
-- A throw is closed (`throw` nil: dice that no throw gave, or the last throw
-- found bad afterwards, which is then counted once, as what it is now; never
-- the other way: a bad throw stays counted whatever comes under its number):
-- s.diceLast, the counts of the match, "fair". `heard`: its seeds event
-- reached me (not a snapshot's proof).
local function close(s, h, verdict, why, throw, heard)
  local old = s.diceLast
  local again = old ~= nil and old.h == h and verdict == "bad"
  local by = throw and s.seats[throw.d] or (again and old.by) or nil
  local last = { h = h, verdict = verdict, why = why, by = by }
  local seen = s.diceSeen or { ok = 0, alone = 0, bad = 0 }
  if again then seen[old.verdict] = seen[old.verdict] - 1 end
  seen[verdict], s.diceSeen, s.diceLast = (seen[verdict] or 0) + 1, seen, last
  if verdict == "bad" then s.diceBad = why end
  if verdict == "alone" then
    local count = s.diceAlone or {}
    count[by or ""], s.diceAlone = (count[by or ""] or 0) + 1, count
    last.silent, last.n = s.seats[throw.alone] or nil, count[by or ""]
    -- My host threw without me although I had said my part (or had, before
    -- a crash took my seed). Against my commit or seed, in its own event and
    -- not excused by my loading screen, it is robbed (s.diceRobbed: a staked
    -- match's "dice", core/StakesFair.lua).
    local said = throw.asked or throw.sent
    if s.mySeat == throw.alone and (said or throw.reload) and unheard(s) and said and heard then s.diceRobbed = (s.diceRobbed or 0) + 1 end
  end
  local client = s.client
  client.events:emit("fair", { tid = s.tid, game = s.game, h = h, verdict = verdict, why = why, at = client.env.epoch() })
end

-- Host, seated, while the engine asks for dice: opens throw h = seq + 1 with
-- the commit of a fresh seed of mine and replaces the wait. Else nothing.
function Dice.open(s)
  if s.role ~= "host" or not s.mySeat or not wantsDice(s) then return end
  local h = s.seq + 1
  local seed = newSeed(s, h)
  s.diceMine = { h = h, seed = seed }
  Dice.wait(s, h)
  s:play(0, { k = "throw", op = "open", h = h, c = Fair.commit(seed) })
end

-- Host: the wait of throw h, replacing any other. DICE_WAIT later, still the
-- host of that throw and without g's seed, my seed is published alone (g lost
-- its say); a host left without a running throw by then opens one.
function Dice.wait(s, h)
  stopTimer(s)
  s.fairTimer = s.client:after(C.DICE_WAIT, function()
    s.fairTimer = nil
    local throw = s.throw
    if s.client.session ~= s or s.role ~= "host" then return end
    if not throw or throw.done then return Dice.open(s) end
    if throw.h ~= h or not throw.seed then return end
    s:play(0, { k = "throw", op = "seeds", h = h, s = { [throw.d] = throw.seed } })
  end)
end

-- The throw's dice are applied (on `state`: mine, unless given): its verdict
-- (a throw whose commit under my seat I could not check is never "ok"), and
-- its proof for the snapshots, with the seat it was thrown for and that
-- seat's roll number as my own state has them (engine.thrown).
local function finish(s, throw, seeds, state)
  stopTimer(s)
  Dice.forget(s)
  local thrown, _, r, t = s:engine().thrown, nil, nil, nil
  if thrown then _, r, t = thrown(state or s.state) end
  s.diceProof = { h = throw.h, c = copy(throw.commits), s = copy(seeds), r = r, t = t }
  local verdict = throw.foul and "bad" or throw.alone and "alone" or (throw.reload or throw.late) and "unseen" or "ok"
  close(s, throw.h, verdict, throw.foul, throw, state == nil)
end

-- The seeds event: both seeds (or the opener's alone) fit the commits ->
-- the dice applied on a copy of the state; nil when anything does not fit.
local function applySeeds(s, throw, list)
  local d, g = throw.d, 3 - throw.d
  if type(list) ~= "table" then return nil end
  for seat in pairs(list) do
    if seat ~= d and seat ~= g then return nil end
  end
  if not isSeed(list[d]) or Fair.commit(list[d]) ~= throw.commits[d] then return nil end
  local alone = list[g] == nil
  if not alone and (not isSeed(list[g]) or Fair.commit(list[g]) ~= throw.commits[g]) then return nil end
  local x, y = Fair.dice(alone and { list[d] } or { list[1], list[2] }, Fair.handId(s.tid, throw.h))
  local trial = copy(s.state)
  if not s:engine().apply(trial, 0, { k = "dice", d = { x, y } }) then return nil end
  s.state, throw.done, throw.alone = trial, true, alone and g or nil
  return true
end

Dice.int = {
  close = close, finish = finish, foul = foul, unheard = unheard, own = own, stopTimer = stopTimer, send = send,
  wantsDice = wantsDice, newSeed = newSeed, isCommit = isCommit, isSeed = isSeed,
}

ns.Ext.dice = {
  -- Host: the engine wants dice. A running throw is never opened again (the
  -- session offers `need` after every event); a missing wait is armed again.
  need = function(s, action)
    if action.need ~= "dice" or s.role ~= "host" then return end
    local throw = s.throw
    if not throw or throw.done then return Dice.open(s) end
    if not s.fairTimer then Dice.wait(s, throw.h) end
  end,

  -- Everyone: the seat-0 throw events. true when applied, nil to refuse;
  -- anything that is not k "throw" goes to the engine.
  table = function(s, a)
    if a.k ~= "throw" then return nil end
    local throw = s.throw
    if a.op == "open" then
      local d, want = seatOf(s.seats, s.host), wantsDice(s)
      if a.h ~= s.seq + 1 or not isCommit(a.c) or not d or not want then return nil end
      s.throw = { h = a.h, d = d, r = want.s or 0, commits = { [d] = a.c }, replaced = throw and not throw.done and throw or nil }
      return true
    elseif a.op == "protest" then
      return type(a.h) == "number" and s.seats[a.seat or 0] and WHY[a.why] and true or nil
    end
    if not throw or throw.done or a.h ~= throw.h then return nil end
    if a.op == "commit" then
      local g = 3 - throw.d
      if a.seat ~= g or not s.seats[g] or throw.commits[g] ~= nil or not isCommit(a.c) then return nil end
      throw.commits[g] = a.c
      return true
    end
    return a.op == "seeds" and applySeeds(s, throw, a.s) or nil
  end,

  -- Host: a member's throw action is never played as it is. g's commit and
  -- g's seed (checked against that commit) become my seat-0 events.
  act = function(s, seat, a)
    if a.k ~= "throw" then return a end
    local throw = s.throw
    -- A complaint is passed on once per seat and throw (s.diceCried), for a
    -- number the table has reached, CRIES a seat in a match.
    if a.op == "protest" then
      local said, h = s.diceCried or {}, a.h
      local n = said[seat] or 0
      if type(h) == "number" and h % 1 == 0 and h >= 1 and h <= s.seq and WHY[a.why] and n < CRIES and not said[seat .. ":" .. h] then
        said[seat], said[seat .. ":" .. h], s.diceCried = n + 1, true, said
        s:play(0, { k = "throw", op = "protest", h = h, seat = seat, why = a.why })
      end
      return nil
    end
    if not throw or throw.done or a.h ~= throw.h or seat ~= 3 - throw.d then return nil end
    local g = seat
    if a.op == "commit" and throw.commits[g] == nil and isCommit(a.c) then
      s:play(0, { k = "throw", op = "commit", h = throw.h, seat = g, c = a.c })
    elseif a.op == "seed" and throw.commits[g] and throw.seed and isSeed(a.s) and Fair.commit(a.s) == throw.commits[g] then
      s:play(0, { k = "throw", op = "seeds", h = throw.h, s = { [throw.d] = throw.seed, [g] = a.s } })
    end
    return nil
  end,

  -- Host: a complaint changes nothing on the board: the turn clock runs on.
  still = function(s, seat, a) return seat == 0 and a.k == "throw" and a.op == "protest" or nil end,

  -- Everyone, after every event.
  applied = function(s, seat, a)
    local k = seat == 0 and a.k
    s.diceHost = s.host -- whose events I follow (see hostChanged)
    if k == "start" or k == "abort" then
      s.throw, s.diceMine = nil, nil
      if k == "start" then
        s.diceLast, s.diceSeen, s.diceBad, s.diceAlone, s.diceUnheard, s.diceCry, s.diceProof = nil, nil, nil, nil, nil, nil, nil
        s.diceCried, s.diceAway, s.diceRobbed = nil, nil, nil
      end
      Dice.forget(s)
      return stopTimer(s)
    end
    -- Dice come only out of a throw (applySeeds, never an event of their own).
    if k == "dice" then return close(s, s.seq, "bad", "forged") end
    if k == "throw" and a.op == "protest" then
      s.diceCry = { h = a.h, seat = a.seat, name = s.seats[a.seat] or nil, why = a.why }
      return
    end
    local throw = s.throw
    if k ~= "throw" or not throw or a.h ~= throw.h then return end
    if a.op == "open" then
      -- Opened over a running throw (of the same host: a host change drops
      -- it) after my seed went out: a second try at the dice.
      local old, mine, me = throw.replaced, s.diceMine, s.mySeat
      throw.replaced = nil
      -- Opened under my own seat number, or while my seat bears another name:
      -- I never opened it (a host that rewrote the seats).
      if s.role ~= "host" and me and (throw.d == me or s.seats[me] ~= s.client.env.me) then foul(throw, "forged") end
      if old and (old.sent or old.foul) then close(s, old.h, "bad", old.foul or "dodge", old) end
      if s.role == "host" then
        if mine and mine.h == a.h then throw.seed, throw.own = mine.seed, a.c; own(s, throw, a.c) end
        s.diceMine = nil
      else
        stopTimer(s)
        Dice.part(s, throw)
      end
    elseif a.op == "commit" and s.role ~= "host" and a.seat == s.mySeat then
      if a.c ~= throw.own then Dice.notMine(throw, throw.fresh) end
      Dice.part(s, throw)
    elseif a.op == "seeds" then
      finish(s, throw, a.s)
    end
  end,

  -- Host: SNP.fr (public data only) = the throw still running {h, d, c} and
  -- p, the proof of the last closed throw (its commits and seeds: the dice of
  -- the snapshot's state are derived from it); nil without either.
  snap = function(s)
    local throw, proof = s.throw, s.diceProof
    local fr = throw and not throw.done and { h = throw.h, d = throw.d, c = copy(throw.commits) } or nil
    if proof then
      fr = fr or {}
      fr.p = copy(proof)
    end
    return fr
  end,
}

return Dice
