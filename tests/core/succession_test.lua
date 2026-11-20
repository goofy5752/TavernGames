local Sim = require("sim")
require("fake_engine")
local S = Sim.ns.Succession

local A, B, C, D = "Иван Петров", "Мария Стоянова", "Kiro Barley", "Пешо Тодоров"

-- a hosts a ttt table, c watches, b sits in seat 2: the match is live.
local function ttt()
  local sim = Sim.new()
  local a = sim:add(A, { cls = "MAGE" })
  local b = sim:add(B, { cls = "PRIEST" })
  local c = sim:add(C, { cls = "ROGUE" })
  sim:run(1)
  local tid = a:openTable{game="ttt", access="guild", turn=45}; sim:run(3)
  c:watch(tid); sim:run(1)
  b:sit(tid, 2); sim:run(3)
  return sim, a, b, c, tid
end

-- fake engine: a, b, c seated (live), d watches.
local function fake()
  local sim = Sim.new()
  local a = sim:add(A, { cls = "MAGE" })
  local b = sim:add(B, { cls = "PRIEST" })
  local c = sim:add(C, { cls = "ROGUE" })
  local d = sim:add(D, { cls = "DRUID" })
  sim:run(1)
  local tid = a:openTable{game="fake", access="guild", turn=45}; sim:run(3)
  b:sit(tid, 2); c:sit(tid, 3); d:watch(tid); sim:run(3)
  return sim, a, b, c, d, tid
end

local function incs(sim, ...)
  for _, cl in ipairs({ ... }) do ok(cl:act{k="inc"}); sim:run(1) end
end

