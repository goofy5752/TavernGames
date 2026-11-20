local _, ns = ...

-- The minimap button: an LDB launcher "TavernGames" with the mug icon, shown by
-- LibDBIcon (position and `hide` live in db.minimap). Left click toggles the
-- main window. Registered at PLAYER_LOGIN, when the saved variables are ready.
local Theme, L = ns.Theme, ns.L

local MinimapButton = {}
ns.Minimap = MinimapButton

local NAME = "TavernGames"

function MinimapButton.init()
  if MinimapButton.object then return end
  local LDB = LibStub("LibDataBroker-1.1", true)
  if not LDB then return end
  MinimapButton.object = LDB:NewDataObject(NAME, {
    type = "launcher",
    label = L("addon.title"),
    icon = Theme.tex.icon,
    OnClick = function(_, button)
      if button == "LeftButton" then ns.MainWindow.toggle() end
    end,
    OnTooltipShow = function(tip)
      tip:AddLine(L("addon.title"), Theme.rgb("brassLight"))
      tip:AddLine(L("minimap.tip"), Theme.rgb("ink"))
    end,
  })
  local Icon = LibStub("LibDBIcon-1.0", true)
  if Icon and MinimapButton.object and ns.db then
    Icon:Register(NAME, MinimapButton.object, ns.db.minimap)
    MinimapButton.icon = Icon
  end
end

-- Shows or hides the button and remembers the choice (the settings tab).
function MinimapButton.setShown(on)
  ns.db.minimap.hide = not on
  local Icon = MinimapButton.icon
  if not Icon then return end
  if on then Icon:Show(NAME) else Icon:Hide(NAME) end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self)
  self:UnregisterEvent("PLAYER_LOGIN")
  MinimapButton.init()
end)
