-- Test loader: builds the addon namespace from TavernGames.toc.
local Loader = {}

function Loader.ns()
  local ns = {}
  local f = assert(io.open("TavernGames.toc", "r"))
  for line in f:lines() do
    line = line:gsub("\r", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if line:match("^core/") or line:match("^engines/") or line:match("^locale/") then
      local chunk, err = loadfile(line)
      if not chunk then error(err, 0) end
      chunk("TavernGames", ns)
    end
  end
  f:close()
  return ns
end

-- Runs a Libs/ file in the global environment (Task 9 only).
function Loader.lib(path)
  local chunk, err = loadfile(path)
  if not chunk then error(err, 0) end
  return chunk("TavernGames")
end

return Loader
