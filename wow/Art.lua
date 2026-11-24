local _, ns = ...

-- The one place client art and sound are read from (spec section 5.3). Every
-- asset has candidates (client file paths and atlas names), checked at run
-- time: a file counts only when GetFileIDFromPath gives it an id, an atlas
-- only when C_Texture.GetAtlasInfo knows it. An asset the check cannot confirm
-- is missing, and the caller shows our own stand-in. The answer is kept for
-- the session (Art.reset clears it), so no frame repeats the check.
-- /tavern probe art prints Art.report().
local Adapter = ns.Adapter
local lookup = Adapter.lookup

local Art = {}
ns.Art = Art

-- UnitRace's file name -> our race key; UnitSex -> our sex key.
Art.RACE = {
  Human = "human", NightElf = "nightelf", Dwarf = "dwarf", Gnome = "gnome", Draenei = "draenei",
  Orc = "orc", Scourge = "undead", Tauren = "tauren", Troll = "troll", BloodElf = "bloodelf",
}
Art.SEX = { [2] = "male", [3] = "female" }

-- Our race keys in report order, and the set of our sex keys.
local RACES = { "human", "nightelf", "dwarf", "gnome", "draenei", "orc", "undead", "tauren", "troll", "bloodelf" }
local SEXES = { "male", "female" }
local IS_SEX = { male = true, female = true }
local IS_RACE = {}
for _, race in ipairs(RACES) do IS_RACE[race] = true end

local ICONS = "Interface\\Icons\\"
local CRESTS = {
  alliance = { { file = "Interface\\Timer\\Alliance-Logo" }, { atlas = "FactionIcon-Alliance" } },
  horde = { { file = "Interface\\Timer\\Horde-Logo" }, { atlas = "FactionIcon-Horde" } },
}
local LEADERS = {
  human = { "Achievement_Leader_King_Varian_Wrynn" },
  nightelf = { "Achievement_Leader_Tyrande_Whisperwind" },
  dwarf = { "Achievement_Leader_King_Magni_Bronzebeard" },
  gnome = { "Achievement_Leader_Gelbin_Mekkatorque", "Achievement_Leader_Gelbin Mekkatorque", "Achievement_Leader_Mekkatorque" },
  draenei = { "Achievement_Leader_Prophet_Velen" },
  orc = { "Achievement_Leader_ Thrall", "Achievement_Leader_Thrall" },
  undead = { "Achievement_Leader_Sylvanas" },
  tauren = { "Achievement_Leader_Cairne Bloodhoof", "Achievement_Leader_Cairne_Bloodhoof" },
  troll = { "Achievement_Leader_Voljin", "Achievement_Leader_Vol'jin" },
  bloodelf = { "Achievement_Leader_Lorthemar_Theron", "Achievement_Leader_Lor'themar_Theron", "Achievement_Leader_LorthemarTheron" },
}
-- The sex of each race's leader, for a king that falls back to the race's own icon.
Art.LEADER_SEX = { nightelf = "female", undead = "female" }
local COINS = { "gold", "silver", "copper" }
local COIN_FILES = {
  gold = "Interface\\MoneyFrame\\UI-GoldIcon",
  silver = "Interface\\MoneyFrame\\UI-SilverIcon",
  copper = "Interface\\MoneyFrame\\UI-CopperIcon",
}
-- Class tokens whose icon name is not first letter upper, rest lower.
local CLASS_NAMES = { DEATHKNIGHT = "DeathKnight", DEMONHUNTER = "DemonHunter" }

