local _, ns = ...

-- A player's name on screen (the owner's rule, 2026-11-24). Where room is tight
-- (the hall's chairs and tables, the list of who is in the tavern, the table's
-- plates and seats, the Death Roll ladder, the stake panels, the toasts, the hand
-- history) a name is short: Names.short among the names shown together (a
-- person's first word, a bot's own name, the next word's initial when two of
-- them would read the same) and, after a bot's, the bot mark: a small brass cog
-- (media/botmark.tga, tools/gen_botmark.py) inline at the text's height. A hover
-- over such a place gives the whole name without the realm (W.nameTip). The
-- ledger and the leaderboard keep the whole names. Only what is drawn changes:
-- chat, the printed lines and the saved data keep the names as they are.
local Theme, W, Names = ns.Theme, ns.W, ns.Names

-- The bot mark, an inline texture as high as the line's text.
W.BOT_MARK = "|T" .. Theme.tex.botmark .. ":0|t"

-- The whole name for a tooltip: no realm; "?" for no name.
function W.fullName(name) return Names.normalize(name) or "?" end

-- The short name of `name` among `others` (the names shown with it), plain, a
-- bot's with its mark after it.
function W.short(name, others)
  local short = Names.short(name, others)
  if Names.isBot(name) then return short .. " " .. W.BOT_MARK end
  return short
end

-- The same in the player's class colour, for a sentence (the mark keeps its brass).
function W.shortColored(client, name, others)
  if type(name) ~= "string" then return "?" end
  local text = W.paint(Names.short(name, others), W.nameColor(client, name))
  if Names.isBot(name) then return text .. " " .. W.BOT_MARK end
  return text
end

-- W.shortColored among the seats of my table (ns.client.session), for a game's line of text.
function W.seatColored(name)
  local s = ns.client and ns.client.session
  return W.shortColored(ns.client, name, s and s.seats)
end

-- The names of `names` (a name, a list with gaps or seats set to false, or nil), each once.
local function list(names)
  if type(names) == "string" then return { names } end
  local out, seen, top = {}, {}, 0
  names = type(names) == "table" and names or {}
  for k in pairs(names) do if type(k) == "number" and k > top then top = k end end
  for i = 1, top do
    local name = names[i]
    local full = type(name) == "string" and Names.normalize(name)
    if full and not seen[full] then seen[full] = true; out[#out + 1] = name end
  end
  return out
end

-- Adds the whole names of `names` to GameTooltip `tip` (owned already), each in its class
-- colour; `title`: the first one is the tooltip's title -> how many.
function W.nameLines(tip, names, title)
  local all = list(names)
  for i, name in ipairs(all) do
    local r, g, b = W.nameColor(ns.client, name)
    if i == 1 and title then tip:SetText(W.fullName(name), r, g, b) else tip:AddLine(W.fullName(name), r, g, b) end
  end
  return #all
end

-- A hover over `frame` shows the whole names get() returns (a name, a list, or nil for none)
-- in a GameTooltip. Hooked, so the frame's own OnEnter / OnLeave keep working.
function W.nameTip(frame, get)
  frame:EnableMouse(true)
  frame:HookScript("OnEnter", function(self)
    local names = get()
    if #list(names) == 0 then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    W.nameLines(GameTooltip, names, true)
    GameTooltip:Show()
    self.nameTipShown = true
  end)
  frame:HookScript("OnLeave", function(self)
    if self.nameTipShown then GameTooltip:Hide() end
    self.nameTipShown = nil
  end)
end
