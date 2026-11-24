-- The headless screenshots' additions to the tests' fake client (tests/helpers/frames.lua):
--   * text is measured with the real fonts' glyph advances (metrics.lua), so the
--     addon's own shrink-to-fit and wrapping decide as the real client would;
--   * GetWidth / GetHeight / GetLeft / GetTop / ... report the laid-out rect,
--     as the client does for a region sized by its anchors;
--   * Shim.layout resolves WoW's SetPoint semantics for any region, and
--     Shim.snapshot walks the visible frame tree into a draw list for render.py.
-- Only the fake's metatables are patched, in this process: the tests never load this file.
local Frames = require("frames")
local METRICS = dofile("tools/shots/metrics.lua")

local Shim = {}

-- The fake's metatables, reached through one throwaway frame of each kind.
local G0 = {}
local make = Frames.factory(G0, function() end)
local probe = make("Frame")
local Frame = getmetatable(probe)
local Region = getmetatable(Frame).__index
local Texture = getmetatable(probe:CreateTexture())
local FontString = getmetatable(probe:CreateFontString())
local ScrollFrame = getmetatable(make("ScrollFrame"))
local EditBox = getmetatable(make("EditBox"))
Shim.Region, Shim.Frame, Shim.Texture, Shim.FontString = Region, Frame, Texture, FontString

---------------------------------------------------------------------------
-- Text metrics
---------------------------------------------------------------------------

local function fontKey(path)
  return (tostring(path):match("([^\\/]+)$"))
end

local function fontOf(path)
  return METRICS[fontKey(path) or ""] or METRICS["PTSans-Regular.ttf"]
end

