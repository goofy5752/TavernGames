local _, ns = ...

-- The sounds of every game but Холдем (which has ui/games/HoldemSounds.lua): our own files (media/sounds,
-- ns.Art.playFile, the SFX channel, muted with every other sound by db.sound = false). Fed by the client's
-- "session" event, the state the view draws, one event at a time, whether the table window shows or not.
-- Each table's last state is kept (`seen`) as a summary its game's reader makes, and the new one is read
-- against it. A reader (GS.games[id], ui/games/GameSoundsCards.lua and GameSoundsBoards.lua):
--   read(st, s)               -> the summary of state st: plain values only, compared with the next one
--   sounds(cur, was, out, s, ending) appends the table's sounds of the step from `was` to `cur`, the most
--                             telling first (`ending`: an end jingle of mine plays in this step)
--   turn(s)                   -> a key that changes with every turn of mine, or nil (optional): "turn"
--   clock = true              my last GS.TICKS seconds on a chess clock tick, once a second
-- Here, for every game:
--   - the end of the game (the match: never a single deal): engine.result went from nil to a value. I won
--     ("game_win"), lost ("game_lose"), or nobody did ("game_draw"); a watcher hears none of them.
--   - Death Roll's loss paid on the spot: the „Уредено“ toast (ui/SettleToast.lua) of a payment between me
--     and a seat of my Death Roll table plays "coins_pay" in place of its SOUNDKIT coins (GS.settled).
-- Nothing plays for the first state seen at a table (joining, a /reload, a snapshot: another epoch or role,
-- my events going back, or a member's jumping by more than one) nor for the same state again. The table's
-- sounds and the jingles play only while the table window is shown; my turn and my clock also while it is
-- hidden. One update plays at most MAX sounds: my turn first, then the jingle, then the table's.
local GS = { MAX = 2, TICKS = 10, games = {} }
ns.GameSounds = GS

local STEP = 0.001 -- a check lands just past the second it waits for

local seen = {}   -- tid -> the summary of the last state observed there
local ticker = nil -- my chess clock under way: { tid, key, s, next (the next second to tick), timer }

local function now()
  local client = ns.client
  return client and client.env and client.env.now() or GetTime()
end

local function play(name) ns.Art.playFile(name) end

local function seated(s) return s.role ~= "watcher" and type(s.mySeat) == "number" end

local function has(list, x)
  for _, v in ipairs(list or {}) do if v == x then return true end end
  return false
end

-- The engine's result of s's state, or nil (a game without one: Холдем).
local function result(s)
  local engine = ns.Games.engine(s.game)
  return engine and engine.result and engine.result(s.state) or nil
end

-- My jingle for the end r of the game at s, or nil: a watcher, a chair outside the result.
function GS.outcome(s, r)
  if not (r and seated(s)) then return nil end
  if has(r.winners, s.mySeat) then return "game_win" end
  if has(r.losers, s.mySeat) then return "game_lose" end
  if #(r.winners or {}) == 0 then return "game_draw" end
  return nil
end

---------------------------------------------------------------------------
-- My chess clock
---------------------------------------------------------------------------

-- My seconds left on a running clock at s, or nil: not my turn, untimed, a watcher.
local function clockLeft(s)
  local st = s.state
  if not seated(s) or type(st) ~= "table" or st.turn ~= s.mySeat or not st.clock or not ns.Clock.timed(s) then return nil end
  local t = ns.Clock.left(s, s.mySeat)
  return t and t / 10
end

local function clockKey(s)
  return clockLeft(s) and (tostring(s.tid) .. ":" .. #(s.state.moves or {})) or nil
end

local function stop()
  if ticker and ticker.timer then ticker.timer.cancel() end
  ticker = nil
end

local check

-- The next look at my clock: when the next second to tick is reached.
local function schedule(a)
  if a.timer then a.timer.cancel(); a.timer = nil end
  local client, left = ns.client, clockLeft(a.s)
  if not (client and left) or a.next < 1 then return end
  a.timer = client:after(math.max(0, left - a.next) + STEP, function()
    a.timer = nil
    if ticker == a then check(a) end
  end)
end

check = function(a)
  if clockKey(a.s) ~= a.key then return stop() end
  local left = clockLeft(a.s)
  if left <= 0 then return stop() end -- the flag is the table's: no sound of mine
  local n = math.ceil(left)
  if n <= a.next then -- a second skipped (a late frame) is not played again
    play("tick")
    a.next = n - 1
  end
  schedule(a)
end

-- My clock after the state of s (`fresh`: a state not seen to follow the last one).
local function clockStep(s, fresh)
  local key = clockKey(s)
  if ticker and ticker.key == key then
    ticker.s = s
    return schedule(ticker)
  end
  stop()
  if key and not fresh then
    ticker = { tid = s.tid, key = key, s = s, next = GS.TICKS }
    check(ticker)
  end
end

---------------------------------------------------------------------------
-- Observing
---------------------------------------------------------------------------

local function summary(s, reader)
  return {
    epoch = s.epoch, seq = s.seq or 0, role = s.role, over = result(s) ~= nil,
    turn = reader.turn and reader.turn(s) or nil, data = reader.read(s.state, s),
  }
end

-- A state that does not follow the last one: read silently.
local function jumped(was, cur)
  return was.epoch ~= cur.epoch or was.role ~= cur.role or cur.seq < was.seq
    or (cur.role ~= "host" and cur.seq > was.seq + 1) -- a member applies its host's events one by one
end

-- Table s changed (nil: I left it); `shown`: the table window shows.
function GS.observe(s, shown)
  for tid in pairs(seen) do
    if not s or tid ~= s.tid then seen[tid] = nil end
  end
  if ticker and (not s or ticker.tid ~= s.tid) then stop() end
  local reader = s and GS.games[s.game]
  if not reader or type(s.state) ~= "table" then return stop() end
  local cur, was = summary(s, reader), seen[s.tid]
  seen[s.tid] = cur
  local fresh = not was or jumped(was, cur)
  if reader.clock then clockStep(s, fresh) end
  if fresh then return end
  local out = {}
  if cur.turn and cur.turn ~= was.turn then out[1] = "turn" end
  if shown then
    local jingle = cur.over and not was.over and GS.outcome(s, result(s)) or nil
    if jingle then out[#out + 1] = jingle end
    reader.sounds(cur.data, was.data, out, s, jingle ~= nil)
  end
  for i = 1, math.min(#out, GS.MAX) do play(out[i]) end
end

-- The „Уредено“ toast's sound for payment p ({from, to}: ui/SettleToast.lua) -> true when it played ours:
-- at my Death Roll table, its window shown, a payment between me and a name of its seats.
function GS.settled(client, p)
  local s, f = client and client.session, ns.TableFrame.frame
  if not (s and s.game == "deathroll" and f and f:IsVisible() and p) then return false end
  local me = client.ledger and client.ledger.me
  local other = p.to == me and p.from or p.from == me and p.to or nil
  if not (other and has(s.seats, other)) then return false end
  return ns.Art.playFile("coins_pay")
end

-- Forgets every table and stops my clock (tests; leaving is GS.observe(nil)).
function GS.reset()
  stop()
  seen = {}
end

ns.ready(function(client)
  client:on("session", function(s)
    local f = ns.TableFrame.frame
    -- a fault in the sounds must never stop the table: it is noted, not raised
    local fine, why = pcall(GS.observe, s, f ~= nil and f:IsVisible())
    if not fine then GS.lastError = why end
  end)
end)
