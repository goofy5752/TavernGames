local _, ns = ...

-- The member side of a table session (player or watcher; see core/Session.lua):
-- adopting the host's SNP snapshot, applying its EV events strictly in order,
-- following its TCK heartbeat, its SNO refusals and its END, and the PNG/SYN
-- the member sends back. Session.receive dispatches the WHISPER/GUILD types in
-- Member.handlers, each fn(client, sender, m).
local Member = {}
ns.Member = Member

local C = ns.Const
local Session = ns.Session
local Succession = ns.Succession
local copy, seatOf = ns.Util.copy, ns.Util.seatOf

-- PNG to the host every PING_EVERY seconds; while stale, the snapshot request again.
function Session:schedulePing()
  self.pingTimer = self.client:after(C.PING_EVERY, function()
    self.pingTimer = nil
    if self.stale then
      self:requestSync()
    else
      self.client:send("WHISPER", self.host, Session.message("PNG", { tid = self.tid }))
    end
    self:schedulePing()
  end)
end

-- Asks the host for a snapshot, at most once per SYN_MIN_GAP seconds: SYN{have},
-- or WAT from a watcher whose new host does not know it yet (see Succession).
function Session:requestSync()
  local now = self.client.env.now()
  if self.lastSyn and now - self.lastSyn < C.SYN_MIN_GAP then return end
  self.lastSyn, self.asked = now, true
  if self.stale and not self.mySeat then
    self.client:send("WHISPER", self.host, Session.message("WAT", { tid = self.tid }))
  else
    self.client:send("WHISPER", self.host, Session.message("SYN", { tid = self.tid, have = self.seq }))
  end
end

-- Member: session from a snapshot (new, or replacing the current one; a host
-- that lost its table to `sender` steps down first).
function Member.adopt(client, sender, m)
  local t, me = m.tbl, client.env.me
  local seat = seatOf(t.s, me)
  local fresh = client.session == nil -- no memory of this table (a relog, or I just came)
  local s = client.session or setmetatable({ client = client }, Session)
  local prevState, prevHost = s.state, s.host
  -- How this snapshot came, for the extensions: fresh, from a host new to me
  -- (changed), answering a request of mine (asked: SYN, WAT or SIT), with a
  -- seat I did not have (sat); q = my seq before it.
  local how = {
    fresh = fresh, changed = not fresh and (prevHost ~= sender or s.epoch ~= m.e or s.stale == true),
    asked = s.asked == true, sat = seat ~= nil and s.mySeat == nil, q = s.seq,
  }
  if s.role == "host" then Succession.demote(s) end
  s.tid, s.role, s.mySeat, s.host = m.tid, seat and "player" or "watcher", seat, sender
  s.epoch, s.seq, s.seats = m.e, m.q, copy(t.s)
  s.game, s.access, s.turn, s.watchers = t.g, t.ac, t.tn, t.w or 0
  s.opt = ns.Games.resolve(t.g, t.o)
  local engine = ns.Games.engine(t.g)
  s.state = type(m.st) == "table" and engine.restore(m.st) or nil
  -- A result already in the snapshot was announced before: noted, not emitted.
  s.resultSeen = s.state ~= nil and engine.result ~= nil and engine.result(s.state) ~= nil
  s.status = t.st == "live" and "live" or (s.state and "aborted" or "open")
  s.deadline = type(m.left) == "number" and client.env.now() + m.left or nil
  s.stale, s.sitAsked, s.asked = nil, nil, nil
  s.invited = {}
  s:addInvited(m.inv)
  client.pending, client.gaveUp = nil, nil
  client.session = s
  -- The extensions hear of a new host and of the state this snapshot replaced.
  if prevHost and prevHost ~= sender then s:hook("hostChanged") end
  s:hook("adopted", prevState, m, how)
  s:armAuto()
  if not s.pingTimer then s:schedulePing() end
  Succession.watchHost(s)
  -- A table I hosted until now, or one adopted before any TBL: list it as the host's.
  if not client.lobby:get(s.tid) then
    client.lobby:receive("WHISPER", sender, Session.message("TBL", copy(t)))
  end
  client.presence:setAt(s.tid)
  Session.emit(client)
end

local function unusable(m, sender)
  local t = m.tbl
  return type(m.e) ~= "number" or type(m.q) ~= "number" or not ns.Lobby.valid(t)
    or t.tid ~= m.tid or t.h ~= sender or not ns.Games.engine(t.g)
    or (t.st == "live" and type(m.st) ~= "table")
end

