local _, ns = ...

-- The games the tavern knows, in hall order, with their player counts, and the
-- per-game table options. A game in ORDER is listed but playable only when it
-- is in PLAYABLE and has an engine; the rest are listed but not playable.
-- Engines load after core/, so they are looked up at call time only.
local Games = {}
ns.Games = Games

Games.ORDER = { "ttt", "deathroll", "santase", "belot", "tabla", "holdem", "chess" }
Games.PLAYERS = { ttt = "2", deathroll = "2–5", santase = "2", belot = "4", tabla = "2", holdem = "2–6", chess = "2" }

-- A game in ORDER is playable only once its integration stage lands. Every
-- game of ORDER is integrated now (santase: stage B, belot: C, tabla: D,
-- holdem: E, chess: the chess plan); the gate stays for a game added later, whose engine may exist
-- before it can be offered (it would broadcast hidden cards and wait for a deck).
-- Ids not in ORDER (test engines) are always looked up.
Games.PLAYABLE = { ttt = true, deathroll = true, santase = true, belot = true, tabla = true, holdem = true, chess = true }

local inOrder = {}
for _, id in ipairs(Games.ORDER) do inOrder[id] = true end

-- The engine of game `id`, or nil.
function Games.engine(id)
  if type(id) ~= "string" or not ns.Engines then return nil end
  if inOrder[id] and not Games.PLAYABLE[id] then return nil end
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

-- The options of `engine` a table takes: one with `at = "stake"` only at a
-- staked table, one with `at = "fun"` only at a table for fun (Холдем: the
-- rebuy mode, the starting stack), every other always.
local function offered(engine, staked)
  local out = {}
  for _, o in ipairs(engine.options or {}) do
    assert(o.at == nil or o.at == "fun" or o.at == "stake", "option at: fun, stake or nothing")
    if o.at == nil or (o.at == "stake") == (staked == true) then out[#out + 1] = o end
  end
  return out
end

-- `opt` checked against the engine's options for a table staked or not ->
-- a new table with every option of that table set (the given value or the
-- default), or nil when the engine is unknown, `opt` is not a table, or a key
-- or value is not one that table offers.
function Games.resolve(id, opt, staked)
  local engine = Games.engine(id)
  if not engine or (opt ~= nil and type(opt) ~= "table") then return nil end
  local options = offered(engine, staked)
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
