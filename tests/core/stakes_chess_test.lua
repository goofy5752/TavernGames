-- Chess at a staked table (core/StakesChess.lua): the snapshot check, my own
-- move log across a /reload, and a draw that owes nothing through the books.
local Sim = require("sim")
local Play = require("play")
local Chess = require("chess")
local ns = Sim.ns
local C, Util = ns.Const, ns.Util
local E, SC, Stakes = ns.Engines.chess, ns.StakesChess, ns.Stakes
local sq = Chess.sq

local H, G = Play.NAMES[1], Play.NAMES[2] -- host (seat 1, black in game 1), guest (seat 2, white)
local SK = 50000

-- A chess table of `minutes` (nil: 10) at stake sk, the guest seated: the
-- game runs, the guest (white) on turn. before(sim) runs before the table opens.
local function open(minutes, sk, before)
  local sim, cl = Play.guild(2)
  if before then before(sim) end
  local host, guest = cl[H], cl[G]
  local tid = assert(host:openTable{ game = "chess", access = "guild", turn = 45, opt = { clock = minutes or 10 }, stake = sk })
  sim:run(3)
  guest:sit(tid, 2, sk); sim:run(1)
  assert(host.session.status == "live", "the game is not live")
  return sim, host, guest, tid
end

local function move(w)
  local p = w:sub(5, 5)
  return { k = "move", f = sq(w:sub(1, 2)), t = sq(w:sub(3, 4)), p = p ~= "" and p or nil }
end

-- Each word by the client of the seat on turn, two seconds apart.
local function plays(sim, host, guest, words)
  for w in words:gmatch("%S+") do
    sim:run(2)
    local c = host.session.state.turn == host.session.mySeat and host or guest
    ok(c:act(move(w)), "the move " .. w .. " was refused")
    sim:run(0)
  end
end

-- Wraps name's env.send: f(msg) -> msg (changed or not), or nil to drop it.
local function tamper(sim, name, f)
  local env = sim.envs[name]
  local send = env.send
  env.send = function(channel, target, msg, done)
    local m = f(Util.copy(msg))
    if m then return send(channel, target, m, done) end
  end
end

-- The host answers the guest's next request with `st` (a state it makes from its own).
local function answers(sim, host, guest, make)
  local once = false
  tamper(sim, H, function(m)
    if m.t == "SNP" and not once then once = true; m.st = make(Util.copy(host.session.state)) end
    return m
  end)
  guest.session:requestSync(); sim:run(0)
  ok(once, "no snapshot went")
end

local function gidOf(host) return host.session.tid .. "/" .. host.session.seq end

