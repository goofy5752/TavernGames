local Sim = require("sim")
local Play = require("play")
local ns = Sim.ns
local C, Stakes = ns.Const, ns.Stakes

local restore = Play.staked("santase", "belot", "tabla")

local I, P, M, G = Play.NAMES[1], Play.NAMES[2], Play.NAMES[3], Play.NAMES[4]
local T = "Тодор Ангелов" -- the fifth guild member: the refill
local SK = 50000

local function record(client, event)
  local list = {}
  client:on(event, function(...) list[#list + 1] = { ... } end)
  return list
end

-- The GUILD entries of kind k at gid (from = nil: anyone's).
local function at(sim, from, k, gid)
  local out = {}
  for _, e in ipairs(Play.entries(sim, from, k)) do if e.gid == gid then out[#out + 1] = e end end
  return out
end

-- The GUILD entries of kind k (C or N) about the D entry d.
local function about(sim, from, k, d)
  local out = {}
  for _, e in ipairs(Play.entries(sim, from, k)) do if e.r == d.i then out[#out + 1] = e end end
  return out
end

-- Runs the simulator up to clock `to`.
local function runTo(sim, to)
  if to > sim.clock then sim:run(to - sim.clock) end
end

-- A staked short match of `game` between the first n names, played to its end
-- -> sim, cl, tid, the result, t (the host's clock at the end).
local function ended(game, n, more)
  Play.short(game)
  local sim, cl = Play.guild(n, more)
  local tid = Play.open(sim, cl, game, SK, n)
  local r = Play.finish(sim, cl[I])
  local t = cl[I].session.stakeEndedAt
  ok(t, "the end is dated")
  return sim, cl, tid, r, t
end

-- The seat names of a finished match: the loser's, the winner's.
local function sides(cl, r)
  local names = cl[I].session.seats
  return names[r.losers[1]], names[r.winners[1]]
end

-- Белот: Мария (seat 3) presses „Стани“ in the running match -> sim, cl, tid, t (the end of that match).
local function belotLeave()
  local sim, cl = Play.guild(4, { T })
  local tid = Play.open(sim, cl, "belot", SK, 4)
  for _ = 1, 4 do Play.step(sim, cl[I]) end
  cl[M]:stand(); sim:run(0)
  local s = cl[I].session
  eq(s.status, "aborted"); ok(s.stakeEndedAt, "the leave ended the match")
  return sim, cl, tid, s.stakeEndedAt
end

describe("stakes: the next match of a staked table", function()
  it("Stakes.gap: 30 s for Сантасе, Белот and Табла; Морски шах and Death Roll keep 10", function()
    eq(C.STAKE_BREAK_MATCH, 30); eq(C.STAKE_BREAK, 10)
    for _, g in ipairs({ { "santase", 30 }, { "belot", 30 }, { "tabla", 30 }, { "ttt", 10 }, { "deathroll", 10 } }) do
      local s = { engine = function() return ns.Engines[g[1]] end }
      eq(Stakes.gap(s), g[2], g[1])
    end
  end)

  for _, g in ipairs({ { "santase", 2 }, { "belot", 4 }, { "tabla", 2 } }) do
    it(g[1] .. ": the next match waits for the break", function()
      local sim, cl, tid, r, t = ended(g[1], g[2])
      local host = cl[I]
      sim:run(5)
      runTo(sim, t + 29)
      eq({ host:startGame() }, { nil, "break" })
      sim:run(1)
      eq(host:startGame(), true); sim:run(0)
      for i = 2, g[2] do eq(cl[Play.NAMES[i]].session.stakeFoul, nil, Play.NAMES[i]) end
      local r2 = Play.finish(sim, host)
      ok(r2.q ~= r.q, "a new match")
      sim:run(5)
      local f, w = sides(cl, r2)
      local d = Play.debt(host, tid .. "/" .. r2.q, f, w)
      ok(d, "a debt of the second match"); eq(d.status, "confirmed")
      ok(Play.debt(host, tid .. "/" .. r.q, sides(cl, r)), "the first match's debt stays")
      Play.restore()
    end)
  end

  it("a guest that goes to the hall inside the break is in no new match", function()
    local sim, cl, tid, r, t = ended("santase", 2)
    local host, gid = cl[I], tid .. "/" .. r.q
    local seen = record(host, "forfeit")
    runTo(sim, t + 5)
    cl[P]:stand(); sim:run(0)
    eq(cl[P].session, nil); eq(#seen, 0)
    eq(host.session.status, "aborted")
    eq({ host:startGame() }, { nil, "short" })
    sim:run(C.STAKE_OWE_WAIT + 5)
    eq(#seen, 0)
    for _, d in ipairs(Play.entries(sim, nil, "D")) do eq(d.gid, gid) end
    Play.restore()
  end)

  -- Сантасе ended; the host is made to send EV start at `when(t, mine)` (t: the
  -- host's end, mine: the guest's own) with `first` -> sim, cl, tid, host, guest.
  local function startAt(when, first)
    local sim, cl, tid, _, t = ended("santase", 2)
    local host, guest = cl[I], cl[P]
    runTo(sim, when(t, guest.session.stakeEndedAt))
    host.session:event(0, { k = "start", first = first }); host.session:recordChanged(); sim:run(0)
    eq(guest.session.stakeLive, true)
    return sim, cl, tid, host, guest
  end

  it("a start inside the break is forged against the new match", function()
    -- Played out until the guest loses the forged match (the engines' own play decides who loses).
    local lost = false
    for first = 1, 2 do
      for delay = 5, 8 do
        local sim, cl, tid, host, guest = startAt(function(t) return t + delay end, first)
        eq(guest.session.stakeFoul, "forged")
        local r2 = Play.finish(sim, host)
        sim:run(5)
        Play.restore()
        local f, w = sides(cl, r2)
        local d = at(sim, w, "D", tid .. "/" .. r2.q)[1]
        ok(d, "the winner's claim"); eq(d.f, f)
        if f == P then
          eq(#about(sim, P, "C", d), 0)
          local n = about(sim, P, "N", d)
          eq(#n, 1); eq(n[1].why, "forged")
          eq(Play.debt(host, d.gid, P, I).status, "contested")
          lost = true
          break
        end
      end
      if lost then break end
    end
    ok(lost, "the guest never lost a forged match")
    -- The same start once the break is over by the guest's own clock (AUTO_GRACE left): clean.
    local _, _, _, _, guest = startAt(function(_, mine) return mine + C.STAKE_BREAK_MATCH - C.AUTO_GRACE end, 1)
    eq(guest.session.stakeFoul, nil)
    Play.restore()
    _, _, _, _, guest = startAt(function(_, mine) return mine + C.STAKE_BREAK_MATCH - C.AUTO_GRACE - 1 end, 1)
    eq(guest.session.stakeFoul, "forged")
    Play.restore()
  end)

  it("tabla: a start while the match runs is forged", function()
    local sim, cl = Play.guild(2)
    Play.open(sim, cl, "tabla", SK, 2)
    for _ = 1, 6 do Play.step(sim, cl[I]) end
    local guest = cl[P].session
    eq(guest.stakeLive, true); eq(guest.stakeFoul, nil)
    cl[I].session:event(0, { k = "start", first = 1 }); sim:run(0)
    eq(guest.stakeLive, true); eq(guest.stakeFoul, "forged")
  end)

  it("santase: an abort with every seat full, then a start, is forged", function()
    local sim, cl, _, _, t = ended("santase", 2)
    local host, guest = cl[I].session, cl[P].session
    runTo(sim, t + 40)
    host:event(0, { k = "abort" }); sim:run(0); eq(guest.status, "aborted")
    host:event(0, { k = "start", first = 1 }); sim:run(0)
    eq(guest.stakeLive, true); eq(guest.stakeFoul, "forged")
    Play.restore()
  end)

  it("belot: a refilled table starts when the break is over", function()
    local sim, cl, tid, t = belotLeave()
    runTo(sim, t + 5)
    cl[T]:sit(tid, 3, SK); sim:run(0)
    local s = cl[I].session
    eq(s.seats[3], T); eq(s.status, "aborted")
    runTo(sim, t + 29); eq(s.status, "aborted")
    sim:run(1); eq(s.status, "live"); eq(s.stakeLive, true)
    for _, name in ipairs({ P, G, T }) do
      local m = cl[name].session
      eq(m.stakeLive, true, name); eq(m.stakeFoul, nil, name)
    end
  end)

  it("belot: a refill after the break starts at once", function()
    local sim, cl, tid, t = belotLeave()
    runTo(sim, t + 40)
    cl[T]:sit(tid, 3, SK); sim:run(0)
    eq(cl[I].session.status, "live"); eq(sim.clock, t + 40)
    for _, name in ipairs({ P, G, T }) do eq(cl[name].session.stakeFoul, nil, name) end
  end)

  -- Белот, the refill at t + 5, the host offline at t + 6 -> sim, cl, tid, the new host's client.
  local function silentHost()
    local sim, cl, tid, t = belotLeave()
    runTo(sim, t + 5)
    cl[T]:sit(tid, 3, SK); sim:run(0)
    runTo(sim, t + 6)
    sim:offline(I)
    local new
    for _ = 1, C.SILENT_AFTER + 60 do
      sim:run(1)
      for _, name in ipairs({ P, G, T }) do
        local s = cl[name].session
        if s and s.role == "host" then new = cl[name] end
      end
      if new then break end
    end
    ok(new, "nobody took over")
    eq(new.session.seats[1], I) -- the old host keeps its seat
    ok(sim.clock >= t + 30)
    return sim, cl, tid, new
  end

  it("belot: the held start survives a host change, and never seats a silent player", function()
    local sim, cl, _, new = silentHost()
    local s = new.session
    eq(s.status, "aborted")
    sim:run(20); eq(s.status, "aborted") -- no start while the old host is silent
    sim:online(I)
    for _ = 1, C.PING_EVERY + 15 do
      if s.status == "live" then break end
      sim:run(1)
    end
    eq(new.session, s); eq(s.role, "host"); eq(s.status, "live"); eq(s.stakeLive, true)
    eq(s.seats[1], I)
    for _, name in ipairs({ P, G, T }) do if cl[name] ~= new then eq(cl[name].session.stakeFoul, nil, name) end end
  end)

  it("belot: the successor's „Нова игра“ never seats the silent old host", function()
    local sim, _, _, new = silentHost()
    local s = new.session
    for _ = 1, 20 do
      eq({ s:canStart() }, { nil, "break" }); eq({ new:startGame() }, { nil, "break" })
      sim:run(1)
    end
    eq(s.status, "aborted"); ok(not s.stakeLive, "no match began")
  end)

  it("belot: a host that never comes back is stood up, the table is short, and nothing is owed", function()
    local sim, _, _, new = silentHost()
    local s = new.session
    local mark = #Play.entries(sim, nil, "D")
    local seen = record(new, "forfeit")
    sim.envs[I].dead = true -- its client is gone
    for _ = 1, C.OFFLINE_STAND_SECONDS do
      if not s.seats[1] then break end
      sim:run(1)
    end
    eq(s.seats[1], false); eq(s.status, "aborted")
    sim:run(10)
    eq({ new:startGame() }, { nil, "short" })
    eq(#seen, 0)
    eq(#Play.entries(sim, nil, "D"), mark)
  end)

  it("santase: a host that came in by snapshot after the end holds a full break", function()
    local sim, cl, tid, _, t = ended("santase", 2, { T })
    runTo(sim, t + 1)
    cl[P] = sim:relog(P); sim:settle(); sim:run(3)
    local p = cl[P].session
    ok(p and p.mySeat == 2, "back at the table"); eq(p.stakeEndedAt, nil); ok(p:gameOver())
    cl[I]:stand(); sim:run(0)
    eq(p.role, "host"); eq(p.status, "aborted")
    local from = sim.clock
    eq(p.stakeHoldFrom, from)
    cl[T]:sit(tid, 1, SK); sim:run(0)
    eq(p.seats[1], T); eq(p.status, "aborted")
    runTo(sim, from + Stakes.gap(p) - 1); eq(p.status, "aborted")
    sim:run(1); eq(p.status, "live")
    eq(cl[T].session.stakeLive, true); eq(cl[T].session.stakeFoul, nil)
    Play.restore()
  end)

  -- A takeover of a table whose game is over: `prep(sim, cl, t)` before the old host
  -- goes offline at t + 2 -> sim, cl, t, the new host's client.
  local function claimed(game, n, more, prep)
    local sim, cl, _, _, t = ended(game, n, more)
    if prep then prep(sim, cl, t) end
    runTo(sim, t + 2)
    sim:offline(I)
    local new
    for _ = 1, C.SILENT_AFTER + 60 do
      sim:run(1)
      for name, c in pairs(cl) do
        if name ~= I and c.session and c.session.role == "host" then new = c end
      end
      if new then break end
    end
    ok(new, "nobody took over")
    return sim, cl, t, new
  end

  it("belot: a match over by play, the host gone silent: the successor's „Нова игра“ bills it nothing", function()
    local sim, _, _, new = claimed("belot", 4)
    local s = new.session
    eq(s.status, "live"); ok(s:gameOver()); eq(s.seats[1], I)
    sim.envs[I].dead = true
    for _ = 1, C.OFFLINE_STAND_SECONDS + 10 do
      local can, code = new:startGame()
      ok(not can and (code == "break" or code == "short"), tostring(code))
      sim:run(1)
    end
    eq(s.seats[1], false); ok(not s.stakeLive, "no match began")
    for _, d in ipairs(Play.entries(sim, nil, "D")) do ok(not (d.f == I and d.why == "offline"), "an offline D against the old host") end
    Play.restore()
  end)

  it("santase: a host made by a snapshot of a game over holds its „Нова игра“ a full break", function()
    local sim, cl, _, new = claimed("santase", 2, nil, function(sim, cl, t)
      runTo(sim, t + 1)
      cl[P] = sim:relog(P); sim:settle(); runTo(sim, t + 2)
    end)
    local s = new.session
    eq(new, cl[P]); eq(s.stakeEndedAt, nil); ok(s:gameOver())
    local from = s.stakeHoldFrom
    eq(from, sim.clock)
    sim:online(I)
    runTo(sim, from + Stakes.gap(s) - 1)
    eq({ new:startGame() }, { nil, "break" })
    sim:run(1)
    eq(new:startGame(), true); sim:run(0)
    eq(s.stakeLive, true); eq(s.seats[1], I)
    eq(cl[I].session.stakeLive, true); eq(cl[I].session.stakeFoul, nil)
    Play.restore()
  end)

  it("a fun table of an again game starts and restarts as before", function()
    local x, saved, calls = ns.Ext.stakes, ns.Ext.stakes.hold, 0
    x.hold = function(...) calls = calls + 1; return saved(...) end
    local done, err = pcall(function()
      Play.short("santase")
      local sim, cl = Play.guild(2)
      Play.open(sim, cl, "santase", nil, 2)
      Play.finish(sim, cl[I])
      eq(cl[I]:startGame(), true); sim:run(0)
      eq(cl[I].session.status, "live"); ok(not cl[I].session:gameOver())
      Play.restore()
      sim, cl = Play.guild(4, { T })
      local tid = Play.open(sim, cl, "belot", nil, 4)
      for _ = 1, 4 do Play.step(sim, cl[I]) end
      cl[M]:stand(); sim:run(0); eq(cl[I].session.status, "aborted")
      cl[T]:sit(tid, 3); sim:run(0)
      eq(cl[I].session.status, "live")
    end)
    x.hold = saved
    Play.restore()
    assert(done, err)
    eq(calls, 0)
  end)
end)

restore()
