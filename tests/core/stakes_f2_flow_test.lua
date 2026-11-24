Loader.lib("Libs/LibStub/LibStub.lua")
Loader.lib("Libs/AceSerializer-3.0/AceSerializer-3.0.lua")
Loader.lib("Libs/LibDeflate/LibDeflate.lua")
local Sim = require("sim")
local Play = require("play")
local ns = Sim.ns
local C, Ledger, View = ns.Const, ns.Ledger, ns.LedgerView

-- The whole road of a staked Сантасе, Белот and Табла table in the simulator
-- (stage F2 Task 10), with the real wire format as wow/Adapter.lua installs it
-- (as tests/core/stakes_ledger_test.lua does; restored at the end of this file).
local wire = ns.Wire.new(LibStub("AceSerializer-3.0"), LibStub("LibDeflate"))
local stand = ns.LedgerNet.size
ns.LedgerNet.size = function(msg) return #wire:pack(msg) end

-- А, Б, В, Г: the players (Play.NAMES; А hosts, А and В are partners in Белот); Д: a bystander.
local A, B, V, G = Play.NAMES[1], Play.NAMES[2], Play.NAMES[3], Play.NAMES[4]
local D = "Дара Маринова"
local SK = 25000 -- 2g 50s
local SEATS = { santase = 2, belot = 4, tabla = 2 }

-- A small generator so that every client of a run draws from one stream
-- (copied from tests/core/santase_table_test.lua, G10).
local function lcg(seed)
  local x = seed
  return function(lo, hi)
    x = (x * 1103515245 + 12345) % 2147483648
    return lo + math.floor(x / 65536) % (hi - lo + 1)
  end
end

