local _, ns = ...

-- Dice by commit-reveal between the two players (spec 6.3), extension "dice"
-- of an engine that asks for them with {k="dice", need="dice"} (Табла). No
-- dealer, no private faces, no audit: a throw is three ordered seat-0 events,
-- and every client derives the dice itself.
--   1. Throw h is opened by the host with the event number it gets
--      (h = seq + 1); its rollId is Fair.handId(tid, h) = tid .. "/" .. h.
--   2. The opener is the host's seat d; the other seat is g = 3 - d. The open
--      event carries the commit of the opener's seed (EV {k="throw",
--      op="open", h, c}). g commits a fresh seed (ACT op "commit" -> EV
--      {..., op="commit", h, seat = g, c}), sees its own commit come back as
--      an event and whispers its seed to the host (ACT op "seed", never
--      relayed as it is). Until then the opener's seed has not left the
--      opener's client, so g reveals blind.
--   3. The host publishes both seeds in one event (EV {..., op="seeds", h,
--      s = {[seat] = seed}}). Every client checks both against the commits
--      and applies the dice Fair.dice({seed_1, seed_2}, rollId) (seeds in
--      seat order) itself as the engine's {k="dice", d = {x, y}} at seat 0.
--      No message carries a dice value.
--   4. DICE_WAIT seconds after the open without g's seed, the host publishes
--      its own seed alone and the dice are Fair.dice({seed_d}, rollId): the
--      silent seat has lost its say over that throw. A throw is never opened
--      again for the same host (`need` re-arms the wait of a running throw;
--      only an explicit Dice.open opens over one); a new h exists only after
--      a host change.
--   5. What this leaves: the host orders the events, so a modified host
--      client could look at g's seed before publishing; it cannot change its
--      own seed (its commit is out first). The guest's client shows what it
--      can see of that in its verdicts: a throw replaced after it sent its
--      seed is "bad", "dodge"; one the host made alone although it sent its
--      commit or seed counts as unheard.
-- Verdicts of a closed throw: "ok" (both seeds), "alone" (the opener's
-- only), "bad" (why).
-- Nothing is sent from the `table` hook: an event sent from inside
-- Session:apply would overtake the one being applied (as in
-- core/DealHooks.lua). Sending happens in `applied`, `adopted`, the act hook
-- and the wait. The act hook plays the host's seat-0 events itself and
-- returns nil for every throw action: a member's action that came back from
-- it would be played at the member's seat, where the engine refuses it.
--
-- Session fields: s.throw = the running or last throw {h, d, commits (seat
-- -> commit), seed (my seed: the opener's on the host, g's on g's client),
-- own (the commit of my seed), asked (g: my commit was sent), sent (g: my
-- seed was sent), done (the dice are applied), alone (= g when the host threw
-- alone), reload, foul, replaced}; s.diceMine = {h, seed} (host: the seed of
-- the open I am sending, until its event is applied); s.diceLast = {h,
-- verdict, why, by (the opener's name), silent, n} of the last closed throw;
-- s.diceSeen = {ok, alone, bad} throws closed in this match; s.diceAlone[name]
-- and s.diceUnheard count the throws a host made alone. s.fairTimer (host) =
-- the throw's wait (DICE_WAIT), from its open until its seeds; Session's
-- TIMERS cancels it with the session. The client event "fair" is emitted for
-- every closed throw: {tid, game, h, verdict, why, at}.
local Dice = {}
ns.Dice = Dice

local C = ns.Const
local Fair = ns.Fair
local Session = ns.Session
local copy, seatOf, contains = ns.Util.copy, ns.Util.seatOf, ns.Util.contains

local function hex(x, n) return type(x) == "string" and #x == n and not x:find("[^0-9a-f]") end
local function isCommit(c) return hex(c, 64) end
local function isSeed(x) return hex(x, 2 * C.SEED_BYTES) end

-- Does the engine ask for dice now?
local function wantsDice(s)
  local action = s.state and s:engine().system(s.state)
  return action ~= nil and action.need == "dice"
end

-- A throw action from my seat to the host.
local function send(s, a)
  s.client:send("WHISPER", s.host, Session.message("ACT", { tid = s.tid, a = a }))
end

local function stopWait(s)
  if s.fairTimer then s.fairTimer.cancel(); s.fairTimer = nil end
end

-- The one handler of s.fairTimer: the wait of throw h (host) is over.
local function waitOver(s, h)
  s.fairTimer = nil
end

-- Host: the wait of throw h, replacing any other.
local function armWait(s, h)
  stopWait(s)
  s.fairTimer = s.client:after(C.DICE_WAIT, function() waitOver(s, h) end)
end

-- Host, seated, while the engine asks for dice: opens throw h = seq + 1 with
-- the commit of a fresh seed of mine and replaces the wait. Else nothing.
function Dice.open(s)
  if s.role ~= "host" or not s.mySeat or not wantsDice(s) then return end
  local env = s.client.env
  local h, seed = s.seq + 1, Fair.seed(function(lo, hi) return env.random(lo, hi) end)
  s.diceMine = { h = h, seed = seed }
  armWait(s, h)
  s:play(0, { k = "throw", op = "open", h = h, c = Fair.commit(seed) })
end

-- The throw is over (its seeds are applied): s.diceLast, the count, "fair".
local function close(s, throw)
  local verdict = throw.alone and "alone" or "ok"
  s.diceLast = { h = throw.h, verdict = verdict, by = s.seats[throw.d] or nil }
  local seen = s.diceSeen or { ok = 0, alone = 0, bad = 0 }
  seen[verdict], s.diceSeen = seen[verdict] + 1, seen
  local client = s.client
  client.events:emit("fair", { tid = s.tid, game = s.game, h = throw.h, verdict = verdict, at = client.env.epoch() })
end

-- The seeds event: both seeds (or the opener's alone) fit the commits ->
-- the dice applied on a copy of the state; nil when anything does not fit.
local function applySeeds(s, throw, list)
  local d = throw.d
  local g = 3 - d
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

ns.Ext.dice = {
  -- Host: the engine wants dice. A running throw is never opened again (rule
  -- 4; the session offers `need` after every event): its wait is armed again
  -- if it is missing.
  need = function(s, action)
    if action.need ~= "dice" or s.role ~= "host" then return end
    local throw = s.throw
    if throw and not throw.done then
      if not s.fairTimer then armWait(s, throw.h) end
      return
    end
    Dice.open(s)
  end,

  -- Everyone: the seat-0 throw events. true when applied, nil to refuse;
  -- anything that is not k "throw" goes to the engine.
  table = function(s, a)
    if a.k ~= "throw" then return nil end
    local throw = s.throw
    if a.op == "open" then
      local d = seatOf(s.seats, s.host)
      if a.h ~= s.seq + 1 or not isCommit(a.c) or not d or not wantsDice(s) then return nil end
      s.throw = { h = a.h, d = d, commits = { [d] = a.c } }
      return true
    end
    if not throw or throw.done or a.h ~= throw.h then return nil end
    if a.op == "commit" then
      local g = 3 - throw.d
      if a.seat ~= g or not s.seats[g] or throw.commits[g] ~= nil or not isCommit(a.c) then return nil end
      throw.commits[g] = a.c
      return true
    elseif a.op == "seeds" then
      return applySeeds(s, throw, a.s)
    end
    return nil
  end,

  -- Host: a member's throw action is never played as it is. g's commit and
  -- g's seed (checked against that commit) become my seat-0 events.
  act = function(s, seat, a)
    if a.k ~= "throw" then return a end
    local throw = s.throw
    if not throw or throw.done or a.h ~= throw.h or seat ~= 3 - throw.d then return nil end
    local d, g = throw.d, seat
    if a.op == "commit" then
      if throw.commits[g] == nil and isCommit(a.c) then
        s:play(0, { k = "throw", op = "commit", h = throw.h, seat = g, c = a.c })
      end
    elseif a.op == "seed" then
      if throw.commits[g] and throw.seed and isSeed(a.s) and Fair.commit(a.s) == throw.commits[g] then
        s:play(0, { k = "throw", op = "seeds", h = throw.h, s = { [d] = throw.seed, [g] = a.s } })
      end
    end
    return nil
  end,

  -- Everyone, after every event.
  applied = function(s, seat, a)
    local k = seat == 0 and a.k
    if k == "start" or k == "abort" then
      s.throw, s.diceMine = nil, nil
      if k == "start" then s.diceLast, s.diceSeen, s.diceAlone, s.diceUnheard = nil, nil, nil, nil end
      return stopWait(s)
    end
    local throw = s.throw
    if k ~= "throw" or not throw or a.h ~= throw.h then return end
    local g = 3 - throw.d
    if a.op == "open" then
      local mine = s.diceMine
      if s.role == "host" then
        if mine and mine.h == a.h then throw.seed, throw.own = mine.seed, a.c end
        s.diceMine = nil
      elseif s.mySeat == g then
        -- My part: a fresh seed, its commit to the host.
        local env = s.client.env
        throw.seed = Fair.seed(function(lo, hi) return env.random(lo, hi) end)
        throw.own, throw.asked = Fair.commit(throw.seed), true
        send(s, { k = "throw", op = "commit", h = throw.h, c = throw.own })
      end
    elseif a.op == "commit" then
      -- My own commit came back: now my seed, to the host only.
      if s.role ~= "host" and a.seat == s.mySeat and throw.own and a.c == throw.own then
        throw.sent = true
        send(s, { k = "throw", op = "seed", h = throw.h, s = throw.seed })
      end
    elseif a.op == "seeds" then
      if s.role == "host" then stopWait(s) end
      close(s, throw)
    end
  end,

  -- Host: the throw still running as SNP.fr (public data only), else nil.
  snap = function(s)
    local throw = s.throw
    if not throw or throw.done then return nil end
    return { h = throw.h, d = throw.d, c = copy(throw.commits) }
  end,
}

-- The table frame's dice line -> locale key, colour token, arg, arg2 | nil:
-- nil for an engine without the extension "dice", and before the first throw.
function Dice.status(s)
  if not contains(s:engine().ext or {}, "dice") then return nil end
  local throw = s.throw
  if throw and not throw.done then return "dice.rolling", "inkDim" end
  local last = s.diceLast
  if last and last.verdict == "ok" then return "dice.ok", "good" end
  return nil
end

return Dice
