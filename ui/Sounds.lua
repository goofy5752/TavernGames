local _, ns = ...

-- The windows' quiet sounds (spec 5.6): a window opens and closes, through ns.Art.play (the SFX channel,
-- muted by db.sound = false). The games' sounds are our own files: Холдем's in ui/games/HoldemSounds.lua,
-- every other game's in ui/games/GameSounds.lua.
local Sounds = {}
ns.Sounds = Sounds

-- `frame` sounds "open" when it shows and "close" when it hides.
function Sounds.window(frame)
  frame:HookScript("OnShow", function() ns.Art.play("open") end)
  frame:HookScript("OnHide", function() ns.Art.play("close") end)
end
