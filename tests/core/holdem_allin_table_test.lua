Loader.lib("Libs/LibStub/LibStub.lua")
Loader.lib("Libs/AceSerializer-3.0/AceSerializer-3.0.lua")
Loader.lib("Libs/LibDeflate/LibDeflate.lua")
local Sim = require("sim")
local Play = require("play")
local ns = Sim.ns
local E, Fair, HE = ns.Engines.holdem, ns.Fair, ns.HoldemEval
if not ns.HoldemModel then assert(loadfile("ui/games/HoldemModel.lua"))("TavernGames", ns) end -- what a table draws (no frames)

-- Rule 11a at the table: once nobody can bet any more the dealer turns every live hand up (a seat-0
-- show) before the board runs out; a folded hand never; a table with a peer of the version before
-- (no early show) plays on as it did, nobody accused.
local N = { "Иван Петров", "Мария Стоянова", "Kiro Barley", "Пешо Тодоров" }
local W = "Гледач Гледачев"
local function rnd(i) return function(lo, hi) return (lo + i) % (hi + 1) end end
local function KEY(i) return ("%02x"):format(i):rep(16) end
local sim, tid, cl, w

local function tableN(n)
  sim = Sim.new(); cl = {}
  for i = 1, n do cl[i] = sim:add(N[i]); sim.envs[N[i]].random = rnd(i) end
  w = sim:add(W); sim:run(1)
  tid = cl[1]:openTable{ game = "holdem", access = "guild", turn = 30 }; sim:run(3)
  w:watch(tid); sim:run(1)
  for i = 2, n do cl[i]:sit(tid, i); sim:run(1) end
end
local function host()
  for i = 1, #cl do
    local c = sim.clients[N[i]]
    if c.session and c.session.role == "host" then return c end
  end
end
local function st() return host().session.state end
local function at(seat) return sim.clients[host().session.seats[seat]] end
-- the seat on turn acts; the messages are delivered (no second passes)
local function act(k, to)
  local seat = st().turn
  local r, why = at(seat):act{ k = k, to = to }
  ok(r, "seat " .. tostring(seat) .. " " .. k .. ": " .. tostring(why)); sim:run(0)