local function sentBy(sim, from, mark, pred)
  local out = {}
  for i, s in ipairs(sim.sent) do
    if i > mark and s.from == from and (not pred or pred(s)) then out[#out + 1] = s end
  end
  return out
end

local function ofType(t) return function(s) return s.msg.t == t end end

-- Nothing at all passes between x and y (either direction, either channel).
local function cut(x, y)
  return function(from, to, _, m)
    if (from == x and to == y) or (from == y and to == x) then return {} end
    return { m }
  end
end

local function whispersCut(x, y)
  return function(from, to, channel, m)
    if channel == "WHISPER" and ((from == x and to == y) or (from == y and to == x)) then return {} end
    return { m }
  end
end

describe("offline seats and reconnect", function()
  it("offline player's turns are auto-played, then he is stood up at 180 s", function()
    local sim, a, _, c, tid = ttt()
    local last = 0; for _, s in ipairs(sim.sent) do if s.from == B then last = s.at end end
    local m0 = #sim.sent
    sim:offline(B); sim:run(179 - (sim:now() - last)); eq(a.session.seats[2], B)
    eq(a.session.status, "live"); eq(a.session.state.board[2], 2, "B's turn was auto-played")
    sim:run(2)
    eq(a.session.seats[2], false); eq(a.session.status, "aborted")
    eq(c.session.seats, { A, false }); eq(c.session.status, "aborted"); eq(c.lobby:get(tid).seats, { A, false })
    local kinds = {}
    for _, s in ipairs(sentBy(sim, A, m0, function(s) return s.msg.t == "EV" and s.target == C and s.msg.seat == 0 end)) do
      kinds[#kinds + 1] = { s.msg.a.k, s.msg.a.why }
    end
    eq(kinds, { { "stand", "offline" }, { "abort" } })
  end)

  it("BYE and peerOffline do not shorten the 180 s wait", function()
    local sim, a = ttt()
    sim:run(5)
    sim:offline(B)
    local at = sim:now()
    a:receive("GUILD", B, { v = 1, t = "BYE" }); a:peerOffline(B)
    sim:run(179); eq(a.session.seats[2], B)
    sim:run(1); eq(a.session.seats[2], false); eq(sim:now() - at, 180)
  end)

  it("a watcher silent for 75 s is dropped, and learns it when he returns", function()
    local sim, a, _, c, tid = ttt()
    sim:run(27) -- t=35: c's PNG went out at 35
    sim:offline(C); sim:run(74); eq(a.session.watchers, 1)
    sim:run(1); eq(a.session.watchers, 0); sim:run(3); eq(a.lobby:get(tid).watchers, 0)
    ok(c.session); sim:online(C); sim:run(30) -- c's next PNG is answered "gone"
    eq(c.session, nil)
  end)

  it("relog within 3 minutes restores seat, board and score", function()
    local sim, a, b = ttt()
    for _, mv in ipairs({ {a,1}, {b,4}, {a,2}, {b,5}, {a,3} }) do ok(mv[1]:act{k="mark", c=mv[2]}); sim:run(1) end
    sim:run(4); ok(b:act{k="mark", c=5}); sim:run(1)
    sim:offline(B); sim:run(60); local b2 = sim:relog(B); sim:run(2)
    eq(b2.session.mySeat, 2); eq(b2.session.state.board, a.session.state.board); eq(b2.session.state.score, a.session.state.score)
    eq(b2.session.state.score, {1,0}); eq(b2.session.role, "player"); eq(b2.session.host, A)
    eq(b2.session.seq, a.session.seq); eq(b2.session.status, "live")
    sim:run(200); eq(a.session.seats[2], B) -- heard again: no auto-stand
  end)

  it("a seated player who logs out (stop) and back in within 3 minutes keeps seat and board", function()
    local sim, a, b = ttt()
    for _, mv in ipairs({ {a,1}, {b,4}, {a,2} }) do ok(mv[1]:act{k="mark", c=mv[2]}); sim:run(1) end
    local m0 = #sim.sent
    b:stop(); sim:run(1)
    eq(#sentBy(sim, B, m0, function(s) return s.msg.t ~= "BYE" end), 0)
    eq(a.session.seats, { A, B }); eq(a.session.status, "live")
    sim:run(120); local b2 = sim:relog(B); sim:run(2)
    eq(a.session.seats, { A, B }); eq(a.session.status, "live")
    eq(b2.session.mySeat, 2); eq(b2.session.role, "player"); eq(b2.session.host, A)
    eq(b2.session.state.board, a.session.state.board); eq(b2.session.seq, a.session.seq)
    eq(b2.session.state.board[4], 2)
    sim:run(200); eq(a.session.seats[2], B) -- heard again: no auto-stand
  end)

  it("a seated player who logs out and stays away is stood up at 180 s", function()
    local sim, a, b = ttt()
    sim:run(5)
    b:stop(); sim:run(0); sim:offline(B) -- the BYE is the last thing heard from him
    sim:run(179); eq(a.session.seats[2], B)
    sim:run(1); eq(a.session.seats[2], false); eq(a.session.status, "aborted")
  end)

  it("a snapshot for a table I just left is answered with STD, not adopted", function()
    local sim, a, b, _, tid = ttt()
    local held
    sim.bus.filter = function(from, to, _, m)
      if from == A and to == B and m.t == "SNP" then held = m; return {} end
      return { m }
    end
    a:receive("WHISPER", B, { v = 1, t = "SYN", tid = tid, have = 0 }); sim:run(0); ok(held)
    sim.bus.filter = nil
    b:stand(); sim:run(1); eq(b.session, nil); eq(a.session.seats, { A, false })
    b:receive("WHISPER", A, held); sim:run(1)
    eq(b.session, nil)
  end)

  it("a stale snapshot of the same epoch does not roll a member back", function()
    local sim, a, b, _, tid = ttt()
    local old
    sim.bus.filter = function(from, to, _, m)
      if from == A and to == B and m.t == "SNP" then old = m; return {} end
      return { m }
    end
    a:receive("WHISPER", B, { v = 1, t = "SYN", tid = tid, have = 0 }); sim:run(0); ok(old)
    sim.bus.filter = nil
    ok(a:act{k="mark", c=1}); sim:run(1)
    local q = b.session.seq; eq(old.q, q - 1)
    b:receive("WHISPER", A, old)
    eq(b.session.seq, q); eq(b.session.state.board[1], 1); eq(b.session.state.turn, 2)
    -- an equal or newer one is still taken
    b.session.state.board[9] = 2
    a:receive("WHISPER", B, { v = 1, t = "SYN", tid = tid, have = 0 }); sim:run(1)
    eq(b.session.seq, q); eq(b.session.state.board, a.session.state.board)
  end)
end)

describe("graceful handoff", function()
  it("host stands mid-turn: next player becomes host, timer restarts, no move lost or doubled", function()
    local sim, a, b, c, d, tid = fake()
    incs(sim, a, b, c); sim:run(20)
    local m0 = #sim.sent
    a:stand(); sim:run(2)
    eq(a.session, nil)
    eq(b.session.role, "host"); eq(b.session.epoch, 2); eq(d.session.host, B); eq(d.lobby:get(tid).host, B)
    eq(c.session.state.n, 3); eq(c.session.status, "live") -- 2 of 3 still seated >= minSeats: no abort
    eq(c.session.host, B); eq(c.session.epoch, 2); eq(d.session.epoch, 2); eq(d.session.role, "watcher")
    eq(b.session.seats, { false, B, C }); eq(c.session.seats, { false, B, C }); eq(d.session.seats, { false, B, C })
    eq(c.session.seq, b.session.seq); eq(d.session.seq, b.session.seq); eq(b.session.watchers, 1)
    eq(a.lobby:get(tid).host, B); eq(a.lobby:get(tid).epoch, 2)
    local hnd = sentBy(sim, A, m0, ofType("HND"))
    eq(#hnd, 3); eq(hnd[1].msg, { v = 1, t = "HND", tid = tid, e = 2, to = B }); eq(hnd[1].channel, "WHISPER")
    eq(#sentBy(sim, A, m0, ofType("END")), 0)
    local snp = sentBy(sim, B, m0, function(s) return s.msg.t == "SNP" and s.target == C end)
    eq(#snp, 1); eq(snp[1].msg.e, 2); eq(snp[1].msg.left, 45)
    eq(c.session.deadline, b.session.deadline)
    sim:run(46); eq(c.session.state.n, 4) -- one auto move after a full fresh turn
    eq(b.session.state.n, 4); eq(d.session.state.n, 4)
    ok(b:act{k="inc"}); sim:run(1); eq(d.session.state.n, 5); eq(c.session.state.n, 5)
  end)

  it("ttt: the host standing aborts the match but the table lives on under the guest", function()
    local sim, a, b, c, tid = ttt()
    ok(a:act{k="mark", c=1}); sim:run(1)
    a:stand(); sim:run(3)
    eq(b.session.role, "host"); eq(b.session.status, "aborted"); eq(b.session.seats, { false, B })
    eq(c.session.host, B); eq(c.session.status, "aborted"); eq(c.session.seq, b.session.seq)
    eq(c.lobby:get(tid).host, B); eq(c.lobby:get(tid).state, "open"); eq(b.session.deadline, nil)
    a:sit(tid, 1); sim:run(1)
    eq(a.session.role, "player"); eq(a.session.host, B); eq(b.session.status, "live"); eq(c.session.status, "live")
  end)

  it("a host's stop() sends no HND: the next player claims after the silence, as after a kill", function()
    local sim, a, b, c, d = fake()
    local m0 = #sim.sent
    a:stop(); sim:run(2)
    eq(#sentBy(sim, A, m0, function(s) return s.msg.t ~= "BYE" end), 0)
    eq(b.session.role, "player"); eq(b.session.host, A)
    sim:run(75)
    eq(b.session.role, "host"); eq(b.session.epoch, 2); eq(b.session.seats, { A, B, C })
    eq(c.session.host, B); eq(c.session.status, "live")
    sim:run(20); eq(d.session.host, B)
  end)

  it("survives duplicated whispers", function()
    local sim, a, b, c, d = fake()
    incs(sim, a, b, c)
    sim.bus.filter = function(_, _, channel, m) return channel == "WHISPER" and { m, m } or { m } end
    a:stand(); sim:run(2)
    eq(b.session.role, "host"); eq(b.session.epoch, 2); eq(c.session.host, B); eq(d.session.host, B)
    eq(b.session.seats, { false, B, C }); eq(c.session.seq, b.session.seq); eq(d.session.seq, b.session.seq)
    eq(b.session.watchers, 1)
    sim:run(46); eq(c.session.state.n, 4); eq(d.session.state.n, 4); eq(c.session.seq, b.session.seq)
  end)

  it("a member that gets the successor's SNP before the HND accepts it, then ignores the HND", function()
    local sim, a, b, c = fake()
    incs(sim, a, b, c)
    local held = {}
    sim.bus.filter = function(from, to, _, m)
      if from == A and to == C and (m.t == "HND" or m.t == "EV") then held[#held + 1] = m; return {} end
      return { m }
    end
    a:stand(); sim:run(2); sim.bus.filter = nil
    eq(c.session.host, B); eq(c.session.epoch, 2); eq(c.session.seats, { false, B, C })
    local q = c.session.seq
    eq(#held, 2)
    for _, m in ipairs(held) do c:receive("WHISPER", A, m) end
    sim:run(1)
    eq(c.session.host, B); eq(c.session.epoch, 2); eq(c.session.seq, q); eq(c.session.seats, { false, B, C })
    eq(b.session.role, "host")
  end)

  it("a lost SNP after the HND is healed by the next tick, and no EV is applied meanwhile", function()
    local sim, a, b, c = fake()
    incs(sim, a, b, c)
    local dropped = 0
    sim.bus.filter = function(from, to, _, m)
      if from == B and to == C and m.t == "SNP" then dropped = dropped + 1; return {} end
      return { m }
    end
    a:stand(); sim:run(2)
    ok(dropped >= 1); eq(c.session.host, B); eq(c.session.epoch, 2); eq(c.session.stale, true)
    eq(c.session.seats, { false, B, C }) -- the old host's stand event did arrive
    sim:run(46); eq(b.session.state.n, 4); eq(c.session.state.n, 3) -- B's EV is not applied on old state
    sim.bus.filter = nil; sim:run(30)
    eq(c.session.stale, nil); eq(c.session.seq, b.session.seq); eq(c.session.state, b.session.state)
  end)

  it("a successor that missed the stand event removes the old host itself", function()
    local sim, a, b, c = fake()
    incs(sim, a, b, c)
    sim.bus.filter = function(from, to, _, m)
      if from == A and to == B and m.t == "EV" then return {} end
      return { m }
    end
    a:stand(); sim:run(2); sim.bus.filter = nil
    eq(b.session.role, "host"); eq(b.session.seats, { false, B, C }); eq(c.session.seats, { false, B, C })
    eq(c.session.seq, b.session.seq); eq(c.session.state.n, 3)
  end)

  it("a successor that never answers is replaced by the next candidate 75 s later", function()
    local sim, a, b, c, d, tid = fake()
    incs(sim, a, b, c)
    sim:offline(B); a:stand(); sim:run(2)
    eq(c.session.host, B); eq(c.session.epoch, 2); eq(c.session.stale, true); eq(b.session.role, "player")
    sim:run(72); eq(c.session.role, "player"); eq(c.session.hostSilent, false)
    sim:run(2); eq(c.session.role, "host"); eq(c.session.epoch, 3); eq(c.session.state.n, 3)
    eq(c.session.seats, { false, B, C }); eq(c.session.status, "live")
    eq(d.session.host, C); eq(d.session.epoch, 3); eq(d.session.seq, c.session.seq); eq(d.lobby:get(tid).host, C)
    sim:online(B); sim:run(31) -- c's tick (epoch 3) reaches b, whatever b did on its own meanwhile
    eq(b.session.host, C); eq(b.session.epoch, 3); eq(b.session.role, "player"); eq(b.session.seq, c.session.seq)
  end)

  it("HND from anyone but my host is ignored", function()
    local sim, _, b, c, d, tid = fake()
    for _, from in ipairs({ C, D }) do
      b:receive("WHISPER", from, { v = 1, t = "HND", tid = tid, e = 5, to = from })
      b:receive("WHISPER", from, { v = 1, t = "HND", tid = tid, e = 5, to = B })
    end
    b:receive("GUILD", A, { v = 1, t = "HND", tid = tid, e = 5, to = B }) -- not a whisper
    sim:run(1)
    eq(b.session.host, A); eq(b.session.epoch, 1); eq(b.session.role, "player"); eq(c.session.host, A)
    -- a watcher named as successor does not take the table
    d:receive("WHISPER", A, { v = 1, t = "HND", tid = tid, e = 2, to = D }); sim:run(1)
    eq(d.session.role, "watcher"); eq(d.session.epoch, 1)
  end)
end)

describe("host silence and convergence", function()
  it("a higher epoch from a non-seated sender is ignored", function()
    local sim, _, b, _, _, tid = fake()
    local q = b.session.seq
    local rec = { tid = tid, g = "fake", h = D, e = 9, ac = "guild", tn = 45, st = "live", s = { A, B, C }, w = 1 }
    b:receive("WHISPER", D, { v = 1, t = "SNP", tid = tid, e = 9, q = 99, tbl = rec, st = { n = 50, turn = 2 } })
    local t = { v = 1, t = "TBL" }; for k, v in pairs(rec) do t[k] = v end
    b:receive("GUILD", D, t)
    b:receive("WHISPER", D, { v = 1, t = "TCK", tid = tid, e = 9, q = 99 })
    b:receive("WHISPER", D, { v = 1, t = "HND", tid = tid, e = 9, to = D })
    sim:run(1)
    eq(b.session.host, A); eq(b.session.epoch, 1); eq(b.session.seq, q); eq(b.session.state.n, 0)
    eq(b.session.stale, nil)
  end)

  it("a higher epoch is never adopted from an EV, even from a seated sender or my host", function()
    local sim, _, b, _, _, tid = fake()
    local q = b.session.seq
    b:receive("WHISPER", C, { v = 1, t = "EV", tid = tid, e = 2, q = q + 1, seat = 1, a = { k = "inc" } })
    b:receive("WHISPER", A, { v = 1, t = "EV", tid = tid, e = 2, q = q + 1, seat = 1, a = { k = "inc" } })
    sim:run(1)
    eq(b.session.host, A); eq(b.session.epoch, 1); eq(b.session.seq, q); eq(b.session.state.n, 0)
  end)

  it("host vanishes mid-turn: guest claims after 75 s and play continues", function()
    local sim, a, b, c, tid = ttt()
    ok(a:act{k="mark", c=1}); sim:run(0)
    local m0 = #sim.sent
    sim:offline(A); sim:run(74); eq(b.session.role, "player"); eq(b.session.hostSilent, false)
    sim:run(2); eq(b.session.role, "host"); eq(b.session.hostSilent, false)
    eq(b.session.epoch, 2); eq(c.session.host, B); eq(c.session.epoch, 2); eq(c.lobby:get(tid).host, B)
    eq(b.session.seats, { A, B }); eq(b.session.deadline, sim:now() - 1 + 45)
    eq(#sentBy(sim, B, m0, function(s) return s.msg.t == "TBL" and s.channel == "GUILD" and s.msg.e == 2 end), 1)
    ok(b:act{k="mark", c=9}); sim:run(1); eq(c.session.state.board[9], 2); eq(c.session.state.board[1], 1)
    eq(c.session.seq, b.session.seq); eq(b.session.watchers, 1)
  end)

  it("members show hostSilent from 75 s until somebody claims; later ranks wait 15 s each", function()
    local sim, _, _, c, d = fake()
    sim:run(27)
    local heard = 0; for _, m in ipairs(sim.sent) do if m.from == A then heard = m.at end end
    sim:offline(A); sim:offline(B)
    sim:run(heard + 74 - sim:now()); eq(c.session.hostSilent, false); eq(d.session.hostSilent, false)
    sim:run(1); eq(c.session.hostSilent, true); eq(d.session.hostSilent, true); eq(c.session.role, "player")
    sim:run(14); eq(c.session.role, "player") -- rank 1: not before 90 s
    sim:run(1); eq(c.session.role, "host"); eq(c.session.epoch, 2); eq(c.session.hostSilent, false)
    eq(d.session.host, C); eq(d.session.hostSilent, false); eq(d.session.epoch, 2)
  end)

  it("the old host keeps its seat and is stood up 180 s after its last message", function()
    local sim, a, b, c = ttt()
    ok(a:act{k="mark", c=1}); sim:run(0)
    local last = 0; for _, s in ipairs(sim.sent) do if s.from == A then last = s.at end end
    sim:offline(A); sim:run(179 - (sim:now() - last))
    eq(b.session.role, "host"); eq(b.session.seats, { A, B }); eq(b.session.status, "live")
    sim:run(2)
    eq(b.session.seats, { false, B }); eq(b.session.status, "aborted"); eq(c.session.seats, { false, B })
  end)

  it("split brain converges", function()
    local sim, a, b, c, d = fake()
    incs(sim, a)
    sim.bus.filter = cut(B, C)
    sim:offline(A); sim:run(91)
    eq(b.session.role, "host"); eq(c.session.role, "host"); eq(b.session.epoch, 2); eq(c.session.epoch, 2)
    eq(d.session.host, B) -- the watcher keeps the claimant in the lower seat
    sim.bus.filter = nil; sim:run(35)
    eq(d.session.host, B); eq(d.session.seq, b.session.seq)
    eq(b.session.host, B); eq(c.session.host, B); eq(b.session.role, "host"); eq(c.session.role, "player")
    eq(c.session.seq, b.session.seq); eq(c.session.state.n, b.session.state.n); eq(c.session.epoch, 2)
    eq(c.lobby:get(b.session.tid).host, B)
    sim:run(100); eq(c.session.host, B); eq(c.session.seq, b.session.seq); eq(c.session.state, b.session.state)
  end)

  it("with only whispers cut the second candidate follows the TBL and syncs once they pass", function()
    local sim, a, b, c = fake()
    incs(sim, a)
    sim.bus.filter = whispersCut(B, C)
    sim:offline(A); sim:run(91)
    eq(b.session.role, "host"); eq(c.session.role, "player"); eq(c.session.host, B); eq(c.session.stale, true)
    local n = c.session.state.n
    sim:run(20); eq(c.session.state.n, n) -- nothing applied while stale
    sim.bus.filter = nil; sim:run(35)
    eq(c.session.stale, nil); eq(c.session.seq, b.session.seq); eq(c.session.state, b.session.state)
  end)

  it("a claimant whose state is behind rolls the others back to its own", function()
    local sim, a, b, c = fake()
    -- c gets the host's last event, b does not
    sim.bus.filter = function(from, to, _, m)
      if from == A and to == B and m.t == "EV" then return {} end
      return { m }
    end
    incs(sim, a); sim.bus.filter = nil
    eq(c.session.state.n, 1); eq(b.session.state.n, 0)
    sim:offline(A); sim:run(76)
    eq(b.session.role, "host"); eq(c.session.host, B); eq(c.session.state.n, 0); eq(c.session.seq, b.session.seq)
  end)

  it("returning old host demotes", function()
    local sim, a, b, c = fake()
    incs(sim, a)
    sim:offline(A); sim:run(76); eq(b.session.role, "host")
    sim:online(A); sim:run(35)
    eq(a.session.role, "player"); eq(a.session.host, B); eq(a.session.epoch, 2)
    eq(a.session.seq, b.session.seq); eq(a.session.state, b.session.state); eq(a.session.mySeat, 1)
    eq(a.lobby:get(b.session.tid).host, B); eq(c.session.host, B)
    local q = b.session.seq
    sim:run(200); eq(b.session.seats, { A, B, C }) -- heard again: stays seated
    ok(b.session.seq > q); eq(a.session.seq, b.session.seq)
  end)

  it("a host that reloads loses the table to the guest and gets its seat back from him", function()
    local sim, a, b, c, tid = ttt()
    ok(a:act{k="mark", c=1}); sim:run(0); sim:run(1)
    local last = 0; for _, s in ipairs(sim.sent) do if s.from == A then last = s.at end end
    sim:run(10); local a2 = sim:relog(A); sim:run(1)
    eq(a2.session, nil); eq(b.session.host, A) -- its HI (at = nil) does not count as the host being heard
    sim:run(last + 74 - sim:now()); eq(b.session.role, "player")
    sim:run(1); eq(b.session.role, "host"); eq(b.session.epoch, 2)
    eq(a2.session.role, "player"); eq(a2.session.mySeat, 1); eq(a2.session.host, B)
    eq(a2.session.state.board, b.session.state.board); eq(a2.session.state.board[1], 1)
    eq(a2.lobby:get(tid).host, B); eq(c.session.host, B)
    ok(b:act{k="mark", c=5}); sim:run(1); ok(a2:act{k="mark", c=2}); sim:run(1)
    eq(c.session.state.board, {1,1,0,0,2,0,0,0,0}); eq(b.session.status, "live")
  end)

  it("a member that lost its seat while away follows the new host as a watcher", function()
    local sim, a, b, c, d, tid = fake()
    incs(sim, a, b, c); a:stand(); sim:run(2)
    -- b (host now) stood c up; c never heard of it and still follows a at epoch 1
    c:receive("WHISPER", B, { v = 1, t = "SNP", tid = tid, e = 1, q = 3, st = { n = 3, turn = 1 },
      tbl = { tid = tid, g = "fake", h = B, e = 1, ac = "guild", tn = 45, st = "live", s = { A, B, C }, w = 1 } })
    eq(c.session.epoch, 2) -- (a lower epoch is not adopted)
    b.session:onStand(C); sim:run(0); eq(b.session.seats, { false, B, false })
    c.session.host, c.session.epoch, c.session.seats = A, 1, { A, B, C }
    sim:run(60) -- b's TBL heartbeat
    eq(c.session.host, B); eq(c.session.role, "watcher"); eq(c.session.mySeat, nil); eq(c.session.epoch, 2)
    eq(c.session.seats, { false, B, false }); eq(c.session.seq, b.session.seq); eq(b.session.watchers, 2)
    ok(d.session)
  end)

  it("lower epochs are ignored after a host change", function()
    local sim, a, b, c, _, tid = fake()
    incs(sim, a, b, c)
    a:stand(); sim:run(2)
    local q, n = c.session.seq, c.session.state.n
    c:receive("WHISPER", A, { v = 1, t = "TCK", tid = tid, e = 1, q = 99 })
    c:receive("WHISPER", A, { v = 1, t = "EV", tid = tid, e = 1, q = q + 1, seat = 1, a = { k = "inc" } })
    c:receive("WHISPER", B, { v = 1, t = "EV", tid = tid, e = 1, q = q + 1, seat = 1, a = { k = "inc" } })
    c:receive("GUILD", A, { v = 1, t = "TBL", tid = tid, g = "fake", h = A, e = 1, ac = "guild", tn = 45, st = "live", s = { A, B, C }, w = 1 })
    sim:run(1)
    eq(c.session.host, B); eq(c.session.epoch, 2); eq(c.session.seq, q); eq(c.session.state.n, n)
    eq(c.lobby:get(tid).host, B); eq(b.session.role, "host")
  end)

  it("watchers never become host: with no candidate left their session ends after 150 s", function()
    local sim = Sim.new()
    local a = sim:add(A, { cls = "MAGE" }); local c = sim:add(C, { cls = "ROGUE" }); sim:run(1)
    local tid = a:openTable{game="ttt", access="guild", turn=45}; sim:run(3)
    c:watch(tid); sim:run(1)
    sim:offline(A); sim:run(149); eq(c.session.role, "watcher"); eq(c.session.hostSilent, true)
    sim:run(3); eq(c.session, nil); eq(c.lobby:get(tid), nil)
  end)

  it("candidates skip the old host and keep seat order", function()
    eq(S.candidates({"a","b",false,"d"}, "a"), {"b","d"}); eq(S.wins({"a","b","c"}, "c", "b"), "b")
    eq(S.wins({"a","b","c"}, "b", "c"), "b"); eq(S.candidates({false,"b"}, "b"), {})
    eq(S.wins({"a",false,"c"}, "x", "c"), "c")
  end)
end)
