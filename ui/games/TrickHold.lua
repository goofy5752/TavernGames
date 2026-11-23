local _, ns = ...

-- The pause on a completed trick (Белот, Сантасе): the engine takes the trick
-- the moment its last card lands, so the view keeps drawing it on the felt for
-- TRICK_HOLD seconds. Display only: nothing but what a view draws depends on
-- it. A view calls TrickHold.check on every update with
--   tid      the table's id (a new table starts without a hold),
--   key      a string naming the last completed trick (nil: none yet),
--   running  true while the next trick has a card on the felt, or the deal
--            is over / not begun (the hold ends at once),
--   redraw   a function that draws the view again (the timer's end).
-- and draws the last trick as the running one while it returns true.
local TrickHold = { TRICK_HOLD = 1.5 }

local function stop(h)
  h.on = false
  if h.timer then h.timer:Cancel(); h.timer = nil end
end

function TrickHold.check(f, tid, key, running, redraw)
  local h = f.trickHold
  if not h then h = {}; f.trickHold = h end
  if h.tid ~= tid then
    stop(h)
    h.tid, h.seen = tid, key -- the first sight of a table: a trick already taken is not held
    return false
  end
  if key ~= h.seen then
    h.seen = key
    stop(h)
    if key and not running then
      h.on = true
      h.timer = C_Timer.NewTimer(TrickHold.TRICK_HOLD, function()
        h.timer, h.on = nil, false
        redraw()
      end)
    end
  elseif running or not key then
    stop(h)
  end
  return h.on == true
end

ns.TrickHold = TrickHold