-- The first n players and Д, past their login queues; each can trade with
-- every other (a trade is "ok"); seed: every client draws from lcg(seed) -> sim, cl, the stream.
local function guild(n, seed)
  local sim, cl = Play.guild(n, { D })
  local all = {}
  for name in pairs(cl) do all[#all + 1] = name end
  for name in pairs(cl) do sim.options[name].near = all end
  local rnd = seed and lcg(seed)
  if rnd then for _, c in pairs(cl) do c.env.random = rnd end end
  return sim, cl, rnd
end

local function record(client, event)
  local list = {}
  client:on(event, function(...) list[#list + 1] = { ... } end)
  return list
end

local function sorted(list)
  local out = {}
  for i, v in ipairs(list) do out[i] = v end
  table.sort(out)
  return out
end

local function view(client) return View.of(client.ledger) end

-- The GUILD entries of kind k `from` sent about a D at gid (k = "D": the claims at gid).
local function wordsAt(sim, from, k, gid)
  local ds, out = {}, {}
  for _, d in ipairs(Play.entries(sim, nil, "D")) do if d.gid == gid then ds[d.i] = true end end
  for _, e in ipairs(Play.entries(sim, from, k)) do
    if (k == "D" and e.gid == gid) or ds[e.r] then out[#out + 1] = e end
  end
  return out
end

-- Is the debt gid|f|t among client's asks()?
local function asked(client, gid, f, t)
  for _, d in ipairs(client.stakes:asks()) do
    if d.gid == gid and d.f == f and d.t == t then return true end
  end
  return false
end

-- Steps until host's match is over -> its gid, the names of its losers and of its winners (by seat).
local function finish(sim, host, limit)
  local r = Play.finish(sim, host, limit)
  local names, L, W = r.names or host.session.seats, {}, {}
  for i, seat in ipairs(sorted(r.losers)) do L[i] = names[seat] end
  for i, seat in ipairs(sorted(r.winners)) do W[i] = names[seat] end
  return host.session.tid .. "/" .. r.q, L, W
end

-- The client hosting a live table among sim's current clients, or nil.
local function hostOf(sim)
  for _, c in pairs(sim.clients) do
    local s = c.session
    if s and s.role == "host" and s.status == "live" and not c.env.dead then return c end
  end
  return nil
end

-- Drops every throw ACT of `name` with that op while its client believes it
-- sent it (once: only those of the first throw it drops) -> a function that
-- lifts it (copied from tests/core/stakes_tabla_test.lua, G10).
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
  return function() on = false end
end

-- Staked Табла matches of seeds 1.., Б's first seed muted until DICE_WAIT
-- passed (a throw made alone against Б's commit: the foul dice), until Б loses
-- one; prepare(sim, cl) runs before the table opens -> sim, cl, gid of the match Б lost.
local function contested(prepare)
  for seed = 1, 40 do
    local sim, cl = guild(2, seed)
    if prepare then prepare(sim, cl) end
    Play.short("tabla")
    local lift = mute(sim, B, "seed", true)
    Play.open(sim, cl, "tabla", SK, 2)
    sim:run(C.DICE_WAIT + 1)
    eq(cl[B].session.stakeFoul, "dice")
    lift()
    local gid, L = finish(sim, cl[A])
    Play.restore()
    sim:run(5)
    if L[1] == B then return sim, cl, gid end
  end
  error("Б never loses")
end

describe("stakes F2: the switch", function()
  it("the dialog's games", function()
    for _, id in ipairs({ "ttt", "deathroll", "santase", "belot", "tabla" }) do
      eq(ns.Stake.allowed(id, 50000), true, id)
    end
    -- Since stage F3 Холдем takes a stake too: its big blind in copper, never another sum.
    eq(ns.Stake.allowed("holdem", 1000, { blinds = 10 }), true); eq(ns.Stake.allowed("holdem", 50000, { blinds = 10 }), false)
    for _, id in ipairs({ "santase", "belot", "tabla" }) do eq(ns.Engines[id].stakes, true, id) end
    -- A staked table of each of the five, each opened by another member, is listed by every other.
    local sim, cl = guild(4)
    -- 5g is no big blind of Холдем.
    local tid, why = cl[A]:openTable{ game = "holdem", access = "guild", turn = 45, stake = 50000 }
    eq({ tid, why }, { nil, "stake" }); eq(cl[A].session, nil)
    local hosts, tids = { A, B, V, G, D }, {}
    for i, id in ipairs({ "ttt", "deathroll", "santase", "belot", "tabla" }) do
      local tid, why = cl[hosts[i]]:openTable{ game = id, access = "guild", turn = 45, stake = 50000 }
      ok(tid, id .. ": " .. tostring(why))
      tids[id] = tid
    end
    sim:run(3)
    for i, id in ipairs({ "ttt", "deathroll", "santase", "belot", "tabla" }) do
      for _, name in ipairs(hosts) do
        if name ~= hosts[i] then
          local r = cl[name].lobby:get(tids[id])
          ok(r, id .. " listed by " .. name); eq({ r.game, r.stake }, { id, 50000 }, id)
        end
      end
    end
  end)
end)

describe("stakes F2: the whole road (real wire)", function()
  it("from the chair to the cleared debt, three times", function()
    for _, game in ipairs({ "santase", "belot", "tabla" }) do
      local n = SEATS[game]
      local sim, cl = guild(n)
      local back = Play.short(game)
      local tid = Play.open(sim, cl, game, SK, n)
      local gid, L, W = finish(sim, cl[A])
      back()
      ok(gid:find(tid, 1, true) == 1, game)
      sim:run(C.STAKE_FAIR_WAIT + 10)
      eq(#L, n / 2, game); eq(#W, n / 2, game)
      -- The debtors' clients confirmed; Д, a bystander, shows the nets: one pair per loser.
      for i = 1, #L do
        local d = Play.debt(cl[D], gid, L[i], W[i])
        ok(d, game .. ": the debt of the " .. i .. ". loser")
        eq({ d.c, d.status }, { SK, "confirmed" }, game)
        eq(#wordsAt(sim, L[i], "C", gid), 1, game); eq(#wordsAt(sim, L[i], "N", gid), 0, game)
        eq(View.net(view(cl[D]), L[i], W[i]), SK, game)
      end
      eq(#View.of(cl[D].ledger).debts, #L, game)
      -- The first debtor pays by trade: the PAY, the fake trade completes, the creditor's P.
      local f, t = L[1], W[1]
      local mark = #sim.sent
      eq(cl[f].pay:owed(t), SK, game)
      eq(cl[f].pay:byTrade(t), true, game)
      sim:run(0)
      local pays = {}
      for j, s in ipairs(sim.sent) do if j > mark and s.msg.t == "PAY" then pays[#pays + 1] = s end end
      eq(#pays, 1, game)
      eq({ pays[1].from, pays[1].channel, pays[1].target, pays[1].msg.c, pays[1].msg.how }, { f, "WHISPER", t, SK, "trade" }, game)
      cl[t].pay:traded({ name = f, gave = 0, got = SK, items = false })
      cl[f].pay:traded({ name = t, gave = SK, got = 0, items = false })
      sim:run(C.LEDGER_COALESCE + 2)
      local p = Play.entries(sim, t, "P")
      eq(#p, 1, game); eq({ p[1].f, p[1].c, p[1].how }, { f, SK, "trade" }, game)
      eq(#Play.entries(sim, nil, "P"), 1, game)
      for name, c in pairs(cl) do
        eq(View.net(view(c), f, t), 0, game .. " " .. name)
        if n == 4 then eq(View.net(view(c), L[2], W[2]), SK, game .. " " .. name) end
      end
    end
  end)

  it("a guest is disconnected mid-match and comes back in time", function()
    local seen = {}
    for seed = 1, 40 do
      if seen.guest and seen.host then break end
      local sim, cl = guild(2, seed)
      local back = Play.short("santase")
      local tid = Play.open(sim, cl, "santase", SK, 2)
      local forfeits = record(cl[A], "forfeit")
      -- On the host's turn of the first hand, just after a tick of the host's reached Б, Б drops
      -- out for 60 s: the host's own timeout plays meanwhile, and the host's tick of the 60th
      -- second (every PING_EVERY) reaches Б back, so Б's silence clock never reaches
      -- SILENT_AFTER (a longer silence: Б would take the table over at the state it holds).
      local hs = cl[A].session
      for _ = 1, 200 do
        if hs.fair and hs.fair.stage == "dealt" and hs.state.turn == 1 then break end
        Play.step(sim, cl[A])
      end
      eq(hs.state.turn, 1)
      local function ticked() -- a tick of the host's reached Б this second
        for i = #sim.sent, 1, -1 do
          local m = sim.sent[i]
          if m.at < sim.clock then return false end
          if m.from == A and m.target == B and m.msg.t == "TCK" then return true end
        end
        return false
      end
      for _ = 1, C.PING_EVERY do if ticked() then break end; sim:run(1) end
      ok(ticked(), "a tick")
      local q = hs.seq
      sim:offline(B); sim:run(2 * C.PING_EVERY - 1); sim:online(B); sim:run(1)
      ok(ticked(), "the tick that reaches Б back")
      ok(hs.seq > q, "the host played on while Б was away")
      -- That tick shows Б the gap: Б asks for the table and is brought back by snapshot.
      sim:run(3)
      eq({ cl[B].session.host, cl[B].session.role, hs.role }, { A, "player", "host" })
      eq(cl[B].session.stakeFoul, "unseen"); eq(hs.stakeFoul, nil)
      local gid, L, W = finish(sim, cl[A])
      back()
      ok(gid:find(tid, 1, true) == 1)
      sim:run(C.STAKE_FAIR_WAIT + C.STAKE_OWE_WAIT + 5)
      eq(#forfeits, 0)
      for _, e in ipairs(Play.entries(sim, nil, "D")) do eq(e.why, "lost") end
      local d = Play.debt(cl[D], gid, L[1], W[1])
      ok(d, "the debt")
      local branch = L[1] == B and "guest" or "host"
      if not seen[branch] then
        seen[branch] = true
        if branch == "guest" then
          eq(d.status, "pending"); eq(asked(cl[B], gid, B, A), true)
          eq(#wordsAt(sim, B, "C", gid), 0); eq(#wordsAt(sim, B, "N", gid), 0)
        else
          eq(d.status, "confirmed"); eq(#wordsAt(sim, A, "C", gid), 1)
        end
      end
    end
    eq(seen, { guest = true, host = true })
  end)

  it("a guest is disconnected for good", function()
    local sim, cl = guild(2)
    local tid = Play.open(sim, cl, "tabla", SK, 2)
    for _ = 1, 6 do Play.step(sim, cl[A]) end
    local forfeits = record(cl[A], "forfeit")
    sim.envs[B].dead = true; sim:offline(B) -- his client is gone
    sim:run(C.OFFLINE_STAND_SECONDS + C.SILENT_AFTER)
    eq(#forfeits, 1); eq({ forfeits[1][1].name, forfeits[1][1].why }, { B, "offline" })
    local gid = tid .. "/" .. forfeits[1][1].q
    local ds = wordsAt(sim, nil, "D", gid)
    eq(#ds, 1); eq({ ds[1].f, ds[1].t, ds[1].c, ds[1].why }, { B, A, SK, "offline" })
    for _, name in ipairs({ A, D }) do eq(Play.debt(cl[name], gid, B, A).status, "pending", name) end
    eq(View.net(view(cl[D]), B, A), 0)
    -- A day later Б logs in: the debt is put to him once, with the game and the amount.
    sim:run(86400)
    local b = sim:relog(B)
    local asks = record(b, "debtAsk")
    for _ = 1, 120 do if #b.stakes:asks() > 0 then break end; sim:run(1) end
    sim:run(30 + C.LEDGER_PEER_GAP) -- long enough for a second ask to have shown up
    local list = b.stakes:asks()
    eq(#list, 1); eq({ list[1].gid, list[1].g, list[1].f, list[1].t, list[1].c }, { gid, "tabla", B, A, SK })
    eq(#asks, 1)
  end)

  it("the host is disconnected for good mid-match", function()
    local sim, cl = guild(4)
    local tid = Play.open(sim, cl, "belot", SK, 4)
    for _ = 1, 6 do Play.step(sim, cl[A]) end
    sim.envs[A].dead = true; sim:offline(A) -- the host's client is gone
    local next, forfeits
    for _ = 1, C.SILENT_AFTER + 60 do
      next = hostOf(sim)
      if next and next ~= cl[A] then break end
      sim:run(1)
    end
    ok(next and next ~= cl[A], "a member takes the table")
    forfeits = record(next, "forfeit")
    sim:run(C.OFFLINE_STAND_SECONDS + C.SILENT_AFTER)
    eq(#forfeits, 1); eq({ forfeits[1][1].name, forfeits[1][1].why }, { A, "offline" })
    local gid = tid .. "/" .. forfeits[1][1].q
    -- The old host owes both opponents (Б, Г), its partner (В) nothing; the successor wrote the R.
    local r = {}
    for _, e in ipairs(Play.entries(sim, nil, "R")) do if e.gid == gid then r[#r + 1] = e end end
    eq(#r, 1)
    eq(Ledger.author(r[1].i), next.env.me); eq({ r[1].l, r[1].w, r[1].why }, { { 1 }, { 2, 4 }, "offline" })
    local to = {}
    for _, e in ipairs(wordsAt(sim, nil, "D", gid)) do
      eq({ e.f, e.c, e.why }, { A, SK, "offline" }); to[#to + 1] = e.t
    end
    eq(sorted(to), sorted({ B, G }))
    for _, name in ipairs({ B, V, G, D }) do
      for _, t in ipairs({ B, G }) do eq(Play.debt(cl[name], gid, A, t).status, "pending", name) end
      for _, d in ipairs(view(cl[name]).debts) do ok(d.f ~= V and d.t ~= V, "the partner is in no debt") end
    end
  end)

  it("a reload at every seat of a Белот match", function()
    local sim, cl = guild(4)
    local tid = Play.open(sim, cl, "belot", SK, 4)
    local E = ns.Engines.belot
    local deals = {}
    local fouls = {}
    local function watch(c) fouls[#fouls + 1] = record(c, "forfeit") end
    for _, c in pairs(cl) do watch(c) end
    -- Seat k's player reloads three moves into deal k + 1 (the host's: its successor plays on).
    for k = 1, 4 do
      for _ = 1, 600 do
        local h = hostOf(sim)
        local s = h and h.session
        if s and s.fairN == k + 1 and s.fair and s.fair.stage == "dealt" then break end
        if h then Play.step(sim, h) else sim:run(1) end
      end
      local h = hostOf(sim)
      eq(h.session.fairN, k + 1, "deal " .. (k + 1))
      for _ = 1, 3 do Play.step(sim, h) end
      local name = h.session.seats[k]
      deals[#deals + 1] = h.session.fairN
      ok(not h.session:gameOver(), "the match runs")
      cl[name] = sim:relog(name); watch(cl[name]); sim:settle(); sim:run(3)
    end
    eq(deals, { 2, 3, 4, 5 })
    -- Then the next scored deal ends the match.
    local back = Play.short("belot")
    local over
    for _ = 1, 3000 do
      local h = hostOf(sim)
      over = nil
      for _, c in pairs(cl) do if c.session and c.session.tid == tid and c.session:gameOver() then over = c end end
      if over then break end
      if h then Play.step(sim, h) else sim:run(1) end
    end
    back()
    ok(over, "the match ended")
    sim:run(C.STAKE_FAIR_WAIT + C.STAKE_OWE_WAIT + 10)
    local ds = {}
    for _, d in ipairs(view(cl[D]).debts) do if d.gid:find(tid, 1, true) == 1 then ds[#ds + 1] = d end end
    eq(#ds, 2)
    for _, f in ipairs(fouls) do eq(#f, 0) end -- the match ended by play, no forfeit anywhere
    for _, e in ipairs(Play.entries(sim, nil, "D")) do eq(e.why, "lost") end
    for _, d in ipairs(ds) do
      eq({ d.c, d.status }, { SK, "pending" }, d.key)
      eq(asked(cl[d.f], d.gid, d.f, d.t), true, d.key)
      for _, name in ipairs({ A, B, V, G, D }) do eq(Play.debt(cl[name], d.gid, d.f, d.t).status, "pending", name) end
    end
    eq(#Play.entries(sim, nil, "C"), 0); eq(#Play.entries(sim, nil, "N"), 0)
    eq(E.TARGET, 151)
  end)

  it("a forged ledger entry about a card match is denied by its author", function()
    local sim, cl = guild(4)
    local tid = Play.open(sim, cl, "belot", SK, 4)
    for _ = 1, 5 do Play.step(sim, cl[A]) end
    -- The host stands Г, present, up (as its own sweep would): Г contests both claims (N "stand").
    local q = cl[A].session.seq + 1
    ok(cl[A].session:event(0, { k = "stand", seat = 4, why = "offline" })); sim:run(1)
    eq(cl[G].session.stakeFoul, "stand")
    sim:run(10)
    local gid = tid .. "/" .. q
    local claim
    for _, d in ipairs(wordsAt(sim, nil, "D", gid)) do if d.t == A then claim = d end end
    ok(claim, "А's claim against Г")
    local word = wordsAt(sim, G, "N", gid)
    eq(#word, 2)
    for _, x in ipairs(word) do if x.r == claim.i then word = x end end
    eq({ word.k, word.why, word.r }, { "N", "stand", claim.i })
    eq(Play.debt(cl[D], gid, G, A).status, "contested")
    -- Г logs in again later (within one run of his client a second body under an id it made
    -- is a collision of his own, put to him, not denied).
    cl[G] = sim:relog(G); sim:settle(); sim:run(C.LEDGER_PEER_GAP)
    -- А forges Г's C for that claim under the id of Г's N and relays it (its HI starts the sync).
    local forged = { i = word.i, k = "C", at = word.at, r = claim.i, dh = Ledger.hash(claim) }
    cl[A].ledger:add(forged, "Някой")
    cl[A].presence:sendGuildHi(false)
    local mark = #sim.sent
    sim:run(900)
    local x
    for i = mark + 1, #sim.sent do
      local s = sim.sent[i]
      if s.from == G and s.msg.t == "LEV" then
        for _, e in ipairs(s.msg.ev) do if e.k == "X" and e.r == forged.i then x = e end end
      end
    end
    ok(x, "Г denied it"); eq(x.h, Ledger.hash(forged))
    for _, name in ipairs({ A, B, V, G, D }) do
      local c = cl[name]
      local held, twins = c.ledger:get(forged.i)
      ok(held, name)
      eq(#(twins or {}) + 1, 2, name)
      eq(Play.debt(c, gid, G, A).status, "contested", name)
      eq(View.net(view(c), G, A), 0, name)
      eq(c.ledger:digest(), cl[G].ledger:digest(), name)
    end
  end)

  it("a client of the F1 version keeps the debt pending and the sync settles", function()
    -- Д's client refuses an N whose reason F1 does not know, as F1's Ledger.valid does.
    local function f1(net)
      local take = net.take
      net.take = function(self, e, from, live)
        if type(e) == "table" and e.k == "N" and (e.why == "deal" or e.why == "dice") then
          local author, n = Ledger.author(e.i)
          if author then return self:refuse(e, author, n) end
        end
        return take(self, e, from, live)
      end
    end
    local sim, cl, gid = contested(function(_, cl) f1(cl[D].ledgerNet) end)
    local words = wordsAt(sim, B, "N", gid)
    eq(#words, 1); eq(words[1].why, "dice")
    local n = words[1]
    eq(Play.debt(cl[A], gid, B, A).status, "contested")
    -- Д holds the D, not the N; it remembers refusing it; the debt is pending there, in no balance.
    local d = Play.debt(cl[D], gid, B, A)
    ok(d, "Д holds the claim"); eq(d.status, "pending")
    eq((cl[D].ledger:get(n.i)), nil)
    eq(cl[D].ledger:refused(B, select(2, Ledger.author(n.i)), Ledger.hash(n)), true)
    eq(View.net(view(cl[D]), B, A), 0)
    -- A new member logs in: two exchanges at most with Д, then nothing more between them
    -- (measured: one, at its login).
    local E = "Яна Нова"
    local e = sim:add(E)
    sim.options[E].near = {}
    local mark = #sim.sent
    sim:run(1500)
    local function between(s) return (s.from == D and s.target == E) or (s.from == E and s.target == D) end
    local exchanges, last = 0, 0
    for i = mark + 1, #sim.sent do
      local s = sim.sent[i]
      if between(s) and s.msg.t == "LVC" and not s.msg.r then exchanges = exchanges + 1 end
      if between(s) and (s.msg.t == "LVC" or s.msg.t == "LID" or s.msg.t == "LEV") then last = s.at end
    end
    ok(exchanges >= 1 and exchanges <= 2, "exchanges between Д and the new member: " .. exchanges)
    ok(last < sim.clock - 2 * C.LEDGER_PEER_GAP, "a sync message between them at " .. last)
    ok(e.ledger:get(n.i), "the new member holds the N (from another member)")
    eq(Play.debt(e, gid, B, A).status, "contested")
    -- The refused N counts as held in Д's digest: the guild's digests agree, no exchange is due.
    for _, c in ipairs({ e, cl[B], cl[D] }) do eq(c.ledger:digest(), cl[A].ledger:digest(), c.env.me) end
    -- Д never relayed the N.
    for _, s in ipairs(sim.sent) do
      if s.from == D and s.msg.t == "LEV" then
        for _, x in ipairs(s.msg.ev or {}) do ok(x.i ~= n.i, "Д relayed the N") end
      end
    end
    eq(Play.debt(cl[D], gid, B, A).status, "pending"); eq(View.net(view(cl[D]), B, A), 0)
    -- A contest of reason "deal" meets the same wrapper: refused, the debt stays pending, in no balance.
    local author, num = Ledger.author(n.i)
    local deal = {}
    for k, v in pairs(n) do deal[k] = v end
    deal.i, deal.why = author .. ":" .. (num + 50), "deal"
    cl[D].ledgerNet:take(deal, author, true)
    eq((cl[D].ledger:get(deal.i)), nil)
    eq(cl[D].ledger:refused(author, num + 50, Ledger.hash(deal)), true)
    eq(Play.debt(cl[D], gid, B, A).status, "pending"); eq(View.net(view(cl[D]), B, A), 0)
  end)

  -- Measured at the first green run: Белот 4 GUILD LEVs (one per sender), Сантасе 2, Табла 2;
  -- no exchange starts (every member had every entry live).
  it("the budget of a staked card match", function()
    for _, g in ipairs({ { "belot", 7 }, { "santase", 4 }, { "tabla", 4 } }) do
      local game, cap = g[1], g[2]
      local n = SEATS[game]
      local sim, cl = guild(n)
      local back = Play.short(game)
      Play.open(sim, cl, game, SK, n)
      local mark = #sim.sent
      local gid, L, W = finish(sim, cl[A])
      back()
      sim:run(C.STAKE_FAIR_WAIT + C.STAKE_OWE_WAIT + 10)
      for i = 1, #L do eq(Play.debt(cl[D], gid, L[i], W[i]).status, "confirmed", game) end
      local total, per, top = 0, {}, 0
      for j, s in ipairs(sim.sent) do
        if j > mark and s.channel == "GUILD" and s.msg.t == "LEV" then
          total, per[s.from] = total + 1, (per[s.from] or 0) + 1
          top = math.max(top, per[s.from])
        end
        if j > mark then ok(s.msg.t ~= "LVC", game .. ": a sync exchange") end
      end
      ok(total <= cap, game .. ": GUILD LEVs " .. total)
      ok(top <= 3, game .. ": one sender's GUILD LEVs " .. top)
      for _, d in ipairs(view(cl[D]).debts) do eq(d.status, "confirmed", game) end
      eq(#view(cl[D]).debts, n / 2, game)
    end
  end)
end)

-- A fun-only evening ------------------------------------------------------------------

-- A whole fun match of `game` (n seats; every client draws from lcg(seed)):
-- FUN[1] hosts, FUN[2..n] sit; the seat on turn moves from its own client
-- (engine.bot, else its automatic move) once a second until the match is over;
-- then 40 s more. -> the message log, a line per message: time, sender,
-- channel, target, the message with its keys sorted (every HI with its ld,
-- every LEV). Run on the build of 88a48e7 to make the reference below.
local FUN = { "Иван Петров", "Мария Стоянова", "Kiro Barley", "Пешо Тодоров" }
local CLS = { "MAGE", "PRIEST", "ROGUE", "DRUID" }

local function ser(v)
  if type(v) == "string" then return string.format("%q", v) end
  if type(v) ~= "table" then return tostring(v) end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(x, y)
    if type(x) ~= type(y) then return type(x) < type(y) end
    return x < y
  end)
  local out = {}
  for _, k in ipairs(keys) do out[#out + 1] = (type(k) == "string" and k or "[" .. tostring(k) .. "]") .. "=" .. ser(v[k]) end
  return "{" .. table.concat(out, ",") .. "}"
end

local function funLog(game, n, seed)
  local sim = Sim.new()
  local rnd, cl = lcg(seed), {}
  for i = 1, n do cl[i] = sim:add(FUN[i], { cls = CLS[i] }); cl[i].env.random = rnd end
  sim:run(1)
  local host = cl[1]
  local tid = host:openTable{ game = game, access = "guild", turn = 45 }; sim:run(3)
  for i = 2, n do cl[i]:sit(tid, i); sim:run(1) end
  local steps = 0
  while not host.session:gameOver() do
    steps = steps + 1
    assert(steps < 6000, "the match did not end")
    local s = host.session
    local seat = s.status == "live" and s.state and s.state.turn
    local c = seat and sim.clients[s.seats[seat]]
    if c and c.session and c.session.state then
      local E, a = c.session:engine(), nil
      if E.bot then a = E.bot(c.session.state, seat, rnd) end
      if a then c:act(a) else c:playAuto() end
    end
    sim:run(1)
  end
  sim:run(40)
  local out = {}
  for _, s in ipairs(sim.sent) do
    out[#out + 1] = s.at .. " " .. s.from .. " " .. s.channel .. " " .. tostring(s.target) .. " " .. ser(s.msg)
  end
  return out
end

-- The log in chunks of 100 lines -> the line count, the first 16 hex of SHA-256 of each chunk (its lines joined by "\n").
-- The reference was recorded at version 0.1.0: the addon's own version in a log line (its HI's
-- ver=) reads as that one again, so a version bump alone never breaks the byte-identical check.
local REF_VERSION = "0.1.0"
local function asRecorded(line)
  local own = 'ver="' .. tostring(ns.Const.VERSION) .. '"'
  local i, j = line:find(own, 1, true)
  if not i then return line end
  return line:sub(1, i - 1) .. 'ver="' .. REF_VERSION .. '"' .. line:sub(j + 1)
end

local function chunks(log)
  local norm = {}
  for i, line in ipairs(log) do norm[i] = asRecorded(line) end
  log = norm
  local out = {}
  for from = 1, #log, 100 do
    out[#out + 1] = ns.Sha256.hex(table.concat(log, "\n", from, math.min(from + 99, #log))):sub(1, 16)
  end
  return #log, table.concat(out, " ")
end

-- funLog(game, n, 1) of each game on the build of 88a48e7 (before stage F2),
-- through chunks(): generated once, by the same functions, from a worktree of that commit
-- (its logs are 583, 2 693 and 2 632 lines, 94, 430 and 576 KB: too long for a literal of their own).
local FUN_88A48E7 = {
  santase = { 583,
    "f6fe542b064bd451 fa2407897c3ccacf 32af86ee4c8923e4 61821b9dcd1f7627 f0c7d00b41a78253 f9a006cdfbc2c122" },
  belot = { 2693,
    "572db3b56c7f959e afae9d2305f3aab1 505f85fc2961abc0 96dcabc1a5f885be 85a841c8ea581cd8 6734c2ed85441543 " ..
    "d2f4812bdd69a4ef fa986b5027f56ddf b49974a8a705022b d1be105d46f55d10 ed8c056ad7f83c94 5176c8d02ab8a7bc " ..
    "1ff352fcc025fba5 7eda90634ceb24a3 e311c5d73da25f31 288897ec0fe74755 255cab2cba1b7921 c1ec8bc10f19971c " ..
    "8ba711a8d2fc6ce0 04a5503916b6dbfd e6cded1f56f1ef21 352ad645808be13c e948c74f42d6a53f dae343b41773f59b " ..
    "7374b0768b90bd09 417befae79c6d04f daa94c921947dba2" },
  tabla = { 2632,
    "ce986db58bc3c66e a9e4973b0e908c0f b3721be76b6b5419 b469b047a4a76411 a37ff01fe2911fd5 540a2e57cc36151d " ..
    "46f2cf7f1ae21518 c5f7892c73bb2a63 171ee998b5eb0d94 c42ebb7d44a0e6ae 8bdc77567dfcc77c 60436dd4087bdd8f " ..
    "8a78011dea113d82 360e5f5168e028bf a32401d95bb328ff 918974171e1a23d0 7b7ab9d261266e6a f74dec765081171d " ..
    "3f5cf0efb7aa7b72 374a166bab4fc96e 70dff5a302f1a1ab e3c3a76abc178b52 e74e7f240ba8bb6b 8f11d0aa075650e3 " ..
    "6c42874e2a039065 c3cd34788e88bf3b 0f8cdfbf98612a7a" },
}

describe("stakes F2: fun tables are untouched", function()
  it("a fun-only evening of the three games is byte-identical", function()
    Play.restore() -- the real targets, should a test above have failed before its own restore
    for _, g in ipairs({ { "santase", 2 }, { "belot", 4 }, { "tabla", 2 } }) do
      local log = funLog(g[1], g[2], 1)
      local lines, sums = chunks(log)
      local ref = FUN_88A48E7[g[1]]
      eq(lines, ref[1], g[1])
      local got, want = {}, {}
      for h in sums:gmatch("%S+") do got[#got + 1] = h end
      for h in ref[2]:gmatch("%S+") do want[#want + 1] = h end
      for i = 1, math.max(#got, #want) do
        if got[i] ~= want[i] then
          eq(got[i], want[i], g[1] .. ": lines " .. (100 * i - 99) .. "-" .. (100 * i) .. ", from: " .. tostring(log[100 * i - 99]))
          break
        end
      end
      eq(got, want, g[1])
      eq(#got, math.ceil(ref[1] / 100), g[1])
    end
  end)
end)

Play.restore()
ns.LedgerNet.size = stand
