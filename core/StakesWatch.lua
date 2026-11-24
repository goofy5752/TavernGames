local _, ns = ...

-- What my client checks of a staked table's host (core/Stakes.lua notes the
-- fouls): the log of what I sent, the stand of my seat, a snapshot against my
-- game, a start no honest host plays. The rules:
--   (a) My clock is mine, on the turn length I accepted (Member.adopt: a
--       snapshot with another is forged). s.stakeTurn.at is my env.now() when
--       my client first saw that seat on turn, by an event or on receipt of a
--       snapshot, anew with the host's turn timer (core/StakesFair.lua); a
--       snapshot sets s.turnAt (Member.timedOut) from it, never from the
--       host's `left`, and keeps the clock only of the very turn I hold
--       (turnKey). A login (no clock of mine ran) brings the turn "unseen".
--   (b) My roll is tied to its turn (Rolls: s.myRoll) through every host
--       change. The first other host is not charged with it and the turn gets
--       a fresh clock, once; without a roll of mine every other host does.
--   (c) An idle or offline stand of my seat needs OFFLINE_STAND_SECONDS -
--       AUTO_GRACE on that clock, however the turn reached me.
--   (d) s.stakeLog, what I sent at this table: my moves, „Реванш“, sit and
--       stand (my rolls: Rolls' own sightings, judged in its `adopted` before
--       they go). A snapshot of any game is checked against it: a mark in my
--       name that I did not send, a new match of Морски шах that seats me
--       without my own sit or „Реванш“ since the last began (Stakes.began,
--       events too). It is saved with my stake note (Stakes.save), so a
--       /reload keeps what I sent; a start that rests on an entry of an
--       earlier session, or comes while the copy is in doubt (a crash:
--       Stakes.restore), is "unseen".
--   A snapshot shows my game when legal play leads from the state I hold to
--   it (Stakes.leadsTo), a round's end and the rounds after it included: what
--   I did not see of it is "unseen". Only what no play reaches is another game.
-- Session fields (local, never sent):
--   stakeLog  {k, c, g, r, old}: the action's kind and cell, s.stakeNo and the round
--             when sent; old: a login took the entry up from my saved variables
local Stakes = ns.Stakes

local C = ns.Const
local same = ns.Util.same
local pend, refresh, running = Stakes.pend, Stakes.refresh, Stakes.running

local LOG_KEPT = 32

-- Did I send a `k` (cell c, in round r) since the last game began here -> the
-- entry | nil (`sure`: one of this session, not one a login took up)
local function sentIn(s, k, c, r, sure)
  local log, g = s.stakeLog or {}, s.stakeNo or 0
  for i = 1, #log do
    local e = log[i]
    if e.k == k and e.g == g and e.c == c and (r == nil or e.r == r) and not (sure and e.old) then return e end
  end
  return nil
end
Stakes.sentIn = sentIn

