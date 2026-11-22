local Sim = require("sim")
local Play = require("play")
local ns = Sim.ns
local C, View = ns.Const, ns.LedgerView
local Santase = ns.Engines.santase

local restore = Play.staked("santase", "belot")

local I, P, M, G = Play.NAMES[1], Play.NAMES[2], Play.NAMES[3], Play.NAMES[4]
local SK = 50000

-- A small generator so that every client of a run draws from one stream
-- (copied from tests/core/santase_table_test.lua, G10).
local function lcg(seed)
  local x = seed
  return function(lo, hi)
    x = (x * 1103515245 + 12345) % 2147483648
    return lo + math.floor(x / 65536) % (hi - lo + 1)
  end
end

-- Every client of cl draws from one lcg(seed) stream -> the stream (give it to a client that logs in again).
local function seeded(cl, seed)
  local rnd = lcg(seed)
  for _, c in pairs(cl) do c.env.random = rnd end
  return rnd
end

-- Every entry `from` sent in GUILD LEVs.
local function authored(sim, from)
  local out = {}
  for _, k in ipairs({ "R", "D", "C", "N", "P", "X" }) do
    for _, e in ipairs(Play.entries(sim, from, k)) do out[#out + 1] = e end
  end
  return out
end

-- The GUILD entries of kind k (C or N) `from` sent about a D at gid.
local function wordsAt(sim, from, k, gid)
  local ds, out = {}, {}
  for _, d in ipairs(Play.entries(sim, nil, "D")) do if d.gid == gid then ds[d.i] = true end end
  for _, e in ipairs(Play.entries(sim, from, k)) do if ds[e.r] then out[#out + 1] = e end end
  return out
end

-- The debts of client's ledger at gid.
local function debtsAt(client, gid)
  local out = {}
  for _, d in ipairs(View.of(client.ledger).debts) do if d.gid == gid then out[#out + 1] = d end end
  return out
end

-- Is the debt gid|f|t among client's asks()?
local function asked(client, gid, f, t)
  for _, d in ipairs(client.stakes:asks()) do
    if d.gid == gid and d.f == f and d.t == t then return true end
  end
  return false
end

-- Steps until host's match is over -> the gid of it, the seat names of its losers and winners.
local function finish(sim, host, limit)
  local r = Play.finish(sim, host, limit)
  local names, L, W = host.session.seats, {}, {}
  for i, seat in ipairs(r.losers) do L[i] = names[seat] end
  for i, seat in ipairs(r.winners) do W[i] = names[seat] end
  return host.session.tid .. "/" .. r.q, L, W
end

-- The seat on turn at host's table moves (Play.step) until done() -> true, or false after `limit` steps.
local function stepUntil(sim, host, done, limit)
  for _ = 1, limit or 3000 do
    if done() then return true end
    Play.step(sim, host)
  end
  return false
end

-- Santase: hand number n is dealt at host's table.
local function toHand(sim, host, n)
  ok(stepUntil(sim, host, function()
    local s = host.session
    return s.fairN == n and s.fair and s.fair.stage == "dealt"
  end), "hand " .. n .. " never comes")
end

describe("stakes: a staked card table plays", function()
  it("a clean staked santase match: the loser confirms by itself", function()
    local sim, cl = Play.guild(2)
    seeded(cl, 5)
    Play.open(sim, cl, "santase", SK, 2)
    local gid, L, W = finish(sim, cl[I])
    for _, name in ipairs({ I, P }) do eq(cl[name].session.stakeFoul, nil, name) end
    sim:run(C.STAKE_FAIR_WAIT + 5)
    for _, name in ipairs({ I, P }) do
      local ds = debtsAt(cl[name], gid)
      eq(#ds, 1); eq({ ds[1].f, ds[1].t, ds[1].c, ds[1].status }, { L[1], W[1], SK, "confirmed" })
    end
    local mine = {} -- but the R, when the loser is the host
    for _, e in ipairs(authored(sim, L[1])) do if not (e.k == "R" and L[1] == I) then mine[#mine + 1] = e.k end end
    eq(mine, { "C" })
  end)

  it("no card face is saved with my log", function()
    local sim, cl = Play.guild(2)
    local tid = Play.open(sim, cl, "santase", SK, 2)
    local db, plays = cl[P].env.db, 0
    for _ = 1, 200 do
      if plays >= 3 then break end
      local s = cl[P].session
      if s.state.turn == 2 then plays = plays + 1 end
      Play.step(sim, cl[I])
    end
    eq(plays, 3)
    local log = db.stakeLog
    eq({ type(log), log.tid, log.st }, { "table", tid, nil })
    local n = 0
    for _, e in ipairs(log.log) do if e.k == "play" then n = n + 1 end end
    ok(n >= 3, "my plays are in the log")
    -- Морски шах keeps its board beside the log.
    local sim2, cl2 = Play.guild(2)
    local tid2 = assert(cl2[I]:openTable{ game = "ttt", access = "guild", turn = 45, stake = SK }); sim2:run(3)
    cl2[P]:sit(tid2, 2, SK); sim2:run(1)
    ok(cl2[I]:act({ k = "mark", c = 1 })); sim2:run(1)
    ok(cl2[P]:act({ k = "mark", c = 5 })); sim2:run(1)
    local log2 = cl2[P].env.db.stakeLog
    eq({ log2.tid, type(log2.st), log2.st.board[5] }, { tid2, "table", 2 })
  end)

  it("a new host mid-match is unseen for every member that follows it, forged for none", function()
    local sim, cl = Play.guild(2)
    local tid = Play.open(sim, cl, "santase", SK, 2)
    eq(cl[I].session.fair.d, 2) -- Петър deals the first hand: its deck stays at the table
    for _ = 1, 3 do Play.step(sim, cl[I]) end
    sim:offline(I)
    ok(stepUntil(sim, cl[P], function() return cl[P].session.role == "host" end, C.SILENT_AFTER + 60), "Петър never takes over")
    eq(cl[P].session.stakeFoul, nil) -- the dealer of the running hand: nothing to judge
    sim:online(I)
    for _ = 1, C.PING_EVERY + 15 do
      if cl[I].session.role ~= "host" then break end
      sim:run(1)
    end
    sim:run(3)
    eq(cl[I].session.host, P); eq(cl[I].session.stakeFoul, "unseen")
    local gid, L = finish(sim, cl[P])
    eq(tid, gid:match("^(.*)/")); eq(cl[P].session.stakeFoul, nil)
    sim:run(C.STAKE_FAIR_WAIT + 5)
    if L[1] == I then
      ok(asked(cl[I], gid, I, P), "Иван's debt is put to him")
      eq(#wordsAt(sim, I, "N", gid), 0)
    else
      eq(Play.debt(cl[I], gid, P, I).status, "confirmed")
    end
  end)

  -- Белот under Иван: six moves, then (lag) the last EV of Иван's before he goes silent never reaches Петър,
  -- the first candidate -> sim, cl, the name of the new host.
  local function belotNewHost(lag)
    local sim, cl = Play.guild(4)
    Play.open(sim, cl, "belot", SK, 4)
    for _ = 1, 6 do Play.step(sim, cl[I]) end
    if lag then
      if cl[I].session.state.turn == 2 then Play.step(sim, cl[I]) end
      sim.bus.filter = function(from, to, _, m) return (from == I and to == P and m.t == "EV") and {} or { m } end
      Play.step(sim, cl[I])
      sim.bus.filter = nil
      ok(cl[P].session.seq < cl[M].session.seq, "Петър lags")
    end
    sim:offline(I)
    local new
    for _ = 1, C.SILENT_AFTER + 60 do
      sim:run(1)
      for _, name in ipairs({ P, M, G }) do if cl[name].session.role == "host" then new = name end end
      if new then break end
    end
    ok(new, "nobody took over")
    sim:run(5)
    return sim, cl, new
  end

  -- The old host comes back: it hears the new one and asks for its snapshot -> its foul then.
  local function comesBack(sim, cl, new)
    sim:online(I)
    for _ = 1, C.PING_EVERY + 15 do
      if cl[I].session.role ~= "host" then break end
      sim:run(1)
    end
    sim:run(3)
    eq(cl[I].session.host, new)
    return cl[I].session.stakeFoul
  end

  it("belot: a new host whose snapshot is not my state: every member that follows it is unseen, none forged", function()
    local sim, cl, new = belotNewHost(true)
    eq(new, P)
    for _, name in ipairs({ M, G }) do eq(cl[name].session.host, P, name); eq(cl[name].session.stakeFoul, "unseen", name) end
    ok(cl[P].session.stakeFoul ~= "forged", "the new host")
    ok(comesBack(sim, cl, new) ~= "forged", "the old host") -- asked: "unseen" unless the table stands where it left it
  end)

  it("belot: a new host whose snapshot is my very state changes nothing", function()
    local sim, cl, new = belotNewHost(false)
    for _, name in ipairs({ P, M, G }) do
      if name ~= new then eq(cl[name].session.host, new, name); eq(cl[name].session.stakeFoul, nil, name) end
    end
    ok(cl[new].session.stakeFoul ~= "forged", "the new host")
    ok(comesBack(sim, cl, new) ~= "forged", "the old host")
  end)

  it("belot: a /reload mid-match asks only the player that reloaded", function()
    local seen = {}
    for seed = 1, 40 do
      if seen.lost and seen.won then break end
      local sim, cl = Play.guild(4)
      local rnd = seeded(cl, seed)
      Play.open(sim, cl, "belot", SK, 4)
      ok(stepUntil(sim, cl[I], function()
        local s = cl[I].session
        return s.fairN == 3 and s.fair and s.fair.stage == "dealt"
      end), "the third deal never comes")
      for _ = 1, 3 do Play.step(sim, cl[I]) end
      cl[G] = sim:relog(G); cl[G].env.random = rnd; sim:settle(); sim:run(3)
      eq(cl[G].session.stakeFoul, "unseen")
      local gid, L, W = finish(sim, cl[I])
      for _, name in ipairs({ I, P, M }) do eq(cl[name].session.stakeFoul, nil, name) end
      sim:run(C.STAKE_FAIR_WAIT + 5)
      local branch = (L[1] == G or L[2] == G) and "lost" or "won"
      if not seen[branch] then
        seen[branch] = true
        for _, c in pairs(cl) do eq(#debtsAt(c, gid), 2) end
        for i = 1, 2 do
          local d = Play.debt(cl[M], gid, L[i], W[i])
          ok(d, "the debt of the " .. i .. ". loser")
          eq(d.status, L[i] == G and "pending" or "confirmed", L[i])
          eq(asked(cl[G], gid, L[i], W[i]), L[i] == G, L[i])
        end
        eq(#wordsAt(sim, G, "N", gid), 0)
      end
    end
    eq(seen, { lost = true, won = true })
  end)

  -- Сантасе under Иван, every client drawing from lcg(seed) -> sim, cl, tid, the stream.
  local function santase(seed)
    local sim, cl = Play.guild(2)
    local rnd = seeded(cl, seed)
    return sim, cl, Play.open(sim, cl, "santase", SK, 2), rnd
  end

  -- Runs cheat(sim, cl) in staked Сантасе matches of seeds 1.. until Петър loses one;
  -- the match is played out -> sim, cl, gid of the one Петър lost.
  local function untilGuestLoses(cheat)
    for seed = 1, 40 do
      local sim, cl = santase(seed)
      cheat(sim, cl)
      local gid, L = finish(sim, cl[I])
      sim:run(C.STAKE_FAIR_WAIT + 5)
      if L[1] == P then return sim, cl, gid end
    end
    error("Петър never loses")
  end

  it("a snapshot my own host pushes on me that changes my hand is forged", function()
    local sim, cl, gid = untilGuestLoses(function(sim, cl)
      ok(stepUntil(sim, cl[I], function() return cl[I].session.state.turn == 2 end), "the turn of seat 2")
      local hs, x = cl[I].session, ns.Util.copy(cl[P].session.state)
      ok(Santase.apply(x, 2, Santase.auto(x, 2))) -- one more played card: mine
      cl[P]:receive("WHISPER", I, ns.Session.message("SNP", {
        tid = hs.tid, e = hs.epoch, q = hs.seq, tbl = hs:record(), st = Santase.snapshot(x),
        left = hs:left(), inv = hs:invitedList(), fr = hs:hook("snap"),
      }))
      sim:run(0)
      eq(cl[P].session.stakeFoul, "forged")
      cl[P].session:requestSync(); sim:run(2) -- my state back: the foul stays
      eq(cl[P].session.stakeFoul, "forged")
    end)
    local n = wordsAt(sim, P, "N", gid)
    eq(#n, 1); eq(n[1].why, "forged"); eq(#wordsAt(sim, P, "C", gid), 0)
    eq(Play.debt(cl[I], gid, P, I).status, "contested")
  end)

  it("the host plays my card for me: contested as forged", function()
    local sim, cl, gid = untilGuestLoses(function(sim, cl)
      toHand(sim, cl[I], 2)
      local hs = cl[I].session
      eq(hs.fair.d, 1) -- the host deals: it knows my hand
      ok(stepUntil(sim, cl[I], function() return hs.state.turn == 2 end), "the turn of seat 2")
      local worst = Santase.auto(ns.Fair.full(hs.state, hs.fair.deck), 2)
      ok(worst)
      hs:play(2, worst, true); sim:run(1)
      eq(cl[P].session.stakeFoul, "forged"); eq(cl[P].session.fair.foul, "forged")
    end)
    local n = wordsAt(sim, P, "N", gid)
    eq(#n, 1); eq(n[1].why, "forged"); eq(#wordsAt(sim, P, "C", gid), 0)
  end)

  it("belot: the host stands a present player up: contested as stand", function()
    local sim, cl = Play.guild(4)
    local tid = Play.open(sim, cl, "belot", SK, 4)
    for _ = 1, 5 do Play.step(sim, cl[I]) end
    local q = cl[I].session.seq + 1
    ok(cl[I].session:event(0, { k = "stand", seat = 4, why = "offline" })); sim:run(1)
    eq(cl[G].session.stakeFoul, "stand")
    sim:run(10)
    local gid = tid .. "/" .. q
    local n = wordsAt(sim, G, "N", gid)
    eq(#n, 2)
    local to = {}
    for _, e in ipairs(n) do eq(e.why, "stand"); to[#to + 1] = e.r:match("^(.*):") end
    table.sort(to)
    eq(to, { I, M }) -- both opponents' claims; the partner owes and is owed nothing
    eq(#wordsAt(sim, G, "C", gid), 0)
    for _, name in ipairs({ I, M }) do eq(Play.debt(cl[P], gid, G, name).status, "contested") end
  end)

  it("a /reload of the dealer mid-hand: the hand goes on, the dealer's debt is a question", function()
    local seen = {}
    for seed = 1, 40 do
      if seen.lost and seen.won then break end
      local sim, cl, _, rnd = santase(seed)
      toHand(sim, cl[I], 3)
      local hs = cl[I].session
      eq(hs.fair.d, 2) -- Петър deals the third hand
      for _ = 1, 2 do Play.step(sim, cl[I]) end
      local h = hs.fair.h
      cl[P] = sim:relog(P); cl[P].env.random = rnd; sim:settle(); sim:run(4)
      eq({ hs.fair.h, hs.fair.stage, hs.fairVoids }, { h, "dealt", nil }) -- its kept deck: no void
      ok(cl[P].session.fair.deck ~= nil)
      local gid, L, W = finish(sim, cl[I])
      eq(cl[I].session.stakeFoul, nil); eq(cl[P].session.stakeFoul, "unseen")
      sim:run(C.STAKE_FAIR_WAIT + 5)
      local branch = L[1] == P and "lost" or "won"
      seen[branch] = true
      if branch == "lost" then
        ok(asked(cl[P], gid, P, I), "the dealer's debt is put to it")
        eq(#wordsAt(sim, P, "N", gid), 0); eq(#wordsAt(sim, P, "C", gid), 0)
        eq(Play.debt(cl[I], gid, P, I).status, "pending")
      else
        eq(Play.debt(cl[P], gid, I, P).status, "confirmed")
      end
    end
    eq(seen, { lost = true, won = true })
  end)
end)

restore()
