local Sim = require("sim")
local Play = require("play")
local ns = Sim.ns
local C, View, Stakes = ns.Const, ns.LedgerView, ns.Stakes
local Santase = ns.Engines.santase

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
  local names, L, W = r.names or host.session.seats, {}, {} -- by the result: a seat may be empty since
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
    for _, e in ipairs(log.log) do
      if e.k == "play" then n = n + 1 end
      eq(e.c, nil, "no face in the entry " .. tostring(e.k))
    end
    ok(n >= 1, "my plays are in the log")
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
    Play.step(sim, cl[new]) -- the table moves on: the snapshot the old host asks for differs from its state
    eq(comesBack(sim, cl, new), "unseen", "the old host")
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

  -- A higher epoch from the same host is no new host (Stakes.hostChanged): still forged, not "unseen".
  it("the same host pushes an unasked snapshot at epoch + 1 that plays my card: forged", function()
    local sim, cl = santase(1)
    ok(stepUntil(sim, cl[I], function() return cl[I].session.state.turn == 2 end), "the turn of seat 2")
    local hs, x = cl[I].session, ns.Util.copy(cl[P].session.state)
    ok(Santase.apply(x, 2, Santase.auto(x, 2)))
    cl[P]:receive("WHISPER", I, ns.Session.message("SNP", {
      tid = hs.tid, e = hs.epoch + 1, q = hs.seq, tbl = hs:record(), st = Santase.snapshot(x),
      left = hs:left(), inv = hs:invitedList(), fr = hs:hook("snap"),
    }))
    sim:run(0)
    eq(cl[P].session.host, I)
    eq(cl[P].session.stakeFoul, "forged")
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
    -- The stand left no trace in the host's sweep: it runs on and does not re-arm at 0 s forever.
    sim:run(C.OFFLINE_STAND_SECONDS + C.SILENT_AFTER + 100)
    eq(cl[I].session.lastHeard[G], nil)
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

describe("stakes: the verdict feeds the confirmation", function()
  local Belot = ns.Engines.belot

  -- A stand-in for a session at a table of `game` (what Stakes.fairFoul reads).
  local function fakeSession(o)
    return { client = { env = { me = o.me } }, mySeat = o.seat, seats = o.seats, game = o.game,
      engine = function(self) return ns.Games.engine(self.game) end }
  end

  -- Runs fn with the match target of `id` at 1 (Play.short), put back whether it passes or fails.
  local function shortly(id, fn)
    local back = Play.short(id)
    local fine, err = pcall(fn)
    back()
    if not fine then error(err, 0) end
  end

  -- Сантасе under Иван, every client drawing from lcg(seed) -> sim, cl, tid, the stream.
  local function santase(seed, more)
    local sim, cl = Play.guild(more and 3 or 2)
    local rnd = seeded(cl, seed)
    return sim, cl, Play.open(sim, cl, "santase", SK, 2), rnd
  end

  local function belot(seed)
    local sim, cl = Play.guild(4)
    local rnd = seeded(cl, seed)
    return sim, cl, Play.open(sim, cl, "belot", SK, 4), rnd
  end

  local function isReveal(m)
    local a = type(m.a) == "table" and m.a
    return a and a.k == "fair" and a.op == "reveal"
  end

  -- Once host's match is over, the dealer's reveal (its ACT to the host; the host's EV when it deals) is
  -- held back (drop: lost) -> the held {from, to, channel, m}.
  local function holdReveals(sim, host, drop)
    local held = {}
    sim.bus.filter = function(from, to, channel, m)
      if isReveal(m) and host.session and host.session:gameOver() then
        if not drop then held[#held + 1] = { from = from, to = to, channel = channel, m = m } end
        return {}
      end
      return { m }
    end
    return held
  end

  -- The held messages reach their clients now.
  local function release(sim, held)
    sim.bus.filter = nil
    for _, x in ipairs(held) do sim.clients[x.to]:receive(x.channel, x.from, x.m) end
    sim:run(0)
  end

  local function noteOf(client, gid) return client.env.db.stakeSeen[gid] end
  local function words(sim, from, gid) return #wordsAt(sim, from, "C", gid) + #wordsAt(sim, from, "N", gid) end

  -- The creditor of loser `name` of a team match (losers and winners by seat, the i-th owes the i-th).
  local function creditorOf(name, L, W)
    for i, f in ipairs(L) do if f == name then return W[i] end end
  end

  it("Stakes.fairFoul: the table of the plan", function()
    local s = fakeSession{ me = "Иван Петров", seat = 1, seats = { "Иван Петров", "Петър Колев", "Мария Стоянова", "Гошо Тодоров" }, game = "belot" }
    local function f(v) return Stakes.fairFoul(s, v) end
    eq(f{ verdict = "ok" }, nil); eq(f{ verdict = "unseen" }, "unseen")
    eq(f{ verdict = "bad", why = "announce", dealer = "Петър Колев" }, nil)
    eq(f{ verdict = "bad", why = "play", dealer = "Мария Стоянова" }, "deal")
    eq(f{ verdict = "bad", why = "noreveal", dealer = "Петър Колев" }, "deal")
    eq(f{ verdict = "bad", why = "noreveal", dealer = "Мария Стоянова" }, "unseen")
    s.fairVoids = { ["Петър Колев"] = 1 }
    eq(f{ verdict = "void", dealer = "Петър Колев" }, "unseen")
    eq(f{ verdict = "bad", why = "nodeal", dealer = "Петър Колев" }, "unseen")
    s.fairVoids = { ["Петър Колев"] = 1 }; s.fairLapses = { ["Петър Колев"] = 1 }
    eq(f{ verdict = "void", dealer = "Петър Колев" }, "deal")
    s.fairVoids = { ["Мария Стоянова"] = 3 }
    eq(f{ verdict = "void", dealer = "Мария Стоянова" }, "unseen"); eq(f{ verdict = "void", dealer = "Иван Петров" }, nil) -- my partner's: I cannot see that it asked (C1)
    eq(f{ verdict = "bad", why = "nodeal", dealer = "Иван Петров" }, "unseen")
    -- Сантасе has no partner: my side is me alone; a throw of Табла is judged by its own verdict.
    local s2 = fakeSession{ me = "Иван Петров", seat = 1, seats = { "Иван Петров", "Петър Колев" }, game = "santase" }
    eq(Stakes.fairFoul(s2, { verdict = "bad", why = "noreveal", dealer = "Петър Колев" }), "deal")
    eq(Stakes.fairFoul(s2, { verdict = "bad", why = "noreveal", dealer = "Иван Петров" }), "unseen")
    local s3 = fakeSession{ me = "Иван Петров", seat = 1, seats = { "Иван Петров", "Петър Колев" }, game = "tabla" }
    eq({ Stakes.fairFoul(s3, { verdict = "bad", why = "seed" }), Stakes.fairFoul(s3, { verdict = "unseen" }), Stakes.fairFoul(s3, { verdict = "ok" }) },
      { "dice", "unseen", nil })
  end)

  local X = ("ab"):rep(16)

  -- Hand 2 at Иван's Сантасе table: Иван deals it from seeds of its own (Петър's commit replaced by
  -- one of X, X fed to it as Петър's seed): the hand closes "bad" ("mine") on Петър
  -- (the scaffolding of tests/core/santase_table_test.lua's cheating host, G10).
  -- rigHand2: until hand 2 is dealt, its foul already held on Петър's client (noted at the commit event).
  local function rigHand2(sim, cl)
    local F, host = ns.Ext.fair, cl[I]
    local realAct = F.act
    F.act = function(s, seat, x)
      if s.client == host and x.k == "fair" and x.op == "commit" and seat == 2 and s.fair and s.fair.d == 1 then
        x = { k = "fair", op = "commit", h = x.h, c = ns.Fair.commit(X) }
      end
      return realAct(s, seat, x)
    end
    local fine, err = pcall(function()
      ok(stepUntil(sim, host, function() local r = host.session.fair; return r and r.d == 1 and r.stage == "seed" end), "the shuffle of hand 2")
      local r = host.session.fair
      ns.Member.handlers.SED(host, P, { tid = host.session.tid, h = r.h, s = X }); sim:run(1)
      eq(host.session.fair.stage, "dealt")
    end)
    F.act = realAct
    if not fine then error(err, 0) end
    eq({ cl[P].session.fair.stage, cl[P].session.fair.foul }, { "dealt", "mine" })
  end
  local function hostDealsOwnSeeds(sim, cl)
    local host = cl[I]
    rigHand2(sim, cl)
    local h = host.session.fair.h
    ok(stepUntil(sim, host, function() local s = cl[P].session; return s:gameOver() or (s.fairLast and s.fairLast.h == h) end), "the end of hand 2")
    sim:run(1)
    eq({ cl[P].session.fairLast.verdict, cl[P].session.fairLast.why }, { "bad", "mine" })
  end

  it("a hand that closed bad on my client contests the match", function()
    for seed = 1, 40 do
      local sim, cl = santase(seed, true)
      hostDealsOwnSeeds(sim, cl)
      eq(cl[P].session.stakeFoul, "deal"); eq(cl[I].session.stakeFoul, nil)
      local gid, L = finish(sim, cl[I])
      sim:run(C.STAKE_FAIR_WAIT + 5)
      if L[1] == P then
        local n = wordsAt(sim, P, "N", gid)
        eq(#n, 1); eq(n[1].why, "deal"); eq(#wordsAt(sim, P, "C", gid), 0)
        eq(Play.debt(cl[M], gid, P, I).status, "contested") -- a third member of the guild
        return
      end
    end
    error("Петър never loses")
  end)

  it("a bad hand is sticky through a resync", function()
    local sim, cl = santase(1)
    hostDealsOwnSeeds(sim, cl)
    eq(cl[P].session.stakeFoul, "deal")
    cl[P].session:requestSync(); sim:run(2)
    eq(cl[P].session.stakeFoul, "deal")
  end)

  it("the loser waits for the last hand's reveal, then confirms", function()
    shortly("santase", function()
      local sim, cl = santase(5)
      local held = holdReveals(sim, cl[I])
      local gid, L, W = finish(sim, cl[I])
      eq(cl[I].session.fair.d, 2) -- Петър deals the one hand: its reveal goes to the host
      sim:run(4) -- +5
      local loser = cl[L[1]]
      local note = noteOf(loser, gid)
      eq({ note.wait, note.foul }, { true, "unseen" })
      ok(Play.debt(loser, gid, L[1], W[1]), "the claim is there")
      eq(Play.debt(loser, gid, L[1], W[1]).status, "pending"); eq(words(sim, L[1], gid), 0)
      sim:run(5); release(sim, held); sim:run(1) -- the reveal at +10
      eq({ note.wait, note.foul }, { nil, nil })
      eq(Play.debt(loser, gid, L[1], W[1]).status, "confirmed")
      sim:run(C.LEDGER_COALESCE + 1)
      eq(#wordsAt(sim, L[1], "C", gid), 1); eq(#wordsAt(sim, L[1], "N", gid), 0)
    end)
  end)

  it("the last hand is never revealed: the loser waits, then contests", function()
    shortly("santase", function()
      for seed = 1, 40 do
        local sim, cl = santase(seed)
        holdReveals(sim, cl[I], true) -- the guest dealer's ACT to the host is lost
        local gid, L = finish(sim, cl[I])
        if L[1] == I then
          eq(cl[I].session.fair.d, 2)
          sim:run(C.FAIR_WAIT - 4)
          eq(noteOf(cl[I], gid).wait, true); eq(words(sim, I, gid), 0)
          sim:run(8)
          eq({ cl[I].session.fairLast.verdict, cl[I].session.fairLast.why }, { "bad", "noreveal" })
          eq({ noteOf(cl[I], gid).foul, noteOf(cl[I], gid).wait }, { "deal", nil })
          sim:run(C.LEDGER_COALESCE + 1)
          local n = wordsAt(sim, I, "N", gid)
          eq(#n, 1); eq(n[1].why, "deal"); eq(#wordsAt(sim, I, "C", gid), 0)
          return
        end
      end
      error("Петър never wins")
    end)
  end)

  it("a silent dealer that is the host: the debt is asked at STAKE_FAIR_WAIT", function()
    for seed = 1, 40 do
      local sim, cl = santase(seed)
      toHand(sim, cl[I], 2)
      eq(cl[I].session.fair.d, 1) -- Иван deals hand 2, its last
      local silent = false
      sim.bus.filter = function(from, _, _, m)
        if from ~= I then return { m } end
        if isReveal(m) and m.t == "EV" and cl[I].session:gameOver() then silent = true end
        return (silent and m.t ~= "LEV") and {} or { m } -- only its ledger entries still go out
      end
      local gid, L
      shortly("santase", function() gid, L = finish(sim, cl[I]) end)
      if L[1] == P then
        ok(silent, "the host's reveal never went out")
        sim:run(C.STAKE_FAIR_WAIT - 5)
        local note = noteOf(cl[P], gid)
        eq({ note.wait, note.foul }, { true, "unseen" })
        ok(Play.debt(cl[P], gid, P, I), "the claim is there"); eq(words(sim, P, gid), 0)
        sim:run(8)
        eq({ note.wait, note.foul }, { nil, "unseen" })
        ok(asked(cl[P], gid, P, I), "the debt is put to Петър")
        eq(words(sim, P, gid), 0)
        return
      end
    end
    error("Иван never wins")
  end)

  it("my own partner's missing reveal is a question, not a contest", function()
    shortly("belot", function()
      for seed = 1, 60 do
        local sim, cl = belot(seed)
        holdReveals(sim, cl[I], true)
        local gid, L, W = finish(sim, cl[I])
        local s = cl[I].session
        local d = s.fair.d
        local mate = d ~= 1 and s.seats[Belot.partner(d)] -- the dealer's partner; a dealing host reveals by itself
        if mate and creditorOf(mate, L, W) then
          sim:run(C.STAKE_FAIR_WAIT + 5)
          eq({ cl[mate].session.fairLast.verdict, cl[mate].session.fairLast.why }, { "bad", "noreveal" })
          eq(noteOf(cl[mate], gid).foul, "unseen")
          ok(asked(cl[mate], gid, mate, creditorOf(mate, L, W)), "the debt is put to the dealer's partner")
          eq(words(sim, mate, gid), 0)
          return
        end
      end
      error("the dealer's team never loses")
    end)
  end)

  it("a note still waiting at a logout stays unseen", function()
    shortly("santase", function()
      for seed = 1, 40 do
        local sim, cl, _, rnd = santase(seed)
        holdReveals(sim, cl[I], true)
        local gid, L = finish(sim, cl[I])
        if L[1] == P then
          sim:run(3)
          eq(noteOf(cl[P], gid).wait, true)
          cl[P] = sim:relog(P); cl[P].env.random = rnd; sim:settle(); sim:run(3)
          eq({ noteOf(cl[P], gid).foul, noteOf(cl[P], gid).wait }, { "unseen", nil })
          sim:run(C.STAKE_FAIR_WAIT)
          ok(asked(cl[P], gid, P, I), "the debt is put to Петър")
          eq(words(sim, P, gid), 0)
          return
        end
      end
      error("Петър never loses")
    end)
  end)

  -- Петър, the dealer of the running hand at Иван's table, comes back without its deck (sim:crash): the hand is void.
  local function voidBy(sim, cl, rnd)
    for _ = 1, 2 do Play.step(sim, cl[I]) end
    cl[P] = sim:crash(P); cl[P].env.random = rnd; sim:settle(); sim:run(4)
  end

  it("an opponent's void: once is a question, twice a contest", function()
    for _, times in ipairs({ 1, 2 }) do
      local found = false
      for seed = 1, 40 do
        local sim, cl, _, rnd = santase(seed)
        eq({ cl[I].session.fairN, cl[I].session.fair.d }, { 1, 2 })
        voidBy(sim, cl, rnd)
        eq(cl[I].session.fairVoids, { [P] = 1 })
        if times == 2 then
          toHand(sim, cl[I], 3); eq(cl[I].session.fair.d, 2)
          voidBy(sim, cl, rnd)
          eq(cl[I].session.fairVoids, { [P] = 2 })
        end
        eq(cl[I].session.stakeFoul, times == 1 and "unseen" or "deal")
        local gid, L = finish(sim, cl[I])
        sim:run(C.STAKE_FAIR_WAIT + 5)
        if L[1] == I then
          local n = wordsAt(sim, I, "N", gid)
          if times == 1 then
            ok(asked(cl[I], gid, I, P), "the debt is put to Иван"); eq(#n, 0)
          else
            eq(#n, 1); eq(n[1].why, "deal")
          end
          eq(#wordsAt(sim, I, "C", gid), 0)
          found = true
          break
        end
      end
      ok(found, "Иван never loses (" .. times .. " voids)")
    end
  end)

  it("my own void costs me nothing (Белот: the dealer comes back without its deck; its partner's loss is a question)", function()
    shortly("belot", function()
      for seed = 1, 60 do
        local sim, cl, _, rnd = belot(seed)
        eq(cl[I].session.fair.d, 4) -- Гошо deals the first hand
        for _ = 1, 2 do Play.step(sim, cl[I]) end
        cl[G] = sim:crash(G); cl[G].env.random = rnd; sim:settle(); sim:run(4)
        eq(cl[I].session.fairVoids, { [G] = 1 })
        eq(cl[P].session.stakeFoul, "unseen") -- my partner's void: my client cannot see that it asked (C1)
        eq({ cl[I].session.stakeFoul, cl[M].session.stakeFoul }, { "unseen", "unseen" }) -- an opponent's first
        local gid, L, W = finish(sim, cl[I])
        sim:run(C.STAKE_FAIR_WAIT + 5)
        if creditorOf(G, L, W) then
          ok(asked(cl[G], gid, G, creditorOf(G, L, W)), "Гошо's debt is put to it (its login)")
          eq(#wordsAt(sim, G, "N", gid), 0)
          eq(#wordsAt(sim, P, "C", gid), 0); eq(#wordsAt(sim, P, "N", gid), 0)
          ok(asked(cl[P], gid, P, creditorOf(P, L, W)), "its partner's debt is put to it")
          return
        end
      end
      error("Гошо's team never loses")
    end)
  end)

  -- The client on turn at Иван's Белот table bids each token of str, one second apart.
  local function bid(sim, cl, str)
    for token in str:gmatch("%S+") do
      local s = cl[I].session
      ok(sim.clients[s.seats[s.state.turn]]:act{ k = "bid", b = token }, "bid " .. token)
      sim:run(1)
    end
  end

  it("a forged announce does not contest", function()
    shortly("belot", function()
      for seed = 1, 60 do
        local sim, cl, tid = belot(seed)
        local host = cl[I]
        local said = {}
        for _, name in ipairs({ I, M }) do
          cl[name]:on("fair", function(v) said[name] = said[name] or (v.why == "announce" and v.verdict) end)
        end
        bid(sim, cl, "S P P P")
        while host.session.state.turn == 1 do Play.step(sim, host) end -- seat 1 announces what it has and leads
        local i = host.session.state.hands[2][1] -- the scenario of tests/core/belot_table_test.lua (G10)
        host:receive("WHISPER", P, { v = 1, t = "ACT", tid = tid, a = { k = "ann", a = { { t = "cJ", i = i }, { t = "s8", i = i }, { t = "c9", i = i } } } })
        sim:run(2)
        local gid, L = finish(sim, host)
        if L[1] == I then -- Иван and Мария lost
          sim:run(C.STAKE_FAIR_WAIT + 5)
          for _, name in ipairs({ I, M }) do
            eq(said[name], "bad", name)
            eq(#wordsAt(sim, name, "C", gid), 1, name); eq(#wordsAt(sim, name, "N", gid), 0, name)
          end
          return
        end
      end
      error("Иван and Мария never lose")
    end)
  end)

  it("a leave waits for no verdict", function()
    local sim, cl, tid = santase(3)
    for _ = 1, 3 do Play.step(sim, cl[I]) end
    ok(cl[I].session.fair.stage == "dealt" and not cl[I].session:gameOver(), "mid-hand")
    local gid = tid .. "/" .. (cl[I].session.seq + 1)
    cl[P]:stand(); sim:run(0)
    for _, name in ipairs({ I, P }) do eq(noteOf(cl[name], gid).wait, nil, name) end
    sim:run(3)
    eq(Play.debt(cl[P], gid, P, I).status, "confirmed")
    sim:run(C.LEDGER_COALESCE)
    eq(#wordsAt(sim, P, "C", gid), 1)
  end)

  it("a foul held against the last hand, which the host deals and never reveals: contested at STAKE_FAIR_WAIT", function()
    for seed = 1, 40 do
      local sim, cl = santase(seed)
      rigHand2(sim, cl)
      local silent = false
      sim.bus.filter = function(from, _, _, m)
        if from ~= I then return { m } end
        if isReveal(m) and m.t == "EV" and cl[I].session:gameOver() then silent = true end
        return (silent and m.t ~= "LEV") and {} or { m } -- only its ledger entries still go out
      end
      local gid, L
      shortly("santase", function() gid, L = finish(sim, cl[I]) end)
      if L[1] == P then
        ok(silent, "the host's reveal never went out")
        eq({ noteOf(cl[P], gid).foul, noteOf(cl[P], gid).wait }, { "deal", true }) -- at once, the hand still open
        sim:run(C.STAKE_FAIR_WAIT + 5)
        eq({ noteOf(cl[P], gid).foul, noteOf(cl[P], gid).wait }, { "deal", nil })
        local n = wordsAt(sim, P, "N", gid)
        eq(#n, 1); eq(n[1].why, "deal"); eq(#wordsAt(sim, P, "C", gid), 0)
        ok(not asked(cl[P], gid, P, I), "contested, not asked")
        return
      end
    end
    error("Иван never wins")
  end)

  it("a leave mid-hand while my client holds a foul against that hand never confirms by itself", function()
    local sim, cl, tid = santase(3)
    rigHand2(sim, cl)
    local gid = tid .. "/" .. (cl[I].session.seq + 1)
    cl[P]:stand(); sim:run(3 + C.LEDGER_COALESCE)
    eq(noteOf(cl[P], gid).foul, "deal")
    ok(Play.debt(cl[P], gid, P, I), "the claim is there")
    ok(Play.debt(cl[P], gid, P, I).status ~= "confirmed", "not confirmed")
    eq(#wordsAt(sim, P, "C", gid), 0)
    ok(asked(cl[P], gid, P, I) or #wordsAt(sim, P, "N", gid) == 1, "put to me or contested")
  end)

  it("belot: the host stands me up mid-hand while my client holds a foul against that hand: contested as deal", function()
    local sim, cl, tid = belot(1)
    for _ = 1, 5 do Play.step(sim, cl[I]) end
    local f = cl[G].session.fair
    ok(f and f.stage == "dealt" and not f.foul, "mid-hand, clean")
    f.foul = "mine" -- as sawCommit notes it when the host replaced my commit
    local q = cl[I].session.seq + 1
    ok(cl[I].session:event(0, { k = "stand", seat = 4, why = "offline" })); sim:run(11)
    local gid = tid .. "/" .. q
    eq(noteOf(cl[G], gid).foul, "deal")
    local n = wordsAt(sim, G, "N", gid)
    eq(#n, 2)
    for _, e in ipairs(n) do eq(e.why, "deal") end
    eq(#wordsAt(sim, G, "C", gid), 0)
  end)

  it("the last hand's own reveal audits bad after the match ended: contested", function()
    local F = ns.Ext.fair
    local realAct = F.act
    F.act = function(s, seat, x) -- the host swaps the guest dealer's seeds in the reveal it relays
      if s.client.env.me == I and type(x) == "table" and x.k == "fair" and x.op == "reveal" and seat == 2 and type(x.s) == "table" then
        local t = {}
        for k = 1, #x.s do t[k] = X end
        x = { k = "fair", op = "reveal", h = x.h, s = t }
      end
      return realAct(s, seat, x)
    end
    local fine, err = pcall(shortly, "santase", function()
      for seed = 1, 40 do
        local sim, cl = santase(seed)
        local gid, L = finish(sim, cl[I])
        eq(cl[I].session.fair.d, 2) -- Петър deals the one hand
        if L[1] == P then
          sim:run(1)
          eq({ cl[P].session.fairLast.verdict, cl[P].session.fairLast.why }, { "bad", "mine" })
          eq({ noteOf(cl[P], gid).foul, noteOf(cl[P], gid).wait }, { "deal", nil })
          sim:run(C.LEDGER_COALESCE + 1)
          local n = wordsAt(sim, P, "N", gid)
          eq(#n, 1); eq(n[1].why, "deal"); eq(#wordsAt(sim, P, "C", gid), 0)
          return
        end
      end
      error("Петър never loses")
    end)
    F.act = realAct
    if not fine then error(err, 0) end
  end)

  it("a verdict that the next start brings does not touch the new match", function()
    shortly("santase", function()
      for seed = 1, 40 do
        local sim, cl = santase(seed)
        holdReveals(sim, cl[I], true)
        local gid, L = finish(sim, cl[I])
        if L[1] == I then -- the dealer Петър won
          local s, t0 = cl[I].session, sim.clock
          if s.fairTimer then s.fairTimer.cancel(); s.fairTimer = nil end -- a host that never orders the "noreveal"
          sim.bus.filter = nil
          local started = false
          for _ = 1, C.STAKE_BREAK_MATCH + 5 do
            if cl[I]:startGame() == true then started = true; break end
            sim:run(1)
          end
          ok(started, "the next match never starts")
          sim:run(0)
          ok(sim.clock - t0 < C.STAKE_FAIR_WAIT - 2, "inside the note's own wait")
          eq({ noteOf(cl[I], gid).foul, noteOf(cl[I], gid).wait }, { "deal", nil })
          eq(noteOf(cl[P], gid).wait, nil)
          for _, name in ipairs({ I, P }) do
            ok(cl[name].session.stakeLive, name); eq(cl[name].session.stakeFoul, nil, name)
          end
          return
        end
      end
      error("Петър never wins")
    end)
  end)
end)

Play.restore()
