local _, ns = ...

-- The game's few quiet sounds (spec 5.6): a window opens and closes, a hand is
-- dealt, my own trick. Each goes through ns.Art.play (the SFX channel, muted
-- by db.sound = false). Холдем has a poker room's sounds of its own files
-- instead (ui/games/HoldemSounds.lua).
local Sounds = {}
ns.Sounds = Sounds

-- scope (a table id) -> kind -> the last key seen.
local seen = {}

-- `frame` sounds "open" when it shows and "close" when it hides.
function Sounds.window(frame)
  frame:HookScript("OnShow", function() ns.Art.play("open") end)
  frame:HookScript("OnHide", function() ns.Art.play("close") end)
end

-- Plays `kind` when `key` differs from the last key of that kind at table
-- `scope` (default: the key up to its first ":", the table id) -> true when a
-- sound played. The first key seen at a table is remembered silently (joining a
-- table mid-hand plays nothing), as is a new key with `audible` == false (no
-- hand yet, no trick of mine, an empty pot).
function Sounds.once(kind, key, scope, audible)
  scope = scope or tostring(key):match("^[^:]*")
  local kinds = seen[scope]
  if not kinds then kinds = {}; seen[scope] = kinds end
  local last = kinds[kind]
  kinds[kind] = key
  if last == nil or last == key or audible == false then return false end
  return ns.Art.play(kind)
end
