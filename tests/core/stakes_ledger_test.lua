Loader.lib("Libs/LibStub/LibStub.lua")
Loader.lib("Libs/AceSerializer-3.0/AceSerializer-3.0.lua")
Loader.lib("Libs/LibDeflate/LibDeflate.lua")
local Sim = require("sim")
local ns = Sim.ns
local C, Ledger, View, Stakes, Bots = ns.Const, ns.Ledger, ns.LedgerView, ns.Stakes, ns.Bots

-- The real wire, as wow/Adapter.lua installs it: the GUILD budget counts packed parts
-- (restored at the end of this file).
local wire = ns.Wire.new(LibStub("AceSerializer-3.0"), LibStub("LibDeflate"))
local stand = ns.LedgerNet.size
ns.LedgerNet.size = function(msg) return #wire:pack(msg) end
local function packed(msg) return #wire:pack(msg) end

-- И hosts; М, П, Г, Д are guild members.
local A, B, P, G, D = "Иван Петров", "Мария Стоянова", "Петър Колев", "Гошо Тодоров", "Дара Маринова"
local SK = 50000
local EPOCH0 = 1700000000

-- И, М, П (and `more`), all in one group, past their login queues.
local function setup(more)
  local sim, cl = Sim.new(), {}
  for _, name in ipairs({ A, B, P }) do cl[name] = sim:add(name) end
  for _, name in ipairs(more or {}) do cl[name] = sim:add(name) end
  for _, env in pairs(sim.envs) do env.inGroup = function() return true end end
  sim:run(1)
  sim:settle()
  return sim, cl
end

