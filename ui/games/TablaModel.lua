local _, ns = ...

-- What the Табла table shows, as plain data: the board from my side (my
-- point 1 bottom right; a watcher sees seat 1's side), the checkers on each
-- point with whose pinned checker lies at the bottom, the bar and the tray,
-- the dice and the steps still open, the points I may pick and where the
-- picked checker may land, the buttons and the line of text (locale keys).
-- No frames. It reads only s.state, s.mySeat, s.status, s.seats, the steps I
-- staged this turn, my pick and the optional `names` (seat -> who held it
-- during the match), and stores nothing. While I am on turn the position is
-- the state after my staged steps (E.stage); staged steps that no longer fit
-- the state are dropped (`reset`), as if none were staged.
local E = ns.Engines.tabla

local M = {}

local function isSeat(seat) return seat == 1 or seat == 2 end

-- `seat`'s name: who held it during the match (`names`), else who holds it now, else "?".
local function nameOf(s, seat, names)
  local n = names and names[seat]
  if type(n) ~= "string" then n = s.seats and s.seats[seat] end
  if type(n) ~= "string" then n = "?" end
  return n
end

local function copy(list)
  if not list then return nil end
  local t = {}
  for i, x in ipairs(list) do t[i] = x end
  return t
end

local function textOf(s, st, seated, me, mine, m, names)
  local function name(seat) return nameOf(s, seat, names) end
  if E.over(st) then
    if st.quit then return { "tabla.left", name(st.quit) } end
    if seated then return { st.winner == me and "tabla.match.won" or "tabla.match.lost" } end
    return { "tabla.match.name", name(st.winner) }
  end
  local phase = st.phase
  if phase == "game" then
    local w = st.gw
    if st.var == "tapa" and st.gp == 2 and st.pin[3 - w][24] == 1 then return { "tabla.game.mother", name(w) } end
    if st.gp == 2 then return { "tabla.game.mars", name(w) } end
    return { "tabla.game.won", name(w) }
  elseif phase == "open" then
    return { "tabla.opening" }
  elseif phase == "roll" then
    if st.game == 1 and st.dice and st.rolls[1] == 0 and st.rolls[2] == 0 then return { "tabla.opens", name(st.turn) } end
    return { "tabla.rolling", name(st.turn) }
  elseif phase == "move" then
    if mine then
      if m.stuck then return { "tabla.stuck" } end
      if m.canDone then return { "tabla.ready" } end
      if m.pick then return { "tabla.pickTarget" } end
      if st.xfer then return { "tabla.xfer.mine", st.cv, name(3 - me) } end
      if st.cv then return { "tabla.cascade", st.cv } end
      return { "tabla.yourTurn" }
    end
    if st.xfer then return { "tabla.xfer", name(st.turn), st.cv, name(3 - st.turn) } end
    return { "tabla.waitFor", name(st.turn) }
  end
  return nil
end

-- Everything the Табла view draws. `staged`: the steps ({from, to}) I staged
-- this turn; `pick`: the point I picked (25 = the bar); `names` (optional):
-- seat -> who held it during the match.
function M.build(s, staged, pick, names)
  local st = s.state
  staged = staged or {}
  local seated = isSeat(s.mySeat)
  local me = seated and s.mySeat or 1
  local op = 3 - me
  local mine = seated and s.status == "live" and st.phase == "move" and st.turn == me

  local stage, reset
  if mine then
    stage = E.stage(st, me, staged)
    if not stage then
      reset, staged = true, {}
      stage = E.stage(st, me, staged)
    end
  end
  local p = stage or st

  local var = st.var
  local points = {}
  for q = 1, 24 do
    local x = E.abs(var, 2, q)
    local under
    if p.pin[me][q] == 1 then
      under = "own"
    elseif p.pin[op][x] == 1 then
      under = "opp"
    end
    points[q] = { own = p.pts[me][q], opp = p.pts[op][x], under = under }
  end

  local from, to = {}, {}
  if mine then
    for _, n in ipairs(stage.next) do from[n[1]] = true end
  end
  if not from[pick] then pick = nil end
  if pick then
    for _, n in ipairs(stage.next) do
      if n[1] == pick then to[n[2]] = true end
    end
  end

  local canDone = mine and stage.done
  local m = {
    me = me, op = op, seated = seated, mine = mine, reset = reset,
    var = var, game = st.game,
    score = { me = st.score[me], op = st.score[op] },
    points = points,
    bar = { own = p.bar[me], opp = p.bar[op] },
    off = { own = p.off[me], opp = p.off[op] },
    dice = st.cv and { st.cv, st.cv } or copy(st.dice),
    left = mine and stage.left or copy(st.left) or {},
    rolling = s.status == "live" and (st.phase == "open" or st.phase == "roll"),
    from = from, pick = pick, to = to,
    canUndo = mine and #staged > 0,
    canDone = canDone,
    stuck = canDone and #staged == 0,
  }
  m.text = textOf(s, st, seated, me, mine, m, names)
  return m
end

ns.TablaModel = M
