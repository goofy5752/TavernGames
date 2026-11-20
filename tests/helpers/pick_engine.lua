-- Test-only engine "pick": 2-4 seats, started by the host, option goal (2 or 3).
-- {k="inc", by} by the seat on turn adds `by` to n[seat]; reaching the goal wins,
-- else the turn passes to the next seat in `players`. Extension "picktest"
-- rewrites every member ACT to {k="inc", by=1} (drops {k="drop"}) and logs
-- every applied event's k in session.appliedLog; "absent" is never registered.
local Sim = require("sim")
local copy = Sim.ns.Util.copy

local E = {
  id = "pick", minSeats = 2, maxSeats = 4, start = "host", ext = { "picktest", "absent" },
  options = { { id = "goal", choices = { 2, 3 }, default = 2 } },
}

-- The seat after `seat` in `players`, cyclic.
local function nextOf(players, seat)
  for i = 1, #players do
    if players[i] == seat then return players[i % #players + 1] end
  end
end

function E.new(opts)
  local players = {}
  for i = 1, #opts.seats do
    if opts.seats[i] then players[#players + 1] = i end
  end
  return { players = players, turn = opts.first, n = { 0, 0, 0, 0 }, goal = opts.opt.goal, winner = nil }
end

function E.apply(s, seat, a)
  if type(a) ~= "table" or a.k ~= "inc" or type(a.by) ~= "number" then return nil, "action" end
  if s.turn == nil or seat ~= s.turn then return nil, "turn" end
  s.n[seat] = s.n[seat] + a.by
  if s.n[seat] >= s.goal then
    s.winner, s.turn = seat, nil
  else
    s.turn = nextOf(s.players, seat)
  end
  return true
end

function E.leave(s, seat)
  for i = 1, #s.players do
    if s.players[i] == seat then
      if s.turn == seat then s.turn = #s.players > 1 and nextOf(s.players, seat) or nil end
      table.remove(s.players, i)
      return
    end
  end
end

function E.result(s)
  if not s.winner then return nil end
  local losers = {}
  for i = 1, #s.players do
    if s.players[i] ~= s.winner then losers[#losers + 1] = s.players[i] end
  end
  return { winners = { s.winner }, losers = losers }
end

function E.nextFirst(prev, occupied)
  if prev.winner and occupied[prev.winner] then return prev.winner end
end

function E.legal(s, seat) return seat == s.turn and { { k = "inc", by = 1 } } or {} end
function E.auto(s, seat, random) if seat == s.turn then return { k = "inc", by = random(1, 1) } end end
function E.system() return nil end
E.snapshot, E.restore = copy, copy

Sim.ns.Engines.pick = E

Sim.ns.Ext.picktest = {
  act = function(_, _, a)
    if a.k == "drop" then return nil end
    return { k = "inc", by = 1 }
  end,
  applied = function(s, _, a)
    s.appliedLog = s.appliedLog or {}
    s.appliedLog[#s.appliedLog + 1] = a.k
  end,
}

return E
