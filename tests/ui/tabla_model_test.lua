local Wow = require("wow")

local A, B = "Иван Петров", "Мария Стоянова"

-- In a guild, booted with the ui/ files, own name resolved, PLAYER_LOGIN fired.
local function guildWow()
  local w = Wow.new{ ui = true }
  w.inGuild = true
  w.roster = { { name = A .. "-Forever", online = true, guid = Wow.GUID } }
  w.G.RAID_CLASS_COLORS.PRIEST = { r = 1, g = 1, b = 1 }
  w:boot()
  w:firstRunDone()
  w:fire("GUILD_ROSTER_UPDATE")
  w:fire("PLAYER_LOGIN")
  return w
end

local w = guildWow()
local M, E = w.ns.TablaModel, w.ns.Engines.tabla

-- The helpers at the top of tests/engines/tabla_test.lua, verbatim.
local function arr(m) local t = {} for i = 1, 24 do t[i] = (m and m[i]) or 0 end return t end
local function sum(t) local n = 0 for i = 1, 24 do n = n + t[i] end return n end
local GAME = { std = 1, tapa = 2, gul = 3 }

-- A position with `turn` about to roll. m1/m2: own point -> count; off defaults to the rest of 15.
local function pos(var, turn, m1, m2, o)
  o = o or {}
  local s = E.new{}
  s.game, s.var = GAME[var], var
  s.pts, s.pin = { arr(m1), arr(m2) }, { arr(o.pin1), arr(o.pin2) }
  s.bar = o.bar or { 0, 0 }
  s.off = {}
  for seat = 1, 2 do
    s.off[seat] = (o.off and o.off[seat]) or (15 - sum(s.pts[seat]) - s.bar[seat])
  end
  s.rolls = o.rolls or { 0, 0 }
  s.turn, s.phase = turn, "roll"
  return s
end
local function roll(s, a, b) ok(E.apply(s, 0, { k = "dice", d = { a, b } })) end
local function mv(s, steps) ok(E.apply(s, s.turn, { k = "move", steps = steps })) end

local function sess(state, seat)
  return { game = "tabla", status = "live", mySeat = seat, seats = { A, B }, state = state }
