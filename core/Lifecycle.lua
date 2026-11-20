local _, ns = ...

-- The game lifecycle of a table session (core/Session.lua), installed on the
-- Session metatable: the engine's extensions (ns.Ext, see Session:hook), a new
-- game from the occupied seats, the "result" event, and the entry points
-- startGame (games with engine.start == "host"; Session:startIfFull never
-- starts those) and playAuto. Session:apply calls newGame and noteResult;
-- Session:onAct passes a member's action through filterAct before playing it.
local Session = ns.Session
local copy = ns.Util.copy

-- Extensions ns.Ext[x], x in engine.ext (a name not registered is skipped): hook
-- calls `name` on every one that has it and returns the first non-nil result;
-- filterAct passes a member's action through their act hooks until one drops it.
function Session:hook(name, ...)
  local ext, out = self:engine().ext or {}, nil
  for i = 1, #ext do
    local x = ns.Ext[ext[i]]
    local r = x and x[name] and x[name](self, ...)
    if out == nil then out = r end
  end
  return out
end

function Session:filterAct(seat, a)
  local ext = self:engine().ext or {}
  for i = 1, #ext do
    local x = ns.Ext[ext[i]]
    if a ~= nil and x and x.act then a = x.act(self, seat, a) end
  end
  return a
end

-- Seat -> true when occupied, and the lowest occupied seat.
local function occupied(seats)
  local out, lowest = {}, nil
  for i = 1, #seats do
    out[i] = seats[i] ~= false
    lowest = lowest or (out[i] and i or nil)
  end
  return out, lowest
end

-- The engine state of a new game: `first` when that seat is occupied, else the
-- lowest occupied seat begins.
function Session:newGame(first)
  local seats, lowest = occupied(self.seats)
  return self:engine().new({ first = seats[first] and first or lowest, seats = seats, opt = copy(self.opt) })
end

-- The engine's result turned from nil to a value: event "result" (once).
function Session:noteResult()
  local engine = self:engine()
  local r = self.state and engine.result and engine.result(self.state)
  if r and not self.resultSeen then
    self.client.events:emit("result", {
      tid = self.tid, game = self.game, opt = copy(self.opt), seats = copy(self.seats),
      winners = copy(r.winners), losers = copy(r.losers), at = self.client.env.epoch(),
    })
  end
  self.resultSeen = r and true or false
end

-- A game has ended and the next may start: engine.over, else a result is known.
local function over(engine, state)
  if engine.over then return engine.over(state) end
  return engine.result ~= nil and engine.result(state) ~= nil
end

-- Host of a game the host starts: the next game begins -> true | nil, code:
-- "none", "nothost", "mode" (the game starts by itself), "short" (fewer than
-- minSeats seated), "live" (a game is running and not over).
function Session.startGame(client)
  local s = client.session
  if not s then return nil, "none" end
  if s.role ~= "host" then return nil, "nothost" end
  local engine = s:engine()
  if engine.start ~= "host" then return nil, "mode" end
  if s:seatedCount() < engine.minSeats then return nil, "short" end
  if s.status == "live" and not over(engine, s.state) then return nil, "live" end
  local seats, first = occupied(s.seats)
  if engine.nextFirst and s.state then first = engine.nextFirst(s.state, seats) or first end
  s:event(0, { k = "start", first = first })
  s:recordChanged()
  return true
end

-- My automatic move -> true | nil, code as Session.act ("turn": none to make).
-- An extension's auto hook may make it instead.
function Session.playAuto(client)
  local s = client.session
  if not s then return nil, "none" end
  if not s.mySeat then return nil, "seat" end
  if s.status ~= "live" then return nil, "live" end
  if s:hook("auto") then return true end
  local a = s:engine().auto(s.state, s.mySeat, client.env.random)
  if not a then return nil, "turn" end
  return Session.act(client, a)
end
