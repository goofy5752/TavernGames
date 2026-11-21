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
