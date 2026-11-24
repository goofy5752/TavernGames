-- The chess clock at a table (core/Clock.lua): dt beside the action, the flag
-- timer, the claim, the staked audit of the host; the other games untouched.
local Sim = require("sim")
local Play = require("play")
local Chess = require("chess")
local ns = Sim.ns
local C, Session, Util = ns.Const, ns.Session, ns.Util
local sq = Chess.sq

local H, G, M = Play.NAMES[1], Play.NAMES[2], Play.NAMES[3] -- host (seat 1, black in game 1), guest (seat 2, white)
local SK = 50000

-- A chess table of `minutes` (nil: the default) at stake sk, the guest seated:
-- the game runs, the guest (white) on turn since the start. before(sim, cl)
-- runs before the table opens; n: clients in the guild (default 2).
local function open(minutes, sk, before, n)
  local sim, cl = Play.guild(n or 2)
  if before then before(sim, cl) end
  local host, guest = cl[H], cl[G]
  local tid = assert(host:openTable{ game = "chess", access = "guild", turn = 45, opt = { clock = minutes }, stake = sk })
  sim:run(3)
  guest:sit(tid, 2, sk); sim:run(1)
  assert(host.session.status == "live", "the game is not live")
  return sim, host, guest, cl
end

local function move(w) return { k = "move", f = sq(w:sub(1, 2)), t = sq(w:sub(3, 4)) } end

