local _, ns = ...

-- The extension `stakes` at a cash table (Stakes.cash: a staked table whose
-- engine has cashGame, Холдем): a game there is one long sitting, and money
-- moves only by the out records of the engine state (engines/holdem_cash.lua).
-- This file wraps the hooks `applied`, `adopted`, `leaving` and `gone`
-- (outermost, after core/StakesFair.lua) and adds `still`. The rules:
--   No forfeit. Every wrapped hook runs with s.stakeRoster nil, before and
--     after the original: F1's forfeit of a stand, its R, my stakeLeft at my
--     own „Стани“, the host's whisper of a stand and the renamed-seat check of
--     core/StakesStart.lua do nothing here. Stakes.stood (my seat stood up
--     while I did not ask) stays.
--   My own names (s.cashNames, seat -> name; local, never sent): only for the
--     rename check below, never for money (the out record names its pairs by
--     the engine's own `who`). Taken from s.seats at the `start` event and at
--     a snapshot that is not my state (a first one, a login, a resync: the
--     names of the state I take up); a `sit` adds its name, a `stand` drops
--     its seat.
--   A snapshot (before the original): other options than the ones I accepted
--     (how.o, how.tn), or a state whose blinds, betting or rebuy mode is not my
--     s.opt's, or a staked state without `cash`: forged. Only when the
--     snapshot is my very state (same(prev, st), a game running): a seat of my
--     names that it shows under another name is forged from my host, a
--     question ("unseen") from a host new to me (how.moved); my name stays.
--     A snapshot of the hand I hold (same g, same hand) is its host's own
--     view: a face of that hand's deck that I knew and it does not show stays
--     mine (a face it shows otherwise is a difference like any other), so an
--     honest successor's snapshot is the state I hold (F3-F C1).
--   My own sit starts my sitting (after the original): when my own SIT took
--     me in (a seat I did not hold: a repeated SIT of a seated player is
--     answered with the snapshot again, and a relog's SIT or WAT at the table
--     my note already named is a login back), my seat is the record whose
--     `who` is me (not leaving), or a chair still leaving whose `takenWho` is
--     me (no record of mine yet: the record there is the leaver's). No chips,
--     no buy, no `cleared`, no pair in cash.took and not dealt into the
--     running hand (or such a taken chair): s.stakeFoul is only what this
--     snapshot's own checks above raised. With chips, a buy, a `cleared` or a
--     pair in my name there: forged. A record of an earlier sitting of mine
--     still leaving the hand keeps the snapshot's verdict (its settlement
--     rests on a history this session did not see).
--   The clock: another seat's `buy` or `cashout` is `still` (the host keeps
--     the turn timer; with no seat on turn it arms its timers, two seats with
--     chips may now be enough for a hand), and my client keeps s.stakeTurn and
--     s.turnAt across it, so an honest timeout after my lost ACT is no foul.
--   No break between games (Stakes.gap 0, core/StakesStart.lua): a new game
--     gives nobody chips, so staying seated accepts nothing.
--   The dealer's step (E2, H14): s.hostHeard is my env.now() at the last EV,
--     SNP or TCK of my host that my client took; s.stepAsks = {k = the dueKey,
--     n} counts my asks for the step due (core/Cash.lua's `ask`), an ask only
--     while my client heard the host within FAIR_ASK_GAP before it (a dead
--     link loses the asks and the host's words alike). Member.unasked reads it.
--   The key draw (E8): the book's forged mark (rule 6a of core/Book.lua: my key
--     left at the end and the same game runs on) is my foul too, at the end of
--     every event and snapshot: "forged", "unseen" when my own key stayed
--     (book.held). And when my game was over on my client, a snapshot of that
--     game over with another end (another hand count or other out records)
--     says the host told me an end its table never had: before the book takes
--     the snapshot's keys, it is forged (from another host or epoch than the
--     one I followed, how.changed: held, a question), so my notes of that end,
--     still waiting, read it.
local Stakes, C = ns.Stakes, ns.Const

local RANK, pend, same = Stakes.RANK, Stakes.pend, ns.Util.same