end
local function build(st, seat, staged, pick) return M.build(sess(st, seat), staged or {}, pick) end
-- The sorted list of the keys of t.
local function set(t)
  local out = {}
  for k in pairs(t) do out[#out + 1] = k end
  table.sort(out)
  return out
end

describe("tabla model", function()
  it("the board from my side; what I may pick, where it may land; canDone is false while a die can still be played", function()
    local st = E.new{}; roll(st, 6, 1); roll(st, 3, 1); local m = build(st, 1)
    eq({ m.me, m.mine, m.var, m.dice, m.left, m.score, m.rolling }, { 1, true, "std", { 3, 1 }, { 3, 1 }, { me = 0, op = 0 }, false })
    eq({ m.points[24], m.points[1], m.points[6], m.points[19], m.points[12], m.points[17] },
       { { own = 2, opp = 0 }, { own = 0, opp = 2 }, { own = 5, opp = 0 }, { own = 0, opp = 5 }, { own = 0, opp = 5 }, { own = 0, opp = 3 } })
    eq({ set(m.from), set(m.to), m.pick, m.canUndo, m.canDone, m.text }, { { 6, 8, 13, 24 }, {}, nil, false, false, { "tabla.yourTurn" } })
    m = build(st, 1, {}, 8); eq({ m.pick, set(m.to), m.text }, { 8, { 5, 7 }, { "tabla.pickTarget" } }); eq(build(st, 1, {}, 7).pick, nil)
    m = build(st, 1, { { 8, 5 } }); eq({ m.points[8].own, m.points[5].own, m.left, set(m.from), m.canUndo, m.canDone }, { 2, 1, { 1 }, { 5, 6, 8, 24 }, true, false })
    m = build(st, 1, { { 8, 5 }, { 6, 5 } }); eq({ m.canDone, set(m.from), m.left, m.text, m.stuck }, { true, {}, {}, { "tabla.ready" }, false })
    m = build(st, 1, { { 8, 4 } }); eq({ m.reset, m.points[8].own, m.canUndo }, { true, 3, false })
    m = build(st, 2); eq({ m.me, m.mine, set(m.from), m.points[1], m.points[24], m.text }, { 2, false, {}, { own = 0, opp = 2 }, { own = 2, opp = 0 }, { "tabla.waitFor", A } })
    m = build(st, nil); eq({ m.me, m.seated, m.mine, m.canDone }, { 1, false, false, false })
  end)

  it("a pinned checker lies under its pinner; Гюлбара puts the opponent's start on my 12", function()
    local s = pos("tapa", 1, { [10] = 1, [9] = 1, [24] = 13 }, { [18] = 1, [20] = 1, [24] = 13 }); roll(s, 3, 2); mv(s, { { 10, 7 }, { 9, 7 } })
    eq(build(s, 1).points[7], { own = 2, opp = 1, under = "opp" }); eq(build(s, 2).points[18], { own = 1, opp = 2, under = "own" })
    local g = pos("gul", 1, { [24] = 15 }, { [24] = 15 })
    eq({ build(g, 1).points[24], build(g, 1).points[12], build(g, 2).points[12] }, { { own = 15, opp = 0 }, { own = 0, opp = 15 }, { own = 0, opp = 15 } })
  end)

  it("the bar, the tray and a roll with no move", function()
    local bo = pos("std", 1, { [2] = 1, [1] = 1 }, { [24] = 15 }); roll(bo, 6, 5); local m = build(bo, 1, {}, 2)
    eq({ set(m.to), m.off }, { { 0 }, { own = 13, opp = 0 } }); eq(build(bo, 1, { { 2, 0 } }).off.own, 14)
    local u = pos("std", 1, { [24] = 2, [13] = 12 }, { [6] = 2, [5] = 2, [4] = 2, [3] = 2, [2] = 2, [1] = 2, [24] = 3 }, { bar = { 1, 0 } })
    eq(build(u, 1).rolling, true); roll(u, 3, 4); m = build(u, 1)
    eq({ m.bar, set(m.from), m.canDone, m.stuck, m.text }, { { own = 1, opp = 0 }, {}, true, true, { "tabla.stuck" } })
    local e = pos("std", 1, { [24] = 2, [13] = 12 }, { [24] = 15 }, { bar = { 1, 0 } }); roll(e, 3, 4); eq(set(build(e, 1).from), { 25 })
  end)

  it("a transferred remainder names whose throw I finish; the cascade names its number", function()
    local g = pos("gul", 1, { [24] = 1, [12] = 1 }, { [7] = 1, [20] = 14 }, { rolls = { 3, 0 } }); roll(g, 5, 5)
    eq(build(g, 1).text, { "tabla.cascade", 5 }); local c = E.restore(E.snapshot(g)); c.cv, c.left = 6, { 6, 6, 6, 6 }; eq(build(c, 2).dice, { 6, 6 }); mv(g, { { 12, 7 }, { 7, 2 } })
    eq({ build(g, 2).mine, build(g, 2).text, build(g, 2).left }, { true, { "tabla.xfer.mine", 5, A }, { 5, 5 } }); eq(build(g, 1).text, { "tabla.xfer", B, 5, A })
  end)

  it("the throw, the end of a game and of the match in words", function()
    local st = E.new{}; eq(build(st, 1).text, { "tabla.opening" }); eq(build(st, 1).dice, nil); roll(st, 6, 1); eq(build(st, 2).text, { "tabla.opens", A })
    roll(st, 3, 1); mv(st, { { 8, 5 }, { 6, 5 } }); eq(build(st, 1).text, { "tabla.rolling", B })
    local mp = pos("tapa", 1, { [4] = 1, [10] = 14 }, { [24] = 1, [20] = 14 }); roll(mp, 3, 5); mv(mp, { { 4, 1 } }); eq(build(mp, 2).text, { "tabla.game.mother", A })
    -- a game won for 1 point, a марс in Обикновена
    local g1 = pos("std", 1, { [1] = 1 }, { [24] = 15 }); roll(g1, 2, 1); mv(g1, { { 1, 0 } })
    eq({ g1.phase, g1.gp }, { "game", 2 }); eq(build(g1, 2).text, { "tabla.game.mars", A })
    local g2 = pos("std", 2, { [24] = 14 }, { [1] = 1 }, { off = { 1, 14 } }); roll(g2, 2, 1); mv(g2, { { 1, 0 } })
    eq({ g2.phase, g2.gp }, { "game", 1 }); eq(build(g2, 1).text, { "tabla.game.won", B })
    -- the match: won, lost, a watcher's line, a seat that left
    local mt = E.new{}; mt.phase, mt.winner, mt.score = "match", 2, { 3, 5 }
    eq({ build(mt, 2).text, build(mt, 1).text, build(mt, nil).text, build(mt, 1).score }, { { "tabla.match.won" }, { "tabla.match.lost" }, { "tabla.match.name", B }, { me = 3, op = 5 } })
    local q = E.new{}; E.leave(q, 1)
    local sq = sess(q, 2); sq.seats = { false, B }
    eq({ M.build(sq, {}, nil, { A, B }).text, M.build(sq, {}).text }, { { "tabla.left", A }, { "tabla.left", "?" } })
  end)
end)
