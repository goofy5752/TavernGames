local _, ns = ...

-- The whispered sync of the gold ledger, one exchange as asker and one as responder
-- at a time (pages and LID lists: core/LedgerSyncPage.lua; vectors: core/LedgerSyncVector.lua). A, the
-- byte-lower of a pair whose HI.ld differ, waits LEDGER_JITTER_MIN + (byte sum of
-- me .. peer .. ld) % 16 s (never env.random), checks again, sends LVC {a = vector}.
-- P serves only the byte-lower name, nobody else at the time, and that peer not
-- again within LEDGER_PEER_GAP. It queues L:above(author, A.n) of each author whose
-- x differs or A lacks, first answering LVC {a, r = true}: its n, x where A is not
-- behind or P lacks the author. A queues L:above(author, P.n) where ahead; equal n:
-- LID {au, l} (at most LEDGER_LID_AUTHORS), l the Ledger.item ("<n>.<h>") of its
-- bodies above n and at ids it holds twins for. Each side queues its bodies of that
-- scope (and at the ids a list names) that the other's list lacks; P answers LID
-- {r = true}. Equal lists: a twin inside the run, A sends its whole list once.
-- A LEV: <= LEDGER_BATCH entries, BATCH_BYTES packed; one per LEDGER_SEND_GAP s
-- (_BUSY at my live table), after the previous whisper has left (env.send's done).
-- f = true on a side's last (A's once P spoke and its LIDs are answered; P's after
-- A's f when it answered with a vector). The end: both f; or LEDGER_SYNC_TIMEOUT s
-- without a valid word of the partner while I wait for it; or LEDGER_EX_MAX s, or
-- more than LEDGER_EX_PAGES pages of a kind (then that peer waits a full peer gap).
-- No side sends more: a vector that does not fit goes in part, marked p = true (the
-- authors the partner differs on first), and each exchange does some of the work.
-- Of an author I hold stubs of, an R or S my heard exchanges carried a peer is not
-- sent it again (Sync:tail, core/LedgerSyncTail.lua).
-- An asked exchange that ended with both f does net:settle(). A changed digest
-- gives one GUILD HI (one per LEDGER_HI_GAP s). <= LEDGER_EXCHANGE_MAX entries sent
-- and taken. A LEV of another author than its sender only inside an exchange with
-- it. Nothing goes out in an instance; an unlisted sender is ignored. An exchange
-- that ended with both f and sent all it had notes the two cells of each author it
-- acted on (Sync:fixed). Two such exchanges in a row that left both cells as they
-- were (the first may have been lost on its way: nothing here is acknowledged)
-- mean the partner cannot take what I have: nothing of that author is sent or
-- listed to that peer again until a cell changes, our digests agree, or a day has
-- passed (an entry one side refuses and could not remember, core/LedgerRefused.lua,
-- would otherwise be offered forever). My x values
-- are hashed in slices (core/LedgerHash.lua): a comparison of digests, my vector and
-- what I do with the partner's wait until they are fresh (net:fresh).
local Ledger, C, Util = ns.Ledger, ns.Const, ns.Util
local Net = ns.LedgerNet
local byteLess, inInstance = Util.byteLess, Net.inInstance

local Sync = {}; Sync.__index = Sync
ns.LedgerSync = Sync
Sync.PAGE, Sync.BATCH_BYTES = 1500, 1140
Sync.arm = Net.arm -- fn(self) in seconds, unless the timer `field` is armed

function Sync.new(client, ledger, net)
  return setmetatable({ client = client, L = ledger, net = net, by = {}, wait = {}, last = {}, out = {}, missed = {},
    fix = {}, cur = {}, want = {}, high = Sync.marks(ledger), hot = {}, since = {}, owe = {}, stats = { sent = 0, got = 0 } }, Sync)
end

function Sync.sorted(t) local out = {} for k in pairs(t) do out[#out + 1] = k end table.sort(out, byteLess) return out end
local sorted = Sync.sorted

function Sync:busy() return next(self.by) ~= nil end
function Sync:stop() -- the client cancels my timers
  self.by, self.ask, self.serve, self.wait, self.out, self.missed = {}, nil, nil, {}, {}, {}
  self.inflight, self.pumpTimer, self.hiTimer = nil, nil, nil
end

-- A peer's HI carried ld: not my digest and I am the lower name -> I look again after the jitter.
function Sync:peer(peer, ld)
  local L = self.L
  if not self.client.running or self.wait[peer] or not byteLess(L.me, peer) then return end
  if L:hashing() then return self:later(function() self:again(peer) end) end
  if ld == L:digest() then self.fix[peer] = nil; return end -- we agree: whatever differs later is new
  local sum = 0
  for _, s in ipairs({ L.me, peer, ld }) do for j = 1, #s do sum = sum + s:byte(j) end end
  self.wait[peer] = self.client:after(C.LEDGER_JITTER_MIN + sum % 16, function() self.wait[peer] = nil; self:begin(peer) end)
end

-- fn() once my x values are fresh (at once when they are), unless my client stopped meanwhile.
function Sync:later(fn)
  self.net:fresh(function() if self.client.running and self.net.running then fn() end end)
end
-- `peer`'s digest as presence has it now is looked at again.
function Sync:again(peer)
  local p = self.client.presence.peers[peer]
  if p and p.ld then self:peer(peer, p.ld) end
end

-- The difference still stands: my exchange with `peer` starts.
function Sync:begin(peer)
  if self.L:hashing() then return self:later(function() self:begin(peer) end) end
  local p, L, now = self.client.presence.peers[peer], self.L, self.client.env.now()
  if not (p and p.ld and p.ld ~= L:digest()) or not self.net.running then return end
  if self.ask or self.by[peer] then self.missed[peer] = true; return end -- tried again when mine ends
  if self.last[peer] and now - self.last[peer] < C.LEDGER_PEER_GAP then return end
  if inInstance(self.client.env) then return self:peer(peer, p.ld) end
  self:asking(self:open(peer, true))
end

-- May `sender` open an exchange with me as its responder? The byte-lower name,
-- past the peer gap of our last exchange (less LEDGER_JITTER_MIN: the asker's
-- clock started a little before mine), while I serve nobody, outside an instance.
function Sync:welcome(sender)
  local last = self.last[sender]
  return not self.serve and not inInstance(self.client.env) and byteLess(sender, self.L.me)
    and not (last and self.client.env.now() - last < C.LEDGER_PEER_GAP - C.LEDGER_JITTER_MIN)
end

function Sync:open(peer, ask)
  local x = { peer = peer, ask = ask, q = {}, qs = {}, sent = 0, took = 0, d0 = self.L:digest(true), lidOut = 0,
    lids = 0, lidN = {}, lidMine = {}, lidAll = {}, lin = {}, pages = {}, items = {}, hw = {}, left = {} }
  self.by[peer], self.last[peer] = x, self.client.env.now()
  if ask then self.ask = x else self.serve = x end
  x.life = self.client:after(C.LEDGER_EX_MAX, function() self:finish(x, true) end)
  self:alive(x)
  return x
end

-- May my side's last LEV (f) go? Has exchange x a LEV to send (none while the partner's
-- vector waits for my fresh x values, x.hold)?
local function last(x) return x.spoke and (x.ask and x.lidOut == 0 or not x.ask and (not x.answered or x.fTheirs)) end
local function due(x) return not x.hold and ((#x.q > 0 and x.sent < C.LEDGER_EXCHANGE_MAX) or (not x.fMine and last(x))) end

-- The partner moved exchange x: given up LEDGER_SYNC_TIMEOUT s from now unless it moves
-- again, while I wait for it (not while I still have batches to send; LEDGER_EX_MAX holds).
function Sync:alive(x)
  if x.timer then x.timer.cancel(); x.timer = nil end
  if x.fTheirs then return end -- the partner is done: I wait for nothing
  x.timer = self.client:after(C.LEDGER_SYNC_TIMEOUT, function()
    x.timer = nil
    if due(x) or self:sending(x) then self:alive(x) else self:finish(x) end
  end)
end

-- Am I still sending for x (a page of it queued, or a whisper of it not yet left)?
function Sync:sending(x)
  if self.inflight and self.inflightX == x then return true end
  for _, o in ipairs(self.out) do if o.x == x then return true end end
  return false
end

-- A page of kind t (part: its cells or items) came in exchange x -> true. Refused, and x
-- closed (capped) -> false: past LEDGER_PAGE_ITEMS items (counted no further) or PAGE + SLACK packed
-- bytes (a copy of a page packs differently by key order), past LEDGER_EX_PAGES pages or LEDGER_EX_PAGES x LEDGER_PAGE_ITEMS items of a kind.
function Sync:page(x, t, msg, part)
  local n = 0
  for _ in pairs(part) do n = n + 1; if n > C.LEDGER_PAGE_ITEMS then break end end
  x.pages[t], x.items[t] = (x.pages[t] or 0) + 1, (x.items[t] or 0) + n
  if n > C.LEDGER_PAGE_ITEMS or x.pages[t] > C.LEDGER_EX_PAGES
    or x.items[t] > C.LEDGER_EX_PAGES * C.LEDGER_PAGE_ITEMS or Net.size(msg) > Sync.PAGE + Net.SLACK then
    self:finish(x, true)
    return false
  end
  self:alive(x)
  return true
end

-- Exchange x ends (capped: at LEDGER_EX_MAX or the page cap, and its peer waits a full peer gap from now).
function Sync:finish(x, capped)
  if self.by[x.peer] ~= x then return end
  self.by[x.peer], self[self.ask == x and "ask" or "serve"] = nil, nil
  if x.timer then x.timer.cancel() end
  x.life.cancel()
  self:ended(x, capped) -- what it sent and what it owes the peer (Sync:tail)
  x.v, x.lin, x.q = nil, nil, {} -- stored pages dropped
  if capped then self.last[x.peer] = self.client.env.now() end
  if x.fMine and x.fTheirs and not capped and not x.cut then self:fixed(x.peer, x.acted) end
  if x.ask and x.fMine and x.fTheirs then self.net:settle() end
  self:later(function() if self.L:digest() ~= x.d0 then self:announce() end end)
  local missed = self.missed -- the differences seen meanwhile
  self.missed = {}
  for _, peer in ipairs(sorted(missed)) do self:again(peer) end
end

-- One GUILD HI with my new digest, at most one per LEDGER_HI_GAP s, within the GUILD budget.
function Sync:announce()
  local presence, now = self.client.presence, self.client.env.now()
  local wait = (self.hiAt or -C.LEDGER_HI_GAP) + C.LEDGER_HI_GAP - now
  if wait > 0 then return self:arm("hiTimer", wait, Sync.announce) end
  if self.L:hashing() then return self:later(function() self:announce() end) end
  if presence.sentLd == self.L:digest() or not self.client.running then return end
  if not self.net:afford(presence:hi(false)) then return self:arm("hiTimer", 1, Sync.announce) end
  self.hiAt = now
  presence:sendGuildHi(false)
end

function Sync:queue(x, bodies) -- bodies for exchange x to send, each once
  for _, b in ipairs(bodies) do if not x.qs[b] then x.qs[b], x.q[#x.q + 1] = true, b end end
end

function Sync:receive(sender, msg)
  if not (self.client.running and self.net.running and self.client.presence.peers[sender]) then return end
  local x = self.by[sender]
  if msg.t == "LEV" then return self:lev(sender, msg, x) end
  if msg.t == "LVC" and type(msg.a) == "table" and (msg.r == true) == (x and x.ask or false) then
    if not x and not self:welcome(sender) then return end
    x = x or self:open(sender, false)
    if x.spoke or not self:page(x, "LVC", msg, msg.a) then return end -- one vector per side and exchange
    x.partial = x.partial or (msg.p == true and not x.ask) or nil
    x.v = x.v or {}
    if Sync.gather(x.v, msg.a, true, msg.m) then x.spoke = true; self:vector(x) end
  elseif msg.t == "LID" and x and Sync.name(msg.au) and type(msg.l) == "table" then
    local au = msg.au
    local mine = x.ask and msg.r == true and x.lidN[au]
    local theirs = not x.ask and msg.r ~= true and x.spoke and not x.fMine and x.lids < 2 * C.LEDGER_LID_AUTHORS
    if not (mine or theirs) or not self:page(x, "LID", msg, msg.l) then return end
    x.lin[au] = x.lin[au] or {}
    if not Sync.gather(x.lin[au], msg.l, false, msg.m) then return end
    local l = x.lin[au]; x.lin[au] = nil
    if theirs then -- P: I queue what A lacks and answer with my list of that scope
      local v = x.v[au]
      local n = math.min(v and v.n or 0, self.L:reach(au))
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

-- A whispered LEV: in an exchange with its sender 0..LEDGER_BATCH entries of any
-- author (relayed), at most LEDGER_EXCHANGE_MAX; else 1..LIVE_MAX of the sender's own, as live.
function Sync:lev(sender, msg, x)
  if type(msg.ev) ~= "table" then return end
  local ev, count = msg.ev, 0
  for _ in pairs(ev) do count = count + 1 end
  if count > (x and C.LEDGER_BATCH or Net.LIVE_MAX) or #ev ~= count then return end
  for _, e in ipairs(ev) do if type(e) ~= "table" or (not x and Ledger.author(e.i) ~= sender) then return end end
  if not x then for _, e in ipairs(ev) do self.net:take(e, sender, true) end return end
  if count == 0 and msg.f ~= true then return end -- no word
  for _, e in ipairs(ev) do
    if x.took >= C.LEDGER_EXCHANGE_MAX then x.cut = true; break end
    x.took = x.took + 1
    local status = self.net:take(e, sender, false)
    if status == "new" or status == "twin" then self.stats.got = self.stats.got + 1 end
  end
  x.spoke = x.spoke or x.ask -- P had no vector to answer with
  x.fTheirs = x.fTheirs or msg.f == true
  self:alive(x)
  self:pump()
  if x.fMine and x.fTheirs then self:finish(x) end
end


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
  for _ = 1, #msg.ev do self:mark(x, table.remove(x.q, 1)) end -- the high-water marks (Sync:tail)
  x.sent, self.stats.sent = x.sent + #msg.ev, self.stats.sent + #msg.ev
  if x.sent >= C.LEDGER_EXCHANGE_MAX then x.cut, x.rest, x.q = x.cut or #x.q > 0, x.q, {} end -- the next exchange continues
  msg.f = (#x.q == 0 and last(x)) or nil
  x.fMine, self.turn = msg.f, x
  local s = self.client.session
  self.levAt = now + ((s and s.mySeat and s.status == "live") and C.LEDGER_SEND_GAP_BUSY or C.LEDGER_SEND_GAP)
  self:send(x, msg)
  if x.fMine and x.fTheirs then self:finish(x) end
end

-- One whisper to x's peer; the next one waits for its done-callback, or
-- LEDGER_SYNC_TIMEOUT s when that never comes.
function Sync:send(x, msg)
  local token = {}
  local function free() if self.inflight == token then self.inflight = nil; self:pump() end end
  self.inflight, self.inflightX = token, x

  self.client:after(C.LEDGER_SYNC_TIMEOUT, free)
  self.client:send("WHISPER", x.peer, msg, free)
end

return Sync