local function at(list, gid)
  local out = {}
  for _, e in ipairs(list) do if e.gid == gid then out[#out + 1] = e end end
  return out
end

-- A fresh game of the guest as white, `words` played with dt 30.
local function game(words, first)
  return Chess.play(E.new{ first = first or 2, opt = { clock = 10 } }, words, 30)
end

describe("chess at a staked table", function()
  it("leads: my game carried on", function()
    local a = game("e2e4 e7e5 g1f3 b8c6")
    local b = game("e2e4 e7e5 g1f3 b8c6 f1c4 g8f6 d2d3 f8c5")
    eq(SC.leads(a, b), true)
    eq(SC.leads(a, a), true)
    eq(Stakes.leadsTo(a, b), true)
    local x = Util.copy(b); x.moves[6].dt = 31
    eq(SC.leads(a, x), false)
    x = Util.copy(b); x.moves[2].dt = 31 -- inside a's moves
    eq(SC.leads(a, x), false)
    x = Util.copy(b); x.clock[1] = x.clock[1] - 600
    eq(SC.leads(a, x), false)
    x = Util.copy(b); x.board[sq("a2")], x.board[sq("a3")] = 0, 1
    eq(SC.leads(a, x), false)
    eq(SC.leads(a, game("e2e4 e7e5 g1f3 b8c6 f1c4 g8f6 d2d3 f8c5", 1)), false)
    x = Util.copy(b); ok(E.apply(x, x.turn, { k = "resign" }))
    eq(SC.leads(a, x), true)
    x = Util.copy(b); x.phase, x.turn, x.result = "over", nil, { winner = 1, reason = "mate" }
    eq(SC.leads(a, x), false)
    eq(SC.leads(b, a), false) -- a is behind b
    x = Util.copy(a); ok(E.apply(x, 1, { k = "resign" }))
    eq(SC.leads(x, b), false) -- a game a shows over
    eq(Stakes.leadsTo(ns.Engines.ttt.new{}, b), false)
    eq(Stakes.leadsTo(b, ns.Engines.ttt.new{}), false)
  end)

  it("a state no play of its moves reaches is no chess state", function()
    local b = game("e2e4 e7e5 g1f3")
    eq(SC.valid(b), true)
    local bad = {
      function(x) x.board[1] = "R" end, function(x) x.board[65] = 0 end, function(x) x.side = 0 end,
      function(x) x.castle = "KQkqX" end, function(x) x.ep = 20 end, function(x) x.clock = { 6000, -1 } end,
      function(x) x.clock = nil end, function(x) x.base = 3000 end, function(x) x.moves[2] = 5 end,
      function(x) x.moves[2].p = "q" end, function(x) x.moves[3].san = "Nc3" end, function(x) x.wait = { 0, 4 } end,
      function(x) x.wait = { 0 } end, function(x) x.offer = 3 end, function(x) x.claimed = 9 end,
      function(x) x.result = 5 end, function(x) x.phase = "over" end, function(x) x.moves = "e2e4" end,
      function(x) x.white = 3 end, function(x) x.extra = true end, function(x) x.seen = {} end,
    }
    for i, f in ipairs(bad) do
      local x = Util.copy(b); f(x)
      ok(not SC.valid(x), "bad state " .. i .. " passed")
    end
    local x = Util.copy(b); x.offer, x.claimed, x.wait = 1, 3, { 3, 0 }
    eq(SC.valid(x), true)
    eq(SC.valid(Chess.play(E.new{ first = 1, opt = { clock = 0 } }, "e2e4", nil)), true)
  end)

  it("a state that crossed the wire is still a chess state", function()
    Loader.lib("Libs/LibStub/LibStub.lua")
    Loader.lib("Libs/AceSerializer-3.0/AceSerializer-3.0.lua")
    Loader.lib("Libs/LibDeflate/LibDeflate.lua")
    local wire = ns.Wire.new(LibStub("AceSerializer-3.0"), LibStub("LibDeflate"))
    local x = E.new{ first = 2, opt = { clock = 30 } }
    local half
    for ply = 0, 119 do
      if x.phase ~= "play" then break end
      local list = E.legal(x, x.turn)
      ok(E.apply(x, x.turn, list[1 + (ply * 7) % #list], 7 + ply % 13))
      if ply == 60 then half = Util.copy(x) end
    end
    ok(#x.taken[1] + #x.taken[2] > 0, "no capture in the game")
    if x.phase == "play" then x.claimed = #x.moves - 1 end
    local back = wire:unpack(wire:pack({ v = 1, t = "SNP", st = x })).st
    eq(SC.valid(back), true)
    eq(SC.leads(half, back), true)
  end)

  it("a forged state in a snapshot is never adopted, and is forged", function()
    local sim, host, guest = open(10, SK)
    plays(sim, host, guest, "e2e4 e7e5")
    local before = Util.copy(guest.session.state)
    answers(sim, host, guest, function(st) st.moves = 7; return st end)
    eq(guest.session.state, before)
    eq(guest.session.stakeFoul, "forged")
    ok(guest:act(move("g1f3")))
    sim:run(0)
    eq(#host.session.state.moves, 3)
  end)

  it("a snapshot I asked for after a gap is unseen, an identical one is nothing", function()
    local sim, host, guest = open(10, SK)
    plays(sim, host, guest, "e2e4 e7e5")
    guest.session:requestSync(); sim:run(0)
    eq(#guest.session.state.moves, 2)
    eq(guest.session.stakeFoul, nil)
    local dropped = false
    local sim2, host2, guest2 = open(10, SK, function(s)
      tamper(s, H, function(m)
        if m.t == "EV" and type(m.a) == "table" and m.a.k == "move" and m.seat == 1 and not dropped then dropped = true; return nil end
        return m
      end)
    end)
    plays(sim2, host2, guest2, "e2e4")
    sim2:run(2); ok(host2:act(move("e7e5"))); sim2:run(0)
    eq(#guest2.session.state.moves, 1)
    guest2.session:requestSync(); sim2:run(0)
    eq(#guest2.session.state.moves, 2)
    eq(guest2.session.stakeFoul, "unseen")
    plays(sim2, host2, guest2, "g1f3 b8c6")
    eq(guest2.session.stakeFoul, "unseen")
  end)

  it("a pushed snapshot with a move in my name is forged", function()
    local sim, host, guest = open(10, SK)
    plays(sim, host, guest, "e2e4 e7e5")
    ok(E.apply(host.session.state, 2, move("g1f3"), 20)) -- the host plays my move itself
    host.session:snapshotTo(G); sim:run(0)
    eq(#guest.session.state.moves, 3)
    eq(guest.session.stakeFoul, "forged")
    -- The same move in an answer to my own request: the snapshot rule says
    -- "unseen", my log says forged.
    local sim2, host2, guest2 = open(10, SK)
    plays(sim2, host2, guest2, "e2e4 e7e5")
    answers(sim2, host2, guest2, function(st) ok(E.apply(st, 2, move("g1f3"), 20)); return st end)
    eq(#guest2.session.state.moves, 3)
    eq(guest2.session.stakeFoul, "forged")
  end)

  it("a snapshot with my own move I sent is no forgery, and its dt is counted", function()
    local held
    local sim, host, guest = open(10, SK, function(s)
      tamper(s, H, function(m)
        if m.t == "EV" and type(m.a) == "table" and m.a.k == "move" and m.seat == 2 and not held then held = m; return nil end
        return m
      end)
    end)
    sim:run(5)
    ok(guest:act(move("e2e4"))); sim:run(0)
    ok(held, "the echo was held")
    eq(#guest.session.state.moves, 0)
    eq(guest.session.chessLog.list, { "e2e4" })
    guest.session:requestSync(); sim:run(0)
    eq(#guest.session.state.moves, 1)
    eq(guest.session.stakeFoul, "unseen")
    eq(guest.session.clockOwn.n, 1)
    ok(guest.session.clockOwn.sum <= ns.Clock.tolerance(1), "sum " .. guest.session.clockOwn.sum)
    eq(guest.session.chessLog.at[1], nil) -- counted once
  end)

  it("a snapshot that brings my own move with a taken dt is forged", function()
    local held
    local sim, host, guest = open(10, SK, function(s)
      tamper(s, H, function(m)
        if m.t == "EV" and type(m.a) == "table" and m.a.k == "move" and m.seat == 2 and not held then held = m; return nil end
        return m
      end)
    end)
    sim:run(5)
    ok(guest:act(move("e2e4"))); sim:run(0)
    answers(sim, host, guest, function(st)
      local x = E.new{ first = 2, opt = { clock = 10 } }
      ok(E.apply(x, 2, move("e2e4"), st.moves[1].dt + 200)) -- 20 s more of my time
      return x
    end)
    eq(#guest.session.state.moves, 1)
    eq(guest.session.stakeFoul, "forged")
  end)

  it("a snapshot that trims my clock is another game", function()
    local sim, host, guest = open(10, SK)
    plays(sim, host, guest, "e2e4 e7e5")
    local clock = guest.session.state.clock[2]
    host.session.state.clock[2] = host.session.state.clock[2] - 600
    host.session:snapshotTo(G); sim:run(0)
    eq(guest.session.stakeFoul, "forged")
    eq(guest.session.state.clock[2], clock)
  end)

  it("a snapshot that says I resigned is forged; one that says I agreed a draw is forged", function()
    local sim, host, guest = open(10, SK)
    plays(sim, host, guest, "e2e4 e7e5")
    answers(sim, host, guest, function(st) ok(E.apply(st, 2, { k = "resign" })); return st end)
    eq(guest.session.state.result.reason, "resign")
    eq(guest.session.stakeFoul, "forged")
    local sim2, host2, guest2 = open(10, SK)
    plays(sim2, host2, guest2, "e2e4 e7e5")
    answers(sim2, host2, guest2, function(st) st.offer = 1; ok(E.apply(st, 2, { k = "accept" })); return st end)
    eq(guest2.session.state.result.reason, "agreed")
    eq(guest2.session.stakeFoul, "forged")
    -- A standing offer in my name, and a claim of mine at this ply, that I never made.
    local sim3, host3, guest3 = open(10, SK)
    plays(sim3, host3, guest3, "e2e4 e7e5")
    answers(sim3, host3, guest3, function(st) st.offer = 2; return st end)
    eq(guest3.session.stakeFoul, "forged")
    local sim4, host4, guest4 = open(10, SK)
    plays(sim4, host4, guest4, "e2e4")
    answers(sim4, host4, guest4, function(st) st.claimed = 1; return st end)
    eq(guest4.session.state.claimed, 1)
    eq(guest4.session.stakeFoul, "forged")
  end)

  it("my own offer and resign in a snapshot are no forgery", function()
    local sim, host, guest = open(10, SK)
    plays(sim, host, guest, "e2e4 e7e5")
    ok(guest:act{ k = "offer" }); sim:run(0)
    plays(sim, host, guest, "g1f3")
    guest.session:requestSync(); sim:run(0)
    eq(guest.session.state.offer, 2)
    eq(guest.session.stakeFoul, nil)
    local sim2, host2, guest2 = open(10, SK, function(s)
      tamper(s, H, function(m)
        if m.t == "EV" and type(m.a) == "table" and m.a.k == "resign" then return nil end
        return m
      end)
    end)
    plays(sim2, host2, guest2, "e2e4 e7e5")
    ok(guest2:act{ k = "resign" }); sim2:run(0)
    eq(guest2.session.state.phase, "play")
    guest2.session:requestSync(); sim2:run(0)
    eq(guest2.session.state.result.reason, "resign")
    ok(guest2.session.stakeFoul ~= "forged", "my own resign charged")
    -- My accept of the host's offer, its event lost: the snapshot's agreed draw is mine.
    local sim3, host3, guest3 = open(10, SK, function(s)
      tamper(s, H, function(m)
        if m.t == "EV" and type(m.a) == "table" and m.a.k == "accept" then return nil end
        return m
      end)
    end)
    plays(sim3, host3, guest3, "e2e4")
    ok(host3:act{ k = "offer" }); sim3:run(0)
    plays(sim3, host3, guest3, "e7e5") -- the offer stands through the host's own move
    ok(guest3:act{ k = "accept" }); sim3:run(0)
    eq(guest3.session.state.phase, "play")
    guest3.session:requestSync(); sim3:run(0)
    eq(guest3.session.state.result.reason, "agreed")
    ok(guest3.session.stakeFoul ~= "forged", "my own accept charged")
  end)

  it("a flag after a relog on my own turn is unseen, never forged", function()
    local sim, host, guest = open(5, SK)
    plays(sim, host, guest, "e2e4 e7e5")
    sim:run(100)
    guest:stop(); sim:run(0)
    local again = sim:relog(G); sim:run(1)
    eq(again.session.clockSeen, false) -- the running turn is a gift: measured from the snapshot
    for _ = 1, 400 do
      if again.session.state.phase == "over" then break end
      sim:run(1)
    end
    eq(again.session.state.result.reason, "flag")
    eq(again.session.stakeFoul, "unseen")
  end)

  it("a flag in a snapshot is judged by my clock", function()
    local sim, host, guest = open(5, SK)
    plays(sim, host, guest, "e2e4 e7e5")
    answers(sim, host, guest, function(st) ok(E.apply(st, 2, { k = "flag" })); return st end)
    eq(guest.session.state.result.reason, "flag")
    eq(guest.session.stakeFoul, "forged")
    local dropped
    local sim2, host2, guest2 = open(5, SK, function(s)
      tamper(s, H, function(m)
        if m.t == "EV" and type(m.a) == "table" and m.a.k == "flag" then dropped = true; return nil end
        return m
      end)
    end)
    sim2:run(300 + C.AUTO_GRACE + 1)
    ok(dropped, "the flag went")
    eq(guest2.session.state.phase, "play")
    guest2.session:requestSync(); sim2:run(0)
    eq(guest2.session.state.result.reason, "flag")
    ok(guest2.session.stakeFoul ~= "forged", "an honest flag charged")
  end)

  it("a relog keeps my log and makes no false charge", function()
    local sim, host, guest = open(10, SK)
    plays(sim, host, guest, "e2e4 e7e5 g1f3 b8c6 f1c4 g8f6")
    guest:stop(); sim:run(0)
    local again = sim:relog(G); sim:run(1)
    local s = again.session
    ok(s and s.state, "the snapshot came")
    eq(#s.state.moves, 6)
    ok(s.stakeFoul == nil or s.stakeFoul == "unseen", "foul " .. tostring(s.stakeFoul))
    eq(s.chessLog.list, { "e2e4", "g1f3", "f1c4" })
    plays(sim, host, again, "d2d3 d7d6 c2c3")
    s:requestSync(); sim:run(0) -- a later snapshot of my game: my log still holds it
    ok(s.stakeFoul == nil or s.stakeFoul == "unseen", "foul " .. tostring(s.stakeFoul))
    eq(s.chessLog.list, { "e2e4", "g1f3", "f1c4", "d2d3", "c2c3" })
    sim:run(2); ok(host:act{ k = "resign" }); sim:run(0)
    local gid = gidOf(host)
    sim:run(C.STAKE_OWE_WAIT + 5)
    local d = Play.debt(again, gid, H, G)
    ok(d, "no debt")
    eq(d and d.status, "confirmed")
    eq(d and d.c, SK)
  end)

  it("after a crash the shorter log is a question, not a charge", function()
    local sim, host, guest = open(10, SK)
    plays(sim, host, guest, "e2e4 e7e5")
    guest:stop(); sim:run(0) -- WoW wrote my saved variables here
    local again = sim:relog(G); sim:run(1)
    plays(sim, host, again, "g1f3 b8c6 f1c4 g8f6")
    eq(again.session.chessLog.list, { "e2e4", "g1f3", "f1c4" })
    local last = sim:crash(G); sim:run(1)
    local s = last.session
    ok(s and s.state, "the snapshot came")
    eq(#s.state.moves, 6)
    eq(s.stakeFoul, "unseen")
    eq(s.chessLog.list, { "e2e4", "g1f3", "f1c4" }) -- what it shows of mine is taken in
    plays(sim, host, last, "d2d3 d7d6")
    s:requestSync(); sim:run(0)
    eq(s.stakeFoul, "unseen")
  end)

  it("a staked win is owed", function()
    local sim, host, guest = open(10, SK)
    plays(sim, host, guest, "e2e4 e7e5")
    sim:run(1); ok(guest:act{ k = "resign" }); sim:run(1)
    local gid = gidOf(host)
    sim:run(C.LEDGER_COALESCE + 1) -- my entries go out together
    local ds = at(Play.entries(sim, nil, "D"), gid)
    eq(#ds, 1)
    eq({ ds[1].f, ds[1].t, ds[1].c }, { G, H, SK })
    eq(#at(Play.entries(sim, H, "D"), gid), 1)
    local rs = at(Play.entries(sim, H, "R"), gid)
    eq(#rs, 1)
    eq(rs[1].w, { 1 }); eq(rs[1].l, { 2 }); eq(rs[1].sk, SK)
    eq(guest.session.stakeFoul, nil)
  end)

  it("losing on time at a staked table is owed", function()
    local sim, host, guest = open(5, SK)
    sim:run(300 + C.AUTO_GRACE + 1)
    eq(host.session.state.result.reason, "flag")
    local gid = gidOf(host)
    sim:run(C.LEDGER_COALESCE + 1)
    local ds = at(Play.entries(sim, nil, "D"), gid)
    eq(#ds, 1)
    eq({ ds[1].f, ds[1].t, ds[1].c }, { G, H, SK })
    eq(guest.session.stakeFoul, nil)
  end)

  -- The host offers on its turn, the guest accepts: an agreed draw at gid.
  local function drawn(sk)
    local sim, host, guest = open(10, sk)
    plays(sim, host, guest, "e2e4")
    sim:run(1); ok(host:act{ k = "offer" }); sim:run(1)
    ok(guest:act{ k = "accept" }); sim:run(1)
    eq(host.session.state.result.reason, "agreed")
    eq(guest.session.state.result.reason, "agreed")
    local gid = gidOf(host)
    sim:run(C.STAKE_OWE_WAIT + 5)
    return sim, host, guest, gid
  end

  it("a staked draw owes nothing", function()
    local sim, host, guest, gid = drawn(SK)
    eq(at(Play.entries(sim, nil, "D"), gid), {})
    guest.session:requestSync(); sim:run(0) -- the draw again in a snapshot: nothing new
    for _, name in ipairs({ H, G }) do
      for _, n in pairs(sim.envs[name].db.stakeSeen or {}) do
        ok(not (type(n) == "table" and type(n.pairs) == "table" and #n.pairs > 0), name .. " holds a note with pairs")
      end
    end
    eq(guest.session.stakeFoul, nil)
    local rs = at(Play.entries(sim, H, "R"), gid)
    eq(#rs, 1)
    eq(rs[1].w, {}); eq(rs[1].l, {}); eq(rs[1].sk, SK)
    for _, c in ipairs({ host, guest }) do
      local recs = at(ns.LedgerStats.games(c.ledger), gid)
      eq(#recs, 1)
      eq(recs[1].counts, { [H] = "draw", [G] = "draw" })
      eq(recs[1].state, "drawn")
    end
  end)

  it("a draw for fun is the host's word", function()
    local sim, host, guest, gid = drawn(nil)
    eq(at(Play.entries(sim, nil, "D"), gid), {})
    local recs = at(ns.LedgerStats.games(guest.ledger), gid)
    eq(#recs, 1)
    eq(recs[1].counts, { [H] = "draw", [G] = "draw" })
    eq(recs[1].state, "fun")
  end)

  it("a staked R with no winner is a claim once a debt stands at its gid", function()
    local sim, host, guest, gid = drawn(SK)
    ok(guest.ledgerNet:make("D", { gid = gid, g = "chess", f = H, t = G, c = SK, why = "lost" }))
    sim:run(C.LEDGER_COALESCE + 1)
    local recs = at(ns.LedgerStats.games(host.ledger), gid)
    eq(recs[1].counts, {})
    ok(recs[1].state ~= "drawn", "still drawn")
  end)

  it("the table goes on after a draw", function()
    local sim, host, guest = drawn(SK)
    sim:run(Stakes.gap(host.session))
    ok(host:startGame())
    sim:run(1)
    eq(host.session.state.phase, "play")
    eq(host.session.state.white, 1)
    eq(guest.session.state.white, 1)
    eq(guest.session.stakeFoul, nil)
  end)

  it("a stand after a failed claim is contested", function()
    local sim, host, guest = open(5, SK)
    plays(sim, host, guest, "e2e4")
    host.session.play = function(self, seat, a, auto) -- a host that never flags itself
      if seat == self.mySeat and a.k == "flag" then return end
      return ns.Session.play(self, seat, a, auto)
    end
    for _ = 1, 400 do
      if ns.Clock.canClaim(guest.session) then break end
      sim:run(1)
    end
    ok(ns.Clock.claim(guest)); sim:run(C.AUTO_GRACE + 1)
    eq(guest.session.stakeFoul, "forged")
    local gid = guest.session.tid .. "/" .. (guest.session.seq + 1)
    guest:stand(); sim:run(1)
    local note = sim.envs[G].db.stakeSeen[gid]
    ok(note, "no note of the forfeit")
    eq(note and note.foul, "forged")
    sim:run(C.STAKE_OWE_WAIT + 5)
    local d = Play.debt(guest, gid, G, H) or Play.debt(host, gid, G, H)
    ok(not d or d.status ~= "confirmed", "a debt was confirmed against the guest")
    eq(at(Play.entries(sim, G, "D"), gid), {})
  end)

  it("the first start and the next start are clean", function()
    local sim, host, guest = open(10, SK)
    eq(guest.session.stakeFoul, nil)
    plays(sim, host, guest, "e2e4")
    sim:run(1); ok(host:act{ k = "resign" }); sim:run(1)
    eq(guest.session.stakeFoul, nil)
    sim:run(Stakes.gap(host.session))
    ok(host:startGame()); sim:run(1)
    eq(guest.session.state.phase, "play")
    eq(#guest.session.state.moves, 0)
    eq(guest.session.stakeFoul, nil)
    plays(sim, host, guest, "e2e4 e7e5")
    eq(guest.session.chessLog.list, { "e7e5" }) -- the host is white now: my log is of this game
    eq(guest.session.stakeFoul, nil)
  end)

  it("a forgotten stake note takes my chess log with it", function()
    local sim, host, guest = open(10, SK)
    plays(sim, host, guest, "e2e4")
    ok(sim.envs[G].db.stakeChess, "no saved log")
    eq(sim.envs[G].db.stakeChess.list, { "e2e4" })
    ns.Stake.clear(guest)
    eq(sim.envs[G].db.stakeChess, nil)
  end)
end)
