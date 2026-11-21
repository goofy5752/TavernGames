-- Regressions of the final Stage D review (C1, I1-I5): what a modified host
-- or guest tried there, and the honest flows that were wrongly blamed.
local Sim = require("sim")
local ns = Sim.ns
local E = ns.Engines.tabla
local Fair = ns.Fair

local A, B, W = "Иван Петров", "Мария Стоянова", "Гледач Гледачев"
local FAKE = "Иван Пeтров" -- a look-alike of A (a Latin e)
local SA = ("01"):rep(16)
local sim, a, b, w

-- A table of Табла hosted by a, watched by w, b in seat 2: seat 1 is on move with 4:4 (event 8).
local function table2(turn)
  sim = Sim.new()
  a = sim:add(A, { cls = "MAGE" })
  b = sim:add(B, { cls = "PRIEST" })
  w = sim:add(W, { cls = "DRUID" })
  sim:run(1)
  local tid = a:openTable{ game = "tabla", access = "guild", turn = turn or 45 }; sim:run(3)
  w:watch(tid); sim:run(1)
  b:sit(tid, 2); sim:run(1)
  return tid
end

-- The "fair" payloads that client emits from now on.
local function fairs(cl)
  local list = {}
  cl:on("fair", function(e) list[#list + 1] = e end)
  return list
end

-- A seed that gives `want` for throw h, alone or beside `other` (what a modified host does).
local function grind(tid, h, want, other)
  for i = 1, 100000 do
    local x = string.format("%032x", i)
    local d1, d2 = Fair.dice(other and { x, other } or { x }, Fair.handId(tid, h))
    if d1 == want[1] and d2 == want[2] then return x end
  end
end

-- A modified host: an event straight to B and W, not applied on A.
local function ev(sa, seat, act)
  sa.seq = sa.seq + 1
  for _, to in ipairs{ B, W } do
    a:send("WHISPER", to, ns.Session.message("EV", { tid = sa.tid, e = sa.epoch, q = sa.seq, seat = seat, a = act }))
  end
  sim:run(0)
end

-- The host throws 6:6 with two seeds of its own under the seats it wrote (opener: seat `d`).
local function bothSeeds(sa, tid, d)
  local h = sa.seq + 1
  local x = grind(tid, h, { 6, 6 }, SA)
  local seeds = d == 2 and { x, SA } or { SA, x }
  ev(sa, 0, { k = "throw", op = "open", h = h, c = Fair.commit(seeds[d]) })
  ev(sa, 0, { k = "throw", op = "commit", h = h, seat = 3 - d, c = Fair.commit(seeds[3 - d]) })
  ev(sa, 0, { k = "throw", op = "seeds", h = h, s = seeds })
  return h
end

describe("final review: the seats of a throw (C1)", function()
  it("a sit onto an occupied seat is refused by every client, in every game", function()
    local s2 = Sim.new()
    local x, y = s2:add(A, { cls = "MAGE" }), s2:add(B, { cls = "PRIEST" }); s2:run(1)
    local tid = x:openTable{ game = "ttt", access = "guild", turn = 45 }; s2:run(3); y:sit(tid, 2); s2:run(1)
    local desync = 0; y:on("desync", function() desync = desync + 1 end)
    eq(y.session:apply(0, { k = "sit", seat = 1, name = FAKE }), nil); eq(y.session.seats, { A, B })
    local sx = x.session
    x:send("WHISPER", B, ns.Session.message("EV", { tid = tid, e = sx.epoch, q = sx.seq + 1, seat = 0, a = { k = "sit", seat = 2, name = A } }))
    s2:run(0); eq({ desync, y.session.seats }, { 1, { A, B } })
    eq(y.session:apply(0, { k = "stand", seat = 2 }), true); eq(y.session:apply(0, { k = "sit", seat = 2, name = B }), true)   -- a free seat is taken as before
  end)

  it("a host that writes itself onto my seat and gives both seeds is red on my client, never green (fr3)", function()
    local tid = table2(); local atB, sa, bs = fairs(b), a.session, b.session
    local okBefore = bs.diceSeen.ok; sa:cancelTimers()
    ev(sa, 0, { k = "sit", seat = 1, name = FAKE }); ev(sa, 0, { k = "sit", seat = 2, name = A })
    eq(bs.seats, { A, B }); eq({ #atB >= 1, atB[1].verdict, atB[1].why }, { true, "bad", "forged" })
    for _ = 1, 4 do bothSeeds(sa, tid, 2) end
    local key, tone = ns.Dice.status(bs)
    eq({ tone, ns.Dice.alarm(bs), bs.diceSeen.ok <= okBefore, bs.diceSeen.bad >= 1 }, { "red", true, true, true }); ok(key ~= "dice.ok")
    for _, e in ipairs(atB) do ok(e.verdict ~= "ok") end
  end)

  it("a throw opened under my own seat number is forged: I never opened it (seats emptied and filled again)", function()
    local tid = table2(); local atB, sa, bs = fairs(b), a.session, b.session
    sa:cancelTimers()
    ev(sa, 0, { k = "stand", seat = 2 }); ev(sa, 0, { k = "sit", seat = 2, name = A })
    ev(sa, 0, { k = "stand", seat = 1 }); ev(sa, 0, { k = "sit", seat = 1, name = FAKE }); eq(bs.seats, { FAKE, A })
    ev(sa, 0, { k = "start" }); eq(#atB, 0)
    local h = bothSeeds(sa, tid, 2)
    eq({ #atB, atB[1].h, atB[1].verdict, atB[1].why }, { 1, h, "bad", "forged" })
    local key, tone = ns.Dice.status(bs); eq({ key, tone, ns.Dice.alarm(bs), bs.diceSeen.ok }, { "dice.bad", "red", true, 0 })
    eq(sim:count(function(m) return m.from == B and m.msg.t == "ACT" and m.msg.a.op == "seed" and m.msg.a.h == h end), 0)
  end)
end)

describe("final review: back to my seat after a /reload (I3)", function()
  local C = "Трети Играч"
  it("the host reloads, looks at another table while it waits, and is taken back by the new host: nobody forfeits (fr2)", function()
    local tid = table2()
    local c = sim:add(C, { cls = "ROGUE" }); sim:run(1)
    local other = c:openTable{ game = "ttt", access = "guild", turn = 45 }; sim:run(3)
    local a2 = sim:relog(A); sim:run(2); eq(a2.session, nil)
    a2:watch(other); sim:run(2); eq(a2.session.tid, other); a2:stand(); sim:run(1); eq(a2.session, nil)
    for _ = 1, 200 do if b.session.role == "host" then break end; sim:run(1) end
    sim:run(3); local s = a2.session
    eq({ s ~= nil and s.tid, s ~= nil and s.mySeat, b.session.seats, b.session.status, b.session.state.quit }, { tid, 1, { A, B }, "live", nil })
    eq(E.over(b.session.state), false)
  end)
  it("the guest reloads while its host is away, looks at another table, and gets its seat back", function()
    local tid = table2()
    local c = sim:add(C, { cls = "ROGUE" }); sim:run(1)
    local other = c:openTable{ game = "ttt", access = "guild", turn = 45 }; sim:run(3)
    sim:offline(A); local b2 = sim:relog(B); sim:run(2); eq(b2.session, nil)
    b2:watch(other); sim:run(2); b2:stand(); sim:run(1)
    sim:online(A); sim:run(125); local s = b2.session   -- my next HI tells the host I am not at its table
    eq({ s ~= nil and s.tid, s ~= nil and s.mySeat, a.session.seats, a.session.state.quit }, { tid, 2, { A, B }, nil })
  end)
  it("the table I am at is kept where a /reload keeps it; a table that was never mine is still refused", function()
    local tid = table2(); eq(sim.envs[B].db.lastAt, tid)
    b:stand(); sim:run(1); eq(sim.envs[B].db.lastAt, nil)
    local P = ns.Presence
    local p = P.new({ env = { db = { lastAt = "X#1" } } })
    eq({ p:mayReturn("X#1"), p:mayReturn("Y#2") }, { true, true })     -- been nowhere yet: the table a login finds me at
    p.been["Z#3"] = true; eq({ p:mayReturn("X#1"), p:mayReturn("Z#3"), p:mayReturn("Y#2") }, { true, true, false })
    eq(P.new({ env = {} }):mayReturn("X#1"), true)                     -- a bot's env has no db
  end)
end)

describe("final review: complaints (I5)", function()
  local function protest(h) b:send("WHISPER", A, ns.Session.message("ACT", { tid = a.session.tid, a = { k = "throw", op = "protest", h = h, why = "forged" } })); sim:run(0) end
  local function relayed() return sim:count(function(m) return m.target == W and m.msg.t == "EV" and m.msg.a.op == "protest" end) end

  it("a guest that keeps complaining does not stop its own clock: a 30 s turn times out on time (fr4)", function()
    table2(30); ok(a:act(E.auto(a.session.state, 1))); sim:run(1)
    local s = a.session; eq({ s.state.turn, s.state.phase, s:left() }, { 2, "move", 30 })
    sim:run(20); protest(3); eq({ relayed(), s:left(), b.session:left(), s.diceCry.h }, { 1, 10, 10, 3 })
    sim:run(5); protest(6); eq({ relayed(), s:left(), b.session:left() }, { 2, 5, 5 })
    sim:run(4); protest(3); protest(6); eq({ relayed(), s:left(), s.state.turn }, { 2, 1, 2 })
    sim:run(1); eq(s.state.turn, 1); eq(sim:count(function(m) return m.target == B and m.msg.t == "EV" and m.msg.auto == true end), 1)
  end)

  it("a complaint is passed on once per seat and throw, only for a throw number the table has reached, a handful a match", function()
    table2(); local s = a.session; local q = s.seq
    protest(6); protest(6); eq({ relayed(), s.seq }, { 1, q + 1 })
    protest(s.seq + 5); protest(0); protest(2.5); protest("6"); eq(relayed(), 1)
    for h = 1, s.seq do protest(h) end
    eq(relayed(), 5); eq(s.seq, q + 5)
    s:play(0, { k = "start" }); sim:run(1); protest(3); eq(relayed(), 6)   -- a new match: heard again
  end)
end)

describe("final review: seeds out of a secret pool (I4)", function()
  -- Every string in `v`, at any depth.
  local function strings(v, out, seen)
    out, seen = out or {}, seen or {}
    if type(v) == "string" then out[#out + 1] = v end
    if type(v) == "table" and not seen[v] then
      seen[v] = true
      for k, x in pairs(v) do strings(k, out, seen); strings(x, out, seen) end
    end
    return out
  end

  it("two clients with the same weak generator throw with seeds that differ, 32 hex each; no pool is in a message, a trace line or the saved variables", function()
    sim = Sim.new()
    local logged = {}
    local function add(name, cls)
      local env = sim:newEnv(name, { cls = cls }); sim:addFakes(env, {})
      env.realSeeds, env.log = true, function(...) logged[#logged + 1] = { ... } end
      return sim:join(name, env)
    end
    -- What the pools are: the text every seed is hashed from (pool|counter|purpose).
    local pools, hex = {}, ns.Sha256.hex
    ns.Sha256.hex = function(text)
      local pool = text:match("^(%x+)|%d+|dice|")
      if pool then pools[pool] = true end
      return hex(text)
    end
    local done, err = pcall(function()
      a, b, w = add(A, "MAGE"), add(B, "PRIEST"), add(W, "DRUID"); sim:run(1)
      local tid = a:openTable{ game = "tabla", access = "guild", turn = 30 }; sim:run(3)
      w:watch(tid); sim:run(1); b:sit(tid, 2); sim:run(200)
    end)
    ns.Sha256.hex = hex; if not done then error(err, 0) end
    local seeds, n = {}, 0
    for _, m in ipairs(sim.sent) do
      local x = m.msg.t == "EV" and m.target == W and m.msg.a
      if x and x.op == "seeds" then
        for seat = 1, 2 do
          local seed = x.s[seat]; ok(#seed == 32 and not seed:find("[^0-9a-f]"), seed)
          ok(not seeds[seed], "a seed came twice"); seeds[seed], n = true, n + 1
        end
      end
    end
    ok(n >= 12, tostring(n)); eq(b.session.state, a.session.state); eq(b.session.diceSeen.bad + b.session.diceSeen.alone, 0)
    local count = 0
    for pool in pairs(pools) do count = count + 1; eq(#pool, 64) end
    eq(count, 2)                                                       -- one pool a client that throws
    local said = strings({ sim.sent, logged, sim.envs[A].db, sim.envs[B].db })
    ok(#said > 100)
    for _, text in ipairs(said) do
      for pool in pairs(pools) do ok(not text:find(pool, 1, true), "a pool left the client") end
    end
  end)
end)

describe("final review: my own loading screen (I2)", function()
  -- The seat on move moves (the host plays for a guest that is away), which opens the next throw.
  local function move()
    for _ = 1, 100 do if a.session.state.phase == "move" and ns.Util.same(a.session.state, b.session.state) then break end; sim:run(1) end
    local st = a.session.state
    if st.turn == 1 then ok(a:act(E.auto(st, 1))) else a.session:play(2, E.auto(st, 2), true) end
  end
  local function tipKeys(s)
    local out = {}
    for _, t in ipairs(ns.Dice.tip(s)) do out[t[2]] = t[3] or true end
    return out
  end

  it("throws the host made alone while my messages waited behind my loading screen are not held against it (fr1)", function()
    table2(); local atB = fairs(b)
    for _ = 1, 2 do
      local held, recv = {}, b.receive
      sim:loading(B, true); b.receive = function(_, ch, sender, msg) held[#held + 1] = { ch, sender, msg } end
      move(); sim:run(12)
      b.receive = recv; sim:loading(B, false)
      for _, m in ipairs(held) do b:receive(m[1], m[2], m[3]) end
      sim:run(5)
    end
    local s = b.session; local key, tone = ns.Dice.status(s)
    eq({ s.diceUnheard, s.diceAway, ns.Dice.alarm(s), s.diceSeen.bad, s.diceSeen.alone }, { nil, 2, false, 0, 2 }); ok(tone ~= "red", tostring(key))
    eq(s.state, a.session.state); for _, e in ipairs(atB) do ok(e.verdict ~= "bad") end
    local tip = tipKeys(s); eq({ tip["dice.away"], tip["dice.unheard"] }, { 2, nil })
  end)

  it("throws whose messages my loading screen lost are not held against the host either (fr2)", function()
    table2()
    for _ = 1, 2 do
      sim:loading(B, true); sim:offline(B); move(); sim:run(12)
      sim:online(B); sim:loading(B, false); sim:run(40)
    end
    local s = b.session
    eq({ s.diceUnheard, ns.Dice.alarm(s), s.diceSeen.bad }, { nil, false, 0 }); ok(s.diceAway >= 1); eq(s.state, a.session.state)
    ok(select(2, ns.Dice.status(s)) ~= "red")
  end)

  it("a loading screen that was over before the throw excuses nothing: a host that throws without me is counted", function()
    table2(); local s = b.session
    sim:loading(B, true); sim:run(2); sim:loading(B, false)
    for _ = 1, 2 do
      local env = sim.envs[B]; local send = env.send
      env.send = function(channel, target, msg)                        -- my commit never arrives; my client believes it sent it
        if msg.t == "ACT" and msg.a.k == "throw" then return end
        return send(channel, target, msg)
      end
      sim:run(12); move(); sim:run(12); env.send = send
    end
    eq({ s.diceUnheard, s.diceAway, ns.Dice.alarm(s) }, { 2, nil, true })
    local tip = tipKeys(s); eq({ tip["dice.unheard"], tip["dice.away"] }, { 2, nil })
  end)

  it("the tooltip no longer says I was in time; both languages have the new line", function()
    for _, lang in ipairs{ "bg", "en" } do
      ns.Locale.set(lang)
      local text = ns.L("dice.unheard", 2); ok(not text:find("in time") and not text:find("навреме"), text)
      ok(ns.L("dice.away", 2):find("2", 1, true))
    end
    ns.Locale.set("bg")
  end)
end)

describe("final review: a match I walk into (I1)", function()
  it("a new table of the same host that takes me into a running match: its dice are unseen for me, never ok; my first whole throw is (fr1)", function()
    local tid = table2(); local atB, sa = fairs(b), a.session
    sa:cancelTimers(); a:send("GUILD", nil, ns.Session.message("END", { tid = tid, e = sa.epoch }))
    local nt = A .. "#1700000777"                                     -- the modified host rebrands its table at once
    sa.tid, sa.seats[2], sa.seq = nt, false, sa.seq + 5; a.lobby:remove(tid); sim:run(1); eq(b.session, nil)
    sa.lastAnnounce = nil; sa:sendTBL(); sim:run(3); ok(b.lobby:get(nt) ~= nil)
    b:sit(nt, 2)                                                       -- an honest click; the answer is made by hand
    sa.seats[2] = B
    local st, h = sa.state, sa.seq - 1
    local x = grind(nt, h, { 6, 6 })
    st.dice, st.left, st.cv, st.xfer, st.phase, st.turn = { 6, 6 }, { 6, 6, 6, 6 }, nil, nil, "move", 1
    sa.diceProof, sa.throw = { h = h, c = { Fair.commit(x) }, s = { x }, r = 1, t = st.rolls[1] }, nil
    sa:snapshotTo(B); sim:run(1); local s = b.session
    eq({ s.tid, s.mySeat, s.status, s.state.dice }, { nt, 2, "live", { 6, 6 } })
    eq({ ns.Dice.status(s) }, { "dice.unseen", "gold" }); eq({ #atB, atB[1].h, atB[1].verdict }, { 1, h, "unseen" }); eq(s.diceSeen.ok, 0)
    ns.Succession.track(sa, B); ok(a:act(E.auto(sa.state, 1))); sim:run(2)   -- the next throw I see from its open
    eq({ ns.Dice.status(s) }, { "dice.ok", "good" }); eq({ #atB, atB[2].verdict, s.diceSeen.ok, ns.Dice.alarm(s) }, { 2, "ok", 1, false })
  end)

  it("a watcher that joins a running match: the dice on the board and a throw already open are unseen, the next throw is ok", function()
    local tid = table2(); local X = "Нов Гледач"
    local x = sim:add(X, { cls = "ROGUE" }); sim:run(1)
    local env, on = sim.envs[B], true; local send = env.send
    env.send = function(channel, target, msg)                           -- B's seed is late: the throw stays open
      if on and msg.t == "ACT" and msg.a.op == "seed" then return end
      return send(channel, target, msg)
    end
    ok(a:act(E.auto(a.session.state, 1))); sim:run(1); eq(a.session.throw.done, nil)
    local atX = fairs(x); x:watch(tid); sim:run(1); local s = x.session
    eq({ s.role, s.throw.h, s.throw.late }, { "watcher", a.session.throw.h, true })
    eq({ #atX, atX[1].verdict, s.diceLast.verdict }, { 1, "unseen", "unseen" }); eq({ ns.Dice.status(s) }, { "dice.rolling", "inkDim" })
    on = false; sim:run(4); eq(a.session.throw.done, true)
    eq({ ns.Dice.status(s) }, { "dice.unseen", "gold" }); eq({ #atX, atX[2].verdict, b.session.diceLast.verdict }, { 2, "unseen", "ok" })
    ok(b:act(E.auto(b.session.state, 2))); sim:run(2)
    eq({ ns.Dice.status(s) }, { "dice.ok", "good" }); eq({ atX[3].verdict, s.diceSeen.ok, ns.Dice.alarm(s) }, { "ok", 1, false }); eq(s.state, a.session.state)
  end)

  it("a seat taken at a table that has not started, and a login back to my seat, are as before: no amber line", function()
    table2(); eq({ ns.Dice.status(b.session) }, { "dice.ok", "good" }); eq(b.session.diceSeen, { ok = 2, alone = 0, bad = 0 })
    local b2 = sim:crash(B); sim:run(3); local s = b2.session
    eq({ s ~= nil and s.mySeat, s.diceLast, ns.Dice.status(s) }, { 2, nil, nil })
  end)
end)

describe("final review: my dice records of tables that are gone (M6)", function()
  it("a record is dropped once its table has been gone for DICE_KEEP seconds; a table still listed keeps its record", function()
    local t1 = table2(); ok(b.dice[t1] ~= nil)
    b:stand(); sim:run(1); a:stand(); sim:run(3); eq({ a.session, b.lobby:get(t1) }, { nil, nil }); ok(b.dice[t1] ~= nil)
    local t2 = a:openTable{ game = "tabla", access = "guild", turn = 45 }; sim:run(3); b:sit(t2, 2); sim:run(2)
    ok(b.dice[t1] ~= nil and b.dice[t2] ~= nil)                        -- gone, but not for long: it may still come back
    b:stand(); sim:run(ns.Const.DICE_KEEP + 1)                         -- t2 lives on under A
    local c = sim:add("Трети Играч", { cls = "ROGUE" }); sim:run(1)
    local t3 = c:openTable{ game = "tabla", access = "guild", turn = 45 }; sim:run(3); b:sit(t3, 2); sim:run(2)
    eq({ b.dice[t1], b.dice[t2] ~= nil, b.dice[t3] ~= nil, b.lobby:get(t2) ~= nil }, { nil, true, true, true })
    -- A host's records go the same way, when it writes the first record of its next dice table.
    a:stand(); sim:run(ns.Const.DICE_KEEP + 1); ok(a.dice[t1] ~= nil and a.dice[t2] ~= nil)
    local t4 = a:openTable{ game = "tabla", access = "guild", turn = 45 }; sim:run(3)
    b:stand(); sim:run(1); b:sit(t4, 2); sim:run(2); eq({ a.dice[t1], a.dice[t2], a.dice[t4] ~= nil }, { nil, nil, true })
  end)
end)
