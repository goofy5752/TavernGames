local E = Loader.ns().Engines.tabla

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
local function rejects(s, steps)
  local before = E.snapshot(s)
  eq({ E.apply(s, s.turn, { k = "move", steps = steps }) }, { nil, "move" })
  eq(E.snapshot(s), before)
end
local function after(s, steps)
  local c = E.restore(E.snapshot(s))
  ok(E.apply(c, c.turn, { k = "move", steps = steps }))
  return c
end
local function posKey(s)
  return table.concat(s.pts[1], ",") .. "|" .. table.concat(s.pts[2], ",") .. "|" ..
    table.concat(s.pin[1], ",") .. "|" .. table.concat(s.pin[2], ",") .. "|" ..
    s.bar[1] .. s.bar[2] .. "|" .. s.off[1] .. "," .. s.off[2] .. "|" .. tostring(s.gp)
end
-- Legal moves as a set of resulting positions.
local function legalSet(s)
  local set, n = {}, 0
  for _, m in ipairs(E.legal(s, s.turn)) do set[posKey(after(s, m.steps))] = true; n = n + 1 end
  return set, n
end
-- `steps` (in this order) applies and its resulting position is one of the legal moves.
local function isLegal(s, steps)
  local c = E.restore(E.snapshot(s))
  if not E.apply(c, c.turn, { k = "move", steps = steps }) then return false end
  return legalSet(s)[posKey(c)] == true
end
local NOMOVE = { { k = "move", steps = {} } }

