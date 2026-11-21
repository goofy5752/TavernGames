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
-- This file: the throw itself, the host's side and the dice line. The member's
-- side (its part of a throw, its seed across a /reload, snapshots, a host
-- change) is core/DiceMember.lua, which fills in Dice.part, Dice.notMine and
-- Dice.forget and reaches the helpers here through Dice.int.
local Dice = {}
ns.Dice = Dice

local C, Fair, Session = ns.Const, ns.Fair, ns.Session
local copy, seatOf, contains = ns.Util.copy, ns.Util.seatOf, ns.Util.contains

local WHY = { forged = true } -- what a seat may complain of (op "protest")
local function hex(x, n) return type(x) == "string" and #x == n and not x:find("[^0-9a-f]") end
local function isCommit(c) return hex(c, 64) end
local function isSeed(x) return hex(x, 2 * C.SEED_BYTES) end

-- Does the engine ask for dice now?
local function wantsDice(s)
  local action = s.state and s:engine().system(s.state)
  return action ~= nil and action.need == "dice"
end

local function newSeed(s)
  local env = s.client.env
  return Fair.seed(function(lo, hi) return env.random(lo, hi) end)
end

local function send(s, a)
  s.client:send("WHISPER", s.host, Session.message("ACT", { tid = s.tid, a = a }))
end

local function stopTimer(s)
  if s.fairTimer then s.fairTimer.cancel(); s.fairTimer = nil end
end

local function foul(throw, why) throw.foul = throw.foul or why end
local function unheard(s) s.diceUnheard = (s.diceUnheard or 0) + 1 end
-- c is the commit of my seed for throw h (s.diceOwn: every one I made at
-- this table, each good for its own throw only).
local function own(s, h, c)
  s.diceOwn = s.diceOwn or {}
  s.diceOwn[h .. ":" .. c] = true
end
-- A throw is closed (`throw` nil: dice that no throw gave, or the last throw
-- found bad afterwards, which is then counted once, as what it is now):
-- s.diceLast, the counts of the match, "fair".
local function close(s, h, verdict, why, throw)
  local old = s.diceLast
  local again = old ~= nil and old.h == h
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
    -- a crash took my seed).
    if s.mySeat == throw.alone and (throw.asked or throw.sent or throw.reload) then unheard(s) end
  end
  local client = s.client
  client.events:emit("fair", { tid = s.tid, game = s.game, h = h, verdict = verdict, why = why, at = client.env.epoch() })
end

-- Host, seated, while the engine asks for dice: opens throw h = seq + 1 with
-- the commit of a fresh seed of mine and replaces the wait. Else nothing.
function Dice.open(s)
  if s.role ~= "host" or not s.mySeat or not wantsDice(s) then return end
  local h, seed = s.seq + 1, newSeed(s)
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

-- The throw's dice are applied: its verdict (a throw whose commit under my
-- seat I could not check is never "ok"), and its proof for the snapshots.
local function finish(s, throw, seeds)
  stopTimer(s)
  Dice.forget(s)
  s.diceProof = { h = throw.h, c = copy(throw.commits), s = copy(seeds) }
  local verdict = throw.foul and "bad" or throw.alone and "alone" or throw.reload and "unseen" or "ok"
  close(s, throw.h, verdict, throw.foul, throw)
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
      local d = seatOf(s.seats, s.host)
      if a.h ~= s.seq + 1 or not isCommit(a.c) or not d or not wantsDice(s) then return nil end
      s.throw = { h = a.h, d = d, commits = { [d] = a.c }, replaced = throw and not throw.done and throw or nil }
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
    local throw, cry = s.throw, s.diceCry
    -- A complaint is passed on once per seat and throw.
    if a.op == "protest" then
      if not (cry and cry.h == a.h and cry.seat == seat) then
        s:play(0, { k = "throw", op = "protest", h = a.h, seat = seat, why = a.why })
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

  -- Everyone, after every event.
  applied = function(s, seat, a)
    local k = seat == 0 and a.k
    s.diceHost = s.host -- whose events I follow (see hostChanged)
    if k == "start" or k == "abort" then
      s.throw, s.diceMine = nil, nil
      if k == "start" then
        s.diceLast, s.diceSeen, s.diceBad, s.diceAlone, s.diceUnheard, s.diceCry, s.diceProof = nil, nil, nil, nil, nil, nil, nil
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
      local old, mine = throw.replaced, s.diceMine
      throw.replaced = nil
      if old and (old.sent or old.foul) then close(s, old.h, "bad", old.foul or "dodge", old) end
      if s.role == "host" then
        if mine and mine.h == a.h then throw.seed, throw.own = mine.seed, a.c; own(s, a.h, a.c) end
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

-- Is the dice line red: a bad throw in this match, or two went unheard.
function Dice.alarm(s)
  return (s.diceSeen ~= nil and s.diceSeen.bad > 0) or (s.diceUnheard or 0) >= 2
end

-- The table frame's dice line -> locale key, colour token, arg, arg2 | nil:
-- nil for an engine without the extension "dice", and before the first throw.
function Dice.status(s)
  if not contains(s:engine().ext or {}, "dice") then return nil end
  local throw, last, red = s.throw, s.diceLast, Dice.alarm(s) and "red" or nil
  if throw and not throw.done then return "dice.rolling", red or "inkDim" end
  if not last then return nil end
  if last.verdict == "ok" then return "dice.ok", red or "good" end
  if last.verdict == "bad" then return "dice.bad", "red" end
  if last.verdict == "unseen" then return "dice.unseen", red or "gold" end
  if last.n >= 2 then return "dice.aloneMany", red or "gold", last.by, last.n end
  return "dice.alone", red or "gold", last.by, last.silent
end

-- The dice line's tooltip -> {{colour token, locale key, arg}, ...}.
function Dice.tip(s)
  local out = { { "ink", "dice.tip" } }
  if s.diceBad then out[#out + 1] = { "red", "dice.tip.bad", s.diceBad } end
  if s.diceUnheard then out[#out + 1] = { "red", "dice.unheard", s.diceUnheard } end
  local cry = s.diceCry -- another seat's claim: shown, it changes no colour of mine
  if cry and cry.seat ~= s.mySeat then out[#out + 1] = { "gold", "dice.cry", cry.name, cry.why } end
  return out
end

return Dice
