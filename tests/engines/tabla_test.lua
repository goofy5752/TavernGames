local E = Loader.ns().Engines.tabla

local function arr(m) local t = {} for i = 1, 24 do t[i] = (m and m[i]) or 0 end return t end
local function sum(t) local n = 0 for i = 1, 24 do n = n + t[i] end return n end

describe("tabla start", function()
  it("Обикновена start: 2 on 24, 5 on 13, 3 on 8, 5 on 6 for both seats; opening roll first", function()
    local s = E.new{}
    eq(s.var, "std"); eq(s.game, 1); eq(s.phase, "open")
    eq(s.pts[1], arr{[24]=2, [13]=5, [8]=3, [6]=5}); eq(s.pts[2], s.pts[1])
    eq(s.bar, {0,0}); eq(s.off, {0,0}); eq(s.score, {0,0})
    eq({E.system(s)}, {{k="need", r="open"}, 0})
  end)
  it("opening roll: tie rolls again, the higher die starts and rolls anew", function()
    local s = E.new{}
    ok(E.apply(s, 0, {k="dice", d={4,4}})); eq(s.phase, "open"); eq(s.turn, nil)
    ok(E.apply(s, 0, {k="dice", d={2,5}})); eq(s.phase, "roll"); eq(s.turn, 2)
    eq({E.system(s)}, {{k="need", r="roll", s=2}, 0})
    ok(E.apply(s, 0, {k="dice", d={3,1}})); eq(s.phase, "move"); eq(s.left, {3,1}); eq(s.dice, {3,1})
  end)
end)