describe("tabla start and flow", function()
  it("Обикновена start: 2 on 24, 5 on 13, 3 on 8, 5 on 6 for both seats; opening roll first", function()
    local s = E.new{}
    eq(s.var, "std"); eq(s.game, 1); eq(s.phase, "open")
    eq(s.pts[1], arr{ [24] = 2, [13] = 5, [8] = 3, [6] = 5 }); eq(s.pts[2], s.pts[1])
    eq(s.bar, { 0, 0 }); eq(s.off, { 0, 0 }); eq(s.score, { 0, 0 })
    eq({ E.system(s) }, { { k = "dice", need = "dice", r = "open" }, 0 })
    eq(E.abs("std", 2, 24), 1); eq(E.abs("std", 2, 6), 19); eq(E.abs("std", 1, 6), 6)
  end)
  it("opening roll: tie rolls again, the higher die starts and rolls anew", function()
    local s = E.new{}
    ok(E.apply(s, 0, { k = "dice", d = { 4, 4 } })); eq(s.phase, "open"); eq(s.turn, nil)
    ok(E.apply(s, 0, { k = "dice", d = { 2, 5 } })); eq(s.phase, "roll"); eq(s.turn, 2)
    eq({ E.system(s) }, { { k = "dice", need = "dice", r = "roll", s = 2 }, 0 })
    ok(E.apply(s, 0, { k = "dice", d = { 3, 1 } })); eq(s.phase, "move"); eq(s.left, { 3, 1 })
    eq(s.dice, { 3, 1 }); eq(E.system(s), nil); eq(E.legal(s, 1), {}); eq(E.auto(s, 1), nil)
    mv(s, { { 8, 5 }, { 6, 5 } })
    eq(s.pts[2], arr{ [24] = 2, [13] = 5, [8] = 2, [6] = 4, [5] = 2 }); eq(s.turn, 1); eq(s.phase, "roll")
  end)
  it("rejects bad seat, phase, turn, dice and actions without touching the state", function()
    local s = E.new{}
    local snap = E.snapshot(s)
    eq({ E.apply(s, 1, { k = "dice", d = { 1, 2 } }) }, { nil, "seat" })
    eq({ E.apply(s, 0, { k = "dice", d = { 0, 2 } }) }, { nil, "dice" })
    eq({ E.apply(s, 0, { k = "dice", d = { 1, 7 } }) }, { nil, "dice" })
    eq({ E.apply(s, 0, { k = "dice", d = { 1.5, 2 } }) }, { nil, "dice" })
    eq({ E.apply(s, 0, { k = "dice" }) }, { nil, "dice" })
    eq({ E.apply(s, 1, { k = "move", steps = {} }) }, { nil, "phase" })
    eq({ E.apply(s, 0, { k = "move", steps = {} }) }, { nil, "seat" })
    eq({ E.apply(s, 0, { k = "next" }) }, { nil, "phase" })
    eq({ E.apply(s, 1, { k = "next" }) }, { nil, "seat" })
    eq({ E.apply(s, 0, { k = "need", r = "open" }) }, { nil, "action" })
    eq({ E.apply(s, 1, nil) }, { nil, "action" })
    eq(E.snapshot(s), snap)
    roll(s, 6, 1); roll(s, 6, 5)
    eq({ E.apply(s, 0, { k = "dice", d = { 1, 2 } }) }, { nil, "phase" })
    eq({ E.apply(s, 2, { k = "move", steps = {} }) }, { nil, "turn" })
    rejects(s, "x"); rejects(s, { { 24, 13 } }); rejects(s, { { 24, 18 } })
    rejects(s, { { 24, 18 }, { 18, 13 }, { 13, 8 } }); rejects(s, { "a" }); rejects(s, { { 2.5, 1 } })
    rejects(s, { { 24, 18 }, { 18, 12 } }); rejects(s, {})
  end)
  it("apply accepts any order of the steps and legal is deduped by resulting position", function()
    local s = pos("std", 1, { [24] = 2, [13] = 5, [8] = 3, [6] = 5 }, { [24] = 2, [13] = 5, [8] = 3, [6] = 5 })
    roll(s, 6, 5)
    eq(posKey(after(s, { { 13, 8 }, { 24, 18 } })), posKey(after(s, { { 24, 18 }, { 13, 8 } })))
    rejects(s, { { 24, 19 }, { 19, 13 } }) -- 19 is the opponent's 6 point
    local d = pos("std", 1, { [24] = 2, [13] = 5, [8] = 3, [6] = 5 }, { [24] = 2, [13] = 5, [8] = 3, [6] = 5 })
    roll(d, 3, 1)
    eq(posKey(after(d, { { 24, 21 }, { 21, 20 } })), posKey(after(d, { { 24, 23 }, { 23, 20 } })))
    local n = 0
    for _, m in ipairs(E.legal(d, 1)) do
      local a = after(d, m.steps)
      if a.pts[1][20] == 1 and a.pts[1][24] == 1 then n = n + 1 end
    end
    eq(n, 1)
    for _, d in ipairs({ { 6, 5 }, { 3, 3 }, { 1, 1 } }) do
      local t = pos("std", 1, { [24] = 2, [13] = 5, [8] = 3, [6] = 5 }, { [24] = 2, [13] = 5, [8] = 3, [6] = 5 })
      roll(t, d[1], d[2])
      local seen, n = {}, 0
      for _, m in ipairs(E.legal(t, 1)) do
        eq(#m.steps, d[1] == d[2] and 4 or 2)
        local k = posKey(after(t, m.steps)); ok(not seen[k], "duplicate position"); seen[k] = true; n = n + 1
      end
      ok(n > 5)
    end
  end)
  it("snapshot round-trips mid-game", function()
    local s = E.new{}; roll(s, 6, 1); roll(s, 3, 1); mv(s, { { 8, 5 }, { 6, 5 } }); roll(s, 4, 4)
    local t = E.snapshot(s); t.pts[1][1] = 9
    eq(s.pts[1][1], 0); eq(E.snapshot(E.restore(E.snapshot(s))), E.snapshot(s))
    eq(E.legal(E.restore(E.snapshot(s)), 2), E.legal(s, 2))
  end)
  it("asks for dice with a need marker", function()
    local s = E.new{}; eq({ E.system(s) }, { { k = "dice", need = "dice", r = "open" }, 0 })
    eq({ E.apply(s, 0, { k = "dice", need = "dice", d = { 3, 5 } }) }, { nil, "need" })
    ok(E.apply(s, 0, { k = "dice", d = { 3, 5 } }))
    eq({ E.system(s) }, { { k = "dice", need = "dice", r = "roll", s = 2 }, 0 })
  end)
end)

describe("tabla Обикновена", function()
  it("landing on a blot hits it to the bar; two checkers block", function()
    local s = pos("std", 1, { [10] = 2 }, { [18] = 1, [24] = 2 })
    roll(s, 3, 1); mv(s, { { 10, 7 }, { 10, 9 } })
    eq(s.pts[1], arr{ [7] = 1, [9] = 1 }); eq(s.pts[2][18], 0); eq(s.bar, { 0, 1 })
    local b = pos("std", 1, { [10] = 2 }, { [18] = 2 })
    roll(b, 3, 3); eq(E.legal(b, 1), NOMOVE); eq(E.auto(b, 1), NOMOVE[1])
    mv(b, {}); eq(b.turn, 2); eq(b.phase, "roll")
  end)
  it("checkers on the bar enter first, into the opponent's home; entry can hit", function()
    local s = pos("std", 1, { [13] = 1 }, { [2] = 1, [10] = 3 }, { bar = { 1, 0 } })
    roll(s, 6, 2)
    local _, n = legalSet(s)
    for _, m in ipairs(E.legal(s, 1)) do eq(m.steps[1][1], 25) end
    ok(isLegal(s, { { 25, 23 }, { 13, 7 } })); ok(isLegal(s, { { 25, 19 }, { 19, 17 } })); ok(n >= 4)
    rejects(s, { { 13, 7 }, { 25, 23 } })
    mv(s, { { 25, 23 }, { 13, 7 } }); eq(s.bar, { 0, 1 }); eq(s.pts[2][2], 0); eq(s.pts[1][23], 1)
  end)
  it("blocked entry loses the roll; with two on the bar the second die waits", function()
    local s = pos("std", 1, { [13] = 1 }, { [6] = 2, [2] = 2 }, { bar = { 1, 0 } })
    roll(s, 6, 2); eq(E.legal(s, 1), NOMOVE)
    local t = pos("std", 1, { [13] = 1 }, { [6] = 2 }, { bar = { 2, 0 } })
    roll(t, 6, 2); eq(E.legal(t, 1), { { k = "move", steps = { { 25, 23 } } } })
  end)
  it("max dice: a first step that strands the second die is not legal", function()
    -- 10/4 leaves no 1 (4/3 blocked, 20/19 blocked); 10/9 then 20/14 uses both
    local s = pos("std", 1, { [10] = 1, [20] = 1 }, { [22] = 2, [6] = 2 })
    roll(s, 6, 1)
    local _, n = legalSet(s)
    ok(isLegal(s, { { 10, 9 }, { 20, 14 } })); ok(n >= 1)
    for _, m in ipairs(E.legal(s, 1)) do eq(#m.steps, 2) end
    rejects(s, { { 10, 4 } })
  end)
  it("larger die: when only one die can be used the larger must be, else the smaller", function()
    local s = pos("std", 1, { [13] = 1 }, { [19] = 2 }) -- 13/6 blocked: 6 or 1, not both
    roll(s, 6, 1); eq(E.legal(s, 1), { { k = "move", steps = { { 13, 7 } } } }); rejects(s, { { 13, 12 } })
    local t = pos("std", 1, { [13] = 1 }, { [18] = 2, [19] = 2 }) -- 13/7 blocked: only the 1
    roll(t, 6, 1); eq(E.legal(t, 1), { { k = "move", steps = { { 13, 12 } } } })
  end)
  it("bearing off: exact, higher die from the highest point, otherwise move inside", function()
    local s = pos("std", 1, { [4] = 2, [2] = 1 }, { [12] = 15 })
    roll(s, 6, 5); eq(E.legal(s, 1), { { k = "move", steps = { { 4, 0 }, { 4, 0 } } } })
    rejects(s, { { 2, 0 }, { 4, 0 } })
    local t = pos("std", 1, { [6] = 1, [1] = 1 }, { [12] = 15 })
    roll(t, 3, 2)
    local legal = E.legal(t, 1); eq(#legal, 1)
    eq(after(t, legal[1].steps).pts[1], arr{ [1] = 2 }); rejects(t, { { 1, 0 }, { 6, 3 } })
    local x = pos("std", 1, { [3] = 2, [5] = 1 }, { [12] = 15 })
    roll(x, 3, 3); mv(x, { { 3, 0 }, { 3, 0 }, { 5, 2 }, { 2, 0 } }); eq(x.off[1], 15)
  end)
  it("bearing off needs every checker home; it may start once the last one comes in", function()
    local s = pos("std", 1, { [7] = 1, [2] = 3 }, { [12] = 15 })
    roll(s, 2, 1)
    ok(isLegal(s, { { 7, 6 }, { 2, 0 } })); ok(isLegal(s, { { 7, 5 }, { 5, 4 } }))
    mv(s, { { 7, 6 }, { 2, 0 } }); eq(s.off[1], 12)
    local t = pos("std", 1, { [7] = 1, [2] = 3 }, { [12] = 15 }); roll(t, 2, 1); rejects(t, { { 2, 0 }, { 7, 6 } })
  end)
  it("марс: 2 points when the loser has borne off none, else 1", function()
    local s = pos("std", 1, { [1] = 1 }, { [12] = 15 })
    roll(s, 6, 5); mv(s, { { 1, 0 } })
    eq(s.phase, "game"); eq(s.gw, 1); eq(s.gp, 2); eq(s.score, { 2, 0 }); eq(s.turn, nil)
    local t = pos("std", 1, { [1] = 1 }, { [12] = 14 })
    roll(t, 6, 5); mv(t, { { 1, 0 } }); eq(t.gp, 1); eq(t.score, { 1, 0 })
  end)
end)

describe("tabla Тапа", function()
  it("starts with 15 on 24 for both, seats move in opposite directions", function()
    local t = E.new{}
    t.score = { 1, 0 }; t.gw, t.phase = 1, "game"; ok(E.apply(t, 0, { k = "next" }))
    eq(t.var, "tapa"); eq(t.pts[1], arr{ [24] = 15 }); eq(t.pts[2], arr{ [24] = 15 }); eq(t.turn, 1)
    eq(t.phase, "roll"); eq(E.abs("tapa", 2, 24), 1)
  end)
  it("landing on a single opposing checker pins it; it cannot move until released", function()
    local s = pos("tapa", 1, { [10] = 1, [9] = 1, [24] = 13 }, { [18] = 1, [20] = 1, [24] = 13 })
    roll(s, 3, 2); mv(s, { { 10, 7 }, { 9, 7 } })
    eq(s.pin[2][18], 1); eq(s.pts[2][18], 1); eq(s.pts[1][7], 2); eq(s.bar, { 0, 0 })
    roll(s, 2, 1)
    for _, m in ipairs(E.legal(s, 2)) do
      for _, st in ipairs(m.steps) do ok(st[1] ~= 18, "pinned checker moved"); ok(st[2] ~= 18, "landed on pinner") end
    end
    rejects(s, { { 18, 16 }, { 20, 19 } }); rejects(s, { { 20, 18 }, { 24, 23 } })
    mv(s, { { 24, 22 }, { 24, 23 } })
    roll(s, 5, 4); mv(s, { { 7, 2 }, { 7, 3 } }); eq(s.pin[2][18], 0)
    roll(s, 2, 1); ok(isLegal(s, { { 18, 16 }, { 20, 19 } }))
  end)
  it("two opposing checkers block; a single pinner blocks the pinned side", function()
    local s = pos("tapa", 1, { [10] = 1, [24] = 14 }, { [18] = 2, [24] = 13 })
    roll(s, 3, 3)
    for _, m in ipairs(E.legal(s, 1)) do for _, st in ipairs(m.steps) do ok(st[2] ~= 7) end end
    local t = pos("tapa", 2, { [7] = 1, [24] = 14 }, { [18] = 1, [20] = 1, [24] = 13 }, { pin2 = { [18] = 1 } })
    roll(t, 2, 6); rejects(t, { { 20, 18 }, { 24, 18 } }); rejects(t, { { 24, 18 }, { 20, 18 } })
  end)
  it("pinning the mother wins at once for 2 points with dice left over", function()
    local s = pos("tapa", 1, { [4] = 1, [10] = 14 }, { [24] = 1, [20] = 14 })
    roll(s, 3, 5)
    ok(isLegal(s, { { 4, 1 } }))
    mv(s, { { 4, 1 } })
    eq(s.phase, "game"); eq(s.gw, 1); eq(s.gp, 2); eq(s.score, { 2, 0 }); eq(s.pin[2][24], 1)
    -- a mother pin may follow a lower step even in a double (the pin ends the move)
    local t = pos("tapa", 1, { [4] = 1, [3] = 1 }, { [24] = 1, [10] = 14 })
    roll(t, 3, 3)
    ok(isLegal(t, { { 4, 1 } })); ok(isLegal(t, { { 3, 0 }, { 4, 1 } }))
    mv(t, { { 3, 0 }, { 4, 1 } }); eq(t.gp, 2); eq(t.off[1], 14)
  end)
  it("a pinned checker outside home stops bearing off and counts as higher", function()
    local s = pos("tapa", 1, { [20] = 1, [2] = 14 }, { [5] = 1, [10] = 14 }, { pin1 = { [20] = 1 } })
    roll(s, 2, 2); eq(E.legal(s, 1), NOMOVE)
    local t = pos("tapa", 1, { [6] = 1, [2] = 1 }, { [19] = 1, [10] = 14 }, { pin1 = { [6] = 1 } })
    roll(t, 5, 4); eq(E.legal(t, 1), NOMOVE)
  end)
end)

describe("tabla Гюлбара", function()
  it("starts with 15 on 24 for both, seat 2's 24 is seat 1's 12, same direction", function()
    local s = E.new{}; s.game = 2; s.var = "tapa"; s.score = { 0, 1 }; s.gw, s.phase = 2, "game"
    ok(E.apply(s, 0, { k = "next" }))
    eq(s.var, "gul"); eq(s.game, 3); eq(s.pts[1], arr{ [24] = 15 }); eq(s.pts[2], arr{ [24] = 15 }); eq(s.turn, 2)
    eq(E.abs("gul", 2, 24), 12); eq(E.abs("gul", 2, 13), 1); eq(E.abs("gul", 2, 12), 24)
    roll(s, 6, 6)
    for _, m in ipairs(E.legal(s, 2)) do for _, st in ipairs(m.steps) do ok(st[2] ~= 12) end end
  end)
  it("one opposing checker blocks a point and nothing is hit", function()
    local s = pos("gul", 1, { [24] = 14, [10] = 1 }, { [9] = 1, [24] = 14 }) -- seat 2's 9 = seat 1's 21
    roll(s, 3, 1)
    for _, m in ipairs(E.legal(s, 1)) do for _, st in ipairs(m.steps) do ok(st[2] ~= 21) end end
    rejects(s, { { 24, 21 }, { 10, 9 } })
    mv(s, { { 24, 23 }, { 23, 20 } }); eq(s.pts[2][9], 1); eq(s.bar, { 0, 0 })
  end)
  it("doubles in a seat's first three rolls are plain doubles", function()
    local s = pos("gul", 1, { [24] = 15 }, { [24] = 15 }, { rolls = { 2, 0 } })
    roll(s, 2, 2); eq(s.left, { 2, 2, 2, 2 }); eq(s.cv, nil); eq(s.rolls[1], 3)
    mv(s, E.auto(s, 1).steps); eq(s.turn, 2); eq(s.phase, "roll")
  end)
  it("from the 4th roll a double cascades up to 6:6", function()
    local s = pos("gul", 1, { [24] = 15 }, { [24] = 15 }, { rolls = { 3, 3 } })
    roll(s, 5, 5); eq(s.cv, 5); eq(s.left, { 5, 5, 5, 5 })
    mv(s, { { 24, 19 }, { 24, 19 }, { 24, 19 }, { 24, 19 } })
    eq(s.turn, 1); eq(s.phase, "move"); eq(s.left, { 6, 6, 6, 6 }); eq(s.cv, 6)
    mv(s, { { 24, 18 }, { 24, 18 }, { 19, 13 }, { 19, 13 } })
    eq(s.turn, 2); eq(s.phase, "roll"); eq(s.cv, nil); eq(s.left, nil)
    local t = pos("std", 1, { [24] = 15 }, { [24] = 15 }, { rolls = { 5, 5 } })
    roll(t, 5, 5); eq(t.cv, nil)
  end)
  it("an unplayable part of the cascade goes to the opponent, who then rolls", function()
    -- seat 1: 12/7/2 then stuck (24/19 blocked, no bear-off): 2 fives + four 6s go to seat 2
    local s = pos("gul", 1, { [24] = 1, [12] = 1 }, { [7] = 1, [20] = 14 }, { rolls = { 3, 0 } })
    roll(s, 5, 5)
    local legal = E.legal(s, 1); eq(#legal, 1); eq(#legal[1].steps, 2)
    mv(s, { { 12, 7 }, { 7, 2 } })
    eq(s.turn, 2); eq(s.phase, "move"); eq(s.left, { 5, 5 }); eq(s.cv, 5); eq(s.xfer, true)
    eq(E.system(s), nil); eq(E.legal(s, 1), {})
    mv(s, { { 20, 15 }, { 20, 15 } })
    eq(s.turn, 2); eq(s.left, { 6, 6, 6, 6 }); eq(s.cv, 6)
    mv(s, E.auto(s, 2).steps)
    eq(s.turn, 2); eq(s.phase, "roll"); eq(s.cv, nil); eq(s.rolls, { 4, 0 })
  end)
  it("what the opponent cannot play of the remainder is lost", function()
    -- 24/18 blocked for both seats, neither may bear off: four 6s go to seat 2, then are lost
    local s = pos("gul", 1, { [24] = 14, [6] = 1 }, { [6] = 1, [24] = 14 }, { rolls = { 3, 1 } })
    roll(s, 6, 6); eq(E.legal(s, 1), NOMOVE); mv(s, {})
    eq(s.turn, 2); eq(s.left, { 6, 6, 6, 6 }); eq(s.xfer, true); eq(E.legal(s, 2), NOMOVE)
    mv(s, {}); eq(s.turn, 2); eq(s.phase, "roll"); eq(s.cv, nil); eq(s.xfer, nil)
  end)
end)

describe("tabla match", function()
  local function winNow(s, w, mars)
    local l = 3 - w
    s.pts, s.pin = { arr(), arr() }, { arr(), arr() }
    s.pts[w][1] = 1; s.pts[l][23] = mars and 15 or 14
    s.off = { 0, 0 }; s.off[w] = 14; s.off[l] = mars and 0 or 1
    s.turn = w
    roll(s, 6, 5); mv(s, { { 1, 0 } })
  end
  it("variants cycle std, tapa, gul, std; the game winner starts the next; match ends at 5", function()
    local s = E.new{}
    roll(s, 1, 6); eq(s.turn, 2)
    eq(s.var, "std"); winNow(s, 1, true); eq(s.score, { 2, 0 })
    eq({ E.system(s) }, { { k = "next" }, 3 }); ok(E.apply(s, 0, { k = "next" }))
    eq(s.var, "tapa"); eq(s.turn, 1); eq(s.phase, "roll"); eq(s.pts[1], arr{ [24] = 15 })
    winNow(s, 2, false); eq(s.score, { 2, 1 }); ok(E.apply(s, 0, { k = "next" }))
    eq(s.var, "gul"); eq(s.turn, 2); eq(s.game, 3)
    winNow(s, 1, false); eq(s.score, { 3, 1 }); ok(E.apply(s, 0, { k = "next" }))
    eq(s.var, "std"); eq(s.turn, 1); eq(s.pts[1], arr{ [24] = 2, [13] = 5, [8] = 3, [6] = 5 }); eq(s.rolls, { 0, 0 })
    eq(E.over(s), false); eq(E.result(s), nil)
    winNow(s, 1, true); eq(s.score, { 5, 1 })
    eq(s.phase, "match"); eq(s.winner, 1); eq(E.over(s), true)
    eq(E.result(s), { winners = { 1 }, losers = { 2 } }); eq(E.system(s), nil)
    eq({ E.apply(s, 0, { k = "next" }) }, { nil, "phase" })
  end)
  it("a seat that leaves loses the match; leaving after the end changes nothing", function()
    local s = E.new{}; roll(s, 5, 2); roll(s, 3, 1)
    E.leave(s, 1)
    eq(E.over(s), true); eq(E.result(s), { winners = { 2 }, losers = { 1 }, left = 1 }); eq(s.turn, nil)
    eq(E.legal(s, 1), {}); eq(E.system(s), nil)
    E.leave(s, 2); eq(E.result(s), { winners = { 2 }, losers = { 1 }, left = 1 })
    local t = E.new{}; E.leave(t, 2); eq(E.result(t), { winners = { 1 }, losers = { 2 }, left = 2 })
  end)
end)

describe("tabla staging", function()
  it("an open game: no view, dice by the extension, a new match on request, the result names a leaver", function()
    eq(E.view, nil); eq(E.ext, { "dice" }); eq(E.again, true); eq(E.nextFirst, nil)
    local s = E.new{}; roll(s, 5, 2); E.leave(s, 1); eq(E.result(s), { winners = { 2 }, losers = { 1 }, left = 1 })
  end)
  it("stage: what may follow a partial move, and done only for a whole legal move", function()
    local s = E.new{}; roll(s, 6, 1); roll(s, 3, 1)                                     -- seat 1 moves a 3 and a 1
    local r = E.stage(s, 1, {})
    eq({ r.done, r.left }, { false, { 3, 1 } }); eq(r.next, { { 24, 23 }, { 24, 21 }, { 13, 10 }, { 8, 7 }, { 8, 5 }, { 6, 5 }, { 6, 3 } })
    r = E.stage(s, 1, { { 8, 5 } }); eq({ r.done, r.left }, { false, { 1 } }); eq(r.next, { { 24, 23 }, { 8, 7 }, { 6, 5 }, { 5, 4 } })
    eq({ E.apply(E.restore(E.snapshot(s)), 1, { k = "move", steps = { { 8, 5 } } }) }, { nil, "move" })
    r = E.stage(s, 1, { { 24, 23 } }); eq(r.left, { 3 }); eq(r.next, { { 24, 21 }, { 23, 20 }, { 13, 10 }, { 8, 5 }, { 6, 3 } })
    r = E.stage(s, 1, { { 8, 5 }, { 6, 5 } }); eq({ r.done, r.left, r.next }, { true, {}, {} })
    eq(r.pts[1], arr{ [24] = 2, [13] = 5, [8] = 2, [6] = 4, [5] = 2 }); eq(s.pts[1][8], 3); eq(s.left, { 3, 1 })
    eq(E.stage(s, 2, {}), nil); eq(E.stage(s, 1, { { 8, 4 } }), nil); eq(E.stage(s, 1, { { 8, 5 }, { 6, 5 }, { 6, 5 } }), nil)
    eq(E.stage(s, 1, "x"), nil); eq(E.stage(s, 1, { { 8 } }), nil); eq(E.stage(E.new{}, 1, {}), nil)
  end)
  it("stage: a double, a blocked roll, bearing off", function()
    local d = pos("std", 1, { [24] = 2, [13] = 5, [8] = 3, [6] = 5 }, { [24] = 2, [13] = 5, [8] = 3, [6] = 5 }); roll(d, 6, 6)
    local r = E.stage(d, 1, {}); eq(r.left, { 6, 6, 6, 6 }); eq(r.next, { { 24, 18 }, { 13, 7 }, { 8, 2 } })
    r = E.stage(d, 1, { { 24, 18 }, { 24, 18 }, { 13, 7 } }); eq({ r.done, r.left }, { false, { 6 } }); eq(r.next, { { 13, 7 }, { 8, 2 } })
    local u = pos("std", 1, { [24] = 2, [13] = 12 }, { [6] = 2, [5] = 2, [4] = 2, [3] = 2, [2] = 2, [1] = 2, [24] = 3 }, { bar = { 1, 0 } }); roll(u, 3, 4)
    eq(E.legal(u, 1), NOMOVE); r = E.stage(u, 1, {}); eq({ r.done, r.next, r.left }, { true, {}, { 3, 4 } })
    local bo = pos("std", 1, { [2] = 1, [1] = 1 }, { [24] = 15 }); roll(bo, 6, 5)
    eq(E.stage(bo, 1, {}).next, { { 2, 0 } }); r = E.stage(bo, 1, { { 2, 0 } }); eq({ r.done, r.left, r.next }, { false, { 5 }, { { 1, 0 } } })
    eq(E.stage(bo, 1, { { 2, 0 }, { 1, 0 } }).done, true)
  end)
  it("stage: a first step that already ends where a whole move ends is done and may still go on", function()
    local e = pos("std", 1, { [4] = 1, [3] = 1 }, { [12] = 15 }); roll(e, 5, 1)       -- 4/0 lands where 4/3 3/0 does
    local r = E.stage(e, 1, { { 4, 0 } }); eq({ r.done, r.left, r.next }, { true, { 1 }, { { 3, 2 } } })
    ok(E.apply(E.restore(E.snapshot(e)), 1, { k = "move", steps = { { 4, 0 } } }))
    eq(E.stage(e, 1, { { 4, 0 }, { 3, 2 } }).done, true)
    eq(E.stage(e, 1, { { 3, 2 } }).next, { { 4, 0 } }); eq(E.stage(e, 1, { { 3, 2 }, { 4, 0 } }).done, true)
  end)
  it("stage: the cache never answers for another state", function()
    local s = E.new{}; roll(s, 6, 1); roll(s, 3, 1)
    eq(E.stage(s, 1, {}).left, { 3, 1 })
    local t = E.restore(E.snapshot(s)); t.left = { 6, 6, 6, 6 }
    eq(E.stage(t, 1, {}).next, { { 24, 18 }, { 13, 7 }, { 8, 2 } })
    t.left = { 3, 1 }; t.pts[1][8], t.pts[1][7] = 2, 1
    eq(E.stage(t, 1, { { 7, 4 } }) ~= nil, true); eq(E.stage(s, 1, { { 7, 4 } }), nil)
  end)
  it("stage: a mother pin is a whole move with a die left; a cascade number that cannot be finished is whole too", function()
    local mp = pos("tapa", 1, { [4] = 1, [10] = 14 }, { [24] = 1, [20] = 14 }); roll(mp, 3, 5)
    eq(E.stage(mp, 1, {}).next, { { 10, 7 }, { 4, 1 } }); local r = E.stage(mp, 1, { { 4, 1 } }); eq({ r.done, r.left, r.next }, { true, { 5 }, {} })
    eq(r.pin[2][24], 1); eq(E.stage(mp, 1, { { 4, 1 }, { 10, 5 } }), nil)
    local g = pos("gul", 1, { [24] = 1, [12] = 1 }, { [7] = 1, [20] = 14 }, { rolls = { 3, 0 } }); roll(g, 5, 5)
    eq(E.stage(g, 1, {}).next, { { 12, 7 } }); r = E.stage(g, 1, { { 12, 7 } }); eq({ r.done, r.left, r.next }, { false, { 5, 5, 5 }, { { 7, 2 } } })
    r = E.stage(g, 1, { { 12, 7 }, { 7, 2 } }); eq({ r.done, r.left }, { true, { 5, 5 } })
  end)
  it("stage agrees with legal and apply on random positions", function()
    local x = 20261123
    local function rnd(lo, hi) x = (x * 16807) % 2147483647; return lo + x % (hi - lo + 1) end
    local function has(list, st)
      for _, y in ipairs(list) do if y[1] == st[1] and y[2] == st[2] then return true end end
      return false
    end
    local function pk(p)
      return table.concat(p.pts[1], ",") .. "|" .. table.concat(p.pts[2], ",") .. "|" .. table.concat(p.pin[1], ",") ..
        "|" .. table.concat(p.pin[2], ",") .. "|" .. p.bar[1] .. p.bar[2] .. "|" .. p.off[1] .. "," .. p.off[2]
    end
    local games, positions, checked, bad, early = 0, 0, 0, 0, 0
    while games < 30 do
      local s, guard = E.new{}, 0
      while not E.over(s) and guard < 100000 do
        guard = guard + 1
        local a = E.system(s)
        if a and a.need == "dice" then
          if not E.apply(s, 0, { k = "dice", d = { rnd(1, 6), rnd(1, 6) } }) then bad = bad + 1 end
        elseif a then
          if not E.apply(s, 0, a) then bad = bad + 1 end
        else
          local seat = s.turn
          if positions < 400 then
            positions = positions + 1
            -- the positions apply accepts as a whole move: those of the legal moves (every 16th checked by apply)
            local legal, finals = E.legal(s, seat), {}
            for i, m in ipairs(legal) do
              local r = E.stage(s, seat, m.steps)
              if not r or r.done ~= true then bad = bad + 1 else finals[pk(r)] = true end
              if r and (checked + i) % 16 == 0 and pk(after(s, m.steps)) ~= pk(r) then bad = bad + 1 end
            end
            for _, m in ipairs(legal) do
              local pre = {}
              for k = 0, #m.steps - 1 do
                local r = E.stage(s, seat, pre)
                local accepts = r and finals[pk(r)] == true
                if not r or r.done ~= accepts or not has(r.next, m.steps[k + 1]) then
                  bad = bad + 1
                elseif r.done or (checked + k) % 16 == 0 then -- done: a prefix ends where a whole move ends (5-1: 4/0)
                  if r.done then early = early + 1 end
                  if (E.apply(E.restore(E.snapshot(s)), seat, { k = "move", steps = pre }) == true) ~= accepts then
                    bad = bad + 1
                  end
                end
                pre[#pre + 1] = m.steps[k + 1]
              end
              checked = checked + 1
            end
            for _, st in ipairs(E.stage(s, seat, {}).next) do
              if E.stage(s, seat, { st }) == nil then bad = bad + 1 end
            end
          end
          local m = E.auto(s, seat)
          if not E.thrown(s) then bad = bad + 1 end
          if not m or not E.apply(s, seat, m) then bad = bad + 1; break end
          if not E.thrown(s) then bad = bad + 1 end
          if s.phase == "game" or s.phase == "match" then games = games + 1 end
        end
      end
      if not E.over(s) then bad = bad + 1 end
    end
    eq(bad, 0)
    ok(checked >= 1000, "checked " .. checked); ok(early > 0 and early < checked / 100, "early " .. early)
  end)
end)

describe("tabla thrown", function()
  it("the open steps of a turn are what its dice give", function()
    local s = E.new{}; eq(E.thrown(s), 0); ok(E.apply(s, 0, { k = "dice", d = { 5, 2 } })); eq(E.thrown(s), 0)   -- the opening throw: nothing open
    ok(E.apply(s, 0, { k = "dice", d = { 3, 1 } })); eq({ s.phase, s.left }, { "move", { 3, 1 } }); ok(E.thrown(s))
    s.left = { 1, 3 }; ok(not E.thrown(s)); s.left = { 3, 1, 1 }; ok(not E.thrown(s)); s.left = { 6, 6, 6, 6 }; ok(not E.thrown(s))
    s.left = nil; ok(not E.thrown(s)); s.left = { 3, 1 }; s.dice = nil; ok(not E.thrown(s)); s.dice = { 3, 3 }; ok(not E.thrown(s))
    s.left = { 3, 3, 3, 3 }; ok(E.thrown(s)); s.left = { 3, 3, 3 }; ok(not E.thrown(s))
    s.left, s.cv = { 5, 5, 5, 5 }, 5; ok(not E.thrown(s))                                      -- a cascade outside Гюлбара
    s.var = "gul"; ok(not E.thrown(s)); s.rolls[s.turn] = E.CASCADE_ROLL; ok(not E.thrown(s))   -- "gul" is not game 1's variant
    s.game = 3; eq({ E.thrown(s) }, { 2, s.turn, E.CASCADE_ROLL })                             -- only from the roller's fourth roll; two moves on
    s.cv = 2; s.left = { 2, 2, 2, 2 }; ok(not E.thrown(s))                                     -- below the double thrown
    s.cv, s.left = 3, { 3, 3, 3, 3 }; eq(E.thrown(s), 0); s.left = { 3, 3 }; ok(not E.thrown(s))
    s.xfer = true; ok(not E.thrown(s))                                                         -- a remainder: the roller is the other seat
    s.rolls[3 - s.turn] = E.CASCADE_ROLL; eq({ E.thrown(s) }, { 1, 3 - s.turn, E.CASCADE_ROLL }); s.cv, s.left = 5, { 5, 5, 5, 5 }; eq(E.thrown(s), 3)
    s.phase = "roll"; ok(not E.thrown(s)); s.left = nil; eq(E.thrown(s), 0)
  end)
  it("the variant is the game's and the rolls are counts; against my own state of the same throw nothing a throw gives has changed", function()
    local s = E.new{}; ok(E.apply(s, 0, { k = "dice", d = { 5, 2 } })); ok(E.apply(s, 0, { k = "dice", d = { 3, 1 } }))
    eq({ E.thrown(s) }, { 0, 1, 1 })                                                           -- seat 1 threw for this turn, its first roll
    for _, bad in ipairs{ "tapa", "gul", false } do local c = E.restore(E.snapshot(s)); c.var = bad or nil; eq(E.thrown(c), false) end
    for _, g in ipairs{ 2, 3, 0, 1.5, "1" } do local c = E.restore(E.snapshot(s)); c.game = g; eq(E.thrown(c), false) end
    for _, r in ipairs{ -1, 0.5, "1" } do local c = E.restore(E.snapshot(s)); c.rolls[2] = r; eq(E.thrown(c), false) end
    local c = E.restore(E.snapshot(s)); c.rolls = nil; eq(E.thrown(c), false); c = E.restore(E.snapshot(s)); c.turn = 3; eq(E.thrown(c), false)
    c = E.new{}; c.rolls[1] = 3; eq(E.thrown(c), false)                                        -- rolls before the game's first dice
    local prev = E.restore(E.snapshot(s)); eq(E.thrown(s, prev), 0)
    c = E.restore(E.snapshot(s)); c.rolls[2] = 3; eq({ E.thrown(c), E.thrown(c, prev) }, { 0, false })   -- a roll count no throw of mine gave
    c = E.restore(E.snapshot(s)); c.game, c.var = 4, "std"; eq({ E.thrown(c), E.thrown(c, prev) }, { 0, false })   -- another game with these dice
    ok(E.apply(s, 1, E.auto(s, 1))); eq({ s.phase, E.thrown(s, prev) }, { "roll", 0 })           -- a move later: the same throw
    c = E.restore(E.snapshot(s)); c.phase, c.gw = "game", 1; ok(E.apply(c, 0, { k = "next" })); eq({ c.game, c.var, E.thrown(c, prev) }, { 2, "tapa", 0 })   -- the next game: no dice yet
  end)
end)

describe("tabla fuzz", function()
  it("200 games driven only by auto and LCG dice all finish; every match ends", function()
    local x = 20261121
    local function rnd(lo, hi) x = (x * 16807) % 2147483647; return lo + x % (hi - lo + 1) end
    local games, matches, bad, moves = 0, 0, 0, 0
    local seen = { cascade = 0, xfer = 0, pin = 0, hit = 0, mars = 0, std = 0, tapa = 0, gul = 0 }
    while games < 200 do
      local s, guard = E.new{}, 0
      while not E.over(s) and guard < 100000 do
        guard = guard + 1
        local a = E.system(s)
        if a and a.need == "dice" then
          if not E.apply(s, 0, { k = "dice", d = { rnd(1, 6), rnd(1, 6) } }) then bad = bad + 1 end
          if s.cv then seen.cascade = seen.cascade + 1 end
        elseif a then
          if not E.apply(s, 0, a) then bad = bad + 1 end
        else
          local seat = s.turn
          local m = E.auto(s, seat)
          if moves % 97 == 0 then eq(E.snapshot(E.restore(E.snapshot(s))), E.snapshot(s)) end
          if not E.thrown(s) then bad = bad + 1 end
          if not m or not E.apply(s, seat, m) then bad = bad + 1; break end
          if not E.thrown(s) then bad = bad + 1 end
          moves = moves + 1
          if s.xfer and s.turn ~= seat then seen.xfer = seen.xfer + 1 end
          if s.bar[1] + s.bar[2] > 0 then seen.hit = seen.hit + 1 end
          if sum(s.pin[1]) + sum(s.pin[2]) > 0 then seen.pin = seen.pin + 1 end
          for q = 1, 2 do if sum(s.pts[q]) + s.bar[q] + s.off[q] ~= 15 then bad = bad + 1 end end
          if s.phase == "game" or s.phase == "match" then
            games = games + 1; seen[s.var] = seen[s.var] + 1
            if s.gp == 2 then seen.mars = seen.mars + 1 end
          end
        end
      end
      if E.over(s) and E.result(s) and s.score[s.winner] >= 5 then matches = matches + 1 else bad = bad + 1 end
    end
    eq(bad, 0)
    ok(matches >= 200 / 9, "matches " .. matches)
    for k, v in pairs(seen) do ok(v > 0, "never saw " .. k) end
  end)
end)
