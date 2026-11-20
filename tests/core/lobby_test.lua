local Sim = require("sim")

local A, B, C = "Иван Петров", "Мария Стоянова", "Kiro Barley"
local NEW = "Нов Клиент"

local function setup(opts)
  opts = opts or {}
  local sim = Sim.new()
  local a = sim:add(A, { cls = "MAGE", group = opts.groupA })
  local b = sim:add(B, { cls = "PRIEST" })
  local c = sim:add(C, { cls = "ROGUE" })
  sim:run(1)
  return sim, a, b, c
end

local function refusals(client)
  local list = {}
  client:on("refused", function(tid, why) list[#list + 1] = { tid, why } end)
  return list
end

local function sentBy(sim, from, mark, pred)
  local out = {}
  for i, s in ipairs(sim.sent) do
    if i > mark and s.from == from and (not pred or pred(s)) then out[#out + 1] = s end
  end
  return out
end

local function tbl(fields)
  local m = { v = 1, t = "TBL", g = "ttt", ac = "guild", tn = 45, st = "live", w = 0 }
  for k, v in pairs(fields) do m[k] = v end
  return m
end

describe("lobby and seating", function()
  it("open -> everyone sees the table; sit fills the dashed chair", function()
    local sim, a, b, c = setup()
    local tid = a:openTable{game="ttt", access="guild", turn=45}; sim:run(3)
    eq(tid, A .. "#1700000001")
    eq(b.lobby:get(tid), { tid = tid, game = "ttt", host = A, epoch = 1, access = "guild", turn = 45,
      state = "open", seats = { A, false }, watchers = 0 })
    eq(a.session.role, "host"); eq(a.session.mySeat, 1); eq(a.session.epoch, 1); eq(a.session.host, A)
    eq(b.lobby:get(tid).seats, {A, false}); b:sit(tid, 2); sim:run(3)
    eq(c.lobby:get(tid).seats, {A, B}); eq(b.session.mySeat, 2); eq(b.session.role, "player")
    eq(c.presence:get(B).at, tid)
    eq(b.session.seats, {A, B}); eq(b.session.host, A); eq(b.session.status, "live") -- full: started (Task 5)
    eq(b.session:record(), { tid = tid, g = "ttt", h = A, e = 1, ac = "guild", tn = 45, st = "live", s = { A, B }, w = 0 })
    eq(#b.lobby:tables(), 1); eq(b.lobby:tables()[1].tid, tid)
  end)

  it("emits session on every change, with nil when it ends", function()
    local sim, a, b = setup()
    local tid = a:openTable{game="ttt", access="guild", turn=45}; sim:run(3)
    local seen = {}
    b:on("session", function(s) seen[#seen + 1] = s and s.role or "none" end)
    local tables = 0; b:on("tables", function() tables = tables + 1 end)
    b:watch(tid); sim:run(1); b:sit(tid, 2); sim:run(1); b:stand()
    eq(seen, { "watcher", "player", "player", "none" }); eq(b.session, nil) -- the 2nd "player": start
    sim:run(3); ok(tables >= 1); eq(b.lobby:get(tid).seats, { A, false })
  end)

  it("openTable refuses busy, unknown game, bad access, bad turn", function()
    local sim, a = setup()
    eq({ a:openTable{game="chess", access="guild", turn=45} }, { nil, "game" })
    eq({ a:openTable{game="ttt", access="public", turn=45} }, { nil, "access" })
    eq({ a:openTable{game="ttt", access="guild", turn=50} }, { nil, "turn" })
    eq(a.session, nil)
    ok(a:openTable{game="ttt", access="group", turn=90}); sim:run(1)
    eq({ a:openTable{game="ttt", access="guild", turn=45} }, { nil, "busy" })
  end)

  it("two players click the same chair: one sits, the other is refused 'taken'", function()
    local sim, a, b, c = setup()
    local tid = a:openTable{game="ttt", access="guild", turn=45}; sim:run(3)
    local rb, rc = refusals(b), refusals(c)
    b:sit(tid, 2); c:sit(tid, 2); sim:run(1)
    eq(b.session.mySeat, 2); eq(c.session, nil)
    eq(rc, { { tid, "taken" } }); eq(rb, {})
    eq(a.session.seats, { A, B })
    c:sit(tid, 7); sim:run(1); eq(rc[2], { tid, "taken" })
  end)

  it("invite-only refuses strangers; group table asks env.inGroup", function()
    local sim, a, b, c = setup({ groupA = { C } })
    local tid = a:openTable{game="ttt", access="invite", turn=45}; sim:run(3)
    local rb = refusals(b)
    b:sit(tid, 2); sim:run(1); eq(rb, { { tid, "access" } }); eq(b.session, nil)
    b:watch(tid); sim:run(1); eq(rb[2], { tid, "access" }); eq(b.session, nil)
    ok(a:invite(C)); eq(a.session.invited[C], true)
    c:sit(tid, 2); sim:run(1); eq(c.session.mySeat, 2)
    c:stand(); a:stand(); sim:run(3)

    local gid = a:openTable{game="ttt", access="group", turn=45}; sim:run(3)
    b:sit(gid, 2); sim:run(1); eq(rb[3], { gid, "access" }); eq(b.session, nil)
    c:sit(gid, 2); sim:run(1); eq(c.session.mySeat, 2); eq(a.session.seats, { A, C })
  end)

  it("cannot sit at two tables", function()
    local sim, a, b, c = setup()
    local tid = a:openTable{game="ttt", access="guild", turn=45}; sim:run(3)
    b:sit(tid, 2); sim:run(3)
    local ctid = c:openTable{game="ttt", access="guild", turn=45}; sim:run(3)
    local rb = refusals(b)
    b:sit(ctid, 2); b:watch(ctid); sim:run(1)
    eq(rb, { { ctid, "busy" }, { ctid, "busy" } }); eq(b.session.tid, tid)
    eq({ b:openTable{game="ttt", access="guild", turn=45} }, { nil, "busy" })
    -- the host's own check, by Presence `at`
    local m0 = #sim.sent
    c:receive("WHISPER", B, { v = 1, t = "SIT", tid = ctid, seat = 2 }); sim:run(1)
    local sno = sentBy(sim, C, m0, function(s) return s.msg.t == "SNO" end)
    eq(#sno, 1); eq(sno[1].target, B); eq(sno[1].msg.why, "busy"); eq(sno[1].msg.tid, ctid)
    eq(c.session.seats, { C, false }); eq(#rb, 2)
  end)

  it("ten quick changes produce at most one TBL per 2 s", function()
    local sim, a, b, c = setup()
    local tid = a:openTable{game="ttt", access="guild", turn=45}; sim:run(1)
    local function tblTimes(mark)
      local out = {}
      for _, s in ipairs(sentBy(sim, A, mark, function(s)
        return s.channel == "GUILD" and s.msg.t == "TBL" and s.msg.tid == tid end)) do out[#out + 1] = s.at end
      return out
    end
    local m0 = #sim.sent
    for i = 1, 9 do
      if i % 2 == 1 then b:watch(tid) else b:stand() end
      sim:run(0)
    end
    c:watch(tid); sim:run(0)
    eq(a.session.watchers, 2)
    sim:run(2)
    ok(#tblTimes(m0) <= 1); eq(#tblTimes(m0), 1)
    eq(c.lobby:get(tid).watchers, 2)
    sim:run(130)
    local times = tblTimes(0)
    ok(#times >= 4)
    for i = 2, #times do ok(times[i] - times[i - 1] >= 2, "gap at " .. times[i]) end
  end)

  it("table disappears on END and after 150 s of silence", function()
    local sim, a, b, c = setup()
    local tid = a:openTable{game="ttt", access="guild", turn=45}; sim:run(3)
    b:watch(tid); sim:run(1); eq(b.session.role, "watcher")
    a:stand(); sim:run(1)
    eq(b.lobby:get(tid), nil); eq(c.lobby:get(tid), nil); eq(a.lobby:get(tid), nil)
    eq(a.session, nil); eq(b.session, nil)
    sim:run(3); eq(c.presence:get(A).at, nil); eq(c.presence:get(B).at, nil)

    local tid2 = a:openTable{game="ttt", access="guild", turn=45}; sim:run(3)
    ok(tid2 ~= tid); ok(b.lobby:get(tid2))
    sim:offline(A); sim:run(100); ok(b.lobby:get(tid2))
    sim:run(51); eq(b.lobby:get(tid2), nil); eq(c.lobby:get(tid2), nil)
  end)

  it("late joiner gets the table by whisper", function()
    local sim = Sim.new(); local a = sim:add(A, { cls = "MAGE" }); sim:run(1)
    local tid = a:openTable{game="ttt", access="guild", turn=45}; sim:run(3)
    local m0 = #sim.sent
    local c = sim:add(C, { cls = "ROGUE" }); sim:run(1)
    ok(c.lobby:get(tid) ~= nil); eq(c.lobby:get(tid).host, A)
    eq(#sentBy(sim, A, m0, function(s) return s.msg.t == "TBL" and s.channel == "WHISPER" and s.target == C end), 1)
    eq(#sentBy(sim, A, m0, function(s) return s.msg.t == "TBL" and s.channel == "GUILD" end), 0)
  end)

  it("ignores TBL whose sender is not its host field", function()
    local sim, a, b = setup()
    local tid = a:openTable{game="ttt", access="guild", turn=45}; sim:run(3)
    b:receive("GUILD", C, tbl{ tid = tid, h = A, e = 9, s = { A, false } })
    eq(b.lobby:get(tid).epoch, 1); eq(b.lobby:get(tid).host, A)
    b:receive("GUILD", A, tbl{ tid = tid, h = C, e = 9, s = { C, false } })
    eq(b.lobby:get(tid).epoch, 1); eq(b.lobby:get(tid).host, A)
    b:receive("GUILD", A, tbl{ tid = tid, h = A, e = 2, s = { A, false } })
    eq(b.lobby:get(tid).epoch, 2)
  end)

  it("a higher epoch from another host is taken only if he sits at the known table", function()
    local sim, a, b = setup()
    local tid = a:openTable{game="ttt", access="guild", turn=45}; sim:run(3)
    -- C is not seated at A's table: his claim is ignored, A's TBLs still count
    b:receive("GUILD", C, tbl{ tid = tid, h = C, e = 5, s = { C, false } })
    eq(b.lobby:get(tid).host, A); eq(b.lobby:get(tid).epoch, 1)
    b:receive("GUILD", A, tbl{ tid = tid, h = A, e = 1, s = { A, C } })
    eq(b.lobby:get(tid).seats, { A, C })
    -- seated now: his claim at a higher epoch wins
    b:receive("GUILD", C, tbl{ tid = tid, h = C, e = 2, s = { false, C } })
    eq(b.lobby:get(tid).host, C); eq(b.lobby:get(tid).epoch, 2)
    -- A no longer sits there: A cannot take it back
    b:receive("GUILD", A, tbl{ tid = tid, h = A, e = 3, s = { A, C } })
    eq(b.lobby:get(tid).host, C)
    -- END from the known host still closes it
    b:receive("GUILD", C, { v = 1, t = "END", tid = tid, e = 2 }); eq(b.lobby:get(tid), nil)
  end)

  it("equal epoch from another host: the lower seat index wins", function()
    local sim, _, b = setup()
    local D, E = "Пешо Тодоров", "Гошо Тестов"
    b:receive("GUILD", D, tbl{ tid = "X#1", h = D, e = 1, s = { E, D } })
    eq(b.lobby:get("X#1").host, D)
    b:receive("GUILD", E, tbl{ tid = "X#1", h = E, e = 1, s = { E, D } })
    eq(b.lobby:get("X#1").host, E)
    b:receive("GUILD", D, tbl{ tid = "X#1", h = D, e = 1, s = { E, D } })
    eq(b.lobby:get("X#1").host, E)
    b:receive("GUILD", D, tbl{ tid = "X#1", h = D, e = 2, s = { E, D } })
    eq(b.lobby:get("X#1").host, D); eq(b.lobby:get("X#1").epoch, 2)
    b:receive("GUILD", E, tbl{ tid = "X#1", h = E, e = 1, s = { E, D } })
    eq(b.lobby:get("X#1").host, D)
    b:receive("GUILD", E, { v = 1, t = "END", tid = "X#1", e = 2 }); ok(b.lobby:get("X#1"))
    b:receive("GUILD", D, { v = 1, t = "END", tid = "X#1", e = 2 }); eq(b.lobby:get("X#1"), nil)
  end)

  it("equal epoch tie reads the claimant's seat from the known record, not its own claim", function()
    local _, _, b = setup()
    local D, E, F, G = "Пешо Тодоров", "Гошо Тестов", "Тошо Петков", "Чужд Човек"
    b:receive("GUILD", E, tbl{ tid = "X#1", h = E, e = 1, s = { D, E, F } })
    eq(b.lobby:get("X#1").host, E)
    -- F sits at seat 3 of the known record and moves itself to seat 1 in its claim
    b:receive("GUILD", F, tbl{ tid = "X#1", h = F, e = 1, s = { F, E, D } })
    eq(b.lobby:get("X#1").host, E)
    -- G is not seated at all and claims seat 1
    b:receive("GUILD", G, tbl{ tid = "X#1", h = G, e = 1, s = { G, E, F } })
    eq(b.lobby:get("X#1").host, E)
    -- D really sits lower than E: its tie claim wins
    b:receive("GUILD", D, tbl{ tid = "X#1", h = D, e = 1, s = { D, E, F } })
    eq(b.lobby:get("X#1").host, D)
  end)

  it("refuses a newer client's SIT with 'version'", function()
    local sim, a = setup()
    local tid = a:openTable{game="ttt", access="guild", turn=45}; sim:run(3)
    local m0 = #sim.sent
    a:receive("WHISPER", NEW, { v = 2, t = "SIT", tid = tid, seat = 2 }); sim:run(1)
    local fromA = sentBy(sim, A, m0)
    eq(#fromA, 1)
    eq(fromA[1].channel, "WHISPER"); eq(fromA[1].target, NEW)
    eq(fromA[1].msg.t, "SNO"); eq(fromA[1].msg.tid, tid); eq(fromA[1].msg.why, "version"); eq(fromA[1].msg.v, 1)
    eq(a.session.seats, { A, false })

    local m1 = #sim.sent
    a:receive("WHISPER", NEW, { v = 2, t = "WAT", tid = tid }); sim:run(0)
    a:receive("WHISPER", NEW, { v = 2, t = "SIT", tid = "Y#1", seat = 2 }); sim:run(0)
    a:receive("WHISPER", NEW, { v = 1, t = "SIT", tid = tid, seat = 2 }); sim:run(0)
    local why = {}
    for _, s in ipairs(sentBy(sim, A, m1)) do why[#why + 1] = s.msg.t .. ":" .. tostring(s.msg.why) end
    eq(why, { "SNO:version", "SNO:version" })
    eq(a.session.seats, { A, false }); eq(a.session.watchers, 0)
  end)

  it("watcher is counted and limited to 8", function()
    local sim = Sim.new(); local a = sim:add(A, { cls = "MAGE" })
    local ws = {}
    for i = 1, 9 do ws[i] = sim:add("Зрител " .. i, { cls = "HUNTER" }) end
    sim:run(1)
    local tid = a:openTable{game="ttt", access="guild", turn=45}; sim:run(3)
    for i = 1, 8 do ws[i]:watch(tid) end
    sim:run(3)
    eq(a.lobby:get(tid).watchers, 8); eq(ws[9].lobby:get(tid).watchers, 8)
    eq(ws[1].session.role, "watcher"); eq(ws[1].session.mySeat, nil)
    local r = refusals(ws[9])
    ws[9]:watch(tid); sim:run(1)
    eq(r, { { tid, "full" } }); eq(ws[9].session, nil)
    -- a watcher may take a free chair; that frees a watcher slot
    ws[2]:sit(tid, 2); sim:run(1)
    eq(ws[2].session.role, "player"); eq(a.session.watchers, 7); eq(ws[1].session.seats, { A, ws[2].env.me })
    ws[9]:watch(tid); sim:run(1); eq(ws[9].session.role, "watcher"); eq(a.session.watchers, 8)
  end)

  it("seating changes are ordered events; the newcomer gets a snapshot", function()
    local sim, a, b, c = setup()
    local tid = a:openTable{game="ttt", access="guild", turn=45}; sim:run(3)
    c:watch(tid); sim:run(1); eq(c.session.seq, 0)
    local m0 = #sim.sent
    b:sit(tid, 2); sim:run(1)
    -- the sit fills the table, so a start event (q 2, Task 5) follows it
    eq(c.session.seats, { A, B }); eq(c.session.seq, 2); eq(b.session.seq, 2)
    local ev = sentBy(sim, A, m0, function(s) return s.msg.t == "EV" and s.msg.a.k == "sit" end)
    eq(#ev, 1); eq(ev[1].target, C)
    eq(ev[1].msg.seat, 0); eq(ev[1].msg.q, 1); eq(ev[1].msg.e, 1); eq(ev[1].msg.a, { k = "sit", seat = 2, name = B })
    local snp = sentBy(sim, A, m0, function(s) return s.msg.t == "SNP" end)
    eq(#snp, 1); eq(snp[1].target, B); eq(snp[1].msg.q, 1); eq(snp[1].msg.tbl.s, { A, B })
    local m1 = #sim.sent
    b:stand(); sim:run(1)
    eq(c.session.seats, { A, false }); eq(c.session.seq, 4); eq(a.session.seats, { A, false }) -- stand, abort
    ev = sentBy(sim, A, m1, function(s) return s.msg.t == "EV" and s.msg.a.k == "stand" end)
    eq(#ev, 1); eq(ev[1].target, C); eq(ev[1].msg.a, { k = "stand", seat = 2, why = "left" })
  end)

  it("unknown or closed tables are refused 'gone'", function()
    local sim, a, b = setup()
    local rb = refusals(b)
    b:sit("Z#1", 2); eq(rb, { { "Z#1", "gone" } })
    local m0 = #sim.sent
    a:receive("WHISPER", B, { v = 1, t = "SIT", tid = "Z#1", seat = 2 }); sim:run(1)
    local sno = sentBy(sim, A, m0, function(s) return s.msg.t == "SNO" end)
    eq(#sno, 1); eq(sno[1].target, B); eq(sno[1].msg.why, "gone")
  end)

  it("an answer to a forgotten request frees the chair again", function()
    local sim, a, b, c = setup()
    local tid = a:openTable{game="ttt", access="guild", turn=45}; sim:run(3)
    b:sit(tid, 2); b:stand(); sim:run(1)
    eq(b.session, nil); eq(a.session.seats, { A, false })
    -- sat elsewhere while the answer was on its way
    local ctid = c:openTable{game="ttt", access="guild", turn=45}; sim:run(3)
    local held
    sim.bus.filter = function(from, _, _, m)
      if from == A and m.t == "SNP" then held = m; return {} end
      return { m }
    end
    b:sit(tid, 2); sim:run(1); sim.bus.filter = nil
    eq(a.session.seats, { A, B }); ok(held)
    b:sit(ctid, 2); sim:run(1); eq(b.session.tid, ctid)
    b:receive("WHISPER", A, held); sim:run(1)
    eq(b.session.tid, ctid); eq(a.session.seats, { A, false })
  end)

  it("stop (logout, /reload) sends only BYE: seat and match are kept", function()
    local sim, a, b, c = setup()
    local tid = a:openTable{game="ttt", access="guild", turn=45}; sim:run(3)
    b:sit(tid, 2); c:watch(tid); sim:run(3)
    eq(a.session.status, "live")
    local m0 = #sim.sent
    b:stop(); sim:run(1)
    eq(a.session.seats, { A, B }); eq(a.session.status, "live")
    local kinds = {}
    for _, s in ipairs(sentBy(sim, B, m0)) do kinds[#kinds + 1] = s.msg.t end
    eq(kinds, { "BYE" })
    c:stop(); sim:run(1)
    kinds = {}
    for _, s in ipairs(sentBy(sim, C, m0)) do kinds[#kinds + 1] = s.msg.t end
    eq(kinds, { "BYE" })
  end)

  it("stop by a host alone at its table closes it: nobody could hand it back", function()
    local sim, a, _, c = setup()
    local tid = a:openTable{game="ttt", access="guild", turn=45}; sim:run(3)
    c:watch(tid); sim:run(3)
    local m0 = #sim.sent
    a:stop(); sim:run(1)
    eq(c.session, nil); eq(c.lobby:get(tid), nil)
    local kinds = {}
    for _, s in ipairs(sentBy(sim, A, m0)) do kinds[#kinds + 1] = s.msg.t end
    eq(kinds, { "END", "BYE" })
  end)
end)
