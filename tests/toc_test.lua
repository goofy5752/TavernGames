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

describe(".pkgmeta", function()
  it("pins every external to the tag recorded in LICENSE-THIRD-PARTY.md", function()
    local f = assert(io.open("LICENSE-THIRD-PARTY.md", "r"))
    local license = f:read("*a")
    f:close()
    local tags, current = {}, nil
    for line in io.lines(".pkgmeta") do
      line = line:gsub("\r", "")
      local path = line:match("^  (Libs/[^:]+):%s*$")
      if path then current = path end
      local tag = line:match("^    tag:%s*(%S+)%s*$")
      if tag and current then tags[current] = tag end
    end
    local expected = {
      ["Libs/LibStub"] = "Release-r1403", ["Libs/CallbackHandler-1.0"] = "Release-r1403",
      ["Libs/AceAddon-3.0"] = "Release-r1403", ["Libs/AceComm-3.0"] = "Release-r1403",
      ["Libs/AceSerializer-3.0"] = "Release-r1403", ["Libs/AceDB-3.0"] = "Release-r1403",
      ["Libs/LibDeflate"] = "1.0.2-release", ["Libs/LibDataBroker-1.1"] = "v1.1.4",
      ["Libs/LibDBIcon-1.0"] = "v12.1.2",
    }
    eq(tags, expected)
    for _, tag in pairs(tags) do ok(license:find(tag, 1, true), "tag not in LICENSE-THIRD-PARTY.md: " .. tag) end
  end)

  it("the big files keep their limits", function()
    local function lines(path) local n = 0; for _ in io.lines(path) do n = n + 1 end; return n end
    ok(lines("core/Session.lua") < 540, "Session.lua"); ok(lines("core/Deal.lua") <= 700, "Deal.lua " .. lines("core/Deal.lua"))
    ok(lines("core/DealHooks.lua") < 400, "DealHooks.lua"); ok(lines("ui/TableFrame.lua") < 600, "TableFrame.lua " .. lines("ui/TableFrame.lua"))
    ok(lines("core/Book.lua") < 260, "Book.lua " .. lines("core/Book.lua")); ok(lines("core/Cash.lua") < 280, "Cash.lua " .. lines("core/Cash.lua"))
    ok(lines("core/BookKeys.lua") < 260, "BookKeys.lua " .. lines("core/BookKeys.lua")); ok(lines("core/BookCheck.lua") < 260, "BookCheck.lua")
    ok(lines("core/Ledger.lua") < 300, "Ledger.lua " .. lines("core/Ledger.lua")); ok(lines("core/LedgerStore.lua") < 260, "LedgerStore.lua " .. lines("core/LedgerStore.lua"))
    ok(lines("core/LedgerDeny.lua") < 200, "LedgerDeny.lua " .. lines("core/LedgerDeny.lua")); ok(lines("core/LedgerHash.lua") < 160, "LedgerHash.lua " .. lines("core/LedgerHash.lua")); ok(lines("core/LedgerView.lua") < 260, "LedgerView.lua " .. lines("core/LedgerView.lua"))
    ok(lines("core/LedgerStats.lua") < 260, "LedgerStats.lua " .. lines("core/LedgerStats.lua")); ok(lines("core/LedgerBoard.lua") < 160, "LedgerBoard.lua " .. lines("core/LedgerBoard.lua"))
    ok(lines("core/LedgerNet.lua") < 240, "LedgerNet.lua " .. lines("core/LedgerNet.lua")); ok(lines("core/LedgerSend.lua") < 120, "LedgerSend.lua " .. lines("core/LedgerSend.lua")); ok(lines("core/LedgerQueue.lua") < 120, "LedgerQueue.lua " .. lines("core/LedgerQueue.lua")); ok(lines("core/LedgerRefused.lua") < 140, "LedgerRefused.lua " .. lines("core/LedgerRefused.lua"))
    ok(lines("core/LedgerStub.lua") < 160, "LedgerStub.lua " .. lines("core/LedgerStub.lua"))
    ok(lines("core/LedgerSyncTail.lua") < 100, "LedgerSyncTail.lua " .. lines("core/LedgerSyncTail.lua"))
    ok(lines("core/LedgerSyncAgain.lua") < 60, "LedgerSyncAgain.lua " .. lines("core/LedgerSyncAgain.lua"))
    ok(lines("core/LedgerHistory.lua") < 140, "LedgerHistory.lua " .. lines("core/LedgerHistory.lua"))
    ok(lines("ui/BookList.lua") < 140, "BookList.lua " .. lines("ui/BookList.lua")); ok(lines("ui/BoardTab.lua") < 300, "BoardTab.lua " .. lines("ui/BoardTab.lua")); ok(lines("ui/HistoryTab.lua") < 300, "HistoryTab.lua " .. lines("ui/HistoryTab.lua"))
    ok(lines("core/LedgerSync.lua") < 300, "LedgerSync.lua " .. lines("core/LedgerSync.lua")); ok(lines("core/LedgerSyncPage.lua") < 200, "LedgerSyncPage.lua " .. lines("core/LedgerSyncPage.lua")); ok(lines("core/LedgerSyncVector.lua") < 160, "LedgerSyncVector.lua " .. lines("core/LedgerSyncVector.lua"))
    ok(lines("core/Stakes.lua") < 340, "Stakes.lua " .. lines("core/Stakes.lua")); ok(lines("core/StakesWatch.lua") < 260, "StakesWatch.lua " .. lines("core/StakesWatch.lua"))
    ok(lines("core/StakesBook.lua") < 260, "StakesBook.lua " .. lines("core/StakesBook.lua")); ok(lines("core/StakesClaims.lua") < 120, "StakesClaims.lua " .. lines("core/StakesClaims.lua"))
    ok(lines("core/StakesStart.lua") < 140, "StakesStart.lua " .. lines("core/StakesStart.lua"))
    ok(lines("core/StakesFair.lua") < 200, "StakesFair.lua " .. lines("core/StakesFair.lua")); ok(lines("core/StakesCash.lua") < 260, "StakesCash.lua " .. lines("core/StakesCash.lua"))
    ok(lines("engines/holdem_cash.lua") < 200, "holdem_cash.lua " .. lines("engines/holdem_cash.lua"))
    ok(lines("core/StakesCashOwe.lua") < 260, "StakesCashOwe.lua " .. lines("core/StakesCashOwe.lua"))
    ok(lines("core/StakesCashWord.lua") < 100, "StakesCashWord.lua " .. lines("core/StakesCashWord.lua"))
    ok(lines("core/CashOut.lua") < 140, "CashOut.lua " .. lines("core/CashOut.lua"))
    ok(lines("core/StakesCashLate.lua") < 200, "StakesCashLate.lua " .. lines("core/StakesCashLate.lua"))
    ok(lines("core/StakesCashKey.lua") < 80, "StakesCashKey.lua " .. lines("core/StakesCashKey.lua"))
    ok(lines("ui/games/HoldemCashView.lua") < 300, "HoldemCashView.lua " .. lines("ui/games/HoldemCashView.lua"))
    ok(lines("core/Pay.lua") < 240, "Pay.lua " .. lines("core/Pay.lua")); ok(lines("core/PaySubject.lua") < 80, "PaySubject.lua " .. lines("core/PaySubject.lua")); ok(lines("core/PayGuard.lua") < 120, "PayGuard.lua " .. lines("core/PayGuard.lua"))
  end)
end)