end
local function evs_(sm, name, from)
  local out = {}
  for i = from + 1, #sm.sent do
    local m = sm.sent[i]
    if m.target == name and m.msg.t == "EV" then out[#out + 1] = m.msg.a end
  end
  return out
end
local function evs(name, from) return evs_(sim, name, from) end
local function kinds(list)
  local out = {}
  for i, a in ipairs(list) do out[i] = a.k == "fair" and a.op or a.k end
  return out
end
local function mentions(v, words)
  if type(v) == "string" then
    for _, x in ipairs(words) do if v:find(x, 1, true) then return true end end
    return false
  end
  if type(v) ~= "table" then return false end
  for k, x in pairs(v) do if mentions(k, words) or mentions(x, words) then return true end end
  return false
end
local function deckOf(h, n)
  local seeds = {}
  for i = 1, n do seeds[i] = Fair.handSeed(KEY(i), tid .. "/" .. h) end
  return Fair.deck(E.DECK, seeds, tid .. "/" .. h)
end
-- the faces of `seats`' hands in `deck` on the state st
local function holes(stt, deck, seats)
  local t = {}
  for _, seat in ipairs(seats) do for _, i in ipairs(stt.p[seat].cards) do t[i] = deck[i] end end
  return t
end
local function faces(t) local out = {} for _, f in pairs(t) do out[#out + 1] = f end return out end
-- no foul, no alarm, every hand sealed on every client
local function fine(list)
  for _, c in ipairs(list) do
    local s = c.session
    eq({ s.fairLast and s.fairLast.verdict, s.fair and s.fair.foul, ns.Deal.alarm(s), s.stale or false }, { "sealed", nil, false, false }, c.env and c.env.me or "")
  end
end
-- the best of the hands shown at the showdown on `stt` (a client's state) -> seat
local function best(stt)
  local top, who = -1, nil
  for _, seat in ipairs(stt.last.shown) do
    local f = {}
    for _, i in ipairs(stt.board) do f[#f + 1] = stt.deck[i] end
    for _, i in ipairs(stt.p[seat].cards) do f[#f + 1] = stt.deck[i] end
    local score = HE.best(f)
    if score > top then top, who = score, seat end
  end
  return who
end

-- A peer of the version before rule 11a: its engine's view knows no hand turned up early (E.faceUp).
-- Simulated by a mark on its own state (copies of it keep the mark: allPublic's trial, Fair.full).
local view = E.view
local function withOld(fn)
  E.view = function(s, seat, dealt) return view(s, seat, dealt or s.old == true) end
  local fine_, err = pcall(fn)
  E.view = view
  if not fine_ then error(err, 0) end
end
local function old(c) c.session.state.old = true end
-- hand 1 folded by its button (seat 1 deals it), the next hand dealt by seat 2
local function toHand2()
  act("fold"); sim:run(5)
  eq({ st().hand, st().button, cl[2].session.fair.d, cl[2].session.fair.stage }, { 2, 2, 2, "dealt" })
end

describe("holdem at the table: hands up at an all-in", function()
  it("heads-up all-in preflop: one show of both hands before the flop, watched too; the board runs out; the best hand wins", function()
    tableN(2); ok(cl[1]:startGame()); sim:run(3); local mark = #sim.sent; local deck = deckOf(4, 2)
    eq({ st().turn, st().order, cl[1].session.fair.d }, { 1, { 2, 1 }, 1 })
    act("allin"); eq(#evs(W, mark), 1); eq(w.session.state.deck, {})            -- the call is open: nothing up
    act("call")
    local up = holes(st(), deck, { 1, 2 })
    eq(kinds(evs(W, mark)), { "allin", "call", "show" }); eq(evs(W, mark)[3].cards, up)
    for _, c in ipairs({ cl[1], cl[2], w }) do
      eq({ c.session.state.phase, c.session.state.deck, #c.session.state.board }, { "street", up, 0 }, c.env.me)
    end
    local m = ns.HoldemModel.build(w.session)                                    -- the watcher sees both hands
    eq({ m.seats[1].cards, m.seats[2].cards }, { { up[2], up[4] }, { up[1], up[3] } })
    sim:run(6)
    eq(kinds(evs(W, mark)), { "allin", "call", "show", "street", "street", "street", "showdown" })
    eq(evs(W, mark)[7].cards[1], up[1])
    local l = st().last; eq({ l.shown, l.won[best(w.session.state)] }, { { 2, 1 }, 2000 })
    eq(w.session.state.last, l); eq(cl[2].session.state.last, l)
    fine({ cl[1], cl[2], w })
  end)

  it("all-in on the turn with a third player folded: only the two live hands; the folded one nowhere", function()
    tableN(3); ok(cl[1]:startGame()); sim:run(3); local mark = #sim.sent; local deck = deckOf(5, 3)
    eq({ st().order, st().turn }, { { 2, 3, 1 }, 1 })
    local folded = faces(holes(st(), deck, { 2 }))                                  -- the small blind folds (seat 1 deals)
    act("call"); act("fold"); act("check"); sim:run(2); act("check"); act("check"); sim:run(2)
    eq({ st().phase, #st().board }, { "bet", 4 })
    act("allin"); act("call")
    local up = holes(st(), deck, { 3, 1 })
    local e = evs(W, mark); eq(e[#e], { k = "show", cards = up })
    sim:run(4); eq(kinds(evs(W, mark)), { "call", "fold", "check", "street", "check", "check", "street", "allin", "call", "show", "street", "showdown" })
    eq(st().last.shown, { 3, 1 })
    -- seat 2's two cards: in its own PRV and nowhere else, on no screen of another
    eq(sim:count(function(m) return mentions(m.msg, folded) end), 1)
    eq(sim:count(function(m) return m.msg.t == "PRV" and m.target == N[2] and mentions(m.msg, folded) end), 1)
    for _, c in ipairs({ cl[1], cl[3], w }) do
      ok(not mentions(c.session.state.deck, folded), c.env.me .. " holds a folded card")
      ok(not mentions(ns.HoldemModel.build(c.session), folded), c.env.me .. " draws a folded card")
    end
    fine({ cl[1], cl[2], cl[3], w })
  end)

  it("a cash table, one short all-in: nothing up while two can bet, then every live hand; the pots as ever", function()
    local s2, c2 = Play.cash(3, nil, { 1000, 1000, 400 })
    local names = { Play.NAMES[1], Play.NAMES[2], Play.NAMES[3] }
    local hostC = c2[names[1]]
    local function hs() return hostC.session.state end
    for _ = 1, 30 do if hs().phase == "bet" then break end; s2:run(1) end
    eq(hs().phase, "bet"); local mark = #s2.sent
    local function move(k) local seat = hs().turn; ok(c2[hostC.session.seats[seat]]:act{ k = k }); s2:run(0) end
    local function shows() local n = 0 for _, a in ipairs(evs_(s2, names[2], mark)) do if a.k == "show" then n = n + 1 end end return n end
    while hs().phase == "bet" and hs().street == 0 do
      local seat = hs().turn
      if seat == 3 and not hs().p[3].allin then move("allin")
      elseif hs().bet > hs().p[seat].bet then move("call") else move("check") end
    end
    eq({ hs().p[3].allin, shows() }, { true, 0 })
    for _ = 1, 3 do s2:run(1) end
    while hs().phase == "bet" and hs().street == 1 do move("check") end
    eq(shows(), 0); for _ = 1, 3 do s2:run(1) end
    eq({ hs().phase, hs().street }, { "bet", 2 }); move("allin"); eq(shows(), 0); move("call")
    eq(shows(), 1)
    local dealer = c2[hostC.session.seats[hostC.session.fair.d]].session.fair.deck
    local e = evs_(s2, names[2], mark); local show
    for _, a in ipairs(e) do if a.k == "show" then show = a end end
    local seen = {} for i in pairs(show.cards) do seen[#seen + 1] = i end
    eq(#seen, 6)                                                                   -- the three live hands
    for i, f in pairs(show.cards) do eq(dealer[i], f) end
    for _ = 1, 6 do s2:run(1) end
    local l = c2[names[3]].session.state.last
    eq({ l.pots[1].amount, l.pots[1].eligible, l.pots[2].amount, #l.pots[2].eligible, #l.shown }, { 1200, hs().last.pots[1].eligible, 1200, 2, 3 })
    eq(l, hs().last)
    local won = 0 for _, x in pairs(l.won) do won = won + x end; eq(won, 2400)
  end)

  it("an old host with a new dealer: no early show (its host refuses it), the hand runs as before, nobody accused", function()
    withOld(function()
      tableN(2); ok(cl[1]:startGame()); sim:run(3); old(cl[1]); toHand2()
      local mark = #sim.sent
      act("allin"); act("call"); sim:run(6)
      eq(kinds(evs(W, mark)), { "allin", "call", "street", "street", "street", "showdown" })
      eq(sim:count(function(m) return m.msg.t == "ACT" and type(m.msg.a) == "table" and m.msg.a.op == "show" end), 1) -- asked once, refused
      eq(#st().last.shown, 2); fine({ cl[1], cl[2], w })
    end)
  end)

  it("an old host with a new dealer, a blind all-in at the deal: the deal goes through, each player gets its own cards", function()
    withOld(function()
      tableN(2); ok(cl[1]:startGame()); sim:run(3); old(cl[1])
      act("fold")
      for _, c in ipairs({ cl[1], cl[2], w }) do c.session.state.seats[2].chips = 4 end   -- the next small blind is short
      sim:run(5)
      local s = st(); eq({ s.hand, s.button, s.phase ~= "bet" and E.inHand(s), cl[2].session.fair.d, cl[2].session.fair.stage }, { 2, 2, true, 2, "dealt" })
      for _, q in ipairs({ 1, 2 }) do
        local mine = cl[q].session.state
        for _, i in ipairs(mine.p[q].cards) do ok(mine.deck[i] ~= nil, "seat " .. q .. " lacks its card " .. i) end
      end
      sim:run(6); eq({ st().phase, #st().last.shown }, { "done", 2 }); fine({ cl[1], cl[2], w })
    end)
  end)

  it("a new host with an old dealer: no show asked, the hands up at the showdown as before", function()
    withOld(function()
      tableN(2); ok(cl[1]:startGame()); sim:run(3); old(cl[2]); toHand2()
      local mark = #sim.sent
      act("allin"); act("call"); sim:run(6)
      eq(kinds(evs(W, mark)), { "allin", "call", "street", "street", "street", "showdown" })
      eq(sim:count(function(m) return m.msg.t == "ACT" and type(m.msg.a) == "table" and m.msg.a.op == "show" end), 0)
      fine({ cl[1], cl[2], w })
    end)
  end)

  it("a dealer that is not the host: it deals the streets, never the showdown the host now plays itself", function()
    tableN(2); ok(cl[1]:startGame()); sim:run(3); toHand2(); local mark = #sim.sent
    act("allin"); act("call"); sim:run(6)
    eq(kinds(evs(W, mark)), { "allin", "call", "show", "street", "street", "street", "showdown" })
    local function steps(k) return sim:count(function(m) local a = m.msg.t == "ACT" and m.msg.a
      return type(a) == "table" and a.op == "step" and m.from == N[2] and type(a.a) == "table" and a.a.k == k end) end
    eq({ steps("street"), steps("showdown") }, { 3, 0 }); fine({ cl[1], cl[2], w })
  end)

  it("the dealer reloads after its show: the show is not played again", function()
    tableN(2); ok(cl[1]:startGame()); sim:run(3); toHand2(); local mark = #sim.sent
    act("allin"); act("call")
    local c2 = sim:relog(N[2]); sim.envs[N[2]].random = rnd(2); sim:run(2)
    eq({ c2.session.fair.stage, c2.session.fair.deck ~= nil }, { "dealt", true })
    sim:run(6)
    local shows = 0
    for _, a in ipairs(evs(W, mark)) do if a.k == "show" then shows = shows + 1 end end
    eq({ shows, st().phase, #st().last.shown }, { 1, "done", 2 }); fine({ cl[1], c2, w })
  end)

  it("an old host refused the show, a seat reloads mid run-out: its PRQ gets its own cards back", function()
    withOld(function()
      tableN(3); ok(cl[1]:startGame()); sim:run(3); old(cl[1])
      act("fold"); act("fold"); sim:run(5)
      eq({ st().hand, st().button, st().order, st().turn, cl[2].session.fair.d }, { 2, 2, { 3, 1, 2 }, 2, 2 })
      act("allin"); act("allin"); act("call")                                      -- stacks 995, 1005, 1000: all in
      local mark = #sim.sent
      local c3 = sim:relog(N[3]); sim.envs[N[3]].random = rnd(3); sim:run(2)
      local mine = c3.session.state
      ok(E.inHand(mine), "the run-out still goes on")
      for _, i in ipairs(mine.p[3].cards) do ok(mine.deck[i] ~= nil, "seat 3 lacks its card " .. i) end
      eq(sim:count(function(m) return m.msg.t == "PRQ" and m.from == N[3] end) > 0, true)
      local back = 0
      for k = mark + 1, #sim.sent do local m = sim.sent[k]; if m.msg.t == "PRV" and m.target == N[3] then back = back + 1 end end
      eq(back, 1); sim:run(6); eq({ st().phase, #st().last.shown }, { "done", 3 }); fine({ cl[1], cl[2], w })
    end)
  end)

  it("an old player and an old watcher take the show like any event", function()
    withOld(function()
      tableN(3); ok(cl[1]:startGame()); sim:run(3); old(cl[3]); old(w); local mark = #sim.sent
      act("allin"); act("call"); act("call"); sim:run(6)
      eq(kinds(evs(W, mark)), { "allin", "call", "call", "show", "street", "street", "street", "showdown" })
      eq(cl[3].session.state.last, st().last); fine({ cl[1], cl[2], cl[3], w })
    end)
  end)
end)