-- UTF-8 code points of s -> array.
local function codepoints(s)
  local out = {}
  for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    local b1 = ch:byte(1)
    local cp
    if b1 < 128 then cp = b1
    elseif b1 < 224 then cp = (b1 - 192) * 64 + (ch:byte(2) - 128)
    elseif b1 < 240 then cp = ((b1 - 224) * 64 + (ch:byte(2) - 128)) * 64 + (ch:byte(3) - 128)
    else cp = (((b1 - 240) * 64 + (ch:byte(2) - 128)) * 64 + (ch:byte(3) - 128)) * 64 + (ch:byte(4) - 128) end
    out[#out + 1] = { ch = ch, cp = cp }
  end
  return out
end

-- The text as tokens: {t="text", s=...}, {t="color", c=...}, {t="reset"},
-- {t="tex", spec=...}, {t="nl"}. WoW's escapes: |cAARRGGBB, |r, |T...|t, |A...|a, |n, ||, |H..|h..|h.
function Shim.tokens(text)
  local out, buf, i, n = {}, {}, 1, #text
  local function flush()
    if #buf > 0 then out[#out + 1] = { t = "text", s = table.concat(buf) }; buf = {} end
  end
  while i <= n do
    local c = text:sub(i, i)
    if c == "|" then
      local d = text:sub(i + 1, i + 1)
      if d == "|" then buf[#buf + 1] = "|"; i = i + 2
      elseif d == "c" and text:sub(i + 2, i + 9):match("^%x%x%x%x%x%x%x%x$") then
        flush(); out[#out + 1] = { t = "color", c = text:sub(i + 2, i + 9) }; i = i + 10
      elseif d == "r" then flush(); out[#out + 1] = { t = "reset" }; i = i + 2
      elseif d == "n" then flush(); out[#out + 1] = { t = "nl" }; i = i + 2
      elseif d == "T" or d == "A" then
        local close = d == "T" and "|t" or "|a"
        local e = text:find(close, i + 2, true)
        if not e then buf[#buf + 1] = c; i = i + 1
        else
          flush(); out[#out + 1] = { t = d == "T" and "tex" or "atlas", spec = text:sub(i + 2, e - 1) }; i = e + 2
        end
      elseif d == "H" then
        local e = text:find("|h", i + 2, true)
        if e then i = e + 2 else buf[#buf + 1] = c; i = i + 1 end
      elseif d == "h" then i = i + 2
      else buf[#buf + 1] = c; i = i + 1 end
    elseif c == "\n" then flush(); out[#out + 1] = { t = "nl" }; i = i + 1
    else buf[#buf + 1] = c; i = i + 1 end
  end
  flush()
  return out
end

-- Width and height of an inline texture tag at font size `size`: |T path:h:w:...|t
-- (h 0: the text height; w 0: as h).
function Shim.inlineSize(spec, size)
  local parts = {}
  for p in (spec .. ":"):gmatch("([^:]*):") do parts[#parts + 1] = p end
  local h = tonumber(parts[2] or "") or 0
  local w = tonumber(parts[3] or "") or 0
  if h == 0 then h = size end
  if w == 0 then w = h end
  return w, h
end

Shim.noGlyph = {} -- code points some text asked of a font that lacks them
local function charWidth(m, cp, size)
  local a = m.adv[cp]
  if not a then -- a glyph the font lacks draws nothing
    if cp >= 32 then Shim.noGlyph[cp] = true end
    return 0
  end
  return a * size
end

local function textWidth(m, s, size)
  local w = 0
  for _, c in ipairs(codepoints(s)) do w = w + charWidth(m, c.cp, size) end
  return w
end
Shim.textWidth = function(path, s, size) return textWidth(fontOf(path), s, size) end

-- Splits tokens into "atoms" for wrapping: words, spaces and inline textures,
-- each carrying the codes in force. Returns lines of atoms (hard breaks only).
local function hardLines(tokens)
  local lines, cur = {}, {}
  for _, tk in ipairs(tokens) do
    if tk.t == "nl" then lines[#lines + 1] = cur; cur = {}
    else cur[#cur + 1] = tk end
  end
  lines[#lines + 1] = cur
  return lines
end

-- Atoms of one hard line: {kind = "word"|"space"|"tex"|"code", s = raw text to emit, w = width}.
local function atoms(line, m, size)
  local out = {}
  for _, tk in ipairs(line) do
    if tk.t == "text" then
      for space, word in tk.s:gmatch("(%s*)(%S*)") do
        if space ~= "" then out[#out + 1] = { kind = "space", s = space, w = textWidth(m, space, size) } end
        if word ~= "" then out[#out + 1] = { kind = "word", s = word:gsub("|", "||"), w = textWidth(m, word, size), plain = word } end
      end
    elseif tk.t == "color" then out[#out + 1] = { kind = "code", s = "|c" .. tk.c, w = 0 }
    elseif tk.t == "reset" then out[#out + 1] = { kind = "code", s = "|r", w = 0 }
    elseif tk.t == "tex" then
      local w = Shim.inlineSize(tk.spec, size)
      out[#out + 1] = { kind = "tex", s = "|T" .. tk.spec .. "|t", w = w }
    elseif tk.t == "atlas" then
      out[#out + 1] = { kind = "tex", s = "", w = size } -- a client atlas: room kept, nothing drawn
    end
  end
  return out
end

local function lineWidth(list)
  local w = 0
  for _, a in ipairs(list) do w = w + a.w end
  return w
end

-- One line's atoms -> text, without trailing spaces.
local function emit(list)
  local last = #list
  while last > 0 and list[last].kind == "space" do last = last - 1 end
  local parts = {}
  for k = 1, last do parts[#parts + 1] = list[k].s end
  return table.concat(parts)
end

-- The codes in force at the start of the next line (the last colour, if any).
local function carry(list, prev)
  local c = prev
  for _, a in ipairs(list) do
    if a.kind == "code" then c = (a.s == "|r") and nil or a.s end
  end
  return c
end

-- `text` cut to fit `width` with "..." (as the client truncates a line).
local function ellipsize(list, m, size, width)
  local dots = textWidth(m, "...", size)
  local out, w = {}, 0
  for _, a in ipairs(list) do
    if a.kind == "code" then out[#out + 1] = a
    elseif w + a.w + dots <= width then out[#out + 1] = a; w = w + a.w
    elseif a.kind == "word" or a.kind == "space" then
      local acc = {}
      for _, c in ipairs(codepoints(a.plain or a.s)) do
        local cw = charWidth(m, c.cp, size)
        if w + cw + dots > width then break end
        acc[#acc + 1] = c.ch; w = w + cw
      end
      if #acc > 0 then out[#out + 1] = { kind = "word", s = table.concat(acc):gsub("|", "||"), w = 0 } end
      break
    else break end
  end
  out[#out + 1] = { kind = "word", s = "...", w = dots }
  return out
end

-- Lays out `text` for font path/size: wrapped at `width` (nil: no limit) when
-- `wrap`, cut to `maxLines` -> lines (strings with codes), widest line width.
function Shim.wrap(text, path, size, width, wrap, maxLines)
  local m = fontOf(path)
  local out, widest, color = {}, 0, nil
  local function push(list)
    local s = emit(list)
    if color and not s:match("^|c") then s = color .. s end
    out[#out + 1] = s
    local w = lineWidth(list)
    -- trailing spaces take no room
    local k = #list
    while k > 0 and list[k].kind == "space" do w = w - list[k].w; k = k - 1 end
    if w > widest then widest = w end
    color = carry(list, color)
  end
  for _, line in ipairs(hardLines(Shim.tokens(text or ""))) do
    local list = atoms(line, m, size)
    if not width or width <= 0 then
      push(list)
    elseif not wrap then
      if lineWidth(list) > width + 0.5 then list = ellipsize(list, m, size, width) end
      push(list)
    else
      local cur, w = {}, 0
      for _, a in ipairs(list) do
        if a.kind == "space" and #cur == 0 and #out > 0 then
          -- a wrapped line does not start with the space it broke at
        elseif a.kind ~= "code" and w + a.w > width + 0.5 and a.kind ~= "space" and w > 0 then
          push(cur); cur, w = {}, 0
          cur[1] = a; w = a.w
        else
          cur[#cur + 1] = a; w = w + a.w
        end
      end
      if w > width + 0.5 then cur = ellipsize(cur, m, size, width) end
      push(cur)
    end
  end
  if maxLines and maxLines >= 1 and #out > maxLines then
    local keep = {}
    for k = 1, maxLines do keep[k] = out[k] end
    local last = atoms(hardLines(Shim.tokens(keep[maxLines]))[1], m, size)
    keep[maxLines] = emit(ellipsize(last, m, size, width or math.huge))
    out = keep
  end
  return out, widest
end

-- The client's line height for a font of `size`: the font height itself.
function Shim.lineHeight(size) return size end

local function fsFont(fs)
  local f = fs.font or { "PTSans-Regular.ttf", 12 }
  return f[1], f[2], f[3]
end

function FontString:GetUnboundedStringWidth()
  local path, size = fsFont(self)
  local _, w = Shim.wrap(self.text or "", path, size, nil, false)
  return w
end
function FontString:GetStringWidth()
  local w = self:GetUnboundedStringWidth()
  if self.fixedWidth and self.fixedWidth > 0 then return math.min(w, self.fixedWidth) end
  return w
end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------

local POINT = {
  TOPLEFT = { 0, 1 }, TOP = { 0.5, 1 }, TOPRIGHT = { 1, 1 }, LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 },
  RIGHT = { 1, 0.5 }, BOTTOMLEFT = { 0, 0 }, BOTTOM = { 0.5, 0 }, BOTTOMRIGHT = { 1, 0 },
}

Shim.G = nil -- the sandbox globals (for anchors given by name, and UIParent)

local function effScale(r)
  local s = 1
  while r do s = s * (r.scale or 1); r = r.parent end
  return s
end
Shim.effScale = effScale

-- The anchors of r, a later SetPoint of the same point replacing the earlier one.
local function anchors(r)
  local list, at = {}, {}
  for _, p in ipairs(r.points or {}) do
    local items = {}
    if p[1] == "ALL" then
      local rel = p[2] or r.parent
      items[1] = { point = "TOPLEFT", rel = rel, relPoint = "TOPLEFT", x = 0, y = 0 }
      items[2] = { point = "BOTTOMRIGHT", rel = rel, relPoint = "BOTTOMRIGHT", x = 0, y = 0 }
    else
      local point, rel, relPoint, x, y = tostring(p[1]):upper(), nil, nil, 0, 0
      if type(p[2]) == "number" then
        x, y = p[2], p[3] or 0
      else
        rel = p[2]
        if type(p[3]) == "string" then relPoint, x, y = p[3], p[4] or 0, p[5] or 0
        else x, y = p[3] or 0, p[4] or 0 end
      end
      if type(rel) == "string" then rel = Shim.G and rawget(Shim.G, rel) end
      items[1] = { point = point, rel = rel or r.parent, relPoint = (relPoint or point):upper(), x = x, y = y }
    end
    for _, it in ipairs(items) do
      if at[it.point] then list[at[it.point]] = it
      else list[#list + 1] = it; at[it.point] = #list end
    end
  end
  return list
end

-- The intrinsic text size of font string fs at width w (its own units): width, height.
local function fsSize(fs, boxW)
  local path, size = fsFont(fs)
  local wrap = fs.wordWrap ~= false
  local lines, widest = Shim.wrap(fs.text or "", path, size, boxW, wrap)
  if not fs.text or fs.text == "" then return 0, 0, lines end
  return widest, #lines * Shim.lineHeight(size), lines
end

local resolving = {}

-- r's rect on the screen {l, b, r, t} (UIParent units), or nil when r has none.
function Shim.rect(r, memo)
  memo = memo or {}
  if memo[r] ~= nil then return memo[r] or nil end
  if resolving[r] then return nil end
  local G = Shim.G
  if G and r == rawget(G, "UIParent") then
    local w, h = r.width, r.height
    memo[r] = { 0, 0, w, h }
    return memo[r]
  end
  resolving[r] = true
  local out
  local s = effScale(r)
  local parent = r.parent
  if parent and parent.objectType == "ScrollFrame" and parent.child == r then
    local pr = Shim.rect(parent, memo)
    if pr then
      local w, h = (r.width or 0) * s, (r.height or 0) * s
      local l, t = pr[1] - (parent.hscroll or 0) * s, pr[4] + (parent.vscroll or 0) * s
      out = { l, t - h, l + w, t }
    end
  else
    local list = anchors(r)
    if #list > 0 then
      local hl, hr, hc, vt, vb, vc
      local ok = true
      for _, a in ipairs(list) do
        local rr = a.rel and Shim.rect(a.rel, memo)
        local P, RP = POINT[a.point], POINT[a.relPoint]
        if not rr or not P or not RP then ok = false; break end
        local px = rr[1] + (rr[3] - rr[1]) * RP[1] + a.x * s
        local py = rr[2] + (rr[4] - rr[2]) * RP[2] + a.y * s
        if P[1] == 0 then hl = px elseif P[1] == 1 then hr = px else hc = px end
        if P[2] == 1 then vt = py elseif P[2] == 0 then vb = py else vc = py end
      end
      if ok then
        local isText = r.objectType == "FontString"
        local w = (r.width or 0) * s
        if isText and not (r.fixedWidth and r.fixedWidth > 0) then w = nil end
        local l, rt
        if hl and hr then l, rt = hl, hr
        elseif hl and hc then l, rt = hl, 2 * hc - hl
        elseif hr and hc then l, rt = 2 * hc - hr, hr
        else
          if not w then w = (fsSize(r, nil)) * s end
          if hl then l, rt = hl, hl + w
          elseif hr then l, rt = hr - w, hr
          else l, rt = hc - w / 2, hc + w / 2 end
        end
        local h = (r.height or 0) * s
        local b, t
        if vt and vb then b, t = vb, vt
        elseif vt and vc then b, t = 2 * vc - vt, vt
        elseif vb and vc then b, t = vb, 2 * vc - vb
        else
          if isText and (r.height or 0) == 0 then
            local boxW = (rt - l) / s
            local _, th = fsSize(r, boxW > 0 and boxW or nil)
            h = th * s
          end
          if vt then b, t = vt - h, vt
          elseif vb then b, t = vb, vb + h
          else b, t = vc - h / 2, vc + h / 2 end
        end
        out = { l, b, rt, t }
      end
    end
  end
  resolving[r] = nil
  memo[r] = out or false
  return out
end

-- The client reports the laid-out size and position of a region sized by its anchors.
local rawW, rawH = Region.GetWidth, Region.GetHeight
local function laidW(self)
  local rc = Shim.rect(self)
  if rc then return (rc[3] - rc[1]) / effScale(self) end
  if self.objectType == "FontString" and not (self.fixedWidth and self.fixedWidth > 0) then
    return (fsSize(self, nil))
  end
  return rawW(self)
end
local function laidH(self)
  local rc = Shim.rect(self)
  if rc then return (rc[4] - rc[2]) / effScale(self) end
  if self.objectType == "FontString" and (self.height or 0) == 0 then
    local _, h = fsSize(self, self.fixedWidth)
    return h
  end
  return rawH(self)
end
Region.GetWidth, Region.GetHeight = laidW, laidH
function Region:GetSize() return laidW(self), laidH(self) end
local function edge(i)
  return function(self)
    if self.left ~= nil and (i == 1) then return self.left end
    if self.top ~= nil and (i == 4) then return self.top end
    local rc = Shim.rect(self)
    if not rc then return nil end
    return rc[i] / effScale(self)
  end
end
Region.GetLeft, Region.GetBottom, Region.GetRight, Region.GetTop = edge(1), edge(2), edge(3), edge(4)
function Region:GetCenter()
  local rc = Shim.rect(self)
  if not rc then return nil end
  local s = effScale(self)
  return (rc[1] + rc[3]) / 2 / s, (rc[2] + rc[4]) / 2 / s
end
function Region:GetRect()
  local rc = Shim.rect(self)
  if not rc then return nil end
  local s = effScale(self)
  return rc[1] / s, rc[2] / s, (rc[3] - rc[1]) / s, (rc[4] - rc[2]) / s
end

-- The wrapped height of a font string at its width.
function FontString:GetStringHeight()
  local w = self.fixedWidth
  if not w or w <= 0 then
    local rc = Shim.rect(self)
    if rc and #anchors(self) > 1 then w = (rc[3] - rc[1]) / effScale(self) end
  end
  local _, h = fsSize(self, w and w > 0 and w or nil)
  return h
end

---------------------------------------------------------------------------
-- The draw list
---------------------------------------------------------------------------

local STRATA = { WORLD = 0, BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6,
                 FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
local LAYER = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4, HIGHLIGHT = 5 }

local function strataOf(f)
  local r = f
  while r do
    if r.strata then return r.strata end
    r = r.parent
  end
  return "MEDIUM"
end

-- A frame's level for drawing: its own, but never below its parent's (the client keeps a child above).
local function levelOf(f, cache)
  if cache[f] then return cache[f] end
  local lv = f.level or 1
  local p = f.parent
  if p and p.regions and strataOf(p) == strataOf(f) then
    local pl = levelOf(p, cache)
    if lv <= pl then lv = pl + 1 end
  end
  cache[f] = lv
  return lv
end

local function alphaOf(r)
  local a = 1
  while r do a = a * (r.alpha or 1); r = r.parent end
  return a
end

-- The intersection of the scroll frames' rects above r, or nil.
local function clipOf(r, memo)
  local clip
  local p = r.parent
  while p do
    if p.objectType == "ScrollFrame" or p.clipsChildren then
      local rc = Shim.rect(p, memo)
      if rc then
        if clip then clip = { math.max(clip[1], rc[1]), math.max(clip[2], rc[2]), math.min(clip[3], rc[3]), math.min(clip[4], rc[4]) }
        else clip = { rc[1], rc[2], rc[3], rc[4] } end
      end
    end
    p = p.parent
  end
  return clip
end

local MEDIA_PREFIX = "interface\\addons\\taverngames\\"
-- A texture path of the addon -> repo file (media/....tga), or nil (client art).
function Shim.file(path)
  if type(path) ~= "string" then return nil end
  local low = path:lower():gsub("/", "\\")
  if low:sub(1, #MEDIA_PREFIX) ~= MEDIA_PREFIX then return nil end
  local rest = path:sub(#MEDIA_PREFIX + 1):gsub("\\", "/")
  if not rest:match("%.%w+$") then rest = rest .. ".tga" end
  return rest
end

local function frameIndex(frames)
  local idx = {}
  for i, f in ipairs(frames) do idx[f] = i end
  return idx
end

-- Every visible texture and font string of the sandbox `w`, in draw order:
-- {items = {...}, missing = {...}}. `skip(frame)` -> true leaves a frame (and its children) out.
function Shim.snapshot(w, skip)
  local memo, levels, idx = {}, {}, frameIndex(w.frames)
  local entries, missing, seenMissing = {}, {}, {}
  local function note(what)
    if not seenMissing[what] then seenMissing[what] = true; missing[#missing + 1] = what end
  end
  local function skipped(f)
    local r = f
    while r do
      if skip and skip(r) then return true end
      r = r.parent
    end
    return false
  end
  for _, f in ipairs(w.frames) do
    if f:IsVisible() and not skipped(f) and alphaOf(f) > 0.001 then
      local strata, level = STRATA[strataOf(f)] or 3, levelOf(f, levels)
      local fa = alphaOf(f)
      local clip = clipOf(f, memo)
      if f.objectType == "ScrollFrame" then
        -- its own regions are not clipped by itself
      end
      local regions = {}
      for ri, r in ipairs(f.regions) do regions[#regions + 1] = { r = r, i = ri } end
      if f.objectType == "EditBox" and f.font and (f.text or "") ~= "" then
        regions[#regions + 1] = { r = f, i = #f.regions + 1, edit = true }
      end
      for _, e in ipairs(regions) do
        local r = e.r
        local layer = e.edit and "OVERLAY" or (r.layer or "ARTWORK")
        if (e.edit or (r.shown and r.objectType ~= "MaskTexture")) and layer ~= "HIGHLIGHT" then
          local rc = Shim.rect(r, memo)
          local a = fa * (e.edit and 1 or (r.alpha or 1))
          if rc and rc[3] - rc[1] > 0.01 and rc[4] - rc[2] > 0.01 and a > 0.001 then
            local item
            local s = effScale(r)
            if r.objectType == "Texture" then
              local file = r.texture and Shim.file(r.texture)
              if r.color then
                item = { k = "tex", color = r.color }
              elseif file then
                item = { k = "tex", path = file, wrap = r.wrap, blend = r.blend }
              elseif r.texture or r.atlas then
                note(tostring(r.texture or ("atlas:" .. tostring(r.atlas))))
              end
              if item then
                item.tc = r.texCoord
                item.vc = r.vertex
                item.blend = r.blend
                if r.masks then
                  item.masks = {}
                  for _, m in ipairs(r.masks) do
                    local mr = Shim.rect(m, memo)
                    local mf = Shim.file(m.texture)
                    if mr and mf then item.masks[#item.masks + 1] = { r = mr, path = mf, tc = m.texCoord } end
                  end
                end
              end
            elseif (r.objectType == "FontString" or e.edit) and r.text and r.text ~= "" and r.font then
              local path, size, flags = r.font[1], r.font[2], r.font[3]
              local boxW = (rc[3] - rc[1]) / s
              local boxH = (rc[4] - rc[2]) / s
              local maxLines
              if e.edit then
                local ins = r.insets or { 0, 0, 0, 0 }
                rc = { rc[1] + (ins[1] or 0) * s, rc[2] + (ins[4] or 0) * s, rc[3] - (ins[2] or 0) * s, rc[4] - (ins[3] or 0) * s }
                boxW = (rc[3] - rc[1]) / s
              end
              local lh = Shim.lineHeight(size)
              if boxH > 0 then maxLines = math.max(1, math.floor(boxH / lh + 0.2)) end
              local wrap = (not e.edit) and r.wordWrap ~= false
              local lines = Shim.wrap(r.text, path, size, boxW, wrap, maxLines)
              item = {
                k = "text", font = fontKey(path), size = size * s, flags = flags or "", lh = lh * s, lines = lines,
                color = r.textColor or { 1, 1, 1, 1 }, jh = r.justifyH or (e.edit and "LEFT" or "CENTER"),
                jv = r.justifyV or "MIDDLE",
                shadow = r.shadow and (r.shadow[1] ~= 0 or r.shadow[2] ~= 0) and {
                  r.shadow[1] * s, r.shadow[2] * s, unpack(r.shadowColor or { 0, 0, 0, 1 }) } or nil,
              }
            end
            if item then
              item.r, item.a, item.clip = rc, a, clipOf(r, memo)
              if e.edit then item.clip = clip end
              entries[#entries + 1] = {
                item = item,
                key = { strata, level, idx[f] or 0, LAYER[layer] or 3, (not e.edit and r.sublayer) or 0, e.i },
              }
            end
          end
        end
      end
    end
  end
  table.sort(entries, function(x, y)
    for k = 1, 6 do
      if x.key[k] ~= y.key[k] then return x.key[k] < y.key[k] end
    end
    return false
  end)
  local items = {}
  for i, e in ipairs(entries) do items[i] = e.item end
  return { items = items, missing = missing }
end

-- The union rect of the given regions' rects, plus margin m.
function Shim.bounds(list, m)
  local u
  for _, r in ipairs(list) do
    local rc = Shim.rect(r)
    if rc then
      if u then u = { math.min(u[1], rc[1]), math.min(u[2], rc[2]), math.max(u[3], rc[3]), math.max(u[4], rc[4]) }
      else u = { rc[1], rc[2], rc[3], rc[4] } end
    end
  end
  m = m or 0
  if u then u = { u[1] - m, u[2] - m, u[3] + m, u[4] + m } end
  return u
end

---------------------------------------------------------------------------
-- JSON
---------------------------------------------------------------------------

local function enc(v, out)
  local t = type(v)
  if t == "nil" then out[#out + 1] = "null"
  elseif t == "boolean" then out[#out + 1] = v and "true" or "false"
  elseif t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then out[#out + 1] = "null"
    elseif v == math.floor(v) and math.abs(v) < 1e15 then out[#out + 1] = string.format("%d", v)
    else out[#out + 1] = string.format("%.4f", v) end
  elseif t == "string" then
    out[#out + 1] = '"' .. v:gsub('[%c"\\]', function(c)
      if c == '"' then return '\\"' elseif c == "\\" then return "\\\\" elseif c == "\n" then return "\\n" end
      return string.format("\\u%04x", c:byte())
    end) .. '"'
  elseif t == "table" then
    local n = #v
    local isArray = n > 0 or next(v) == nil
    if isArray then
      for k in pairs(v) do if type(k) ~= "number" then isArray = false break end end
    end
    if isArray then
      out[#out + 1] = "["
      for i = 1, n do if i > 1 then out[#out + 1] = "," end enc(v[i], out) end
      out[#out + 1] = "]"
    else
      out[#out + 1] = "{"
      local keys = {}
      for k in pairs(v) do keys[#keys + 1] = tostring(k) end
      table.sort(keys)
      for i, k in ipairs(keys) do
        if i > 1 then out[#out + 1] = "," end
        enc(k, out); out[#out + 1] = ":"; enc(v[k], out)
      end
      out[#out + 1] = "}"
    end
  else
    out[#out + 1] = "null"
  end
end

function Shim.json(v)
  local out = {}
  enc(v, out)
  return table.concat(out)
end

return Shim
