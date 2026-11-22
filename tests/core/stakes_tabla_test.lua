local Sim = require("sim")
local Play = require("play")
local ns = Sim.ns
local C, Stakes = ns.Const, ns.Stakes
local E = ns.Engines.tabla

local restore = Play.staked("tabla")

local I, P = Play.NAMES[1], Play.NAMES[2] -- the host (seat 1) and the guest (seat 2)
local SK = 50000
local NEED = ns.Ext.dice.need -- a test that holds a throw back puts it back

-- Drops every throw ACT of `name` with that op while its client believes it
-- sent it (once: only those of the first throw it drops) -> a function that
-- lifts it, {n = how many were dropped} (copied from
-- tests/core/tabla_table_test.lua with the sim as an argument and `once`, G10).
local function mute(sim, name, op, once)
  local env, dropped, on = sim.envs[name], { n = 0 }, true
  local send = env.send
  env.send = function(channel, target, msg)
    local act = msg.t == "ACT" and msg.a
    if on and type(act) == "table" and act.k == "throw" and act.op == op and (not once or dropped.h == nil or dropped.h == act.h) then
      dropped.n, dropped.h = dropped.n + 1, act.h
      return
    end
    return send(channel, target, msg)
  end
  return function() on = false end, dropped
end

-- A small generator so that every client of a run draws its seeds from one
-- stream (copied from tests/core/stakes_cards_test.lua, G10).
local function lcg(seed)
  local x = seed
  return function(lo, hi)
    x = (x * 1103515245 + 12345) % 2147483648
    return lo + math.floor(x / 65536) % (hi - lo + 1)
  end
end

-- A staked Табла match of one game between I (host) and P; before the guest
-- sits, before(sim, cl) runs (a mute); seed: every client's random stream -> sim, cl, tid.
local function staked(seed, before)
  ns.Ext.dice.need = NEED
  local sim, cl = Play.guild(2)
  if seed then
    local rnd = lcg(seed)
    for _, c in pairs(cl) do c.env.random = rnd end
  end
  Play.short("tabla")
  if before then before(sim, cl) end
  local tid = Play.open(sim, cl, "tabla", SK, 2)
  return sim, cl, tid
end

-- The seat on turn at host's table moves (Play.step) until done() -> true, or false after `limit` steps.
local function stepUntil(sim, host, done, limit)
  for _ = 1, limit or 3000 do
    if done() then return true end
    Play.step(sim, host)
  end
  return false
end

-- Steps until host's match is over (each(): after every step) -> its gid, loser, winner.
local function finish(sim, host, each)
  local last
  host:on("result", function(r) last = r end)
  for _ = 1, 6000 do
    if host.session and host.session:gameOver() then break end
    Play.step(sim, host)
    if each then each() end
  end
  ok(last, "the match ended")
  local names = last.names or host.session.seats
  return host.session.tid .. "/" .. last.q, names[last.losers[1]], names[last.winners[1]]
end

