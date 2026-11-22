-- Staked tables of Сантасе, Белот and Табла in the simulator, played by the
-- engines' own automatic moves (stage F2). local Play = require("play")
local Sim = require("sim")

local Play = {}

-- Seats 1..4: Иван and Мария are partners in Белот (seats 1 and 3).
Play.NAMES = { "Иван Петров", "Петър Колев", "Мария Стоянова", "Гошо Тодоров" }

local pending = {} -- the restores of Play.short not run yet, in the order made

-- Play.staked([ns,] id, ...): the engines `id` take a stake in `ns` (default
-- Sim.ns) -> a function that puts the old flags back and runs Play.restore().
function Play.staked(ns, ...)
  local ids = { ... }
  if type(ns) ~= "table" then table.insert(ids, 1, ns); ns = Sim.ns end
  local old = {}
  for i, id in ipairs(ids) do old[i] = ns.Engines[id].stakes; ns.Engines[id].stakes = true end
  return function()
    for i, id in ipairs(ids) do ns.Engines[id].stakes = old[i] end
    Play.restore()
  end
end

-- The first n of NAMES and the names in `more`, past their login queues -> sim, cl (cl[name]).
function Play.guild(n, more)
  local sim, cl = Sim.new(), {}
  for i = 1, n do cl[Play.NAMES[i]] = sim:add(Play.NAMES[i]) end
  for _, name in ipairs(more or {}) do cl[name] = sim:add(name) end
  sim:run(1)
  sim:settle()
  return sim, cl
end

-- NAMES[1] opens `game` at stake sk (nil: for fun), NAMES[2..n] sit in seats
-- 2..n with sk: the match is live -> tid.
function Play.open(sim, cl, game, sk, n)
  local host = cl[Play.NAMES[1]]
  local tid = assert(host:openTable{ game = game, access = "guild", turn = 45, stake = sk })
  sim:run(3)
  for seat = 2, n do
    cl[Play.NAMES[seat]]:sit(tid, seat, sk)
    sim:run(1)
  end
  assert(host.session and host.session.status == "live", "the match is not live")
  return tid
end

-- The seat on turn at host's table moves from its own client (engine.bot when
-- the engine has one, else its automatic move); then one second.
function Play.step(sim, host)
  local s = host.session
  local seat = s and s.status == "live" and s.state and s.state.turn
  local cl = seat and sim.clients[s.seats[seat]]
  if cl and cl.session and cl.session.state then
    local E, a = cl.session:engine(), nil
    if E.bot then a = E.bot(cl.session.state, seat, cl.env.random) end
    if a then cl:act(a) else cl:playAuto() end
  end
  sim:run(1)
end

-- Steps until host's game is over (an error after `limit`, default 6000,
-- steps) -> the last "result" payload host emitted.
function Play.finish(sim, host, limit)
  local last
  host:on("result", function(r) last = r end)
  for _ = 1, limit or 6000 do
    if host.session and host.session:gameOver() then return last end
    Play.step(sim, host)
  end
  error("the match did not end")
end

-- The match target of engine `id` becomes 1 (the first scored hand or game
-- ends the match) -> a function that puts it back.
function Play.short(id)
  local E = Sim.ns.Engines[id]
  local key = id == "santase" and "GOAL" or "TARGET"
  local was, done = E[key], false
  local function back()
    if done then return end
    done, E[key] = true, was
    for i, f in ipairs(pending) do if f == back then table.remove(pending, i); break end end
  end
  E[key] = 1
  pending[#pending + 1] = back
  return back
end

-- Runs every restore of Play.short still pending.
function Play.restore()
  while #pending > 0 do pending[#pending]() end
end

-- The debt gid|f|t as client's ledger shows it, or nil.
function Play.debt(client, gid, f, t)
  local key = gid .. "|" .. f .. "|" .. t
  for _, d in ipairs(Sim.ns.LedgerView.of(client.ledger).debts) do
    if d.key == key then return d end
  end
  return nil
end

-- The entries of kind k in the GUILD LEVs `from` sent (from == nil: anyone).
function Play.entries(sim, from, k)
  local out = {}
  for _, m in ipairs(sim.sent) do
    if m.channel == "GUILD" and m.msg.t == "LEV" and (from == nil or m.from == from) then
      for _, e in ipairs(m.msg.ev or {}) do if e.k == k then out[#out + 1] = e end end
    end
  end
  return out
end

return Play
