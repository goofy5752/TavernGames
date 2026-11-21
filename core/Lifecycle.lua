local _, ns = ...

-- The game lifecycle of a table session (core/Session.lua), installed on the
-- Session metatable: the engine's extensions (ns.Ext, see Session:hook), a new
-- game from the occupied seats, the "result" event, and the entry points
-- startGame (games with engine.start == "host"; Session:startIfFull never
-- starts those; its checks are Session:canStart and Session:gameOver, shared
-- with the bots and the table frame) and playAuto. Session:apply calls newGame and noteResult;
-- Session:onAct passes a member's action through filterAct before playing it;
-- a new host (core/Succession.lua) applies its catch-up events with applyUnsent.
local Session = ns.Session
local copy = ns.Util.copy

-- Extensions ns.Ext[x], x in engine.ext (a name not registered is skipped): hook
-- calls `name` on every one that has it and returns the first non-nil result;
-- filterAct passes a member's action through their act hooks until one drops it.
-- Hooks: act, applied, auto (see the shared contracts), adopted(s, prevState)
-- after a snapshot replaced my state, hostChanged(s) when my table changed host.
-- A hook that raises counts as nil: the error goes to env.log ("error", "ext",
-- "<ext>.<hook>", message), so it cannot cut short the request, event or
-- snapshot handling around it (e.g. the sitter's SNP after a sit).
function Session:hook(name, ...)
  local ext, out = self:engine().ext or {}, nil
  for i = 1, #ext do
    local x = ns.Ext[ext[i]]
    local r = nil
    if x and x[name] then
      local ok, got = pcall(x[name], self, ...)
      if ok then
        r = got
      else
        local env = self.client.env
        if env.log then env.log("error", "ext", ext[i] .. "." .. name, tostring(got)) end
      end
    end
    if out == nil then out = r end
  end
  return out
end

-- An event a new host orders for itself before its snapshots go out (the old
-- host's stand that never reached it, the abort of a short table): applied and
-- counted without being sent, then the extensions' `applied`. -> true | nil
function Session:applyUnsent(seat, a)
  if not self:apply(seat, a) then return nil end
  self.seq = self.seq + 1
  self:hook("applied", seat, a)
  return true
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

-- The game has ended and the next may start -> bool: any truthy engine.over,
-- else a known result; false without a state.
function Session:gameOver()
  local engine, state = self:engine(), self.state
  if not state then return false end
  if engine.over then return engine.over(state) and true or false end
  return engine.result ~= nil and engine.result(state) ~= nil
end

-- Would startGame start the next game now -> true | nil, code: "nothost",
-- "mode" (the game starts by itself), "short" (fewer than minSeats seated),
-- "live" (a game is running and not over). The checks of startGame, no effect.
function Session:canStart()
  if self.role ~= "host" then return nil, "nothost" end
  local engine = self:engine()
  if engine.start ~= "host" then return nil, "mode" end
  if self:seatedCount() < engine.minSeats then return nil, "short" end
  if self.status == "live" and not self:gameOver() then return nil, "live" end
  return true
end

-- Host of a game the host starts: the next game begins -> true | nil, code:
-- "none" (no table), else a code of Session:canStart.
function Session.startGame(client)
  local s = client.session
  if not s then return nil, "none" end
  local can, code = s:canStart()
  if not can then return nil, code end
  local engine = s:engine()
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
