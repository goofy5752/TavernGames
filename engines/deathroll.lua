local _, ns = ...
ns.Engines = ns.Engines or {}

-- Death Roll: the players take turns rolling 1..max; each roll becomes the new
-- max, and whoever rolls 1 loses. The host starts every game; the rolls come
-- from the "rolls" extension (server roll seen, claimed, asked for, or a
-- timeout's local roll, see E.SOURCES), the players share a group ("party").
-- At most 5 players (Const.PARTY_SIZE) so everyone fits one WoW party; the addon never converts a group to a raid.
-- A staked game (opts.staked: state.staked) takes only rolls the host saw
-- (src "seen") and has no automatic roll; a seat that stays on turn instead
-- is stood up by the host (E.idle, core/Stakes.lua).
local E = {
  id = "deathroll", minSeats = 2, maxSeats = 5, start = "host", needsGroup = true, stakes = true, idle = true,
  ext = { "rolls", "party" },
  options = { { id = "start", choices = { 100, 1000, 10000, 100000 }, default = 1000 } },
  SOURCES = { seen = true, claim = true, ask = true, timeout = true },
}
ns.Engines.deathroll = E

local copy = ns.Util.copy

-- The seat after `seat` in `players`, cyclic.
local function nextOf(players, seat)
  for i = 1, #players do
    if players[i] == seat then return players[i % #players + 1] end
  end
end

function E.new(opts)
  local seats = opts and opts.seats or {}
  local players = {}
  for i = 1, #seats do
    if seats[i] then players[#players + 1] = i end
  end
  local first = opts and opts.first
  local start = opts and opts.opt and opts.opt.start or 1000
  return {
    players = players, turn = (first and seats[first]) and first or players[1],
    start = start, max = start, rolls = {}, phase = "play", loser = nil,
    staked = (opts and opts.staked) or nil,
  }
end

function E.apply(s, seat, a)
  if type(a) ~= "table" or a.k ~= "roll" then return nil, "action" end
  if s.phase ~= "play" then return nil, "phase" end
  if s.turn == nil or seat ~= s.turn then return nil, "turn" end
  if a.max ~= s.max then return nil, "max" end
  local n = a.n
  if type(n) ~= "number" or n % 1 ~= 0 or n < 1 or n > s.max then return nil, "n" end
  if not E.SOURCES[a.src] or (s.staked and a.src ~= "seen") then return nil, "src" end
  s.rolls[#s.rolls + 1] = { seat = seat, n = n, max = s.max, src = a.src }
  if n == 1 then
    s.phase, s.loser, s.turn = "over", seat, nil
  else
    s.max = n
    s.turn = nextOf(s.players, seat)
  end
  return true
end

function E.legal(s, seat)
  if s.phase == "play" and s.turn == seat then return { { k = "roll", max = s.max } } end
  return {}
end

function E.auto(s, seat, random)
  if s.phase ~= "play" or s.turn ~= seat or s.staked then return nil end
  return { k = "roll", n = (random or math.random)(1, s.max), max = s.max, src = "timeout" }
end

function E.system() return nil end

-- A seat leaves: fewer than two players left ends the game without a loser;
-- the turn of the leaving seat passes to the player after it.
function E.leave(s, seat)
  for i = 1, #s.players do
    if s.players[i] == seat then
      local after = nextOf(s.players, seat)
      table.remove(s.players, i)
      if s.phase == "play" then
        if #s.players < 2 then
          s.phase, s.loser, s.turn = "over", nil, nil
        elseif s.turn == seat then
          s.turn = after
        end
      end
      return
    end
  end
end

-- Seat is still in this game -> bool: it was seated at the start and has not
-- left. A chair someone else took after its player left is not, so its rolls
-- and the loss belong to nobody seated now.
function E.playing(s, seat)
  for i = 1, #s.players do
    if s.players[i] == seat then return true end
  end
  return false
end

-- The loser and everyone else still playing, once someone rolled 1; nil once
-- the loser has left the table.
function E.result(s)
  if s.phase ~= "over" or not s.loser or not E.playing(s, s.loser) then return nil end
  local winners = {}
  for i = 1, #s.players do
    if s.players[i] ~= s.loser then winners[#winners + 1] = s.players[i] end
  end
  return { losers = { s.loser }, winners = winners }
end

-- Over with or without a loser (everyone else left): a new game may start.
function E.over(s) return s.phase == "over" end

-- The loser rolls first in the next game while still seated (never left).
function E.nextFirst(prev, occupied)
  if prev and prev.loser and occupied[prev.loser] and E.playing(prev, prev.loser) then return prev.loser end
  return nil
end

function E.snapshot(s) return copy(s) end
function E.restore(t) return copy(t) end

return E
