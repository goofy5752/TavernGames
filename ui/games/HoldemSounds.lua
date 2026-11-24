local _, ns = ...

-- The poker room's sounds of a Холдем table: our own files (media/sounds, ns.Art.playFile, the SFX
-- channel, muted with every other sound by db.sound = false). Fed by the client's "session" event, the
-- state the view draws, one event at a time, whether the table window shows or not; each table's last
-- state is kept (`seen`) and the new one is read against it:
--   - any seat's action (ns.HandHistory.holdemActs, the hand history's own reading of st.p): fold, check,
--     call, bet or raise ("bet"), all-in; a new hand's blinds sound as a call;
--   - a new hand's hole cards dealt ("deal"), a street's board cards ("board"), the pot to a winner ("win",
--     not after a void);
--   - my turn begins ("turn"); my turn clock (s.deadline, the clock my plate shows) "tick" at 10, 9, 8,
--     7 and 6 seconds left, "tickLast" at 5 … 1, each once; "timeout" when it ran out and the table
--     played for me. The ticks stop as soon as I act (HS.acted, from the view's buttons).
-- Nothing plays for the first state seen at a table (joining, a /reload, a snapshot: another epoch or
-- role, my events jumped, a hand count going back) nor for the same state again. A watcher hears the
-- table, never turn, tick or timeout. The table's sounds play only while the table window is shown;
-- turn, tick and timeout play also while it is hidden. One update plays at most MAX sounds: mine
-- first (turn, timeout), then win, board, deal, then the latest action only.
local HS = { TICKS = 10, LAST = 5, MAX = 2 }
ns.HoldemSounds = HS

local KIND = { fold = "fold", check = "check", call = "call", bet = "bet", raise = "bet", allin = "allin" }
local STEP = 0.001 -- a check lands just past the second it waits for
local LATE = 0.05  -- my turn that ended this close to its deadline ran out

local seen = {}   -- tid -> the summary of the last state observed there
local alert = nil -- my turn under way: { tid, key, s, deadline, next (the next second to tick), acted, out, timer }

local function now()
  local client = ns.client
  return client and client.env and client.env.now() or GetTime()
end

local function play(name) ns.Art.playFile(name) end

-- My turn at table s -> a key that changes with every turn of mine (hand, street, the bet I face), or nil:
-- not my turn, not live, a watcher, a chair the engine has not seated.
function HS.key(s)
  local st = s and s.state
  if type(st) ~= "table" or s.game ~= "holdem" or s.role == "watcher" or type(s.mySeat) ~= "number" then return nil end
  if s.status ~= "live" or st.phase ~= "bet" or st.turn ~= s.mySeat or not (st.seats and st.seats[s.mySeat]) then return nil end
  return tostring(st.hand) .. ":" .. tostring(st.street) .. ":" .. tostring(st.bet)
end

local function stop()
  if alert and alert.timer then alert.timer.cancel() end
  alert = nil
end

local check

-- The next look at my clock: when the next second to tick is reached (at 0: the timeout).
local function schedule(a)
  if a.timer then a.timer.cancel(); a.timer = nil end
  local client = ns.client
  if a.acted or a.out or not a.deadline or not client then return end
  local left = a.deadline - now()
  a.timer = client:after(math.max(0, left - a.next) + STEP, function()
    a.timer = nil
    if alert == a then check(a) end
  end)
end

check = function(a)
  if a.acted or a.out or HS.key(a.s) ~= a.key then return end
  if a.s.deadline then a.deadline = a.s.deadline end
  if not a.deadline then return end -- an untimed turn
  local left = a.deadline - now()
  if left <= 0 then
    a.out = true
    return play("timeout")
  end
  local n = math.ceil(left)
  if n <= a.next then -- a second skipped (a late frame) is not played again
    play(n <= HS.LAST and "tickLast" or "tick")
    a.next = n - 1
  end
  schedule(a)
end

-- I acted on my turn `key` (HS.key before the action): its clock is silent from now on.
function HS.acted(key)
  if alert and key ~= nil and alert.key == key then
    alert.acted = true
    if alert.timer then alert.timer.cancel(); alert.timer = nil end
  end
end

local function summary(s)
  local st = s.state
  local first = st.order and st.order[1]
  local p1 = first and st.p and st.p[first]
  local last, won = st.last, false
  if last and last.hand == st.hand and not last.void then
    for _, amt in pairs(last.won or {}) do if amt > 0 then won = true end end
  end
  return {
    epoch = s.epoch, seq = s.seq or 0, role = s.role, hand = st.hand or 0, board = #(st.board or {}), won = won,
    dealt = p1 ~= nil and #(p1.cards or {}) > 0, was = ns.HandHistory.holdemSnapshot(st), key = HS.key(s),
  }
end

-- A state that does not follow the last one: read silently.
local function jumped(was, cur)
  return was.epoch ~= cur.epoch or was.role ~= cur.role or cur.seq < was.seq or cur.hand < was.hand
    or (cur.role ~= "host" and cur.seq > was.seq + 1) -- a member applies its host's events one by one
end

-- The action of the seat that acted last since `was` (clockwise from the seat that was on turn).
local function latest(acts, st, was)
  local order, pos = st.order or {}, {}
  for k, i in ipairs(order) do pos[i] = k end
  local from, n, best, rank = pos[was.turn] or 1, math.max(1, #order), nil, -1
  for _, a in ipairs(acts) do
    local r = ((pos[a.seat] or 1) - from) % n
    if r > rank then best, rank = a, r end
  end
  return best
end

local function tableSounds(s, cur, was, out)
  local newHand = cur.hand > was.hand
  if cur.won and (newHand or not was.won) then out[#out + 1] = "win" end
  if not newHand and cur.board > was.board then out[#out + 1] = "board" end
  if cur.dealt and (newHand or not was.dealt) then out[#out + 1] = "deal" end
  if newHand then
    out[#out + 1] = "call" -- the blinds
  else
    local a = latest(ns.HandHistory.holdemActs(s.state, was.was), s.state, was.was)
    if a and KIND[a.k] then out[#out + 1] = KIND[a.k] end
  end
end

-- Table s changed (nil: I left it); `shown`: the table window shows.
function HS.observe(s, shown)
  for tid in pairs(seen) do
    if not s or tid ~= s.tid then seen[tid] = nil end
  end
  if alert and (not s or alert.tid ~= s.tid) then stop() end
  if not s or s.game ~= "holdem" or type(s.state) ~= "table" then return stop() end
  local cur, was = summary(s), seen[s.tid]
  seen[s.tid] = cur
  if not was or jumped(was, cur) then -- silent; a turn I did not see begin stays so, a running one goes on
    if alert and alert.key == cur.key then
      alert.s, alert.deadline = s, s.deadline or alert.deadline
      return schedule(alert)
    end
    return stop()
  end
  local out = {}
  if alert and alert.key ~= cur.key then
    if not alert.acted and not alert.out and alert.deadline and now() >= alert.deadline - LATE then out[1] = "timeout" end
    stop()
  end
  if cur.key and cur.key ~= was.key then
    out[#out + 1] = "turn"
    alert = { tid = s.tid, key = cur.key, s = s, deadline = s.deadline, next = HS.TICKS }
    check(alert)
  elseif alert then
    alert.s = s
    if s.deadline then alert.deadline = s.deadline end
    schedule(alert)
  end
  if shown then tableSounds(s, cur, was, out) end
  for i = 1, math.min(#out, HS.MAX) do play(out[i]) end
end

-- Forgets every table and stops my clock (tests; leaving is HS.observe(nil)).
function HS.reset()
  stop()
  seen = {}
end

ns.ready(function(client)
  client:on("session", function(s)
    local f = ns.TableFrame.frame
    -- a fault in the sounds must never stop the table: it is noted, not raised
    local fine, why = pcall(HS.observe, s, f ~= nil and f:IsVisible())
    if not fine then HS.lastError = why end
  end)
end)