-- The GUILD entries of kind k (C or N) `from` sent about a D at gid.
local function wordsAt(sim, from, k, gid)
  local ds, out = {}, {}
  for _, d in ipairs(Play.entries(sim, nil, "D")) do if d.gid == gid then ds[d.i] = true end end
  for _, e in ipairs(Play.entries(sim, from, k)) do if ds[e.r] then out[#out + 1] = e end end
  return out
end

-- Runs a staked match per seed, cheat(sim, cl, seed) first, until the guest loses -> sim, cl, gid.
local function untilGuestLoses(cheat, before)
  for seed = 1, 40 do
    local sim, cl = staked(seed, before)
    cheat(sim, cl, seed)
    local gid, L = finish(sim, cl[I])
    sim:run(5)
    if L == P then return sim, cl, gid end
    Play.restore()
  end
  error("Петър never loses")
end

-- How many EVs for seat 2 flagged auto (a timeout) went to the guest after index `from` of sim.sent.
local function timeouts(sim, from)
  local n = 0
  for i = from + 1, #sim.sent do
    local m = sim.sent[i]
    if m.target == P and m.msg.t == "EV" and m.msg.seat == 2 and m.msg.auto then n = n + 1 end
  end
  return n
end

-- The guest's seat 2 is on turn and may move (its dice are thrown).
local function guestMoves(cl) local st = cl[I].session.state; return st.turn == 2 and st.phase == "move" end
local function hostMoves(cl) local st = cl[I].session.state; return st.turn == 1 and st.phase == "move" end

describe("stakes: a staked Табла table (F2 Task 5)", function()
  it("a clean staked tabla match: the loser confirms by itself", function()
    local sim, cl = staked()
    local function clean()
      for _, name in ipairs({ I, P }) do eq(cl[name].session.stakeFoul, nil, name) end
    end
    local gid, L, W = finish(sim, cl[I], clean)
    clean()
    sim:run(5)
    for _, name in ipairs({ I, P }) do
      local d = Play.debt(cl[name], gid, L, W)
      ok(d, name); eq({ d.c, d.status }, { SK, "confirmed" })
    end
    eq(#wordsAt(sim, L, "C", gid), 1); eq(#wordsAt(sim, L, "N", gid), 0)
    Play.restore()
  end)

  it("the host moves for my seat: contested as forged (D1)", function()
    local sim, cl, gid = untilGuestLoses(function(sim, cl)
      local hs = cl[I].session
      ok(stepUntil(sim, cl[I], function() return guestMoves(cl) end), "the guest's move")
      hs:play(2, E.auto(hs.state, 2), true); sim:run(0)
      eq(cl[P].session.stakeFoul, "forged")
    end)
    local n = wordsAt(sim, P, "N", gid)
    eq(#n, 1); eq(n[1].why, "forged"); eq(#wordsAt(sim, P, "C", gid), 0)
    eq(Play.debt(cl[I], gid, P, I).status, "contested")
    Play.restore()
  end)

  it("the host's timeout for my seat is taken only after my own clock ran out", function()
    -- The host's own clock: AUTO_GRACE after the deadline of a 45 s turn.
    local sim, cl = staked()
    local hs, gs = cl[I].session, cl[P].session
    ok(stepUntil(sim, cl[I], function() return guestMoves(cl) end), "the guest's move")
    local from = #sim.sent
    sim:run(45 + C.AUTO_GRACE)
    eq(timeouts(sim, from), 1); eq(gs.seq, hs.seq); eq(gs.stakeFoul, nil)
    Play.restore()
    -- The same event at 10 s.
    sim, cl = staked()
    hs, gs = cl[I].session, cl[P].session
    ok(stepUntil(sim, cl[I], function() return guestMoves(cl) end), "the guest's move")
    sim:run(10)
    hs:play(2, E.auto(hs.state, 2), true); sim:run(0)
    eq(gs.stakeFoul, "forged")
    Play.restore()
  end)

  it("a throw my host holds back gives my turn a fresh clock: its timeout for me before that clock ran out is forged", function()
    for _, honest in ipairs({ false, true }) do
      local sim, cl = staked()
      local hs, gs = cl[I].session, cl[P].session
      ok(stepUntil(sim, cl[I], function() return hostMoves(cl) end), "the host's move")
      ns.Ext.dice.need = function() end -- the host opens no throw for the guest's turn
      Play.step(sim, cl[I])
      eq({ hs.state.turn, hs.state.phase }, { 2, "roll" })
      sim:run(30)
      ns.Ext.dice.need = NEED
      ns.Dice.open(hs); sim:run(0)
      ok(guestMoves(cl), "the throw is in")
      local from = #sim.sent
      if honest then
        sim:run(45 + C.AUTO_GRACE)
        eq(timeouts(sim, from), 1); eq(gs.stakeFoul, nil) -- the host's own clock: clean
      else
        sim:run(16) -- 46 s after the turn came to me, 16 s after my dice
        hs:play(2, E.auto(hs.state, 2), true); sim:run(0)
        eq(gs.stakeFoul, "forged")
      end
      Play.restore()
    end
  end)

  it("my own moves of a cascade each give my clock a fresh start", function()
    local sim, cl = staked()
    local hs, gs = cl[I].session, cl[P].session
    ok(stepUntil(sim, cl[I], function() return guestMoves(cl) end), "the guest's move")
    -- Both clients hold a Гюлбара cascade of 1s on the guest's turn (its 5th roll).
    local function zeros() local t = {} for q = 1, 24 do t[q] = 0 end return t end
    local st = {
      phase = "move", game = 3, var = "gul", score = { 0, 0 }, turn = 2, dice = { 1, 1 }, left = { 1, 1, 1, 1 },
      cv = 1, xfer = false, pts = { zeros(), zeros() }, pin = { zeros(), zeros() }, bar = { 0, 0 }, off = { 0, 0 }, rolls = { 4, 5 },
    }
    st.pts[1][24], st.pts[2][24] = 15, 15
    hs.state, gs.state = ns.Util.copy(st), ns.Util.copy(st)
    sim:run(30)
    cl[P]:act(E.auto(gs.state, 2)); sim:run(0)
    eq({ hs.state.turn, hs.state.cv, gs.state.turn, gs.state.cv }, { 2, 2, 2, 2 }) -- my turn goes on: 2s
    eq(gs.turnAt, cl[P].env.now()); eq(gs.stakeTurn.at, cl[P].env.now())
    sim:run(16)
    eq(ns.Member.timedOut(gs, { auto = true, seat = 2, a = E.auto(gs.state, 2) }), false)
    hs:play(2, E.auto(hs.state, 2), true); sim:run(0)
    eq(gs.stakeFoul, "forged")
    Play.restore()
  end)

  it("a snapshot that is not my very state gives my turn a fresh clock (Табла's rolls are no Death Roll's)", function()
    local a = E.new{}; local b = ns.Util.copy(a)
    b.pts[1][24], b.pts[1][23] = b.pts[1][24] - 1, 1
    eq(Stakes.leadsTo(a, b), false); eq(Stakes.leadsTo(b, a), false); eq(Stakes.leadsTo(a, a), false)
    local sim, cl = staked()
    local hs, gs = cl[I].session, cl[P].session
    ok(stepUntil(sim, cl[I], function() return guestMoves(cl) end), "the guest's move")
    sim:run(30)
    -- The same host at epoch + 1: my seat on turn in a state I do not hold.
    local x = ns.Util.copy(hs.state)
    x.pts[1][24], x.pts[1][23] = x.pts[1][24] - 1, x.pts[1][23] + 1
    cl[P]:receive("WHISPER", I, ns.Session.message("SNP", {
      tid = hs.tid, e = hs.epoch + 1, q = hs.seq, tbl = hs:record(), st = E.snapshot(x),
      left = hs:left(), inv = hs:invitedList(), fr = hs:hook("snap"),
    }))
    sim:run(0)
    gs = cl[P].session
    eq(gs.state.turn, 2); eq(gs.turnAt, cl[P].env.now())
    sim:run(16)
    eq(ns.Member.timedOut(gs, { auto = true, seat = 2, a = E.auto(gs.state, 2) }), false)
    Play.restore()
  end)

  it("a throw made alone against my commit contests the match from the first one (D3)", function()
    local lift
    local sim, cl, gid = untilGuestLoses(function(sim, cl)
      sim:run(C.DICE_WAIT + 1)
      local gs = cl[P].session
      eq(gs.diceSeen.alone, 1); eq(gs.diceRobbed, 1); eq(gs.stakeFoul, "dice")
      lift()
    end, function(sim) lift = mute(sim, P, "seed", true) end)
    local n = wordsAt(sim, P, "N", gid)
    eq(#n, 1); eq(n[1].why, "dice"); eq(#wordsAt(sim, P, "C", gid), 0)
    eq(Play.debt(cl[I], gid, P, I).status, "contested")
    Play.restore()
  end)

  it("a throw made alone while my client said nothing is no foul", function()
    local sim, cl = staked()
    ok(stepUntil(sim, cl[I], function() return hostMoves(cl) end), "the host's move")
    local gs = cl[P].session
    local alone = cl[I].session.diceSeen.alone or 0
    sim:offline(P)
    Play.step(sim, cl[I]) -- the guest's throw opens while it hears nothing
    sim:run(C.DICE_WAIT + 2)
    eq(cl[I].session.diceSeen.alone, alone + 1)
    sim:online(P)
    for _ = 1, 40 do if cl[P].session.seq == cl[I].session.seq then break end; sim:run(1) end
    eq(cl[P].session.seq, cl[I].session.seq) -- resynced before the host's clock ran out on my turn
    Play.step(sim, cl[I]) -- my own move
    gs = cl[P].session
    eq(gs.diceRobbed, nil); eq(gs.stakeFoul, "unseen")
    Play.restore()
  end)

  it("my own loading screen: the match is put to me, not contested (D6)", function()
    local sim, cl = staked(nil, function(sim)
      sim:loading(P, true) -- the flag only: the events still reach the guest
      mute(sim, P, "seed")
    end)
    local gs = cl[P].session
    sim:run(C.DICE_WAIT)
    eq(gs.diceSeen.alone, 1); eq(gs.diceAway, 1); eq(gs.diceRobbed, nil); eq(gs.stakeFoul, "unseen")
    sim:run(C.DICE_WAIT) -- the next throw under the same screen
    eq(gs.diceSeen.alone, 2); eq(gs.diceAway, 1); eq(gs.diceRobbed, 1); eq(gs.stakeFoul, "dice")
    Play.restore()
    -- A throw that only a resync shows me (its messages were lost with the screen).
    sim, cl = staked(nil, function(sim) mute(sim, P, "seed", true) end)
    gs = cl[P].session
    ok(gs.throw and gs.throw.sent, "my seed went out")
    sim:loading(P, true); sim:offline(P)
    sim:run(C.DICE_WAIT + 2)
    sim:online(P); sim:loading(P, false)
    sim:run(90)
    gs = cl[P].session
    eq(gs.diceRobbed, nil); eq(gs.stakeFoul, "unseen")
    Play.restore()
  end)

  it("a host that reloads over my seed re-rolls: contested (D2)", function()
    local sim, cl = staked(nil, function(sim) mute(sim, P, "seed", true) end)
    local gs = cl[P].session
    local h = gs.throw.h
    ok(gs.throw.sent, "my seed went out")
    local a2 = sim:relog(I) -- before its seeds event
    for _ = 1, 120 do if gs.role == "host" then break end; sim:run(1) end
    eq(gs.role, "host")
    sim:run(2)
    ok(gs.throw and gs.throw.h > h, "a new number")
    eq(gs.diceRobbed, 1); eq(gs.stakeFoul, "dice")
    eq(a2.session and a2.session.stakeFoul, "unseen") -- the old host, back by a snapshot
    Play.restore()
    -- Only my commit had gone out: the opener knew nothing.
    sim, cl = staked(nil, function(sim) mute(sim, P, "commit") end)
    gs = cl[P].session
    ok(gs.throw.asked and not gs.throw.sent, "only my commit")
    sim:relog(I)
    for _ = 1, 120 do if gs.role == "host" then break end; sim:run(1) end
    eq(gs.role, "host"); sim:run(2)
    eq(gs.diceRobbed, nil); ok(gs.stakeFoul ~= "dice", "no dice foul")
    Play.restore()
  end)

  it("a seat-0 dice event is contested", function()
    local sim, cl = staked(nil, function(sim) mute(sim, P, "seed") end)
    cl[I].session:play(0, { k = "dice", d = { 6, 6 } }); sim:run(0)
    eq(cl[P].session.stakeFoul, "dice")
    Play.restore()
  end)

  it("a host that throws again over my seed (dodge) is contested", function()
    local sim, cl = staked(nil, function(sim) mute(sim, P, "seed") end)
    ns.Dice.open(cl[I].session); sim:run(1)
    eq(cl[P].session.diceLast.why, "dodge"); eq(cl[P].session.stakeFoul, "dice")
    Play.restore()
  end)

  it("after my /reload a valid alone proof is taken, and my debt is a question (D5)", function()
    local b2
    local sim, cl, gid = untilGuestLoses(function(sim, cl)
      ok(stepUntil(sim, cl[I], function() return hostMoves(cl) end), "the host's move")
      mute(sim, P, "seed", true)
      Play.step(sim, cl[I]) -- the guest's throw: its commit is in, its seed is not
      b2 = sim:crash(P); sim:settle() -- the seed is lost with the crash
      for _ = 1, 10 do if b2.session then break end; sim:run(1) end
      eq(b2:acceptStake(), true) -- the crash lost my stake note: I am asked, and accept
      sim:run(C.DICE_WAIT + 5)
      local gs = b2.session
      ok(gs.stakeLive, "back in the match"); eq(gs.diceLast.verdict, "alone")
      eq(gs.diceRobbed, nil); eq(gs.stakeFoul, "unseen")
    end)
    eq(b2.session.stakeFoul, "unseen")
    eq(#wordsAt(sim, P, "C", gid), 0); eq(#wordsAt(sim, P, "N", gid), 0)
    local asked = false
    for _, d in ipairs(b2.stakes:asks()) do if d.gid == gid and d.f == P and d.t == I then asked = true end end
    ok(asked, "the debt is put to me")
    eq(Play.debt(cl[I], gid, P, I).status, "pending")
    Play.restore()
  end)

  it("the counts are the match's", function()
    local sim, cl = staked(nil, function(sim) mute(sim, P, "seed", true) end)
    sim:run(C.DICE_WAIT + 1)
    local gs = cl[P].session
    eq(gs.diceRobbed, 1)
    cl[I].session:event(0, { k = "start", first = 1 }); sim:run(0) -- a start while the match runs
    eq(gs.stakeLive, true); eq(gs.diceRobbed, 1); eq(gs.stakeFoul, "forged")
    Play.restore()
    sim, cl = staked(nil, function(sim) mute(sim, P, "seed", true) end)
    sim:run(C.DICE_WAIT + 1)
    gs = cl[P].session
    eq(gs.diceRobbed, 1)
    finish(sim, cl[I])
    eq(gs.diceRobbed, 1) -- kept across the end
    sim:run(C.STAKE_BREAK_MATCH + 1)
    eq(cl[I]:startGame(), true); sim:run(0)
    eq(gs.stakeLive, true); eq(gs.diceRobbed, nil); eq(gs.stakeFoul, nil)
    Play.restore()
  end)

  it("a fun tabla table runs no stakes code", function()
    local calls, saved = 0, {}
    for name, f in pairs(ns.Ext.stakes) do
      saved[name] = f
      ns.Ext.stakes[name] = function(...) calls = calls + 1; return f(...) end
    end
    ns.Ext.dice.need = NEED
    local sim, cl = Play.guild(2)
    local back = Play.short("tabla")
    mute(sim, P, "seed", true)
    Play.open(sim, cl, "tabla", nil, 2)
    sim:run(C.DICE_WAIT + 1)
    local s = cl[P].session
    for _ = 1, 4 do Play.step(sim, cl[I]) end
    back()
    for name, f in pairs(saved) do ns.Ext.stakes[name] = f end
    eq(calls, 0)
    eq(s.diceRobbed, 1) -- counted, shown nowhere
    eq({ ns.Dice.status(s) }, { "dice.ok", "good" }) -- as 88a48e7 gives for this script
    eq(ns.Dice.tip(s), { { "ink", "dice.tip" }, { "red", "dice.unheard", 1 } })
  end)
end)

ns.Ext.dice.need = NEED
restore()
