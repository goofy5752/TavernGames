local _, ns = ...

-- Chess at a staked table (spec 5.4), what core/StakesWatch.lua forwards to.
-- - A chess state (SC.valid) is the engine's own play of its moves from a new
--   game of its colours and base, an end no move shows (resign agreed flag
--   flagdraw left) played as such, but for the offer, the waits and the last
--   claim, which no move shows either. No honest host sends another: Member.adopt never takes one.
-- - My log: every action of my seat that was not forged, once per (ply, kind),
--   so my ACT and the event that shows it are one entry (both call
--   Stakes.sent). A move is "<from><to><promotion>" ("e2e4", "e7e8q") at its
--   index in state.moves, any other action its kind at #state.moves. A word
--   never holds a space (word() refuses one): the saved log packs them so.
-- - A snapshot (SC.adopted): a move of my seat my log lacks at a ply up to
--   its last move is forged; beyond it forged too, but "unseen" after a login
--   (WoW's copy may be the one before a crash), and so for a resign of mine,
--   an agreed draw (my offer or my accept at that ply or the one before), my
--   standing offer (the same) and my claim at this ply; what a login finds
--   unseen is taken into my log. A flag of my seat is judged by my clock of
--   that turn (Clock.flagHonest, s.clockPrev); a timed move without dt is
--   forged; a move of mine it brings (its event never came) goes into my clock sum.
-- Session field chessLog {no, list, ply, at} (local, never sent): no the s.stakeNo
-- of its game; list[i] what my seat did, ply[i] where; at[i] = {sent, turn}: my
-- env.now() at my ACT of a move and at the start of its turn on my clock (nil:
-- not seen), until its dt is counted. Saved as db.stakeChess = {tid, no, log =
-- "1:e2e4 3:g1f3 3:offer"} (ply:word split by spaces, so no word holds one; one
-- string: well under 1 KB a game) beside my
-- stake note for this table, while it stands (ns.Stake.clear).
local SC = {}
ns.StakesChess = SC

local same = ns.Util.same
local FILES = "abcdefgh"
local PROMO = { q = true, r = true, b = true, n = true }

local function whole(v, lo, hi) return type(v) == "number" and v >= lo and v <= hi and v % 1 == 0 end
local function square(n) local f = (n - 1) % 8 + 1; return FILES:sub(f, f) .. (math.floor((n - 1) / 8) + 1) end

-- What a log entry says of action (or move entry) a -> string | nil.
local function word(a)
  if a.k ~= nil and a.k ~= "move" then return type(a.k) == "string" and not a.k:find("%s") and a.k or nil end
  if not (whole(a.f, 1, 64) and whole(a.t, 1, 64)) then return nil end
  return square(a.f) .. square(a.t) .. (PROMO[a.p] and a.p or "")
end

-- The seat that plays ply p of st (white the odd plies).
local function mover(st, p) return p % 2 == 1 and st.white or 3 - st.white end

-- The replay x (in play) ends as b's result r says, by the engine's own
-- actions -> true when it could.
local function close(E, x, r)
  local why = r.reason
  if why == "resign" then return (r.winner == 1 or r.winner == 2) and E.apply(x, 3 - r.winner, { k = "resign" }) == true end
  if why == "flag" or why == "flagdraw" then return E.apply(x, x.turn, { k = "flag" }) == true end
  if why == "agreed" then x.offer = 1; return E.apply(x, 2, { k = "accept" }) == true end -- the result names no seat
  if why == "left" and (r.left == 1 or r.left == 2) then E.leave(x, r.left); return x.phase == "over" end
  return false
end

-- b replayed by the engine (see the header) -> the replay, or nil.
local function replay(b)
  local E = ns.Engines.chess
  if not ((b.white == 1 or b.white == 2) and type(b.moves) == "table") then return nil end
  local x = E.new{ first = b.white, opt = { clock = type(b.base) == "number" and b.base / 600 or 0 } }
  for i = 1, #b.moves do
    local m = b.moves[i]
    if type(m) ~= "table" or E.apply(x, x.turn, { k = "move", f = m.f, t = m.t, p = m.p }, m.dt) ~= true then return nil end
  end
  if x.phase == "play" and b.phase == "over" and not (type(b.result) == "table" and close(E, x, b.result)) then return nil end
  local w, offer, claimed = b.wait, b.offer, b.claimed
  if not (type(w) == "table" and whole(w[1], 0, E.WAIT) and whole(w[2], 0, E.WAIT)) then return nil end
  if offer ~= nil and not (x.phase == "play" and (offer == 1 or offer == 2)) then return nil end
  if claimed ~= nil and not (x.base and whole(claimed, 0, #x.moves)) then return nil end
  x.wait, x.offer, x.claimed = { w[1], w[2] }, offer, claimed
  return x
end

-- Is b a chess state at all: the replay of its own moves -> bool (anything
-- unreadable: false). The last answer is kept with a copy of its state: one
-- snapshot passes here several times (Member, Stakes.leadsTo, SC.adopted) but replays once.
local last -- { st = copy of the state judged, ok = its answer }
function SC.valid(b)
  if type(b) ~= "table" then return false end
  if last and same(last.st, b) then return last.ok end
  local read, x = pcall(replay, b)
  local ok = read and x ~= nil and same(x, b)
  last = { st = ns.Util.copy(b), ok = ok }
  return ok
end

-- Does chess state a lead to b in one game (b is a, or a later point of it)
-- -> bool: the same colours and base, a's moves (f t p dt) begin b's, a game
-- a shows over b shows the same, and b is a chess state (SC.valid).
function SC.leads(a, b)
  local read, leads = pcall(function()
    if a.white ~= b.white or a.base ~= b.base or #a.moves > #b.moves then return false end
    for i = 1, #a.moves do
      local x, y = a.moves[i], b.moves[i]
      if x.f ~= y.f or x.t ~= y.t or x.p ~= y.p or x.dt ~= y.dt then return false end
    end
    if a.phase == "over" and not (#a.moves == #b.moves and same(a.result, b.result)) then return false end
    return SC.valid(b)
  end)
  return read and leads == true
end

-- Which turn of its game st stands at -> #st.moves | nil.
function SC.turnKey(st) return type(st.moves) == "table" and #st.moves or nil end

local function save(s)
  local db, log = s.client.env.db, s.chessLog
  if type(db.stakeSat) ~= "table" or db.stakeSat.tid ~= s.tid or not log then return end
  local packed = {}
  for i = 1, #log.list do packed[i] = log.ply[i] .. ":" .. log.list[i] end
  db.stakeChess = { tid = s.tid, no = log.no, log = table.concat(packed, " ") }
end

-- The entry of log saying w at a ply from lo to hi -> its index | nil.
local function find(log, w, lo, hi)
  for i = 1, log and #log.list or 0 do
    if log.list[i] == w and log.ply[i] >= lo and log.ply[i] <= hi then return i end
  end
  return nil
end

local function add(log, w, ply)
  local i = #log.list + 1
  log.list[i], log.ply[i] = w, ply
  return i
end

-- I sent `a` (my ACT, a host's own action) or my client took it for mine
-- (Stakes' applied): one entry per (ply, kind), the ACT's times kept for a
-- move. Its event (the state then holds the move) drops them: Clock.before counted it.
function SC.sent(s, a)
  local st, me = s.state, s.mySeat
  if type(a) ~= "table" or a.k == "sit" or a.k == "stand" or not (st and type(st.moves) == "table" and me) then return end
  local w = word(a)
  if not w then return end
  local log, n = s.chessLog, #st.moves
  if not (log and log.no == s.stakeNo) then
    log = { no = s.stakeNo, list = {}, ply = {}, at = {} }
    s.chessLog = log
  end
  local ply = n
  if a.k == "move" and not (n > 0 and mover(st, n) == me) then ply = n + 1 end
  local i = find(log, w, ply, ply)
  if i then
    if n >= ply then log.at[i] = nil end
    return
  end
  i = add(log, w, ply)
  if a.k == "move" and n < ply then
    log.at[i] = { sent = s.client.env.now(), turn = s.clockSeen and s.clockKey == n and s.clockAt or nil }
  end
  save(s)
end

-- A login takes up db.stakeChess when it is of the game st shows: saved with
-- my generic log (db.stakeLog, Stakes.save) at the same game, whose state
-- then leads to st. Its number is the one the login's snapshot gives the
-- game (Stakes.refresh: a login always begins it anew on my client, when it runs).
local function takeUp(s, st)
  local db = s.client.env.db
  local saved, gen = db.stakeChess, db.stakeLog
  local no = (s.stakeNo or 0) + (ns.Stakes.running(s) and 1 or 0)
  local log = { no = no, list = {}, ply = {}, at = {} }
  if type(saved) == "table" and saved.tid == s.tid and type(saved.log) == "string"
      and type(gen) == "table" and gen.tid == s.tid and gen.no == saved.no and ns.Stakes.leadsTo(gen.st, st) then
    for ply, w in saved.log:gmatch("(%d+):(%S+)") do add(log, w, tonumber(ply)) end
  end
  return log
end

-- A snapshot replaced my state (core/StakesWatch.lua's `adopted`, for a chess
-- state; forward, prefix: as there) -> "forged" | "unseen" | nil. My seat:
-- the one I held, or after a login back to it the one the snapshot gives me.
function SC.adopted(s, prev, st, how, forward, prefix)
  local me = s.stakeSeat or (how.fresh and not how.req and s.mySeat) or nil
  if not me then return nil end
  if not (forward or SC.valid(st)) then return "forged" end -- Member.adopt takes none: no host sends it
  local login, cont = how.fresh, forward or prefix or same(prev, st)
  if login then s.chessLog = takeUp(s, st); save(s) end
  local log, n = s.chessLog, #st.moves
  if not (login or (cont and log and log.no == s.stakeNo)) then log = nil end -- another game: none of it is in my log
  local worst
  -- What my log lacks: forged (true), but after a login unseen and taken in.
  local function lacks(w, ply)
    if not login then return true end
    worst = "unseen"
    add(log, w, ply)
  end
  local last = 0 -- the last ply my log holds a move at
  for i = 1, log and #log.list or 0 do
    if log.list[i]:match("^[a-h][1-8][a-h][1-8][qrbn]?$") then last = math.max(last, log.ply[i]) end
  end
  for p = 1, n do
    local m = st.moves[p]
    if st.base and m.dt == nil then return "forged" end
    if mover(st, p) == me and not find(log, word(m), p, p) and (p <= last or lacks(word(m), p)) then return "forged" end
  end
  local r, play = st.result, st.phase == "play"
  local ended = st.phase == "over" and not (cont and prev and prev.phase == "over") -- an end my client held was judged then
  if ended and r.reason == "resign" and r.winner == 3 - me and not find(log, "resign", 0, math.huge) and lacks("resign", n) then return "forged" end
  if ended and r.reason == "agreed" and not (find(log, "offer", n - 1, n) or find(log, "accept", n - 1, n)) and lacks("accept", n) then return "forged" end
  if play and st.offer == me and not find(log, "offer", n - 1, n) and lacks("offer", n) then return "forged" end
  if play and st.turn == 3 - me and st.claimed == n and not find(log, "claim", n, n) and lacks("claim", n) then return "forged" end
  if ended and (r.reason == "flag" or r.reason == "flagdraw") and (st.side == 1 and st.white or 3 - st.white) == me then
    local c = s.clockPrev
    local honest, why = ns.Clock.flagHonest(s, me, prev and c and c.key == n and c or nil)
    if not honest and why == "forged" then return "forged" end
    if not honest then worst = "unseen" end
  end
  -- My moves this snapshot brings, into my clock sum.
  for p = forward and st.base and #prev.moves + 1 or n + 1, n do
    local i = mover(st, p) == me and find(log, word(st.moves[p]), p, p)
    local t = i and log.at[i]
    if t then
      log.at[i] = nil
      if t.turn and ns.Clock.countOwn(s, st.moves[p].dt, t.sent, t.turn) then return "forged" end
    end
  end
  return worst
end

return SC
