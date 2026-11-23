local Wow = require("wow")

local ALLIANCE_LOGO = "Interface\\Timer\\Alliance-Logo"

describe("art: the check", function()
  it("a file counts only when GetFileIDFromPath confirms it, an atlas only by GetAtlasInfo", function()
    local w = Wow.new{}; local A = w.ns.Art
    eq(A.find("crest", "alliance"), nil)
    w:hasAtlas("FactionIcon-Alliance"); A.reset()
    eq(A.find("crest", "alliance"), { atlas = "FactionIcon-Alliance" })
    w:hasFile(ALLIANCE_LOGO); A.reset()
    eq(A.find("crest", "alliance"), { file = ALLIANCE_LOGO }) -- the first candidate wins
  end)

  it("a file is looked up by its lower-case path; an answer of 0 or a raise is no file", function()
    local w = Wow.new{}; local A = w.ns.Art
    w:hasFile("INTERFACE\\TIMER\\HORDE-LOGO")
    ok(A.present({ file = "Interface\\Timer\\Horde-Logo" }))
    w.G.GetFileIDFromPath = function() return 0 end
    eq(A.present({ file = "Interface\\Timer\\Horde-Logo" }), false)
    w.G.GetFileIDFromPath = function() error("no") end
    eq(A.present({ file = "Interface\\Timer\\Horde-Logo" }), false)
    w.G.C_Texture.GetAtlasInfo = function() error("no") end
    eq(A.present({ atlas = "FactionIcon-Horde" }), false)
    eq(A.present({}), false)
  end)

  it("a client without the check APIs has nothing", function()
    local w = Wow.new{ noArt = true }
    eq(w.G.GetFileIDFromPath, nil); eq(w.G.C_Texture, nil)
    eq(w.ns.Art.find("coin", "gold"), nil); eq(w.ns.Art.tag("coin", "gold"), nil)
    eq(w.ns.Art.set(w.G.CreateFrame("Frame"):CreateTexture(), "leader", "orc"), false)
  end)

  it("an atlas is not set on a texture without SetAtlas; an unknown kind or id finds nothing", function()
    local w = Wow.new{}; local A = w.ns.Art
    w:hasAtlas("raceicon128-orc-male")
    local bare = { SetTexture = function(t, p) t.texture = p end }
    eq(A.set(bare, "race", "orc", "male"), false); eq(bare.texture, nil)
    local tex = w.G.CreateFrame("Frame"):CreateTexture()
    tex:SetColorTexture(1, 0, 0)
    eq(A.set(tex, "race", "orc", "male"), true)
    eq(tex:GetAtlas(), "raceicon128-orc-male"); eq(tex.color, nil); eq(tex:GetTexture(), nil)
    eq(A.tag("race", "orc", "male"), "|A:raceicon128-orc-male:0:0|a")
    w:hasFile("Interface\\Icons\\Achievement_Leader_Thrall")
    eq(A.set(tex, "leader", "orc"), true)
    eq(tex:GetTexture(), "Interface\\Icons\\Achievement_Leader_Thrall"); eq(tex:GetAtlas(), nil)
    eq(A.tag("leader", "orc"), "|TInterface\\Icons\\Achievement_Leader_Thrall:0|t")
    eq(A.set(tex, "leader", "tauren"), false); eq(tex:GetTexture(), "Interface\\Icons\\Achievement_Leader_Thrall")
    eq(A.tag("leader", "tauren"), nil)
    for _, c in ipairs({ { "banner", "alliance" }, { "crest", "neutral" }, { "leader", "murloc" }, { "race", "orc", "other" },
                         { "race", "murloc", "male" }, { "race", "orc" }, { "class", nil }, { "class", "mage" },
                         { "coin", "platinum" }, { nil, nil } }) do
      eq(A.candidates(c[1], c[2], c[3]), {}, tostring(c[1]) .. " " .. tostring(c[2]))
      eq(A.find(c[1], c[2], c[3]), nil)
    end
  end)

  it("a file after an atlas on the same texture shows the whole file (the atlas's tex-coords reset)", function()
    local w = Wow.new{}; local A = w.ns.Art
    w:hasAtlas("raceicon128-orc-female"); w:hasFile("Interface\\Icons\\Achievement_Leader_Thrall")
    local tex = w.G.CreateFrame("Frame"):CreateTexture()
    eq(A.set(tex, "race", "orc", "female"), true)
    ok(tex.texCoord[1] ~= 0, "the fake atlas sets its own coords")
    eq(A.set(tex, "leader", "orc"), true)
    eq(tex:GetTexture(), "Interface\\Icons\\Achievement_Leader_Thrall"); eq(tex.texCoord, { 0, 1, 0, 1 })
  end)

  it("lists the candidates of every kind in order", function()
    local A = Wow.new{}.ns.Art
    eq(A.candidates("crest", "horde"), { { file = "Interface\\Timer\\Horde-Logo" }, { atlas = "FactionIcon-Horde" } })
    eq(A.candidates("leader", "tauren"), { { file = "Interface\\Icons\\Achievement_Leader_Cairne Bloodhoof" },
      { file = "Interface\\Icons\\Achievement_Leader_Cairne_Bloodhoof" } })
    eq(A.candidates("leader", "gnome"), { { file = "Interface\\Icons\\Achievement_Leader_Gelbin_Mekkatorque" } })
    eq(A.candidates("leader", "troll"), { { file = "Interface\\Icons\\Achievement_Leader_Voljin" } })
    eq(A.candidates("race", "bloodelf", "female"), { { atlas = "raceicon128-bloodelf-female" },
      { atlas = "raceicon-bloodelf-female" }, { file = "Interface\\Icons\\Achievement_Character_Bloodelf_Female" } })
    eq(A.candidates("race", "undead", "male")[3], { file = "Interface\\Icons\\Achievement_Character_Undead_Male" })
    eq(A.candidates("class", "DEATHKNIGHT"), { { file = "Interface\\Icons\\ClassIcon_DeathKnight" }, { atlas = "classicon-deathknight" } })
    eq(A.candidates("class", "DEMONHUNTER")[1], { file = "Interface\\Icons\\ClassIcon_DemonHunter" })
    eq(A.candidates("class", "MAGE"), { { file = "Interface\\Icons\\ClassIcon_Mage" }, { atlas = "classicon-mage" } })
    eq(A.candidates("coin", "copper"), { { file = "Interface\\MoneyFrame\\UI-CopperIcon" } })
    eq(A.RACE.Scourge, "undead"); eq(A.SEX[3], "female")
    local leaders = 0
    for _, race in pairs(A.RACE) do
      leaders = leaders + 1
      ok(#A.candidates("leader", race) >= 1, race); eq(#A.candidates("race", race, "male"), 3, race)
    end
    eq(leaders, 10)
  end)

  it("the lookup is memoized until reset", function()
    local w = Wow.new{}; local A = w.ns.Art
    local calls, orig = 0, w.G.GetFileIDFromPath
    w.G.GetFileIDFromPath = function(path) calls = calls + 1; return orig(path) end
    eq(A.find("coin", "gold"), nil); eq(calls, 1)
    eq(A.find("coin", "gold"), nil); eq(A.tag("coin", "gold"), nil); eq(calls, 1)
    w:hasFile("Interface\\MoneyFrame\\UI-GoldIcon")
    eq(A.find("coin", "gold"), nil); eq(calls, 1) -- still the memo
    A.reset()
    eq(A.find("coin", "gold"), { file = "Interface\\MoneyFrame\\UI-GoldIcon" }); eq(calls, 2)
    eq(A.tag("coin", "gold"), "|TInterface\\MoneyFrame\\UI-GoldIcon:0|t"); eq(calls, 2)
  end)
end)

describe("art: sounds", function()
  it("a sound plays on SFX only when SOUNDKIT names it", function()
    local w = Wow.new{}; local A = w.ns.Art
    w.G.SOUNDKIT.LOOT_WINDOW_COIN_SOUND = 120
    eq(w.ns.db, nil); eq(A.play("coins"), true); eq(w.sounds[1], { 120, "SFX" }) -- before the db: not muted, no error
    w:boot()
    eq(A.sound("coins"), 120); eq(A.sound("settled"), 120); eq(A.sound("open"), nil); eq(A.sound("nope"), nil)
    w.G.SOUNDKIT.ACHIEVEMENT_MENU_OPEN = 7
    eq(A.sound("settled"), 120) -- the coin sound comes first on the settled toast
    local n = #w.sounds
    eq(A.play("coins"), true); eq(w.sounds[n + 1], { 120, "SFX" })
    eq(A.play("open"), false); eq(#w.sounds, n + 1)
    w.G.SOUNDKIT = nil
    eq(A.sound("coins"), nil); eq(A.play("coins"), false); eq(#w.sounds, n + 1)
  end)

  it("the applied skin's sound of a moment comes before the shared one", function()
    local w = Wow.new{ ui = true }; local A, T = w.ns.Art, w.ns.Theme
    w.G.SOUNDKIT.LOOT_WINDOW_COIN_SOUND, w.G.SOUNDKIT.HORDE_COINS = 120, 9
    eq(T.SKINS.alliance.sounds, {}); eq(T.SKINS.horde.sounds, {})
    T.SKINS.horde.sounds.coins = { "HORDE_COINS" }
    eq(A.sound("coins"), 120) -- alliance applied: no skin sound
    T.apply("horde"); eq(A.sound("coins"), 9)
    T.SKINS.horde.sounds.coins = { "MISSING" }; eq(A.sound("coins"), 120) -- a name the client lacks falls through
    T.SKINS.horde.sounds.coins = nil
  end)
end)

describe("art: report", function()
  local function row(rows, label)
    for _, r in ipairs(rows) do
      if r[1] == label then return r[2] end
    end
  end

  it("one row per candidate, sound and API; classes from RAID_CLASS_COLORS, sorted", function()
    local w = Wow.new{}; local A = w.ns.Art
    w.G.RAID_CLASS_COLORS = { WARRIOR = {}, MAGE = {} }
    w:hasFile(ALLIANCE_LOGO); w:hasAtlas("classicon-warrior")
    w.G.SOUNDKIT.IG_BACKPACK_OPEN = 862
    local rows, found, total = A.report()
    eq(row(rows, ALLIANCE_LOGO), "file"); eq(row(rows, "FactionIcon-Alliance"), "-")
    eq(row(rows, "classicon-warrior"), "atlas"); eq(row(rows, "Interface\\Icons\\ClassIcon_Warrior"), "-")
    eq(row(rows, "IG_BACKPACK_OPEN"), "ok"); eq(row(rows, "MONEY_FRAME_OPEN"), "-")
    eq(row(rows, "GetFileIDFromPath"), "function"); eq(row(rows, "C_Texture.GetAtlasInfo"), "function")
    eq(row(rows, "UnitIsVisible"), "function"); eq(row(rows, "SetPortraitToTexture"), "function")
    eq(row(rows, "Texture.SetAtlas"), "function"); eq(row(rows, "Texture.AddMaskTexture"), "function")
    eq(row(rows, "Frame.CreateMaskTexture"), "function")
    local mage, warrior, coins
    for i, r in ipairs(rows) do
      if r[1] == "classicon-mage" then mage = i end
      if r[1] == "Interface\\Icons\\ClassIcon_Warrior" then warrior = i end
      if r[1] == "Interface\\MoneyFrame\\UI-GoldIcon" then coins = i end
    end
    ok(mage < warrior and warrior < coins, "class order")
    local coinRows = 0
    for _, r in ipairs(rows) do if r[1] == "LOOT_WINDOW_COIN_SOUND" then coinRows = coinRows + 1 end end
    eq(coinRows, 1) -- a sound name named by two keys is one row
    -- 2 crests x 2, 11 leader files, 10 races x 2 sexes x 3, 2 classes x 2, 3 coins
    eq(found, 2); eq(total, 4 + 11 + 60 + 4 + 3)
  end)

  it("a client without the check APIs reports every asset missing", function()
    local w = Wow.new{ noArt = true }
    w:hasFile(ALLIANCE_LOGO)
    local rows, found = w.ns.Art.report()
    eq(found, 0); eq(row(rows, ALLIANCE_LOGO), "-"); eq(row(rows, "GetFileIDFromPath"), "nil"); eq(row(rows, "C_Texture.GetAtlasInfo"), "nil")
  end)
end)

describe("fake client: units and portraits", function()
  it("faction, race, sex, visibility and the portrait calls", function()
    local w = Wow.new{}; local G = w.G
    eq({ G.UnitFactionGroup("player") }, { "Alliance", "Alliance" })
    eq({ G.UnitRace("player") }, { "Човек", "Human", 1 }); eq(G.UnitSex("player"), 2)
    w.faction, w.race, w.sex = "Horde", { "Орк", "Orc", 2 }, 3
    eq(G.UnitFactionGroup("player"), "Horde"); eq(select(2, G.UnitRace("player")), "Orc"); eq(G.UnitSex("player"), 3)
    eq(G.UnitIsVisible("player"), true); eq(G.UnitIsVisible("party1"), false)
    w.units.party1 = "Player-1-00000002"; eq(G.UnitIsVisible("party1"), true)
    w.visible.party1 = false; eq(G.UnitIsVisible("party1"), false)
    local f = G.CreateFrame("Frame"); local tex = f:CreateTexture()
    G.SetPortraitTexture(tex, "party1"); eq(tex.portrait, "party1"); eq(tex:GetTexture(), "portrait:party1")
    G.SetPortraitToTexture(tex, "Interface\\Icons\\X"); eq(tex:GetTexture(), "Interface\\Icons\\X"); eq(tex.round, true)
    local m = f:CreateMaskTexture(); eq(m:GetObjectType(), "MaskTexture")
    m:SetTexture("mask"); tex:AddMaskTexture(m); eq(tex.masks, { m })
    tex:SetAtlas("a"); eq(tex:GetAtlas(), "a"); tex:SetTexture("b"); eq(tex:GetAtlas(), nil)
  end)
end)
