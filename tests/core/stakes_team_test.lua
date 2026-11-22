local Sim = require("sim")
local Play = require("play")
local ns = Sim.ns
local C, View = ns.Const, ns.LedgerView
local Stakes = ns.Stakes

local restore = Play.staked("santase", "belot", "tabla")

local I, P, M, G = Play.NAMES[1], Play.NAMES[2], Play.NAMES[3], Play.NAMES[4]
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

-- The debts of client's ledger at gid.
local function debtsAt(client, gid)
  local out = {}
  for _, d in ipairs(View.of(client.ledger).debts) do if d.gid == gid then out[#out + 1] = d end end
  return out
end

-- Does any debt on any client name `who` as debtor or creditor (at gid, when given)?
local function named(sim, who, gid)
  for _, c in pairs(sim.clients) do
    for _, d in ipairs(View.of(c.ledger).debts) do
      if (gid == nil or d.gid == gid) and (d.f == who or d.t == who) then return true end
    end
  end
  return false
end

local function sorted(list)
  local out = {}
  for i, v in ipairs(list) do out[i] = v end
  table.sort(out)
  return out
end

-- A staked Белот under Петър: Иван in seat 2, Гошо in 3, Мария in 4 (Иван and Мария are partners).
local function petar(sim, cl)
  local tid = assert(cl[P]:openTable{ game = "belot", access = "guild", turn = 45, stake = SK }); sim:run(3)
  cl[I]:sit(tid, 2, SK); sim:run(1)
  cl[G]:sit(tid, 3, SK); sim:run(1)
  cl[M]:sit(tid, 4, SK); sim:run(1)
  eq(cl[P].session.status, "live"); eq(ns.Engines.belot.partner(2), 4)
  return tid
end

-- Иван and Мария both press „Стани“ at once under Петър -> the first (whose stand the host ordered), the other, gid.
local function race(sim, cl, tid)
  for _ = 1, 4 do Play.step(sim, cl[P]) end
  local seen = record(cl[P], "forfeit")
  cl[I]:stand(); cl[M]:stand(); sim:run(5)
  eq(#seen, 1)
  local first = seen[1][1].name
  return first, first == I and M or I, tid .. "/" .. seen[1][1].q
end

describe("stakes: who owes whom in Сантасе, Белот and Табла", function()
  it("Stakes.matched pairs by position; Stakes.pairs is unchanged", function()
    eq(Stakes.matched({ "L1", "L2" }, { "W1", "W2" }, 100), { { f = "L1", t = "W1", c = 100 }, { f = "L2", t = "W2", c = 100 } })
    eq(#Stakes.pairs({ "L1", "L2" }, { "W1", "W2" }, 100), 4)
    eq(Stakes.matched({ "L1", "L2" }, { "W1" }, 100), { { f = "L1", t = "W1", c = 100 } })
  end)

  it("E.partner and the worst case", function()
    local E = ns.Engines.belot
    eq(E.partner(1), 3); eq(E.partner(2), 4); eq(E.partner(3), 1); eq(E.partner(4), 2)
    eq(ns.Engines.santase.partner, nil); eq(ns.Engines.tabla.partner, nil)
    eq(ns.Stake.worst("belot", 10000), 20000); eq(ns.Stake.worst("santase", 10000), 10000); eq(ns.Stake.worst("tabla", 10000), 10000)
  end)

  it("belot: the losers pay the winners in two transfers, not four", function()
    local back = Play.short("belot")
    local sim, cl = Play.guild(4)
    local tid = Play.open(sim, cl, "belot", SK, 4)
    local r = Play.finish(sim, cl[I])
    back()
    local gid = tid .. "/" .. r.q
    sim:run(5)
    local L, W = sorted(r.losers), sorted(r.winners)
    local names = cl[I].session.seats
    for _, c in pairs(cl) do
      eq(#debtsAt(c, gid), 2)
      for i = 1, 2 do
        local d = Play.debt(c, gid, names[L[i]], names[W[i]])
        ok(d, "a debt of the loser of the " .. i .. ". lower seat")
        eq({ d.c, d.status }, { SK, "confirmed" })
      end
    end
    eq(#at(sim, nil, "D", gid), 2)
    local rs = at(sim, nil, "R", gid)
    eq(#rs, 1); eq(Play.entries(sim, I, "R")[1].gid, gid)
    eq({ rs[1].w, rs[1].l, rs[1].why }, { r.winners, r.losers, nil })
  end)

  it("belot: a leaver pays both opponents and the partner nothing", function()
    local sim, cl = Play.guild(4)
    local tid = Play.open(sim, cl, "belot", SK, 4)
    for _ = 1, 4 do Play.step(sim, cl[I]) end
    local seen = record(cl[I], "forfeit")
    cl[M]:stand(); sim:run(5)
    eq(#seen, 1)
    local gid = tid .. "/" .. seen[1][1].q
    eq(cl[M].env.db.stakeLeft[tid].names, { P, G }); eq(cl[M].env.db.stakeLeft[tid].g, "belot")
    for _, name in ipairs({ P, G }) do
      local d = Play.debt(cl[name], gid, M, name)
      ok(d, "a debt to " .. name); eq({ d.c, d.status }, { SK, "confirmed" })
    end
    ok(not named(sim, I), "the partner owes nothing and is owed nothing")
    local rs, ds = at(sim, nil, "R", gid), at(sim, nil, "D", gid)
    eq(#rs, 1); eq({ rs[1].l, rs[1].w, rs[1].why }, { { 3 }, { 2, 4 }, "left" })
    eq(#ds, 2)
    for _, d in ipairs(ds) do eq({ d.f, d.why, d.c }, { M, "left", SK }) end
  end)

  it("belot: both partners stand at once: one leaver, two debts", function()
    local sim, cl = Play.guild(4)
    local tid = petar(sim, cl)
    local first, other, gid = race(sim, cl, tid)
    for _, name in ipairs({ P, G }) do
      local d = Play.debt(cl[name], gid, first, name)
      ok(d, "a debt to " .. name); eq({ d.c, d.status }, { SK, "confirmed" })
    end
    ok(not named(sim, other), "the one whose stand lost the race owes nothing")
    local note = cl[other].env.db.stakeSeen[gid]
    ok(note, "its own note of the forfeit that never happened")
    eq(cl[other].stakes:asks(), {})
    sim:run(C.STAKE_OWE_WAIT + 5)
    eq(#Play.entries(sim, other, "D"), 0); eq(#Play.entries(sim, other, "C"), 0)
    ok(not named(sim, other))
    eq(#at(sim, nil, "R", gid), 1); eq(#at(sim, nil, "D", gid), 2)
  end)

  it("belot: both partners stand at once: a forged claim against the one whose stand lost the race is asked, never confirmed", function()
    for _, held in ipairs({ false, true }) do
      local sim, cl = Play.guild(4)
      local tid = petar(sim, cl)
      local victim
      if not held then -- the R never reaches her (nor any other ledger message) until the end of the case
        sim.bus.filter = function(_, to, _, m)
          if to == victim and (m.t == "LEV" or m.t == "LVC" or m.t == "LID") then return {} end
          return { m }
        end
        victim = M -- Петър orders Иван's STD first: it was sent first
      end
      local first, other, gid = race(sim, cl, tid)
      eq({ first, other }, { I, M })
      local left = cl[other].env.db.stakeLeft[tid]
      ok(left and left.sk == SK and ns.Util.contains(left.names, G))
      local mark = #sim.sent
      local e = cl[G].ledgerNet:make("D", { gid = gid, g = "belot", f = other, t = G, c = SK, why = "left" })
      if not held then eq(cl[other].ledgerNet:take(e, G, true), "new") end
      sim:run(3)
      local key = gid .. "|" .. other .. "|" .. G
      if held then
        eq(#at(sim, nil, "R", gid), 1)
        local asks = cl[other].stakes:asks()
        eq(#asks, 1); eq(asks[1].key, key)
      else
        eq(cl[other].stakes:asks(), {}) -- no R of that game yet: it waits
        local asked = record(cl[other], "debtAsk")
        sim:run(C.STAKE_OWE_WAIT)
        eq(#asked, 1) -- the wait ends by itself: no ledger news reaches her meanwhile
        local asks = cl[other].stakes:asks()
        eq(#asks, 1); eq(asks[1].key, key)
      end
      for i = mark + 1, #sim.sent do
        local m = sim.sent[i]
        if m.from == other and m.msg.t == "LEV" then
          for _, x in ipairs(m.msg.ev) do ok(x.k ~= "C" and x.k ~= "D", "no word of the victim's") end
        end
      end
      sim.bus.filter = nil
      -- The first partner's own claims got their C: the single R names its seat.
      sim:run(3)
      for _, name in ipairs({ P, G }) do eq(Play.debt(cl[name], gid, first, name).status, "confirmed") end
      eq(Play.debt(cl[P], gid, other, G).status, "pending")
    end
  end)

  it("belot: an opponent's forged R and D against the race loser are never confirmed: only the host's R counts", function()
    local sim, cl = Play.guild(4)
    local tid = petar(sim, cl)
    sim.bus.filter = function(_, to, _, m) -- the honest host's R does not reach her until the end
      if to == M and (m.t == "LEV" or m.t == "LVC" or m.t == "LID") then return {} end
      return { m }
    end
    local first, other, gid = race(sim, cl, tid)
    eq({ first, other }, { I, M })
    eq(cl[M].env.db.stakeLeft[tid].h, P)
    -- Гошо, no host, forges an R naming Мария's seat (4) alone, and a D Мария -> Гошо.
    local r = cl[G].ledgerNet:make("R", { gid = gid, g = "belot", n = { P, I, G, M }, w = { 1, 3 }, l = { 4 }, sk = SK, why = "left" })
    local d = cl[G].ledgerNet:make("D", { gid = gid, g = "belot", f = M, t = G, c = SK, why = "left" })
    ok(r and d)
    eq(cl[M].ledgerNet:take(r, G, true), "new"); eq(cl[M].ledgerNet:take(d, G, true), "new")
    local mark = #sim.sent
    sim:run(3)
    eq(cl[M].stakes:asks(), {}) -- no R of Петър's yet: it waits
    sim:run(C.STAKE_OWE_WAIT)
    local asks = cl[M].stakes:asks()
    eq(#asks, 1); eq(asks[1].key, gid .. "|" .. M .. "|" .. G)
    sim.bus.filter = nil
    sim:run(5)
    for i = mark + 1, #sim.sent do
      local m = sim.sent[i]
      if m.from == M and m.msg.t == "LEV" then
        for _, x in ipairs(m.msg.ev) do ok(x.k ~= "C" and x.k ~= "D", "no word of the victim's") end
      end
    end
    eq(Play.debt(cl[P], gid, M, G).status, "pending")
    eq(#cl[M].stakes:asks(), 1)
  end)

  it("belot: a claim from the wrong winner of a clean match is contested", function()
    local back = Play.short("belot")
    local sim, cl = Play.guild(4)
    local tid = Play.open(sim, cl, "belot", SK, 4)
    local r = Play.finish(sim, cl[I])
    back()
    sim:run(5)
    local gid, names = tid .. "/" .. r.q, cl[I].session.seats
    local L, W = sorted(r.losers), sorted(r.winners)
    local loser, wrong = names[L[1]], names[W[2]]
    local mark = #sim.sent
    local e = cl[wrong].ledgerNet:make("D", { gid = gid, g = "belot", f = loser, t = wrong, c = SK, why = "lost" })
    sim:run(5)
    local words = {}
    for i = mark + 1, #sim.sent do
      local m = sim.sent[i]
      if m.from == loser and m.channel == "GUILD" and m.msg.t == "LEV" then
        for _, x in ipairs(m.msg.ev) do if x.r == e.i then words[#words + 1] = x end end
      end
    end
    eq(#words, 1); eq({ words[1].k, words[1].why }, { "N", "no" })
    eq(cl[loser].stakes:asks(), {})
    eq(Play.debt(cl[P], gid, loser, wrong).status, "contested")
    eq(Play.debt(cl[P], gid, loser, names[W[1]]).status, "confirmed")
  end)

  it("belot: a claim from the leaver's partner is contested", function()
    local sim, cl = Play.guild(4)
    local tid = Play.open(sim, cl, "belot", SK, 4)
    for _ = 1, 4 do Play.step(sim, cl[I]) end
    local seen = record(cl[I], "forfeit")
    cl[M]:stand(); sim:run(5)
    local gid = tid .. "/" .. seen[1][1].q
    cl[I].ledgerNet:make("D", { gid = gid, g = "belot", f = M, t = I, c = SK, why = "left" }); sim:run(5)
    local n = {}
    for _, x in ipairs(Play.entries(sim, M, "N")) do n[#n + 1] = x end
    eq(#n, 1); eq(n[1].why, "no")
    eq(Play.debt(cl[P], gid, M, I).status, "contested"); eq(cl[M].stakes:asks(), {})
  end)

  it("belot: the leaver's partner then stands: it costs nothing", function()
    local sim, cl = Play.guild(4)
    Play.open(sim, cl, "belot", SK, 4)
    for _ = 1, 4 do Play.step(sim, cl[I]) end
    cl[M]:stand(); sim:run(5)
    local r, d = #Play.entries(sim, nil, "R"), #Play.entries(sim, nil, "D")
    eq({ r, d }, { 1, 2 })
    cl[I]:stand(); sim:run(C.STAKE_OWE_WAIT + 5)
    eq({ #Play.entries(sim, nil, "R"), #Play.entries(sim, nil, "D") }, { 1, 2 })
    ok(not named(sim, I))
  end)

  it("belot: three minutes offline is a leave: the debts wait for the leaver", function()
    local sim, cl = Play.guild(4)
    local tid = Play.open(sim, cl, "belot", SK, 4)
    for _ = 1, 4 do Play.step(sim, cl[I]) end
    local seen = record(cl[I], "forfeit")
    sim.envs[G].dead = true; sim:offline(G) -- his client is gone (a disconnect)
    sim:run(C.OFFLINE_STAND_SECONDS + C.SILENT_AFTER)
    eq(#seen, 1)
    local gid = tid .. "/" .. seen[1][1].q
    for _, name in ipairs({ I, M }) do
      local d = Play.debt(cl[I], gid, G, name)
      ok(d, "a debt to " .. name); eq(d.status, "pending")
    end
    for _, x in ipairs(at(sim, nil, "D", gid)) do eq({ x.f, x.why }, { G, "offline" }) end
    ok(not named(sim, P), "the partner owes nothing and is owed nothing")
    local g = sim:relog(G); sim:settle()
    for _ = 1, 90 do if #g.stakes:asks() == 2 then break end; sim:run(1) end
    local asks = g.stakes:asks()
    eq(#asks, 2)
    for _, d in ipairs(asks) do ok(g.stakes:answer(d.key, true)) end
    sim:run(5)
    for _, name in ipairs({ I, M }) do eq(Play.debt(cl[P], gid, G, name).status, "confirmed") end
  end)

  it("santase: one outcome for a leave, not two", function()
    local sim, cl = Play.guild(2)
    local tid = Play.open(sim, cl, "santase", SK, 2)
    for _ = 1, 3 do Play.step(sim, cl[I]) end
    local seen = record(cl[I], "forfeit")
    cl[P]:stand(); sim:run(5)
    eq(#seen, 1)
    local gid = tid .. "/" .. seen[1][1].q
    local notes = 0
    for _, n in pairs(cl[I].env.db.stakeSeen) do if n.tid == tid then notes = notes + 1 end end
    eq(notes, 1); eq(cl[I].env.db.stakeSeen[gid].why, "left")
    local ds, rs = at(sim, nil, "D", gid), at(sim, nil, "R", gid)
    eq(#ds, 1); eq({ ds[1].f, ds[1].t, ds[1].why }, { P, I, "left" })
    eq(#rs, 1); eq({ rs[1].l, rs[1].w, rs[1].why }, { { 2 }, { 1 }, "left" })
    eq(#Play.entries(sim, nil, "D"), 1); eq(#Play.entries(sim, nil, "R"), 1)
    eq(Play.debt(cl[I], gid, P, I).status, "confirmed")
  end)

  it("santase: a forfeit during the first shuffle", function()
    local sim, cl = Play.guild(2)
    local tid = assert(cl[I]:openTable{ game = "santase", access = "guild", turn = 45, stake = SK }); sim:run(3)
    local seen = record(cl[I], "forfeit")
    sim.bus.filter = function(from, _, _, m) -- Петър's part of the shuffle is late
      if from == P and m.t == "ACT" and type(m.a) == "table" and m.a.k == "fair" then return {} end
      return { m }
    end
    cl[P]:sit(tid, 2, SK); sim:run(1)
    local s = cl[I].session
    eq(s.status, "live"); ok(s.fair and s.fair.stage ~= "dealt", "the first deal is not dealt yet")
    cl[P]:stand(); sim.bus.filter = nil; sim:run(5)
    eq(#seen, 1)
    local gid = tid .. "/" .. seen[1][1].q
    local ds = at(sim, nil, "D", gid)
    eq(#ds, 1); eq({ ds[1].f, ds[1].t, ds[1].why }, { P, I, "left" })
    eq(#at(sim, nil, "R", gid), 1)
    eq(Play.debt(cl[I], gid, P, I).status, "confirmed")
    local note = cl[P].env.db.stakeSeen[gid]
    ok(note); eq(note.wait, nil)
  end)

  it("tabla: the host leaves mid-match and its successor writes the R", function()
    local sim, cl = Play.guild(2)
    local tid = Play.open(sim, cl, "tabla", SK, 2)
    for _ = 1, 6 do Play.step(sim, cl[I]) end
    sim.bus.filter = function(from, _, _, m) -- Петър's commit of the next throw is late
      if from == P and m.t == "ACT" and type(m.a) == "table" and m.a.k == "throw" then return {} end
      return { m }
    end
    for _ = 1, 40 do
      local t = cl[I].session.throw
      if t and not t.done then break end
      Play.step(sim, cl[I])
    end
    local t = cl[I].session.throw
    ok(t and not t.done, "a throw is open")
    cl[I]:stand(); sim.bus.filter = nil; sim:run(5)
    eq(cl[P].session.role, "host")
    local rs = Play.entries(sim, P, "R")
    eq(#rs, 1); eq({ rs[1].l, rs[1].w, rs[1].why }, { { 1 }, { 2 }, "left" })
    local ds = Play.entries(sim, P, "D")
    eq(#ds, 1); eq({ ds[1].gid, ds[1].f, ds[1].t, ds[1].why }, { rs[1].gid, I, P, "left" })
    eq(#Play.entries(sim, I, "R"), 0); eq(#Play.entries(sim, I, "C"), 1)
    eq(Play.debt(cl[P], rs[1].gid, I, P).status, "confirmed")
    ok(rs[1].gid:find(tid, 1, true) == 1)
  end)

  it("a fun table of each game writes its R as before", function()
    for _, g in ipairs({ { "santase", 2, nil, { 1 }, { 2 } }, { "belot", 4, "left", { 1, 3 }, { 2, 4 } }, { "tabla", 2, "left", { 1 }, { 2 } } }) do
      local sim, cl = Play.guild(g[2])
      local tid = Play.open(sim, cl, g[1], nil, g[2])
      for _ = 1, 3 do Play.step(sim, cl[I]) end
      cl[P]:stand(); sim:run(5)
      local rs = Play.entries(sim, I, "R")
      eq(#rs, 1, g[1]); eq({ rs[1].g, rs[1].w, rs[1].l, rs[1].why, rs[1].sk }, { g[1], g[4], g[5], g[3], nil })
      ok(rs[1].gid:find(tid, 1, true) == 1)
      eq(#Play.entries(sim, nil, "D"), 0)
    end
  end)
end)

restore()
