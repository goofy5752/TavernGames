local Sim = require("sim")
local Loader = require("loader")

-- An old client does not know chess: a client of a second namespace without the
-- chess engine, its registry lines and its locale keys (an old build has none).

local A, B, O = "Иван Петров", "Мария Стоянова", "Стар Клиент"

local function oldNs()
  local old = Loader.ns()
  old.Engines.chess = nil
  for _, list in ipairs{ old.Games.ORDER } do
    for i = #list, 1, -1 do if list[i] == "chess" then table.remove(list, i) end end
  end
  old.Games.PLAYERS.chess, old.Games.PLAYABLE.chess = nil, nil
  for _, t in pairs(old.Locale.tables) do
    for k in pairs(t) do
      if k == "game.chess" or k:find("^opt%.chess%.") or k:find("^optv%.chess%.") then t[k] = nil end
    end
  end
  -- the seeds of a sim client (tests/helpers/sim.lua does the same for its namespace)
  old.Fair.seed = function(env)
    local out = {}
    for i = 1, old.Const.SEED_BYTES do out[i] = string.format("%02x", env.random(0, 255)) end
    return table.concat(out)
  end
  return old
end

-- The client of namespace `old` joined to the bus the way Sim:join does it.
local function joinOld(sim, old, name)
  local env = sim:newEnv(name, { cls = "WARRIOR" })
  env.guild = "МЕХАНАТА"
  env.db.ledger = {}
  sim:addFakes(env, {})
  local client = old.Client.new(env)
  sim.clients[name], sim.envs[name] = client, env
  sim.bus:join(name, function(channel, sender, msg)
    if sim.offlineSet[name] or sim.offlineSet[sender] then return end
    client:receive(channel, sender, msg)
  end)
  client:start()
  return client, env
end

local function world()
  local sim = Sim.new()
  local old = oldNs()
  local a = sim:add(A, { cls = "MAGE" })
  local b = sim:add(B, { cls = "PRIEST" })
  local o, env = joinOld(sim, old, O)
  sim:run(1)
  return sim, old, a, b, o, env
end

