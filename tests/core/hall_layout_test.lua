local ns = Loader.ns()
local H = ns.HallLayout

local A = "Иван Петров"

local function near(a, b) return math.abs(a - b) < 1e-6 end

describe("hall layout", function()
  it("hall switches to list above 8 tables", function()
    eq(H.mode(0), "floor"); eq(H.mode(8), "floor"); eq(H.mode(9), "list")
  end)

  it("8 slots are distinct and inside the floor", function()
    local s = H.slots(8, 560, 420)
    eq(#s, 8)
    local seen = {}
    for _, p in ipairs(s) do
      ok(p[1] > 0 and p[1] < 560, "x out of the floor: " .. p[1])
      ok(p[2] > 0 and p[2] < 420, "y out of the floor: " .. p[2])
      local key = p[1] .. "," .. p[2]
      ok(not seen[key], "duplicate slot " .. key)
      seen[key] = true
    end
  end)

  it("column count follows the table count", function()
    local function columns(n)
      local xs, count = {}, 0
      for _, p in ipairs(H.slots(n, 600, 400)) do
        if not xs[p[1]] then xs[p[1]] = true; count = count + 1 end
      end
      return count
    end
    eq(columns(1), 1); eq(columns(3), 3); eq(columns(4), 2); eq(columns(5), 3); eq(columns(6), 3)
    eq(columns(7), 4); eq(columns(8), 4)
    eq(H.slots(1, 600, 400), { { 300, 200 } })
    eq(H.slots(0, 600, 400), {})
  end)

  it("seat 1 is at the top", function()
    local c = H.chairs(2, 40)
    eq(#c, 2)
    ok(near(c[1][1], 0) and near(c[1][2], 40), "seat 1 not at the top")
    ok(near(c[2][1], 0) and near(c[2][2], -40), "seat 2 not at the bottom")
    local q = H.chairs(4, 10)
    ok(near(q[2][1], 10) and near(q[2][2], 0), "seat 2 of 4 not on the right")
  end)

  it("my table comes first, then open, then live", function()
    local r = function(tid, st, s) return { tid = tid, state = st, seats = s } end
    local input = { r("b#2", "live", { A, false }), r("c#3", "open", { "X", false }), r("a#1", "live", { "X", "Y" }), r("d#4", "open", { "Z", false }) }
    local out = H.order(input, A)
    eq({ out[1].tid, out[2].tid, out[3].tid, out[4].tid }, { "b#2", "c#3", "d#4", "a#1" })
    eq(input[3].tid, "a#1") -- the input list is left alone
  end)
end)
