local _, ns = ...

-- The member side of a table session (player or watcher; see core/Session.lua):
-- adopting the host's SNP snapshot, applying its EV events strictly in order,
-- following its TCK heartbeat, its SNO refusals and its END, and the PNG/SYN
-- the member sends back. Session.receive dispatches the WHISPER/GUILD types in
-- Member.handlers, each fn(client, sender, m).
local Member = {}
ns.Member = Member

local C = ns.Const
local Session = ns.Session
local Succession = ns.Succession
local copy, seatOf = ns.Util.copy, ns.Util.seatOf

-- PNG to the host every PING_EVERY seconds; while stale, the snapshot request again.
function Session:schedulePing()
  self.pingTimer = self.client:after(C.PING_EVERY, function()
    self.pingTimer = nil
    if self.stale then
      self:requestSync()
    else
      self.client:send("WHISPER", self.host, Session.message("PNG", { tid = self.tid }))
    end
    self:schedulePing()
  end)
end

-- Asks the host for a snapshot, at most once per SYN_MIN_GAP seconds: SYN{have},
-- or WAT from a watcher whose new host does not know it yet (see Succession).
function Session:requestSync()
  local now = self.client.env.now()
  if self.lastSyn and now - self.lastSyn < C.SYN_MIN_GAP then return end
  self.lastSyn, self.asked = now, true
  if self.stale and not self.mySeat then
    self.client:send("WHISPER", self.host, Session.message("WAT", { tid = self.tid }))
  else
    self.client:send("WHISPER", self.host, Session.message("SYN", { tid = self.tid, have = self.seq }))
  end
end

-- The stake I accepted for table `tid` -> known, sk: the stake I am being
-- asked about (s.stakeAsk, ns.Stake.ask), else my own note for the table
-- (db.stakeSat, see ns.Stake.note), else none (nil: only a fun table) when I am at
-- the table in this run, my note was written or cleared in this run, or the
-- table is not the one my last client left me at (presence.home).
-- Unknown: a fresh login back to that table whose loaded note is of another
-- table or missing (a crash): ns.Stake.ask. Never a watcher session's stake.
local function accepted(client, tid)
  local note, s = client.env.db.stakeSat, client.session
  if s and s.stakeAsk then return true, s.stake end
  if type(note) == "table" and note.tid == tid then return true, note.sk end
  if s or client.stakeNoted or tid ~= client.presence.home then return true, nil end
  return false, nil
end

-- Does the snapshot m show the very game I hold -> bool: my own seq and the
-- state I have, live or not as mine. The only snapshot an asked seat takes: a
-- snapshot carries no other proof of which game it is, and at my own seq an
-- honest host holds the state I hold.
function Member.sameGame(s, m)
  local mine = s.state and s:engine().snapshot(s.state) or nil
  return m.q == s.seq and (m.tbl.st == "live") == (s.status == "live") and ns.Util.same(m.st, mine)
end

