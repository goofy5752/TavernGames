-- Табла soak: luajit tools/sim/tabla_soak.lua [matches] [seed] [randomPositions] [diceSamples]
-- (run from the repo root). Deterministic per seed.
--
-- Plays whole matches (Обикновена -> Тапа -> Гюлбара ..., to 5 points) with random legal moves
-- and with the engine's own automatic move (E.auto, what the bots and the timeout play), and
-- checks every turn against an INDEPENDENT reference written from the rules (help.tabla.* and
-- bkgm.com / Wikipedia, see the audit report), not from engines/tabla.lua:
--   * the full set of legal whole-turn results (max dice, larger die, bar first, blocks, hits,
--     pins, mother, bearing off, the 15th checker ending the move) equals the engine's E.legal;
--   * every legal move and every valid reordering of it is accepted, everything else (random
--     junk, truncated / extended / mutated legal moves) is rejected without touching the state;
--   * E.stage of every prefix of a played move agrees with the reference;
--   * 15 checkers per seat are conserved; turn flow (opening roll, who rolls, Гюлбара cascade
--     and remainder hand-over), game points, match score and the variant cycle follow the rules;
--   * snapshot -> restore -> replay of the rest of the match is identical;
--   * each game terminates.
-- Then random positions of every variant (not reachable only by play) are compared the same way,
-- and Fair.dice is checked for uniformity (chi-square over faces and over the 36 pairs).
package.path = "tests/helpers/?.lua;" .. package.path
local Loader = require("loader")
local ns = Loader.ns()
local E = ns.Engines.tabla

local MATCHES = tonumber(arg[1]) or 150
local SEED = tonumber(arg[2]) or 1
local RANDPOS = tonumber(arg[3]) or 3000
local DICEN = tonumber(arg[4]) or 20000
math.randomseed(SEED)
local R = math.random

local checks, fails, failLog = 0, 0, {}
local function fail(msg, ctx)
  fails = fails + 1
  if #failLog < 40 then failLog[#failLog + 1] = msg .. (ctx and ("\n    " .. ctx) or "") end
end
local function check(c, msg, ctx) checks = checks + 1; if not c then fail(msg, ctx) end; return c end

