-- Морски шах soak: luajit tools/sim/ttt_soak.lua [matches] [seed]
-- 1. exhaustive DFS of EVERY reachable round (both starters) through the real engine, checked
--    against an independent reference (string patterns, not the engine's line table);
-- 2. random whole matches (rounds, "next", rematch) against a reference model.
package.path = "tests/helpers/?.lua;" .. package.path
local Loader = require("loader")
local ns = Loader.ns()
local E = ns.Engines.ttt
local matches = tonumber(arg and arg[1]) or 20000
local seed = tonumber(arg and arg[2]) or 1
math.randomseed(seed)

local checks, fails = 0, {}
local function fail(msg)
  fails[#fails + 1] = msg
  if #fails > 20 then print(table.concat(fails, "\n")); os.exit(1) end
end
local function check(c, msg) checks = checks + 1; if not c then fail(msg) end end

-- reference: winner of a board (0 none) by scanning the 3x3 as strings
local function refWinner(b)
  local rows = {}
  for r = 0, 2 do rows[#rows + 1] = b[r * 3 + 1] .. b[r * 3 + 2] .. b[r * 3 + 3] end
  for c = 1, 3 do rows[#rows + 1] = b[c] .. b[c + 3] .. b[c + 6] end
  rows[#rows + 1] = b[1] .. b[5] .. b[9]; rows[#rows + 1] = b[3] .. b[5] .. b[7]
  for _, t in ipairs(rows) do if t == "111" then return 1 elseif t == "222" then return 2 end end
  return 0
end
local function key(s) -- full serialisation for "a rejected move leaves the state untouched"
  local o = {}
  for k, v in pairs(s) do
    local t = {}
    if type(v) == "table" then for i = 1, 9 do if v[i] ~= nil then t[#t + 1] = tostring(v[i]) end end end
    o[#o + 1] = k .. "=" .. (type(v) == "table" and table.concat(t, ",") or tostring(v))
  end
  table.sort(o); return table.concat(o, ";")
end

-- ---- 1. exhaustive ----
local games, wins, draws, nodes = 0, { 0, 0 }, 0, 0
local function dfs(s, board)
  nodes = nodes + 1
  local turn = s.turn
  local before, other = key(s), 3 - turn
  local okLegal = {}
  for _, a in ipairs(E.legal(s, turn)) do okLegal[a.c] = true end
  for c = 1, 9 do
    check((board[c] == 0) == (okLegal[c] == true), "legal mismatch cell " .. c)
    local t = E.restore(s)
    check(E.apply(t, other, { k = "mark", c = c }) == nil, "wrong turn accepted")
    if board[c] ~= 0 then check(E.apply(t, turn, { k = "mark", c = c }) == nil, "occupied accepted") end
    check(key(t) == before, "state changed by rejected move")
  end
  for _, bad in ipairs { 0, 10, 1.5, "1", -1 } do
    local t = E.restore(s); check(E.apply(t, turn, { k = "mark", c = bad }) == nil, "bad cell accepted")
  end
  check(E.legal(s, other)[1] == nil, "legal for non-turn seat")
  local au, first = E.auto(s, turn), nil
  for c = 1, 9 do if board[c] == 0 then first = c break end end
  check(au and au.k == "mark" and au.c == first, "auto not first free")
  check(E.auto(s, other) == nil, "auto for non-turn")
  for c = 1, 9 do
    if board[c] == 0 then
      local t = E.restore(s)
      local nb = { unpack(board) }; nb[c] = turn
      check(E.apply(t, turn, { k = "mark", c = c }) == true, "legal move rejected")
      local w = refWinner(nb)
      local full = true
      for i = 1, 9 do if nb[i] == 0 then full = false end end
      if w ~= 0 then
        games = games + 1; wins[w] = wins[w] + 1
        check(w == turn, "winner is not mover")
        check(t.phase == "round" and t.score[w] == 1 and t.score[3 - w] == 0 and not t.draw and t.turn == nil and t.line, "win state wrong")
        if t.line then check(nb[t.line[1]] == w and nb[t.line[2]] == w and nb[t.line[3]] == w, "bad line") end
        check(E.apply(t, turn, { k = "mark", c = c }) == nil and E.apply(t, 3 - turn, { k = "mark", c = 1 }) == nil, "move after game over")
        check(#E.legal(t, 1) == 0 and #E.legal(t, 2) == 0 and E.auto(t, 1) == nil and E.auto(t, 2) == nil, "legal/auto after over")
        check(E.result(t) == nil, "result before match end")
      elseif full then
        games = games + 1; draws = draws + 1
        check(t.phase == "round" and t.draw and t.score[1] == 0 and t.score[2] == 0 and t.turn == nil and t.line == nil, "draw state wrong")
      else
        check(t.phase == "play" and t.turn == 3 - turn and not t.draw and t.score[1] == 0, "continue state wrong")
        dfs(t, nb)
      end
    end
  end
end
for _, first in ipairs { 1, 2 } do dfs(E.new { first = first }, { 0, 0, 0, 0, 0, 0, 0, 0, 0 }) end
print(("exhaustive: %d games (expected %d), wins by seat 1/2 %d/%d, draws %d, nodes %d"):format(games, 2 * 255168, wins[1], wins[2], draws, nodes))
check(games == 2 * 255168, "game count " .. games)
check(wins[1] + wins[2] + draws == games, "sum")

-- ---- 2. random matches ----
local nrounds = 0
for m = 1, matches do
  local first = math.random(2)
  local s = E.new { first = first }
  local score, round, rfirst = { 0, 0 }, 1, first
  local rematches = math.random(0, 2)
  local trace = {}
  local mode = math.random(3) -- 1 random legal, 2 auto only, 3 mixed
  while true do
    while s.phase == "play" do
      local seat = s.turn
      local a
      if mode == 2 or (mode == 3 and math.random() < 0.5) then a = E.auto(s, seat)
      else local l = E.legal(s, seat); a = l[math.random(#l)] end
      trace[#trace + 1] = seat .. ":" .. a.c
      check(E.apply(s, seat, a) == true, "move rejected (seed " .. seed .. " match " .. m .. ": " .. table.concat(trace, " ") .. ")")
    end
    nrounds = nrounds + 1
    local w = refWinner(s.board)
    if w ~= 0 then score[w] = score[w] + 1 end
    check(s.score[1] == score[1] and s.score[2] == score[2], "score " .. s.score[1] .. s.score[2] .. " vs " .. score[1] .. score[2])
    if score[1] >= 3 or score[2] >= 3 then
      check(s.phase == "match" and s.winner == (score[1] >= 3 and 1 or 2), "match end")
      local r = E.result(s)
      check(r and r.winners[1] == s.winner and r.losers[1] == 3 - s.winner and #r.winners == 1, "result")
      check(E.system(s) == nil, "system after match")
      check(E.apply(s, 0, { k = "next" }) == nil, "next after match")
      local t = E.restore(s)
      check(E.apply(t, 1, { k = "rematch" }) == true and t.phase == "match", "one rematch is not enough")
      if rematches > 0 then
        rematches = rematches - 1
        local x = math.random(2)
        check(E.apply(s, x, { k = "rematch" }) == true and s.phase == "match", "rematch1")
        check(E.apply(s, 3 - x, { k = "rematch" }) == true, "rematch2")
        check(s.phase == "play" and s.score[1] == 0 and s.score[2] == 0 and s.round == 1 and not s.winner, "rematch reset")
        first = 3 - first -- the match starter alternates between matches
        check(s.turn == first, ("rematch starter %s want %s"):format(tostring(s.turn), first))
        score, round, rfirst = { 0, 0 }, 1, first
        trace = {}
      else break end
    else
      check(s.phase == "round", "phase after round")
      local sys = E.system(s)
      check(sys and sys.k == "next", "system")
      check(E.apply(s, 1, { k = "next" }) == nil, "player next")
      check(E.apply(s, 0, sys) == true, "next")
      round = round + 1; rfirst = 3 - rfirst
      check(s.phase == "play" and s.turn == rfirst and s.round == round and s.first == rfirst, "next round state")
      for i = 1, 9 do check(s.board[i] == 0, "board not cleared") end
    end
    check(key(E.restore(E.snapshot(s))) == key(s), "snapshot")
  end
end
print(("random: %d matches, %d rounds"):format(matches, nrounds))
-- ---- 3. Stakes.leadsTo (core/StakesWatch.lua): an honest later state of the same match must "lead" from any earlier one ----
-- (a false "no" would make a client call its honest host a forger after a reconnect that skipped rounds).
local pairsChecked, tampered, tamperCaught = 0, 0, 0
for m = 1, math.floor(matches / 10) do
  local s = E.new { first = math.random(2) }
  local snaps = { E.snapshot(s) }
  while s.phase ~= "match" do
    if s.phase == "play" then
      local l = E.legal(s, s.turn); E.apply(s, s.turn, l[math.random(#l)])
    else E.apply(s, 0, E.system(s)) end
    snaps[#snaps + 1] = E.snapshot(s)
  end
  for i = 1, #snaps do
    for j = i, #snaps do
      pairsChecked = pairsChecked + 1
      check(ns.Stakes.leadsTo(snaps[i], snaps[j]) == true, ("leadsTo false for an honest pair %d->%d (seed %d match %d)"):format(i, j, seed, m))
    end
  end
  -- tampering with the later state: a mark moved/removed, or a score point out of nowhere, must not lead
  for _ = 1, 3 do
    local i = math.random(#snaps - 1)
    local j = math.random(i + 1, #snaps)
    local b = E.snapshot(snaps[j])
    local a = snaps[i]
    local kind = math.random(3)
    if kind == 1 then
      local c = math.random(9)
      if a.board[c] ~= 0 and a.round == b.round then b.board[c] = 3 - a.board[c]; tampered = tampered + 1
        if not ns.Stakes.leadsTo(a, b) then tamperCaught = tamperCaught + 1 else check(false, "flipped mark of the same round led") end end
    elseif kind == 2 and b.phase ~= "match" then
      local who = math.random(2); b.score[who] = b.score[who] + 3; tampered = tampered + 1
      if not ns.Stakes.leadsTo(a, b) then tamperCaught = tamperCaught + 1 else check(false, "free points led") end
    end
  end
end
print(("leadsTo: %d honest pairs ok, tampered states caught %d/%d"):format(pairsChecked, tamperCaught, tampered))
print(("checks %d, failures %d"):format(checks, #fails))
for _, f in ipairs(fails) do print(f) end
os.exit(#fails == 0 and 0 or 1)