-- The sound of each moment: the first SOUNDKIT name the client has plays.
Art.SOUNDS = {
  open = { "IG_CHARACTER_INFO_OPEN" },
  close = { "IG_CHARACTER_INFO_CLOSE" },
  deal = { "IG_ABILITY_PAGE_TURN" },
  trick = { "IG_BACKPACK_OPEN" },
  coins = { "LOOT_WINDOW_COIN_SOUND", "MONEY_FRAME_OPEN" },
  settled = { "LOOT_WINDOW_COIN_SOUND", "ACHIEVEMENT_MENU_OPEN" }, -- a coin sound on the settled toast (spec 5.4)
  chessMove = { "IG_ABILITY_ICON_DROP" },     -- chess (ui/games/ChessView.lua): a quiet move, a capture, a check, the end
  chessCapture = { "IG_BACKPACK_CLOSE" },
  chessCheck = { "IG_PLAYER_INVITE" },
  chessEnd = { "IG_QUEST_LIST_COMPLETE" },
}
local SOUND_KEYS = { "open", "close", "deal", "trick", "coins", "settled", "chessMove", "chessCapture", "chessCheck", "chessEnd" }

-- What /tavern probe art reports by type(); the last three are of a scratch frame and texture.
local APIS = {
  "GetFileIDFromPath", "C_Texture.GetAtlasInfo", "UnitFactionGroup", "UnitRace", "UnitSex", "UnitIsVisible",
  "SetPortraitTexture", "SetPortraitToTexture", "PlaySound", "ReloadUI",
}

local function capital(s) return s:sub(1, 1):upper() .. s:sub(2):lower() end

local function copy(list)
  local out = {}
  for i, c in ipairs(list) do out[i] = { file = c.file, atlas = c.atlas } end
  return out
end

-- The candidates of an asset, in the order they are tried; {} for an unknown kind or id.
function Art.candidates(kind, id, sub)
  if kind == "crest" then return copy(CRESTS[id] or {}) end
  if kind == "leader" then
    local out = {}
    for i, name in ipairs(LEADERS[id] or {}) do out[i] = { file = ICONS .. name } end
    return out
  end
  if kind == "race" then
    if not (IS_RACE[id] and IS_SEX[sub]) then return {} end
    return {
      { atlas = "raceicon128-" .. id .. "-" .. sub },
      { atlas = "raceicon-" .. id .. "-" .. sub },
      { file = ICONS .. "Achievement_Character_" .. capital(id) .. "_" .. capital(sub) },
    }
  end
  if kind == "class" then
    if type(id) ~= "string" or not id:match("^%u+$") then return {} end
    return { { file = ICONS .. "ClassIcon_" .. (CLASS_NAMES[id] or capital(id)) }, { atlas = "classicon-" .. id:lower() } }
  end
  if kind == "coin" then
    local file = COIN_FILES[id]
    return file and { { file = file } } or {}
  end
  return {}
end

-- Does the client have the candidate? Only a confirmed yes counts.
function Art.present(c)
  if type(c) ~= "table" then return false end
  if c.file then
    local fn = lookup("GetFileIDFromPath")
    if type(fn) ~= "function" then return false end
    local okCall, fileId = pcall(fn, c.file)
    return okCall and type(fileId) == "number" and fileId > 0
  end
  if c.atlas then
    local fn = lookup("C_Texture.GetAtlasInfo")
    if type(fn) ~= "function" then return false end
    local okCall, info = pcall(fn, c.atlas)
    return okCall and type(info) == "table"
  end
  return false
end

local memo = {} -- kind, id, sub -> the candidate found, or false

function Art.reset() memo = {} end

-- The first candidate the client has, or nil.
function Art.find(kind, id, sub)
  local key = tostring(kind) .. "\0" .. tostring(id) .. "\0" .. tostring(sub)
  local hit = memo[key]
  if hit == nil then
    hit = false
    for _, c in ipairs(Art.candidates(kind, id, sub)) do
      if Art.present(c) then hit = c; break end
    end
    memo[key] = hit
  end
  return hit or nil
end

-- Puts the asset on the texture -> true; false (the texture untouched) when the
-- client has none or it is an atlas and the texture cannot take one.
function Art.set(tex, kind, id, sub)
  local c = Art.find(kind, id, sub)
  if not c then return false end
  if c.file then
    tex:SetTexture(c.file)
    if tex.SetTexCoord then tex:SetTexCoord(0, 1, 0, 1) end -- an atlas set before left its own
    return true
  end
  if not tex.SetAtlas then return false end
  tex:SetAtlas(c.atlas)
  return true
