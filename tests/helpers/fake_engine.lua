-- Test-only engine "fake": 2-3 seats, {k="inc"} by the seat on turn adds 1 to
-- state.n, turns rotate 1 -> 2 -> 3, the match never ends.
local Sim = require("sim")
local copy = Sim.ns.Util.copy

local E = { id = "fake", minSeats = 2, maxSeats = 3 }

function E.new() return { n = 0, turn = 1 } end

function E.apply(s, seat, a)
  if type(a) ~= "table" or a.k ~= "inc" then return nil, "action" end
  if seat ~= s.turn then return nil, "turn" end
  s.n, s.turn = s.n + 1, s.turn % 3 + 1
  return true
end

function E.legal(s, seat) return seat == s.turn and { { k = "inc" } } or {} end
function E.auto(s, seat) if seat == s.turn then return { k = "inc" } end end
function E.system() return nil end
E.snapshot, E.restore = copy, copy

Sim.ns.Engines.fake = E
return E
