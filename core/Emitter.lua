local _, ns = ...

local Emitter = {}
Emitter.__index = Emitter
ns.Emitter = Emitter

function Emitter.new()
  return setmetatable({ handlers = {} }, Emitter)
end

function Emitter:on(event, fn)
  local list = self.handlers[event]
  if not list then list = {}; self.handlers[event] = list end
  list[#list + 1] = fn
end

-- Handlers added while emitting run from the next emit on.
function Emitter:emit(event, ...)
  local list = self.handlers[event]
  if not list then return end
  local snapshot = {}
  for i = 1, #list do snapshot[i] = list[i] end
  for i = 1, #snapshot do snapshot[i](...) end
end
