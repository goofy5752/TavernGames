local Sim = require("sim")
local ns = Sim.ns
local C, Stakes, Rolls, Util = ns.Const, ns.Stakes, ns.Rolls, ns.Util
local TTT, DR = ns.Engines.ttt, ns.Engines.deathroll

-- И hosts; М and П are guild members.
local A, B, P = "Иван Петров", "Мария Стоянова", "Петър Колев"
local SK = 50000

-- Иван, Мария, Петър, all in one group (a staked Death Roll starts only so).
local function setup()
  local sim = Sim.new()
  local a = sim:add(A, { cls = "MAGE" })
  local b = sim:add(B, { cls = "PRIEST" })
  local c = sim:add(P, { cls = "ROGUE" })
  for _, env in pairs(sim.envs) do env.inGroup = function() return true end end
  sim:run(1)
  return sim, a, b, c
end

-- Every emission of `event` on `client`, as a list of argument lists.
local function record(client, event)
  local list = {}
  client:on(event, function(...) list[#list + 1] = { ... } end)
  return list
end

-- The messages of type `t` from `from` after sim.sent[mark], as sim.sent rows.
local function sent(sim, from, t, mark)
  local out = {}
  for i, s in ipairs(sim.sent) do
    if i > (mark or 0) and s.from == from and s.msg.t == t then out[#out + 1] = s end
  end
  return out
end

-- The EVs `from` whispered to `to` after sim.sent[mark], as sim.sent rows.
local function events(sim, from, mark, to)
  local out = {}
  for _, s in ipairs(sent(sim, from, "EV", mark)) do
    if s.target == to then out[#out + 1] = s end
  end
  return out
end

-- A Морски шах of Иван at stake `sk` (nil: for fun), Мария seated: the match runs, Иван on turn.
local function tttTable(sk)
  local sim, a, b, c = setup()
  local tid = a:openTable{ game = "ttt", access = "guild", turn = 45, stake = sk }; sim:run(3)
  b:sit(tid, 2, sk); sim:run(1)
  return sim, a, b, c, tid
end

-- The same, after Иван's mark on cell 1: Мария on turn.
local function tttMariaOnTurn(sk)
  local sim, a, b, c, tid = tttTable(sk)
  ok(a:act({ k = "mark", c = 1 })); sim:run(0)
  return sim, a, b, c, tid
end

-- Both players of a ttt table play E.auto until the match is over.
local function playOut(sim, host, guest)
  for _ = 1, 200 do
    local s = host.session
    if not s or s:gameOver() then return end
    local seat = s.state and s.state.turn
    if seat == 1 then host:act(TTT.auto(s.state, 1)) elseif seat == 2 then guest:act(TTT.auto(guest.session.state, 2)) end
    sim:run(1)
  end
end

-- A Death Roll of Иван from `start` (default 100) at stake `sk`, with `others`
-- (names) in seats 2.., started: Иван (seat 1) on turn.
local function drTable(others, sk, start)
  local sim, a, b, c = setup()
  local by = { [B] = b, [P] = c }
  local tid = a:openTable{ game = "deathroll", access = "guild", turn = 45, opt = { start = start or 100 }, stake = sk }
  sim:run(3)
  for i, name in ipairs(others) do by[name]:sit(tid, i + 1, sk) end
  sim:run(1)
  ok(a:startGame()); sim:run(0)
  return sim, a, b, c, tid
end

-- `client` rolls n: its server roll, seen by whoever sim.canSee lets.
local function roll(sim, client, n)
  sim.nextRolls = { n }
  ok(client:roll()); sim:run(0)
end

-- Counts the calls of every stakes hook while fn runs.
local HOOKS = { "applied", "forged", "refused", "adopted", "hostChanged", "leaving", "gone" }
local function spied(fn)
  local x, saved, calls = ns.Ext.stakes, {}, {}
  for _, h in ipairs(HOOKS) do
    saved[h] = x[h]
    x[h] = function(...)
      calls[h] = (calls[h] or 0) + 1
      return saved[h](...)
    end
  end
  local done, err = pcall(fn)
  for _, h in ipairs(HOOKS) do x[h] = saved[h] end
  if not done then error(err, 0) end
  return calls
end

describe("stakes: play", function()
  it("Stakes.foul keeps the higher rank", function()
    eq(Stakes.RANK, { forged = 4, roll = 3, deal = 3, dice = 3, stand = 2, unseen = 1 })
    local s = {}
    Stakes.foul(s, "unseen"); eq(s.stakeFoul, "unseen")
    Stakes.foul(s, "roll"); Stakes.foul(s, "stand"); eq(s.stakeFoul, "roll")
    Stakes.foul(s, "forged"); Stakes.foul(s, "unseen"); eq(s.stakeFoul, "forged")
  end)

  it("the hooks of stakes run only at a staked table", function()
    local calls = spied(function() tttMariaOnTurn(SK) end)
    ok((calls.applied or 0) > 0, "no applied hook at a staked table")
    eq(spied(function() tttMariaOnTurn(nil) end), {})
  end)

  it("ttt: a move the host makes for my seat is the foul forged", function()
    for _, stake in ipairs({ SK, false }) do
      local sk = stake or nil
      local calls = spied(function()
        local sim, a, b = tttMariaOnTurn(sk)
        -- Иван's client plays cell 9 for Мария, who sent cell 5.
        sim.bus.filter = function(from, _, _, m)
          if from == B and m.t == "ACT" then m.a = { k = "mark", c = 9 } end
          return { m }
        end
        ok(b:act({ k = "mark", c = 5 })); sim:run(1)
        sim.bus.filter = nil
        eq(b.session.state.board[9], 2); eq(b.session.state.board[5], 0)
        eq(b.session.stakeFoul, sk and "forged" or nil); eq(a.session.stakeFoul, nil)
        if not sk then eq(b.session.stakeLive, nil); eq(b.session.stakeRoster, nil); eq(b.session.stakeTurn, nil) end
      end)
      if not sk then eq(calls, {}) end
    end
  end)

  it("ttt: the host's timeout for my seat is taken only after my own clock ran out", function()
    local sim, a, b = tttMariaOnTurn(SK)
    local mark = #sim.sent
    sim:run(C.TURN_DEFAULT + C.AUTO_GRACE - 1); eq(b.session.state.board[2], 0)
    sim:run(1); eq(b.session.state.board[2], 2); eq(b.session.stakeFoul, nil)
    local ev = events(sim, A, mark, B)
    eq(#ev, 1); eq(ev[1].msg.auto, true); eq(ev[1].msg.seat, 2)
    -- A host that plays it after 10 s.
    sim, a, b = tttMariaOnTurn(SK)
    sim:run(10)
    a.session:play(2, TTT.auto(a.session.state, 2), true); sim:run(0)
    eq(b.session.state.board[2], 2); eq(b.session.stakeFoul, "forged")
  end)

  it("ttt: the host waits AUTO_GRACE before it moves for the other seat, and not for its own", function()
    for _, stake in ipairs({ SK, false }) do
      local sim = tttTable(stake or nil)
      local start, mark = sim.clock, #sim.sent
      sim:run(100)
      local autos = {}
      for _, s in ipairs(events(sim, A, mark, B)) do
        if s.msg.auto then autos[#autos + 1] = { s.msg.seat, s.at - start } end
      end
      eq(autos, stake and { { 1, 45 }, { 2, 97 } } or { { 1, 45 }, { 2, 90 } })
    end
  end)

  it("ttt: an event my engine refuses is forged", function()
    local sim, _, b, _, tid = tttMariaOnTurn(SK)
    local s = b.session
    -- Иван marks again, on the taken cell 1, while Мария is on turn.
    b:receive("WHISPER", A, { v = 1, t = "EV", tid = tid, e = s.epoch, q = s.seq + 1, seat = 1, a = { k = "mark", c = 1 } })
    eq(s.stakeFoul, "forged")
    sim:run(1)
    -- The snapshot it asked for is the very game it holds: the foul stays.
    eq(b.session, s); eq(s.stakeFoul, "forged"); eq(s.seq, sim.clients[A].session.seq)
  end)

  it("ttt: an auto move for my seat while my ACT is unmatched is forged", function()
    local function dropped(at)
      local sim, _, b = tttMariaOnTurn(SK)
      sim.bus.filter = function(from, _, _, m)
        if from == B and m.t == "ACT" then return {} end
        return { m }
      end
      sim:run(at); ok(b:act({ k = "mark", c = 9 }))
      sim:run(C.TURN_DEFAULT + C.AUTO_GRACE - at)
      sim.bus.filter = nil
      eq(b.session.state.board[2], 2); eq(b.session.state.board[9], 0)
      return b.session.stakeFoul
    end
    eq(dropped(10), "forged")
    -- An ACT sent after her own deadline is no move in time: the timeout stands.
    eq(dropped(C.TURN_DEFAULT + 2), nil)
  end)

  it("a snapshot I asked for into a running game is unseen; a pushed one that changes it is forged", function()
    local sim, _, b = tttMariaOnTurn(SK)
    b = sim:relog(B); sim:run(1)
    eq(b.session.mySeat, 2); eq(b.session.stakeLive, true); eq(b.session.stakeFoul, "unseen")
    eq(b.session.stakeRoster, { A, B })
    local a
    sim, a, b = tttMariaOnTurn(SK)
    ok(b:act({ k = "mark", c = 5 })); sim:run(1)
    eq(b.session.stakeFoul, nil)
    -- The same snapshot again changes nothing.
    a.session:snapshotTo(B); sim:run(0); eq(b.session.stakeFoul, nil)
    a.session.state.board[5] = 1 -- Мария's mark becomes Иван's, at the same q
    a.session:snapshotTo(B); sim:run(0)
    eq(b.session.state.board[5], 1); eq(b.session.stakeFoul, "forged")
  end)

  it("an honest takeover is unseen, not forged", function()
    -- Seats: Иван 1, Петър 2, Мария 3. Иван rolls, Петър rolls (the EV of it
    -- does not reach `hold`), Иван goes silent and Петър takes the table over.
    local function takeover(hold, tamper)
      local sim, a, b, c = drTable({ P, B }, SK)
      roll(sim, a, 50)
      sim.bus.filter = function(from, to, _, m)
        if from == A and m.t == "EV" and to == hold then return {} end
        return { m }
      end
      roll(sim, c, 40)
      sim.bus.filter = nil
      sim:offline(A)
      if tamper then tamper(c.session.state) end
      sim:run(C.SILENT_AFTER + 1)
      eq(c.session.role, "host"); eq(b.session.host, P)
      return b.session
    end
    eq(takeover(nil).stakeFoul, nil)  -- the very game Мария holds
    eq(takeover(B).stakeFoul, "unseen") -- Мария missed the last roll: her game is a prefix of Петър's
    eq(takeover(P).stakeFoul, nil) -- Петър missed his own roll: he plays it as he takes over (round 3), the very game she holds
    eq(takeover(B, function(st) st.rolls[1].n = 49 end).stakeFoul, "forged")
  end)

  it("the staked flag comes from what I accepted", function()
    local sim, a, b = drTable({ B }, SK)
    roll(sim, a, 50)
    sim.bus.filter = function(_, to, _, m)
      if to == B and m.t == "SNP" and type(m.st) == "table" then m.st.staked = false end
      return { m }
    end
    b = sim:relog(B); sim:run(1)
    sim.bus.filter = nil
    local s = b.session
    eq(s.mySeat, 2); eq(s.state.staked, true); eq(s.stakeFoul, "forged")
    for _, src in ipairs({ "claim", "ask", "timeout" }) do
      eq({ DR.apply(Util.copy(s.state), 2, { k = "roll", n = 10, max = 50, src = src }) }, { nil, "src" })
    end
    eq(DR.auto(s.state, 2, function() return 1 end), nil)
  end)

  it("the foul is reset when the next game begins", function()
    -- Морски шах: a forged move, the match played out, „Реванш“ from both.
    local sim, a, b = tttMariaOnTurn(SK)
    sim:run(10)
    a.session:play(2, TTT.auto(a.session.state, 2), true); sim:run(0)
    eq(b.session.stakeFoul, "forged")
    playOut(sim, a, b)
    ok(b.session:gameOver()); eq(b.session.stakeFoul, "forged"); eq(b.session.stakeLive, false)
    eq(b.session.stakeRoster, nil)
    ok(a:act({ k = "rematch" })); ok(b:act({ k = "rematch" })); sim:run(1)
    eq(b.session:gameOver(), false); eq(b.session.stakeLive, true); eq(b.session.stakeFoul, nil)
    -- Death Roll: an unseen relog, the game played out, „Нова игра“.
    sim, a, b = drTable({ B }, SK)
    b = sim:relog(B); sim:run(1); eq(b.session.stakeFoul, "unseen")
    roll(sim, a, 1); ok(a.session:gameOver()); eq(b.session.stakeFoul, "unseen")
    sim:run(C.STAKE_BREAK); ok(a:startGame()); sim:run(0)
    eq(b.session.stakeFoul, nil); eq(b.session.stakeRoster, { A, B })
  end)

  it("a foul raised by the event that starts a game counts against the new game", function()
    local sim, a, b = tttTable(SK)
    playOut(sim, a, b)
    ok(b.session:gameOver())
    ok(a:act({ k = "rematch" })); sim:run(0)
    a.session:play(2, { k = "rematch" }); sim:run(0) -- Мария never pressed „Реванш“
    eq(b.session:gameOver(), false); eq(b.session.stakeLive, true)
    eq(b.session.stakeFoul, "forged"); eq(b.session.stakeRoster, { A, B })
  end)

  it("a staked game gets a break", function()
    local sim, a, b = drTable({ B }, SK)
    roll(sim, a, 1); ok(a.session:gameOver())
    eq({ a:startGame() }, { nil, "break" })
    sim:run(C.STAKE_BREAK - 1); eq({ a:startGame() }, { nil, "break" })
    sim:run(1); ok(a:startGame()); sim:run(0)
    eq(b.session.stakeLive, true); eq(b.session.stakeFoul, nil)
    -- A host that starts earlier: Мария's clock says no break was given (AUTO_GRACE left for the transport).
    sim, a, b = drTable({ B }, SK)
    roll(sim, a, 1); sim:run(C.STAKE_BREAK - C.AUTO_GRACE - 1)
    a.session:event(0, { k = "start", first = 1 }); a.session:recordChanged(); sim:run(0)
    eq(b.session.stakeLive, true); eq(b.session.stakeFoul, "forged")
    -- A fun table starts at once, as today.
    sim, a, b = drTable({ B }, nil)
    roll(sim, a, 1); ok(a:startGame()); sim:run(0)
    eq(b.session.state.phase, "play"); eq(b.session.stakeFoul, nil)
    -- Морски шах starts when a sit fills the table (no „Започни“, no break):
    -- a watcher who sits down right after an abort sees no foul.
    local c, tid
    sim, a, b, c, tid = tttMariaOnTurn(SK)
    c:watch(tid); sim:run(1)
    b:stand(); sim:run(0); eq(c.session.status, "aborted")
    c:sit(tid, 2, SK); sim:run(0)
    eq(c.session.mySeat, 2); eq(c.session.stakeLive, true); eq(c.session.stakeFoul, nil)
  end)

  it("the roster is who plays the running game", function()
    local sim, a, b, c, tid = drTable({ B }, SK)
    c:sit(tid, 3, SK); sim:run(1)
    eq(c.session.seats[3], P)
    for _, cl in ipairs({ a, b, c }) do eq(cl.session.stakeRoster, { A, B }) end
  end)

  it("death roll: the host cannot start while a seated player is not in its group", function()
    local sim, a, b = setup()
    a.env.inGroup = function() return false end
    local tid = a:openTable{ game = "deathroll", access = "guild", turn = 45, stake = SK }; sim:run(3)
    b:sit(tid, 2, SK); sim:run(1)
    eq({ a:startGame() }, { nil, "group" })
    a.env.inGroup = function() return true end
    ok(a:startGame())
    -- A fun table starts as today.
    sim, a, b = setup()
    a.env.inGroup = function() return false end
    tid = a:openTable{ game = "deathroll", access = "guild", turn = 45 }; sim:run(3)
    b:sit(tid, 2); sim:run(1)
    ok(a:startGame())
  end)

  it("death roll: a client that cannot /roll gets no staked seat", function()
    local sim, a, _, c = setup()
    local G = "Гошо Гошев"
    local d = sim:add(G, { cls = "MAGE", roll = false }); sim:run(1)
    local tid = a:openTable{ game = "deathroll", access = "guild", turn = 45, stake = SK }; sim:run(3)
    local refused, mark = record(d, "refused"), #sim.sent
    eq({ d:sit(tid, 2, SK) }, { nil, "roll" }); sim:run(1)
    eq(refused, { { tid, "roll" } }); eq(#sent(sim, G, "SIT", mark), 0); eq(d.session, nil)
    -- At a fun table it sits as today.
    local fun = c:openTable{ game = "deathroll", access = "guild", turn = 45 }; sim:run(3)
    d:sit(fun, 2); sim:run(1)
    eq(d.session.mySeat, 2); eq(#refused, 1)
  end)

  it("death roll: only a roll the host saw counts", function()
    local sim, a, b = drTable({ B }, SK)
    roll(sim, a, 50)
    sim.canSee = function(from, to) return not (from == B and to == A) end
    local mark = #sim.sent
    roll(sim, b, 40); sim:run(C.ROLL_CLAIM_WAIT)
    eq(#events(sim, A, mark, B), 0); eq(#a.session.state.rolls, 1)
    eq(#sent(sim, B, "ACT", mark), 0) -- no claim at a staked table
    sim:run(C.ROLL_VERIFY_WAIT)
    sim.canSee = function() return true end
    roll(sim, b, 40)
    local ev = events(sim, A, mark, B)
    eq(#ev, 1); eq(ev[1].msg.a, { k = "roll", n = 40, max = 50, src = "seen" })
  end)

  it("death roll: nobody rolls for a silent seat; 180 s on turn stands it up as idle", function()
    -- Мария on turn and silent: no roll at 45 s, the idle stand at 180 s.
    local sim, a, b, c = drTable({ B, P }, SK)
    roll(sim, a, 50)
    local t0, mark = sim.clock, #sim.sent
    sim:run(C.TURN_DEFAULT + C.AUTO_GRACE + 1); eq(#events(sim, A, mark, P), 0)
    sim:run(C.OFFLINE_STAND_SECONDS - (C.TURN_DEFAULT + C.AUTO_GRACE + 1) - 1); eq(#events(sim, A, mark, P), 0)
    sim:run(1)
    local ev = events(sim, A, mark, P)
    eq(#ev, 1); eq(ev[1].msg.a, { k = "stand", seat = 2, why = "idle" }); eq(ev[1].at - t0, C.OFFLINE_STAND_SECONDS)
    eq(c.session.state.turn, 3); eq(a.session.status, "live")

    -- A roll at 179 s cancels it; the next seat's turn has a full 180 s of its own.
    sim, a, b, c = drTable({ B, P }, SK)
    roll(sim, a, 50)
    t0, mark = sim.clock, #sim.sent
    sim:run(C.OFFLINE_STAND_SECONDS - 1); roll(sim, b, 40)
    sim:run(C.OFFLINE_STAND_SECONDS - 1)
    for _, s in ipairs(events(sim, A, mark, B)) do ok(s.msg.a.k ~= "stand", "a stand before its time") end
    sim:run(1)
    ev = events(sim, A, mark, B)
    eq(ev[#ev].msg.a, { k = "stand", seat = 3, why = "idle" }); eq(ev[#ev].at - t0, 2 * C.OFFLINE_STAND_SECONDS - 1)

    -- It follows a host change: Иван hands over, Петър stands Мария up a fresh 180 s after
    -- his takeover (round 2 follow-up ruling). Seats: Иван 1, Петър 2, Мария 3; Мария on turn.
    sim, a, b, c = drTable({ P, B }, SK)
    roll(sim, a, 50); roll(sim, c, 40)
    sim:run(100); a:stand(); sim:run(1)
    local took = sim.clock
    eq(c.session.role, "host"); eq(c.session.state.turn, 3)
    sim:run(C.OFFLINE_STAND_SECONDS - 1); eq(c.session.seats[3], B)
    sim:run(1); eq(c.session.seats[3], false); eq(sim.clock - took, C.OFFLINE_STAND_SECONDS)

    -- Only a host plays it: a demoted host cancels it ...
    local function stands(from, since)
      local n = 0
      for _, s in ipairs(sent(sim, from, "EV", since)) do
        if s.msg.a.k == "stand" then n = n + 1 end
      end
      return n
    end
    sim, a, b = drTable({ B }, SK)
    roll(sim, a, 50)
    sim:run(100)
    ok(a.session.idleTimer, "no idle timer at the host")
    mark = #sim.sent
    ns.Succession.follow(a.session, B, a.session.epoch + 1) -- Мария's epoch: she claims it, Иван stays a member
    eq(a.session.idleTimer, nil)
    sim:run(C.OFFLINE_STAND_SECONDS); eq(stands(A, mark), 0)
    -- ... and a timer left armed does nothing once I do not host.
    sim, a, b = drTable({ B }, SK)
    roll(sim, a, 50)
    mark = #sim.sent
    ns.Succession.demote(a.session)
    ok(a.session.idleTimer, "demote alone leaves the timer")
    sim:run(C.OFFLINE_STAND_SECONDS + 1); eq(stands(A, mark), 0)
  end)

  it("death roll: the host's own idle seat hands the table over", function()
    local sim, a, b = drTable({ B }, SK)
    local t0, mark, idle = sim.clock, #sim.sent, nil
    local saved = ns.Ext.stakes.leaving
    ns.Ext.stakes.leaving = function(s)
      idle = s.stakeIdle
      return saved(s)
    end
    local done, err = pcall(function()
      sim:run(C.OFFLINE_STAND_SECONDS - 1); eq(a.session.role, "host"); eq(a.session.state.turn, 1)
      sim:run(1)
    end)
    ns.Ext.stakes.leaving = saved
    if not done then error(err, 0) end
    eq(idle, true); eq(a.session, nil); eq(b.session.role, "host")
    local ev = events(sim, A, mark, B)
    eq(ev[1].msg.a, { k = "stand", seat = 1, why = "left" }); eq(ev[1].at - t0, C.OFFLINE_STAND_SECONDS)
  end)

  it("death roll: a staked game played cleanly has no foul", function()
    local sim, a, b, c = drTable({ B, P }, SK)
    local by = { a, b, c }
    for _, n in ipairs({ 90, 80, 70, 60, 50, 40, 30, 20, 10, 1 }) do roll(sim, by[a.session.state.turn], n) end
    ok(a.session:gameOver()); eq(#b.session.state.rolls, 10)
    sim:run(C.ROLL_FINAL_WAIT)
    for _, cl in ipairs(by) do
      eq(cl.session.stakeFoul, nil); eq(Rolls.audit(cl.session), nil)
    end
  end)

  it("death roll: an idle stand after my own roll is the foul roll", function()
    local function idleAfter(rolled)
      local sim, a, b = drTable({ B }, SK)
      roll(sim, a, 50)
      sim.canSee = function(from, to) return not (from == B and to == A) end -- the host never sees her roll
      if rolled then roll(sim, b, 40) end
      local s = b.session
      sim:run(C.OFFLINE_STAND_SECONDS + C.PING_EVERY + 1)
      eq(b.session, nil); eq(a.session.seats[2], false)
      return s
    end
    eq(idleAfter(true).stakeFoul, "roll")
    eq(idleAfter(false).stakeFoul, nil)
  end)

  it("death roll: a roll the host never played clears my rolling flag", function()
    local sim, a, b = drTable({ B }, SK)
    roll(sim, a, 50)
    sim.canSee = function(from, to) return not (from == B and to == A) end
    roll(sim, b, 40); ok(b.session.rolling, "rolling"); eq(b.session.rollUnheard, nil)
    sim:run(C.ROLL_CLAIM_WAIT + C.ROLL_VERIFY_WAIT - 1); ok(b.session.rolling, "still rolling")
    sim:run(1); eq(b.session.rolling, nil); eq(b.session.rollUnheard, true)
    -- The host sees the next one in time: no hint.
    sim.canSee = function() return true end
    roll(sim, b, 40); eq(b.session.rollUnheard, nil)
    sim:run(C.ROLL_CLAIM_WAIT + C.ROLL_VERIFY_WAIT)
    eq(b.session.rollUnheard, nil); eq(b.session.rolling, nil); eq(#b.session.state.rolls, 2)
  end)

  it("a namesake's roll under my seat is the foul roll", function()
    local sim, a, b = drTable({ B }, SK)
    roll(sim, a, 50)
    -- Another Мария of the guild types /roll 50 on Мария's turn: every client sees „Мария“.
    a:rollSeen("Мария", 30, 1, 50); b:rollSeen("Мария", 30, 1, 50); sim:run(0)
    eq(b.session.state.rolls[2], { seat = 2, n = 30, max = 50, src = "seen" }); eq(Rolls.check(b.session, 2), "ok")
    eq(b.session.rolling, nil)
    sim:run(C.ROLL_VERIFY_WAIT)
    eq(Rolls.audit(b.session), "roll"); eq(Rolls.audit(a.session), nil)
  end)

  it("Rolls.audit", function()
    -- Иван's roll seen with another number: "roll".
    local sim, a, b = drTable({ B }, SK)
    sim.canSee = function(from, to) return not (from == A and to == B) end
    b:rollSeen("Иван", 41, 1, 100); roll(sim, a, 40)
    eq(Rolls.audit(b.session), "unseen") -- the verdict is pending: not clean
    sim:run(C.ROLL_VERIFY_WAIT)
    eq(Rolls.check(b.session, 1), "mismatch"); eq(Rolls.audit(b.session), "roll")
    -- Never seen: "unseen"; a later mismatch wins over it.
    sim, a, b = drTable({ B }, SK)
    sim.canSee = function(from, to) return not (from == A and to == B) end
    roll(sim, a, 40); sim:run(C.ROLL_VERIFY_WAIT)
    eq(Rolls.check(b.session, 1), "unseen"); eq(Rolls.audit(b.session), "unseen")
    sim.canSee = function() return true end
    roll(sim, b, 30)
    sim.canSee = function(from, to) return not (from == A and to == B) end
    b:rollSeen("Иван", 21, 1, 30); roll(sim, a, 20); sim:run(C.ROLL_VERIFY_WAIT)
    eq(Rolls.check(b.session, 2), "ok"); eq(Rolls.check(b.session, 3), "mismatch"); eq(Rolls.audit(b.session), "roll")
    -- A game of more than ROLL_LOG rolls keeps its early rolls.
    sim, a, b = drTable({ B }, SK, 1000)
    local hide = true
    sim.canSee = function(from, to) return not (hide and from == A and to == B) end
    local by = { a, b }
    for n = 999, 975, -1 do
      roll(sim, by[a.session.state.turn], n)
      hide = false
    end
    eq(#b.session.state.rolls, 25); eq(#b.session.rollLog, C.ROLL_LOG)
    sim:run(C.ROLL_VERIFY_WAIT)
    eq(Rolls.check(b.session, 1), "unseen"); eq(Rolls.check(b.session, 2), "ok"); eq(Rolls.audit(b.session), "unseen")
    -- Final ROLL_FINAL_WAIT after the result: the last roll's verdict is pending at it.
    sim, a, b = drTable({ B }, SK)
    roll(sim, a, 50)
    sim.canSee = function(from, to) return not (from == A and to == B) end
    roll(sim, b, 30); roll(sim, a, 1)
    ok(b.session:gameOver()); eq(Rolls.audit(b.session), "unseen")
    sim:run(1); b:rollSeen("Иван", 1, 1, 30) -- the line comes late, but in time
    sim:run(C.ROLL_FINAL_WAIT - 2); eq(Rolls.audit(b.session), "unseen")
    sim:run(1); eq(Rolls.audit(b.session), nil)
    ok(C.ROLL_FINAL_WAIT >= C.ROLL_VERIFY_WAIT)
  end)

  it("a stand of my own seat while my client runs is the foul stand, unless idle and my clock agrees", function()
    -- Мария on turn; Иван's client stands her up `after` s later (nil: its own idle timer).
    local function stoodUp(why, after)
      local sim, a, b = drTable({ B }, SK)
      roll(sim, a, 50)
      local s = b.session
      if after then
        sim:run(after)
        ns.Succession.untrack(a.session, B) -- as the host's own stands do
        a.session:event(0, { k = "stand", seat = 2, why = why }); a.session:abortIfShort(); a.session:recordChanged()
      end
      sim:run(C.OFFLINE_STAND_SECONDS + C.PING_EVERY + 1)
      eq(b.session, nil) -- her host's SNO "gone" ended her session
      return s
    end
    eq(stoodUp("offline", 10).stakeFoul, "stand")
    eq(stoodUp(nil, nil).stakeFoul, nil) -- idle at 180 s by her clock
    eq(stoodUp("idle", 60).stakeFoul, "stand")
    -- A stand of my seat that reaches me as an event is judged by its why.
    local function told(why, after)
      local sim, a, b, _, tid = drTable({ B, P }, SK)
      roll(sim, a, 50)
      a.session.idleTimer.cancel() -- this host plays its stands by hand
      sim:run(after)
      local s = b.session
      b:receive("WHISPER", A, { v = 1, t = "EV", tid = tid, e = s.epoch, q = s.seq + 1, seat = 0,
                                a = { k = "stand", seat = 2, why = why } })
      eq(s.seats[2], false)
      return s.stakeFoul
    end
    eq(told("offline", 10), "stand"); eq(told("left", 10), "stand")
    eq(told("idle", C.OFFLINE_STAND_SECONDS), nil); eq(told("idle", 60), "stand")
  end)
end)

describe("stakes: play, fix round 1", function()
  it("the host whispers a stand to the player it stood up, who judges it once", function()
    local sim, a, b, c = drTable({ B, P }, SK)
    roll(sim, a, 50)
    local mark, s = #sim.sent, b.session
    sim:run(C.OFFLINE_STAND_SECONDS)
    local ev = events(sim, A, mark, B)
    eq(#ev, 1); eq(ev[1].msg.a, { k = "stand", seat = 2, why = "idle" }); eq(ev[1].msg.q, s.seq)
    eq(s.seats[2], false); eq(s.stakeFoul, nil)
    -- Her next PNG gets SNO "gone": the stand is not judged a second time.
    sim:run(C.PING_EVERY + 1); eq(b.session, nil); eq(s.stakeFoul, nil)
    -- A leave is not told: its player asked for it.
    mark = #sim.sent
    c:stand(); sim:run(1)
    eq(#events(sim, A, mark, P), 0); eq(a.session.seats[3], false)
  end)

  it("a start no honest host plays is forged, and counts against the game it starts", function()
    -- Морски шах once the match is over, without „Реванш“ from me.
    local sim, a, b = tttTable(SK)
    playOut(sim, a, b); ok(b.session:gameOver())
    a.session:event(0, { k = "start" }); sim:run(0)
    eq(b.session.stakeLive, true); eq(b.session.stakeFoul, "forged"); eq(b.session.stakeRoster, { A, B })
    -- Морски шах in the middle of a match.
    sim, a, b = tttMariaOnTurn(SK)
    a.session:event(0, { k = "start" }); sim:run(0)
    eq(b.session.state.board[1], 0); eq(b.session.stakeFoul, "forged")
    -- Death Roll while a game runs: a new game with its own roster, the foul against it.
    local c, tid
    sim, a, b, c, tid = drTable({ B }, SK)
    roll(sim, a, 50)
    c:sit(tid, 3, SK); sim:run(1); eq(b.session.stakeRoster, { A, B })
    a.session:event(0, { k = "start", first = 2 }); sim:run(0)
    eq(#b.session.state.rolls, 0); eq(b.session.stakeFoul, "forged"); eq(b.session.stakeRoster, { A, B, P })
  end)

  it("a roll verdict still pending when my session ends or the game is replaced is never clean", function()
    -- A final roll for Мария's seat that no chat ever showed, then at once SNO "gone".
    local sim, a, b, _, tid = drTable({ B }, SK)
    roll(sim, a, 50)
    a.session:play(2, { k = "roll", n = 1, max = 50, src = "seen" }); sim:run(0)
    local gid = tid .. "/" .. a.session.seq
    ok(b.session:gameOver()); eq(Rolls.audit(Rolls.auditOf(b, gid)), "unseen") -- pending: not clean
    a:send("WHISPER", B, { v = 1, t = "SNO", tid = tid, why = "gone" }); sim:run(0)
    eq(b.session, nil)
    sim:run(C.ROLL_FINAL_WAIT)
    eq(Rolls.audit(Rolls.auditOf(b, gid)), "roll")
    -- The same, and the host starts the next game at once.
    sim, a, b, _, tid = drTable({ B }, SK)
    roll(sim, a, 50)
    a.session:play(2, { k = "roll", n = 1, max = 50, src = "seen" }); sim:run(0)
    gid = tid .. "/" .. a.session.seq
    a.session:event(0, { k = "start", first = 1 }); sim:run(0)
    eq(#b.session.state.rolls, 0)
    sim:run(C.ROLL_FINAL_WAIT)
    eq(Rolls.audit(Rolls.auditOf(b, gid)), "roll"); eq(Rolls.audit(b.session), nil)
    -- A roll my log confirmed late but before I stood up keeps its "ok" (round 2, M4: no honest host framed).
    sim, a, b, _, tid = drTable({ B }, SK)
    roll(sim, a, 50); roll(sim, b, 30)
    sim.canSee = function(from, to) return not (from == A and to == B) end
    roll(sim, a, 1); gid = tid .. "/" .. a.session.seq
    sim:run(1); b:rollSeen("Иван", 1, 1, 30); eq(Rolls.check(b.session, 3), "ok")
    b:stand(); eq(Rolls.audit(Rolls.auditOf(b, gid)), "unseen") -- still pending: not clean
    sim:run(C.ROLL_FINAL_WAIT)
    eq(Rolls.check(Rolls.auditOf(b, gid), 3), "ok"); eq(Rolls.audit(Rolls.auditOf(b, gid)), nil)
    -- One without any verdict when I stood up has its final verdict: "unseen".
    sim, a, b, _, tid = drTable({ B }, SK)
    roll(sim, a, 50); roll(sim, b, 30)
    sim.canSee = function(from, to) return not (from == A and to == B) end
    roll(sim, a, 1); gid = tid .. "/" .. a.session.seq
    b:stand(); sim:run(C.ROLL_FINAL_WAIT)
    eq(Rolls.check(Rolls.auditOf(b, gid), 3), "unseen"); eq(Rolls.audit(Rolls.auditOf(b, gid)), "unseen")
  end)

  it("no snapshot clears or lowers the foul of the game that ran", function()
    -- Морски шах: a forged move, then Иван rewrites the board and makes Мария ask (a TCK one ahead).
    local sim, a, b, _, tid = tttMariaOnTurn(SK)
    sim:run(10); a.session:play(2, TTT.auto(a.session.state, 2), true); sim:run(0)
    eq(b.session.stakeFoul, "forged")
    local st = a.session.state
    st.board[1], st.board[3] = 0, 1
    a.session.seq = a.session.seq + 1
    a:send("WHISPER", B, { v = 1, t = "TCK", tid = tid, e = a.session.epoch, q = a.session.seq }); sim:run(1)
    eq(b.session.state.board[3], 1); eq(b.session.stakeFoul, "forged")
    -- Death Roll: a roll under my seat that I did not make, then an asked snapshot of another game.
    sim, a, b, _, tid = drTable({ B }, SK)
    roll(sim, a, 50)
    a:rollSeen("Мария", 30, 1, 50); sim:run(0); sim:run(C.ROLL_VERIFY_WAIT)
    eq(Rolls.audit(b.session), "roll"); eq(b.session.stakeFoul, nil)
    a.session.state = a.session:newGame(1); a.session.seq = a.session.seq + 1
    a:send("WHISPER", B, { v = 1, t = "TCK", tid = tid, e = a.session.epoch, q = a.session.seq }); sim:run(1)
    -- The replaced game's record stays with the running one (round 2: no side table).
    eq(#b.session.state.rolls, 0); eq(b.session.stakeFoul, "unseen"); eq(Rolls.audit(b.session), "roll")
  end)

  it("the break leaves AUTO_GRACE for the transport; a snapshot dates its end by its arrival", function()
    -- Иван's final roll reaches Мария a second late; he starts the next game at once when allowed.
    local sim, a, b, _, tid = drTable({ B }, SK)
    local held = {}
    sim.bus.filter = function(from, to, _, m)
      if from == A and to == B and m.t == "EV" then held[#held + 1] = m; return {} end
      return { m }
    end
    roll(sim, a, 1); sim.bus.filter = nil
    sim:run(1)
    for _, m in ipairs(held) do sim.bus:send(A, "WHISPER", B, m) end
    sim:run(0); ok(b.session:gameOver())
    sim:run(C.STAKE_BREAK - 1); ok(a:startGame()); sim:run(0)
    eq(b.session.stakeLive, true); eq(b.session.stakeFoul, nil)
    -- The end comes by an asked snapshot: dated when it reached me; a start inside my
    -- break from then is a question, never forged (the host's own break may be over: Ruling F2-F, C2).
    sim, a, b, _, tid = drTable({ B }, SK)
    sim.bus.filter = function(from, to, _, m)
      if from == A and to == B and m.t == "EV" then return {} end
      return { m }
    end
    roll(sim, a, 1); sim.bus.filter = nil
    a:send("WHISPER", B, { v = 1, t = "TCK", tid = tid, e = a.session.epoch, q = a.session.seq }); sim:run(1)
    ok(b.session:gameOver()); eq(b.session.stakeLive, false)
    ok(b.session.stakeEndedAt and b.session.stakeEndedAt > sim.clock - 1.5, "dated at the snapshot's arrival"); eq(b.session.stakeEndSnap, true)
    a.session:event(0, { k = "start", first = 1 }); sim:run(0)
    eq(b.session.stakeLive, true); eq(b.session.stakeFoul, "unseen")
  end)

  it("death roll: my roll outside the host's group is no foul; another host drops my roll and says roll again", function()
    local sim, a, b = drTable({ B }, SK)
    roll(sim, a, 50)
    b.env.inGroup = function() return false end
    sim.canSee = function(from, to) return not (from == B and to == A) end
    eq(Rolls.withHost(b.session), false)
    roll(sim, b, 40); eq(b.session.myRoll, nil)
    local s = b.session
    sim:run(C.OFFLINE_STAND_SECONDS + C.PING_EVERY + 1)
    eq(b.session, nil); eq(s.stakeFoul, nil)
    -- In the group it counts; another host does not hold it (round 2 follow-up; the same host's new epoch keeps it).
    sim, a, b = drTable({ B }, SK)
    roll(sim, a, 50)
    sim.canSee = function(from, to) return not (from == B and to == A) end
    eq(Rolls.withHost(b.session), true)
    roll(sim, b, 40); eq(b.session.myRoll, { n = 40, max = 50, i = 2 })
    b.session.host = P; b.session:hook("hostChanged") -- round 3: the roll stays with its turn, Петър is not charged with it
    eq(b.session.myRoll, { n = 40, max = 50, i = 2, pass = P }); eq(b.session.rollUnheard, true)
  end)

  it("a watcher without /roll whose lobby lost the table still gets no staked seat", function()
    local sim, a = setup()
    local G = "Гошо Гошев"
    local d = sim:add(G, { cls = "MAGE", roll = false }); sim:run(1)
    local tid = a:openTable{ game = "deathroll", access = "guild", turn = 45, stake = SK }; sim:run(3)
    d:watch(tid); sim:run(1); eq(d.session.tid, tid)
    d.lobby:remove(tid)
    local mark = #sim.sent
    eq({ d:sit(tid, 2, SK) }, { nil, "roll" }); eq(#sent(sim, G, "SIT", mark), 0)
  end)

  it("Морски шах: a board that carries mine on is the same game (F21)", function()
    local L = Stakes.leadsTo
    local mine = TTT.new({})
    ok(TTT.apply(mine, 1, { k = "mark", c = 1 }))
    local more = Util.copy(mine); ok(TTT.apply(more, 2, { k = "mark", c = 5 }))
    ok(L(mine, more)); ok(L(mine, mine)); ok(not L(more, mine))
    local other = Util.copy(more); other.board[1] = 2
    ok(not L(mine, other))
    -- Round 1 won by seat 1, then the next round.
    local won = TTT.new({})
    for _, m in ipairs({ { 1, 1 }, { 2, 4 }, { 1, 2 }, { 2, 5 }, { 1, 3 } }) do ok(TTT.apply(won, m[1], { k = "mark", c = m[2] })) end
    eq(won.phase, "round")
    local nextRound = Util.copy(won); ok(TTT.apply(nextRound, 0, { k = "next" }))
    ok(L(won, nextRound)); ok(not L(nextRound, won))
    local later = Util.copy(nextRound); later.round = 3
    ok(not L(won, later))
    ok(L(mine, nextRound)) -- round 1 still running leads to round 2 by legal play (fix round 4, I2): its end is unseen
  end)
end)

describe("stakes: play, fix round 2", function()
  it("Морски шах: an abort with both seats full, then a start, is forged against that game", function()
    local sim, a, b = tttTable(SK)
    playOut(sim, a, b); ok(b.session:gameOver())
    a.session:event(0, { k = "abort" }); sim:run(0); eq(b.session.status, "aborted")
    a.session:event(0, { k = "start" }); sim:run(0)
    eq(b.session.stakeLive, true); eq(b.session.stakeFoul, "forged")
    -- A seat my client saw empty and filled again by a sit: the start is the table's.
    local c, tid
    sim, a, b, c, tid = tttMariaOnTurn(SK)
    c:watch(tid); sim:run(1)
    b:stand(); sim:run(0)
    local d = sim:add("Гошо Гошев", { cls = "MAGE" }); sim:run(1)
    d:sit(tid, 2, SK); sim:run(1)
    eq(c.session.stakeLive, true); eq(c.session.stakeFoul, nil); eq(d.session.stakeFoul, nil)
  end)

  it("the grouping check is my own roster's, never the host's announced GUID", function()
    local sim, a, b = drTable({ B }, SK)
    roll(sim, a, 50)
    b.presence.peers[A].guid = "Player-0000-99999999" -- what a host may announce about itself
    eq(Rolls.withHost(b.session), true)
    b.presence.peers[A].guid = nil
    eq(Rolls.withHost(b.session), true)
    sim.canSee = function(from, to) return not (from == B and to == A) end
    roll(sim, b, 40); eq(b.session.myRoll, { n = 40, max = 50, i = 2 })
    -- Outside my roster's group it is false, whatever the host announces.
    b.presence.peers[A].guid = b.env.guid
    b.env.groupedWith = function() return false end
    eq(Rolls.withHost(b.session), false)
  end)

  it("the same host at a new epoch is no host change: my roll stays and its idle stand is the foul roll", function()
    local sim, a, b, _, tid = drTable({ B }, SK)
    roll(sim, a, 50)
    sim.canSee = function(from, to) return not (from == B and to == A) end
    roll(sim, b, 40); eq(b.session.myRoll, { n = 40, max = 50, i = 2 })
    a.session.epoch = a.session.epoch + 1
    a:send("WHISPER", B, { v = 1, t = "TCK", tid = tid, e = a.session.epoch, q = a.session.seq }); sim:run(1)
    eq(b.session.epoch, a.session.epoch); eq(b.session.myRoll, { n = 40, max = 50, i = 2 }); eq(b.session.stakeFoul, nil)
    ok(b.session.rolling, "the roll under way is not dropped by the same host's new epoch")
    local s = b.session
    sim:run(C.OFFLINE_STAND_SECONDS)
    eq(s.seats[2], false); eq(s.stakeFoul, "roll")
  end)

  it("a snapshot that does for my seat what I did not is forged", function()
    -- Морски шах: a mark of mine I never sent, brought by a snapshot I was made to ask for.
    local sim, a, b, _, tid = tttMariaOnTurn(SK)
    local function ask()
      a.session.seq = a.session.seq + 1
      a:send("WHISPER", B, { v = 1, t = "TCK", tid = tid, e = a.session.epoch, q = a.session.seq }); sim:run(1)
    end
    ok(TTT.apply(a.session.state, 2, { k = "mark", c = 7 })); ask()
    eq(b.session.state.board[7], 2); eq(b.session.stakeFoul, "forged")
    -- My own mark, sent and dropped on the way back, then brought by a snapshot: no foul.
    sim, a, b, _, tid = tttMariaOnTurn(SK)
    sim.bus.filter = function(from, to, _, m)
      if from == A and to == B and m.t == "EV" then return {} end
      return { m }
    end
    ok(b:act({ k = "mark", c = 7 })); sim:run(1); sim.bus.filter = nil
    a:send("WHISPER", B, { v = 1, t = "TCK", tid = tid, e = a.session.epoch, q = a.session.seq }); sim:run(1)
    eq(b.session.state.board[7], 2); eq(b.session.stakeFoul, "unseen")
    -- My timeout, due by my clock and missed on the way: no foul either.
    sim, a, b, _, tid = tttMariaOnTurn(SK)
    sim.bus.filter = function(from, to, _, m)
      if from == A and to == B and m.t == "EV" then return {} end
      return { m }
    end
    sim:run(C.TURN_DEFAULT + C.AUTO_GRACE); sim.bus.filter = nil
    a:send("WHISPER", B, { v = 1, t = "TCK", tid = tid, e = a.session.epoch, q = a.session.seq }); sim:run(1)
    eq(b.session.state.board[2], 2); eq(b.session.stakeFoul, "unseen")
    -- A new match without my „Реванш“.
    sim, a, b, _, tid = tttTable(SK)
    playOut(sim, a, b); ok(b.session:gameOver())
    sim.bus.filter = function(from, to, _, m)
      if from == A and to == B and m.t == "EV" then return {} end
      return { m }
    end
    ok(a:act({ k = "rematch" })); a.session:play(2, { k = "rematch" }); sim:run(0); sim.bus.filter = nil
    a:send("WHISPER", B, { v = 1, t = "TCK", tid = tid, e = a.session.epoch, q = a.session.seq }); sim:run(1)
    eq(b.session:gameOver(), false); eq(b.session.stakeFoul, "forged")
    -- Death Roll: a roll of mine no chat ever showed.
    sim, a, b, _, tid = drTable({ B }, SK)
    roll(sim, a, 50)
    ok(DR.apply(a.session.state, 2, { k = "roll", n = 20, max = 50, src = "seen" })); ask()
    eq(#b.session.state.rolls, 2); eq(b.session.stakeFoul, "forged")
    -- Death Roll: my seat gone at 60 s, in a snapshot I asked for; at 180 s by my clock it is the idle stand.
    -- (Its EV and the SNO "gone" to my SYN are lost on the way: only the snapshot tells me.)
    for _, at in ipairs({ 60, C.OFFLINE_STAND_SECONDS }) do
      sim, a, b, _, tid = drTable({ B }, SK)
      roll(sim, a, 50)
      a.session.idleTimer.cancel()
      sim.bus.filter = function(from, to, _, m)
        if from == A and to == B and (m.t == "EV" or m.t == "SNO") then return {} end
        return { m }
      end
      sim:run(at)
      ns.Succession.untrack(a.session, B)
      a.session:event(0, { k = "stand", seat = 2, why = "idle" }); sim:run(0)
      local s = b.session
      s.lastSyn = nil; s:requestSync(); sim:run(0); sim.bus.filter = nil
      a.session:snapshotTo(B); sim:run(0)
      eq(s.stakeFoul, at == 60 and "forged" or "unseen")
    end
  end)

  it("a verdict pending when a snapshot replaces my game updates that game's record", function()
    local sim, a, b, _, tid = drTable({ B }, SK)
    roll(sim, a, 50)
    a.session:play(2, { k = "roll", n = 20, max = 50, src = "seen" }); sim:run(0) -- no chat line of mine
    a.session.state = a.session:newGame(1); a.session.seq = a.session.seq + 1
    a:send("WHISPER", B, { v = 1, t = "TCK", tid = tid, e = a.session.epoch, q = a.session.seq }); sim:run(1)
    eq(#b.session.state.rolls, 0); eq(Rolls.audit(b.session), "unseen") -- pending reads unseen ...
    sim:run(C.ROLL_VERIFY_WAIT)
    eq(Rolls.audit(b.session), "roll") -- ... until its verdict replaces it
  end)

  it("a game a stand ends keeps its roll record", function()
    local sim, a, b, _, tid = drTable({ B }, SK)
    sim.canSee = function(from, to) return not (from == A and to == B) end
    roll(sim, a, 50) -- Мария never sees it: pending
    ns.Succession.untrack(a.session, B)
    a.session:event(0, { k = "stand", seat = 2, why = "offline" }); sim:run(0)
    local gid = tid .. "/" .. a.session.seq
    ok(Rolls.auditOf(b, gid), "no record for the game the stand ended")
    sim:run(C.ROLL_FINAL_WAIT)
    eq(Rolls.audit(Rolls.auditOf(b, gid)), "unseen")
  end)

  it("a /reload on my turn: an honest idle stand is unseen, not stand", function()
    local sim, a, b = drTable({ B }, SK)
    roll(sim, a, 50)
    sim:run(100)
    b = sim:relog(B); sim:run(1)
    eq(b.session.stakeFoul, "unseen"); eq(b.session.stakeTurn.seen, false)
    local s = b.session
    sim:run(C.OFFLINE_STAND_SECONDS - 101)
    eq(s.seats[2], false); eq(s.stakeFoul, "unseen")
  end)
end)

describe("stakes: play, fix round 2 follow-up", function()
  it("my roll to a host that crashes is not held against the new host: a fresh 180 s, no roll foul", function()
    -- Seats: Иван 1 (host), Петър 2, Мария 3. Мария rolls on her turn; Иван never sees it and crashes.
    local sim, a, b, c = drTable({ P, B }, SK)
    roll(sim, a, 50); roll(sim, c, 40)
    sim.canSee = function(from, to) return not (from == B and to == A) end
    roll(sim, b, 30); eq(b.session.myRoll, { n = 30, max = 40, i = 3 })
    local t0 = sim.clock
    sim:offline(A)
    sim:run(C.SILENT_AFTER + 1)
    eq(c.session.role, "host"); eq(b.session.host, P)
    local took = sim.clock
    eq(b.session.myRoll, { n = 30, max = 40, i = 3, pass = P }); eq(b.session.rollUnheard, true) -- kept with its turn (round 3); the UI says: roll again
    local s = b.session
    -- No stand at the old turn's 180 s, but a fresh 180 s after the takeover.
    sim:run(t0 + C.OFFLINE_STAND_SECONDS + 1 - sim.clock); eq(s.seats[3], B)
    sim:run(took + C.OFFLINE_STAND_SECONDS - sim.clock); eq(s.seats[3], false)
    eq(s.stakeFoul, nil)
  end)
end)

describe("stakes: play, fix round 3 (structural)", function()
  -- Иван makes Мария ask for a snapshot: a TCK at q (default: his own seq).
  local function tick(sim, a, tid, q)
    a:send("WHISPER", B, { v = 1, t = "TCK", tid = tid, e = a.session.epoch, q = q or a.session.seq }); sim:run(1)
  end

  local function holdEvents(sim)
    sim.bus.filter = function(from, to, _, m)
      if from == A and to == B and m.t == "EV" then return {} end
      return { m }
    end
  end

  it("(a) my turn clock is mine: a snapshot's left never dates a timeout of my seat", function()
    -- The very game I hold, sent again with left = 0, then the host's instant "timeout" for my seat.
    local sim, a, b, _, tid = tttMariaOnTurn(SK)
    sim:run(5)
    local at = b.session.turnAt
    sim.bus.filter = function(from, to, _, m)
      if from == A and to == B and m.t == "SNP" then m.left = 0 end
      return { m }
    end
    tick(sim, a, tid, a.session.seq + 1); sim.bus.filter = nil
    eq(b.session.stakeFoul, nil); eq(b.session.turnAt, at)
    a.session:play(2, TTT.auto(a.session.state, 2), true); sim:run(0)
    eq(b.session.state.board[2], 2); eq(b.session.stakeFoul, "forged")
    -- The same snapshot from an honest host changes nothing: its timeout at my own deadline is clean.
    sim, a, b, _, tid = tttMariaOnTurn(SK)
    sim:run(20); tick(sim, a, tid, a.session.seq + 1)
    sim:run(C.TURN_DEFAULT + C.AUTO_GRACE - 21)
    eq(b.session.state.board[2], 2); eq(b.session.stakeFoul, nil)
    -- A turn a snapshot brought (its EV was held) runs from my receipt of it: a timeout at once is forged.
    sim, a, b, _, tid = tttTable(SK)
    holdEvents(sim)
    ok(a:act({ k = "mark", c = 1 })); sim:run(0); sim.bus.filter = nil
    sim:run(10); tick(sim, a, tid)
    eq(b.session.state.turn, 2); eq(b.session.turnAt, sim.clock); eq(b.session.stakeFoul, "unseen")
    a.session:play(2, TTT.auto(a.session.state, 2), true); sim:run(0)
    eq(b.session.state.board[2], 2); eq(b.session.stakeFoul, "forged")
    -- After my own /reload no clock of mine saw the turn begin: the honest timeout is a question, not forged.
    sim, a, b = tttMariaOnTurn(SK)
    sim:run(30); b = sim:relog(B); sim:run(1)
    eq(b.session.stakeFoul, "unseen")
    sim:run(C.TURN_DEFAULT + C.AUTO_GRACE - 31)
    eq(b.session.state.board[2], 2); eq(b.session.stakeFoul, "unseen")
  end)

  it("(a) my turn length is the table's I accepted: a snapshot with another is forged, never my clock (review C1)", function()
    local function tn1(sim)
      sim.bus.filter = function(from, to, _, m)
        if from == A and to == B and m.t == "SNP" then m.tbl = Util.copy(m.tbl); m.tbl.tn = 1 end
        return { m }
      end
    end
    local sim, a, b, _, tid = tttMariaOnTurn(SK)
    tn1(sim); tick(sim, a, tid, a.session.seq + 1); sim.bus.filter = nil
    eq(b.session.turn, 45); eq(b.session.stakeFoul, "forged")
    sim:run(2)
    eq(ns.Member.timedOut(b.session, { auto = true, seat = 2, a = TTT.auto(b.session.state, 2) }), false)
    -- My stake note keeps it through a /reload.
    sim, a, b, _, tid = tttMariaOnTurn(SK)
    b = sim:relog(B); sim:run(1)
    tn1(sim); tick(sim, a, tid, a.session.seq + 1); sim.bus.filter = nil
    eq(b.session.turn, 45); eq(b.session.stakeFoul, "forged")
    -- A fun table takes the host's word, as before.
    sim, a, b, _, tid = tttMariaOnTurn(nil)
    tn1(sim); tick(sim, a, tid, a.session.seq + 1); sim.bus.filter = nil
    eq(b.session.turn, 1); eq(b.session.stakeFoul, nil)
  end)

  it("(b) my roll is tied to its turn: a host that bounces the table away and back is charged with it", function()
    local sim, a, b, _, tid = drTable({ B }, SK)
    roll(sim, a, 50)
    sim.canSee = function(from, to) return not (from == B and to == A) end
    roll(sim, b, 40); eq(b.session.myRoll, { n = 40, max = 50, i = 2 })
    local e, s = a.session.epoch, b.session
    -- HND to a third name, then Иван takes the table back two epochs later.
    a:send("WHISPER", B, { v = 1, t = "HND", tid = tid, e = e + 1, to = "Хикс Хиксов" }); sim:run(0)
    eq(s.host, "Хикс Хиксов"); eq(s.myRoll, { n = 40, max = 50, i = 2, pass = "Хикс Хиксов" }); eq(s.rollUnheard, true)
    local restarted = s.stakeTurn.at
    sim:run(3)
    a.session.epoch = e + 2
    tick(sim, a, tid)
    eq(s.host, A); eq(s.epoch, e + 2); eq(s.stale, nil)
    eq(s.myRoll, { n = 40, max = 50, i = 2, pass = false }); eq(s.stakeTurn.at, restarted) -- no second fresh clock
    sim:run(C.OFFLINE_STAND_SECONDS)
    eq(s.seats[2], false); eq(s.stakeFoul, "roll")
  end)

  it("(b) the first other host is not charged with a roll the old one never answered, once; I play my own when I take over", function()
    local sim, a, b = drTable({ B }, SK)
    roll(sim, a, 50)
    sim.canSee = function(from, to) return not (from == B and to == A) end
    roll(sim, b, 40)
    local s = b.session
    s.host = P; s:hook("hostChanged")
    eq(s.myRoll.pass, P); eq(s.rollUnheard, true); eq(s.rolling, nil)
    local at = s.stakeTurn.at
    sim:run(5); s.host = A; s:hook("hostChanged")
    eq(s.myRoll.pass, false); eq(s.stakeTurn.at, at)
    -- Without a roll of mine every other host gives the turn a fresh clock.
    sim, a, b = drTable({ B }, SK)
    roll(sim, a, 50)
    s = b.session
    sim:run(5); s.host = P; s:hook("hostChanged"); eq(s.stakeTurn.at, sim.clock)
    sim:run(5); s.host = A; s:hook("hostChanged"); eq(s.stakeTurn.at, sim.clock)
    -- The host crashes over my roll and the table is mine: my client plays the roll it saw itself make.
    sim, a, b = drTable({ B }, SK)
    roll(sim, a, 50)
    sim.canSee = function(from, to) return not (from == B and to == A) end
    roll(sim, b, 40)
    sim:offline(A); sim:run(C.SILENT_AFTER + 1)
    eq(b.session.role, "host"); eq(b.session.state.rolls[2], { seat = 2, n = 40, max = 50, src = "seen" })
    eq(b.session.myRoll, nil); eq(b.session.rollUnheard, nil); eq(b.session.state.turn, 1)
  end)

  it("(c) an idle stand needs my own clock, however the turn reached me", function()
    -- The EV that put Мария on turn is held; a snapshot she is made to ask for brings the turn.
    local function early(after)
      local sim, a, b, _, tid = drTable({ B }, SK)
      holdEvents(sim)
      roll(sim, a, 50); sim.bus.filter = nil
      a.session.idleTimer.cancel() -- this host plays its stands by hand
      tick(sim, a, tid)
      local s = b.session
      eq(s.state.turn, 2); eq(s.stakeFoul, "unseen"); eq(s.stakeTurn.at, sim.clock)
      sim:run(after)
      ns.Succession.untrack(a.session, B)
      a.session:event(0, { k = "stand", seat = 2, why = "idle" }); sim:run(0)
      eq(s.seats[2], false)
      return s.stakeFoul
    end
    eq(early(10), "stand")
    eq(early(C.OFFLINE_STAND_SECONDS - C.AUTO_GRACE - 1), "stand")
    eq(early(C.OFFLINE_STAND_SECONDS - C.AUTO_GRACE), "unseen") -- 180 − AUTO_GRACE by my clock: only the ask stays
    -- A snapshot that carries the game on to a later turn of mine starts that turn's clock afresh.
    local sim, a, b, _, tid = drTable({ B }, SK)
    roll(sim, a, 90); sim:run(170)
    holdEvents(sim)
    roll(sim, b, 80); roll(sim, a, 70); sim.bus.filter = nil
    a.session.idleTimer.cancel()
    tick(sim, a, tid)
    local s = b.session
    eq(#s.state.rolls, 3); eq(s.state.turn, 2); eq(s.stakeTurn.at, sim.clock)
    sim:run(20)
    ns.Succession.untrack(a.session, B)
    a.session:event(0, { k = "stand", seat = 2, why = "idle" }); sim:run(0)
    eq(s.stakeFoul, "stand")
    -- After another host my late-started clock disagrees but the turn's first clock agrees: a question (M1).
    local function afterChange(at)
      local sim, a, b, _, tid = drTable({ B, P }, SK)
      roll(sim, a, 50)
      local s = b.session
      sim:run(100); s.host = P; s:hook("hostChanged")
      eq(s.stakeTurn.at, sim.clock); eq(s.stakeTurn.was, sim.clock - 100)
      -- Иван is gone: nothing of his reaches her any more, and Петър is heard.
      sim.bus.filter = function(from, to, _, m) return (from == A and to == B) and {} or { m } end
      for _ = 1, at - 100 do sim:run(1); ns.Succession.watchHost(s) end
      b:receive("WHISPER", P, { v = 1, t = "EV", tid = tid, e = s.epoch, q = s.seq + 1, seat = 0,
                                a = { k = "stand", seat = 2, why = "idle" } })
      eq(s.seats[2], false)
      return s.stakeFoul
    end
    eq(afterChange(120), "stand"); eq(afterChange(C.OFFLINE_STAND_SECONDS), "unseen")
    eq(afterChange(100 + C.OFFLINE_STAND_SECONDS), nil)
  end)

  it("(d) a snapshot of another game is checked against what I sent", function()
    -- Морски шах: an abort with both seats full, then a new match by a snapshot I am made to ask for.
    local sim, a, b, _, tid = tttTable(SK)
    playOut(sim, a, b); ok(b.session:gameOver())
    a.session:event(0, { k = "abort" }); sim:run(0); eq(b.session.status, "aborted")
    a.session.state, a.session.status, a.session.seq = a.session:newGame(1), "live", a.session.seq + 1
    tick(sim, a, tid)
    eq(b.session.stakeLive, true); eq(b.session.state.round, 1); eq(b.session.stakeFoul, "forged")
    -- Морски шах: a „Реванш“ in my name while the match is over, then the host's own: the new match is not clean.
    sim, a, b = tttTable(SK)
    playOut(sim, a, b); ok(b.session:gameOver())
    a.session:play(2, { k = "rematch" }); sim:run(0)
    ok(a:act({ k = "rematch" })); sim:run(0)
    eq(b.session.stakeLive, true); eq(b.session.stakeFoul, "forged")
    -- My own „Реванш“ and my own sit are in my log: no foul.
    sim, a, b = tttTable(SK)
    eq(b.session.stakeFoul, nil); eq(b.session.stakeLog[1].k, "sit")
    playOut(sim, a, b)
    ok(b:act({ k = "rematch" })); ok(a:act({ k = "rematch" })); sim:run(1)
    eq(b.session.stakeLive, true); eq(b.session.stakeFoul, nil)
    -- Death Roll: a snapshot of another game with a roll in my name, judged before my sightings go.
    sim, a, b, _, tid = drTable({ B }, SK)
    roll(sim, a, 50)
    local st = a.session:newGame(2)
    ok(DR.apply(st, 2, { k = "roll", n = 20, max = 100, src = "seen" }))
    a.session.state, a.session.seq = st, a.session.seq + 1
    tick(sim, a, tid)
    eq(#b.session.state.rolls, 1); eq(b.session.state.turn, 1); eq(b.session.stakeFoul, "forged")
    -- ... and one that replays a roll I did make, already counted for my game.
    sim, a, b, _, tid = drTable({ B }, SK, 100)
    roll(sim, a, 100); roll(sim, b, 60)
    st = a.session:newGame(2)
    ok(DR.apply(st, 2, { k = "roll", n = 60, max = 100, src = "seen" }))
    a.session.state, a.session.seq = st, a.session.seq + 1
    tick(sim, a, tid)
    eq(b.session.state.max, 60); eq(#b.session.state.rolls, 1); eq(b.session.stakeFoul, "forged")
    -- A hand-typed roll of mine in a game whose start I missed is mine: only the ask stays.
    sim, a, b, _, tid = drTable({ B }, SK)
    roll(sim, a, 50)
    a.session.state, a.session.seq = a.session:newGame(2), a.session.seq + 1
    holdEvents(sim)
    a:rollSeen("Мария", 20, 1, 100); b:rollSeen(B, 20, 1, 100); sim:run(0); sim.bus.filter = nil
    eq(#a.session.state.rolls, 1)
    tick(sim, a, tid)
    eq(#b.session.state.rolls, 1); eq(b.session.stakeFoul, "unseen")
  end)

  it("no host makes a login of a running client: a session it ended is not seated again", function()
    -- Only a login brings a turn my clock cannot judge (stakeTurn.seen false). A host that ends
    -- my session finds my stake note gone with it (core/Stake.lua): its snapshot is refused.
    local sim, a, b, _, tid = drTable({ B }, SK)
    roll(sim, a, 50)
    a.session.idleTimer.cancel()
    sim:run(10)
    local s, mark = b.session, #sim.sent
    a:send("WHISPER", B, { v = 1, t = "SNO", tid = tid, why = "gone" }); sim:run(0)
    eq(b.session, nil); eq(s.stakeFoul, "stand")
    a.session:snapshotTo(B); sim:run(0)
    eq(b.session, nil); ok(#sent(sim, B, "STD", mark) >= 1, "the seat is not refused")
  end)
end)

describe("stakes: play, fix round 4", function()
  local function tick(sim, a, tid, q)
    a:send("WHISPER", B, { v = 1, t = "TCK", tid = tid, e = a.session.epoch, q = q or a.session.seq }); sim:run(1)
  end

  -- Иван's EVs to Мария (and with `acts` Мария's ACTs) are lost while this holds.
  local function hold(sim, acts)
    sim.bus.filter = function(from, to, _, m)
      if (from == A and to == B and m.t == "EV") or (acts and from == B and m.t == "ACT") then return {} end
      return { m }
    end
  end

  -- A snapshot of Иван to Мария says twice the stake while this holds.
  local function otherStake(sim)
    sim.bus.filter = function(from, to, _, m)
      if from == A and to == B and m.t == "SNP" then m.tbl.sk = 2 * SK end
      return { m }
    end
  end

  -- Иван takes round 1 with the cells 1, 2, 3 (Мария: 4, 5), but for his last mark.
  local function roundOne(sim, a, b)
    for _, c in ipairs({ 1, 4, 2, 5 }) do
      ok((c < 3 and a or b):act({ k = "mark", c = c })); sim:run(1)
    end
  end

  it("C1: an END from my host while I sit in a running staked game is forged, noted beyond my session", function()
    local sim, a, b, _, tid = drTable({ B }, SK)
    roll(sim, a, 50)
    local s, q = b.session, b.session.seq
    a:send("WHISPER", B, { v = 1, t = "END", tid = tid, e = a.session.epoch }); sim:run(0)
    eq(b.session, nil); eq(s.stakeFoul, "forged")
    local note = b.env.db.stakeSeen[tid .. "/" .. q]
    eq({ note.foul, note.open, note.sk, note.tid, note.q, note.g }, { "forged", true, SK, tid, q, "deathroll" })
    -- Outside a running game an END is what it was: I leave, nothing is noted.
    sim, a, b, _, tid = tttTable(SK)
    playOut(sim, a, b); ok(b.session:gameOver())
    a:send("WHISPER", B, { v = 1, t = "END", tid = tid, e = a.session.epoch }); sim:run(0)
    eq(b.session, nil); for _, n in pairs(b.env.db.stakeSeen) do eq(n.open, nil) end -- only the match's own outcome note (Task 8)
    -- A fun table: nothing of it.
    eq(spied(function()
      sim, a, b, _, tid = tttMariaOnTurn(nil)
      a:send("WHISPER", B, { v = 1, t = "END", tid = tid, e = a.session.epoch }); sim:run(0)
    end), {})
    eq(b.session, nil); eq(b.env.db.stakeSeen, nil)
  end)

  it("C1: a snapshot at another stake while I sit in a running staked game is forged, and I give up no seat", function()
    local sim, a, b, _, tid = drTable({ B }, SK)
    roll(sim, a, 50)
    local s, q, mark = b.session, b.session.seq, #sim.sent
    local refused = record(b, "refused")
    otherStake(sim); a.session:snapshotTo(B); sim:run(0); sim.bus.filter = nil
    eq(b.session, nil); eq(refused, { { tid, "stake" } }); eq(s.stakeFoul, "forged")
    eq(#sent(sim, B, "STD", mark), 0); eq(a.session.seats[2], B)
    local note = b.env.db.stakeSeen[tid .. "/" .. q]
    eq({ note.foul, note.open, note.sk }, { "forged", true, SK })
    -- No game runs: the seat is given up as before, and nothing is noted.
    sim, a, b, _, tid = tttTable(SK)
    playOut(sim, a, b); mark = #sim.sent
    otherStake(sim); a.session:snapshotTo(B); sim:run(0); sim.bus.filter = nil
    eq(b.session, nil); eq(#sent(sim, B, "STD", mark), 1); for _, n in pairs(b.env.db.stakeSeen) do eq(n.open, nil) end -- only the outcome note (Task 8)
  end)

  it("I1: what I sent outlives a /reload: my „Реванш“, then the host's, is no forged match (unseen: the breaker fix)", function()
    local sim, a, b, _, tid = tttTable(SK)
    playOut(sim, a, b); ok(b.session:gameOver())
    ok(b:act({ k = "rematch" })); sim:run(1)
    eq(b.env.db.stakeLog.tid, tid); eq(b.env.db.stakeLog.no, 1)
    b = sim:relog(B); sim:run(1)
    eq(b.session.mySeat, 2); eq(b.session.stakeNo, 1)
    eq(b.session.stakeLog[#b.session.stakeLog].k, "rematch")
    ok(a:act({ k = "rematch" })); sim:run(1)
    eq(b.session.stakeLive, true); eq(b.session.stakeFoul, "unseen"); eq(b.env.db.stakeLog.no, 2)
    -- The log goes with my stake note.
    b:stand(); sim:run(0)
    eq(b.env.db.stakeSat, nil); eq(b.env.db.stakeLog, nil)
    -- A log of another table is not mine here.
    sim, a, b, _, tid = tttTable(SK)
    playOut(sim, a, b)
    b.env.db.stakeLog = { tid = "x#1", no = 1, log = { { k = "rematch", g = 1 } } }
    b = sim:relog(B); sim:run(1)
    a.session:play(2, { k = "rematch" }); ok(a:act({ k = "rematch" })); sim:run(1)
    eq(b.session.stakeLive, true); eq(b.session.stakeFoul, "forged")
  end)

  it("I2: a lost round-ending event is the same game: unseen, never forged; a mark in my name still needs my log", function()
    local sim, a, b = tttTable(SK)
    roundOne(sim, a, b)
    hold(sim); ok(a:act({ k = "mark", c = 3 })); sim:run(0); sim.bus.filter = nil
    eq(b.session.state.phase, "play")
    sim:run(5) -- the host's `next` shows the gap: I ask
    eq(b.session.state.round, 2); eq(b.session.state.score, { 1, 0 })
    eq(b.session.stakeFoul, "unseen"); eq(b.session.stakeNo, 1)
    -- I play on in round 2: my own marks are mine.
    ok(b:act({ k = "mark", c = 9 })); sim:run(1)
    eq(a.session.state.board[9], 2); eq(b.session.stakeFoul, "unseen")
    -- The same loss, and the host marks for me in the round I never saw begin.
    local tid
    sim, a, b, _, tid = tttTable(SK)
    roundOne(sim, a, b)
    hold(sim); ok(a:act({ k = "mark", c = 3 })); sim:run(4)
    eq(a.session.state.round, 2); eq(a.session.state.turn, 2)
    a.session:play(2, { k = "mark", c = 7 }); sim:run(0); sim.bus.filter = nil
    tick(sim, a, tid)
    eq(b.session.state.board[7], 2); eq(b.session.stakeFoul, "forged")
  end)

  it("I2: only what no legal play reaches is another game", function()
    local function st(over)
      local t = TTT.new()
      for k, v in pairs(over or {}) do t[k] = v end
      if t.phase ~= "play" then t.turn = nil end
      return t
    end
    local lead = Stakes.leadsTo
    local mid = st({ board = { 1, 1, 0, 2, 2, 0, 0, 0, 0 } })
    ok(lead(mid, mid)); ok(lead(st(), mid)); ok(not lead(mid, st()))
    -- The round's end, the next round, a later one: each within what the rounds between can score.
    ok(lead(mid, st({ board = { 1, 1, 1, 2, 2, 0, 0, 0, 0 }, phase = "round", score = { 1, 0 } })))
    ok(lead(mid, st({ round = 2, first = 2, turn = 2, score = { 1, 0 } })))
    ok(lead(mid, st({ round = 2, first = 2, turn = 2, score = { 0, 1 } })))
    ok(lead(mid, st({ round = 2, first = 2, turn = 2 })), "a draw")
    ok(lead(mid, st({ round = 3, score = { 1, 1 } })))
    ok(not lead(mid, st({ round = 2, first = 2, turn = 2, score = { 1, 1 } })), "two points in one round")
    ok(not lead(mid, st({ round = 2, first = 2, turn = 2, score = { 2, 0 } })))
    ok(not lead(mid, st({ round = 2, score = { 1, 0 } })), "the wrong seat begins")
    ok(not lead(st({ round = 2, first = 2, turn = 2, score = { 1, 0 } }), st({ round = 3, score = { 0, 1 } })), "a score went down")
    -- A round already decided adds nothing more; a match that is over goes nowhere.
    local won = st({ board = { 1, 1, 1, 2, 2, 0, 0, 0, 0 }, phase = "round", score = { 1, 0 } })
    ok(lead(won, st({ round = 2, first = 2, turn = 2, score = { 1, 0 } })))
    ok(not lead(won, st({ round = 2, first = 2, turn = 2, score = { 2, 0 } })))
    ok(not lead(won, st({ board = { 1, 1, 1, 2, 2, 2, 0, 0, 0 }, phase = "round", score = { 1, 0 } })))
    local over = st({ board = { 1, 1, 1, 2, 2, 0, 0, 0, 0 }, phase = "match", score = { 3, 0 }, round = 3, winner = 1 })
    ok(lead(over, over)); ok(not lead(over, st({ round = 4, first = 2, turn = 2, score = { 3, 0 } })))
    local two = st({ board = { 1, 1, 0, 2, 2, 0, 0, 0, 0 }, score = { 2, 0 }, round = 3 })
    ok(lead(two, over)); over.winner = 2; ok(not lead(two, over), "the winner is the seat with the points"); over.winner = 1
    -- Marks no play makes: three more of one seat, a cell changed, a point that is not the line's.
    ok(not lead(mid, st({ board = { 1, 1, 0, 2, 2, 0, 1, 1, 1 } })))
    ok(not lead(mid, st({ board = { 1, 2, 0, 2, 2, 0, 1, 0, 0 } })))
    ok(not lead(mid, st({ board = { 1, 1, 1, 2, 2, 0, 0, 0, 0 }, phase = "round", score = { 0, 1 } })))
  end)

  it("I2: a changed host's honest prefix of my match is unseen, my own marks in it are no foul", function()
    local sim, a, b = tttTable(SK)
    for _, c in ipairs({ 1, 5, 2 }) do
      ok((c < 3 and a or b):act({ k = "mark", c = c })); sim:run(1)
    end
    eq(b.session.state.board, { 1, 1, 0, 0, 2, 0, 0, 0, 0 }); eq(b.session.stakeFoul, nil)
    -- The host at a new epoch, one mark behind me.
    local s = a.session
    s.state.board[2], s.state.turn, s.epoch = 0, 1, s.epoch + 1
    s:snapshotTo(B); sim:run(0)
    eq(b.session.epoch, s.epoch); eq(b.session.state.board, { 1, 0, 0, 0, 2, 0, 0, 0, 0 })
    eq(b.session.stakeFoul, "unseen"); eq(b.session.stakeNo, 1)
    -- A "prefix" with a mark in my name that my match never had is none: forged.
    sim, a, b = tttTable(SK)
    for _, c in ipairs({ 1, 5, 2 }) do
      ok((c < 3 and a or b):act({ k = "mark", c = c })); sim:run(1)
    end
    s = a.session
    s.state.board, s.state.turn, s.epoch = { 1, 0, 0, 0, 0, 0, 0, 0, 2 }, 1, s.epoch + 1
    s:snapshotTo(B); sim:run(0)
    eq(b.session.state.board[9], 2); eq(b.session.stakeFoul, "forged")
  end)

  it("M1: a seat the host stood, taken again by my own sit before I was told to go, is a sit", function()
    local sim, a, b, _, tid = tttMariaOnTurn(SK)
    a.session:event(0, { k = "stand", seat = 2, why = "offline" }); a.session:abortIfShort(); sim:run(0)
    eq(b.session.seats[2], false); eq(b.session.mySeat, 2); eq(b.session.stakeFoul, "stand")
    b:sit(tid, 2, SK); sim:run(1)
    eq(a.session.seats[2], B); eq(b.session.stakeLive, true); eq(b.session.stakeNo, 2)
    eq(b.session.stakeFoul, nil)
  end)

  it("M2: after a login on my turn the honest timeout is unseen by a snapshot as by an event", function()
    local sim, a, b, _, tid = tttMariaOnTurn(SK)
    sim:run(30); b = sim:relog(B); sim:run(1)
    eq(b.session.stakeFoul, "unseen")
    hold(sim, true)
    sim:run(C.TURN_DEFAULT + C.AUTO_GRACE - 31); sim.bus.filter = nil
    eq(a.session.state.board[2], 2); eq(b.session.state.board[2], 0)
    tick(sim, a, tid)
    eq(b.session.state.board[2], 2); eq(b.session.stakeFoul, "unseen")
    -- Any other mark in my name on that turn is forged.
    sim, a, b, _, tid = tttMariaOnTurn(SK)
    sim:run(30); b = sim:relog(B); sim:run(1)
    hold(sim, true)
    a.session:play(2, { k = "mark", c = 9 }); sim:run(0); sim.bus.filter = nil
    tick(sim, a, tid)
    eq(b.session.state.board[9], 2); eq(b.session.stakeFoul, "forged")
  end)
end)

describe("stakes: play, fix round 5", function()
  -- Round 1: Иван 1, Мария 2 by the host's timeout, Иван 4, Мария 5,
  -- Иван 7 and the round; then round 2, Мария's mark on 9.
  local function intoRoundTwo()
    local sim, a, b = tttMariaOnTurn(SK)
    sim:run(C.TURN_DEFAULT + C.AUTO_GRACE)
    eq(b.session.state.board[2], 2); eq(b.session.stakeFoul, nil)
    ok(a:act({ k = "mark", c = 4 })); sim:run(1)
    ok(b:act({ k = "mark", c = 5 })); sim:run(1)
    ok(a:act({ k = "mark", c = 7 })); sim:run(4)
    eq(b.session.state.round, 2); eq(b.session.state.score, { 1, 0 })
    ok(b:act({ k = "mark", c = 9 })); sim:run(1)
    eq(b.session.stakeFoul, nil)
    return sim, a, b
  end

  -- Иван, at a new epoch, sends round 1 again as it stood before his last mark, with `board`.
  local function backToRoundOne(sim, a, board)
    local s, st = a.session, TTT.new()
    st.board = board
    s.state, s.epoch = st, s.epoch + 1
    s:snapshotTo(B); sim:run(0)
  end

  it("I1: an earlier round sent again is checked against what I sent: a mark I never made is forged", function()
    -- The honest one: my own mark and the timeout my client took for mine.
    local sim, a, b = intoRoundTwo()
    backToRoundOne(sim, a, { 1, 2, 0, 1, 2, 0, 0, 0, 0 })
    eq(b.session.state.round, 1); eq(b.session.stakeFoul, "unseen"); eq(b.session.stakeNo, 1)
    -- A mark in my name that I never sent, in the round I had left.
    sim, a, b = intoRoundTwo()
    backToRoundOne(sim, a, { 1, 2, 0, 1, 0, 0, 0, 2, 0 })
    eq(b.session.state.board[8], 2); eq(b.session.stakeFoul, "forged")
  end)

  it("I2: a log a crash brought back is in doubt: the honest „Реванш“ after mine is unseen, not forged", function()
    local sim, a, b = tttTable(SK)
    playOut(sim, a, b); ok(b.session:gameOver())
    b:stop(); b = sim:relog(B); sim:run(1) -- a /reload: saved
    eq(b.session.stakeDoubt, nil)
    ok(b:act({ k = "rematch" })); sim:run(1)
    b = sim:crash(B); sim:run(1) -- the log of the /reload comes back, without my „Реванш“
    eq(b.session.mySeat, 2); eq(b.session.stakeDoubt, true)
    ok(a:act({ k = "rematch" })); sim:run(1)
    eq(b.session.stakeLive, true); eq(b.session.stakeFoul, "unseen"); eq(b.session.stakeDoubt, nil)
    -- The same with a /reload in place of the crash: saved, so no doubt, but an entry of an
    -- earlier session never makes a start clean (the breaker fix).
    sim, a, b = tttTable(SK)
    playOut(sim, a, b)
    b:stop(); b = sim:relog(B); sim:run(1)
    ok(b:act({ k = "rematch" })); sim:run(1)
    b:stop(); b = sim:relog(B); sim:run(1)
    eq(b.session.stakeDoubt, nil)
    ok(a:act({ k = "rematch" })); sim:run(1)
    eq(b.session.stakeLive, true); eq(b.session.stakeFoul, "unseen")
    -- In doubt, my own „Реванш“ of this run is mine: clean.
    sim, a, b = tttTable(SK)
    playOut(sim, a, b)
    b:stop(); b = sim:relog(B); sim:run(1)
    ok(b:act({ k = "rematch" })); sim:run(1)
    b = sim:crash(B); sim:run(1)
    eq(b.session.stakeDoubt, true)
    ok(b:act({ k = "rematch" })); ok(a:act({ k = "rematch" })); sim:run(1)
    eq(b.session.stakeLive, true); eq(b.session.stakeFoul, nil)
  end)

  it("I2: a stale „Реванш“ a crash brought back never makes a match I did not agree to clean", function()
    local sim, a, b = tttTable(SK)
    playOut(sim, a, b)
    ok(b:act({ k = "rematch" })); sim:run(1)
    b:stop(); b = sim:relog(B); sim:run(1) -- saved: my „Реванш“ of match 1
    eq(b.session.stakeDoubt, nil)
    ok(a:act({ k = "rematch" })); sim:run(1)
    eq(b.session.stakeLive, true); eq(b.session.stakeFoul, "unseen"); eq(b.session.stakeNo, 2)
    playOut(sim, a, b); ok(b.session:gameOver())
    -- The host's „Реванш“ in my name is on the table when I come back: only the game the log was saved at tells.
    a.session:play(2, { k = "rematch" }); sim:run(0)
    b = sim:crash(B); sim:run(1)
    eq(b.session.state.rematch[2], true); eq(b.session.stakeNo, 1); eq(b.session.stakeDoubt, true)
    ok(a:act({ k = "rematch" })); sim:run(1)
    eq(b.session.stakeLive, true); eq(b.session.stakeFoul, "unseen")
    -- After a /reload the log is current: the same „Реванш“ in my name is forged.
    sim, a, b = tttTable(SK)
    playOut(sim, a, b)
    b:stop(); b = sim:relog(B); sim:run(1)
    a.session:play(2, { k = "rematch" }); ok(a:act({ k = "rematch" })); sim:run(1)
    eq(b.session.stakeLive, true); eq(b.session.stakeFoul, "forged")
  end)

  it("minors: a saved log that is no log is not taken; the note names who ended my game; first and winner are compared", function()
    local sim, a, b, _, tid = tttTable(SK)
    playOut(sim, a, b)
    b.env.db.stakeLog = { tid = tid, no = "1", log = 7 }
    b = sim:relog(B); sim:run(1)
    eq(b.session.stakeLog, nil); eq(b.session.stakeNo, nil)
    sim, a, b, _, tid = drTable({ B }, SK)
    roll(sim, a, 50)
    local q = b.session.seq
    a:send("WHISPER", B, { v = 1, t = "END", tid = tid, e = a.session.epoch }); sim:run(0)
    eq(b.env.db.stakeSeen[tid .. "/" .. q].h, A)
    local mid = TTT.new(); mid.board = { 1, 1, 0, 2, 2, 0, 0, 0, 0 }
    local won = TTT.new()
    won.board, won.round, won.first, won.turn, won.phase, won.score = { 1, 1, 0, 2, 2, 2, 0, 0, 0 }, 2, 2, nil, "round", { 0, 1 }
    ok(Stakes.leadsTo(mid, won))
    won.first = 1; ok(not Stakes.leadsTo(mid, won)); won.first = 2
    won.winner = 1; ok(not Stakes.leadsTo(mid, won))
  end)
end)

describe("stakes: play, breaker fix", function()
  it("a „Реванш“ of an earlier session never makes a start clean: the host replays the state my log was saved at", function()
    local sim, a, b = tttTable(SK)
    playOut(sim, a, b)
    ok(b:act({ k = "rematch" })); sim:run(1)
    local saved = Util.copy(a.session.state) -- match 1 over, with my „Реванш“
    eq(saved.rematch, { false, true })
    b:stop(); b = sim:relog(B); sim:run(1) -- a /reload: the disk holds my „Реванш“ of match 1
    ok(a:act({ k = "rematch" })); sim:run(1)
    eq(b.session.stakeLive, true); eq(b.session.stakeNo, 2)
    playOut(sim, a, b); ok(b.session:gameOver())
    -- I crash; the host answers my login with match 1 as it stood, then presses its own „Реванш“.
    a.session.state = Util.copy(saved)
    b = sim:crash(B); sim:run(1)
    eq(b.session.state.rematch, { false, true }); eq(b.session.stakeNo, 1); eq(b.session.stakeDoubt, nil)
    ok(a:act({ k = "rematch" })); sim:run(1)
    eq(b.session.stakeLive, true); eq(b.session.stakeFoul, "unseen")
    -- My own „Реванш“ of this session is sure, whatever the disk held.
    sim, a, b = tttTable(SK)
    playOut(sim, a, b)
    b:stop(); b = sim:relog(B); sim:run(1)
    ok(b:act({ k = "rematch" })); ok(a:act({ k = "rematch" })); sim:run(1)
    eq(b.session.stakeLive, true); eq(b.session.stakeFoul, nil)
  end)
end)
