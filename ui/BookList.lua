local _, ns = ...

-- A virtual list for the pages on paper: a W.Scroll whose rows get widgets only for the
-- lines on screen (at most `rows` + 1), refilled when the mouse wheel moves it. The row
-- is { frame = a Frame of width x rowH with the mouse on, ... } and `make(row)` adds its
-- widgets once; `fill(row, line, i)` writes line i into it (the list places the frame).
-- opts = { width, rowH, rows, make = fn(row), fill = fn(row, line, i) }.
local W = ns.W

local BookList = {}
ns.BookList = BookList
BookList.__index = BookList

function BookList.new(parent, opts)
  local scroll = W.Scroll(parent)
  scroll:SetSize(opts.width, opts.rows * opts.rowH)
  scroll.content:SetWidth(opts.width)
  local list = setmetatable({ scroll = scroll, rows = {}, lines = {}, opts = opts }, BookList)
  scroll:HookScript("OnMouseWheel", function() list:fill() end)
  return list
end

-- The widgets of row j, made when first needed.
function BookList:row(j)
  local r, o = self.rows[j], self.opts
  if r then return r end
  local f = CreateFrame("Frame", nil, self.scroll.content)
  f:SetSize(o.width, o.rowH)
  f:EnableMouse(true)
  r = { frame = f }
  o.make(r)
  self.rows[j] = r
  return r
end

-- The row widgets of the lines on screen; the others are hidden.
function BookList:fill()
  local o, used = self.opts, 0
  local first = math.floor(self.scroll:GetVerticalScroll() / o.rowH) + 1
  for i = first, math.min(#self.lines, first + o.rows) do
    used = used + 1
    local r = self:row(used)
    r.index = i
    r.frame:ClearAllPoints()
    r.frame:SetPoint("TOPLEFT", self.scroll.content, "TOPLEFT", 0, -(i - 1) * o.rowH)
    o.fill(r, self.lines[i], i)
    r.frame:Show()
  end
  for j = used + 1, #self.rows do self.rows[j].frame:Hide() end
end

-- Shows these lines (the scroll stays where it is, within the new height).
function BookList:set(lines)
  self.lines = lines
  self.scroll:setContentHeight(#lines * self.opts.rowH)
  self:fill()
end