-- Is s a cash table -> bool.
function Stakes.cash(s)
  return s.stake ~= nil and s:engine().cashGame == true
end

-- My names from the table as it sits now.
local function takeNames(s)
  local out = {}
  for i = 1, #s.seats do
    if type(s.seats[i]) == "string" then out[i] = s.seats[i] end
  end
  s.cashNames = out
end

-- Does the state st hold the options of my table (s.opt) -> bool.
local function myOptions(s, st)
  local o = s.opt or {}
  return type(st.cash) == "table" and st.bb == o.blinds and st.sb == math.floor((o.blinds or 0) / 2) and st.betting == o.betting
    and st.cash.rebuy == o.rebuy
end

-- Has seat i a pair in the matrix of cash -> bool.
local function paired(cash, i)
  if type(cash) ~= "table" or type(cash.took) ~= "table" then return false end
  if type(cash.took[i]) == "table" and next(cash.took[i]) ~= nil then return true end
  for _, row in pairs(cash.took) do
    if type(row) == "table" and row[i] then return true end
  end
  return false
end

-- My own sit in state st -> true (clean: my record has nothing yet, or a
-- chair still leaving is taken for me), false (chips, a buy, a pair, a
-- `cleared` or a hand in my name), nil (no seat of mine in the state, or a
-- record of an earlier sitting of mine still leaving: its settlement rests on
-- a history this session took from the snapshot, so the snapshot's verdict
-- stands).
local function sitting(s, st, me)
  local engine, clean, taken, old = s:engine(), nil, nil, false
  for i, r in ipairs(type(st.seats) == "table" and st.seats or {}) do
    if type(r) == "table" and r.who == me and r.leaving then old = true
    elseif type(r) == "table" and r.who == me and clean == nil then
      local p = engine.inHand(st) and type(st.p) == "table" and st.p[i]
      clean = r.chips == 0 and r.bought == 0 and r.cleared == 0 and not paired(st.cash, i) and not (p and not p.gone)
    end
    if type(r) == "table" and r.leaving and r.takenWho == me then taken = true end
  end
  if clean == false then return false end
  if old then return nil end
  if clean then return true end
  return taken
end

-- Dealer: my ask for the step due now has gone to my host (core/Cash.lua's `ask`).
function Stakes.stepAsked(s)
  if s.role == "host" then return end -- my own step goes to no other client
  local asks = s.stepAsks
  if not (asks and asks.k == s.dueKey) then asks = { k = s.dueKey, n = 0 }; s.stepAsks = asks end
  if s.hostHeard and s.client.env.now() - s.hostHeard <= C.PING_EVERY + C.FAIR_ASK_GAP then asks.n = asks.n + 1 end
end

-- My host's heartbeat (Member's TCK at my epoch) is heard.
local tick = ns.Member.handlers.TCK
ns.Member.handlers.TCK = function(client, sender, m)
  local s = client.session
  if s and s.tid == m.tid and s.host == sender and m.e == s.epoch and Stakes.cash(s) then s.hostHeard = client.env.now() end
  return tick(client, sender, m)
end

-- A SIT or WAT with no table of mine, while my note (db.stakeSat, kept across a
-- logout while I am seated) already names that table: a relog that clicks its
-- own table before the host's snapshot. The host answers "already here", so
-- that snapshot is a login back, not my own sit (client.cashBack, read by the
-- hook `adopted`). A second click of one request keeps the first one's word.
local request = ns.Session.request
function ns.Session.request(client, kind, tid, seat, sk)
  local p, note = client.pending, client.env.db.stakeSat
  if not (p and p.tid == tid) then
    client.cashBack = client.session == nil and type(note) == "table" and note.tid == tid or nil
  end
  return request(client, kind, tid, seat, sk)
end

-- The book's forged mark is my foul (E8).
local function marked(s)
  local book = s.book
  if book and book.forged then Stakes.foul(s, book.held and "unseen" or "forged") end
end