local function onSnapshot(client, sender, m)
  local t, s, p = m.tbl, client.session, client.pending
  if unusable(m, sender) then
    -- Seated at a table I cannot join (e.g. a game I do not have): free the seat.
    if type(t) == "table" and type(t.s) == "table" and seatOf(t.s, client.env.me)
        and not (s and s.tid == m.tid) then
      client:send("WHISPER", sender, Session.message("STD", { tid = m.tid }))
    end
    return
  end
  if s and s.tid == m.tid then
    -- My table: a new host's snapshot always; my own host's unless it is older
    -- than what I have (a stale member has nothing worth keeping).
    local kind = Succession.authority(s, sender, m.e)
    if kind == "new" or (kind == "current" and (s.stale or m.q >= s.seq)) then
      Member.adopt(client, sender, m)
    end
  elseif not s and ((p and p.tid == m.tid and p.host == sender)
      or (client.gaveUp ~= m.tid and seatOf(t.s, client.env.me))) then
    -- The answer to my request, or (after a relog) a table I still hold a seat at.
    Member.adopt(client, sender, m)
  else
    -- Seated or listed after I gave up waiting or went elsewhere: free the place again.
    client:send("WHISPER", sender, Session.message("STD", { tid = m.tid }))
  end
end

-- My action goes to the host (Session.act) and is remembered, the last
-- SENT_KEPT of them, until the host's event for my seat shows it.
local SENT_KEPT = 8
function Member.sendAct(s, a)
  local sent = s.sent or {}
  s.sent = sent
  sent[#sent + 1] = copy(a)
  if #sent > SENT_KEPT then table.remove(sent, 1) end
  s.client:send("WHISPER", s.host, Session.message("ACT", { tid = s.tid, a = a }))
end

-- Is `a` an action I sent and have not seen come back -> bool. It is taken
-- off the list together with the ones sent before it (the host dropped them).
function Member.mine(s, a)
  local sent = s.sent or {}
  for i = 1, #sent do
    if ns.Util.same(sent[i], a) then
      for _ = 1, i do table.remove(sent, 1) end
      return true
    end
  end
  return false
end

-- Events are taken only from my host, at exactly my epoch, in order. An epoch
-- is never adopted from an EV, and a stale member waits for its snapshot.
-- With hidden hands (engine.view) nobody but my client moves for my seat, my
-- timeouts included (Session:armAuto): an event for it that I did not send is
-- reported to the extensions (hook `forged`) and applied like any other.
local function onEvent(client, sender, m)
  local s = client.session
  if not s or s.role == "host" or s.tid ~= m.tid or s.host ~= sender or s.stale then return end
  if m.e ~= s.epoch or type(m.q) ~= "number" or m.q <= s.seq then return end
  if m.q > s.seq + 1 then return s:requestSync() end
  if m.seat == s.mySeat and s:engine().view and not Member.mine(s, m.a) then s:hook("forged", m.seat, m.a) end
  if not s:apply(m.seat, m.a) then
    s:hook("refused", m.seat, m.a)
    client.events:emit("desync", s.tid)
    return s:requestSync()
  end
  s.seq = m.q
  s.deadline = type(m.left) == "number" and client.env.now() + m.left or nil
  s:hook("applied", m.seat, m.a)
  s:armAuto()
  Session.emit(client)
end

local function onTick(client, sender, m)
  local s = client.session
  if not s or s.tid ~= m.tid or type(m.q) ~= "number" then return end
  local kind = Succession.authority(s, sender, m.e)
  if kind == "new" then
    Succession.follow(s, sender, m.e)
    s:requestSync()
  elseif kind == "current" and (s.stale or m.q > s.seq) then
    s:requestSync()
  end
end

local function onRefusal(client, sender, m)
  if type(m.why) ~= "string" then return end
  local s, p = client.session, client.pending
  if p and p.tid == m.tid and p.host == sender then
    client.pending = nil
    Session.refuse(client, m.tid, m.why)
  elseif s and s.role ~= "host" and s.tid == m.tid and s.host == sender then
    -- "gone": I am not at its table any more. Stale: the new host did not take me in.
    -- Anything else I can live with, e.g. a watcher asking for a taken chair.
    s.sitAsked = nil
    if m.why == "gone" or s.stale then Session.leave(client) end
    Session.refuse(client, m.tid, m.why)
  end
end

local function onEnd(client, sender, m)
  local s, p = client.session, client.pending
  if s and s.role ~= "host" and s.tid == m.tid and s.host == sender
      and type(m.e) == "number" and m.e >= s.epoch then
    Session.leave(client)
  elseif p and p.tid == m.tid and p.host == sender then
    client.pending = nil
    Session.refuse(client, m.tid, "gone")
  end
end

Member.handlers = { SNP = onSnapshot, EV = onEvent, TCK = onTick, SNO = onRefusal, END = onEnd }
