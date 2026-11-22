Loader.lib("Libs/LibStub/LibStub.lua")
Loader.lib("Libs/AceSerializer-3.0/AceSerializer-3.0.lua")
Loader.lib("Libs/LibDeflate/LibDeflate.lua")
local Sim = require("sim")
local ns = Sim.ns
local C, Ledger, View, U = ns.Const, ns.Ledger, ns.LedgerView, ns.Util

-- The whole road of a staked game in the simulator, from the chair to the
-- cleared debt, with the real wire format as wow/Adapter.lua installs it: the
-- sync cuts its batches and pages by packed bytes, and the budget below counts
-- packed bytes and 255-byte parts (restored at the end of this file).
-- AceSerializer writes a table's keys in pairs order, which LuaJIT seeds per
-- process, so one message packs a few bytes differently from run to run: every
-- byte pin here sits far from its cut.
local wire = ns.Wire.new(LibStub("AceSerializer-3.0"), LibStub("LibDeflate"))
local stand = ns.LedgerNet.size
ns.LedgerNet.size = function(msg) return #wire:pack(msg) end
local function packed(msg) return #wire:pack(msg) end

-- Four guild members, byte order А < Б < В < Г.
local A, B, V, G = "Асен Петров", "Борис Колев", "Вера Стоянова", "Гошо Тодоров"
local SK = 25000 -- 2g 50s

-- Морски шах -------------------------------------------------------------------

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

-- by[seat] play until `winner`'s next mark wins the match (one mark of the
-- match left), returning a function that plays it (by[1] is the host: after the
-- next drain its seq is the q of the winning mark).
local function toLast(sim, by, winner)
  for _ = 1, 600 do
    local s = by[1].session
    local st = s.state
    if st.phase == "play" then
      local seat = st.turn
      local c, wins = pick(by[seat].session.state.board, seat, seat == winner)
      if wins and seat == winner and st.score[seat] == ns.Engines.ttt.WINS - 1 then
        return function() ok(by[seat]:act({ k = "mark", c = c })) end
      end
      ok(by[seat]:act({ k = "mark", c = c }))
      sim:run(0)
    else
      sim:run(1)
    end
  end
  error("the match did not come to its last mark")
end

-- host opens a staked Морски шах, guest accepts the stake and sits: the match runs.
local function table2(sim, host, guest, sk)
  local tid = host:openTable{ game = "ttt", access = "guild", turn = 45, stake = sk }; sim:run(3)
  guest:sit(tid, 2, sk); sim:run(1)
  eq(host.session.status, "live")
  return tid
end

-- The ledger, as the clients see it ----------------------------------------------

local function view(client) return View.of(client.ledger) end
-- Every row as the tab „Тефтер“ states it (ui/LedgerTab.lua): open, paid, pending, contested.
local function rows(client)
  local out = {}
  for _, r in ipairs(View.rows(view(client))) do
    local d = r.debt
    out[#out + 1] = { key = d.key, c = d.c, open = r.open,
      state = d.status ~= "confirmed" and d.status or r.open > 0 and "open" or "paid" }
  end
  return out
