local _, ns = ...

-- The whispered sync of the gold ledger, one exchange as asker and one as responder
-- at a time. A, the byte-lower of a pair whose HI.ld differ, waits LEDGER_JITTER_MIN
-- + (byte sum of me .. peer .. ld) % 16 s (never env.random), checks again, sends
-- LVC {a = vector}. P (serving nobody else) queues L:above(author, A.n) of each
-- author whose x differs or A lacks, first answering LVC {a, r = true}: its n, x
-- where A is not behind or P lacks the author. A queues L:above(author, P.n) where
-- ahead; equal n: LID {au, l} (at most LEDGER_LID_AUTHORS), l the "<seq>.<h6>" of
-- its bodies above n and at ids it holds twins for. Each side queues its bodies of
-- that scope (and at the ids a list names) that the other's list lacks; P answers
-- LID {r = true}. Equal lists: a twin inside the run, A sends its whole list once.
-- A LEV: <= LEDGER_BATCH entries, BATCH_BYTES packed; one per LEDGER_SEND_GAP s
-- (_BUSY at my live table), after the previous whisper has left (env.send's done).
-- f = true on a side's last (A's once P spoke and its LIDs are answered; P's after
-- A's f when it answered with a vector). The end: both f, or LEDGER_SYNC_TIMEOUT s
-- without a word of the partner or a whisper of mine; net:settle(), and a changed
-- digest gives one GUILD HI (one per LEDGER_HI_GAP s). Pages <= PAGE packed bytes,
-- m = true but on the last. <= LEDGER_EXCHANGE_MAX entries sent and taken. A LEV of
-- another author than its sender only inside an exchange with it. Nothing goes out
-- in an instance; an unlisted sender is ignored.
local Ledger, C, Util = ns.Ledger, ns.Const, ns.Util
local Net = ns.LedgerNet
local byteLess, inInstance = Util.byteLess, Net.inInstance

local Sync = {}; Sync.__index = Sync
ns.LedgerSync = Sync
Sync.PAGE, Sync.BATCH_BYTES = 1500, 1140
Sync.arm = Net.arm -- fn(self) in seconds, unless the timer `field` is armed

function Sync.new(client, ledger, net)
  return setmetatable({ client = client, L = ledger, net = net, by = {}, wait = {}, last = {}, out = {}, missed = {},
    stats = { sent = 0, got = 0 } }, Sync)
end

local function name(v) return type(v) == "string" and v ~= "" and #v <= 64 and not v:find("[|,]") end
local function cell(v) return type(v) == "table" and type(v.n) == "number" and v.n >= 0 and v.n == math.floor(v.n)
  and type(v.x) == "string" and #v.x == 6 and v.x:find("^[0-9a-f]+$") ~= nil end
local function item(b) return select(2, Ledger.author(b.i)) .. "." .. b.h:sub(1, 6) end
local function sorted(t) local out = {} for k in pairs(t) do out[#out + 1] = k end table.sort(out, byteLess) return out end

function Sync:busy() return next(self.by) ~= nil end
function Sync:stop() -- the client cancels my timers
  self.by, self.ask, self.serve, self.wait, self.out, self.missed, self.inflight, self.pumpTimer, self.hiTimer = {}, nil, nil, {}, {}, {}
end

-- A peer's HI carried ld: not my digest and I am the lower name -> I look again after the jitter.
function Sync:peer(peer, ld)
  local L = self.L
  if not self.client.running or self.wait[peer] or not byteLess(L.me, peer) or ld == L:digest() then return end
  local sum = 0
  for _, s in ipairs({ L.me, peer, ld }) do for j = 1, #s do sum = sum + s:byte(j) end end
  self.wait[peer] = self.client:after(C.LEDGER_JITTER_MIN + sum % 16, function() self.wait[peer] = nil; self:begin(peer) end)
end

-- The difference still stands: my exchange with `peer` starts.
function Sync:begin(peer)
  local p, L, now = self.client.presence.peers[peer], self.L, self.client.env.now()
  if not (p and p.ld and p.ld ~= L:digest()) or not self.net.running then return end
  if self.ask or self.by[peer] then self.missed[peer] = true; return end -- tried again when mine ends
  if self.last[peer] and now - self.last[peer] < C.LEDGER_PEER_GAP then return end
  if inInstance(self.client.env) then return self:peer(peer, p.ld) end
  self.last[peer] = now
  self:pages(self:open(peer, true), { v = C.PROTOCOL, t = "LVC" }, "a", L:vector(), true)
end

function Sync:open(peer, ask)
  local x = { peer = peer, ask = ask, q = {}, qs = {}, sent = 0, took = 0, d0 = self.L:digest(), lidOut = 0,
    lids = 0, lidN = {}, lidMine = {}, lidAll = {}, lin = {} }
  self.by[peer] = x
  if ask then self.ask = x else self.serve = x end
  self:alive(x)
  return x
end

-- Exchange x moved: it is given up LEDGER_SYNC_TIMEOUT s from now unless it moves again.
function Sync:alive(x)
  if x.timer then x.timer.cancel() end
  x.timer = self.client:after(C.LEDGER_SYNC_TIMEOUT, function() self:finish(x) end)
end

function Sync:finish(x)
  if self.by[x.peer] ~= x then return end
  self.by[x.peer], self[self.ask == x and "ask" or "serve"] = nil, nil

  x.timer.cancel()
  self.net:settle()
  if self.L:digest() ~= x.d0 then self:announce() end
  local peers, missed = self.client.presence.peers, self.missed -- the differences seen meanwhile
  self.missed = {}
  for _, peer in ipairs(sorted(missed)) do if peers[peer] and peers[peer].ld then self:peer(peer, peers[peer].ld) end end
end

-- One GUILD HI with my new digest, at most one per LEDGER_HI_GAP s, within the GUILD budget.
function Sync:announce()
  local presence, now = self.client.presence, self.client.env.now()
  local wait = (self.hiAt or -C.LEDGER_HI_GAP) + C.LEDGER_HI_GAP - now
  if wait > 0 then return self:arm("hiTimer", wait, Sync.announce) end
  if presence.sentLd == self.L:digest() or not self.client.running then return end
  if not self.net:afford(presence:hi(false)) then return self:arm("hiTimer", 1, Sync.announce) end
  self.hiAt = now
  presence:sendGuildHi(false)
end

function Sync:queue(x, bodies) -- bodies for exchange x to send, each once
  for _, b in ipairs(bodies) do if not x.qs[b] then x.qs[b], x.q[#x.q + 1] = true, b end end
end

-- `data` (keyed: a map, by key; else a list) as messages base + {[key] = part} of
-- at most PAGE packed bytes, m = true on all but the last; they go out in turn.
function Sync:pages(x, base, key, data, keyed)
  local keys = keyed and sorted(data) or {}
  if not keyed then for j = 1, #data do keys[j] = j end end
  local function page(from, k) -- measured with m (the last page loses it)
    local msg, part = Util.copy(base), {}
    for j = from, from + k - 1 do
      if keyed then part[keys[j]] = data[keys[j]] else part[#part + 1] = data[j] end
    end
    msg[key], msg.m = part, true
    return msg
  end
  local from, list = 1, {}
  repeat -- an empty map or list is one empty page
    local left = #keys - from + 1
    local k = left > 0 and math.max(1, Net.fit(left, Sync.PAGE, function(k) return page(from, k) end)) or 0
    list[#list + 1], from = page(from, k), from + k
  until from > #keys
  list[#list].m = nil
  for _, msg in ipairs(list) do self.out[#self.out + 1] = { x = x, msg = msg } end
  self:pump()
end

-- My bodies of author au in a LID's scope: above n, at ids I hold twins for, at the ids in `at` (all: every one).
function Sync:scope(au, n, at, all)
  local out, bodies = {}, self.L:above(au, 0)
  for j, b in ipairs(bodies) do
    local twin = (bodies[j - 1] and bodies[j - 1].i == b.i) or (bodies[j + 1] and bodies[j + 1].i == b.i)
    local bn = select(2, Ledger.author(b.i))
    if all or bn > n or twin or at[bn] then out[#out + 1] = b end
  end
  return out
end

-- My LID for author au (answer: to one I got; all: my whole list).
function Sync:lid(x, au, n, at, answer, all)
  local list, set = {}, {}
  for _, b in ipairs(self:scope(au, n, at, all)) do list[#list + 1] = item(b); set[item(b)] = true end
  if not answer then x.lidN[au], x.lidMine[au], x.lidAll[au] = n, set, all end
  self:pages(x, { v = C.PROTOCOL, t = "LID", au = au, r = answer or nil }, "l", list, false)
end

-- A list l of au came: I queue my bodies in its scope that it lacks -> the ids it names, how many I queued, its set.
function Sync:lacks(x, au, n, l)
  local set, at, send = {}, {}, {}
  for _, s in ipairs(l) do
    local k = tonumber(s:match("^(%d+)%."))
    set[s], at[k or 0] = true, true
  end
  for _, b in ipairs(self:scope(au, n, at)) do if not set[item(b)] then send[#send + 1] = b end end
  self:queue(x, send)
  return at, #send, set
end

-- The partner's whole vector came. P: what A lacks goes, and my answer (where A
-- is not behind). A: what P lacks where I am ahead; equal n: LID.
function Sync:vector(x)
  local L, mine, back = self.L, self.L:vector(), {}
  for _, a in ipairs(sorted(x.ask and x.v or mine)) do
    local m, t = mine[a], x.v[a]
    if not x.ask and (not t or t.x ~= m.x) then self:queue(x, L:above(a, t and t.n or 0)) end
    if not x.ask and t and t.x ~= m.x and t.n >= m.n then back[a] = m end
    if x.ask and m and m.x ~= t.x and m.n > t.n then self:queue(x, L:above(a, t.n)) end
    if x.ask and m and m.x ~= t.x and m.n == t.n and x.lidOut < C.LEDGER_LID_AUTHORS then
      x.lidOut = x.lidOut + 1
      self:lid(x, a, m.n, {})
    end
  end
  for a in pairs(x.ask and {} or x.v) do if not mine[a] then back[a] = { n = 0, x = "000000" } end end
  if next(back) then x.answered = true; self:pages(x, { v = C.PROTOCOL, t = "LVC", r = true }, "a", back, true) end
  self:pump()
end

-- A page of a vector (keyed) or of a list into acc -> true when it was the last.
local function gather(acc, part, keyed, more)
  for k, v in pairs(part) do
    if keyed and name(k) and cell(v) then acc[k] = { n = v.n, x = v.x } end
    if not keyed and type(k) == "number" and type(v) == "string" and #v <= 20 then acc[#acc + 1] = v end
  end
  return not more
end

function Sync:receive(sender, msg)
  if not (self.client.running and self.net.running and self.client.presence.peers[sender]) then return end
  local x = self.by[sender]
  if x then self:alive(x) end
  if msg.t == "LEV" then return self:lev(sender, msg, x) end
  if msg.t == "LVC" and type(msg.a) == "table" and (msg.r == true) == (x and x.ask or false) then
    if not x and (self.serve or inInstance(self.client.env)) then return end -- serving another: ignored
    x = x or self:open(sender, false)
    if x.spoke then return end -- one vector per side and exchange
    x.v = x.v or {}
    if gather(x.v, msg.a, true, msg.m) then x.spoke = true; self:vector(x) end
  elseif msg.t == "LID" and x and name(msg.au) and type(msg.l) == "table" then
    local au = msg.au
    local mine = x.ask and msg.r == true and x.lidN[au]
    local theirs = not x.ask and msg.r ~= true and x.spoke and not x.fMine and x.lids < 2 * C.LEDGER_LID_AUTHORS
    if not (mine or theirs) then return end
    x.lin[au] = x.lin[au] or {}
    if not gather(x.lin[au], msg.l, false, msg.m) then return end
    local l = x.lin[au]; x.lin[au] = nil
    if theirs then -- P: I queue what A lacks and answer with my list of that scope
      local v, m = x.v[au], self.L:vector()[au]
      local n = math.min(v and v.n or 0, m and m.n or 0)
      x.lids = x.lids + 1
      return self:lid(x, au, n, (self:lacks(x, au, n, l)), true)
    end
    local n, sent = x.lidN[au], x.lidMine[au] -- A: I queue what P lacks; the same lists: my whole one
    x.lidN[au] = nil
    local _, queued, set = self:lacks(x, au, n, l)
    local same = queued == 0 and not x.lidAll[au]
    for s in pairs(set) do same = same and sent[s] end
    for s in pairs(sent) do same = same and set[s] end
    if same then self:lid(x, au, n, {}, false, true) else x.lidOut = x.lidOut - 1 end
    self:pump()
  end
end

-- A whispered LEV of 0..LEDGER_BATCH entries: in an exchange with its sender of
-- any author (relayed), at most LEDGER_EXCHANGE_MAX; else only the sender's own, as live.
function Sync:lev(sender, msg, x)
  local ev, count = msg.ev, 0
  if type(ev) ~= "table" then return end
  for _ in pairs(ev) do count = count + 1 end
  if count > C.LEDGER_BATCH or #ev ~= count then return end
  for _, e in ipairs(ev) do if type(e) ~= "table" or (not x and Ledger.author(e.i) ~= sender) then return end end
  if not x then for _, e in ipairs(ev) do self.net:take(e, sender, true) end return end
  for _, e in ipairs(ev) do
    if x.took >= C.LEDGER_EXCHANGE_MAX then break end
    x.took, self.stats.got = x.took + 1, self.stats.got + 1
    self.net:take(e, sender, false)
  end
  x.spoke = x.spoke or x.ask -- P had no vector to answer with
  x.fTheirs = x.fTheirs or msg.f == true
  self:pump()
  if x.fMine and x.fTheirs then self:finish(x) end
end

-- May my side's last LEV (f) go?
local function last(x) return x.spoke and (x.ask and x.lidOut == 0 or not x.ask and (not x.answered or x.fTheirs)) end
local function due(x) return (#x.q > 0 and x.sent < C.LEDGER_EXCHANGE_MAX) or (not x.fMine and last(x)) end

-- The next whisper: a page first, else a LEV of an exchange (in turn), once the
-- previous whisper has left and the gap has passed; nothing in an instance.
function Sync:pump()
  if self.inflight or not self.net.running then return end
  local env = self.client.env
  if inInstance(env) then return self:arm("pumpTimer", C.LEDGER_SEND_GAP, Sync.pump) end
  while self.out[1] and self.by[self.out[1].x.peer] ~= self.out[1].x do table.remove(self.out, 1) end
  local o = table.remove(self.out, 1)
  if o then return self:send(o.x, o.msg) end

  local first, second = self.ask, self.serve
  if self.turn == first then first, second = second, first end
  local x = (first and due(first) and first) or (second and due(second) and second)
  if not x then return end
  local now = env.now()
  if now < (self.levAt or 0) then return self:arm("pumpTimer", self.levAt - now, Sync.pump) end
  local function lev(k) -- measured with f (only the last batch keeps it)
    local ev = {}
    for j = 1, k do ev[j] = Ledger.wire(x.q[j]) end
    return { v = C.PROTOCOL, t = "LEV", ev = ev, f = true }
  end

  local room = math.min(C.LEDGER_BATCH, #x.q, C.LEDGER_EXCHANGE_MAX - x.sent)
  local msg = lev(room > 0 and Net.fit(room, Sync.BATCH_BYTES, lev) or 0)
  for _ = 1, #msg.ev do table.remove(x.q, 1) end
  x.sent, self.stats.sent = x.sent + #msg.ev, self.stats.sent + #msg.ev
  if x.sent >= C.LEDGER_EXCHANGE_MAX then x.q = {} end -- the next exchange continues
  msg.f = (#x.q == 0 and last(x)) or nil
  x.fMine, self.turn = msg.f, x
  local s = self.client.session
  self.levAt = now + ((s and s.mySeat and s.status == "live") and C.LEDGER_SEND_GAP_BUSY or C.LEDGER_SEND_GAP)
  self:send(x, msg)
  if x.fMine and x.fTheirs then self:finish(x) end
end

-- One whisper to x's peer; the next one waits for its done-callback.
function Sync:send(x, msg)
  local token = {}
  self.inflight = token
  self.client:send("WHISPER", x.peer, msg, function()
    if self.inflight ~= token then return end
    self.inflight = nil
    if self.by[x.peer] == x then self:alive(x) end
    self:pump()
  end)
end

return Sync
