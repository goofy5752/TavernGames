-- The "fits the width" rule of the move histories (mockup 10, the owner's rules: no horizontal
-- scrolling, nothing hidden): every widget a ns.HistoryKit pool placed lies inside the content,
-- x >= 0 and its right edge <= `width`; a label's text is not wider than its box, and a wrapped
-- label has no word wider than its box (the client would cut it).
--   local Fit = require("fit"); Fit.check(pool, width, why) -> the number of widgets checked
local Fit = {}

local function words(text)
  local out = {}
  for word in tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gmatch("[^%s]+") do out[#out + 1] = word end
  return out
end

function Fit.check(pool, width, why)
  why = why or ""
  local n = 0
  for _, p in ipairs(pool.placed) do
    local r = p.r
    if r:IsShown() then
      n = n + 1
      ok(p.x >= 0, why .. ": left of the content at " .. p.x)
      ok(p.x + p.w <= width + 0.5, why .. ": past the right edge " .. (p.x + p.w) .. " > " .. width .. " " .. tostring(r.text or r.texture or ""))
      if r.objectType == "FontString" then
        local box = p.box or p.w
        local scratch = r.parent:CreateFontString(nil, "OVERLAY")
        scratch:SetFont(r:GetFont())
        if not p.box then
          scratch:SetText(r.text or "")
          ok(scratch:GetUnboundedStringWidth() <= box + 0.5, why .. ": a line wider than its place: " .. tostring(r.text))
        end
        for _, word in ipairs(words(r.text)) do
          scratch:SetText(word)
          ok(scratch:GetUnboundedStringWidth() <= box + 0.5, why .. ": a word cut: " .. word .. " in " .. box)
        end
        local _, size = r:GetFont()
        ok(size >= 9 - 0.01, why .. ": smaller than readable: " .. tostring(r.text) .. " at " .. size) -- 9 at the least (QA: 8 px on screen at the least scale)
      end
    end
  end
  return n
end

return Fit