local function record(client, event)
  local list = {}
  client:on(event, function(...) list[#list + 1] = { ... } end)
  return list
end

-- The GUILD LEVs of `from` after sim.sent[mark] (from = nil: anyone's).
local function levs(sim, from, mark)
  local out = {}
  for i, s in ipairs(sim.sent) do
    if i > (mark or 0) and (from == nil or s.from == from) and s.channel == "GUILD" and s.msg.t == "LEV" then out[#out + 1] = s.msg end
  end
  return out
end

-- Every entry of kind k in those LEVs.
local function sentOf(sim, from, mark, k)
  local out = {}
  for _, m in ipairs(levs(sim, from, mark)) do
    for _, e in ipairs(m.ev) do if k == nil or e.k == k then out[#out + 1] = e end end
  end
  return out
end

local function view(client) return View.of(client.ledger) end
local function debtOf(client, key)
  for _, d in ipairs(view(client).debts) do if d.key == key then return d end end
end
local function count(client)
  local n = 0
  client.ledger:each(function() n = n + 1 end)
  return n
end
local function bodyOf(client, i) return (client.ledger:get(i)) end

-- Морски шах ------------------------------------------------------------------

local LINES = { { 1, 2, 3 }, { 4, 5, 6 }, { 7, 8, 9 }, { 1, 4, 7 }, { 2, 5, 8 }, { 3, 6, 9 }, { 1, 5, 9 }, { 3, 5, 7 } }
local function completes(board, seat, c)
  for _, l in ipairs(LINES) do
    local n, hit = 0, false
    for _, x in ipairs(l) do if x == c then hit = true elseif board[x] == seat then n = n + 1 end end
    if hit and n == 2 then return true end
  end
  return false
end
-- The cell `seat` marks: the winner completes or blocks a line, the loser never completes one.
local function pick(board, seat, wins)
  local free = {}
  for _, c in ipairs({ 5, 1, 3, 7, 9, 2, 4, 6, 8 }) do if board[c] == 0 then free[#free + 1] = c end end
  for _, c in ipairs(free) do if wins and completes(board, seat, c) then return c, true end end
  for _, c in ipairs(free) do if wins and completes(board, 3 - seat, c) then return c end end
  for _, c in ipairs(free) do if not wins and not completes(board, seat, c) then return c end end
  return free[1]
end

-- The players by[seat] play until `winner` has won the match; before its
-- last mark `last()` runs (when given). -> the q of the winning mark
local function match(sim, by, winner, last)
  for _ = 1, 600 do
    local s = by[1].session or by[2].session
    if s.state.phase == "match" then return s.seq end
    local seat = s.state.phase == "play" and s.state.turn
    if seat then
      local st = by[seat].session.state
      local c, wins = pick(st.board, seat, seat == winner)
      if wins and seat == winner and st.score[seat] == ns.Engines.ttt.WINS - 1 and last then last() end
      ok(by[seat]:act({ k = "mark", c = c }))
      sim:run(0)
      if (by[1].session or by[2].session).state.phase == "match" then return (by[1].session or by[2].session).seq end
    end
    sim:run(1)
  end
  error("the match did not end")
end

-- И's staked (or fun) Морски шах, М seated: the match runs, И on turn.
local function ttt(sim, cl, sk)
  local tid = cl[A]:openTable{ game = "ttt", access = "guild", turn = 45, stake = sk }; sim:run(3)
  cl[B]:sit(tid, 2, sk); sim:run(1)
  return tid
end

-- Death Roll ------------------------------------------------------------------

-- И's staked Death Roll from `start`, `others` in seats 2..: started, И on turn.
local function dr(sim, cl, others, sk, start)
  local tid = cl[A]:openTable{ game = "deathroll", access = "guild", turn = 45, opt = { start = start or 100 }, stake = sk }
  sim:run(3)
  for i, name in ipairs(others) do cl[name]:sit(tid, i + 1, sk) end
  sim:run(1)
  ok(cl[A]:startGame()); sim:run(0)
  return tid
end

local function roll(sim, client, n)
  sim.nextRolls = { n }
  ok(client:roll()); sim:run(0)
end

describe("stakes: from a game to the ledger", function()
  it("Stakes.pairs: every loser to every winner", function()
    eq(Stakes.pairs({ "a" }, { "b", "c" }, 5), { { f = "a", t = "b", c = 5 }, { f = "a", t = "c", c = 5 } })
    eq(Stakes.pairs({ "a", "b" }, { "c" }, 7), { { f = "a", t = "c", c = 7 }, { f = "b", t = "c", c = 7 } })
    eq(Stakes.pairs({}, { "c" }, 7), {})
  end)

  it("ttt: the loser owes the winner; three entries, all confirmed", function()
    local sim, cl = setup()
    local tid = ttt(sim, cl, SK)
    local mark = #sim.sent
    local q = match(sim, { cl[A], cl[B] }, 1)
    sim:run(10)
    local gid = tid .. "/" .. q
    local mine = levs(sim, A, mark)
    eq(#mine, 1); eq(#mine[1].ev, 2)
    local r, d = mine[1].ev[1], mine[1].ev[2]
    eq({ r.k, r.gid, r.g, r.n, r.w, r.l, r.sk, r.why }, { "R", gid, "ttt", { A, B }, { 1 }, { 2 }, SK, nil })
    eq({ d.k, d.gid, d.f, d.t, d.c, d.why }, { "D", gid, B, A, SK, "lost" })
    local hers = levs(sim, B, mark)
    eq(#hers, 1); eq(#hers[1].ev, 1)
    eq({ hers[1].ev[1].k, hers[1].ev[1].r, hers[1].ev[1].dh }, { "C", d.i, bodyOf(cl[B], d.i).h })
    eq(#levs(sim, P, mark), 0); eq(#levs(sim, nil, mark), 2)
    eq(View.net(view(cl[P]), B, A), SK); eq(debtOf(cl[P], gid .. "|" .. B .. "|" .. A).status, "confirmed")
    for _, name in ipairs({ A, B }) do
      local note = cl[name].env.db.stakeSeen[gid]
      eq({ note.tid, note.q, note.sk, note.g, note.why, note.foul, note.pairs }, { tid, q, SK, "ttt", "lost", nil, { { f = B, t = A, c = SK } } })
      eq(cl[name].stakes:last(tid), note)
    end
    -- No more: no claim is missing, so nobody writes a debt of its own at 60 s.
    sim:run(C.STAKE_OWE_WAIT); eq(#levs(sim, nil, mark), 2)
  end)

  it("ttt: a rematch is a second debt with its own gid", function()
    local sim, cl = setup()
    local tid = ttt(sim, cl, SK)
    local q1 = match(sim, { cl[A], cl[B] }, 2); sim:run(5)
    ok(cl[A]:act({ k = "rematch" })); ok(cl[B]:act({ k = "rematch" })); sim:run(1)
    eq(cl[A].session.state.phase, "play")
    local q2 = match(sim, { cl[A], cl[B] }, 2); sim:run(10)
    ok(q1 ~= q2, "two gids")
    eq(debtOf(cl[P], tid .. "/" .. q1 .. "|" .. A .. "|" .. B).status, "confirmed")
    eq(debtOf(cl[P], tid .. "/" .. q2 .. "|" .. A .. "|" .. B).status, "confirmed")
    eq(View.net(view(cl[P]), A, B), 2 * SK)
  end)

  it("a fun game writes only its result", function()
    local sim, cl = setup()
    local tid = ttt(sim, cl, nil)
    local mark = #sim.sent
    local q = match(sim, { cl[A], cl[B] }, 1); sim:run(10)
    local all = sentOf(sim, nil, mark)
    eq(#all, 1); eq(#levs(sim, A, mark), 1)
    eq({ all[1].k, all[1].gid, all[1].n, all[1].w, all[1].l, all[1].sk }, { "R", tid .. "/" .. q, { A, B }, { 1 }, { 2 }, nil })
    eq(cl[B].env.db.stakeSeen, nil); eq(View.claims(view(cl[B]), B), {})
  end)

  it("a bot table writes no entry, staked or fun (F12)", function()
    for _, sk in ipairs({ SK, false }) do
      local sim, cl = setup()
      for _, env in pairs(sim.envs) do env.noLedger = function() return true end end
      local mark = #sim.sent
      ttt(sim, cl, sk or nil)
      match(sim, { cl[A], cl[B] }, 1); sim:run(C.STAKE_OWE_WAIT + 5)
      eq(#levs(sim, nil, mark), 0)
      for _, c in pairs(cl) do eq(count(c), 0) end
    end
    -- Bots.enable installs it: a match against a bot leaves my ledger empty.
    local sim = Sim.new()
    local a, envA = sim:add(A, { cls = "MAGE" }); Bots.enable(a, envA, sim.makeEnv)
    sim:run(1); sim:settle()
    local tid = a:openTable{ game = "ttt", access = "invite", turn = 45 }; ok(a:invite("Bot Ivanov")); sim:run(5)
    eq(envA.noLedger(tid), true); eq(envA.noLedger("Някой#1"), false)
    for _ = 1, 400 do
      local s = a.session
      if s.state and s.state.phase == "match" then break end
      if s.state and s.state.phase == "play" and s.state.turn == 1 then a:act(ns.Engines.ttt.auto(s.state, 1)) end
      sim:run(1)
    end
    eq(a.session.state.phase, "match"); sim:run(10)
    eq(count(a), 0)
  end)

  it("stakes:asks() emits debtAsk when a claim joins it or answer removes it, not when nothing changed (F19)", function()
    local sim, cl = setup()
    local asked = record(cl[B], "debtAsk")
    local gid = "Някой#1700000000/7"
    cl[A].ledgerNet:make("D", { gid = gid, g = "ttt", f = B, t = A, c = SK, why = "lost" }); sim:run(5)
    eq(#asked, 1)
    local asks = cl[B].stakes:asks()
    eq(#asks, 1); eq(asks[1].key, gid .. "|" .. B .. "|" .. A); eq(asks[1].c, SK)
    cl[B].stakes:review(); cl[B].stakes:review(); sim:run(5); eq(#asked, 1)
    eq(cl[B].stakes:answer("no such key", true), nil); eq(#asked, 1)
    eq(cl[B].stakes:answer(asks[1].key, true), true)
    eq(#asked, 2); eq(cl[B].stakes:asks(), {})
    sim:run(5)
    eq(#asked, 2); eq(debtOf(cl[A], asks[1].key).status, "confirmed")
  end)

  it("death roll, four players: who rolls 1 owes each of the others", function()
    local sim, cl = setup({ G })
    local tid = dr(sim, cl, { B, P, G }, SK)
    local mark = #sim.sent
    roll(sim, cl[A], 50); roll(sim, cl[B], 40); roll(sim, cl[P], 1)
    local q = cl[A].session.seq
    sim:run(15)
    local gid = tid .. "/" .. q
    local ds = sentOf(sim, nil, mark, "D")
    eq(#ds, 3)
    local authors = {}
    for _, d in ipairs(ds) do
      eq({ d.gid, d.f, d.c, d.why }, { gid, P, SK, "lost" }); authors[Ledger.author(d.i)] = d.t
    end
    eq(authors, { [A] = A, [B] = B, [G] = G })
    local his = levs(sim, P, mark)
    eq(#his, 1); eq(#his[1].ev, 3)
    for _, e in ipairs(his[1].ev) do eq(e.k, "C") end
    for _, t in ipairs({ A, B, G }) do eq(View.net(view(cl[A]), P, t), SK) end
    local r = sentOf(sim, A, mark, "R")
    eq(#r, 1); eq({ r[1].n, r[1].l, r[1].w, r[1].sk }, { { A, B, P, G, false }, { 3 }, { 1, 2, 4 }, SK })
  end)

  it("ttt: pressing „Стани“ mid-game forfeits at once", function()
    local sim, cl = setup()
    local tid = ttt(sim, cl, SK)
    local seen = { record(cl[A], "forfeit"), record(cl[B], "forfeit") }
    ok(cl[A]:act({ k = "mark", c = 1 })); sim:run(0)
    local mark = #sim.sent
    cl[B]:stand(); sim:run(10)
    for _, list in ipairs(seen) do
      eq(#list, 1)
      local f = list[1][1]
      eq({ f.tid, f.name, f.to, f.why, f.sk, f.seat }, { tid, B, { A }, "left", SK, 2 })
    end
    local gid = tid .. "/" .. seen[1][1][1].q
    local left = cl[B].env.db.stakeLeft[tid]
    eq({ left.sk, left.names }, { SK, { A } })
    local d = sentOf(sim, A, mark, "D")
    eq(#d, 1); eq({ d[1].gid, d[1].f, d[1].t, d[1].c, d[1].why }, { gid, B, A, SK, "left" })
    eq(#sentOf(sim, B, mark, "C"), 1)
    eq(debtOf(cl[P], gid .. "|" .. B .. "|" .. A).status, "confirmed")
    eq(cl[A].session.status, "aborted")
  end)

  it("a stand with a reason the ledger does not know is recorded as left: the creditors' claims stay valid (final review Minor 1)", function()
    local sim, cl = setup()
    local tid = dr(sim, cl, { B, P }, SK)
    local seen, mark = record(cl[P], "forfeit"), #sim.sent
    cl[A].session:event(0, { k = "stand", seat = 2, why = "x" }); sim:run(10) -- a modified host stands Мария up
    eq(#seen, 1); eq(seen[1][1].why, "left")
    local ds = sentOf(sim, nil, mark, "D")
    eq(#ds, 2)
    for _, d in ipairs(ds) do eq({ d.gid, d.f, d.c, d.why }, { tid .. "/" .. seen[1][1].q, B, SK, "left" }) end
    local r = sentOf(sim, A, mark, "R")
    eq(#r, 1); eq(r[1].why, "left")
  end)

  it("other left claims at a table I left: one just after my stand is put to me, one of a game I was not in is contested", function()
    local sim, cl = setup()
    local tid = ttt(sim, cl, SK)
    ok(cl[A]:act({ k = "mark", c = 1 })); sim:run(0)
    cl[B]:stand(); sim:run(10)
    local lq, mark = cl[B].env.db.stakeLeft[tid].q, #sim.sent
    cl[A].ledgerNet:make("D", { gid = tid .. "/" .. (lq + 1), g = "ttt", f = B, t = A, c = SK, why = "left" })
    cl[A].ledgerNet:make("D", { gid = tid .. "/" .. 999, g = "ttt", f = B, t = A, c = SK, why = "left" }); sim:run(10)
    local n = sentOf(sim, B, mark)
    eq(#n, 1); eq({ n[1].k, n[1].why }, { "N", "forged" })
    local asks = cl[B].stakes:asks()
    eq(#asks, 1); eq(asks[1].gid, tid .. "/" .. (lq + 1))
    eq(View.net(view(cl[P]), B, A), SK)
  end)

  it("a left claim far past my stand is asked while my stand's own claim has not come: in-flight timing is never contested", function()
    local sim, cl = setup()
    local tid = ttt(sim, cl, SK)
    ok(cl[A]:act({ k = "mark", c = 1 })); sim:run(0)
    local held = {}
    sim.bus.filter = function(from, to, _, m)
      if from == A and to == B and m.t == "LEV" then held[#held + 1] = m; return {} end
      return { m }
    end
    local mark = #sim.sent
    cl[B]:stand(); sim:run(10)
    local lq = cl[B].env.db.stakeLeft[tid].q
    -- As if my host had ordered many events while my STD was in flight: my stand's claim at lq + 6.
    eq(cl[B].ledgerNet:take(cl[A].ledgerNet:make("D", { gid = tid .. "/" .. (lq + 6), g = "ttt", f = B, t = A, c = SK, why = "left" }), A, true), "new")
    sim:run(10)
    eq(#sentOf(sim, B, mark), 0)
    local asks = cl[B].stakes:asks()
    eq(#asks, 1); eq(asks[1].gid, tid .. "/" .. (lq + 6))
    sim.bus.filter = nil
  end)

  it("an asked seat's stand leaves an inert leave: an earlier used leave never contests the host's shifted claim", function()
    local sim, cl = setup()
    local tid = dr(sim, cl, { B }, SK)
    sim.envs[B].db.stakeSat = nil -- a crash: no note of the stake I accepted
    local b = sim:relog(B); sim:run(3); sim:settle()
    eq(b.session.stakeAsk, true)
    local seq = b.session.seq
    -- An earlier „Стани“ of mine at this table against Иван, its claim already confirmed.
    b.env.db.stakeLeft = { [tid] = { at = EPOCH0 + sim.clock - 30, sk = SK, names = { A }, q = seq - 6, used = { [A] = "0123456789abcdef" } } }
    local mark = #sim.sent
    ns.Stake.standUp(b, b.session); sim:run(1)
    -- The host's claim, shifted by one event in flight.
    eq(b.ledgerNet:take(cl[A].ledgerNet:make("D", { gid = tid .. "/" .. (seq + 2), g = "deathroll", f = B, t = A, c = SK, why = "left" }), A, true), "new")
    sim:run(10)
    eq(#sentOf(sim, B, mark), 0)
    local gids = {}
    for _, d in ipairs(b.stakes:asks()) do gids[#gids + 1] = d.gid end
    table.sort(gids)
    eq(gids, { tid .. "/" .. (seq + 1), tid .. "/" .. (seq + 2) })
    local inert = b.env.db.stakeLeft[tid]
    eq({ inert.q, inert.names, inert.sk, inert.used }, { seq + 1, { A }, nil, nil })
  end)

  it("a far left claim is contested only when it comes within LEAVE_AT_SLACK of the stored leave (a crash may have lost a later one)", function()
    local sim, cl = setup()
    local tid = ttt(sim, cl, SK)
    match(sim, { cl[A], cl[B] }, 1); sim:run(10)
    cl[B]:stand(); sim:run(1) -- after the game: no leave of its own
    -- My saved leave of this table, its claim confirmed, from 300 s ago; a later „Стани“ of mine was lost with a crash.
    cl[B].env.db.stakeLeft = { [tid] = { at = EPOCH0 + sim.clock - 300, sk = SK, names = { A }, q = 3, used = { [A] = "0123456789abcdef" } } }
    local mark = #sim.sent
    eq(cl[B].ledgerNet:take(cl[A].ledgerNet:make("D", { gid = tid .. "/" .. 60, g = "ttt", f = B, t = A, c = SK, why = "left" }), A, true), "new")
    sim:run(10)
    eq(#sentOf(sim, B, mark), 0)
    local asks = cl[B].stakes:asks()
    eq(#asks, 1); eq(asks[1].gid, tid .. "/60")
  end)

  it("my „Стани“ confirms only its own claim, whatever comes first (review probe A)", function()
    local sim, cl = setup()
    local tid = ttt(sim, cl, SK)
    ok(cl[A]:act({ k = "mark", c = 1 })); sim:run(0)
    local held = {}
    sim.bus.filter = function(from, to, _, m)
      if from == A and to == B and m.t == "LEV" then held[#held + 1] = m; return {} end
      return { m }
    end
    local mark = #sim.sent
    cl[B]:stand(); sim:run(10)
    sim.bus.filter = nil
    ok(#held > 0, "the real claim is held")
    cl[A].ledgerNet:make("D", { gid = tid .. "/999", g = "ttt", f = B, t = A, c = SK, why = "left" }); sim:run(10)
    for _, m in ipairs(held) do cl[B]:receive("GUILD", A, m) end
    sim:run(10)
    local c, n = sentOf(sim, B, mark, "C"), sentOf(sim, B, mark, "N")
    eq(#c, 1); eq(bodyOf(cl[B], c[1].r).gid, tid .. "/" .. cl[B].env.db.stakeLeft[tid].q)
    eq(#n, 1); eq(n[1].why, "forged"); eq(cl[B].stakes:asks(), {})
    eq(View.net(view(cl[P]), B, A), SK)
  end)

  it("my „Стани“ never confirms an earlier game of that table I lost unfairly (review probe B)", function()
    local sim, cl = setup()
    local tid = ttt(sim, cl, SK)
    ok(cl[A]:act({ k = "mark", c = 1 })); sim:run(0)
    sim.bus.filter = function(from, _, _, m)
      if from == B and m.t == "ACT" then m.a = { k = "mark", c = 9 } end
      return { m }
    end
    ok(cl[B]:act({ k = "mark", c = 5 })); sim:run(1)
    sim.bus.filter = nil
    local gid1
    match(sim, { cl[A], cl[B] }, 1, function()
      gid1 = tid .. "/" .. (cl[A].session.seq + 1)
      cl[A].stakes.did["D" .. gid1 .. "|" .. B .. "|" .. A] = true -- this creditor withholds its normal claim
    end)
    sim:run(10)
    eq(cl[B].env.db.stakeSeen[gid1].foul, "forged")
    ok(cl[A]:act({ k = "rematch" })); ok(cl[B]:act({ k = "rematch" })); sim:run(1)
    if cl[A].session.state.turn == 1 then ok(cl[A]:act({ k = "mark", c = 1 })) end
    sim:run(0)
    local mark = #sim.sent
    cl[B]:stand() -- and the claim for game 1 reaches her before the one for her stand
    eq(cl[B].ledgerNet:take(cl[A].ledgerNet:make("D", { gid = gid1, g = "ttt", f = B, t = A, c = SK, why = "left" }), A, true), "new")
    sim:run(20)
    local n = sentOf(sim, B, mark, "N")
    eq(#n, 1); eq(n[1].why, "forged"); eq(#sentOf(sim, B, mark, "C"), 1)
    eq(debtOf(cl[P], gid1 .. "|" .. B .. "|" .. A).status, "contested"); eq(View.net(view(cl[P]), B, A), SK)
  end)

  it("„Стани“ confirms only the table's stake", function()
    local sim, cl = setup()
    ttt(sim, cl, SK)
    ok(cl[A]:act({ k = "mark", c = 1 })); sim:run(0)
    sim.bus.filter = function(from, _, _, m)
      if from == A and m.t == "LEV" then for _, e in ipairs(m.ev) do if e.k == "D" then e.c = 2 * SK end end end
      return { m }
    end
    local mark = #sim.sent
    cl[B]:stand(); sim:run(10)
    sim.bus.filter = nil
    local n = sentOf(sim, B, mark, "N")
    eq(#n, 1); eq(n[1].why, "amount"); eq(#sentOf(sim, B, mark, "C"), 0)
  end)

  it("„Стани“ in a game my client did not see whole is put to me, never confirmed by the leave note (final review C1)", function()
    local sim, cl = setup()
    ttt(sim, cl, SK)
    ok(cl[A]:act({ k = "mark", c = 1 })); sim:run(0)
    cl[B]:stop(); local b = sim:relog(B); sim:run(3); sim:settle()
    eq(b.session.stakeFoul, "unseen")
    local mark, asked = #sim.sent, record(b, "debtAsk")
    b:stand(); sim:run(10)
    eq(#sentOf(sim, A, mark, "D"), 1); eq(#sentOf(sim, B, mark, "C"), 0); eq(#sentOf(sim, B, mark, "N"), 0)
    eq(#asked, 1); eq(#b.stakes:asks(), 1); eq(b.stakes:asks()[1].t, A)
    eq(View.net(view(cl[P]), B, A), 0)
  end)

  it("my „Стани“ after a move forged for my seat is put to me, not confirmed (final review C1)", function()
    local sim, cl = setup()
    local tid = ttt(sim, cl, SK)
    ok(cl[A]:act({ k = "mark", c = 1 })); sim:run(0)
    -- Иван's modified client plays another cell than the one Мария sent.
    sim.bus.filter = function(from, _, _, m)
      if from == B and m.t == "ACT" then m.a = { k = "mark", c = 9 } end
      return { m }
    end
    ok(cl[B]:act({ k = "mark", c = 5 })); sim:run(1)
    sim.bus.filter = nil
    eq(cl[B].session.stakeFoul, "forged")
    local mark = #sim.sent
    cl[B]:stand(); sim:run(10)
    local gid = tid .. "/" .. cl[B].env.db.stakeLeft[tid].q
    eq(cl[B].env.db.stakeSeen[gid].foul, "forged")
    local d = sentOf(sim, A, mark, "D")
    eq(#d, 1); eq({ d[1].gid, d[1].why }, { gid, "left" })
    eq(#sentOf(sim, B, mark, "C"), 0)
    eq(#cl[B].stakes:asks(), 1); eq(cl[B].stakes:asks()[1].gid, gid)
    eq(debtOf(cl[P], gid .. "|" .. B .. "|" .. A).status, "pending"); eq(View.net(view(cl[P]), B, A), 0)
  end)

  it("Death Roll: my „Стани“ after a roll recorded with another number than I saw is put to me (final review C1)", function()
    local sim, cl = setup()
    local tid = dr(sim, cl, { B }, SK)
    -- Мария sees Иван roll 41; his client records 40.
    sim.canSee = function(from, to) return not (from == A and to == B) end
    cl[B]:rollSeen("Иван", 41, 1, 100); roll(sim, cl[A], 40)
    sim.canSee = function() return true end
    sim:run(C.ROLL_VERIFY_WAIT)
    eq(ns.Rolls.audit(cl[B].session), "roll"); eq(cl[B].session.stakeFoul, nil)
    local mark = #sim.sent
    cl[B]:stand(); sim:run(C.ROLL_FINAL_WAIT + 10)
    local gid = tid .. "/" .. cl[B].env.db.stakeLeft[tid].q
    eq(cl[B].env.db.stakeSeen[gid].foul, "roll")
    eq(#sentOf(sim, A, mark, "D"), 1); eq(#sentOf(sim, B, mark, "C"), 0)
    eq(#cl[B].stakes:asks(), 1); eq(View.net(view(cl[P]), B, A), 0)
  end)

  it("Death Roll: a clean „Стани“ waits for the last roll verdict, then confirms", function()
    local sim, cl = setup()
    local tid = dr(sim, cl, { B }, SK)
    roll(sim, cl[A], 40) -- its verdict on Мария's client is still pending when she stands
    local mark = #sim.sent
    cl[B]:stand(); sim:run(1)
    local gid = tid .. "/" .. cl[B].env.db.stakeLeft[tid].q
    eq(cl[B].env.db.stakeSeen[gid].wait, true); eq(#sentOf(sim, B, mark, "C"), 0); eq(cl[B].stakes:asks(), {})
    sim:run(C.ROLL_FINAL_WAIT + 5)
    eq(cl[B].env.db.stakeSeen[gid].foul, nil); eq(#sentOf(sim, B, mark, "C"), 1)
    eq(View.net(view(cl[P]), B, A), SK)
  end)

  it("a host that stands up from a game its client did not see whole is asked too (final review C1)", function()
    local sim, cl = setup()
    local tid = ttt(sim, cl, SK)
    ok(cl[A]:act({ k = "mark", c = 1 })); sim:run(0)
    ns.Stakes.foul(cl[A].session, "unseen")
    local mark = #sim.sent
    cl[A]:stand(); sim:run(10)
    local gid = tid .. "/" .. cl[A].env.db.stakeLeft[tid].q
    eq(cl[A].env.db.stakeSeen[gid].foul, "unseen")
    eq(#sentOf(sim, B, mark, "D"), 1); eq(#sentOf(sim, A, mark, "C"), 0); eq(#cl[A].stakes:asks(), 1)
  end)

  it("a claim whose id holds a claim of another game as well gets my own D, not a C", function()
    local sim, cl = setup()
    local tid = ttt(sim, cl, SK)
    sim.bus.filter = function(from, to, _, m)
      if from == A and to == B and m.t == "LEV" then return {} end
      return { m }
    end
    local q = match(sim, { cl[A], cl[B] }, 1); sim:run(5)
    sim.bus.filter = nil
    local gid, d = tid .. "/" .. q, sentOf(sim, A, 0, "D")[1] -- Иван's claim, as it went out
    local twin = ns.Util.copy(d)
    twin.gid = "Някой#1700000000/3" -- the same id in another game (a creditor that lost its files)
    local mark = #sim.sent
    eq(cl[B].ledgerNet:take(twin, P), "new"); eq(cl[B].ledgerNet:take(d, A, true), "twin")
    sim:run(5)
    local mine = sentOf(sim, B, mark)
    eq(#mine, 1); eq({ mine[1].k, mine[1].gid, mine[1].f, mine[1].t, mine[1].c, mine[1].why }, { "D", gid, B, A, SK, "lost" })
    eq(debtOf(cl[B], gid .. "|" .. B .. "|" .. A).status, "confirmed")
    local asks = cl[B].stakes:asks()
    eq(#asks, 1); eq(asks[1].gid, twin.gid) -- the other game's claim is put to her
  end)

  it("standing up after the game is over costs nothing; a watcher or a player who sat down mid-game leaving neither", function()
    local sim, cl = setup()
    ttt(sim, cl, SK)
    match(sim, { cl[A], cl[B] }, 1); sim:run(5)
    local forfeits, mark = record(cl[A], "forfeit"), #sim.sent
    cl[B]:stand(); sim:run(10)
    eq(forfeits, {}); eq(#sentOf(sim, nil, mark), 0); eq(cl[B].env.db.stakeLeft, nil)
    -- Death Roll: Г watches, П sits down after the start; both leave mid-game.
    sim, cl = setup({ G })
    local tid = dr(sim, cl, { B }, SK)
    forfeits = { record(cl[A], "forfeit"), record(cl[P], "forfeit"), record(cl[G], "forfeit") }
    cl[G]:watch(tid); sim:run(1)
    cl[P]:sit(tid, 3, SK); sim:run(1)
    eq(cl[A].session.seats[3], P); eq(cl[A].session.stakeRoster, { A, B })
    mark = #sim.sent
    cl[P]:stand(); cl[G]:stand(); sim:run(10)
    for _, list in ipairs(forfeits) do eq(list, {}) end
    eq(#sentOf(sim, nil, mark), 0); eq(cl[P].env.db.stakeLeft, nil); eq(cl[G].env.db.stakeLeft, nil)
  end)

  it("death roll, three players: a leaver owes both others and the game goes on", function()
    local sim, cl = setup()
    local tid = dr(sim, cl, { B, P }, SK)
    roll(sim, cl[A], 50)
    eq(cl[A].session.state.turn, 2)
    cl[P]:stand(); sim:run(10)
    eq(cl[A].session.status, "live"); eq(cl[A].session.stakeRoster, { A, B })
    roll(sim, cl[B], 1); sim:run(15)
    eq(View.net(view(cl[A]), P, A), SK); eq(View.net(view(cl[A]), P, B), SK); eq(View.net(view(cl[A]), B, A), SK)
    eq(View.net(view(cl[B]), P, A), SK); eq(View.net(view(cl[B]), B, A), SK)
    local claims = 0
    for _, d in ipairs(view(cl[A]).debts) do
      if d.f == P then claims = claims + 1; eq({ d.why, d.status }, { "left", "confirmed" }) end
    end
    eq(claims, 2)
    eq(cl[A].stakes:last(tid).pairs, { { f = B, t = A, c = SK } }) -- П is no winner
  end)

  it("offline: the forfeit waits for the leaver; she is asked once she logs in", function()
    for _, yes in ipairs({ true, false }) do
      local sim, cl = setup()
      local tid = ttt(sim, cl, SK)
      local mark = #sim.sent
      sim.envs[B].dead = true; sim:offline(B) -- her client is gone (a disconnect)
      sim:run(C.OFFLINE_STAND_SECONDS + 5)
      eq(cl[A].session.seats[2], false)
      local d = sentOf(sim, A, mark, "D")
      eq(#d, 1); eq({ d[1].f, d[1].t, d[1].why, d[1].c }, { B, A, "offline", SK })
      local key = d[1].gid .. "|" .. B .. "|" .. A
      eq(debtOf(cl[A], key).status, "pending"); eq(debtOf(cl[P], key).status, "pending")
      eq(#sentOf(sim, nil, mark, "C"), 0)
      sim:run(3600)
      local b = sim:relog(B)
      local asked = record(b, "debtAsk")
      sim:run(90)
      local asks = b.stakes:asks()
      eq(#asks, 1); eq(asks[1].key, key); eq(#asked, 1)
      if yes then
        ok(b.stakes:answer(key, true)); sim:run(5)
        eq(debtOf(cl[A], key).status, "confirmed"); eq(debtOf(cl[P], key).status, "confirmed"); eq(View.net(view(cl[P]), B, A), SK)
      else
        -- The leaver may contest.
        ok(b.stakes:answer(key, false)); sim:run(5)
        local n = sentOf(sim, B, mark, "N")
        eq(#n, 1); eq(n[1].why, "no")
        for _, c in ipairs({ cl[A], cl[P], b }) do eq(debtOf(c, key).status, "contested"); eq(View.net(view(c), B, A), 0) end
      end
      eq(b.stakes:asks(), {}); eq(#asked, 2)
    end
  end)

  it("a host that stands an online player up gets a contested debt (residual E1)", function()
    local sim, cl = setup()
    ttt(sim, cl, SK)
    local asked, mark = record(cl[B], "debtAsk"), #sim.sent
    sim:run(10)
    local s = cl[A].session
    ns.Succession.untrack(s, B)
    s:event(0, { k = "stand", seat = 2, why = "offline" }); s:abortIfShort(); s:recordChanged()
    sim:run(10)
    local d = sentOf(sim, A, mark, "D")
    eq(#d, 1); eq(d[1].why, "offline")
    local n = sentOf(sim, B, mark, "N")
    eq(#n, 1); eq({ n[1].why, n[1].r }, { "stand", d[1].i })
    eq(asked, {}); eq(cl[B].stakes:asks(), {})
    eq(debtOf(cl[P], d[1].gid .. "|" .. B .. "|" .. A).status, "contested")
  end)

  it("a stand I hear of only by SNO \"gone\" is answered from the open note it leaves", function()
    local sim, cl = setup()
    local tid = dr(sim, cl, { B }, SK)
    roll(sim, cl[A], 50)
    cl[A].session.idleTimer.cancel() -- this host plays its stand by hand, and never tells her
    sim.bus.filter = function(from, to, _, m)
      if from == A and to == B and m.t == "EV" and m.a and m.a.k == "stand" then return {} end
      return { m }
    end
    sim:run(10)
    local s, mark = cl[A].session, #sim.sent
    ns.Succession.untrack(s, B)
    s:event(0, { k = "stand", seat = 2, why = "offline" }); s:abortIfShort(); s:recordChanged()
    sim:run(C.PING_EVERY + 5)
    sim.bus.filter = nil
    eq(cl[B].session, nil)
    local open
    for _, n in pairs(cl[B].env.db.stakeSeen) do if n.open then open = n end end
    eq({ open.tid, open.foul, open.h, open.sk }, { tid, "stand", A, SK })
    local d = sentOf(sim, A, mark, "D")
    eq(#d, 1); ok(tonumber(d[1].gid:match("/(%d+)$")) > open.q, "the claim's q is after the note's")
    local n = sentOf(sim, B, mark, "N")
    eq(#n, 1); eq({ n[1].why, n[1].r }, { "stand", d[1].i }); eq(cl[B].stakes:asks(), {})
  end)

  it("an asked seat that stands up mid-game is asked about the host's claim, never confirmed by itself", function()
    local sim, cl = setup()
    local tid = dr(sim, cl, { B }, SK)
    sim.envs[B].db.stakeSat = nil -- a crash: no note of the stake I accepted
    local b = sim:relog(B); sim:run(3); sim:settle()
    eq(b.session.stakeAsk, true)
    -- An earlier „Стани“ of mine at this table, a little before: it never confirms this stand.
    local left = { at = EPOCH0 + sim.clock, sk = SK, names = { A }, q = b.session.seq - 1, used = {} }
    b.env.db.stakeLeft = { [tid] = left }
    local mark = #sim.sent
    ns.Stake.standUp(b, b.session); sim:run(10) -- as at a snapshot of another game (Member.adopt)
    eq(b.env.db.stakeLeft[tid].sk, nil); eq(left.used, {}) -- my leave here is now inert (fix round 2), nothing was used
    local d = sentOf(sim, A, mark, "D")
    eq(#d, 1); eq(d[1].why, "left")
    sim:run(30)
    eq(#sentOf(sim, B, mark), 0); eq(#b.stakes:asks(), 1)
  end)

  it("a forged move turns into a contest, not a debt (residual F8)", function()
    local sim, cl = setup()
    ttt(sim, cl, SK)
    ok(cl[A]:act({ k = "mark", c = 1 })); sim:run(0)
    local mark = #sim.sent
    sim.bus.filter = function(from, _, _, m)
      if from == B and m.t == "ACT" then m.a = { k = "mark", c = 9 } end
      return { m }
    end
    ok(cl[B]:act({ k = "mark", c = 5 })); sim:run(1)
    sim.bus.filter = nil
    eq(cl[B].session.stakeFoul, "forged")
    match(sim, { cl[A], cl[B] }, 1); sim:run(10)
    local n = sentOf(sim, B, mark, "N")
    eq(#n, 1); eq(n[1].why, "forged"); eq(#sentOf(sim, B, mark, "C"), 0)
    for _, c in pairs(cl) do eq(View.net(view(c), B, A), 0) end
  end)

  it("death roll: a roll I saw differently contests as roll; one I did not see is put to me; a claim before the verdict waits", function()
    -- Seen differently: Мария saw Иван's 50 as 41.
    local sim, cl = setup()
    dr(sim, cl, { B }, SK)
    local mark, asked = #sim.sent, record(cl[B], "debtAsk")
    sim.canSee = function(from, to) return not (from == A and to == B) end
    cl[B]:rollSeen("Иван", 41, 1, 100); roll(sim, cl[A], 50)
    sim.canSee = function() return true end
    roll(sim, cl[B], 1); sim:run(15)
    local n = sentOf(sim, B, mark, "N")
    eq(#n, 1); eq(n[1].why, "roll"); eq(cl[B].stakes:asks(), {}); eq(asked, {}) -- never put to her while the verdict was pending
    -- Not seen at all: the question.
    sim, cl = setup()
    dr(sim, cl, { B }, SK)
    mark = #sim.sent
    sim.canSee = function(from, to) return not (from == A and to == B) end
    roll(sim, cl[A], 50)
    sim.canSee = function() return true end
    roll(sim, cl[B], 1); sim:run(15)
    eq(#sentOf(sim, B, mark), 0); eq(#cl[B].stakes:asks(), 1)
    -- Clean: the claim comes at 2 s and waits for the roll part of the note (final at ROLL_FINAL_WAIT).
    sim, cl = setup()
    local tid = dr(sim, cl, { B }, SK)
    mark = #sim.sent
    roll(sim, cl[A], 50); roll(sim, cl[B], 1)
    local gid = tid .. "/" .. cl[A].session.seq
    sim:run(C.LEDGER_COALESCE + 1)
    ok(debtOf(cl[B], gid .. "|" .. B .. "|" .. A), "the claim is here")
    eq(cl[B].env.db.stakeSeen[gid].wait, true); eq(cl[B].stakes:asks(), {}); eq(debtOf(cl[B], gid .. "|" .. B .. "|" .. A).status, "pending")
    sim:run(C.ROLL_FINAL_WAIT - C.LEDGER_COALESCE - 1)
    eq(cl[B].env.db.stakeSeen[gid].wait, nil)
    sim:run(C.LEDGER_COALESCE)
    eq(#sentOf(sim, B, mark, "C"), 1); eq(debtOf(cl[P], gid .. "|" .. B .. "|" .. A).status, "confirmed")
  end)

  it("death roll: a modified host's idle stand after my own roll is contested as roll (F10)", function()
    local sim, cl = setup()
    dr(sim, cl, { B }, SK)
    roll(sim, cl[A], 50)
    local mark = #sim.sent
    sim.canSee = function(from, to) return not (from == B and to == A) end -- the host never sees her roll
    roll(sim, cl[B], 40)
    sim:run(C.OFFLINE_STAND_SECONDS + C.PING_EVERY + 5)
    eq(cl[A].session.seats[2], false)
    local d = sentOf(sim, A, mark, "D")
    eq(#d, 1); eq(d[1].why, "idle")
    local n = sentOf(sim, B, mark, "N")
    eq(#n, 1); eq({ n[1].why, n[1].r }, { "roll", d[1].i })
  end)

  it("ttt: an auto move for my seat with my ACT unmatched is contested as forged (F10)", function()
    local sim, cl = setup()
    ttt(sim, cl, SK)
    ok(cl[A]:act({ k = "mark", c = 1 })); sim:run(0)
    local mark = #sim.sent
    sim.bus.filter = function(from, _, _, m)
      if from == B and m.t == "ACT" then return {} end
      return { m }
    end
    sim:run(10); ok(cl[B]:act({ k = "mark", c = 9 }))
    sim:run(C.TURN_DEFAULT + C.AUTO_GRACE - 10)
    sim.bus.filter = nil
    eq(cl[B].session.stakeFoul, "forged")
    match(sim, { cl[A], cl[B] }, 1); sim:run(10)
    local n = sentOf(sim, B, mark, "N")
    eq(#n, 1); eq(n[1].why, "forged")
  end)

  it("a /reload mid-game keeps my staked seat and no forfeit is written (F11)", function()
    local sim, cl = setup()
    local tid = ttt(sim, cl, SK)
    local forfeits, mark = record(cl[A], "forfeit"), #sim.sent
    ok(cl[A]:act({ k = "mark", c = 1 })); sim:run(0)
    local b = sim:relog(B); sim:run(10)
    eq(b.session.tid, tid); eq(b.session.seats[2], B); eq(cl[A].session.seats[2], B)
    eq(forfeits, {}); eq(#sentOf(sim, nil, mark, "D"), 0)
  end)

  it("a claim for more than the table's stake is contested as amount (Review Focus 4)", function()
    local sim, cl = setup()
    ttt(sim, cl, SK)
    local mark = #sim.sent
    sim.bus.filter = function(from, _, _, m)
      if from == A and m.t == "LEV" then for _, e in ipairs(m.ev) do if e.k == "D" then e.c = 5000000 end end end
      return { m }
    end
    match(sim, { cl[A], cl[B] }, 1); sim:run(10)
    sim.bus.filter = nil
    local n = sentOf(sim, B, mark, "N")
    eq(#n, 1); eq(n[1].why, "amount"); eq(#sentOf(sim, B, mark, "C"), 0)
    eq(View.net(view(cl[P]), B, A), 0)
  end)

  it("a claim about a game I never played is put to me, not confirmed; twenty-five such claims from one creditor show twenty", function()
    local sim, cl = setup()
    local mark = #sim.sent
    for q = 1, 25 do
      cl[A].ledgerNet:make("D", { gid = "Някой#1700000000/" .. q, g = "ttt", f = B, t = A, c = SK, why = "lost" })
    end
    sim:run(60)
    eq(#sentOf(sim, A, mark, "D"), 25)
    eq(#cl[B].stakes:asks(), C.LEDGER_CLAIMS_OPEN); eq(#sentOf(sim, B, mark), 0)
  end)

  it("the claim may come before or after my note: one C", function()
    local sim, cl = setup()
    ttt(sim, cl, SK)
    local held, hold, asked = {}, false, record(cl[B], "debtAsk")
    sim.bus.filter = function(from, to, channel, m)
      if hold and from == A and to == B and channel == "WHISPER" then held[#held + 1] = m; return {} end
      return { m }
    end
    local mark = #sim.sent
    local q = match(sim, { cl[A], cl[B] }, 1, function() hold = true end)
    sim:run(C.LEDGER_COALESCE + 1)
    ok(#held > 0, "the winning EV is held")
    ok(debtOf(cl[B], cl[A].session.tid .. "/" .. q .. "|" .. B .. "|" .. A), "the claim came first")
    eq(cl[B].stakes:asks(), {}); eq(#sentOf(sim, B, mark), 0)
    hold, sim.bus.filter = false, nil
    for _, m in ipairs(held) do cl[B]:receive("WHISPER", A, m) end
    sim:run(10)
    eq(#sentOf(sim, B, mark, "C"), 1); eq(#sentOf(sim, B, mark), 1); eq(asked, {})
  end)

  it("the loser's note survives a relog and confirms the late claim (Review Focus 5)", function()
    local sim, cl = setup()
    local tid = ttt(sim, cl, SK)
    sim.bus.filter = function(from, to, _, m)
      if from == A and to == B and m.t == "LEV" then return {} end
      return { m }
    end
    local q = match(sim, { cl[A], cl[B] }, 1); sim:run(C.STAKE_OWE_WAIT - 5) -- she logs out just before her own debt would be due
    local gid = tid .. "/" .. q
    ok(cl[B].env.db.stakeSeen[gid], "her note"); eq(debtOf(cl[B], gid .. "|" .. B .. "|" .. A), nil)
    cl[B]:stop(); sim.bus.filter = nil
    local mark = #sim.sent
    local b = sim:relog(B)
    local asked = record(b, "debtAsk")
    sim:run(120)
    local c = sentOf(sim, B, mark, "C")
    eq(#c, 1); eq(#sentOf(sim, B, mark), 1); eq(asked, {})
    eq(debtOf(cl[P], gid .. "|" .. B .. "|" .. A).status, "confirmed")
  end)

  it("no claim within 60 s: the loser writes the debt itself", function()
    local sim, cl = setup()
    local tid = ttt(sim, cl, SK)
    local mark = #sim.sent
    local q = match(sim, { cl[A], cl[B] }, 1, function()
      -- Иван's client crashes on the winning move: it applies it, the EV goes out, nothing more.
      sim.bus.filter = function(from, _, _, m)
        if from == A and m.t ~= "EV" then return {} end
        return { m }
      end
    end)
    sim.envs[A].dead = true; sim:offline(A)
    local gid = tid .. "/" .. q
    sim:run(C.STAKE_OWE_WAIT - 1); eq(#sentOf(sim, B, mark), 0)
    sim:run(5)
    local d = sentOf(sim, B, mark, "D")
    eq(#d, 1); eq({ Ledger.author(d[1].i), d[1].gid, d[1].f, d[1].t, d[1].c, d[1].why }, { B, gid, B, A, SK, "lost" })
    local key = gid .. "|" .. B .. "|" .. A
    eq(debtOf(cl[B], key).status, "confirmed"); eq(debtOf(cl[P], key).status, "confirmed")
    -- Иван's own claim, late: still one debt of 50000.
    local late = { i = Ledger.id(A, 50), k = "D", at = EPOCH0 + sim.clock, gid = gid, g = "ttt", f = B, t = A, c = SK, why = "lost" }
    eq(cl[B].ledgerNet:take(late, A, true), "new"); sim:run(5)
    local n = 0
    for _, x in ipairs(view(cl[B]).debts) do if x.gid == gid then n = n + 1 end end
    eq(n, 1); eq(debtOf(cl[B], key).c, SK); eq(View.net(view(cl[B]), B, A), SK)
  end)

  it("no claim, and the loser reloads within 60 s: its own debt is still written, once", function()
    local sim, cl = setup()
    local tid = ttt(sim, cl, SK)
    local mark = #sim.sent
    local q = match(sim, { cl[A], cl[B] }, 1, function()
      sim.bus.filter = function(from, _, _, m)
        if from == A and m.t ~= "EV" then return {} end
        return { m }
      end
    end)
    sim.envs[A].dead = true; sim:offline(A)
    local gid, key = tid .. "/" .. q, tid .. "/" .. q .. "|" .. B .. "|" .. A
    sim:run(20)
    ok(cl[B].env.db.stakeSeen[gid].owe, "the due time is in the note")
    cl[B]:stop()
    local b = sim:relog(B); sim:run(C.LEDGER_ADOPT_WAIT + C.LEDGER_JITTER_MAX + C.LEDGER_SYNC_TIMEOUT + 5)
    local d = sentOf(sim, B, mark, "D")
    eq(#d, 1); eq({ Ledger.author(d[1].i), d[1].gid, d[1].f, d[1].t, d[1].c }, { B, gid, B, A, SK })
    eq(debtOf(cl[P], key).status, "confirmed"); eq(b.env.db.stakeSeen[gid].owe, nil)
    -- Once: another /reload writes nothing more.
    b:stop(); sim:relog(B); sim:run(200)
    eq(#sentOf(sim, B, mark, "D"), 1); eq(View.net(view(cl[P]), B, A), SK)
  end)

  it("nothing is written while my login queue is open, so two /reloads in it make one C", function()
    local sim, cl = setup()
    local tid = ttt(sim, cl, SK)
    sim.bus.filter = function(from, to, _, m)
      if from == A and to == B and m.t == "LEV" then return {} end
      return { m }
    end
    match(sim, { cl[A], cl[B] }, 1); sim:run(5)
    sim.bus.filter = nil
    local d = sentOf(sim, A, 0, "D")[1]
    local mark = #sim.sent
    for _ = 1, 2 do -- the claim comes inside the login queue, then a /reload
      cl[B]:stop()
      local b = sim:relog(B); sim:run(1)
      ok(b.ledgerNet.waiting, "the login queue is open")
      b.ledgerNet:take(d, A, true); sim:run(5)
      cl[B] = b
    end
    sim:run(C.LEDGER_ADOPT_WAIT + 5)
    eq(#sentOf(sim, B, mark, "C"), 1); eq(#sentOf(sim, B, mark), 1)
    eq(debtOf(cl[P], d.gid .. "|" .. B .. "|" .. A).status, "confirmed")
  end)

  it("an entry is made once per key in a run, even while it only waits in the login queue", function()
    local _, cl = setup()
    local net, calls = cl[B].ledgerNet, 0
    local made = net.make
    net.make = function() calls = calls + 1; return "queued" end
    cl[B].stakes:make("Wabc", "C", { r = A .. ":1", dh = "0123456789abcdef" })
    cl[B].stakes:make("Wabc", "C", { r = A .. ":1", dh = "0123456789abcdef" })
    net.make = made
    eq(calls, 1)
  end)

  it("a claim written long after my note of that game is put to me, not confirmed (Task 4 re-review)", function()
    local sim, cl = setup()
    local tid = ttt(sim, cl, SK)
    sim.bus.filter = function(from, to, _, m)
      if from == A and to == B and m.t == "LEV" then return {} end
      return { m }
    end
    local q = match(sim, { cl[A], cl[B] }, 1); sim:run(5)
    sim.bus.filter = nil
    local gid = tid .. "/" .. q
    local late = { i = Ledger.id(A, 50), k = "D", at = cl[B].env.db.stakeSeen[gid].at + C.STAKE_LEFT_WINDOW + 60, gid = gid, g = "ttt",
      f = B, t = A, c = SK, why = "lost" }
    local mark = #sim.sent
    eq(cl[B].ledgerNet:take(late, A, true), "new"); sim:run(5)
    eq(#sentOf(sim, B, mark), 0); eq(#cl[B].stakes:asks(), 1)
  end)

  it("an old open note of a table does not answer a claim long after it", function()
    local sim, cl = setup()
    local tid = dr(sim, cl, { B }, SK)
    roll(sim, cl[A], 50)
    local q = cl[B].session.seq
    cl[A]:send("WHISPER", B, { v = 1, t = "END", tid = tid, e = cl[A].session.epoch }); sim:run(0)
    local note = cl[B].env.db.stakeSeen[tid .. "/" .. q]
    eq({ note.open, note.foul }, { true, "forged" })
    local mark = #sim.sent
    local function claim(n, at)
      return { i = Ledger.id(A, n), k = "D", at = at, gid = tid .. "/" .. (q + n), g = "deathroll", f = B, t = A, c = SK, why = "offline" }
    end
    eq(cl[B].ledgerNet:take(claim(40, note.at + 200), A, true), "new")
    eq(cl[B].ledgerNet:take(claim(41, note.at + C.STAKE_LEFT_WINDOW + 60), A, true), "new"); sim:run(5)
    local n = sentOf(sim, B, mark, "N")
    eq(#n, 1); eq({ n[1].why, n[1].r }, { "forged", A .. ":40" }); eq(#cl[B].stakes:asks(), 1)
  end)

  it("the host hands over mid-game and the debts still come", function()
    local sim, cl = setup()
    local tid = ttt(sim, cl, SK)
    ok(cl[A]:act({ k = "mark", c = 1 })); sim:run(0)
    local mark = #sim.sent
    cl[A]:stand(); sim:run(10)
    eq(cl[B].session.role, "host")
    local d = sentOf(sim, B, mark, "D")
    eq(#d, 1); eq({ d[1].f, d[1].t, d[1].why, d[1].c }, { A, B, "left", SK })
    local r = sentOf(sim, B, mark, "R")
    eq(#r, 1); eq({ r[1].gid, r[1].l, r[1].w, r[1].n, r[1].why }, { d[1].gid, { 1 }, { 2 }, { A, B }, "left" })
    eq(#sentOf(sim, A, mark, "R"), 0); eq(#sentOf(sim, A, mark, "C"), 1)
    eq(debtOf(cl[P], d[1].gid .. "|" .. A .. "|" .. B).status, "confirmed")
    ok(d[1].gid:find(tid, 1, true) == 1, "a gid of this table")
  end)

  it("death roll: the host's own idle forfeit is recorded as left, its note says idle (F22)", function()
    local sim, cl = setup()
    local tid = dr(sim, cl, { B }, SK)
    local mark = #sim.sent
    sim:run(C.OFFLINE_STAND_SECONDS + 10)
    eq(cl[A].session, nil); eq(cl[B].session.role, "host")
    local d = sentOf(sim, B, mark, "D")
    eq(#d, 1); eq({ d[1].f, d[1].t, d[1].why }, { A, B, "left" })
    local r = sentOf(sim, B, mark, "R")
    eq(#r, 1); eq(r[1].why, "left")
    eq(cl[A].stakes:last(tid).why, "idle"); eq(cl[A].env.db.stakeLeft[tid].sk, SK)
    eq(#sentOf(sim, A, mark, "C"), 1); eq(debtOf(cl[P], d[1].gid .. "|" .. A .. "|" .. B).status, "confirmed")
  end)

  it("a snapshot that already shows the result writes nothing", function()
    local sim, cl = setup()
    local tid = ttt(sim, cl, SK)
    cl[P]:watch(tid); sim:run(1)
    match(sim, { cl[A], cl[B] }, 1); sim:run(10)
    local mark = #sim.sent
    local p = sim:relog(P); sim:run(60)
    eq(#sentOf(sim, P, mark), 0); eq(p.env.db.stakeSeen, nil)
  end)

  it("review is idempotent", function()
    local sim, cl = setup()
    ttt(sim, cl, SK)
    match(sim, { cl[A], cl[B] }, 1); sim:run(10)
    local before = { count(cl[A]), count(cl[B]), count(cl[P]) }
    local mark = #sim.sent
    for _ = 1, 10 do for _, c in pairs(cl) do c.stakes:review() end end
    sim:run(10)
    eq({ count(cl[A]), count(cl[B]), count(cl[P]) }, before); eq(#levs(sim, nil, mark), 0)
  end)
end)

describe("stakes: the guild cost of a game (real wire)", function()
  -- The GUILD LEVs after mark, and every sender's parts within any 10 s.
  local function budget(sim, mark)
    local per, parts = {}, {}
    for i, s in ipairs(sim.sent) do
      if i > mark and s.channel == "GUILD" and (s.msg.t == "LEV" or s.msg.t == "HI") then
        if s.msg.t == "LEV" then per[s.from] = (per[s.from] or 0) + 1 end
        parts[s.from] = parts[s.from] or {}
        table.insert(parts[s.from], { at = s.at, n = math.ceil(packed(s.msg) / 255) })
      end
    end
    for from, list in pairs(parts) do
      for _, p in ipairs(list) do
        local inside = 0
        for _, x in ipairs(list) do if x.at >= p.at and x.at < p.at + 10 then inside = inside + x.n end end
        ok(inside <= 10, from .. ": parts in 10 s from " .. p.at .. ": " .. inside)
      end
    end
    local total, top = 0, 0
    for _, n in pairs(per) do total, top = total + n, math.max(top, n) end
    eq(sim:count(function(s) return s.msg.t == "LVC" end), 0) -- no sync: no sync HI
    return total, top
  end

  it("a two-player staked game costs at most 4 GUILD messages, a five-player Death Roll at most 10, none above 3 a sender", function()
    local sim, cl = setup()
    ttt(sim, cl, SK)
    local mark = #sim.sent
    match(sim, { cl[A], cl[B] }, 1); sim:run(C.STAKE_OWE_WAIT + 10)
    local total, top = budget(sim, mark)
    ok(total <= 4, "ttt: " .. total); ok(top <= 3, "ttt top: " .. top)

    sim, cl = setup({ G, D })
    dr(sim, cl, { B, P, G, D }, SK)
    mark = #sim.sent
    roll(sim, cl[A], 50); roll(sim, cl[B], 40); roll(sim, cl[P], 30); roll(sim, cl[G], 20); roll(sim, cl[D], 1)
    sim:run(C.STAKE_OWE_WAIT + 10)
    total, top = budget(sim, mark)
    ok(total <= 10, "death roll: " .. total); ok(top <= 3, "death roll top: " .. top)
    local four = levs(sim, D, mark)
    eq(#four, 1); eq(#four[1].ev, 4)
    ok(packed(four[1]) < 600, "4 C: " .. packed(four[1]))
    for _, t in ipairs({ A, B, P, G }) do eq(View.net(view(cl[A]), D, t), SK) end
  end)
end)

ns.LedgerNet.size = stand
