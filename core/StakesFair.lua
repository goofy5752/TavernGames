local _, ns = ...

-- What the fairness layer of a staked game (the "fair" verdicts of
-- core/Deal.lua, the dice counts of core/Dice.lua) means for my debt. A game
-- whose engine has that layer (`fair` or `dice` in engine.ext) is "judged":
-- the extension judges what a snapshot did to the hand or the throw, and for
-- `stakes` a snapshot from a host new to me that is not my state is the same
-- match, "unseen" (core/StakesWatch.lua's `adopted`: Stakes.leadsTo cannot
-- read these states); one my own host pushed on me unasked that changes my
-- state is "forged"; one I asked for or logged in with is "unseen".
--
-- What a closed hand means for my debt (Stakes.fairFoul, from the "fair"
-- event; "my side" = me and the player in my partner's seat):
--   verdict on my client                                   foul
--   "ok"                                                   none
--   "unseen"                                               unseen
--   "bad", why "announce"                                  none (the engine scored it 0 on every client)
--   "bad", why "noreveal", the dealer on my side           unseen
--   any other "bad"                                        deal
--   "void", the dealer is me                               none (my client asked for it)
--   "void" of my partner's deal; "nodeal" on my side       unseen (I cannot see that my partner asked)
--   "void" or "bad" "nodeal", the dealer not on my side:
--     that dealer's first in the match                     unseen
--     its second (fairVoids[name] + fairLapses[name] >= 2) deal
-- The verdict of the last hand comes after the event that ended the match:
-- the note of that match waits for it (note.wait) at most STAKE_FAIR_WAIT; a
-- hand still open then reads "unseen". A match that ended by a leave waits
-- for nothing: its running hand gets no verdict. A foul my client already
-- holds against a hand still open (fair.foul, noted before its close, which
-- turns it "bad": Stakes.openFoul) is deal at once, but "announce".
--
-- What the throws mean for my debt (Stakes.fairCount, from the session's dice
-- counts after the extension `dice` has run): a throw closed "bad" in this
-- match (diceSeen.bad > 0) or diceRobbed > 0 -> dice; diceSeen.unseen > 0 or
-- diceAway > 0 -> unseen. s.diceRobbed (core/Dice.lua, per match, kept where
-- s.diceUnheard is): a throw my host made alone after my client had sent its
-- commit or seed for it, in its own event and not excused by my loading
-- screen (D3); a running throw my seed had left for that died with a host
-- change or that a snapshot of my own host dropped (D2, core/DiceMember.lua). A throw made alone while my client had said nothing is no foul.
--
-- My turn clock (s.stakeTurn, and Member.timedOut's s.turnAt) at a staked
-- table whose engine has no `idle` restarts at every event after which an
-- honest host arms its turn timer again (Session:event: all but a sit, a
-- stand and an event an extension calls `still`): Табла's throw for my turn,
-- each step of my cascade. The host's timeout for my seat is then taken only
-- after a whole turn of mine since (D1).
--
-- Session field (local, never sent): s.stakeRec = {gid, h, open, late}, the
-- match that just ended by play while its last hand (h) was still open:
-- open until that hand's verdict, late the foul it brought (Stakes.audit,
-- Stakes.fairHeard). The verdict of hand h alone closes it; it dies with the
-- session (a login or the hall before the reveal: the note stays "unseen").
local Stakes, C = ns.Stakes, ns.Const
local NONE = {}

local function has(engine, x) return ns.Util.contains(engine.ext or NONE, x) end
local worse = Stakes.worse -- core/StakesBook.lua

-- Does s's engine have a fairness layer that judges its snapshots -> bool.
function Stakes.judged(s)
  local ext = s:engine().ext or NONE
  for _, x in ipairs(ext) do
    if x == "fair" or x == "dice" then return true end
  end
  return false
end

-- The foul my client already holds against `round` (s.fair) while it is open: what its close will make of it -> "deal" | nil.
function Stakes.openFoul(round)
  return round and round.stage ~= "done" and round.foul and round.foul ~= "announce" and "deal" or nil
end

-- Is `name` on my side of s: me, or the player in my partner's seat (engine.partner, while I am seated).
local function mySide(s, name)
  local engine = s:engine()
  if name == s.client.env.me then return true end
  return name ~= nil and engine.partner ~= nil and s.mySeat ~= nil and s.seats[engine.partner(s.mySeat)] == name
end

-- The foul a closed hand (v, the "fair" event of core/Deal.lua) or throw
-- (core/Dice.lua) means for my debt, by the tables above -> "deal" | "dice" | "unseen" | nil.
function Stakes.fairFoul(s, v)
  local engine, verdict, why = s:engine(), v.verdict, v.why
  if has(engine, "dice") then return (verdict == "bad" and "dice") or (verdict == "unseen" and "unseen") or nil end
  if engine.sealed then return verdict == "bad" and "deal" or nil end -- Холдем: a void or a lapse moves no chip
  if not has(engine, "fair") or verdict == "ok" or (verdict == "bad" and why == "announce") then return nil end
  if verdict == "unseen" then return "unseen" end
  local side = mySide(s, v.dealer)
  if verdict == "bad" and why == "noreveal" then return side and "unseen" or "deal" end
  if verdict == "void" or why == "nodeal" then
    -- Only my own void is one my client knows it asked for (an unasked one closed "bad" "forged").
    if side then return (verdict == "bad" or v.dealer ~= s.client.env.me) and "unseen" or nil end
    local n = ((s.fairVoids or NONE)[v.dealer] or 0) + ((s.fairLapses or NONE)[v.dealer] or 0)
    return n >= 2 and "deal" or "unseen"
  end
  return verdict == "bad" and "deal" or nil
end

-- A hand or throw closed at my staked table (client event "fair"). While a
-- match runs it is a foul of that match. After one ended by play, only the
-- verdict of its last hand (s.stakeRec.h) counts, and it makes that match's
-- note final (Book:final). It reads s.stakeLive, never Stakes.running: the
-- next start closes an unrevealed hand inside the `fair` hook, when the new
-- state exists already but the `stakes` hook has not run.
function Stakes.fairHeard(client, v)
  local s = client.session
  if not (s and s.stake ~= nil and s.tid == v.tid) then return end
  local foul, rec = Stakes.fairFoul(s, v), s.stakeRec
  if s.stakeLive then
    if foul then Stakes.foul(s, foul) end
  elseif rec and rec.open and v.h == rec.h then
    rec.late, rec.open = worse(rec.late, foul), false
    if client.stakes then client.stakes:final(rec.gid) end
  end
end

-- The verdict still out for the outcome gid of s (left: a forfeit) -> nil |
-- {read = function() -> foul | nil, wait = seconds}: Death Roll's rolls
-- (Rolls.audit, final ROLL_FINAL_WAIT later); the last hand of a card match
-- that ended by play while its round was still open (s.stakeRec; pending
-- reads "unseen", or "deal" by Stakes.openFoul; final STAKE_FAIR_WAIT later or at that hand's verdict). A
-- leave waits for nothing: its running hand gets no verdict.
function Stakes.audit(s, gid, left)
  local engine, fair = s:engine(), s.fair
  if has(engine, "rolls") then
    local rec = ns.Rolls.auditOf(s.client, gid) or s
    return { read = function() return ns.Rolls.audit(rec) end, wait = C.ROLL_FINAL_WAIT }
  end
  if engine.sealed and not left and Stakes.cash(s) then return Stakes.sealedAudit(s, gid) end -- the book's verdict (core/StakesCashOwe.lua)
  if left or engine.sealed or not has(engine, "fair") or not (fair and fair.stage ~= "done") then return nil end
  local rec = { gid = gid, h = fair.h, open = true }
  s.stakeRec = rec
  return { read = function() return worse(rec.late, rec.open and (Stakes.openFoul(fair) or "unseen") or nil) end, wait = C.STAKE_FAIR_WAIT }
end

-- The dice counts of the running match, as the foul of the event (or
-- snapshot) being handled (the table above). Only while a match runs: a count
-- left between two matches would land on the next one.
function Stakes.fairCount(s)
  if not (s.stakeLive and has(s:engine(), "dice")) then return end
  local seen = s.diceSeen or NONE
  if (seen.bad or 0) > 0 or (s.diceRobbed or 0) > 0 then
    Stakes.pend(s, "dice")
  elseif (seen.unseen or 0) > 0 or (s.diceAway or 0) > 0 then
    Stakes.pend(s, "unseen")
  end
end

-- The hooks count first; the original's refresh turns the pending foul into
-- the game's (after its reset when the event begins a new game, before
-- Book:settle writes the note). `hostChanged` refreshes nothing: its foul is
-- the running match's at once.
local ext = ns.Ext.stakes
local applied, adopted, hostChanged, refused = ext.applied, ext.adopted, ext.hostChanged, ext.refused

ext.applied = function(s, seat, a)
  Stakes.fairCount(s)
  applied(s, seat, a)
  local t, k = s.stakeTurn, seat == 0 and a.k
  if not t or s:engine().idle then return end
  if k and k ~= "sit" and k ~= "stand" and not s:hook("still", seat, a) then
    t = { seat = t.seat, at = s.client.env.now(), seen = true }
    s.stakeTurn = t
  end
  if s.role ~= "host" and t.seat == s.mySeat then s.turnAt = t.at end
end
ext.adopted = function(s, prev, m, how) Stakes.fairCount(s); return adopted(s, prev, m, how) end
ext.hostChanged = function(s)
  Stakes.fairCount(s)
  hostChanged(s)
  if s.stakeLive and s.stakePend then Stakes.foul(s, s.stakePend); s.stakePend = nil end
end
ext.refused = function(s, seat, a) Stakes.fairCount(s); return refused(s, seat, a) end
