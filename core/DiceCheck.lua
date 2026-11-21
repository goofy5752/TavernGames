local _, ns = ...

-- What a member holds itself and what a snapshot is held against (core/Dice.lua,
-- core/DiceMember.lua; rules: engine contract, Addendum 6). Nothing the host
-- can set is taken on its word: the dice come from the proof, the variant and
-- the roll counts from the engine's own derivation (engine.thrown), the seat a
-- throw was for from what I saw when I committed, and what I can vouch for is
-- my own state, never the snapshot's event number.
-- My dice records live as long as my client does, not as long as the session:
-- client.dice[tid] = the session's dice fields with my state and event
-- number, written after every hook. A table that ends under me and
-- takes me in again (END, then a snapshot) finds them: only a login without
-- such a record is new to the table.
local Dice = ns.Dice
local Fair, int, ext = ns.Fair, ns.Dice.int, ns.Ext.dice
local same = ns.Util.same

-- The dice that the proof p = {h, c, s, r, t} of a closed throw gives (SNP.fr.p
-- of snapshot m) -> x, y; nil when it is none: every seed must open its commit.
function int.proved(s, m, p)
  if type(p) ~= "table" or type(p.c) ~= "table" or type(p.s) ~= "table" then return nil end
  if type(p.h) ~= "number" or p.h % 1 ~= 0 or p.h > m.q then return nil end
  local list = {}
  for seat = 1, 2 do
    local seed = p.s[seat]
    if seed ~= nil then
      if not int.isSeed(seed) or Fair.commit(seed) ~= p.c[seat] then return nil end
      list[#list + 1] = seed
    end
  end
  if #list == 0 then return nil end
  return Fair.dice(list, Fair.handId(s.tid, p.h))
end

-- What the snapshot m shows of the dice against its proof p (dice x, y; nil:
-- none) and against what I know -> the number of the throw that is forged or
-- nil, then true when the open steps are ones I cannot vouch for (to be
-- counted). `old`: I have records of this table; sameHost: the host is the
-- player I knew.
--   Anyone: a state that no throws give (engine.thrown: variant, roll counts,
--   open steps), dice or open steps without a proof, dice that are not the
--   proof's, a turn in progress that is not the proof's seat and roll, more
--   moves since the throw than the snapshot has events.
--   old, the proof is the one I hold: no dice came since, so the roll counts
--   are my state's (engine.thrown with it); steps open again after I saw the
--   turn end, or a cascade behind mine, are forged under the host I knew.
--   Open steps other than mine (a cascade gone on) I did not see played:
--   forged when beyond the events my host says I missed, else to be counted.
--   old, another proof: a seed under my seat (unless I had left it myself)
--   goes with a commit I made for that very throw and seat (s.diceOwn); the throw I hold told otherwise is
--   forged; under the host I knew it is of a later throw. At my own event
--   number the state of the host I knew must be mine.
function int.forgery(s, prev, m, how, old, sameHost, p, x, y)
  local st, mine, last, engine = s.state, s.diceProof, s.diceLast, s:engine()
  local held, thrown = old and same(p, mine), engine.thrown
  local h = last and last.h or m.q
  local mark, n, r, t = x and p.h or h, 0, nil, nil
  if st and thrown then
    n, r, t = thrown(st, held and prev or nil)
    if not n then return mark end
  end
  local open = st ~= nil and st.left ~= nil
  if open or (st and st.dice ~= nil) then
    if not x or not same(st.dice, { x, y }) then return mark end
    if (r and (r ~= p.r or t ~= p.t)) or n > m.q - p.h - 1 then return p.h end
  end
  if not old then return nil end
  if sameHost and prev and st and m.q == how.q and not how.changed and not same(engine.snapshot(prev), engine.snapshot(st)) then return h end
  if held then
    if not (open and prev and thrown) then return nil end
    local had = prev.left ~= nil and thrown(prev) or nil
    if had == n and same(st.left, prev.left) then return nil end
    if sameHost and (not had or n < had or n - had > m.q - how.q) then return p.h end
    return nil, true
  end
  if not x then return nil end
  local seat = s.mySeat
  if seat and not how.away and p.s[seat] ~= nil and (s.diceOwn or {})[p.h .. ":" .. p.c[seat]] ~= (p.r or 0) then return p.h end
  if mine and ((sameHost and p.h <= mine.h) or (p.h == mine.h and same(p.s, mine.s))) then return mine.h end
  return nil
end

-- The records ---------------------------------------------------------------

local FIELDS = {
  "throw", "diceLast", "diceSeen", "diceBad", "diceAlone", "diceUnheard", "diceCry", "diceProof", "diceOwn",
  "diceHost", "diceNew", "diceAway", "diceHeard",
}

local function kept(s) return s.client.dice and s.client.dice[s.tid] end

local function keep(s)
  local all = s.client.dice or {}
  local rec = { state = s.state, q = s.seq }
  for i = 1, #FIELDS do rec[FIELDS[i]] = s[FIELDS[i]] end
  all[s.tid], s.client.dice = rec, all
end

local applied, adopted, hostChanged, refused = ext.applied, ext.adopted, ext.hostChanged, ext.refused

-- A start or an abort while the match was running on my client (an honest
-- host orders neither: a match ends first, also by a player leaving): a throw
-- I had given my seed to dies as a second try, and a start wipes no count.
ext.applied = function(s, seat, a)
  local k, t, rec = seat == 0 and a.k, s.throw, kept(s)
  local running = (k == "start" or k == "abort") and rec and rec.state ~= nil and not s:engine().over(rec.state)
  if running and t and not t.done and (t.sent or t.foul) then int.close(s, t.h, "bad", t.foul or "dodge", t) end
  local was = running and k == "start" and { s.diceSeen, s.diceBad, s.diceAlone, s.diceUnheard, s.diceAway }
  applied(s, seat, a)
  if was then s.diceSeen, s.diceBad, s.diceAlone, s.diceUnheard, s.diceAway = was[1], was[2], was[3], was[4], was[5] end
  s.diceHeard = s.client.env.now() -- when I last heard the table (Dice.int.unheard)
  keep(s)
end

-- I stand up myself (rec.away): what is thrown at the table until I sit down
-- again is not mine to see.
local stand = ns.Session.stand
ns.Session.stand = function(client)
  local rec = client.session and kept(client.session)
  if rec then rec.away = true end
  return stand(client)
end

-- A session new to a table I have records of takes them up again: the
-- snapshot is held against the state I had, as one pushed on me; as one I
-- asked for when I had stood up myself (how.away: the seat was not mine
-- meanwhile).
ext.adopted = function(s, prev, m, how)
  local rec = how.fresh and kept(s)
  if rec then
    for i = 1, #FIELDS do s[FIELDS[i]] = rec[FIELDS[i]] end
    prev = rec.state
    how = { asked = rec.away == true, away = rec.away, sat = how.sat, q = rec.q }
    if s.diceHost ~= s.host then hostChanged(s) end
  end
  adopted(s, prev, m, how)
  s.diceHeard = s.client.env.now()
  keep(s)
end

ext.hostChanged = function(s) hostChanged(s); keep(s) end
ext.refused = function(s, seat, a) refused(s, seat, a); keep(s) end

return Dice
