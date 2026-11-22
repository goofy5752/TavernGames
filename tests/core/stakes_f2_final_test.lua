-- The findings of the final review of stage F2 (Ruling F2-F): what a modified
-- host could make an honest client confirm by itself, and no longer can.
local Sim = require("sim")
local Play = require("play")
local ns = Sim.ns
local C, View = ns.Const, ns.LedgerView

local I, P, M, G = Play.NAMES[1], Play.NAMES[2], Play.NAMES[3], Play.NAMES[4]
local SK = 50000

-- The GUILD entries of kind k (C or N) `from` sent about a D at gid.
local function wordsAt(sim, from, k, gid)
  local ds, out = {}, {}
  for _, d in ipairs(Play.entries(sim, nil, "D")) do if d.gid == gid then ds[d.i] = true end end
  for _, e in ipairs(Play.entries(sim, from, k)) do if ds[e.r] then out[#out + 1] = e end end
  return out
end

-- Is the debt gid|f|t among client's asks()?
local function asked(client, gid, f, t)
  for _, d in ipairs(client.stakes:asks()) do
    if d.gid == gid and d.f == f and d.t == t then return true end
  end
  return false
end

-- A staked Белот table that Петър hosts from seat 2: seat 1 Иван, seat 3 Гошо
-- (partners), seat 4 Мария (the host's partner) -> sim, cl, tid.
local function petarHosts()
  local sim, cl = Play.guild(4)
  local tid = assert(cl[I]:openTable{ game = "belot", access = "guild", turn = 45, stake = SK }); sim:run(3)
  cl[P]:sit(tid, 2, SK); sim:run(1)
  cl[I]:stand(); sim:run(3)
  cl[I]:sit(tid, 1, SK); sim:run(1)
  cl[G]:sit(tid, 3, SK); sim:run(1)
  cl[M]:sit(tid, 4, SK); sim:run(1)
  eq({ cl[P].session.role, cl[P].session.status, cl[P].session.seats }, { "host", "live", { I, P, G, M } })
  return sim, cl, tid
end

-- Петър's match is played to its end; each step, before(steps) may act
-- instead of the seat on turn (-> true) -> the last "result", the steps taken.
local function play(sim, host, before)
  local last, steps = nil, 0
  host:on("result", function(r) last = r end)
  for _ = 1, 30000 do
    if host.session:gameOver() then return last, steps end
    steps = steps + 1
    if not (before and before(steps)) then Play.step(sim, host) end
  end
  error("the match did not end")
end

describe("stakes: the final review of F2", function()
  it("belot: the host voids a hand my partner dealt: my loss is put to me, the dealer contests (C1)", function()
    for n = 1, 2 do -- the first such hand is Иван's deal, the second Гошо's
      local sim, cl, tid = petarHosts()
      local host, seen, count, dealer = cl[P], {}, 0, nil
      local r = play(sim, host, function()
        local s = host.session
        local f = s.fair
        if not (f and f.stage == "dealt" and (f.d == 1 or f.d == 3) and s.state.turn and not seen[f.h]) then return false end
        seen[f.h], count = true, count + 1
        if count ~= n then return false end
        local q = s.seq
        s:play(0, { k = "void" })
        ok(s.seq > q, "the void is played")
        dealer = s.seats[f.d]
        sim:run(1)
        return true
      end)
      sim:run(C.STAKE_FAIR_WAIT + C.STAKE_OWE_WAIT + 10)
      eq(r.losers, { 1, 3 }) -- Иван and Гошо lose: Иван owes Петър, Гошо owes Мария
      local gid, partner = tid .. "/" .. r.q, dealer == I and G or I
      local owedBy = { [I] = P, [G] = M }
      eq(#wordsAt(sim, dealer, "N", gid), 1); eq(wordsAt(sim, dealer, "N", gid)[1].why, "deal")
      eq(#wordsAt(sim, partner, "C", gid), 0); eq(#wordsAt(sim, partner, "N", gid), 0)
      ok(asked(cl[partner], gid, partner, owedBy[partner]), "the partner's debt is put to it")
      eq(Play.debt(cl[P], gid, partner, owedBy[partner]).status, "pending")
    end
  end)

  -- Сантасе at Иван's table: the event that ends match 1 never reaches the guest Петър; a snapshot
  -- of the game over does ("pushed" by the host, or "asked" for by the guest's own tick) -> sim, cl, tid, host, guest.
  local function endedBySnapshot(mode)
    Play.short("santase")
    local sim, cl = Play.guild(2)
    local tid = Play.open(sim, cl, "santase", SK, 2)
    local host, guest = cl[I], cl[P]
    sim.bus.filter = function(_, to, _, m)
      if to == P and m.t == "EV" and host.session and host.session:gameOver() then return {} end
      return { m }
    end
    Play.finish(sim, host)
    sim.bus.filter = nil
    eq(guest.session:gameOver(), false)
    if mode == "pushed" then host.session:snapshotTo(P); sim:run(0) end
    for _ = 1, 40 do
      if guest.session:gameOver() then break end
      sim:run(1) -- the guest's own tick asks for it
    end
    ok(guest.session:gameOver(), "the snapshot brought the end")
    return sim, cl, tid, host, guest
  end
  local function start(sim, host, first)
    host.session:event(0, { k = "start", first = first }); host.session:recordChanged(); sim:run(0)
  end

  it("a match that a snapshot ended for me: a start inside the break by my clock is a question (C2)", function()
    local lost = 0
    for _, mode in ipairs({ "pushed", "asked" }) do
      for first = 1, 2 do
        local sim, cl, tid, host, guest = endedBySnapshot(mode)
        ok(guest.session.stakeEndedAt > sim.clock - 1, "dated by my clock, at the snapshot's arrival"); eq(guest.session.stakeEndSnap, true)
        sim:run(1)
        start(sim, host, first)
        eq({ guest.session.stakeLive, guest.session.stakeFoul }, { true, "unseen" })
        local r2 = Play.finish(sim, host)
        Play.restore()
        sim:run(C.STAKE_FAIR_WAIT + C.STAKE_OWE_WAIT + 10)
        if host.session.seats[r2.losers[1]] == P then
          local gid = tid .. "/" .. r2.q
          lost = lost + 1
          eq(#wordsAt(sim, P, "C", gid), 0); eq(#wordsAt(sim, P, "N", gid), 0)
          ok(asked(guest, gid, P, I), "the second match's debt is put to the guest")
          eq(Play.debt(host, gid, P, I).status, "pending")
        end
      end
    end
    ok(lost > 0, "the guest never lost the second match")
  end)

  it("a match that a snapshot ended for me: a start after the break by my clock is clean (C2)", function()
    for _, late in ipairs({ 0, -1 }) do
      local sim, _, _, host, guest = endedBySnapshot("asked")
      local from = guest.session.stakeEndedAt
      sim:run(from + C.STAKE_BREAK_MATCH - C.AUTO_GRACE + late - sim.clock)
      start(sim, host, 1)
      eq({ guest.session.stakeLive, guest.session.stakeFoul }, { true, late ~= 0 and "unseen" or nil })
      Play.restore()
    end
  end)

  -- The pairs of client's note of gid as "f>t" strings, sorted.
  local function notePairs(client, gid)
    local note, out = client.env.db.stakeSeen[gid], {}
    for _, p in ipairs(note and note.pairs or {}) do out[#out + 1] = p.f .. ">" .. p.t end
    table.sort(out)
    return out, note
  end

  -- host's snapshot for `to` with `names` (seat -> name) put over its seats, as the message
  -- of `from` (default: the host itself) at epoch + e.
  local function renamedSnapshot(host, to, names, from, e)
    local hs = host.session
    local tbl = hs:record()
    for seat, name in pairs(names) do tbl.s[seat] = name end
    tbl.h, tbl.e = from or tbl.h, hs.epoch + (e or 0)
    return ns.Session.message("SNP", { tid = hs.tid, e = tbl.e, q = hs.seq, tbl = tbl, st = hs:snapshotFor(to),
      left = hs:left(), inv = hs:invitedList(), fr = hs:hook("snap") })
  end

  -- Петър's Белот match (petarHosts), `cheat(sim, cl)` right before its last step
  -- -> sim, cl, gid; Иван and Гошо lose it: Гошо owes Мария, never Петър.
  local function lastStep(cheat)
    local sim0, cl0 = petarHosts()
    local r0, steps = play(sim0, cl0[P])
    eq(r0.losers, { 1, 3 })
    local sim, cl, tid = petarHosts()
    local r = play(sim, cl[P], function(n)
      if n == steps then cheat(sim, cl) end
      return false
    end)
    eq(r.losers, { 1, 3 })
    return sim, cl, tid .. "/" .. r.q
  end

  it("belot: my own host's snapshot of my very state under other names is forged; my debt stays my roster's (C3)", function()
    local sim, cl, gid = lastStep(function(sim, cl)
      eq(cl[G].session.stakeFoul, nil)
      cl[G]:receive("WHISPER", P, renamedSnapshot(cl[P], G, { [2] = M, [4] = P })); sim:run(0)
      eq(cl[G].session.seats, { I, M, G, P })
      eq(cl[G].session.stakeFoul, "forged")
    end)
    eq(notePairs(cl[G], gid), { G .. ">" .. M, I .. ">" .. P })
    ok(cl[P].ledgerNet:make("D", { gid = gid, g = "belot", f = G, t = P, c = SK, why = "lost" }), "Петър's forged claim")
    sim:run(C.STAKE_FAIR_WAIT + C.STAKE_OWE_WAIT + 10)
    eq(#wordsAt(sim, G, "C", gid), 0)
    for _, n in ipairs(wordsAt(sim, G, "N", gid)) do eq(n.why, "forged") end
    eq(Play.debt(cl[I], gid, G, P).status, "contested")
  end)

  it("belot: the same snapshot from a host new to me is a question (C3)", function()
    local sim, cl = petarHosts()
    for _ = 1, 6 do Play.step(sim, cl[P]) end
    eq(cl[G].session.stakeFoul, nil)
    cl[G]:receive("WHISPER", M, renamedSnapshot(cl[P], G, { [2] = M, [4] = P }, M, 1)); sim:run(0)
    eq({ cl[G].session.host, cl[G].session.seats }, { M, { I, M, G, P } })
    eq(cl[G].session.stakeFoul, "unseen")
    eq(cl[G].session.stakeRoster, { I, P, G, M }) -- my roster is the one the match began with
    -- The very state under the names I hold, from a new host: nothing (as before).
    sim, cl = petarHosts()
    for _ = 1, 6 do Play.step(sim, cl[P]) end
    cl[G]:receive("WHISPER", M, renamedSnapshot(cl[P], G, {}, M, 1)); sim:run(0)
    eq({ cl[G].session.host, cl[G].session.stakeFoul }, { M, nil })
  end)

  it("belot: whatever names the table shows at the end, the pairs are my roster's: the honest claim is confirmed, the other contested (C3)", function()
    local sim, cl, gid = lastStep(function(_, cl)
      local s = cl[G].session -- the names of seats 2 and 4 swapped on Гошо's client, by a path no check saw
      s.seats[2], s.seats[4] = s.seats[4], s.seats[2]
      s.seatedBefore = ns.Util.copy(s.seats)
    end)
    local pairs_, note = notePairs(cl[G], gid)
    eq(pairs_, { G .. ">" .. M, I .. ">" .. P }); eq(note.foul, nil)
    ok(cl[P].ledgerNet:make("D", { gid = gid, g = "belot", f = G, t = P, c = SK, why = "lost" }), "Петър's forged claim")
    sim:run(C.STAKE_FAIR_WAIT + C.STAKE_OWE_WAIT + 10)
    eq(Play.debt(cl[I], gid, G, M).status, "confirmed")
    eq(Play.debt(cl[I], gid, G, P).status, "contested")
    local n = wordsAt(sim, G, "N", gid)
    eq(#n, 1); eq(n[1].why, "no")
  end)

  -- Иван's table of `game` at SK with Мария and Петър (Death Roll: all in one group, started).
  local T = "Тодор Илиев"
  local function small(game, n)
    local sim, cl = Sim.new(), {}
    for _, name in ipairs({ I, M, P }) do cl[name] = sim:add(name) end
    for _, env in pairs(sim.envs) do env.inGroup = function() return true end end
    sim:run(1); sim:settle()
    local tid = assert(cl[I]:openTable{ game = game, access = "guild", turn = 45, stake = SK, opt = game == "deathroll" and { start = 100 } or nil })
    sim:run(3)
    cl[M]:sit(tid, 2, SK); sim:run(1)
    if n == 3 then cl[P]:sit(tid, 3, SK); sim:run(1) end
    if game == "deathroll" then ok(cl[I]:startGame()); sim:run(0) end
    eq(cl[M].session.stakeLive, true)
    return sim, cl, tid
  end
  local function roll(sim, client, n)
    sim.nextRolls = { n }
    ok(client:roll()); sim:run(0)
  end

  it("death roll: a seat renamed by my host's snapshot is forged, and the loser owes the players it began with (C3)", function()
    for _, how in ipairs({ "snapshot", "seats" }) do
      local sim, cl, tid = small("deathroll", 3)
      local seen = {}
      cl[M]:on("result", function(r) seen[#seen + 1] = r end)
      roll(sim, cl[I], 50)
      if how == "snapshot" then
        cl[M]:receive("WHISPER", I, renamedSnapshot(cl[I], M, { [3] = T })); sim:run(0)
        eq(cl[M].session.seats[3], T); eq(cl[M].session.stakeFoul, "forged")
      else
        cl[M].session.seats[3] = T; cl[M].session.seatedBefore = ns.Util.copy(cl[M].session.seats)
      end
      roll(sim, cl[M], 1) -- Мария loses
      eq(#seen, 1)
      local gid = tid .. "/" .. seen[1].q
      eq(notePairs(cl[M], gid), { M .. ">" .. I, M .. ">" .. P })
      sim:run(C.ROLL_FINAL_WAIT + C.STAKE_OWE_WAIT + 10)
      eq(Play.debt(cl[P], gid, M, T), nil)
      eq(Play.debt(cl[P], gid, M, P).status, how == "snapshot" and "contested" or "confirmed")
    end
  end)

  it("морски шах: a seat renamed by my host's snapshot is forged, and my note names the player I sat down with (C3)", function()
    local sim, cl, tid = small("ttt", 2)
    local TTT, seen = ns.Engines.ttt, {}
    cl[M]:on("result", function(r) seen[#seen + 1] = r end)
    ok(cl[I]:act({ k = "mark", c = 1 })); sim:run(0)
    cl[M]:receive("WHISPER", I, renamedSnapshot(cl[I], M, { [1] = T })); sim:run(0)
    eq(cl[M].session.seats[1], T); eq(cl[M].session.stakeFoul, "forged")
    for _ = 1, 200 do
      local s = cl[I].session
      if #seen > 0 or not s or s:gameOver() then break end
      local seat = s.state.turn
      if seat == 1 then cl[I]:act(TTT.auto(s.state, 1)) elseif seat == 2 then cl[M]:act(TTT.auto(cl[M].session.state, 2)) end
      sim:run(1)
    end
    eq(#seen, 1)
    local pairs_ = notePairs(cl[M], tid .. "/" .. seen[1].q)
    eq(#pairs_, 1); ok(not pairs_[1]:find(T, 1, true), pairs_[1])
  end)

  it("belot: the host leaves: both opponents are confirmed (I1)", function()
    local sim, cl = Play.guild(4)
    local tid = Play.open(sim, cl, "belot", SK, 4)
    for _ = 1, 4 do Play.step(sim, cl[I]) end
    local seen = {}
    cl[P]:on("forfeit", function(f) seen[#seen + 1] = f end)
    cl[I]:stand(); sim:run(5)
    eq(#seen, 1); eq({ seen[1].name, seen[1].to }, { I, { P, G } })
    local gid = tid .. "/" .. seen[1].q
    eq(cl[I].env.db.stakeLeft[tid].h, I) -- I hosted when I stood: my own client ordered that stand
    for _, name in ipairs({ P, G }) do
      local d = Play.debt(cl[name], gid, I, name)
      ok(d, "a debt to " .. name); eq({ d.c, d.status }, { SK, "confirmed" })
    end
    eq(cl[I].stakes:asks(), {})
    eq(Play.debt(cl[P], gid, I, M), nil) -- the partner is owed nothing
    local rs = {}
    for _, e in ipairs(Play.entries(sim, nil, "R")) do if e.gid == gid then rs[#rs + 1] = e end end
    eq(#rs, 1); ok(rs[1].i:find(P, 1, true) == 1, "the successor wrote the R") -- none by the leaver itself
  end)

  it("belot: an R under my host's name that did not come from my host is not its R: asked, never confirmed (M1)", function()
    -- Петър hosts; Иван (seat 2) and Мария (seat 4), partners, both stand: Иван's stand is ordered first.
    local sim, cl = Play.guild(4)
    local tid = assert(cl[P]:openTable{ game = "belot", access = "guild", turn = 45, stake = SK }); sim:run(3)
    cl[I]:sit(tid, 2, SK); sim:run(1)
    cl[G]:sit(tid, 3, SK); sim:run(1)
    cl[M]:sit(tid, 4, SK); sim:run(1)
    sim.bus.filter = function(_, to, _, m) -- the honest R of that game does not reach Мария
      if to == M and (m.t == "LEV" or m.t == "LVC" or m.t == "LID") then return {} end
      return { m }
    end
    for _ = 1, 4 do Play.step(sim, cl[P]) end
    local seen = {}
    cl[P]:on("forfeit", function(f) seen[#seen + 1] = f end)
    cl[I]:stand(); cl[M]:stand(); sim:run(5)
    eq(#seen, 1); eq(seen[1].name, I)
    local gid = tid .. "/" .. seen[1].q
    eq(cl[M].env.db.stakeLeft[tid].h, P)
    -- Гошо hands Мария, as a sync would, an R with an id of Петър's that names her seat alone, and claims his stake.
    local r = cl[G].ledgerNet:make("R", { gid = gid, g = "belot", n = { P, I, G, M }, w = { 1, 3 }, l = { 4 }, sk = SK, why = "left" })
    local forged = {}
    for k, v in pairs(ns.Ledger.wire(r)) do forged[k] = v end
    forged.i = P .. ":900"
    local d = cl[G].ledgerNet:make("D", { gid = gid, g = "belot", f = M, t = G, c = SK, why = "left" })
    eq({ cl[M].ledgerNet:take(forged, G, false), cl[M].ledgerNet:take(d, G, true) }, { "new", "new" })
    sim:run(3)
    eq({ cl[M].stakes:results(gid, P) }, { 0, false })
    eq(cl[M].stakes:asks(), {}) -- no R of Петър's own yet: it waits
    sim:run(C.STAKE_OWE_WAIT + 5)
    eq(#cl[M].stakes:asks(), 1)
    eq(#wordsAt(sim, M, "C", gid), 0)
    eq(Play.debt(cl[G], gid, M, G).status, "pending")
    sim.bus.filter = nil
  end)

  it("a login to a finished match: a start inside the break from it is a question; one after it is clean (concern 1)", function()
    for _, late in ipairs({ -1, 0 }) do
      Play.short("santase")
      local sim, cl = Play.guild(2)
      Play.open(sim, cl, "santase", SK, 2)
      local host = cl[I]
      Play.finish(sim, host); sim:run(2)
      cl[P] = sim:relog(P); sim:settle(); sim:run(3)
      local g = cl[P].session
      ok(g:gameOver(), "the login brought the finished match")
      local from = g.stakeEndedAt or g.stakeHoldFrom
      ok(from ~= nil, "the login dates the end")
      sim:run(from + C.STAKE_BREAK_MATCH - C.AUTO_GRACE + late - sim.clock)
      host.session:event(0, { k = "start", first = 1 }); host.session:recordChanged(); sim:run(0)
      eq({ g.stakeLive, g.stakeFoul }, { true, late < 0 and "unseen" or nil })
      Play.restore()
    end
  end)
end)
