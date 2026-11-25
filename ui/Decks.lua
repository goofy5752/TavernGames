local _, ns = ...

-- The card decks (spec 5.2): the cities of the skin's faction, or one race on
-- every suit, and the court (J, Q, K) each face shows. Data and lookups only;
-- the saved choice is ns.db.deck (a key of ORDER; anything else reads as "faction").
local L = ns.L

local Decks = {
  ORDER = { "faction", "human", "nightelf", "dwarf", "gnome", "draenei", "orc", "undead", "tauren", "troll", "bloodelf" },
  -- Accessory layers of the king (k), queen (q) and jack (j), from mockup 08.
  RACES = {
    human = { faction = "alliance", king = "Varian", k = { "crown" }, q = { "hair" }, j = {} },
    nightelf = { faction = "alliance", king = "Tyrande", k = { "ears", "hair" }, q = { "ears", "hair" }, j = { "ears" } },
    dwarf = { faction = "alliance", king = "Magni", k = { "beard", "crown" }, q = { "hair" }, j = { "beard" } },
    gnome = { faction = "alliance", king = "Mekkatorque", k = { "crown" }, q = { "hair" }, j = {} },
    draenei = { faction = "alliance", king = "Velen", k = { "horns", "beard" }, q = { "horns" }, j = { "horns" } },
    orc = { faction = "horde", king = "Thrall", k = { "tusks" }, q = { "tusks", "hair" }, j = { "tusks" } },
    undead = { faction = "horde", king = "Sylvanas", k = { "hood" }, q = { "hood" }, j = { "hood" } },
    tauren = { faction = "horde", king = "Cairne", k = { "horns" }, q = { "horns" }, j = { "horns" } },
    troll = { faction = "horde", king = "Vol'jin", k = { "tusks", "ears" }, q = { "tusks", "hair" }, j = { "tusks", "ears" } },
    bloodelf = { faction = "horde", king = "Kael'thas", k = { "ears", "hair" }, q = { "ears", "hair" }, j = { "ears" } },
  },
  -- The race of each suit (S spades, H hearts, D diamonds, C clubs) in the faction deck.
  CITIES = {
    alliance = { S = "human", H = "nightelf", D = "dwarf", C = "draenei" },
    horde = { S = "orc", H = "undead", D = "tauren", C = "bloodelf" },
  },
}
ns.Decks = Decks

local ROLE = { K = "king", Q = "queen", J = "jack" }

-- The saved deck key, "faction" when it is unset or unknown (the value is left alone).
function Decks.key()
  local k = ns.db and ns.db.deck
  for _, d in ipairs(Decks.ORDER) do
    if d == k then return k end
  end
  return "faction"
end

-- Saves the deck and redraws an open table.
function Decks.set(key)
  ns.db.deck = key
  if ns.TableFrame and ns.TableFrame.refresh then ns.TableFrame.refresh() end
end

-- The faction a deck wears: the skin's for "faction", else the race's own.
function Decks.faction(key, skin)
  local r = Decks.RACES[key]
  if r then return r.faction end
  return skin == "horde" and "horde" or "alliance"
end

-- The court card `face` ("KS", "QH", "JC") shows in deck `key` under `skin`
-- -> { race, faction, role, label }, nil for any other face.
function Decks.court(face, key, skin)
  if type(face) ~= "string" then return nil end
  local role = ROLE[face:sub(1, 1)]
  if not role or #face ~= 2 then return nil end
  local race
  if Decks.RACES[key] then
    race = key
  else
    race = Decks.CITIES[Decks.faction("faction", skin)][face:sub(2, 2)]
  end
  if not race then return nil end
  local r = Decks.RACES[race]
  local label = role == "king" and r.king or L("deck." .. (role == "queen" and "queen" or "jack"))
  return { race = race, faction = r.faction, role = role, label = label }
end

-- The deck's display name.
function Decks.name(key, skin)
  if Decks.RACES[key] then return L("deck.race." .. key) end
  return L("deck.faction." .. Decks.faction("faction", skin))
end
