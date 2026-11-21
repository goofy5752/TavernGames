local _, ns = ...

-- The member's side of a throw (core/Dice.lua; rules: engine contract,
-- Addendum 6): my part as the other seat g, my seed across a /reload, what a
-- snapshot or a new host does to a throw, and what I can tell of dice I did
-- not derive.
-- My seed is kept where a /reload keeps it, as core/DealKeep.lua keeps the
-- dealer's: env.db.fairKeep = {dice = true, tid, h, me, seat, c (the opener's
-- commit), seed}, written when the seed is made, dropped when the throw ends
-- (Dice.forget) and, by Session.leave (DealKeep.clear), when I leave the
-- table. It is in no message.
local Dice = ns.Dice
local Fair, int = ns.Fair, ns.Dice.int
local same, seatOf = ns.Util.same, ns.Util.seatOf

local AGAIN, REPEATS = 3, 2 -- g says its last throw action again after this long, this often

-- The kept seed of my table -> record | nil, env.db.
local function record(s)
  local db = s.client.env.db
  local rec = db and db.fairKeep
  return type(rec) == "table" and rec.dice == true and rec.tid == s.tid and rec or nil, db
end

function Dice.forget(s)
  local rec, db = record(s)
  if rec then db.fairKeep = nil end
end

-- I logged in again into throw `throw`: my seed of that very open, if kept
-- -> true. A record of anything else is dropped.
local function restore(s, throw)
  local rec = record(s)
  if rec and rec.h == throw.h and rec.me == s.client.env.me and rec.seat == s.mySeat
      and rec.c == throw.commits[throw.d] and int.isSeed(rec.seed) then
    throw.seed, throw.own = rec.seed, Fair.commit(rec.seed)
    return true
  end
  Dice.forget(s)
  return false
end

-- A commit under my seat that I did not send: with my seed lost in a crash I
-- cannot tell (reload: I send nothing, the throw is never "ok"), else forged.
function Dice.notMine(throw, lost)
  if lost then throw.reload = true else int.foul(throw, "mine") end
end

-- g, not the host: my commit while my seat shows none, my seed once my own
-- commit stands there; said again every AGAIN seconds while the throw runs,
-- REPEATS times at most (the host ignores a second commit and a late seed).
function Dice.part(s, throw)
  local g = 3 - throw.d
  if s.role == "host" or s.mySeat ~= g or throw.done or throw.foul or throw.reload then return end
  local c, env = throw.commits[g], s.client.env
  if c ~= nil and c ~= throw.own then return end
  if c == nil then
    if not throw.seed then
      throw.seed = int.newSeed(s)
      throw.own = Fair.commit(throw.seed)
      if env.db then
        env.db.fairKeep = { dice = true, tid = s.tid, h = throw.h, me = env.me, seat = g, c = throw.commits[throw.d], seed = throw.seed }
      end
    end
    throw.asked = true
    int.send(s, { k = "throw", op = "commit", h = throw.h, c = throw.own })
  else
    throw.sent = true
    int.send(s, { k = "throw", op = "seed", h = throw.h, s = throw.seed })
  end
  if s.fairTimer or (throw.rep or 0) >= REPEATS then return end
  s.fairTimer = s.client:after(AGAIN, function()
    s.fairTimer = nil
    if s.client.session ~= s or s.throw ~= throw then return end
    throw.rep = (throw.rep or 0) + 1
    Dice.part(s, throw)
  end)
end

-- The table shows dice, or a board, that are not what I derived: throw h (the
-- last one I closed) is bad on my client whatever it was, and I say so.
local function forged(s, h)
  int.close(s, h, "bad", "forged")
  if s.role ~= "host" then int.send(s, { k = "throw", op = "protest", h = h, why = "forged" }) end
end

