local function tocPaths()
  local paths, set = {}, {}
  for line in io.lines("TavernGames.toc") do
    line = line:gsub("\r", "")
    if line:match("%.lua%s*$") and not line:match("^#") then
      line = line:gsub("%s+$", "")
      paths[#paths + 1] = line
      set[line] = true
    end
  end
  return paths, set
end

describe("toc", function()
  it("lists only files that exist", function()
    local paths = tocPaths()
    for _, p in ipairs(paths) do
      local f = io.open(p, "r")
      ok(f, "missing file in TOC: " .. p)
      if f then f:close() end
    end
    ok(true)
  end)

  it("lists every source file", function()
    local _, set = tocPaths()
    for p in io.lines("tests/.files.txt") do
      p = p:gsub("\r", "")
      if p ~= "" then ok(set[p], "not in TOC: " .. p) end
    end
    ok(true)
  end)

  it("compiles every listed non-Libs file", function()
    local paths = tocPaths()
    for _, p in ipairs(paths) do
      if not p:match("^Libs/") then
        local fn, err = loadfile(p)
        ok(type(fn) == "function", "does not compile: " .. p .. " " .. tostring(err))
      end
    end
    ok(true)
  end)
end)
