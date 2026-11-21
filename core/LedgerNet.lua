local _, ns = ...

-- The live side of the gold ledger (core/LedgerStore.lua; sending: core/LedgerSend.lua).
-- * net:make: my entry, added at once; it leaves with the ones I make within
--   LEDGER_COALESCE s as GUILD LEVs of at most 4, never while I am in an
--   instance. For LEDGER_ADOPT_WAIT s after a login (or until net:settle) my
--   entries, my denials among them, wait in store.pending (core/LedgerQueue.lua:
--   saved, per character, replayed once), so my next id is above
--   whatever the guild holds. My X entries leave at most LEDGER_DENY_RATE a minute.
-- * net:take: a valid entry whose author and names in f/t/n are guild members
--   (env.member; absent = all) or authors in my store. A live GUILD LEV is 1..4
--   entries of its sender, else dropped whole. "ledger" is emitted once a moment.
-- * An entry under my name that I did not hold moves my counter above it, and:
--   in the adoption window (a store without my record at load, closed with the
--   login queue) it is kept as mine, unless it is too far above my counter
--   (then denied once the window closes). Else, at an id I made in this run
--   (a collision: a crash, another computer) it is put to me, and my own body,
--   if it has not left yet, is made again under a fresh id. Else when its
--   number is at most my saved seq (the store's at login), I held its id or it
--   is too far, it is forged and I deny it (an X that points at the stored
--   body). Else a crash lost it: kept uncounted (`un`, a local field the view
--   and the denials skip) and put to me, one question per entry (net:asks,
--   net:answer, "mineAsk"); past LEDGER_MINE_ASK open questions it waits unshown.
local Ledger, C = ns.Ledger, ns.Const

local Net = {}; Net.__index = Net
ns.LedgerNet = Net
Net.LIVE_MAX = 4

function Net.new(client, ledger)
  return setmetatable({ client = client, L = ledger, running = false, out = {}, denials = {}, deniedAt = {},
    made = {} }, Net)
end

-- fn(self) in `seconds`, unless the timer named `field` is armed already.
function Net:arm(field, seconds, fn)
  if self[field] then return end
  self[field] = self.client:after(seconds, function()
    self[field] = nil
    fn(self)
  end)
end

-- "ledger" (and "mineAsk" when the question changed) once, at the end of this moment.
function Net:changed()
  self:arm("emitTimer", 0, function()
    self.client.events:emit("ledger")
    if self.asked then self.asked = nil; self.client.events:emit("mineAsk") end
  end)
end

-- After a login: my record (seq 0 when missing), the saved seq, the window of a
-- new store and the queue of my own entries, both closed by net:settle.
function Net:start()
  if self.running then return end
  local L = self.L
  self.running = true
  L.adopting = L.fresh and not self.began -- a new store: once per client
  self.began = true
  self.saved = L:record().seq
  self.waiting = true
  self:pending()
  self:arm("settleTimer", C.LEDGER_ADOPT_WAIT, Net.settle)
  if #self:asks() > 0 then self.asked = true; self:changed() end -- still unanswered from before
end

-- My entries of the last seconds still go out; the login queue stays saved.
function Net:stop()
  if not self.running then return end
  self:flush()
  self.running = false
  self.out, self.denials = {}, {}
  self.outTimer, self.denyTimer, self.emitTimer, self.settleTimer = nil, nil, nil, nil
end

-- Is the adoption window of a new store open?
function Net:adopting() return self.L.adopting == true end

-- My new entry -> entry | "queued" | nil, reason ("stopped", or a reason of L:make).
-- The entry may still move to a fresh id before it leaves (Net:collide): keep its content, not its i.
function Net:make(kind, fields)
  if not self.running then return nil, "stopped" end
  if self.waiting then self:queue(kind, fields); return "queued" end
  local e, why = self.L:make(kind, fields)
  if not e then return nil, why end
  self.made[select(2, Ledger.author(e.i))] = e
  local deny = kind == "X"
  local list = deny and self.denials or self.out
  list[#list + 1] = Ledger.wire(e)
  self:arm(deny and "denyTimer" or "outTimer", C.LEDGER_COALESCE, deny and Net.pump or Net.flush)
  self:changed()
  return e
end

-- My X of body b.
function Net:deny(b) return self:make("X", { r = b.i, h = b.h }) end

-- May my store take an entry naming these people? A member or a known author.
function Net:allowed(e, author)
  local member, L = self.client.env.member, self.L
  if not member then return true end
  local function known(name) return name == false or name == L.me or L:seen(name) > 0 or member(name) end
  if not known(author) or (e.f ~= nil and not known(e.f)) or (e.t ~= nil and not known(e.t)) then return false end
  for _, name in ipairs(type(e.n) == "table" and e.n or {}) do if not known(name) then return false end end
  return true
end

-- Another body came under the id of `mine`, which I made in this run: if mine
-- has not left yet, it is dropped and made again under a fresh id (the same
-- content); once it has left it stays (both count), never denied.
function Net:collide(mine)
  for j, w in ipairs(self.out) do
    if w.i == mine.i then
      table.remove(self.out, j)
      local a, n = Ledger.author(mine.i)
      self.L:move(a, n, mine, true)
      self.made[n] = nil
      local fields = Ledger.wire(mine)
      fields.i, fields.k, fields.at = nil, nil, nil
      return self:make(mine.k, fields)
    end
  end
end

-- Puts body b to me: uncounted until answered, never denied unasked.
function Net:ask(b) b.un, self.L.rev, self.asked = true, self.L.rev + 1, true end

-- The own-name check of body b, number n, new in my store (held: I held its id before).
function Net:own(b, n, held)
  local L = self.L
  local near, mine = L:bump(n), self.made[n] -- my counter is above it already (L:add), unless n is too far
  if L.adopting then
    if not near then self:deny(b) end -- waits in the login queue until the window has closed
  elseif mine and L:has(mine.i, mine.h) then
    self:ask(b)
    self:collide(mine)
  elseif not near or held or n <= self.saved then
    self:deny(b)
  else
    self:ask(b)
  end
end

-- An entry from the net, got from `from`; `live`: in a live LEV, where every
-- entry is its sender's own -> "new" | "dup" | "twin" | nil.
function Net:take(e, from, live)
  if not self.running or type(e) ~= "table" or type(from) ~= "string" then return nil end
  local L = self.L
  if not Ledger.valid(e, L.epoch()) then return nil end
  local author, n = Ledger.author(e.i)
  if (live and author ~= from) or not self:allowed(e, author) then return nil end
  local rev, held = L.rev, author == L.me and L:has(e.i)
  local status, b = L:add(e, from)
  if not status then return nil end
  if status ~= "dup" and author == L.me then self:own(b, n, held) end
  if L.rev ~= rev then self:changed() end
  return status
end

-- A message the client got: a live GUILD LEV (a whispered one is the sync's).
function Net:receive(channel, sender, msg)
  if channel ~= "GUILD" or msg.t ~= "LEV" or type(msg.ev) ~= "table" then return end
  local count = 0
  for _ in pairs(msg.ev) do count = count + 1 end
  if count < 1 or count > Net.LIVE_MAX or #msg.ev ~= count then return end
  for _, e in ipairs(msg.ev) do if type(e) ~= "table" or Ledger.author(e.i) ~= sender then return end end
  for _, e in ipairs(msg.ev) do self:take(e, sender, true) end
end

-- My entries the guild holds that my store had lost (a crash, a collision),
-- one question each: {body, ...} (the first LEDGER_MINE_ASK, by id), and how
-- many more wait unshown (uncounted, not denied) until a question is answered.
function Net:asks()
  local out, more = {}, 0
  for _, b in ipairs(self.L:above(self.L.me, 0)) do
    if b.un and #out < C.LEDGER_MINE_ASK then out[#out + 1] = b elseif b.un then more = more + 1 end
  end
  return out, more
end

-- The answer for one shown asked entry (a body of net:asks, or an id: its asked
-- bodies), or for all shown (answer(keep)): keep, it is mine and counts; else
-- one X -> true | nil (nothing of it was asked).
function Net:answer(which, keep)
  if type(which) == "boolean" then which, keep = nil, which end
  local list = {}
  for _, b in ipairs(self.running and self:asks() or {}) do
    if which == nil or which == b or which == b.i then list[#list + 1] = b end
  end
  if #list == 0 then return nil end
  for _, b in ipairs(list) do b.un = nil end
  self.L.rev, self.asked = self.L.rev + 1, true
  if not keep then for _, b in ipairs(list) do self:deny(b) end end
  self:changed()
  return true
end

return Net
