local _, ns = ...

-- „Класация“'s board and versus over the records of core/LedgerStats.lua (Stats.games),
-- never stored: one uncached pass over the cached records, asked at most once per 2 s
-- while shown (J3). Net is the gold won: confirmed debts in scope, from the same status
-- the balances tab reads. A Холдем S names one player, so versus counts no Холдем win or
-- loss between two names; only the copper between them shows.
local Stats, View = ns.LedgerStats, ns.LedgerView
local byteLess, floor, abs, max = ns.Util.byteLess, math.floor, math.abs, math.max

local NONE = {}
local function str(v) return type(v) == "string" end

-- Rows sorted by keys: "name" ascending by bytes, "-name" descending, "|name|" by |x| descending.
local function order(rows, ...)
  local keys = {}
  for j, k in ipairs({ ... }) do keys[j] = { k:match("^[-|]?([^|]+)"), k:sub(1, 1) } end
  table.sort(rows, function(p, q)
    for _, k in ipairs(keys) do
      local x, y, how = p[k[1]], q[k[1]], k[2]
      if how == "|" then x, y = abs(x), abs(y) end
      if x ~= y then if how == "-" or how == "|" then return x > y end return byteLess(x, y) end
    end
    return false
  end)
  return rows
end

-- The start of opts' period (nil: all time); is x (a record or a debt) in scope; fn(d) per confirmed debt in scope.
local function scope(L, opts)
  local p = Stats.PERIOD[opts.period]
  return p and (opts.now or L.epoch()) - p, opts.game
end
local function inside(x, from, game) return (not from or x.at >= from) and (not game or x.g == game) end
local function confirmed(L, from, game, fn)
  for _, d in ipairs(View.of(L).debts) do if d.status == "confirmed" and inside(d, from, game) then fn(d) end end
end

-- The board rows in scope (net, wins, games desc, name bytes): every name with a counted
-- game or a confirmed net; fav (none under a game filter); honour: a win run first.
local function tally(L, from, game)
  local t, rows = {}, {}
  local function row(name) t[name] = t[name] or { games = 0, wins = 0, net = 0, run = 0, bw = 0, bl = 0, per = {} }; return t[name] end
  for _, rec in ipairs(Stats.games(L)) do
    for name, how in pairs(inside(rec, from, game) and rec.counts or NONE) do
      local r = row(name)
      r.games, r.wins = r.games + 1, r.wins + (how == "win" and 1 or 0)
      if how == r.kind then r.run = r.run + 1 else r.kind, r.run = how, 1 end
      if how == "win" then r.bw = max(r.bw, r.run) elseif how == "loss" then r.bl = max(r.bl, r.run) end
      if str(rec.g) then r.per[rec.g] = (r.per[rec.g] or 0) + 1 end
    end
  end
  confirmed(L, from, game, function(d) row(d.f).net, row(d.t).net = row(d.f).net - d.c, row(d.t).net + d.c end)
  for name, r in pairs(t) do
    local out = { name = name, games = r.games, wins = r.wins, net = r.net }
    if r.games > 0 then out.pct = floor(r.wins * 100 / r.games + 0.5) end
    for g, k in pairs(game and NONE or r.per) do
      local best = out.fav and r.per[out.fav]
      if not best or k > best or (k == best and byteLess(g, out.fav)) then out.fav = g end
    end
    if r.bw >= Stats.RUN then out.honour = { kind = "wins", n = r.bw }
    elseif r.bl >= Stats.RUN then out.honour = { kind = "losses", n = r.bl } end
    if r.games > 0 or r.net ~= 0 then rows[#rows + 1] = out end
  end
  return order(rows, "-net", "-wins", "-games", "name")
end

-- Rule 6: the highest positive net; else the most wins among players with KING_GAMES games
-- (in board order, so the first row of the most wins).
local function king(rows)
  if rows[1] and rows[1].net > 0 then return rows[1].name end
  local best
  for _, r in ipairs(rows) do if r.games >= Stats.KING_GAMES and r.wins > (best and best.wins or 0) then best = r end end
  return best and best.name
end

-- opts = {period = "week"|"month"|"all", game = id|nil, now = epoch} -> {rows, king, top}.
function Stats.board(L, opts)
  local from, game = scope(L, opts)
  local rows, top = tally(L, from, game), 0
  for _, r in ipairs(rows) do top = max(top, abs(r.net)) end
  return { rows = rows, king = king(game and tally(L, from, nil) or rows), top = top }
end

-- {{name, won, lost, net}}: per opponent of `name`, the counted games on opposite sides
-- and the confirmed copper between them (> 0: name won it); |net|, games, name bytes.
function Stats.versus(L, name, opts)
  local from, game = scope(L, opts)
  local by, out = {}, {}
  local function opp(o) if not by[o] then by[o] = { name = o, won = 0, lost = 0, net = 0, n = 0 }; out[#out + 1] = by[o] end return by[o] end
  for _, rec in ipairs(Stats.games(L)) do
    local me = rec.counts[name]
    for o, how in pairs((me == "win" or me == "loss") and inside(rec, from, game) and rec.counts or NONE) do
      if how ~= me and how ~= "draw" then
        local x = opp(o)
        x.won, x.lost, x.n = x.won + (me == "win" and 1 or 0), x.lost + (me == "loss" and 1 or 0), x.n + 1
      end
    end
  end
  confirmed(L, from, game, function(d)
    if d.t == name then opp(d.f).net = opp(d.f).net + d.c elseif d.f == name then opp(d.t).net = opp(d.t).net - d.c end
  end)
  for j = #out, 1, -1 do if out[j].n == 0 and out[j].net == 0 then table.remove(out, j) end end
  order(out, "|net|", "-n", "name")
  for _, x in ipairs(out) do x.n = nil end
  return out
end

return Stats