-- Before the book takes a snapshot's keys (ns.Ext.cash.adopted): my game over, the same game over with another end.
local cashAdopted = ns.Ext.cash.adopted
ns.Ext.cash.adopted = function(s, prev, m, how)
  local st, book, e = s.state, s.book, s:engine()
  if Stakes.cash(s) and book and not book.forged and type(prev) == "table" and type(st) == "table" and prev.g == book.g and st.g == book.g
      and e.over(prev) and e.over(st) and not (prev.hand == st.hand and same(prev.cash and prev.cash.outs, st.cash and st.cash.outs)) then
    ns.Book.forge(book)
    if how.changed then book.held = true end
  end
  return cashAdopted(s, prev, m, how)
end

local ext = ns.Ext.stakes
local applied, adopted, leaving, gone, still = ext.applied, ext.adopted, ext.leaving, ext.gone, ext.still

ext.applied = function(s, seat, a)
  if not Stakes.cash(s) then return applied(s, seat, a) end
  local t, at = s.stakeTurn, s.turnAt
  local money = seat ~= 0 and (a.k == "buy" or a.k == "cashout")
  s.stakeRoster, s.hostHeard = nil, s.client.env.now()
  applied(s, seat, a)
  s.stakeRoster = nil
  if money and t and t.seat ~= seat and s.stakeTurn and s.stakeTurn.seat == t.seat then s.stakeTurn, s.turnAt = t, at end
  local k = seat == 0 and a.k
  if k == "start" then
    takeNames(s)
  elseif k == "sit" and type(a.name) == "string" then
    s.cashNames = s.cashNames or {}
    s.cashNames[a.seat] = a.name
  elseif k == "stand" and s.cashNames then
    s.cashNames[a.seat] = nil
  end
  if money and s.role == "host" and s.state and not s.state.turn then s:armTimers() end
  marked(s)
end

ext.adopted = function(s, prev, m, how)
  if not Stakes.cash(s) then return adopted(s, prev, m, how) end
  local st, raised = s.state, nil
  if type(prev) == "table" and type(st) == "table" and prev.g ~= nil and prev.g == st.g and prev.hand == st.hand
      and type(prev.deck) == "table" and type(st.deck) == "table" then
    for i, f in pairs(prev.deck) do if st.deck[i] == nil then st.deck[i] = f end end
  end
  local function raise(why)
    if not raised or RANK[why] > RANK[raised] then raised = why end
    pend(s, why)
  end
  if how.o or how.tn or (type(st) == "table" and not myOptions(s, st)) then raise("forged") end
  local identical = prev ~= nil and st ~= nil and same(prev, st)
  if identical and s.stakeLive and Stakes.running(s) then
    for seat, name in pairs(s.cashNames or {}) do
      if type(s.seats[seat]) == "string" and s.seats[seat] ~= name and st.seats[seat] then raise(how.moved and "unseen" or "forged") end
    end
  end
  local held = s.stakeSeat -- my seat before this snapshot (core/StakesWatch.lua's guard)
  s.stakeRoster, s.hostHeard = nil, s.client.env.now()
  adopted(s, prev, m, how)
  s.stakeRoster = nil
  if not identical or how.fresh then takeNames(s) end
  local back = s.client.cashBack -- my request was a login back (Session.request below)
  s.client.cashBack = nil
  if s.mySeat and type(st) == "table" and ((how.req and not back) or (not how.fresh and (how.sat or (how.sit and not held)))) then
    local clean = sitting(s, st, s.client.env.me)
    if clean then s.stakeFoul = raised elseif clean == false then Stakes.foul(s, "forged") end
  end
  marked(s)
end

ext.leaving = function(s)
  if not Stakes.cash(s) then return leaving(s) end
  s.stakeRoster = nil
  leaving(s)
  s.stakeRoster = nil
end

ext.gone = function(s)
  if not Stakes.cash(s) then return gone(s) end
  s.stakeRoster = nil
  gone(s)
  s.stakeRoster = nil
end

-- Another seat's buy or cash-out leaves the turn clock alone.
ext.still = function(s, seat, a)
  if Stakes.cash(s) and seat ~= 0 and (a.k == "buy" or a.k == "cashout") then return true end
  if still then return still(s, seat, a) end
end