describe("chess and an old client", function()
  it("an old client lists a chess table for fun as an unknown game", function()
    local sim, old, a, _, o = world()
    local tid = a:openTable{ game = "chess", access = "guild", turn = 45, opt = { clock = 10 } }; sim:run(3)
    local rec = o.lobby:get(tid)
    ok(rec, "the old client does not list the table"); eq(rec.game, "chess")
    eq(old.Games.engine("chess"), nil)
    eq(old.L("game.chess"), "game.chess") -- W.gameName turns this into L("game.unknown")
    eq(old.L("game.unknown"), "Непозната игра")
  end)

  it("an old client does not see a staked chess table", function()
    local sim, _, a, _, o = world()
    local tid = a:openTable{ game = "chess", access = "guild", turn = 45, stake = 50000, opt = { clock = 10 } }
    ok(tid, "the staked table did not open"); sim:run(3)
    eq(o.lobby:get(tid), nil)
  end)

  it("an old client cannot sit", function()
    local sim, _, a, _, o = world()
    local tid = a:openTable{ game = "chess", access = "guild", turn = 45, opt = { clock = 10 } }; sim:run(3)
    local refused = {}
    o:on("refused", function(t, why) refused[#refused + 1] = { t, why } end)
    local n = #sim.sent
    o:sit(tid, 2); sim:run(2)
    eq(refused, { { tid, "version" } }); eq(o.session, nil); eq(#sim.sent, n)
    eq(a.session.seats[2], false)
  end)

  -- Hosts a chess table (staked at `sk`, else for fun), seats B, plays three moves; returns
  -- tid, the host's SNP of it and the three EVs it sent after the snapshot.
  local function played(sim, a, b, sk)
    local tid = a:openTable{ game = "chess", access = "guild", turn = 45, stake = sk, opt = { clock = 10 } }
    ok(tid, "no table"); sim:run(3)
    b:sit(tid, 2, sk); sim:run(8)
    ok(b.session, "the guest is not seated"); eq(a.session.status, "live")
    local mark = #sim.sent
    local players = { a, b }
    for _, mv in ipairs{ { 13, 29 }, { 53, 37 }, { 7, 22 } } do -- e2e4 e7e5 g1f3, for whoever is on the move
      ok(players[a.session.state.turn]:act{ k = "move", f = mv[1], t = mv[2] }, "move " .. mv[1] .. mv[2]); sim:run(1)
    end
    local snp, evs = nil, {}
    for i, m in ipairs(sim.sent) do
      if m.msg.tid == tid and m.from == A then
        if m.msg.t == "SNP" and not snp then snp = m.msg end
        if i > mark and m.msg.t == "EV" and #evs < 3 then evs[#evs + 1] = m.msg end
      end
    end
    ok(snp, "no SNP"); eq(#evs, 3)
    return tid, snp, evs
  end

  -- What the host sent, by hand to the old client: copies, `dt` on the events, and a snapshot
  -- that seats it (the seat 2 of the table) when `seated`.
  local function deliver(sim, old, o, snp, evs, seated)
    local snap = old.Util.copy(snp)
    if seated then snap.tbl.s[2] = O end
    ok(pcall(function()
      o:receive("WHISPER", A, snap)
      for _, ev in ipairs(evs) do
        local e = old.Util.copy(ev)
        e.dt = 12
        o:receive("WHISPER", A, e)
      end
      sim:run(2)
    end), "the old client raised an error")
  end

  local function stdFrom(sim, from, to, tid)
    for _, m in ipairs(sim.sent) do
      if m.from == from and m.msg.t == "STD" and m.msg.tid == tid and m.target == to then return true end
    end
    return false
  end

  it("an invitation, a snapshot and events do not break it", function()
    local sim, old, a, b, o, env = world()
    local invited = {}
    o:on("invite", function(inv) invited[#invited + 1] = inv end)
    local tid0 = a:openTable{ game = "chess", access = "guild", turn = 45, opt = { clock = 10 } }; sim:run(3)
    ok(a:invite(O)); sim:run(2)
    eq(#invited, 1); eq(invited[1].tid, tid0)
    a:stand(); sim:run(2)
    local tid, snp, evs = played(sim, a, b)
    local ledger = old.Util.copy(env.db.ledger)
    deliver(sim, old, o, snp, evs, false)
    eq(o.session, nil); eq(env.db.ledger, ledger)
    eq(a.session.seats, { A, B })
    ok(not stdFrom(sim, O, A, tid), "a snapshot that did not seat it got an STD")
  end)

  it("a snapshot that seats the old client gets its STD", function()
    local sim, old, a, b, o, env = world()
    local tid, snp, evs = played(sim, a, b)
    deliver(sim, old, o, snp, evs, true)
    eq(o.session, nil)
    ok(stdFrom(sim, O, A, tid), "no STD from the old client")
  end)

  it("a staked table's snapshot and events leave the old client's ledger alone", function()
    local sim, old, a, b, o, env = world()
    local tid, snp, evs = played(sim, a, b, 50000)
    ok(snp.tbl.sk, "the snapshot carries no stake")
    local ledger = old.Util.copy(env.db.ledger)
    deliver(sim, old, o, snp, evs, false)
    eq(o.session, nil); eq(env.db.ledger, ledger)
    deliver(sim, old, o, snp, evs, true)
    eq(o.session, nil); eq(env.db.ledger, ledger)
    ok(stdFrom(sim, O, A, tid), "no STD from the old client")
  end)

  it("a new client at an old table sees no change", function()
    local sim, _, a, b, o = world()
    local tid = o:openTable{ game = "ttt", access = "guild", turn = 45 }; sim:run(3)
    b:sit(tid, 2); sim:run(2)
    ok(b.session, "no seat at the old table")
    for _, mv in ipairs{ { o, 1 }, { b, 4 }, { o, 2 }, { b, 5 }, { o, 3 } } do
      ok(mv[1]:act{ k = "mark", c = mv[2] }, "move " .. mv[2]); sim:run(1)
    end
    ok(o.session.state, "no state"); eq(b.session.state, o.session.state)
    eq(a.session, nil)
  end)
end)
