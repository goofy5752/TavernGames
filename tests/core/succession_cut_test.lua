local Sim = require("sim")
local Play = require("play")
local ns = Sim.ns
local C = ns.Const

-- A seat whose client is cut off (it runs, it hears nothing) at a staked table
-- (e2e soak, tools/sim/e2e_soak.lua: seeds 200031, 200028).
local A, B = Play.NAMES[1], Play.NAMES[2]
local D = "Дара Маринова"
local SK = 25000

local function dsBy(sim, author)
  local out = {}
  for _, e in ipairs(Play.entries(sim, nil, "D")) do
    if ns.Ledger.author(e.i) == author then out[#out + 1] = e end
  end
  return out
end

describe("a seat cut off at a staked table", function()
  it("alone it takes the table over but stands nobody up and writes no debt to it", function()
    local sim, cl = Play.guild(2, { D })
    Play.open(sim, cl, "santase", SK, 2)
    for _ = 1, 4 do Play.step(sim, cl[A]) end
    sim:offline(B); sim:run(C.SILENT_AFTER + 5)
    eq(cl[B].session.role, "host") -- it claimed: it cannot tell its own cut from the host's
    sim:run(C.OFFLINE_STAND_SECONDS + 30)
    eq(cl[B].session.seats[1], A) -- the host it lost keeps its seat on the cut-off client
    sim:online(B); sim:run(C.TBL_HEARTBEAT + 5)
    eq(#dsBy(sim, B), 0)
    -- The host stood the silent guest up (its forfeit, B owes A): B gives the table back and
    -- takes up the host's snapshot; its own stand there is no foul of that host's ("unseen").
    eq(cl[A].session.role, "host"); eq(cl[A].session.epoch, 1)
    local bs = cl[B].session -- gone from the table, or watching it under A
    ok(bs == nil or (bs.host == A and bs.mySeat == nil), "B: " .. tostring(bs and bs.role))
    local d = dsBy(sim, A)
    eq(#d, 1); eq({ d[1].f, d[1].t, d[1].why }, { B, A, "offline" })
    for gid, note in pairs(cl[B].env.db.stakeSeen or {}) do
      ok(note.foul ~= "forged", gid .. ": " .. tostring(note.foul))
    end
  end)
end)

describe("a seat cut off at a cash table", function()
  it("stood up offline meanwhile, back it follows the host again and calls nothing forged", function()
    local sim, cl = Play.cash(3)
    local V = Play.NAMES[3]
    local fouls = {}
    local foul = ns.Stakes.foul
    ns.Stakes.foul = function(s, why) fouls[#fouls + 1] = s.client.env.me .. ":" .. why; return foul(s, why) end
    local okRun, err = pcall(function()
      Play.hand(sim, cl[A])
      sim:offline(B); sim:run(C.OFFLINE_STAND_SECONDS + 40)
      eq(cl[A].session.seats[2], false) -- the host stood the silent seat up
      eq(cl[B].session.role, "host")
      sim:online(B); sim:run(C.TBL_HEARTBEAT + 5)
      eq({ cl[A].session.role, cl[A].session.epoch, cl[V].session.host }, { "host", 1, A })
      local bs = cl[B].session
      ok(bs == nil or (bs.host == A and bs.mySeat == nil), "B: " .. tostring(bs and bs.role))
      eq(#dsBy(sim, B), 0)
      for _, f in ipairs(fouls) do ok(not f:find(":forged", 1, true), f) end
    end)
    ns.Stakes.foul = foul
    if not okRun then error(err, 0) end
  end)
end)

describe("two seats claim a table whose host is gone", function()
  -- e2e soak (seed 1100150): the host died and the first candidate was cut off as well; it
  -- claimed alone, the second claimed with the last seat following it. Back, the first won
  -- the seat tie of their epoch and stayed a host of its own: the table ran on twice.
  it("the one nobody follows follows the one the others follow", function()
    local sim, cl = Play.guild(4)
    local I, P, M, G = Play.NAMES[1], Play.NAMES[2], Play.NAMES[3], Play.NAMES[4]
    Play.open(sim, cl, "belot", nil, 4)
    for _ = 1, 4 do Play.step(sim, cl[I]) end
    sim.envs[I].dead = true; sim:offline(I) -- the host's client is gone
    sim:offline(P)
    for _ = 1, C.SILENT_AFTER + 3 * C.CLAIM_STAGGER do
      if cl[M].session.role == "host" then break end
      sim:run(1)
    end
    eq({ cl[P].session.role, cl[M].session.role, cl[G].session.host }, { "host", "host", M })
    sim:online(P); sim:run(C.PING_EVERY + 5)
    eq({ cl[P].session.role, cl[P].session.host, cl[G].session.host, cl[M].session.role }, { "player", M, M, "host" })
    eq({ cl[P].session.seq, cl[G].session.seq, cl[P].session.epoch }, { cl[M].session.seq, cl[M].session.seq, cl[M].session.epoch })
    eq(cl[P].session.state.trickNo, cl[M].session.state.trickNo); eq(cl[P].session.state.turn, cl[M].session.state.turn)
  end)
end)
