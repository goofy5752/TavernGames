Loader.lib("Libs/LibStub/LibStub.lua")
Loader.lib("Libs/AceSerializer-3.0/AceSerializer-3.0.lua")
Loader.lib("Libs/LibDeflate/LibDeflate.lua")
local Sim = require("sim")
local Play = require("play")
local ns = Sim.ns
local C, E, copy = ns.Const, ns.Engines.holdem, ns.Util.copy

-- Stage F3, Task 6: no void and no away moves a chip at a cash table (E2, E4,
-- E5, C9; core/Cash.lua `lapsed`, Member.unasked, s.stepAsks, s.hostHeard).
local restore = Play.staked("holdem")
local A, B, M = Play.NAMES[1], Play.NAMES[2], Play.NAMES[3]
local ALL = { A, B, M }

-- The EV actions `name` was whispered after the first `from` messages of sim.sent
-- (copied from tests/core/holdem_table_test.lua).
local function evs(sim, name, from)
  local out = {}
  for i = from + 1, #sim.sent do
    local m = sim.sent[i]
    if m.target == name and m.msg.t == "EV" then out[#out + 1] = m.msg.a end
  end
  return out
end
local function kinds(list)
  local out = {}
  for i, a in ipairs(list) do out[i] = a.k == "fair" and a.op or a.k end
  return out
end

-- The ACTs `name` sends that `drop(a)` picks go nowhere (every ACT without drop)
-- until the returned function is called.
local function mute(sim, name, drop)
  local env, on = sim.envs[name], true
  local send = env.send
  env.send = function(channel, target, msg, done)
    local a = msg.t == "ACT" and msg.a
    if on and type(a) == "table" and (drop == nil or drop(a)) then return end
    return send(channel, target, msg, done)
  end
  return function() on = false end
end
local function isStep(a) return a.k == "book" and a.op == "step" end

-- The chips of every seat and a copy of cash.took on c's state.
local function money(c)
  local st, t = c.session.state, {}
  for i = 1, 9 do if type(st.seats[i]) == "table" then t[i] = st.seats[i].chips end end
  return t, copy(st.cash and st.cash.took)
end

-- One second at a time until a hand runs at host's table.
local function inHand(sim, host)
  for _ = 1, 30 do
    if E.inHand(host.session.state) then return end
    sim:run(1)
  end
  error("no hand begins")
end

-- One second at a time until a hand at host's table ends void (an error after `limit` s, default 40).
local function untilVoid(sim, host, limit)
  local seen = host.session.state.last
  for _ = 1, limit or 40 do
    local l = host.session.state.last
    if l ~= seen and l and l.void then return end
    sim:run(1)
  end
  error("no void")
end

-- The seat on turn checks, else calls, until the running hand is over (or until(st)).
local function calm(sim, host, stop)
  for _ = 1, 200 do
    local st = host.session.state
    if not E.inHand(st) or (stop and stop(st)) then return end
    local c = st.turn and sim.clients[host.session.seats[st.turn]]
    if c and not c:act{ k = "check" } then c:act{ k = "call" } end
    sim:run(1)
  end
  error("the hand does not end")
end

-- Play.cash(3); hand 1 (the host deals it) is played out: between hands, the
-- next one is dealt by a member -> sim, cl, tid.
local function toHand2()
  local sim, cl, tid = Play.cash(3)
  local host = cl[A]
  inHand(sim, host)
  calm(sim, host)
  return sim, cl, tid
end

-- Hand 2 runs to its flop, which is due: the dealer's step is asked next ->
-- the dealer's seat, name, and the money before the hand.
local function flopDue(sim, cl)
  local host = cl[A]
  local chips, took = money(host)
  inHand(sim, host)
  calm(sim, host, function(st) return st.phase == "street" end)
  local hs = host.session
  eq({ hs.state.phase, hs.fair.stage, hs.fair.d ~= 1 }, { "street", "dealt", true })
  return hs.fair.d, hs.seats[hs.fair.d], chips, took
end

-- The host's heartbeat reaches `name` now.
local function tick(sim, cl, name)
  local hs = cl[A].session
  sim.envs[A].send("WHISPER", name, ns.Session.message("TCK", { tid = hs.tid, e = hs.epoch, q = hs.seq }))
end

local function fouls(cl)
  local t = {}
  for _, n in ipairs(ALL) do t[#t + 1] = tostring(cl[n].session.stakeFoul) end
  return t
end

describe("a lapse at a cash table voids before it sits anyone out", function()
  it("a commit lapse voids first: the silent big blind keeps its blind", function()
    local sim, cl = Play.cash(3)
    local host = cl[A]
    ok(not E.inHand(host.session.state), "no hand yet")
    local chips, took = money(host)
    mute(sim, M) -- seat 3, the big blind of hand 1: no commit of it reaches the host
    local mark = #sim.sent
    inHand(sim, host)
    eq(host.session.state.p[3].total, 10)
    untilVoid(sim, host)
    eq(kinds(evs(sim, B, mark)), { "hand", "open", "void", "away" })
    eq(evs(sim, B, mark)[4], { k = "away", seat = 3 })
    for _, n in ipairs(ALL) do
      local c, t = money(cl[n])
      eq({ c, t }, { chips, took }, n)
    end
    eq(fouls(cl), { "nil", "nil", "nil" })
    eq(host.session.state.seats[3].away, true)
  end)

  it("a seed lapse with no seat named voids first (the dealer silent)", function()
    local sim, cl = toHand2()
    local host = cl[A]
    local chips, took = money(host)
    local dseat = host.session.state.button % 3 + 1 -- hand 2's button and dealer
    local dn = host.session.seats[dseat]
    mute(sim, dn, function(a) return a.k == "fair" and a.op == "deal" end) -- it has every seed and deals nothing
    local mark = #sim.sent
    untilVoid(sim, host)
    local e = evs(sim, B, mark)
    local i = 0
    for k, a in ipairs(e) do if a.k == "void" then i = k; break end end
    ok(i > 0, "a void")
    eq(e[i + 1], { k = "away", seat = dseat })
    for _, n in ipairs(ALL) do
      local c, t = money(cl[n])
      eq({ c, t }, { chips, took }, n) -- the small blind's chips are back
    end
    eq(fouls(cl), { "nil", "nil", "nil" })
  end)

  it("a fun table's lapse is as before", function()
    local sim, cl = Play.guild(3)
    local tid = assert(cl[A]:openTable{ game = "holdem", access = "guild", turn = 30 })
    sim:run(3)
    cl[B]:sit(tid, 2); sim:run(1)
    cl[M]:sit(tid, 3); sim:run(1)
    mute(sim, M)
    local mark = #sim.sent
    ok(cl[A]:startGame()); sim:run(1)
    sim:run(C.FAIR_WAIT + 1)
    -- What e62ddc6 plays: the silent seat sits out, its blind stays in the pot, the shuffle opens again.
    eq(kinds(evs(sim, B, mark)), { "start", "hand", "open", "away", "open", "commits", "deal" })
    eq(evs(sim, B, mark)[4], { k = "away", seat = 3 })
    local st = cl[A].session.state
    eq({ st.seats[3].chips, st.p[3].total, st.p[3].folded, st.last }, { 990, 10, true, nil })
  end)
end)

describe("a member judges a void and an away at a cash table", function()
  it("an early void of a commit round is forged on a member; one after the wait is not", function()
    for _, wait in ipairs({ 5, 14 }) do
      local sim, cl = Play.cash(3)
      local host = cl[A]
      local chips, took = money(host)
      mute(sim, M)
      inHand(sim, host)
      eq(cl[B].session.fair.stage, "commit")
      sim:run(wait) -- by the members' clocks: the open came with the hand
      host.session:play(0, { k = "void" }); sim:run(1)
      eq(host.session.state.last.void, true)
      eq(cl[B].session.stakeFoul, wait == 5 and "forged" or nil, wait)
      eq({ money(cl[B]) }, { chips, took })
    end
  end)

  it("an away of my live seat in a running hand is forged at a staked table", function()
    for _, staked in ipairs({ true, false }) do
      local sim, cl, tid
      if staked then
        sim, cl = Play.cash(3)
        mute(sim, M)
      else
        sim, cl = Play.guild(3)
        tid = assert(cl[A]:openTable{ game = "holdem", access = "guild", turn = 30 })
        sim:run(3)
        cl[B]:sit(tid, 2); sim:run(1)
        cl[M]:sit(tid, 3); sim:run(1)
        mute(sim, M)
        ok(cl[A]:startGame())
      end
      local host = cl[A]
      inHand(sim, host)
      sim:run(1)
      local s = cl[B].session
      eq(s.fair.stage, "commit")
      sim:run(14 - (sim.clock - s.fair.openedAt)) -- a modified host: 14 s after the open, before its wait is over
      host.session:play(0, { k = "away", seat = 2 }); sim:run(1)
      eq(s.state.seats[2].away, true)
      if staked then eq(s.stakeFoul, "forged") else eq(s.fair.foul, nil) end -- a fun table takes it
    end
  end)
end)

describe("the dealer's step (E2, H14)", function()
  it("the dealer whose step the host ignores: its void is forged on the dealer (E2)", function()
    local sim, cl = toHand2()
    local _, dn, chips, took = flopDue(sim, cl)
    local host = cl[A]
    local third = dn == B and M or B
    local recv = host.receive -- the host drops every step
    host.receive = function(self, channel, sender, msg)
      if msg.t == "ACT" and type(msg.a) == "table" and isStep(msg.a) then return end
      return recv(self, channel, sender, msg)
    end
    sim:run(3); tick(sim, cl, dn) -- the host's heartbeat between the dealer's first and second ask
    untilVoid(sim, host)
    eq(cl[dn].session.stakeFoul, "forged")
    eq(cl[third].session.stakeFoul, nil)
    for _, n in ipairs(ALL) do
      local c, t = money(cl[n])
      eq({ c, t }, { chips, took }, n)
    end
  end)

  it("a dealer that asked once and lost its link is not charged", function()
    local sim, cl = toHand2()
    local _, dn = flopDue(sim, cl)
    local host = cl[A]
    local unmute = mute(sim, dn, isStep) -- its first ask is lost in the link that goes down
    sim:run(2)
    eq(cl[dn].session.stepAsks.n, 1)
    sim:offline(dn)
    sim:run(C.FAIR_WAIT)
    eq(host.session.state.last.void, true)
    unmute(); sim:online(dn)
    sim:run(C.PING_EVERY + 5)
    local ds = cl[dn].session
    eq(ds.seq, host.session.seq)
    eq(ds.stakeFoul, "unseen") -- the question of the snapshot it asked for when back, no foul of the void
  end)

  it("two asks into a dead link: no foul (H14)", function()
    for _, up in ipairs({ false, true }) do
      local sim, cl = toHand2()
      local _, dn, chips, took = flopDue(sim, cl)
      local host = cl[A]
      -- No step of the dealer reaches the host: lost on the link (down), or dropped by a modified host (up).
      local recv = host.receive
      host.receive = function(self, channel, sender, msg)
        if msg.t == "ACT" and type(msg.a) == "table" and isStep(msg.a) then return end
        return recv(self, channel, sender, msg)
      end
      if not up then sim:offline(dn) end -- down from the moment the step is due
      sim:run(3); tick(sim, cl, dn) -- the host's heartbeat: lost too while the link is down
      sim:run(4)
      eq(sim:count(function(m) return m.from == dn and m.msg.t == "ACT" and isStep(m.msg.a) end), 2)
      sim:online(dn)
      untilVoid(sim, host)
      local ds = cl[dn].session
      eq({ ds.stepAsks.n, ds.stakeFoul }, { up and 2 or 1, up and "forged" or nil }, up)
      for _, n in ipairs(ALL) do
        local c, t = money(cl[n])
        eq({ c, t }, { chips, took }, n)
      end
    end
  end)

  it("a dealer that goes silent at a due showdown voids a lost all-in (C9)", function()
    local sim, cl = toHand2()
    local host = cl[A]
    local chips, took = money(host)
    inHand(sim, host)
    local hs = host.session
    for _ = 1, 30 do if hs.fair and hs.fair.stage == "dealt" and hs.state.turn then break end; sim:run(1) end
    local dn = hs.seats[hs.fair.d]
    ok(hs.fair.d ~= 1, "a member deals")
    local third = dn == B and M or B
    ok(sim.clients[hs.seats[hs.state.turn]]:act{ k = "allin" }); sim:run(1)
    ok(sim.clients[hs.seats[hs.state.turn]]:act{ k = "call" }); sim:run(1)
    local unmute = mute(sim, dn, isStep) -- the all-in is called: the dealer's client goes silent
    ok(sim.clients[hs.seats[hs.state.turn]]:act{ k = "fold" }); sim:run(1)
    eq(hs.state.phase, "street")
    untilVoid(sim, host)
    for _, n in ipairs(ALL) do
      local c, t = money(cl[n])
      eq({ c, t }, { chips, took }, n)
    end
    for _, n in ipairs({ A, third }) do eq((cl[n].session.fairVoids or {})[dn], 1, n) end
    eq({ ns.Deal.status(cl[third].session) }, { "fair.voidBy", dn })
    -- The same dealer, silent once more: red.
    unmute()
    local due = false
    for _ = 1, 300 do
      local f, st = hs.fair, hs.state
      due = f and f.stage == "dealt" and hs.seats[f.d] == dn and st.phase == "street"
      if due then break end
      local c = E.inHand(st) and st.turn and sim.clients[hs.seats[st.turn]]
      if c and not c:act{ k = "check" } then c:act{ k = "call" } end
      sim:run(1)
    end
    ok(due, "the same dealer deals again, its flop due")
    mute(sim, dn, isStep)
    untilVoid(sim, host)
    local other = cl[third].session
    eq((other.fairVoids or {})[dn], 2)
    eq({ ns.Deal.status(other) }, { "fair.voidMany", dn, 2 })
    eq(ns.Deal.alarm(other), true)
  end)

  it("a provoked seed lapse returns every chip and is counted by name (E4)", function()
    local sim, cl = toHand2()
    local host = cl[A]
    local chips, took = money(host)
    local dn = host.session.seats[host.session.state.button % 3 + 1]
    local victim = dn == B and M or B
    local recv = cl[dn].receive -- the dealer claims it lacks the victim's seed
    cl[dn].receive = function(self, channel, sender, msg)
      if msg.t == "SED" and sender == victim then return end
      return recv(self, channel, sender, msg)
    end
    untilVoid(sim, host)
    for _, n in ipairs(ALL) do
      local c, t = money(cl[n])
      eq({ c, t }, { chips, took }, n)
      eq((cl[n].session.fairLapses or {})[dn], 1, n)
    end
    eq(host.session.fairLapses[dn], 1)
  end)
end)

restore()
