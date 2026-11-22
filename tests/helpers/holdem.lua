-- Hold'em engine test helpers, shared: require("holdem")(E) with the engine of the test's namespace.
--   deckFor(s, holes, board) -> the full deck of the current hand: holes = {[seat] = "AS KD"}, board = five
--                               faces (flop turn river), every other card in E.DECK order
--   apply(s, seat, a)        -> E.apply that must be taken
--   checkdown(s)             -> to the end of the hand: every street and showdown dealt, every bettor checks
--                               (or calls what it faces)
return function(E)
  local M = {}

  local function split(str) local t = {} for c in str:gmatch("%S+") do t[#t + 1] = c end return t end

  function M.deckFor(s, holes, board)
    local n, d, used = #s.order, {}, {}
    local function put(i, f) assert(not used[f], "duplicate " .. f); d[i] = f; used[f] = true end
    for j, seat in ipairs(s.order) do
      if holes[seat] then local c = split(holes[seat]); put(j, c[1]); put(n + j, c[2]) end
    end
    if board then
      local b, pos = split(board), { 2 * n + 2, 2 * n + 3, 2 * n + 4, 2 * n + 6, 2 * n + 8 }
      for k, i in ipairs(pos) do put(i, b[k]) end
    end
    local r = 1
    for i = 1, 52 do
      if not d[i] then
        while used[E.DECK[r]] do r = r + 1 end
        put(i, E.DECK[r])
      end
    end
    return d
  end

  function M.apply(s, seat, a)
    local r, why = E.apply(s, seat, a)
    ok(r, "seat " .. seat .. " " .. tostring(a.k) .. " rejected: " .. tostring(why))
  end

  function M.checkdown(s)
    while E.inHand(s) do
      if s.phase == "bet" then M.apply(s, s.turn, { k = s.bet > s.p[s.turn].bet and "call" or "check" })
      else M.apply(s, 0, (E.system(s))) end
    end
  end

  return M
end