end
-- Every body of the store as "<id>:<h>", sorted.
local function bodies(client)
  local out = {}
  client.ledger:each(function(e) out[#out + 1] = e.i .. ":" .. e.h end)
  table.sort(out)
  return out
end
local function ofKind(client, k)
  local out = {}
  client.ledger:each(function(e) if e.k == k then out[#out + 1] = e end end)
  return out
end

-- The messages ---------------------------------------------------------------------

-- The GUILD LEVs after sim.sent[mark], per sender.
local function guildLevs(sim, mark)
  local per, total = {}, 0
  for j, s in ipairs(sim.sent) do
    if j > mark and s.channel == "GUILD" and s.msg.t == "LEV" then
      per[s.from], total = (per[s.from] or 0) + 1, total + 1
    end
  end
  return total, per
end
-- The most packed bytes one sender sent (any channel) within any 10 s, after
-- sim.sent[mark], leaving out what `skip(s)` names; and the most 255-byte GUILD
-- parts of LEV and HI within any 10 s.
local function peaks(sim, mark, skip)
  local by = {}
  for j, s in ipairs(sim.sent) do
    if j > mark and not (skip and skip(s)) then
      by[s.from] = by[s.from] or {}
      local n = packed(s.msg)
      local guild = s.channel == "GUILD" and (s.msg.t == "LEV" or s.msg.t == "HI")
      table.insert(by[s.from], { at = s.at, n = n, parts = guild and math.ceil(n / 255) or 0 })
    end
  end
  local bytes, parts = 0, 0
  for _, list in pairs(by) do
    for _, p in ipairs(list) do
      local b, q = 0, 0
      for _, x in ipairs(list) do
        if x.at >= p.at and x.at < p.at + 10 then b, q = b + x.n, q + x.parts end
      end
      bytes, parts = math.max(bytes, b), math.max(parts, q)
    end
  end
  return bytes, parts
end

-- The four members online, in one guild, past their login queues; Б stands next to А.
local function guild()
  local sim, cl = Sim.new(), {}
  cl[A] = sim:add(A)
  cl[B] = sim:add(B, { near = { A } })
  cl[V] = sim:add(V)
  cl[G] = sim:add(G)
  sim:run(1)
  sim:settle()
  sim:run(1)
  return sim, cl
end

-- А wins a staked Морски шах against Б; Г is offline from before the game
-- until after the payment; Б pays by trade. -> sim, cl, marks
local function road()
  local sim, cl = guild()
  sim:offline(G)
  local m = { game = #sim.sent }
  table2(sim, cl[A], cl[B], SK)
  toLast(sim, { cl[A], cl[B] }, 1)()
  sim:run(C.STAKE_OWE_WAIT + 10)
  eq(cl[B].pay:byTrade(A), true)
  sim:run(0)
  -- The fake trade completes on both clients: Б gave 2g 50s, А got it, no item.
  cl[A].pay:traded({ name = B, gave = 0, got = SK, items = false })
  cl[B].pay:traded({ name = A, gave = SK, got = 0, items = false })
  sim:run(C.LEDGER_COALESCE + 2)
  m.login = #sim.sent
  sim:relog(G)
  m.loginAt = sim.clock
  sim:run(C.LEDGER_ADOPT_WAIT + C.LEDGER_JITTER_MAX + C.LEDGER_SYNC_TIMEOUT + 30)
  return sim, cl, m
end

describe("stakes: the whole road (real wire)", function()
  it("from the chair to the cleared debt", function()
    local sim, cl = guild()
    sim:offline(G)
    local tid = table2(sim, cl[A], cl[B], SK)
    toLast(sim, { cl[A], cl[B] }, 1)()
    sim:run(0)
    local q = cl[A].session.seq
    eq(cl[A].session.state.phase, "match")
    sim:run(10)
    local gid = tid .. "/" .. q
    local key = gid .. "|" .. B .. "|" .. A
    -- Б's client confirmed what it saw; В, a bystander, holds the same debt.
    for _, name in ipairs({ A, B, V }) do
      eq(rows(cl[name]), { { key = key, c = SK, open = SK, state = "open" } }, name)
      eq(View.net(view(cl[name]), B, A), SK, name)
    end
    local r, d, confirms = ofKind(cl[V], "R"), ofKind(cl[V], "D"), ofKind(cl[V], "C")
    eq(#r, 1); eq({ Ledger.author(r[1].i), r[1].gid, r[1].sk, r[1].w, r[1].l }, { A, gid, SK, { 1 }, { 2 } })
    eq(#d, 1); eq({ Ledger.author(d[1].i), d[1].f, d[1].t, d[1].c, d[1].why }, { A, B, A, SK, "lost" })
    eq(#confirms, 1); eq({ Ledger.author(confirms[1].i), confirms[1].r, confirms[1].dh }, { B, d[1].i, d[1].h })
    eq(#ofKind(cl[G], "D"), 0) -- Г heard nothing

    -- Б pays by trade.
    local mark = #sim.sent
    eq(cl[B].pay:owed(A), SK); eq(cl[A].pay:due(B), SK)
    eq(cl[B].pay:byTrade(A), true)
    sim:run(0)
    eq(sim.trades, { { from = B, name = A, c = SK } })
    local pays = {}
    for j, s in ipairs(sim.sent) do if j > mark and s.msg.t == "PAY" then pays[#pays + 1] = s end end
    eq(#pays, 1); eq({ pays[1].from, pays[1].channel, pays[1].target, pays[1].msg.c, pays[1].msg.how }, { B, "WHISPER", A, SK, "trade" })
    cl[A].pay:traded({ name = B, gave = 0, got = SK, items = false })
    cl[B].pay:traded({ name = A, gave = SK, got = 0, items = false })
    sim:run(C.LEDGER_COALESCE + 2)
    local p = ofKind(cl[V], "P")
    eq(#p, 1); eq({ Ledger.author(p[1].i), p[1].f, p[1].c, p[1].how }, { A, B, SK, "trade" })
    for _, name in ipairs({ A, B }) do eq(#ofKind(cl[name], "P"), 1, name) end -- the creditor's one P
    for _, name in ipairs({ A, B, V }) do
      eq(View.net(view(cl[name]), B, A), 0, name)
      eq(rows(cl[name]), { { key = key, c = SK, open = 0, state = "paid" } }, name)
    end
    eq(cl[A].pay:asks(), {}); eq(cl[B].pay:waiting(A), false)

    -- Г logs in: one exchange brings it the whole story.
    sim:relog(G)
    sim:run(C.LEDGER_ADOPT_WAIT + C.LEDGER_JITTER_MAX + C.LEDGER_SYNC_TIMEOUT + 30)
    eq(sim:count(function(s) return s.msg.t == "LVC" and not s.msg.r end), 1)
    local g = sim.clients[G]
    eq(g.ledger:digest(), cl[A].ledger:digest())
    eq(bodies(g), bodies(cl[A]))
    eq(rows(g), rows(cl[A]))
    eq(View.net(view(g), B, A), 0)
  end)

  -- Measured over six runs: the GUILD LEV of R + D 186-196 packed bytes, of C 123-127, of P
  -- 123-125, each one 255-byte part; Г's catch-up one exchange of 4 whispers (LVC, its
  -- answer, LEV of 4 entries 260-266 bytes, the closing LEV 33-35); the busiest client
  -- sends 2 778-2 856 bytes in its busiest 10 s, in 1 GUILD part.
  it("the whole road stays inside the budget", function()
    local sim, _, m = road()
    -- The game and the payment: R + D of А, C of Б, P of А; each LEV one part.
    local total, per = guildLevs(sim, m.game)
    local top = 0
    for _, n in pairs(per) do top = math.max(top, n) end
    ok(total <= 5, "GUILD LEVs of the game and the payment: " .. total)
    ok(top <= 3, "one sender's GUILD LEVs: " .. top)
    eq(total, 3); eq(per[A], 2); eq(per[B], 1)
    for j, s in ipairs(sim.sent) do
      if j > m.game and s.channel == "GUILD" and s.msg.t == "LEV" then ok(packed(s.msg) <= 255, "a live LEV of " .. packed(s.msg)) end
    end
    -- Г's catch-up goes by whisper only, in one exchange: no ledger message on GUILD.
    local sync, asks, guildAfter = 0, 0, 0
    for j, s in ipairs(sim.sent) do
      if j > m.login then
        local t = s.msg.t
        if t == "LVC" or t == "LID" or t == "LEV" then
          if s.channel == "GUILD" then guildAfter = guildAfter + 1 else sync = sync + 1 end
          if s.channel == "WHISPER" then ok(s.from == G or s.target == G, "a sync whisper not with Г") end
          if t == "LVC" and not s.msg.r then asks = asks + 1 end
          if t == "LEV" then ok(packed(s.msg) <= 400, "a catch-up LEV of " .. packed(s.msg)) end
        end
      end
    end
    eq(guildAfter, 0); eq(asks, 1); eq(sync, 4)
    eq(sim.clients[G].ledger:digest(), sim.clients[A].ledger:digest())
    -- Bytes and GUILD parts of any one client within any 10 s, the whole road long
    -- (Г's own messages while it was offline reached nobody and are left out).
    local bytes, parts = peaks(sim, m.game, function(s) return s.from == G and s.at < m.loginAt end)
    ok(bytes <= 8000, "bytes in 10 s: " .. bytes)
    ok(bytes <= 3400, "bytes in 10 s above the measured 2 778-2 856: " .. bytes)
    ok(parts <= 10, "GUILD parts in 10 s: " .. parts)
    eq(parts, 1)
  end)

  it("two tables end in the same second", function()
    local sim, cl = guild()
    local t1 = table2(sim, cl[A], cl[B], SK)
    local t2 = table2(sim, cl[V], cl[G], 2 * SK)
    local last1 = toLast(sim, { cl[A], cl[B] }, 1)
    local last2 = toLast(sim, { cl[V], cl[G] }, 2)
    local at = sim.clock
    last1(); last2()
    sim:run(0)
    eq(sim.clock, at)
    local q1, q2 = cl[A].session.seq, cl[V].session.seq
    eq(cl[A].session.state.phase, "match"); eq(cl[V].session.state.phase, "match")
    sim:run(C.STAKE_OWE_WAIT + 10)
    local k1, k2 = t1 .. "/" .. q1 .. "|" .. B .. "|" .. A, t2 .. "/" .. q2 .. "|" .. V .. "|" .. G
    local want = bodies(cl[A])
    eq(#want, 6) -- R, D, C of each game
    for _, name in ipairs({ A, B, V, G }) do
      local c = cl[name]
      eq(bodies(c), want, name)
      eq(c.ledger:digest(), cl[A].ledger:digest(), name)
      local states = {}
      for _, r in ipairs(rows(c)) do states[r.key] = r.state .. " " .. r.c end
      eq(states, { [k1] = "open " .. SK, [k2] = "open " .. 2 * SK }, name)
      eq(View.net(view(c), B, A), SK); eq(View.net(view(c), V, G), 2 * SK)
    end
    -- No id is reused: one body per id, everywhere.
    local ids = {}
    for _, b in ipairs(want) do
      local i = b:match("^(.*):[0-9a-f]+$")
      ok(not ids[i], "id reused: " .. i)
      ids[i] = true
    end
  end)

  it("a guild of two versions", function()
    local sim, cl = guild()
    local NEW, ODD = "Яна Нова", "Юлия Стара" -- byte-higher than every member: they would be asked
    local updates = 0
    cl[A]:on("update", function() updates = updates + 1 end)
    cl[A].ledgerNet:make("P", { f = B, c = 100, how = "hand" }); sim:run(C.LEDGER_COALESCE + 1)
    local mark = #sim.sent
    for _, name in ipairs({ A, B, V, G }) do
      local c = cl[name]
      -- A client at v = 2: its HI with a digest unlike every member's, its ledger messages.
      c:receive("GUILD", NEW, { v = 2, t = "HI", cls = "MAGE", id = "Player-0000-00000099", re = true, ver = "9.0.0", ld = "0123abcd" })
      c:receive("GUILD", NEW, { v = 2, t = "LEV", ev = { { i = NEW .. ":1", k = "P", at = 1700000000, f = A, c = 500, how = "hand" } } })
      c:receive("WHISPER", NEW, { v = 2, t = "LVC", a = { [NEW] = { 1, "000000000000" } } })
      c:receive("WHISPER", NEW, { v = 2, t = "PAY", c = 500, how = "trade" })
      -- A v = 1 client whose HI has no usable digest.
      c:receive("GUILD", ODD, { v = 1, t = "HI", cls = "MAGE", id = "Player-0000-00000098", re = true, ver = "0.1.0", ld = "XYZ" })
    end
    sim:run(C.LEDGER_JITTER_MAX + C.LEDGER_SYNC_TIMEOUT + 30)
    eq(updates, 1) -- the version handling of today: one notice
    for _, name in ipairs({ A, B, V, G }) do
      local c = cl[name]
      eq(c.presence:get(NEW).incompatible, true, name)
      eq(c.presence:get(ODD).incompatible, false, name)
      eq(c.presence:get(ODD).ld, nil, name)
      eq((c.ledger:get(NEW .. ":1")), nil, name)
      eq(c.ledgerSync:busy(), false, name)
    end
    -- Nothing at all goes to either of them, and no sync starts among the members.
    eq(sim:count(function(s) return s.target == NEW end), 0)
    -- The v = 1 client without a digest gets the HI answer of today, nothing more.
    for _, s in ipairs(sim.sent) do if s.target == ODD then eq({ s.channel, s.msg.t, s.msg.re }, { "WHISPER", "HI", false }) end end
    eq(sim:count(function(s) return s.target == ODD end), 4)
    for j, s in ipairs(sim.sent) do
      if j > mark then ok(s.msg.t ~= "LVC" and s.msg.t ~= "LID" and s.msg.t ~= "LEV", "a sync message: " .. s.msg.t) end
    end
  end)
end)

-- A fun-only evening --------------------------------------------------------------

-- The message log of the first two-player game of tests/core/session_test.lua
-- (И hosts Морски шах, Kiro watches, М sits; the first round), played on to the
-- end of the match and 40 s past it, with every client online throughout. Each
-- line: time, sender, channel, target, the message with its keys sorted.
local FUN_A, FUN_B, FUN_C = "Иван Петров", "Мария Стоянова", "Kiro Barley"

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

-- -> the log with `ld` removed from every HI and every LEV dropped; the dropped LEVs; the HIs with an ld
local function funLog()
  local sim = Sim.new()
  local a = sim:add(FUN_A, { cls = "MAGE" })
  local b = sim:add(FUN_B, { cls = "PRIEST" })
  local c = sim:add(FUN_C, { cls = "ROGUE" })
  sim:run(1)
  local tid = a:openTable{ game = "ttt", access = "guild", turn = 45 }; sim:run(3)
  c:watch(tid); sim:run(1)
  b:sit(tid, 2); sim:run(1)
  sim:run(2)
  local function play(moves)
    for _, mv in ipairs(moves) do
      local who = mv[1] == 1 and a or b
      ok(who:act{ k = "mark", c = mv[2] })
      sim:run(1)
    end
  end
  local X_FIRST = { { 1, 1 }, { 2, 4 }, { 1, 2 }, { 2, 5 }, { 1, 3 } }
  local O_FIRST = { { 2, 4 }, { 1, 1 }, { 2, 5 }, { 1, 2 }, { 2, 9 }, { 1, 3 } }
  play(X_FIRST); sim:run(3)
  sim:run(1); play(O_FIRST); sim:run(4); play(X_FIRST); sim:run(4)
  eq(a.session.state.phase, "match")
  sim:run(40)
  local out, levs, his = {}, {}, 0
  for _, s in ipairs(sim.sent) do
    local m = s.msg
    if m.t == "LEV" then
      levs[#levs + 1] = s
    else
      if m.t == "HI" then
        if m.ld then his = his + 1 end
        m = U.copy(m); m.ld = nil
      end
      out[#out + 1] = s.at .. " " .. s.from .. " " .. s.channel .. " " .. tostring(s.target) .. " " .. ser(m)
    end
  end
  return out, levs, his
end

-- funLog() run on the build of 82b0140 (before stage F1), where no HI had an
-- ld and no LEV existed: generated once, by the same function.
local FUN_82B0140 = [==[
0 Иван Петров GUILD nil {cls="MAGE",id="Player-0000-00000001",re=true,t="HI",v=1,ver="0.1.0"}
0 Мария Стоянова GUILD nil {cls="PRIEST",id="Player-0000-00000002",re=true,t="HI",v=1,ver="0.1.0"}
0 Kiro Barley GUILD nil {cls="ROGUE",id="Player-0000-00000003",re=true,t="HI",v=1,ver="0.1.0"}
1 Иван Петров WHISPER Мария Стоянова {cls="MAGE",id="Player-0000-00000001",re=false,t="HI",v=1,ver="0.1.0"}
1 Иван Петров WHISPER Kiro Barley {cls="MAGE",id="Player-0000-00000001",re=false,t="HI",v=1,ver="0.1.0"}
1 Мария Стоянова WHISPER Kiro Barley {cls="PRIEST",id="Player-0000-00000002",re=false,t="HI",v=1,ver="0.1.0"}
1 Иван Петров GUILD nil {ac="guild",e=1,g="ttt",h="Иван Петров",s={[1]="Иван Петров",[2]=false},st="open",t="TBL",tid="Иван Петров#1700000001",tn=45,v=1,w=0}
2 Иван Петров GUILD nil {at="Иван Петров#1700000001",cls="MAGE",id="Player-0000-00000001",re=false,t="HI",v=1,ver="0.1.0"}
4 Kiro Barley WHISPER Иван Петров {t="WAT",tid="Иван Петров#1700000001",v=1}
5 Иван Петров WHISPER Kiro Barley {e=1,q=0,t="SNP",tbl={ac="guild",e=1,g="ttt",h="Иван Петров",s={[1]="Иван Петров",[2]=false},st="open",tid="Иван Петров#1700000001",tn=45,w=1},tid="Иван Петров#1700000001",v=1}
5 Иван Петров GUILD nil {ac="guild",e=1,g="ttt",h="Иван Петров",s={[1]="Иван Петров",[2]=false},st="open",t="TBL",tid="Иван Петров#1700000001",tn=45,v=1,w=1}
5 Kiro Barley GUILD nil {at="Иван Петров#1700000001",cls="ROGUE",id="Player-0000-00000003",re=false,t="HI",v=1,ver="0.1.0"}
5 Мария Стоянова WHISPER Иван Петров {seat=2,t="SIT",tid="Иван Петров#1700000001",v=1}
6 Иван Петров WHISPER Kiro Barley {a={k="sit",name="Мария Стоянова",seat=2},e=1,q=1,seat=0,t="EV",tid="Иван Петров#1700000001",v=1}
6 Иван Петров WHISPER Мария Стоянова {e=1,q=1,t="SNP",tbl={ac="guild",e=1,g="ttt",h="Иван Петров",s={[1]="Иван Петров",[2]="Мария Стоянова"},st="open",tid="Иван Петров#1700000001",tn=45,w=1},tid="Иван Петров#1700000001",v=1}
6 Иван Петров WHISPER Мария Стоянова {a={k="start"},e=1,left=45,q=2,seat=0,t="EV",tid="Иван Петров#1700000001",v=1}
6 Иван Петров WHISPER Kiro Barley {a={k="start"},e=1,left=45,q=2,seat=0,t="EV",tid="Иван Петров#1700000001",v=1}
6 Мария Стоянова GUILD nil {at="Иван Петров#1700000001",cls="PRIEST",id="Player-0000-00000002",re=false,t="HI",v=1,ver="0.1.0"}
7 Иван Петров GUILD nil {ac="guild",e=1,g="ttt",h="Иван Петров",s={[1]="Иван Петров",[2]="Мария Стоянова"},st="live",t="TBL",tid="Иван Петров#1700000001",tn=45,v=1,w=1}
8 Иван Петров WHISPER Мария Стоянова {a={c=1,k="mark"},e=1,left=45,q=3,seat=1,t="EV",tid="Иван Петров#1700000001",v=1}
8 Иван Петров WHISPER Kiro Barley {a={c=1,k="mark"},e=1,left=45,q=3,seat=1,t="EV",tid="Иван Петров#1700000001",v=1}
9 Мария Стоянова WHISPER Иван Петров {a={c=4,k="mark"},t="ACT",tid="Иван Петров#1700000001",v=1}
10 Иван Петров WHISPER Мария Стоянова {a={c=4,k="mark"},e=1,left=45,q=4,seat=2,t="EV",tid="Иван Петров#1700000001",v=1}
10 Иван Петров WHISPER Kiro Barley {a={c=4,k="mark"},e=1,left=45,q=4,seat=2,t="EV",tid="Иван Петров#1700000001",v=1}
10 Иван Петров WHISPER Мария Стоянова {a={c=2,k="mark"},e=1,left=45,q=5,seat=1,t="EV",tid="Иван Петров#1700000001",v=1}
10 Иван Петров WHISPER Kiro Barley {a={c=2,k="mark"},e=1,left=45,q=5,seat=1,t="EV",tid="Иван Петров#1700000001",v=1}
11 Мария Стоянова WHISPER Иван Петров {a={c=5,k="mark"},t="ACT",tid="Иван Петров#1700000001",v=1}
12 Иван Петров WHISPER Мария Стоянова {a={c=5,k="mark"},e=1,left=45,q=6,seat=2,t="EV",tid="Иван Петров#1700000001",v=1}
12 Иван Петров WHISPER Kiro Barley {a={c=5,k="mark"},e=1,left=45,q=6,seat=2,t="EV",tid="Иван Петров#1700000001",v=1}
12 Иван Петров WHISPER Мария Стоянова {a={c=3,k="mark"},e=1,q=7,seat=1,t="EV",tid="Иван Петров#1700000001",v=1}
12 Иван Петров WHISPER Kiro Barley {a={c=3,k="mark"},e=1,q=7,seat=1,t="EV",tid="Иван Петров#1700000001",v=1}
15 Иван Петров WHISPER Мария Стоянова {a={k="next"},e=1,left=45,q=8,seat=0,t="EV",tid="Иван Петров#1700000001",v=1}
15 Иван Петров WHISPER Kiro Barley {a={k="next"},e=1,left=45,q=8,seat=0,t="EV",tid="Иван Петров#1700000001",v=1}
17 Мария Стоянова WHISPER Иван Петров {a={c=4,k="mark"},t="ACT",tid="Иван Петров#1700000001",v=1}
18 Иван Петров WHISPER Мария Стоянова {a={c=4,k="mark"},e=1,left=45,q=9,seat=2,t="EV",tid="Иван Петров#1700000001",v=1}
18 Иван Петров WHISPER Kiro Barley {a={c=4,k="mark"},e=1,left=45,q=9,seat=2,t="EV",tid="Иван Петров#1700000001",v=1}
18 Иван Петров WHISPER Мария Стоянова {a={c=1,k="mark"},e=1,left=45,q=10,seat=1,t="EV",tid="Иван Петров#1700000001",v=1}
18 Иван Петров WHISPER Kiro Barley {a={c=1,k="mark"},e=1,left=45,q=10,seat=1,t="EV",tid="Иван Петров#1700000001",v=1}
19 Мария Стоянова WHISPER Иван Петров {a={c=5,k="mark"},t="ACT",tid="Иван Петров#1700000001",v=1}
20 Иван Петров WHISPER Мария Стоянова {a={c=5,k="mark"},e=1,left=45,q=11,seat=2,t="EV",tid="Иван Петров#1700000001",v=1}
20 Иван Петров WHISPER Kiro Barley {a={c=5,k="mark"},e=1,left=45,q=11,seat=2,t="EV",tid="Иван Петров#1700000001",v=1}
20 Иван Петров WHISPER Мария Стоянова {a={c=2,k="mark"},e=1,left=45,q=12,seat=1,t="EV",tid="Иван Петров#1700000001",v=1}
20 Иван Петров WHISPER Kiro Barley {a={c=2,k="mark"},e=1,left=45,q=12,seat=1,t="EV",tid="Иван Петров#1700000001",v=1}
21 Мария Стоянова WHISPER Иван Петров {a={c=9,k="mark"},t="ACT",tid="Иван Петров#1700000001",v=1}
22 Иван Петров WHISPER Мария Стоянова {a={c=9,k="mark"},e=1,left=45,q=13,seat=2,t="EV",tid="Иван Петров#1700000001",v=1}
22 Иван Петров WHISPER Kiro Barley {a={c=9,k="mark"},e=1,left=45,q=13,seat=2,t="EV",tid="Иван Петров#1700000001",v=1}
22 Иван Петров WHISPER Мария Стоянова {a={c=3,k="mark"},e=1,q=14,seat=1,t="EV",tid="Иван Петров#1700000001",v=1}
22 Иван Петров WHISPER Kiro Barley {a={c=3,k="mark"},e=1,q=14,seat=1,t="EV",tid="Иван Петров#1700000001",v=1}
25 Иван Петров WHISPER Мария Стоянова {a={k="next"},e=1,left=45,q=15,seat=0,t="EV",tid="Иван Петров#1700000001",v=1}
25 Иван Петров WHISPER Kiro Barley {a={k="next"},e=1,left=45,q=15,seat=0,t="EV",tid="Иван Петров#1700000001",v=1}
27 Иван Петров WHISPER Мария Стоянова {a={c=1,k="mark"},e=1,left=45,q=16,seat=1,t="EV",tid="Иван Петров#1700000001",v=1}
27 Иван Петров WHISPER Kiro Barley {a={c=1,k="mark"},e=1,left=45,q=16,seat=1,t="EV",tid="Иван Петров#1700000001",v=1}
28 Мария Стоянова WHISPER Иван Петров {a={c=4,k="mark"},t="ACT",tid="Иван Петров#1700000001",v=1}
29 Иван Петров WHISPER Мария Стоянова {a={c=4,k="mark"},e=1,left=45,q=17,seat=2,t="EV",tid="Иван Петров#1700000001",v=1}
29 Иван Петров WHISPER Kiro Barley {a={c=4,k="mark"},e=1,left=45,q=17,seat=2,t="EV",tid="Иван Петров#1700000001",v=1}
29 Иван Петров WHISPER Мария Стоянова {a={c=2,k="mark"},e=1,left=45,q=18,seat=1,t="EV",tid="Иван Петров#1700000001",v=1}
29 Иван Петров WHISPER Kiro Barley {a={c=2,k="mark"},e=1,left=45,q=18,seat=1,t="EV",tid="Иван Петров#1700000001",v=1}
30 Мария Стоянова WHISPER Иван Петров {a={c=5,k="mark"},t="ACT",tid="Иван Петров#1700000001",v=1}
31 Иван Петров WHISPER Мария Стоянова {e=1,q=18,t="TCK",tid="Иван Петров#1700000001",v=1}
31 Иван Петров WHISPER Kiro Barley {e=1,q=18,t="TCK",tid="Иван Петров#1700000001",v=1}
31 Иван Петров WHISPER Мария Стоянова {a={c=5,k="mark"},e=1,left=45,q=19,seat=2,t="EV",tid="Иван Петров#1700000001",v=1}
31 Иван Петров WHISPER Kiro Barley {a={c=5,k="mark"},e=1,left=45,q=19,seat=2,t="EV",tid="Иван Петров#1700000001",v=1}
31 Иван Петров WHISPER Мария Стоянова {a={c=3,k="mark"},e=1,q=20,seat=1,t="EV",tid="Иван Петров#1700000001",v=1}
31 Иван Петров WHISPER Kiro Barley {a={c=3,k="mark"},e=1,q=20,seat=1,t="EV",tid="Иван Петров#1700000001",v=1}
35 Kiro Barley WHISPER Иван Петров {t="PNG",tid="Иван Петров#1700000001",v=1}
36 Мария Стоянова WHISPER Иван Петров {t="PNG",tid="Иван Петров#1700000001",v=1}
61 Иван Петров WHISPER Мария Стоянова {e=1,q=20,t="TCK",tid="Иван Петров#1700000001",v=1}
61 Иван Петров WHISPER Kiro Barley {e=1,q=20,t="TCK",tid="Иван Петров#1700000001",v=1}
65 Kiro Barley WHISPER Иван Петров {t="PNG",tid="Иван Петров#1700000001",v=1}
66 Мария Стоянова WHISPER Иван Петров {t="PNG",tid="Иван Петров#1700000001",v=1}
67 Иван Петров GUILD nil {ac="guild",e=1,g="ttt",h="Иван Петров",s={[1]="Иван Петров",[2]="Мария Стоянова"},st="live",t="TBL",tid="Иван Петров#1700000001",tn=45,v=1,w=1}
]==]

describe("stakes: fun tables are untouched", function()
  it("a fun-only evening is byte-identical but for HI.ld and R", function()
    local log, levs, his = funLog()
    local ref = {}
    for line in FUN_82B0140:gmatch("[^\n]+") do ref[#ref + 1] = line end
    eq(#log, #ref)
    for j = 1, math.max(#log, #ref) do eq(log[j], ref[j], "line " .. j) end
    -- What was dropped: the host's one LEV with the result, on GUILD; and every HI carried a digest.
    eq(#levs, 1)
    eq({ levs[1].from, levs[1].channel, #levs[1].msg.ev, levs[1].msg.ev[1].k }, { FUN_A, "GUILD", 1, "R" })
    ok(his > 0, "no HI had an ld")
  end)
end)

ns.LedgerNet.size = stand