-- The EVs host sent (to `to`, when given) after sim.sent[mark], their messages.
local function evs(sim, mark, to)
  local out = {}
  for i, r in ipairs(sim.sent) do
    if i > (mark or 0) and r.from == H and r.msg.t == "EV" and (not to or r.target == to) then out[#out + 1] = r.msg end
  end
  return out
end

-- The last EV the host sent whose action is of kind k.
local function lastEv(sim, k)
  local list = evs(sim, 0, G)
  for i = #list, 1, -1 do if type(list[i].a) == "table" and list[i].a.k == k then return list[i] end end
  return nil
end

-- Wraps name's env.send: f(msg) -> msg (changed or not), or nil to drop it.
local function tamper(sim, name, f)
  local env = sim.envs[name]
  local send = env.send
  env.send = function(channel, target, msg, done)
    local m = f(Util.copy(msg))
    if m then return send(channel, target, m, done) end
  end
end

-- The host's own flag never goes (a host that ignores its time).
local function noOwnFlag(host)
  host.session.play = function(self, seat, a, auto)
    if seat == self.mySeat and a.k == "flag" then return end
    return Session.play(self, seat, a, auto)
  end
end

local function over(client, winner, reason)
  local st = client.session.state
  eq(st.phase, "over")
  eq(st.result.winner, winner)
  eq(st.result.reason, reason)
end

describe("chess at the table", function()
  it("the guest plays white in the first game", function()
    local sim, host, guest = open()
    eq(host.session.state.white, 2)
    eq(host.session.state.turn, 2)
    eq(guest.session.state.white, 2)
    local s2, cl2 = Play.guild(2)
    Play.open(s2, cl2, "ttt", nil, 2)
    eq(cl2[H].session.state.turn, 1)
  end)

  it("a first game the host starts also gives white to the guest", function()
    -- A chess the host starts (engine.start "host"): Session.startGame has no state to take nextFirst from.
    ns.Engines.chesshost = setmetatable({ id = "chesshost", start = "host" }, { __index = ns.Engines.chess })
    local sim, cl = Play.guild(2)
    local host = cl[H]
    local tid = assert(host:openTable{ game = "chesshost", access = "guild", turn = 45 })
    sim:run(3)
    cl[G]:sit(tid, 2); sim:run(1)
    eq(host.session.state, nil)
    ok(host:startGame()); sim:run(0)
    eq(host.session.state.white, 2)
    eq(cl[G].session.state.turn, 2)
    ns.Engines.chesshost = nil
  end)

  it("dt travels beside the action", function()
    local sim, host, guest = open()
    sim:run(12)
    ok(guest:act(move("e2e4"))); sim:run(0)
    local ev = lastEv(sim, "move")
    eq(ev.dt, 120)
    eq(ev.a, { k = "move", f = 13, t = 29 })
    eq(host.session.state.clock[2], 6000 - 120 + 50)
    eq(guest.session.state.clock[2], 6000 - 120 + 50)
    eq(host.session.state.moves[1].dt, 120)
    ok(host:act{ k = "resign" }); sim:run(0)
    local rv = lastEv(sim, "resign")
    ok(rv ~= nil and rv.dt == nil, "a resign carries no dt")
    local s2, cl2 = Play.guild(2)
    Play.open(s2, cl2, "ttt", nil, 2)
    ok(cl2[H]:act{ k = "mark", c = 1 }); s2:run(0)
    local n = 0
    for _, r in ipairs(s2.sent) do
      if r.msg.t == "EV" then n = n + 1; ok(r.msg.dt == nil, "a Морски шах EV has no dt") end
    end
    ok(n > 0)
  end)

  it("no timer without a limit", function()
    local sim, host, guest = open(0)
    eq(host.session.deadline, nil)
    eq(host.session.state.clock, nil)
    sim:run(4000)
    eq(host.session.state.phase, "play")
    ok(guest:act(move("e2e4"))); sim:run(0)
    eq(lastEv(sim, "move").dt, nil)
    eq(host.session.deadline, nil)
  end)

  it("the host flags a silent guest after the grace", function()
    local sim, host, guest = open(5)
    sim:run(300 + C.AUTO_GRACE - 1)
    eq(host.session.state.phase, "play")
    sim:run(2)
    over(host, 1, "flag")
    over(guest, 1, "flag")
    eq(lastEv(sim, "flag").auto, true)
  end)

  it("the host flags itself with no grace", function()
    local sim, host, guest = open(5)
    ok(guest:act(move("e2e4"))); sim:run(0)
    sim:run(299)
    eq(host.session.state.phase, "play")
    sim:run(1)
    over(host, 2, "flag")
    over(guest, 2, "flag")
  end)

  it("a late move loses to the flag", function()
    local held
    local sim, host, guest = open(5, nil, function(sim)
      tamper(sim, G, function(m)
        if m.t == "ACT" and m.a.k == "move" then held = m; return nil end
        return m
      end)
    end)
    sim:run(299)
    ok(guest:act(move("e2e4"))); sim:run(0) -- in time by the guest's clock; the ACT is held up
    sim:run(2)
    sim.bus:send(G, "WHISPER", H, held) -- it reaches the host at 301 s
    sim:run(0)
    eq(#host.session.state.moves, 0)
    eq(host.session.state.phase, "play")
    sim:run(C.AUTO_GRACE)
    over(host, 1, "flag")
    eq(#host.session.state.moves, 0)
    eq(guest.session.state, host.session.state)
  end)

  it("a draw offer does not restart the measurement", function()
    local sim, host, guest = open()
    sim:run(10)
    ok(guest:act{ k = "offer" }); sim:run(10)
    ok(guest:act(move("e2e4"))); sim:run(0)
    eq(lastEv(sim, "move").dt, 200)
    eq(host.session.state.clock[2], 6000 - 200 + 50)
  end)

  -- OFFLINE_STAND_SECONDS (180) stands the silent host up before a 10-minute
  -- deadline could come; a 5-minute game with the host gone after 200 s
  -- reaches the flag first.
  it("a new host keeps the clock running", function()
    local sim, host, guest, cl = open(5, nil, nil, 3)
    local t0 = sim.clock
    sim:run(200)
    sim:offline(H)
    local hosted
    for _ = 1, 99 do
      if guest.session.role == "host" then hosted = sim.clock; break end
      sim:run(1)
    end
    ok(hosted, "the guest took the table over")
    local wait = hosted - t0 - 200
    local left = ns.Clock.left(guest.session, 2)
    ok(math.abs(left - (3000 - 2000 - wait * 10)) <= 10, "left " .. tostring(left))
    eq(guest.session.deadline, t0 + 300)
    sim:run(t0 + 299 - sim.clock)
    eq(guest.session.state.phase, "play")
    sim:run(1)
    over(guest, 1, "flag")
    -- The table goes on under the new host: the old host stood up, another sits in its seat.
    for _ = 1, 400 do
      if guest.session.seats[1] == false then break end
      sim:run(1)
    end
    eq(guest.session.seats[1], false)
    cl[M]:sit(guest.session.tid, 1); sim:run(1)
    eq(guest.session.seats[1], M)
    eq(guest.session.status, "live") -- the full table starts the next game by itself
    eq(#guest.session.state.moves, 0)
    eq(guest.session.state.white, 1) -- E.nextFirst: the seat that played black
    eq(guest.session.state.turn, 1)
    eq(cl[M].session.state.white, 1)
  end)

  it("a snapshot is a gift to the seat on turn", function()
    local sim, host, guest = open()
    ok(guest:act(move("e2e4"))); sim:run(0)
    sim:run(100)
    eq(ns.Clock.left(guest.session, 1), 6000 - 1000)
    local again = sim:relog(G); sim:run(0)
    local s = again.session
    ok(s and s.state, "the snapshot came")
    eq(#s.state.moves, 1)
    eq(ns.Clock.left(s, 1), 6000)
    eq(s.clockSeen, false)
    eq(ns.Clock.left(host.session, 1), 6000 - 1000)
  end)

  describe("staked", function()
    -- Advances the sim by `sec` seconds in tenths.
    local function wait(sim, sec)
      local t0 = sim.clock
      for i = 1, math.floor(sec * 10 + 0.5) do
        sim.clock = t0 + i / 10
        sim:drain()
      end
    end

    -- The seat on turn plays a legal move from its own client (a fixed choice).
    local function play(sim, host, guest, ply)
      local s = host.session
      local c = s.state.turn == 1 and host or guest
      local list = ns.Engines.chess.legal(c.session.state, c.session.mySeat)
      ok(c:act(list[1 + (ply * 7) % #list]))
    end

    -- Every message both ways 0.4 s late (the plan's 0.8 s each way is left to
    -- the in-game follow-up: 16 tenths a move, 320 after 20 of mine, over the
    -- 200 of tolerance(20); a round trip over about 1 s is charged in a long game).
    it("an honest host under lag is not charged", function()
      local function lag(sim, name)
        local env = sim.envs[name]
        local send = env.send
        env.send = function(channel, target, msg, done)
          local m = Util.copy(msg)
          env.after(0.4 - 1e-9, function() send(channel, target, m, done) end) -- a hair less: on time for the steps of a tenth
        end
      end
      local sim, host, guest = open(30, SK, function(sim) lag(sim, H); lag(sim, G) end)
      wait(sim, 1)
      local played, ply = {}, 0
      for _ = 1, 4000 do
        if ply >= 40 or host.session.state.phase ~= "play" then break end
        for _, c in ipairs({ host, guest }) do
          local s = c.session
          local st = s.state
          if st.phase == "play" and st.turn == s.mySeat and s.clockAt and not played[#st.moves]
              and sim.clock - s.clockAt >= 5 - 1e-6 then
            played[#st.moves] = true
            local list = ns.Engines.chess.legal(st, s.mySeat)
            ok(c:act(list[1 + (ply * 7) % #list]))
            ply = ply + 1
          end
        end
        wait(sim, 0.1)
      end
      wait(sim, 2)
      eq(#host.session.state.moves, 40)
      eq(guest.session.stakeFoul, nil)
      local own, opp = guest.session.clockOwn, guest.session.clockOpp
      eq(own.n, 20); eq(opp.n, 20)
      ok(own.sum <= ns.Clock.tolerance(own.n), "own " .. own.sum)
      ok(opp.sum <= ns.Clock.tolerance(opp.n), "opp " .. opp.sum)
      ok(math.abs(own.sum - 8 * own.n) < 1, "the round trip, 8 tenths a move, is the player's: own " .. own.sum)
      ok(math.abs(opp.sum) < 1, "opp " .. opp.sum)
    end)

    it("a host that takes my time is caught", function()
      local sim, host, guest = open(30, SK, function(sim)
        tamper(sim, H, function(m)
          if m.t == "EV" and type(m.a) == "table" and m.a.k == "move" and m.seat == 2 then m.dt = m.dt + 30 end
          return m
        end)
      end)
      for ply = 0, 9 do
        if guest.session.stakeFoul then break end
        sim:run(2)
        play(sim, host, guest, ply); sim:run(0)
      end
      eq(guest.session.stakeFoul, "forged")
      ok(guest.session.clockOwn.n <= 5, "caught after " .. guest.session.clockOwn.n)
      eq(guest.session.clockOwn.n, 5)
    end)

    it("a host that hides its own time is caught", function()
      local sim, host, guest = open(30, SK, function(sim)
        tamper(sim, H, function(m)
          if m.t == "EV" and type(m.a) == "table" and m.a.k == "move" and m.seat == 1 then m.dt = 10 end
          return m
        end)
      end)
      for ply = 0, 3 do
        if guest.session.stakeFoul then break end
        if host.session.state.turn == 1 then sim:run(20) end
        play(sim, host, guest, ply); sim:run(0)
      end
      eq(guest.session.stakeFoul, "forged")
      ok(guest.session.clockOpp.n <= 2)
    end)

    it("a move without dt is forged", function()
      local stripped = 0
      local sim, host, guest = open(10, SK, function(sim)
        tamper(sim, H, function(m) -- the host's first move goes without its dt
          if m.t == "EV" and type(m.a) == "table" and m.a.k == "move" and m.seat == 1 and stripped == 0 then
            m.dt, stripped = nil, m.q
          end
          return m
        end)
      end)
      sim:run(1)
      play(sim, host, guest, 0); sim:run(1)
      eq(guest.session.stakeFoul, nil)
      play(sim, host, guest, 1); sim:run(0)
      ok(stripped > 0, "the host's move went")
      eq(#guest.session.state.moves, 2)
      eq(guest.session.stakeFoul, "forged")
    end)

    it("an honest staked game is clean", function()
      local sim, host, guest = open(10, SK)
      for ply = 0, 11 do
        sim:run(3)
        play(sim, host, guest, ply); sim:run(0)
      end
      eq(#guest.session.state.moves, 12)
      eq(guest.session.stakeFoul, nil)
    end)

    it("a false flag is forged", function()
      local sim, host, guest = open(5, SK)
      sim:run(10)
      host.session:play(2, { k = "flag" }, true); sim:run(0)
      over(guest, 1, "flag")
      eq(guest.session.stakeFoul, "forged")
    end)

    it("a flag my own clock agrees with is clean", function()
      local sim, host, guest = open(5, SK)
      sim:run(300 + C.AUTO_GRACE + 1)
      over(guest, 1, "flag")
      eq(guest.session.stakeFoul, nil)
    end)

    -- The guest moves at once; the host's turn runs out by both clocks.
    local function claimable(sk)
      local sim, host, guest = open(5, sk)
      ok(guest:act(move("e2e4"))); sim:run(0)
      noOwnFlag(host)
      for _ = 1, 400 do
        if ns.Clock.canClaim(guest.session) then break end
        sim:run(1)
      end
      ok(ns.Clock.canClaim(guest.session), "the claim is open")
      return sim, host, guest
    end

    it("a claim the host ignores is forged", function()
      local sim, host, guest = claimable(SK)
      ok(ns.Clock.claim(guest)); sim:run(0)
      eq(host.session.state.claimed, 1)
      eq(ns.Clock.canClaim(guest.session), false) -- once per ply
      sim:run(C.AUTO_GRACE - 1)
      eq(guest.session.stakeFoul, nil)
      sim:run(1)
      eq(guest.session.stakeFoul, "forged")
      eq(guest.session.state.phase, "play")
    end)

    it("a claim the host answers with a move is forged", function()
      local sim, host, guest = claimable(SK)
      ok(ns.Clock.claim(guest)); sim:run(1)
      eq(guest.session.stakeFoul, nil)
      host.session.clockAt = sim.clock -- the host forgets its own time
      ok(host:act(move("e7e5"))); sim:run(0)
      eq(#guest.session.state.moves, 2)
      eq(guest.session.stakeFoul, "forged")
      eq(guest.session.claimTimer, nil)
    end)

    it("a claim an honest host answers ends in its flag", function()
      local flags = {}
      local sim, host, guest = open(5, SK, function(sim)
        tamper(sim, H, function(m) -- the flag is slow on its way
          if m.t == "EV" and type(m.a) == "table" and m.a.k == "flag" then
            flags[#flags + 1] = m
            sim.envs[H].after(3, function() sim.bus:send(H, "WHISPER", G, m) end)
            return nil
          end
          return m
        end)
      end)
      ok(guest:act(move("e2e4"))); sim:run(0)
      sim:run(300)
      eq(host.session.state.phase, "over")
      eq(guest.session.state.phase, "play")
      ok(ns.Clock.canClaim(guest.session), "the guest's clock says the time is gone")
      ok(ns.Clock.claim(guest)); sim:run(0)
      sim:run(3)
      over(guest, 2, "flag")
      eq(guest.session.claimTimer, nil)
      sim:run(C.AUTO_GRACE + 1)
      eq(guest.session.stakeFoul, nil)
      eq(#flags, 1)
    end)
  end)

  it("at a table for fun a failed claim marks nothing, and the honest host flags itself", function()
    local sim, host, guest = open(5)
    ok(guest:act(move("e2e4"))); sim:run(0)
    noOwnFlag(host)
    sim:run(300)
    ok(ns.Clock.canClaim(guest.session))
    ok(ns.Clock.claim(guest)); sim:run(C.AUTO_GRACE + 1)
    eq(guest.session.stakeFoul, nil)
    eq(guest.session.state.phase, "play")
    local sim2, host2, guest2 = open(5)
    ok(guest2:act(move("e2e4"))); sim2:run(0)
    sim2:run(300)
    over(guest2, 2, "flag")
    eq(guest2.session.stakeFoul, nil)
  end)

  it("the other games send what they sent", function()
    local function noDt(sim)
      local n = 0
      for _, r in ipairs(sim.sent) do
        n = n + 1
        ok(r.msg.dt == nil, "a " .. tostring(r.msg.t) .. " with dt")
      end
      ok(n > 0)
    end
    local sim, cl = Play.guild(2)
    Play.open(sim, cl, "ttt", nil, 2)
    Play.finish(sim, cl[H])
    noDt(sim)
    Play.short("santase")
    local sim2, cl2 = Play.guild(2)
    Play.open(sim2, cl2, "santase", nil, 2)
    Play.finish(sim2, cl2[H])
    Play.restore()
    noDt(sim2)
  end)
end)