end

-- The asset as an inline chat/font-string tag, or nil.
function Art.tag(kind, id, sub)
  local c = Art.find(kind, id, sub)
  if not c then return nil end
  if c.file then return "|T" .. c.file .. ":0|t" end
  return "|A:" .. c.atlas .. ":0:0|a"
end

local function firstSound(kit, names)
  for _, name in ipairs(names or {}) do
    local soundId = rawget(kit, name)
    if type(soundId) == "number" then return soundId end
  end
end

-- The SOUNDKIT id of the moment `key`, or nil: the applied skin's names first
-- (ns.Theme.S.sounds), then Art.SOUNDS.
function Art.sound(key)
  local kit = lookup("SOUNDKIT")
  if type(kit) ~= "table" then return nil end
  local skin = ns.Theme and ns.Theme.S and ns.Theme.S.sounds
  return firstSound(kit, skin and skin[key]) or firstSound(kit, Art.SOUNDS[key])
end

-- Plays the moment's sound on the SFX channel -> true; false when muted or the client has none.
function Art.play(key)
  if ns.db and ns.db.sound == false then return false end
  local soundId, play = Art.sound(key), lookup("PlaySound")
  if not soundId or type(play) ~= "function" then return false end
  return (pcall(play, soundId, "SFX"))
end

-- Every asset of every kind, in report order: { kind, id, sub } triples.
local function assets()
  local out = {}
  local function add(kind, id, sub) out[#out + 1] = { kind, id, sub } end
  add("crest", "alliance"); add("crest", "horde")
  for _, race in ipairs(RACES) do add("leader", race) end
  for _, race in ipairs(RACES) do
    for _, sex in ipairs(SEXES) do add("race", race, sex) end
  end
  local classes = {}
  local colors = lookup("RAID_CLASS_COLORS")
  if type(colors) == "table" then
    for token in pairs(colors) do
      if type(token) == "string" then classes[#classes + 1] = token end
    end
  end
  table.sort(classes)
  for _, token in ipairs(classes) do add("class", token) end
  for _, coin in ipairs(COINS) do add("coin", coin) end
  return out
end

local scratch -- a frame and texture made once, only to ask what methods they have

-- The probe's rows { label, state }: every candidate ("file" / "atlas" / "-"),
-- every sound name ("ok" / "-"), every API (its type()). Also returns how many
-- candidates the client has, and how many there are.
function Art.report()
  local rows, found, total = {}, 0, 0
  for _, a in ipairs(assets()) do
    for _, c in ipairs(Art.candidates(a[1], a[2], a[3])) do
      local state = "-"
      if Art.present(c) then state = c.file and "file" or "atlas" end
      if state ~= "-" then found = found + 1 end
      total = total + 1
      rows[#rows + 1] = { c.file or c.atlas, state }
    end
  end
  local kit, seen = lookup("SOUNDKIT"), {}
  for _, key in ipairs(SOUND_KEYS) do
    for _, name in ipairs(Art.SOUNDS[key]) do
      if not seen[name] then
        seen[name] = true
        local has = type(kit) == "table" and type(rawget(kit, name)) == "number"
        rows[#rows + 1] = { name, has and "ok" or "-" }
      end
    end
  end
  for _, path in ipairs(APIS) do rows[#rows + 1] = { path, type(lookup(path)) } end
  local create = lookup("CreateFrame")
  if not scratch and type(create) == "function" then
    local okFrame, frame = pcall(create, "Frame")
    if okFrame and frame then
      frame:Hide()
      scratch = { frame = frame, texture = frame:CreateTexture() }
    end
  end
  rows[#rows + 1] = { "Texture.SetAtlas", type(scratch and scratch.texture.SetAtlas) }
  rows[#rows + 1] = { "Texture.AddMaskTexture", type(scratch and scratch.texture.AddMaskTexture) }
  rows[#rows + 1] = { "Frame.CreateMaskTexture", type(scratch and scratch.frame.CreateMaskTexture) }
  return rows, found, total
end
