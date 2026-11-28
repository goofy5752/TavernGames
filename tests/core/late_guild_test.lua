local Sim = require("sim")
local Play = require("play")
local ns = Sim.ns

-- A client that started before the game client knew its guild's name (right
-- after login GetGuildInfo may answer nil): no ledger, so no staked table, until
-- Client:joinGuild opens the ledger (wow/Adapter.lua, on the guild's events).
-- Found in game: „The table's stake is a different one“ at every staked chair.

local A, B = Play.NAMES[1], Play.NAMES[2]
local LATE = "Късна Гилдия"
local SK = 20000 -- 2g

-- The guild of A and B, and LATE: started without a guild name, its saved
-- ledgers kept as a real client's are.
local function world()
  local sim, cl = Play.guild(2)
  sim.options[LATE] = {}
  local env = sim:newEnv(LATE, {})
  env.db.ledger = env.db.ledger or {}
  sim:addFakes(env, {})
  sim:keep(LATE, env.db)
  cl[LATE] = sim:join(LATE, env)
  sim:run(1); sim:settle()
  return sim, cl, env
end

describe("core: a guild known late", function()
  it("no ledger before it: a staked table is neither opened nor sat at", function()
    local sim, cl, env = world()
    local late = cl[LATE]
    eq(env.guild, nil); eq(late.ledger, nil)
    eq({ late:openTable{ game = "santase", access = "guild", turn = 45, stake = SK } }, { nil, "stake" })
    local tid = assert(cl[A]:openTable{ game = "santase", access = "guild", turn = 45, stake = SK })
    sim:run(3)
    eq({ late:sit(tid, 2, SK) }, { nil, "stake" })
    sim:run(2)
    eq(late.session, nil)
  end)

  it("joinGuild opens the ledger, started and heard, and the staked game is played", function()
    local sim, cl, env = world()
    local late = cl[LATE]
    local heard = 0
    late:on("ledger", function() heard = heard + 1 end)
    eq(late:joinGuild("МЕХАНАТА"), true)
    eq(env.guild, "МЕХАНАТА")
    ok(late.ledger and late.ledgerNet and late.ledgerSync and late.stakes and late.pay, "the whole ledger is there")
    ok(heard >= 1, "the ledger event tells the windows")
    ok(env.db.ledger["МЕХАНАТА"] ~= nil, "kept in the saved ledgers under the guild")
    -- once only
    eq(late:joinGuild("МЕХАНАТА"), nil)
    eq(late:joinGuild("Друга"), nil); eq(env.guild, "МЕХАНАТА")
    -- now it sits at a staked table and the match goes live
    local tid = assert(cl[A]:openTable{ game = "santase", access = "guild", turn = 45, stake = SK })
    sim:run(3)
    late:sit(tid, 2, SK)
    sim:run(2)
    ok(late.session and late.session.tid == tid, "seated")
    eq(late.session.stake, SK)
    eq(cl[A].session.status, "live")
    sim:settle()
    -- its ledger syncs as any other's: B's own entry reaches it
    eq(late.ledger.me, LATE)
  end)

  it("refuses a name it cannot use", function()
    local _, cl = world()
    local late = cl[LATE]
    eq(late:joinGuild(nil), nil); eq(late:joinGuild(""), nil); eq(late:joinGuild(5), nil)
    eq(late.ledger, nil)
    -- a client with a ledger keeps it
    local before = cl[B].ledger
    eq(cl[B]:joinGuild("Друга"), nil); ok(cl[B].ledger == before, "kept")
  end)
end)