local function deepEq(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not deepEq(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end
local function ser(v)
  if type(v) ~= "table" then return tostring(v) end
  local t = {}
  for i = 1, #v do t[#t + 1] = ser(v[i]) end
  return "{" .. table.concat(t, ",") .. "}"
end

-- Reference model ------------------------------------------------------------------------------
-- Absolute points 1..24 (seat 1's numbering). Seat 1 runs 24 -> 1 in every variant. Std / Тапа:
-- seat 2 runs the opposite way, 1 -> 24. Гюлбара: both run the same way round, from diagonally
-- opposite corners: seat 2 starts on abs 12 and runs 12 -> 1, then 24 -> 13 (home abs 13..18).
local function absOf(var, seat, q)
  if seat == 1 then return q end
  if var == "gul" then return q > 12 and q - 12 or q + 12 end
  return 25 - q
end
local function ownOf(var, seat, a)
  if seat == 1 then return a end
  if var == "gul" then return a > 12 and a - 12 or a + 12 end
  return 25 - a
end

-- pos: n = { [1] = counts by abs, [2] = ... }, pinned[a] = seat whose single checker lies pinned
-- under the other seat's checkers (Тапа) or 0, bar, off, won (points) / nil.
local function rcopy(P)
  local n1, n2, pn = {}, {}, {}
  for a = 1, 24 do n1[a], n2[a], pn[a] = P.n[1][a], P.n[2][a], P.pinned[a] end
  return { var = P.var, n = { n1, n2 }, pinned = pn, bar = { P.bar[1], P.bar[2] },
           off = { P.off[1], P.off[2] }, won = P.won, wonBy = P.wonBy }
end
local function rkey(P)
  local t = {}
  for a = 1, 24 do t[#t + 1] = P.n[1][a] .. ":" .. P.n[2][a] .. ":" .. P.pinned[a] end
  return table.concat(t, " ") .. "|" .. P.bar[1] .. "," .. P.bar[2] .. "|" .. P.off[1] .. "," ..
    P.off[2] .. "|" .. tostring(P.won)
end
local function homeAll(P, me)
  if P.bar[me] > 0 then return false end
  for a = 1, 24 do
    if P.n[me][a] > 0 and ownOf(P.var, me, a) > 6 then return false end
  end
  return true
end
local function movable(P, me, a)
  return P.n[me][a] > 0 and P.pinned[a] ~= me
end

-- One checker of `me` from own point q (25 = bar) by die d -> new pos, own to (0 = off) | nil.
local function rstep(P, me, q, d)
  local var, op = P.var, 3 - me
  if P.won then return nil end
  if q == 25 then
    if var ~= "std" or P.bar[me] == 0 then return nil end
  else
    if var == "std" and P.bar[me] > 0 then return nil end -- bar first
    if not movable(P, me, absOf(var, me, q)) then return nil end
  end
  local t = q - d
  local N = rcopy(P)
  if t >= 1 then
    local b = absOf(var, me, t)
    local oc = P.n[op][b]
    if var == "std" then
      if oc >= 2 then return nil end
      if oc == 1 then N.n[op][b] = 0; N.bar[op] = N.bar[op] + 1 end
    elseif var == "tapa" then
      if P.pinned[b] == op then
        -- the opponent's checker lies pinned under mine: I may add more
      elseif P.pinned[b] == me or oc >= 2 then
        return nil
      elseif oc == 1 then
        N.pinned[b] = op
        -- the mother: the opponent's lone checker still on its own starting point
        if ownOf(var, op, b) == 24 then N.won, N.wonBy = 2, me end
      end
    else
      if oc >= 1 then return nil end
    end
    N.n[me][b] = N.n[me][b] + 1
  else
    if not homeAll(P, me) then return nil end
    if t < 0 then
      for a = 1, 24 do
        if P.n[me][a] > 0 and ownOf(var, me, a) > q then return nil end
      end
    end
    N.off[me] = N.off[me] + 1
    t = 0
  end
  if q == 25 then
    N.bar[me] = N.bar[me] - 1
  else
    local a = absOf(var, me, q)
    N.n[me][a] = N.n[me][a] - 1
    if N.n[me][a] == 0 and N.pinned[a] == op then N.pinned[a] = 0 end
  end
  if not N.won and N.off[me] == 15 then N.won, N.wonBy = (N.off[op] == 0) and 2 or 1, me end
  return N, t
end

local function remKey(rem)
  local c = {}
  for i = 1, #rem do c[i] = rem[i] end
  table.sort(c)
  return table.concat(c, ",")
end
local function remove1(rem, d)
  local out, gone = {}, false
  for _, x in ipairs(rem) do if x == d and not gone then gone = true else out[#out + 1] = x end end
  return out
end
local function uniq(rem)
  local s, o = {}, {}
  for _, x in ipairs(rem) do if not s[x] then s[x] = true; o[#o + 1] = x end end
  return o
end

-- Every legal whole-turn result: set key -> { P, used }. Rules: as many dice as possible (a move
-- that wins the game ends there and is a complete move); if only one die of two different ones
-- can be played, the larger one when it can.
local function rlegal(P, me, dice)
  local leaves, seen = {}, {}
  local function dfs(Q, rem)
    local mk = rkey(Q) .. "#" .. remKey(rem)
    if seen[mk] then return end
    seen[mk] = true
    local any = false
    if not Q.won and #rem > 0 then
      for _, d in ipairs(uniq(rem)) do
        for q = 25, 1, -1 do
          local N = rstep(Q, me, q, d)
          if N then any = true; dfs(N, remove1(rem, d)) end
        end
      end
    end
    if not any then
      local used = Q.won and #dice or (#dice - #rem)
      local die
      if used == 1 and not Q.won then
        local r = rem[1]
        die = (dice[1] == r) and dice[2] or dice[1]
      elseif used == 1 then
        die = nil
      end
      leaves[#leaves + 1] = { P = Q, used = used, die = die, won = Q.won,
                              firstDie = #dice - #rem == 1 and ((dice[1] == rem[1]) and dice[2] or dice[1]) or nil }
    end
  end
  dfs(rcopy(P), dice)
  local maxN = 0
  for _, l in ipairs(leaves) do if l.used > maxN then maxN = l.used end end
  local double = #dice ~= 2 or dice[1] == dice[2]
  local needBig
  if not double and maxN == 1 then
    local hi = math.max(dice[1], dice[2])
    for _, l in ipairs(leaves) do if l.used == 1 and l.die == hi then needBig = hi end end
  end
  local out, n = {}, 0
  for _, l in ipairs(leaves) do
    if l.used == maxN and (not needBig or l.die == needBig) then
      local k = rkey(l.P)
      if not out[k] then out[k] = { P = l.P, used = l.used }; n = n + 1 end
    end
  end
  return out, n, maxN, leaves
end

-- Does the step list, played in this order with some die per step, reach a legal result?
local function raccepts(P, me, dice, steps, legal)
  if type(steps) ~= "table" then return false end
  local function go(Q, i, rem)
    if i > #steps then return legal[rkey(Q)] ~= nil end
    if Q.won then return false end
    local st = steps[i]
    if type(st) ~= "table" or type(st[1]) ~= "number" or type(st[2]) ~= "number" then return false end
    local q, t = st[1], st[2]
    if q ~= 25 and (q < 1 or q > 24 or q % 1 ~= 0) then return false end
    for _, d in ipairs(uniq(rem)) do
      local N, to = rstep(Q, me, q, d)
      if N and to == t and go(N, i + 1, remove1(rem, d)) then return true end
    end
    return false
  end
  return go(rcopy(P), 1, dice)
end

-- Engine state -> reference position (and structural invariants).
local function fromEngine(s, ctx)
  local P = { var = s.var, n = { {}, {} }, pinned = {}, bar = { s.bar[1], s.bar[2] },
              off = { s.off[1], s.off[2] } }
  for a = 1, 24 do P.n[1][a], P.n[2][a], P.pinned[a] = 0, 0, 0 end
  for seat = 1, 2 do
    local tot = s.bar[seat] + s.off[seat]
    for q = 1, 24 do
      local c = s.pts[seat][q]
      check(type(c) == "number" and c >= 0 and c % 1 == 0, "bad count", ctx)
      local a = absOf(s.var, seat, q)
      P.n[seat][a] = c
      tot = tot + c
      if s.pin[seat][q] == 1 then
        check(s.var == "tapa", "pin outside Тапа", ctx)
        check(c == 1, "pinned point holds " .. c .. " checkers", ctx)
        P.pinned[a] = seat
      else
        check(s.pin[seat][q] == 0, "pin flag not 0/1", ctx)
      end
    end
    check(tot == 15, "seat " .. seat .. " has " .. tot .. " checkers", ctx)
    check(s.var == "std" or s.bar[seat] == 0, "bar outside Обикновена", ctx)
  end
  for a = 1, 24 do
    if P.n[1][a] > 0 and P.n[2][a] > 0 then
      local p = P.pinned[a]
      check(p ~= 0 and P.n[3 - p][a] >= 1, "both seats share abs point " .. a .. " without a pin", ctx)
    elseif P.pinned[a] ~= 0 then
      check(false, "pinned checker without a pinner on abs " .. a, ctx)
    end
  end
  return P
end

-- Engine helpers ----------------------------------------------------------------------------
local function engineAfter(s, steps)
  local c = E.restore(E.snapshot(s))
  local ok, r, why = pcall(E.apply, c, c.turn, { k = "move", steps = steps })
  if not ok then return nil, "ERROR " .. tostring(r) end
  if not r then return nil, why end
  return c
end
-- The game points a finished position is worth (derived from the position alone), or nil.
local function wonOf(P, me)
  local op = 3 - me
  if P.var == "tapa" then
    for a = 1, 24 do
      if P.pinned[a] == op and ownOf(P.var, op, a) == 24 then return 2 end
    end
  end
  if P.off[me] == 15 then return P.off[op] == 0 and 2 or 1 end
  return nil
end

-- The engine's legal results. Every legal move is staged whole (E.stage: the engine's own
-- position after a move, with gen cached), and a sample of them is applied for real (apply
-- re-generates the legal moves each time, too slow for all of a double's hundreds of moves).
local function engineLegalSet(s, ctx)
  local set, n = {}, 0
  local list = E.legal(s, s.turn)
  local sample = {}
  for _ = 1, 3 do sample[R(#list)] = true end
  for i, m in ipairs(list) do
    local P
    if sample[i] or #list <= 3 then
      local c, why = engineAfter(s, m.steps)
      if check(c ~= nil, "engine rejects its own legal move " .. ser(m.steps) .. " (" .. tostring(why) .. ")", ctx) then
        P = fromEngine(c, ctx)
        P.won = (c.phase == "game" or c.phase == "match") and c.gp or nil
        check(P.won == wonOf(P, s.turn), "game points of the move " .. tostring(P.won), ctx)
      end
    else
      local st = E.stage(s, s.turn, m.steps)
      if check(st ~= nil and st.done, "stage of a legal move not done " .. ser(m.steps), ctx) then
        P = fromEngine({ var = s.var, pts = st.pts, pin = st.pin, bar = st.bar, off = st.off }, ctx)
        P.won = wonOf(P, s.turn)
      end
    end
    if P then
      local k = rkey(P)
      check(not set[k], "legal lists the same result twice " .. ser(m.steps), ctx)
      set[k] = m; n = n + 1
    end
  end
  return set, n, list
end

local function ctxOf(s, extra)
  return string.format("var=%s game=%d turn=%s left=%s cv=%s xfer=%s | %s", tostring(s.var), s.game,
    tostring(s.turn), ser(s.left), tostring(s.cv), tostring(s.xfer), extra or "")
end

-- Compare legal sets of the engine state s (phase move) against the reference.
local stats = { turns = 0, legalCompared = 0, probes = 0, stageChecks = 0, noMove = 0, maxDiceCut = 0,
                bigDie = 0, winsEarly = 0 }
local function compareLegal(s, ctx)
  local P = fromEngine(s, ctx)
  local ref, rn, maxN, leaves = rlegal(P, s.turn, s.left)
  local eng, en = engineLegalSet(s, ctx)
  stats.legalCompared = stats.legalCompared + 1
  for k in pairs(ref) do check(eng[k] ~= nil, "reference move missing from engine legal", ctx .. " ref=" .. k) end
  for k, m in pairs(eng) do check(ref[k] ~= nil, "engine legal move not legal by the rules " .. ser(m.steps), ctx) end
  if rn == 1 and next(ref) == rkey(P) then stats.noMove = stats.noMove + 1 end
  if maxN < #s.left then stats.maxDiceCut = stats.maxDiceCut + 1 end
  return P, ref, eng
end

local function randomJunk()
  local r = R(10)
  if r == 1 then return "x" end
  if r == 2 then return { 1, 2 } end
  if r == 3 then return { { "a", 1 } } end
  if r == 4 then return { { 2.5, 1 } } end
  local t = {}
  for i = 1, R(0, 4) do t[i] = { R(-1, 26), R(-2, 25) } end
  return t
end
local function mutate(steps)
  local t = {}
  for i, st in ipairs(steps) do t[i] = { st[1], st[2] } end
  local r = R(5)
  if r == 1 and #t > 0 then table.remove(t, R(#t))
  elseif r == 2 and #t > 0 then local i = R(#t); t[i][2] = t[i][2] + (R(2) == 1 and 1 or -1)
  elseif r == 3 then t[#t + 1] = { R(1, 25), R(0, 24) }
  elseif r == 4 and #t > 0 then local i = R(#t); t[i][1] = t[i][1] + (R(2) == 1 and 1 or -1); t[i][2] = t[i][2]
  else for i = #t, 2, -1 do local j = R(i); t[i], t[j] = t[j], t[i] end end
  return t
end

-- Probe apply with `steps`: accepted iff the reference accepts; a rejection leaves s untouched.
local function probe(s, P, ref, steps, ctx)
  stats.probes = stats.probes + 1
  local want = raccepts(P, s.turn, s.left, steps, ref)
  local before = E.snapshot(s)
  local c = E.restore(before)
  local ok, r, why = pcall(E.apply, c, c.turn, { k = "move", steps = steps })
  check(ok, "apply raised on " .. ser(steps) .. ": " .. tostring(r), ctx)
  if not ok then return end
  check((r == true) == want, "apply " .. (r and "accepted" or "rejected") .. " " .. ser(steps) ..
    " but the rules say " .. (want and "legal" or "illegal"), ctx)
  if not r then check(deepEq(c, before), "rejected move changed the state", ctx) end
end

-- E.stage along a move: every prefix stages, its next holds the following step, the last is done
-- and equals the applied result; the next list matches the reference continuations.
local function checkStage(s, P, ref, steps, ctx, full)
  stats.stageChecks = stats.stageChecks + 1
  local me = s.turn
  local Q, rem = rcopy(P), s.left
  for i = 0, #steps do
    local pre = {}
    for j = 1, i do pre[j] = steps[j] end
    local st = E.stage(s, me, pre)
    if not check(st ~= nil, "stage nil on a prefix of a legal move " .. ser(pre), ctx) then return end
    if i < #steps then
      local nx = steps[i + 1]
      local found = false
      for _, x in ipairs(st.next) do if x[1] == nx[1] and x[2] == nx[2] then found = true end end
      check(found, "stage next lacks the following step " .. ser(nx) .. " after " .. ser(pre), ctx)
    else
      check(st.done == true, "stage of a whole legal move not done " .. ser(pre), ctx)
    end
    if full then
      -- reference continuations from this prefix: steps that keep some legal result reachable
      local refNext, memo = {}, {}
      local function reach(Z, r2)
        local zk = rkey(Z)
        if ref[zk] then return true end
        if Z.won then return false end
        local mk = zk .. "#" .. remKey(r2)
        if memo[mk] ~= nil then return memo[mk] end
        local v = false
        for _, d in ipairs(uniq(r2)) do
          for q = 25, 1, -1 do
            local N = rstep(Z, me, q, d)
            if N and reach(N, remove1(r2, d)) then v = true break end
          end
          if v then break end
        end
        memo[mk] = v
        return v
      end
      -- prefix positions (any die assignment)
      local fronts = {}
      local function play(Z, j, r2)
        if j > i then fronts[#fronts + 1] = { Z, r2 }; return end
        for _, d in ipairs(uniq(r2)) do
          local N, to = rstep(Z, me, pre[j][1], d)
          if N and to == pre[j][2] then play(N, j + 1, remove1(r2, d)) end
        end
      end
      play(rcopy(P), 1, rem)
      for _, f in ipairs(fronts) do
        local Z, r2 = f[1], f[2]
        if not Z.won then
          for _, d in ipairs(uniq(r2)) do
            for q = 25, 1, -1 do
              local N, to = rstep(Z, me, q, d)
              if N and reach(N, remove1(r2, d)) then refNext[q * 32 + to] = true end
            end
          end
        end
      end
      local engNext = {}
      for _, x in ipairs(st.next) do engNext[x[1] * 32 + x[2]] = true end
      for k in pairs(refNext) do check(engNext[k], "stage next misses " .. math.floor(k / 32) .. "/" .. k % 32 .. " after " .. ser(pre), ctx) end
      for k in pairs(engNext) do check(refNext[k], "stage next offers " .. math.floor(k / 32) .. "/" .. k % 32 .. " after " .. ser(pre), ctx) end
    end
  end
end

-- Reference turn flow -----------------------------------------------------------------------
local VARS = { "std", "tapa", "gul" }
local START = { std = { [24] = 2, [13] = 5, [8] = 3, [6] = 5 }, tapa = { [24] = 15 }, gul = { [24] = 15 } }
local function refBoard(var)
  local P = { var = var, n = { {}, {} }, pinned = {}, bar = { 0, 0 }, off = { 0, 0 } }
  for a = 1, 24 do P.n[1][a], P.n[2][a], P.pinned[a] = 0, 0, 0 end
  for seat = 1, 2 do for q, c in pairs(START[var]) do P.n[seat][absOf(var, seat, q)] = c end end
  return P
end

-- F: { game, var, score, rolls, phase, turn, dice(list), casc = { v, xfer } | nil, P }
local function newFlow()
  return { game = 1, var = "std", score = { 0, 0 }, rolls = { 0, 0 }, phase = "open", P = refBoard("std") }
end
local function flowDice(F, a, b)
  if F.phase == "open" then
    if a ~= b then F.turn, F.phase = (a > b) and 1 or 2, "roll" end
    return
  end
  local me = F.turn
  F.rolls[me] = F.rolls[me] + 1
  if a == b then
    F.dice = { a, a, a, a }
    if F.var == "gul" and F.rolls[me] >= 4 then F.casc = { v = a, xfer = false } end
  else
    F.dice = { a, b }
  end
  F.phase = "move"
end
local function flowMove(F, result, used)
  local me = F.turn
  F.P = result
  if result.won then
    F.score[me] = F.score[me] + result.won
    F.dice, F.casc, F.turn = nil, nil, nil
    F.lastWinner = me
    F.phase = F.score[me] >= 5 and "match" or "game"
    return
  end
  local c = F.casc
  if c then
    local full = used == #F.dice
    if full and c.v < 6 then
      c.v = c.v + 1; F.dice = { c.v, c.v, c.v, c.v }; return
    elseif not full and not c.xfer then
      local left = {}
      for i = 1, #F.dice - used do left[i] = c.v end
      F.dice, c.xfer, F.turn = left, true, 3 - me
      return
    end
    -- over: a hand-over's receiver rolls next, otherwise the roller's opponent
    F.turn = c.xfer and me or 3 - me
    F.casc, F.dice, F.phase = nil, nil, "roll"
    return
  end
  F.dice, F.turn, F.phase = nil, 3 - me, "roll"
end
local function flowNext(F)
  F.game = F.game + 1
  F.var = VARS[(F.game - 1) % 3 + 1]
  F.P = refBoard(F.var)
  F.rolls = { 0, 0 }
  F.turn, F.phase = F.lastWinner, "roll"
end

local function sortedCopy(t)
  if not t then return nil end
  local c = {}
  for i = 1, #t do c[i] = t[i] end
  table.sort(c)
  return c
end
local function compareFlow(s, F, ctx)
  check(s.phase == F.phase, "phase " .. tostring(s.phase) .. " ~= " .. F.phase, ctx)
  check(s.game == F.game and s.var == F.var, "game/variant " .. s.game .. s.var .. " ~= " .. F.game .. F.var, ctx)
  check(deepEq(s.score, F.score), "score " .. ser(s.score) .. " ~= " .. ser(F.score), ctx)
  check(s.turn == F.turn, "turn " .. tostring(s.turn) .. " ~= " .. tostring(F.turn), ctx)
  if F.phase == "move" then
    check(deepEq(sortedCopy(s.left), sortedCopy(F.dice)), "dice left " .. ser(s.left) .. " ~= " .. ser(F.dice), ctx)
    check((s.cv ~= nil) == (F.casc ~= nil), "cascade flag", ctx)
    if F.casc then check(s.cv == F.casc.v, "cascade number", ctx) end
  end
  if F.phase ~= "match" and F.phase ~= "game" and F.phase ~= "open" then
    local P = fromEngine(s, ctx)
    check(rkey(P) == rkey(F.P), "board differs from the reference", ctx)
  end
  if F.phase == "match" then
    check(E.over(s) == true, "over() false at match end", ctx)
    local r = E.result(s)
    check(r and r.winners[1] == F.lastWinner and r.losers[1] == 3 - F.lastWinner, "result winners", ctx)
  else
    check(not E.over(s), "over() true mid-match", ctx)
  end
end

-- Match driver ----------------------------------------------------------------------------
local totals = { matches = 0, games = { std = 0, tapa = 0, gul = 0 }, points = { [1] = 0, [2] = 0 },
                 mars = 0, mother = 0, cascades = 0, handovers = 0, actions = 0, snapshots = 0,
                 maxActions = 0, timeouts = 0 }

local function playMatch(mode, mi)
  local s = E.new{}
  local F = newFlow()
  local log = {}
  local snapAt = R(1, 400)
  local snap, snapIdx
  local actions = 0
  local gameActions = 0
  local cascSeen = false
  while not E.over(s) do
    actions = actions + 1; gameActions = gameActions + 1
    if gameActions > 6000 then totals.timeouts = totals.timeouts + 1; fail("game did not end", ctxOf(s)) break end
    if actions == snapAt then snap, snapIdx = E.snapshot(s), #log end
    local ctx = ctxOf(s, "mode=" .. mode .. " match=" .. mi .. " seed=" .. SEED .. " action=" .. actions)
    -- every state between two actions is one the dice extension's snapshot check passes
    check(E.thrown(s) ~= false, "E.thrown rejects a state between actions", ctx)
    local a, delay = E.system(s)
    if s.phase == "open" or s.phase == "roll" then
      check(a and a.k == "dice" and a.need == "dice" and delay == 0, "system does not ask for dice", ctx)
      check(a.r == (s.phase == "open" and "open" or "roll"), "system r", ctx)
      if s.phase == "roll" then check(a.s == s.turn, "system roller", ctx) end
      local d = { R(6), R(6) }
      check(E.apply(s, 0, { k = "dice", need = "dice", d = d }) == nil, "dice with need accepted", ctx)
      check(E.apply(s, 1, { k = "dice", d = d }) == nil, "dice from a seat accepted", ctx)
      local ok = E.apply(s, 0, { k = "dice", d = d })
      check(ok == true, "dice rejected", ctx)
      log[#log + 1] = { 0, { k = "dice", d = d } }
      flowDice(F, d[1], d[2])
      if s.cv and not cascSeen then cascSeen = true; totals.cascades = totals.cascades + 1 end
      compareFlow(s, F, ctx)
    elseif s.phase == "game" then
      check(a and a.k == "next" and delay == 3, "system does not offer next", ctx)
      check(E.apply(s, 0, { k = "next" }) == true, "next rejected", ctx)
      log[#log + 1] = { 0, { k = "next" } }
      flowNext(F)
      gameActions = 0; cascSeen = false
      compareFlow(s, F, ctx)
    elseif s.phase == "move" then
      stats.turns = stats.turns + 1
      check(a == nil, "system acts during a move", ctx)
      check(#E.legal(s, 3 - s.turn) == 0, "legal for the seat off turn", ctx)
      check(E.auto(s, 3 - s.turn) == nil, "auto for the seat off turn", ctx)
      local P, ref, eng = compareLegal(s, ctx)
      local list = E.legal(s, s.turn)
      local auto = E.auto(s, s.turn)
      -- the automatic move is one of the legal moves (the first)
      check(auto and auto.k == "move" and deepEq(auto.steps, list[1].steps), "auto is not legal[1]", ctx)
      local m = mode == "bot" and auto or list[R(#list)]
      -- probes: junk, mutated legal moves, a valid reordering
      probe(s, P, ref, randomJunk(), ctx)
      probe(s, P, ref, mutate(m.steps), ctx)
      local shuf = {}
      for i, st in ipairs(m.steps) do shuf[i] = { st[1], st[2] } end
      for i = #shuf, 2, -1 do local j = R(i); shuf[i], shuf[j] = shuf[j], shuf[i] end
      probe(s, P, ref, shuf, ctx)
      checkStage(s, P, ref, m.steps, ctx, R(8) == 1)
      check(E.apply(s, 3 - s.turn, { k = "move", steps = m.steps }) == nil, "move by the seat off turn accepted", ctx)
      local played = (raccepts(P, s.turn, s.left, shuf, ref) and R(2) == 1) and shuf or m.steps
      local me = s.turn
      local okm = E.apply(s, me, { k = "move", steps = played })
      check(okm == true, "chosen legal move rejected", ctx)
      log[#log + 1] = { me, { k = "move", steps = played } }
      -- the reference result for this move
      local after = fromEngine(s, ctx)
      after.won = (s.phase == "game" or s.phase == "match") and s.gp or nil
      local k = rkey(after)
      local rr = ref[k]
      if check(rr ~= nil, "result of the played move is not a legal result", ctx) then
        if rr.P.won then
          if rr.P.won == 2 then
            if s.var == "tapa" and rr.P.off[me] < 15 then totals.mother = totals.mother + 1 else totals.mars = totals.mars + 1 end
          end
          totals.games[F.var] = totals.games[F.var] + 1
        end
        local wasCasc, wasX = F.casc and true, F.casc and F.casc.xfer
        flowMove(F, rr.P, rr.used)
        if wasCasc and not wasX and F.casc and F.casc.xfer then totals.handovers = totals.handovers + 1 end
      end
      compareFlow(s, F, ctx)
    else
      fail("unknown phase " .. tostring(s.phase), ctx); break
    end
  end
  totals.actions = totals.actions + actions
  if actions > totals.maxActions then totals.maxActions = actions end
  totals.matches = totals.matches + 1
  if s.winner then totals.points[s.winner] = totals.points[s.winner] + 1 end
  -- snapshot -> restore -> replay the rest
  if snap then
    totals.snapshots = totals.snapshots + 1
    local c = E.restore(snap)
    local okAll = true
    for i = snapIdx + 1, #log do
      local seat, act = log[i][1], log[i][2]
      if not E.apply(c, seat, act) then okAll = false; break end
    end
    check(okAll and deepEq(E.snapshot(c), E.snapshot(s)), "snapshot/restore replay differs",
      "mode=" .. mode .. " match=" .. mi .. " seed=" .. SEED .. " snapIdx=" .. snapIdx)
    local t = E.snapshot(s); t.score[1] = 99
    check(s.score[1] ~= 99, "snapshot shares tables with the state")
  end
end

-- Random positions -----------------------------------------------------------------------------
local function randomPosition(var)
  for _ = 1, 50 do
    local s = E.new{}
    s.game = ({ std = 1, tapa = 2, gul = 3 })[var]; s.var = var
    s.pts, s.pin = { {}, {} }, { {}, {} }
    for seat = 1, 2 do for q = 1, 24 do s.pts[seat][q], s.pin[seat][q] = 0, 0 end end
    s.bar, s.off, s.rolls = { 0, 0 }, { 0, 0 }, { R(0, 6), R(0, 6) }
    local occ = {} -- abs -> seat
    local pinnedAbs = {}
    local homeBias = R(3) == 1
    for seat = 1, 2 do
      local left = 15
      if var == "std" and R(4) == 1 then s.bar[seat] = R(1, 3); left = left - s.bar[seat] end
      if R(3) == 1 then local o = R(0, left); if R(4) == 1 then o = 0 end; s.off[seat] = o; left = left - o end
      local tries = 0
      while left > 0 and tries < 200 do
        tries = tries + 1
        local q = homeBias and R(1, 8) or R(1, 24)
        local a = absOf(var, seat, q)
        if occ[a] == nil or occ[a] == seat then
          local c = math.min(left, R(1, 4))
          s.pts[seat][q] = s.pts[seat][q] + c; left = left - c; occ[a] = seat
        elseif var == "tapa" and not pinnedAbs[a] and s.pts[3 - seat][ownOf(var, 3 - seat, a)] == 1 and R(2) == 1 then
          -- pin the other seat's lone checker here
          local c = math.min(left, R(1, 3))
          s.pts[seat][q] = c; left = left - c
          s.pin[3 - seat][ownOf(var, 3 - seat, a)] = 1; pinnedAbs[a] = true
        end
      end
      if left > 0 then s.off[seat] = s.off[seat] + left end
    end
    if s.off[1] < 15 and s.off[2] < 15 then
      -- no mother already pinned (that game would be over)
      local okp = true
      for seat = 1, 2 do if s.pin[seat][24] == 1 then okp = false end end
      if okp then
        s.turn = R(2); s.phase = "roll"
        return s
      end
    end
  end
end

local function randomPositions(n)
  local done = 0
  for i = 1, n do
    local var = VARS[(i - 1) % 3 + 1]
    local s = randomPosition(var)
    if s then
      local d = { R(6), R(6) }
      if R(5) == 1 then d[2] = d[1] end
      E.apply(s, 0, { k = "dice", d = d })
      if var == "gul" and d[1] == d[2] and R(3) == 1 then
        -- a cascade step / remainder in progress
        s.cv = R(d[1], 6); s.xfer = R(2) == 1
        local k = s.xfer and R(1, 3) or 4
        s.left = {}
        for j = 1, k do s.left[j] = s.cv end
      end
      if s.phase == "move" then
        local ctx = ctxOf(s, "randomPosition #" .. i .. " seed=" .. SEED)
        local P, ref = compareLegal(s, ctx)
        local list = E.legal(s, s.turn)
        local m = list[R(#list)]
        probe(s, P, ref, randomJunk(), ctx)
        probe(s, P, ref, mutate(m.steps), ctx)
        checkStage(s, P, ref, m.steps, ctx, R(4) == 1)
        done = done + 1
      end
    end
  end
  return done
end

-- Dice uniformity ------------------------------------------------------------------------------
local function hexSeed()
  local t = {}
  for i = 1, 2 * ns.Const.SEED_BYTES do t[i] = string.format("%x", R(0, 15)) end
  return table.concat(t)
end
local function chi2(counts, n, k)
  local e, x = n / k, 0
  for i = 1, k do x = x + (counts[i] - e) ^ 2 / e end
  return x
end
local function diceCheck(n)
  local face1, face2, pair = {}, {}, {}
  for i = 1, 6 do face1[i], face2[i] = 0, 0 end
  for i = 1, 36 do pair[i] = 0 end
  for i = 1, n do
    local seeds = (i % 5 == 0) and { hexSeed() } or { hexSeed(), hexSeed() }
    local x, y = ns.Fair.dice(seeds, ns.Fair.handId("t" .. R(1, 1e6), i))
    if not (x >= 1 and x <= 6 and y >= 1 and y <= 6 and x % 1 == 0 and y % 1 == 0) then
      fail("Fair.dice out of range " .. tostring(x) .. "," .. tostring(y))
    end
    face1[x] = face1[x] + 1; face2[y] = face2[y] + 1; pair[(x - 1) * 6 + y] = pair[(x - 1) * 6 + y] + 1
  end
  local c1, c2, cp = chi2(face1, n, 6), chi2(face2, n, 6), chi2(pair, n, 36)
  -- critical values at p = 0.001: df 5 -> 20.52, df 35 -> 66.62
  check(c1 < 20.52, "die 1 not uniform, chi2=" .. c1)
  check(c2 < 20.52, "die 2 not uniform, chi2=" .. c2)
  check(cp < 66.62, "dice pairs not uniform, chi2=" .. cp)
  return c1, c2, cp, face1, face2
end

-- Run -----------------------------------------------------------------------------------------
local t0 = os.clock()
local half = math.floor(MATCHES / 2)
for i = 1, half do playMatch("random", i) end
for i = half + 1, MATCHES do playMatch("bot", i) end
local t1 = os.clock()
local rp = randomPositions(RANDPOS)
local t2 = os.clock()
local c1, c2, cp, f1, f2 = diceCheck(DICEN)
local t3 = os.clock()

local g = totals.games
print(string.format("Табла soak seed=%d", SEED))
print(string.format("matches %d (random %d, bot %d), games %d (std %d, tapa %d, gul %d), %.1fs",
  totals.matches, half, MATCHES - half, g.std + g.tapa + g.gul, g.std, g.tapa, g.gul, t1 - t0))
print(string.format("  turns %d, legal sets compared %d, apply probes %d, stage checks %d, snapshot replays %d",
  stats.turns, stats.legalCompared, stats.probes, stats.stageChecks, totals.snapshots))
print(string.format("  no-move turns %d, turns cut by the max-dice rule %d, mars %d, mothers %d, cascades %d, hand-overs %d, longest match %d actions, stuck games %d",
  stats.noMove, stats.maxDiceCut, totals.mars, totals.mother, totals.cascades, totals.handovers, totals.maxActions, totals.timeouts))
print(string.format("  match wins seat1 %d seat2 %d", totals.points[1], totals.points[2]))
print(string.format("random positions compared %d, %.1fs", rp, t2 - t1))
print(string.format("dice %d throws: chi2 die1 %.2f die2 %.2f pairs %.2f (crit 20.52 / 66.62), faces1 %s, %.1fs",
  DICEN, c1, c2, cp, ser(f1), t3 - t2))
print(string.format("checks %d, failures %d", checks, fails))
for _, l in ipairs(failLog) do print("FAIL " .. l) end
os.exit(fails == 0 and 0 or 1)
