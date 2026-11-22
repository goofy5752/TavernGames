local Wow = require("wow")

-- A guild world booted with the ui/ files for player "Иван Петров", PLAYER_LOGIN fired.
local M = { ME = "Иван Петров" }

function M.guildWow()
  local w = Wow.new{ ui = true }
  w.inGuild = true
  w.roster = { { name = M.ME .. "-Forever", online = true, guid = Wow.GUID } }
  w:boot()
  w:firstRunDone()
  w:fire("GUILD_ROSTER_UPDATE")
  w:fire("PLAYER_LOGIN")
  return w
end

-- ... and my login queue has closed: my ledger entries leave at once.
function M.readyWow()
  local w = M.guildWow()
  w:advance(w.ns.Const.LEDGER_ADOPT_WAIT + 1)
  return w
end

return M
