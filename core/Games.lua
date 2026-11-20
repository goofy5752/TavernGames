local _, ns = ...

-- The games the tavern knows, in hall order, with their player counts, and the
-- per-game table options. A game without an engine here is listed but not
-- playable. Engines load after core/, so they are looked up at call time only.
local Games = {}
ns.Games = Games

Games.ORDER = { "ttt", "deathroll", "santase", "belot", "tabla", "holdem" }
Games.PLAYERS = { ttt = "2", deathroll = "2–6", santase = "2", belot = "4", tabla = "2", holdem = "2–9" }

-- The engine of game `id`, or nil.
function Games.engine(id)
  if type(id) ~= "string" or not ns.Engines then return nil end
  return ns.Engines[id]
end

-- { {id, players, engine = E|nil}, ... } in ORDER.
function Games.list()
  local out = {}
  for i, id in ipairs(Games.ORDER) do
    out[i] = { id = id, players = Games.PLAYERS[id], engine = Games.engine(id) }
  end
  return out
end

local function option(options, id)
  for i = 1, #options do
    if options[i].id == id then return options[i] end
  end
  return nil
end

local function offers(choices, value)
  for i = 1, #choices do
    if choices[i] == value then return true end
  end
  return false
end

-- `opt` checked against the engine's options -> a new table with every option
-- set (the given value or the default), or nil when the engine is unknown,
-- `opt` is not a table, or a key or value is not one the engine offers.
function Games.resolve(id, opt)
  local engine = Games.engine(id)
  if not engine or (opt ~= nil and type(opt) ~= "table") then return nil end
  local options = engine.options or {}
  for k, v in pairs(opt or {}) do
    local o = option(options, k)
    if not o or not offers(o.choices, v) then return nil end
  end
  local out = {}
  for i = 1, #options do
    local o = options[i]
    local v = opt and opt[o.id]
    if v == nil then v = o.default end
    out[o.id] = v
  end
  return out
end