-- Is SNP.fr of snapshot m a throw I take -> true, false (not well formed, not
-- opened by my host's seat, or the state asks for no dice) or "old" (I did
-- not just log in, and my host used that number before).
local function fits(s, m, how, held)
  local fr, last = m.fr, s.diceLast
  if type(fr) ~= "table" or type(fr.c) ~= "table" or type(fr.h) ~= "number" or fr.h % 1 ~= 0 then return false end
  local d = fr.d
  if (d ~= 1 and d ~= 2) or d ~= seatOf(s.seats, s.host) or fr.h > m.q then return false end
  if not int.isCommit(fr.c[d]) or (fr.c[3 - d] ~= nil and not int.isCommit(fr.c[3 - d])) or not int.wantsDice(s) then return false end
  if how.fresh or (held and not held.done and held.h == fr.h) then return true end
  return fr.h > math.max(held and held.h or 0, last and last.by == s.host and last.h or 0) or "old"
end

-- The snapshot m replaced my state `prev` (how: see Member.adopt).
ns.Ext.dice.adopted = function(s, prev, m, how)
  if s.role == "host" then return end
  -- Under the host I knew (not after a login, not when another player hosts
  -- now) my own state is what I hold the snapshot against.
  local known = not how.fresh and not s.diceNew and prev ~= nil and s.state ~= nil
  s.diceNew, s.diceHost = nil, s.host
  local held, fr, last, engine = s.throw, m.fr, s.diceLast, s:engine()
  -- At my own event number the state must be mine: every client derives it.
  if known and m.q == how.q and not how.changed and not same(engine.snapshot(prev), engine.snapshot(s.state)) then
    forged(s, last and last.h or m.q)
    known = false
  end
  local good = fits(s, m, how, held)
  if good == "old" then return end
  local kept = good and held ~= nil and not held.done and held.h == fr.h
  if held and not held.done and not kept and (held.asked or held.sent or held.foul) then
    -- A throw I had said my part to is gone or another one: unasked, or under
    -- an epoch its opener (still my host) raised, a second try; else unheard.
    local why = held.foul or ((how.changed or not how.asked) and "dodge") or nil
    if why then int.close(s, held.h, "bad", why, held) else int.unheard(s) end
  elseif known and s.mySeat and s.state.dice and not same(s.state.dice, prev.dice) then
    -- Dice of a throw whose events never reached me: the same way.
    if how.changed or not how.asked then int.close(s, m.q, "bad", "dodge") else int.unheard(s) end
  end
  if not good then
    if held and not held.done then s.throw = nil; int.stopTimer(s); Dice.forget(s) end
    return
  end
  local d, g, throw = fr.d, 3 - fr.d, kept and held or { h = fr.h, d = fr.d }
  if kept and fr.c[d] ~= held.commits[d] then int.foul(held, "commit") end
  s.throw, throw.sent = throw, nil -- my throw keeps my seed; what I sent is asked again
  throw.commits = { [d] = fr.c[d], [g] = fr.c[g] }
  if s.mySeat == g then
    -- A login mid-throw: my kept seed (a /reload), else none (a crash).
    if not kept and how.fresh and not restore(s, throw) then throw.fresh = true end
    if fr.c[g] ~= nil and fr.c[g] ~= throw.own then Dice.notMine(throw, throw.fresh) end
  end
  int.stopTimer(s)
  Dice.part(s, throw)
end

-- The throw died with its host. A running one whose opener hosts on (it raised
-- its own epoch) was a second try; else, my part said, it went unheard.
-- s.diceNew: another player hosts now, so the next snapshot is not held
-- against my state.
ns.Ext.dice.hostChanged = function(s)
  local t = s.throw
  if s.diceHost ~= s.host then s.diceNew = true end
  local why = t and not t.done and (t.foul or (s.seats[t.d] == s.host and "dodge"))
  if why then int.close(s, t.h, "bad", why, t) elseif t and not t.done and (t.asked or t.sent) then int.unheard(s) end
  s.throw, s.diceMine = nil, nil
  Dice.forget(s)
  int.stopTimer(s)
end

-- An event of my host that does not apply to my state (not a throw's: those
-- I refuse whenever I hold no such throw). In an open game I hold the whole
-- state, so the host's is not the one the throws gave.
ns.Ext.dice.refused = function(s, seat, a)
  if type(a) == "table" and a.k ~= "throw" then forged(s, s.diceLast and s.diceLast.h or s.seq + 1) end
end

return Dice