-- I sent `a` (a member's ACT, a host's own move, my sit, my stand), or my
-- client took it for mine (Stakes' applied); logged once, and of this run.
function Stakes.sent(s, a)
  if s:engine().clock then ns.StakesChess.sent(s, a) end -- chess: its own log as well (core/StakesChess.lua)
  local log, r = s.stakeLog or {}, s.state and s.state.round
  local c = not s:engine().view and a.c or nil -- a card game: no face is kept (the log is saved)
  s.stakeLog = log
  local e = sentIn(s, a.k, c, r)
  if e then e.old = nil else log[#log + 1] = { k = a.k, c = c, g = s.stakeNo or 0, r = r } end
  if #log > LOG_KEPT then table.remove(log, 1) end
  Stakes.save(s)
end

-- My seat `seat` went while a game runs and I did not ask (`why`: the stand's,
-- nil when only my host's SNO "gone" or a snapshot told me; `max`: the game's
-- max before it): "stand" ("forged" when a snapshot shows it), unless a stand
-- for idleness (engine.idle; any why but "left") my own clock agrees with: my
-- seat on turn for OFFLINE_STAND_SECONDS, AUTO_GRACE left for the transport.
-- "unseen" when my clock did not see that turn begin (a fresh adopt), or when
-- another host restarted it and the turn's first clock agrees. After my own
-- roll on that turn at its max (Rolls: s.myRoll) such a stand is "roll", but
-- from the first other host since that roll (myRoll.pass). Judged once a game.
function Stakes.stood(s, seat, why, snap, max)
  if not s.stakeLive or s.role == "host" or s.stakeStood or sentIn(s, "stand") then return end
  s.stakeStood = true
  local t, now, r = s.stakeTurn, s.client.env.now(), s.myRoll
  local due = C.OFFLINE_STAND_SECONDS - C.AUTO_GRACE
  local mine = s:engine().idle and why ~= "left" and t and t.seat == seat
  if mine and r and r.max == max and r.pass ~= s.host then return pend(s, "roll") end
  if mine and now >= t.at + due then return end
  pend(s, (mine and (not t.seen or (t.was and now >= t.was + due))) and "unseen" or snap and "forged" or "stand")
end

-- My Морски шах timeout is due by my own clock (Member.timedOut's rule for a
-- turn my client saw begin, before this event): one mark of mine may be it.
local function timeoutDue(s, seat)
  local t = s.stakeTurn
  if not (t and t.seat == seat and t.seen and type(s.turn) == "number") then return false end
  if s.client.env.now() < t.at + s.turn then return false end
  for _, e in ipairs(s.sent or {}) do
    if e.at >= t.at and e.at < t.at + s.turn then return false end
  end
  return true
end

-- What a snapshot of Морски шах did for my seat that I did not -> true:
-- forged. A mark of mine that my game did not have and my log does not: in
-- another game any; in my game (carried on, `forward`, or a changed host's
-- `prefix` of it, an earlier round too) any but, carried on in the round I
-- hold, engine.auto's cell: my timeout, due by my clock or of a turn a login
-- brought me (no clock of mine saw it begin: the snapshot's "unseen").
local function doneForMe(s, prev, st, seat, forward, prefix)
  if not (st and st.board and st.round and seat) then return false end -- a board of rounds: Холдем's is no Морски шах
  local round, t = (forward or prefix) and prev.round == st.round, s.stakeTurn
  local auto = forward and round and (timeoutDue(s, seat) or (t and t.seat == seat and not t.seen)) and s:engine().auto(prev, seat)
  for c = 1, 9 do
    if st.board[c] == seat and not (round and prev.board[c] == seat) then
      if (forward or prefix) and sentIn(s, "mark", c, st.round) then
        if forward then ns.Member.mine(s, { k = "mark", c = c }) end -- shown: no later event may pass for it
      elseif auto and auto.c == c then
        Stakes.sent(s, { k = "mark", c = c }) -- taken for mine
      else
        return true
      end
    end
  end
  return false
end

-- Морски шах: does legal play lead from a to b in one match? From a's board,
-- or from the empty one of a later round (whoever's turn it is to begin it),
-- the marks b adds are played through the engine, seat by seat, with each of
-- the last mover's as the last (only the last mark may end a round). b must
-- stand where that play ends, and the points it holds beyond that play are
-- at most one for each round it skips, a's own open round among them.
local function marksLead(a, b)
  local E, skip = ns.Engines.ttt, b.round - a.round
  if skip < 0 or (skip > 0 and a.phase == "match") then return false end
  local x, add = E.restore(a), { {}, {} }
  if skip > 0 then
    x.board, x.round, x.phase, x.line, x.draw = { 0, 0, 0, 0, 0, 0, 0, 0, 0 }, b.round, "play", nil, false
    x.first = skip % 2 == 0 and a.first or 3 - a.first
    x.turn = x.first
  end
  for c = 1, 9 do
    local v, w = x.board[c], b.board[c]
    if v ~= w then
      if v ~= 0 or not add[w] then return false end
      table.insert(add[w], c)
    end
  end
  local n, hidden = #add[1] + #add[2], skip > 0 and skip - 1 + (a.phase == "play" and 1 or 0) or 0
  local last = x.turn and add[n % 2 == 1 and x.turn or 3 - x.turn] or {}
  for i = 1, math.max(1, #last) do
    local y, at, played = E.restore(x), { 0, 0 }, true
    for _ = 1, n do
      local seat = y.turn
      local cells = seat and add[seat]
      local k = cells and at[seat] + 1
      at[seat or 1] = k
      if cells == last then k = (k == #cells and i) or (k >= i and k + 1) or k end -- its i-th mark goes last
      played = played and cells ~= nil and cells[k] ~= nil and E.apply(y, seat, { k = "mark", c = cells[k] }) == true
    end
    local g1, g2 = y.score[1] - a.score[1], y.score[2] - a.score[2] -- the point of this play
    local h1, h2 = b.score[1] - y.score[1], b.score[2] - y.score[2] -- the points of the rounds skipped
    local over = b.score[1] >= E.WINS or b.score[2] >= E.WINS
    if played and y.turn == b.turn and y.first == b.first and h1 >= 0 and h2 >= 0 and h1 + h2 <= hidden
        and (skip == 0 or (b.score[1] - g1 < E.WINS and b.score[2] - g2 < E.WINS))
        and b.phase == ((y.phase == "play" and not over and "play") or (over and "match") or "round")
        and b.winner == (b.phase == "match" and (b.score[1] >= E.WINS and 1 or 2) or nil) then
      return true
    end
  end
  return false
end

-- Does game state a lead to b in one game (b is a, or a later point of it)?
-- Death Roll (a start): the same start, a's rolls are b's first rolls. Морски шах: by
-- legal play (marksLead; a state it cannot read, Табла's roll counts too, leads nowhere).
function Stakes.leadsTo(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  if a.rolls and b.rolls and a.start then
    if a.start ~= b.start or #a.rolls > #b.rolls then return false end
    for i = 1, #a.rolls do
      if not same(a.rolls[i], b.rolls[i]) then return false end
    end
    return true
  end
  if a.moves and b.moves then return ns.StakesChess.leads(a, b) end
  if not (a.board and b.board) then return false end
  local read, leads = pcall(marksLead, a, b)
  return read and leads
end

local leadsTo = Stakes.leadsTo

-- Which turn of its game a state stands at (two states of one game at the
-- same key and seat: the same turn) -> number | nil (it cannot tell)
local function turnKey(st)
  if type(st) ~= "table" then return nil end
  if st.rolls and st.start then return #st.rolls end
  if st.moves then return ns.StakesChess.turnKey(st) end
  if not (st.board and st.round) then return nil end
  local n = 0
  for c = 1, 9 do
    if st.board[c] ~= 0 then n = n + 1 end
  end
  return st.round * 10 + n
end

-- A snapshot replaced my state (how: see Member.adopt). The very game I hold:
-- nothing. My game carried on (or, from a changed host, one behind mine, a
-- prefix: its marks in my name are judged by my log like any other): the same
-- game, "unseen". Anything else is another game. A snapshot nobody asked
-- for that changes my game is "forged", from my own host always, from a
-- changed host unless a prefix (F21) or the game is judged (core/StakesFair.lua); one I asked for or logged in with
-- is "unseen". Its Death Roll state must say staked (Member.adopt set mine).
-- The foul of a game that was running here stays, whatever the snapshot (the
-- host can make me ask for one at will: a TCK or a gap); Rolls' adopted
-- judged the rolls it brought in my name. The clock of my turn is my own (a; how.tn), and so are the options of my staked table (how.o).
ns.Ext.stakes.adopted = function(s, prev, m, how)
  local st, was, on, me = s.state, s.stakeLive, running(s), s.client.env.me
  if how.fresh then Stakes.restore(s) end -- a login back to my table: what I sent there before
  local kept = was and s.stakeFoul or nil
  if how.tn or how.o or (s:engine().idle and type(m.st) == "table" and m.st.staked ~= true) then pend(s, "forged") end
  local identical = prev ~= nil and st ~= nil and same(prev, st) and was == on
  local forward = leadsTo(prev, st)
  local prefix = not forward and how.changed and ((how.moved and Stakes.judged(s)) or leadsTo(st, prev)) -- a judged game: the same match
  local cont = identical or forward or prefix
  if not identical and (was or on) then
    local pushed = not (how.changed or how.asked or how.fresh)
    pend(s, (pushed or (how.changed and not how.asked and not cont)) and "forged" or "unseen")
  end
  local held = s.stakeSeat -- my seat before this snapshot
  if st and st.moves then local f = ns.StakesChess.adopted(s, prev, st, how, forward, prefix); if f then pend(s, f) end
  elseif held and not identical and doneForMe(s, prev, st, held, forward, prefix) then pend(s, "forged") end
  if held and s.seats[held] ~= me then Stakes.stood(s, held, nil, true, prev and prev.max) end
  local sat = how.sat or (how.sit and not held) -- a seat I did not hold (one the host had stood: by my own SIT)
  if sat then s.stakeRefill = "filled" end -- my own sit filled the seat
  if s.mySeat and (how.req or (sat and not how.fresh)) then Stakes.sent(s, { k = "sit" }) end -- my own SIT took me in
  local t = s.stakeTurn
  local sameTurn = cont and on and t ~= nil and t.seat == st.turn and (identical or (turnKey(st) ~= nil and turnKey(prev) == turnKey(st)))
  refresh(s, not cont, not sameTurn, how)
  if kept then Stakes.foul(s, kept) end
  s.stakeHost, t = s.host, s.stakeTurn
  s.turnAt = t and t.seat == s.mySeat and t.at or nil
end
