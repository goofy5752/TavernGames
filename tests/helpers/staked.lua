local Wow = require("wow")
local Play = require("play")

-- A guild world booted with the ui/ files for player "Иван Петров", PLAYER_LOGIN fired; the
-- engines named in `staked` take a stake in this world's own namespace (ruling G6).
local M = { ME = "Иван Петров" }

function M.guildWow(staked)
  local w = Wow.new{ ui = true }
  if staked then Play.staked(w.ns, unpack(staked)) end
  w.inGuild = true
  w.roster = { { name = M.ME .. "-Forever", online = true, guid = Wow.GUID } }
  w:boot()
  w:firstRunDone()
  w:fire("GUILD_ROSTER_UPDATE")
  w:fire("PLAYER_LOGIN")
  return w
end

-- ... and my login queue has closed: my ledger entries leave at once.
function M.readyWow(staked)
  local w = M.guildWow(staked)
  w:advance(w.ns.Const.LEDGER_ADOPT_WAIT + 1)
  return w
end

return M
