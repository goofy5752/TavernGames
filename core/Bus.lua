local _, ns = ...

-- In-memory message bus (tests and bot mode). Recipients are resolved at send
-- time, each delivery is queued as its own deep copy, and flush() delivers FIFO.
local Bus = {}
Bus.__index = Bus
ns.Bus = Bus

function Bus.new()
  -- filter(from, to, channel, msg) -> list of msgs to deliver; nil means { msg }
  return setmetatable({ members = {}, order = {}, queue = {}, head = 1, filter = nil }, Bus)
end

function Bus:join(name, receive)
  if not self.members[name] then self.order[#self.order + 1] = name end
  self.members[name] = receive
end

function Bus:leave(name)
  if not self.members[name] then return end
  self.members[name] = nil
  for i = #self.order, 1, -1 do
    if self.order[i] == name then table.remove(self.order, i) end
  end
end

local function enqueue(self, from, to, channel, msg)
  local copy = ns.Util.copy
  local out = self.filter and self.filter(from, to, channel, copy(msg)) or { msg }
  for i = 1, #out do
    self.queue[#self.queue + 1] = { from = from, to = to, channel = channel, msg = copy(out[i]) }
  end
end

-- GUILD goes to every joined name except `from`; WHISPER only to a joined `target`.
function Bus:send(from, channel, target, msg)
  if channel == "GUILD" then
    for i = 1, #self.order do
      local name = self.order[i]
      if name ~= from then enqueue(self, from, name, channel, msg) end
    end
  elseif channel == "WHISPER" and self.members[target] then
    enqueue(self, from, target, channel, msg)
  end
end

-- Delivers until the queue is empty, including messages sent while delivering.
-- A flush called from inside a delivery returns at once; the outer one goes on.
function Bus:flush()
  if self.flushing then return end
  self.flushing = true
  local ok, err = pcall(function()
    while self.head <= #self.queue do
      local item = self.queue[self.head]
      self.head = self.head + 1
      local receive = self.members[item.to]
      if receive then receive(item.channel, item.from, item.msg) end
    end
  end)
  self.flushing = false
  if not ok then error(err, 0) end -- the rest stays queued for the next flush
  self.queue, self.head = {}, 1
end