-- Member: session from a snapshot (new, or replacing the current one; a host
-- that lost its table to `sender` steps down first). A snapshot that seats me
-- at another stake than the one I accepted stands me up ("refused" "stake");
-- one that seats me at a staked table at an unknown stake asks (ns.Stake.ask).
function Member.adopt(client, sender, m)
  local t, me = m.tbl, client.env.me
  local seat = seatOf(t.s, me)
  local known, sk = accepted(client, m.tid)
  -- My staked table at another stake while I sit in its running game: forged
  -- (the hook `ended`, core/Stakes.lua), and no STD goes: I gave up no seat.
  local cur = client.session
  local robbed = cur ~= nil and cur.tid == m.tid and cur.stake ~= nil and cur.stake ~= t.sk and cur:hook("ended", sender) == true
  if seat and known and sk ~= t.sk then
    if not robbed then client:send("WHISPER", sender, Session.message("STD", { tid = m.tid })) end
    client.pending, client.gaveUp = nil, m.tid
    if client.session and client.session.role == "host" then Succession.demote(client.session) end
    if client.session then Session.leave(client) end
    return Session.refuse(client, m.tid, "stake")
  end
  -- An asked seat is kept for the game it was asked in only: a snapshot, at
  -- any q, that is not that very game (a new game, a gap, another state at my
  -- own q) stands me up before anything of it is taken.
  local asked = client.session
  local same = seat and asked and asked.stakeAsk and Member.sameGame(asked, m)
  if seat and asked and asked.stakeAsk and not same then
    if sender ~= asked.host then client:send("WHISPER", sender, Session.message("STD", { tid = m.tid })) end
    return ns.Stake.standUp(client, asked)
  end
  local ask = seat ~= nil and not known and t.sk ~= nil
  local fresh = client.session == nil -- no memory of this table (a relog, or I just came)
  local s = client.session or setmetatable({ client = client }, Session)
  local prevState, prevHost = s.state, s.host
  -- At the staked table I accepted my clock runs on the turn length I
  -- accepted (my note's tn; a note without one takes this snapshot's): a
  -- snapshot with another never changes it, and is forged (core/StakesWatch.lua).
  -- So with the options of the staked table I accepted (my note's o; a note without
  -- them takes this snapshot's): a snapshot with others keeps mine (how.o).
  local note, tn, opt, otherOpt = client.env.db.stakeSat, t.tn, ns.Games.resolve(t.g, t.o, t.sk ~= nil), false
  if type(note) == "table" and note.tid == m.tid and note.sk ~= nil and note.sk == t.sk then
    if type(note.tn) ~= "number" and type(tn) == "number" then note.tn = tn end
    tn = note.tn
    note.o = type(note.o) == "table" and ns.Games.resolve(t.g, note.o, true) or nil -- a note from another build: defaults filled in
    if not note.o then note.o = ns.Stake.options(t.g, opt) end
    if note.o then otherOpt, opt = not ns.Util.same(note.o, opt), copy(note.o) end
  end
  -- How this snapshot came, for the extensions: fresh, from a host new to me
  -- (changed), answering a request of mine (asked: SYN, WAT or SIT), with a
  -- seat I did not have (sat); q = my seq before it; req: it takes me in at
  -- my own SIT or WAT (a newcomer, not a login back to a seat I held); sit:
  -- it seats me while a SIT of mine at this table is unanswered.
  local how = {
    fresh = fresh, moved = not fresh and prevHost ~= sender, changed = not fresh and (prevHost ~= sender or s.epoch ~= m.e or s.stale == true),
    asked = s.asked == true, sat = seat ~= nil and s.mySeat == nil, q = s.seq,
    req = fresh and client.pending ~= nil and client.pending.tid == m.tid, sit = seat ~= nil and s.sitAsked ~= nil,
    tn = tn ~= t.tn, -- another turn length than the one I accepted
    o = otherOpt,    -- other table options than the ones I accepted
  }
  if s.role == "host" then Succession.demote(s) end
  s.tid, s.role, s.mySeat, s.host = m.tid, seat and "player" or "watcher", seat, sender
  s.epoch, s.seq, s.seats = m.e, m.q, copy(t.s)
  s.game, s.access, s.turn, s.watchers, s.stake = t.g, t.ac, tn, t.w or 0, t.sk
  s.opt = opt
  local engine = ns.Games.engine(t.g)
  s.state = type(m.st) == "table" and engine.restore(m.st) or nil
  -- The stake I accepted decides whether the game is staked, never the host's
  -- state (a snapshot that said otherwise is forged: core/Stakes.lua).
  if s.state and engine.idle then s.state.staked = s.stake ~= nil or nil end
  -- A result already in the snapshot was announced before: noted, not emitted.
  s.resultSeen = s.state ~= nil and engine.result ~= nil and engine.result(s.state) ~= nil
  -- No result yet: the table as it sits now is the one a "result" names (Session:noteResult).
  if not s.resultSeen then s.seatedBefore = copy(s.seats) end
  s.status = t.st == "live" and "live" or (s.state and "aborted" or "open")
  s.deadline = type(m.left) == "number" and client.env.now() + m.left or nil
  -- My turn in a snapshot: no clock of mine saw it begin, the host's word dates it
  -- (at a staked table never: my own clock does, the hook `adopted` of core/StakesWatch.lua).
  s.turnAt = s.stake == nil and seat and s.state and s.state.turn == seat and s.deadline and type(s.turn) == "number" and s.deadline - s.turn or nil
  s.stale, s.sitAsked, s.asked = nil, nil, nil
  if not same then s.gameNo = (s.gameNo or 0) + 1 end -- another game, for all I can tell (Session:noteResult)
  s.invited = {}
  s:addInvited(m.inv)
  client.pending, client.gaveUp = nil, nil
  client.session = s
  -- The extensions hear of a new host and of the state this snapshot replaced.
  if prevHost and prevHost ~= sender then s:hook("hostChanged") end
  s:hook("adopted", prevState, m, how)
  s:armAuto()
  if not s.pingTimer then s:schedulePing() end
  Succession.watchHost(s)
  -- A table I hosted until now, or one adopted before any TBL: list it as the host's.
  if not client.lobby:get(s.tid) then
    client.lobby:receive("WHISPER", sender, Session.message("TBL", copy(t)))
  end
  client.presence:setAt(s.tid)
  Session.emit(client)
  if ask then ns.Stake.ask(client) end
end

local function unusable(m, sender)
  local t = m.tbl
  return type(m.e) ~= "number" or type(m.q) ~= "number" or not ns.Lobby.valid(t)
    or t.tid ~= m.tid or t.h ~= sender or not ns.Games.engine(t.g)
    or (t.st == "live" and type(m.st) ~= "table")
end

local function onSnapshot(client, sender, m)
  local t, s, p = m.tbl, client.session, client.pending
  if unusable(m, sender) then
    -- Seated at a table I cannot join (e.g. a game I do not have): free the seat.
    if type(t) == "table" and type(t.s) == "table" and seatOf(t.s, client.env.me)
        and not (s and s.tid == m.tid) then
      client:send("WHISPER", sender, Session.message("STD", { tid = m.tid }))
    end
    return
  end
  if s and s.tid == m.tid then
    -- My table: a new host's snapshot always; my own host's unless it is older
    -- than what I have (a stale member has nothing worth keeping).
    local kind = Succession.authority(s, sender, m.e)
    if kind == "new" or (kind == "current" and (s.stale or m.q >= s.seq)) then
      Member.adopt(client, sender, m)
    end
  elseif not s and ((p and p.tid == m.tid and p.host == sender)
      or (client.gaveUp ~= m.tid and seatOf(t.s, client.env.me) and client.presence:mayReturn(m.tid))) then
    -- The answer to my request (sit, watch, an invitation I took), or a seat I
    -- still hold at a table I was at (after a relog: the one it left me at).
    Member.adopt(client, sender, m)
  else
    -- Seated or listed after I gave up waiting or went elsewhere, or at a table
    -- I never asked for: free the place again (the STD is the trace line).
    client:send("WHISPER", sender, Session.message("STD", { tid = m.tid }))
  end
end

-- Does the in-order event m stand me up before it is applied -> bool (see onEvent).
function Member.staleSeat(s, m)
  local a, client = m.a, s.client
  if type(a) ~= "table" then return false end
  if s.stakeAsk and (ns.Stake.over(s) or (m.seat == 0 and a.k == "start") or a.k == "rematch") then return true end
  if s.stake == nil or m.seat ~= 0 or a.k ~= "sit" or a.name ~= client.env.me then return false end
  local note = client.env.db.stakeSat
  return not (type(note) == "table" and note.tid == s.tid and note.sk == s.stake)
end

-- My action goes to the host (Session.act) and is remembered, the last
-- SENT_KEPT of them as {a, at = env.now() when sent}, until the host's event
-- for my seat shows it (the same action sent again, a retried timeout, is
-- remembered once).
local SENT_KEPT = 8
function Member.sendAct(s, a)
  local sent = s.sent or {}
  s.sent = sent
  if not (sent[#sent] and ns.Util.same(sent[#sent].a, a)) then sent[#sent + 1] = { a = copy(a), at = s.client.env.now() } end
  if #sent > SENT_KEPT then table.remove(sent, 1) end
  if s.stake ~= nil then ns.Stakes.sent(s, a) end -- the table's log of what I sent (core/StakesWatch.lua)
  s.client:send("WHISPER", s.host, Session.message("ACT", { tid = s.tid, a = a }))
end

-- Is `a` an action I sent and have not seen come back -> bool. It is taken
-- off the list together with the ones sent before it (the host dropped them).
function Member.mine(s, a)
  local sent = s.sent or {}
  for i = 1, #sent do
    if ns.Util.same(sent[i].a, a) then
      for _ = 1, i do table.remove(sent, 1) end
      return true
    end
  end
  return false
end

-- Is the event m the host's timeout for my seat, due by my own clock -> bool?
-- Only for an engine whose automatic move needs no hidden card (publicAuto, or
-- any engine without `view` at a staked table: the host plays it AUTO_GRACE
-- after the deadline, Session:armTimers): flagged auto, the move engine.auto
-- makes, and my own turn time has run out since my seat came on turn
-- (s.turnAt, my env.now() then). The host's `left` is not taken: a host that
-- sent left = 0 could fold me at once. At a staked table no timeout is due
-- while an ACT I sent on this turn before my deadline is still unmatched in
-- s.sent: the host dropped my move.
function Member.timedOut(s, m)
  local engine, at = s:engine(), s.turnAt
  if m.auto ~= true or not (engine.publicAuto or (s.stake and not engine.view)) or not at or type(s.turn) ~= "number" then return false end
  if s.client.env.now() < at + s.turn then return false end
  if s.stake ~= nil then
    local sent = s.sent or {}
    for i = 1, #sent do
      if sent[i].at >= at and sent[i].at < at + s.turn then return false end
    end
  end
  return s.state ~= nil and ns.Util.same(m.a, engine.auto(s.state, m.seat))
end

-- Has FAIR_WAIT passed by my own clock since `at` (nil: I did not see it
-- begin, a snapshot brought it)? AUTO_GRACE is left for the transport: my
-- clock starts when the host's event reaches me, after the host's own.
local function waited(s, at)
  return at == nil or s.client.env.now() >= at + C.FAIR_WAIT - C.AUTO_GRACE
end

-- A seat-0 event of a sealed table (core/Cash.lua) that no honest host plays
-- now -> bool (a host's stand of a seat stays its claim: no member can tell):
-- - while the hand runs, an away of my seat while I am dealt in and not
--   folded, from the blinds on, unless the shuffle is in stage commit or seed
--   and FAIR_WAIT has passed since its open (a silent commit, the dealer and
--   the seats it named; members see no commit before the `commits` event, so
--   whether mine was in cannot be told); after a void the hand is over;
-- - while the hand runs, a void with no shuffle open or in stage commit (an
--   honest host never plays one), in stage seed earlier than FAIR_WAIT after
--   the open (the lapse of a round with seats named as missing), in a dealt
--   hand earlier than FAIR_WAIT after its step became due (fair.openedAt,
--   s.dueAt), unless the dealer's seat has left the hand's dealer (a stand
--   mid-hand, a new host's takeover).
-- At a staked table (core/Cash.lua's `lapsed` voids before any away, E5):
-- - an away of my dealt-in, unfolded seat while the hand runs, in any stage;
-- - a void in stage commit only earlier than FAIR_WAIT after the open;
-- - a void of the hand I deal, while I hold its deck, also when my client
--   asked for the step due at least twice with the host heard
--   (s.stepAsks, Stakes.stepAsked: E2). Any other void of my dealt hand is
--   the honest one (a step that never reached the host) and counts as one I
--   asked for (round.voidAsked: core/DealHooks.lua does not call it forged).
-- Called once per EV, before it is applied; it may mark the round (round.voidAsked) for the void it returns false for.
function Member.unasked(s, seat, a)
  local engine, st = s:engine(), s.state
  if seat ~= 0 or type(a) ~= "table" or not (engine.sealed and st and engine.inHand(st)) then return false end
  local fair, staked = s.fair, s.stake ~= nil
  local round = fair and fair.stage ~= "done" and fair or nil
  if a.k == "away" then
    local p = s.mySeat and a.seat == s.mySeat and st.p and st.p[s.mySeat]
    if not p or p.folded then return false end
    if not staked and round and (round.stage == "commit" or round.stage == "seed") then return not waited(s, round.openedAt) end
    return true
  elseif a.k == "void" then
    if not round then return true end
    if round.stage == "commit" then return not (staked and waited(s, round.openedAt)) end
    if round.stage == "seed" then return not waited(s, round.openedAt) end
    if s.seats[round.d] == round.dealer and not (s.dueKey and waited(s, s.dueAt)) then return true end
    if not (staked and round.d == s.mySeat and round.deck) then return false end
    local asks = s.stepAsks
    if asks and asks.k == s.dueKey and asks.n >= 2 then return true end
    round.voidAsked = true
    return false
  end
  return false
end

-- Events are taken only from my host, at exactly my epoch, in order. An epoch
-- is never adopted from an EV, and a stale member waits for its snapshot.
-- With hidden hands (engine.view), and at a staked table whose engine has no
-- `idle` (Морски шах; Death Roll's rolls are judged by Rolls.audit alone),
-- nobody but my client moves for my seat, my timeouts included
-- (Session:armAuto), but for the host's public timeout once
-- my own clock ran out (Member.timedOut): an event for it that I did not send
-- is reported to the extensions (hook `forged`) and applied like any other;
-- so is a seat-0 event of a sealed table no honest host plays now (unasked). s.turnAt: my env.now() when
-- an event I applied put my seat on turn (nil while it is not on turn).
local function onEvent(client, sender, m)
  local s = client.session
  if not s or s.role == "host" or s.tid ~= m.tid or s.host ~= sender or s.stale then return end
  if m.e ~= s.epoch or type(m.q) ~= "number" or m.q <= s.seq then return end
  if m.q > s.seq + 1 then return s:requestSync() end
  -- Before the event is applied: an asked stake I did not accept goes before
  -- anything that begins a new game (a start, a rematch, any event once the
  -- asked game is over; ns.Stake.ask); at a staked table a sit naming me is
  -- forged (an honest host skips the sitter, who gets the snapshot) unless my
  -- own SIT note for this table and stake stands.
  if Member.staleSeat(s, m) then return ns.Stake.standUp(client, s) end
  local engine = s:engine()
  if m.seat == s.mySeat and (engine.view or (s.stake and not engine.idle)) and not Member.mine(s, m.a) and not Member.timedOut(s, m) then
    s:hook("forged", m.seat, m.a, m.auto)
  elseif Member.unasked(s, m.seat, m.a) then
    s:hook("forged", m.seat, m.a)
  end
  local turn = s.state and s.state.turn
  if not s:apply(m.seat, m.a) then
    s:hook("refused", m.seat, m.a)
    client.events:emit("desync", s.tid)
    return s:requestSync()
  end
  s.seq = m.q
  if not (s.mySeat and s.state and s.state.turn == s.mySeat) then
    s.turnAt = nil
  elseif turn ~= s.mySeat or not s.turnAt then
    s.turnAt = client.env.now()
  end
  s.deadline = type(m.left) == "number" and client.env.now() + m.left or nil
  s:hook("applied", m.seat, m.a)
  s:armAuto()
  Session.emit(client)
end

local function onTick(client, sender, m)
  local s = client.session
  if not s or s.tid ~= m.tid or type(m.q) ~= "number" then return end
  local kind = Succession.authority(s, sender, m.e)
  if kind == "new" then
    Succession.follow(s, sender, m.e)
    s:requestSync()
  elseif kind == "current" and (s.stale or m.q > s.seq) then
    s:requestSync()
  end
end

local function onRefusal(client, sender, m)
  if type(m.why) ~= "string" then return end
  local s, p = client.session, client.pending
  if p and p.tid == m.tid and p.host == sender then
    client.pending = nil
    Session.refuse(client, m.tid, m.why)
  elseif s and s.role ~= "host" and s.tid == m.tid and s.host == sender then
    -- "gone": I am not at its table any more (my seat went without my STD: the
    -- extensions hear of it first, hook `gone`). Stale: the new host did not take me in.
    -- Anything else I can live with, e.g. a watcher asking for a taken chair.
    s.sitAsked = nil
    if m.why == "gone" and s.mySeat then s:hook("gone") end
    if m.why == "gone" or s.stale then Session.leave(client) end
    Session.refuse(client, m.tid, m.why)
  end
end

local function onEnd(client, sender, m)
  local s, p = client.session, client.pending
  if s and s.role ~= "host" and s.tid == m.tid and s.host == sender
      and type(m.e) == "number" and m.e >= s.epoch then
    if s.stake ~= nil then s:hook("ended", sender) end -- while I sit in a running staked game: forged (core/Stakes.lua)
    Session.leave(client)
  elseif p and p.tid == m.tid and p.host == sender then
    client.pending = nil
    Session.refuse(client, m.tid, "gone")
  end
end

-- A sealed table (core/Cash.lua, after every event and snapshot, the host's
-- own seat too): my seat sits out in a live game, I am here, so it is dealt
-- in again from the next hand ({k="back"}), asked once while it stays away
-- (s.backAsked; a snapshot asks again). A seat dealt into the running hand
-- asks once that hand is over: back, it would count again among the hand's
-- players (rule 18), and so in the shuffle reopened without it and in the
-- dealer named (the host refuses such a back, Cash's act hook).
function Member.comeBack(s)
  local st = s.state
  local mine = s.mySeat and st and st.seats[s.mySeat]
  if not (s.status == "live" and type(mine) == "table" and mine.away) then s.backAsked = nil; return end
  if s.backAsked or s:gameOver() or (s:engine().inHand(st) and ns.Util.contains(st.order or {}, s.mySeat)) then return end
  s.backAsked = true
  Session.act(s.client, { k = "back" })
end

Member.handlers = { SNP = onSnapshot, EV = onEvent, TCK = onTick, SNO = onRefusal, END = onEnd }
