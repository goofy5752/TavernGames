-- The layout checker: every lint scene (tools/shots/lint_scenes.lua), in both languages and both
-- factions, on four screens and six window scales, checked for text that does not fit, overlaps,
-- regions outside their window, windows off the screen, text too small to read and sideways
-- scrolling. What is meant to be so is on the allow-list (tools/shots/lint_allow.lua), each entry
-- with its reason. Run from the repo root:
--     luajit tools/shots/lint.lua [--quick] [--shots] [scene ...]
-- --quick: English and the Alliance only; --shots: also writes tools/shots/build/lint_<...>.json
-- draw lists of the hardest cases for render.py (SHOTS below). Findings: tools/shots/build/lint.txt (and stdout).
package.path = "tests/helpers/?.lua;tools/shots/?.lua;" .. package.path
SHOTS_LIB = true
local S = dofile("tools/shots/scenes.lua")
local Shim = require("shim")
local SCENES = dofile("tools/shots/lint_scenes.lua")(S)
local ALLOW = dofile("tools/shots/lint_allow.lua")

local SCREENS = { { 1024, 768 }, { 1365, 768 }, { 1820, 768 }, { 1920, 1080 } }
local SCALES = { 0.6, 0.8, 1.0, 1.3, 1.6, 2.0 }
local READ_PX = 8 -- the smallest text size, in screen pixels of a 1080p screen, that still reads
local PX_1080 = 1080
local OUT = "tools/shots/build/lint.txt"

local args, wantScenes, quick, shots = { ... }, {}, false, false
for _, a in ipairs(args) do
  if a == "--quick" then quick = true elseif a == "--shots" then shots = true else wantScenes[#wantScenes + 1] = a end
end
local COMBOS = quick and { { lang = "en", faction = "Alliance" } } or {
  { lang = "en", faction = "Alliance" }, { lang = "bg", faction = "Horde" },
  { lang = "en", faction = "Horde", only = { hall = true, belot = true } },
  { lang = "bg", faction = "Alliance", only = { hall = true, belot = true } },
}

---------------------------------------------------------------------------
-- The frame tree
---------------------------------------------------------------------------

local LAYER_HIGHLIGHT = "HIGHLIGHT"

local function alphaOf(r)
  local a = 1
  while r do a = a * (r.alpha or 1); r = r.parent end
  return a
end

-- The scroll frames' clip rect above region r (nil: none).
local function clipOf(r)
  local clip, p = nil, r.parent
  while p do
    if p.objectType == "ScrollFrame" then
      local rc = Shim.rect(p)
      if rc then
        clip = clip and { math.max(clip[1], rc[1]), math.max(clip[2], rc[2]), math.min(clip[3], rc[3]), math.min(clip[4], rc[4]) }
          or { rc[1], rc[2], rc[3], rc[4] }
      end
    end
    p = p.parent
  end
  return clip
end

local function cut(a, b)
  if not b then return a end
  local out = { math.max(a[1], b[1]), math.max(a[2], b[2]), math.min(a[3], b[3]), math.min(a[4], b[4]) }
  if out[3] - out[1] <= 0.01 or out[4] - out[2] <= 0.01 then return nil end
  return out
end

-- The windows on the screen: every visible frame on UIParent, and the frames the addon
-- draws as windows of their own though they hang off another (the table's „История“,
-- the new-table dialog) -> list of {frame, name}.
local function windows(w)
  local ns, UI = w.ns, w.G.UIParent
  local names = {}
  for key, mod in pairs(ns) do
    if type(mod) == "table" and type(rawget(mod, "frame")) == "table" and mod.frame.objectType then names[mod.frame] = key end
  end
  local TF = ns.TableFrame
  if TF.view and TF.view.history then names[TF.view.history] = "History" end
  if ns.StakePanels.askFrame then names[ns.StakePanels.askFrame] = "StakeAsk" end
  if ns.Accounts.sure then names[ns.Accounts.sure] = "SettleSure" end
  if ns.Intro.lang and ns.Intro.lang.frame then names[ns.Intro.lang.frame] = "IntroLang" end
  local out, own = {}, {}
  for _, f in ipairs(w.frames) do
    if f:IsVisible() and alphaOf(f) > 0.001 and (f.parent == UI or (names[f] and f.parent)) and Shim.rect(f) then
      out[#out + 1] = { frame = f, name = names[f] or ("frame" .. #out) }
      own[f] = out[#out]
    end
  end
  return out, own
end

local function windowOf(r, own)
  local p = (r.objectType == "Texture" or r.objectType == "FontString") and r.parent or r
  while p do
    if own[p] then return own[p] end
    p = p.parent
  end
end

-- Every drawn region: {r, frame, rect (clipped), full (unclipped), clip, kind, win}.
local function drawn(w, own)
  local out = {}
  for _, f in ipairs(w.frames) do
    if f:IsVisible() and alphaOf(f) > 0.001 then
      for _, r in ipairs(f.regions) do
        local layer = r.layer or "ARTWORK"
        if r.shown and r.objectType ~= "MaskTexture" and layer ~= LAYER_HIGHLIGHT and (r.alpha or 1) > 0.001 then
          local rc = Shim.rect(r)
          if rc and rc[3] - rc[1] > 0.01 and rc[4] - rc[2] > 0.01 then
            local kind
            if r.objectType == "Texture" and (r.color or r.texture) then kind = "tex"
            elseif r.objectType == "FontString" and r.text and r.text ~= "" and r.font then kind = "text" end
            if kind then
              local clip = clipOf(r)
              out[#out + 1] = { r = r, frame = f, full = rc, clip = clip, kind = kind, win = windowOf(r, own) }
            end
          end
        end
      end
    end
  end
  return out
end

local function plain(text)
  return (tostring(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "©"):gsub("\n", "/"))
end

-- A font string's text as laid out in its box: lines, cut (ellipsized or lines dropped), the ink rect.
local function layout(d)
  local r, rc = d.r, d.full
  local s = Shim.effScale(r)
  local path, size = r.font[1], r.font[2]
  local boxW, boxH = (rc[3] - rc[1]) / s, (rc[4] - rc[2]) / s
  local maxLines = boxH > 0 and math.max(1, math.floor(boxH / size + 0.2)) or nil
  Shim.cut = false
  local lines, widest = Shim.wrap(r.text, path, size, boxW, r.wordWrap ~= false, maxLines)
  local wasCut = Shim.cut
  Shim.cut = false
  local iw, ih = widest * s, #lines * size * s
  local jh, jv = r.justifyH or "CENTER", r.justifyV or "MIDDLE"
  local l = jh == "LEFT" and rc[1] or jh == "RIGHT" and rc[3] - iw or (rc[1] + rc[3]) / 2 - iw / 2
  local t = jv == "TOP" and rc[4] or jv == "BOTTOM" and rc[2] + ih or (rc[2] + rc[4]) / 2 + ih / 2
  return lines, wasCut, { l, t - ih, l + iw, t }, s, size
end

---------------------------------------------------------------------------
-- Findings
---------------------------------------------------------------------------

local findings, order = {}, {}
local function allowed(f)
  for _, a in ipairs(ALLOW) do
    local hit = true
    for k, pat in pairs(a) do
      if k ~= "why" and not tostring(f[k] or ""):find(pat) then hit = false; break end
    end
    if hit then return a.why end
  end
end

-- One finding; the same one seen again (another size, language) only adds where.
local function add(f, where)
  local key = table.concat({ f.check, f.scene, f.win or "", f.site or "", f.what or "" }, "|")
  local e = findings[key]
  if not e then
    e = f
    e.where, e.whereSet = {}, {}
    e.why = allowed(f)
    findings[key] = e
    order[#order + 1] = key
  end
  if not e.whereSet[where] then e.whereSet[where] = true; e.where[#e.where + 1] = where end
end

local function rectText(rc) return string.format("(%.0f,%.0f)-(%.0f,%.0f)", rc[1], rc[2], rc[3], rc[4]) end

-- The checks that do not depend on the scale (the layout does not reflow): fit, overlap, inside, sideways.
local function checkLayout(scene, w, where)
  local wins, own = windows(w)
  local list = drawn(w, own)
  local inks = {}
  for _, d in ipairs(list) do
    local site = d.r.site or "?"
    local winName = d.win and d.win.name or "none"
    local rect = d.full
    if d.kind == "text" then
      local lines, wasCut, inkRect = layout(d)
      if wasCut then
        add({ check = "fit", scene = scene, win = winName, site = site, what = plain(d.r.text):sub(1, 60),
              detail = "cut to: " .. plain(table.concat(lines, " / ")):sub(1, 90) }, where)
      end
      rect = inkRect
    end
    local shown = cut(rect, d.clip)
    if d.clip and shown and (rect[1] < d.clip[1] - 1 or rect[3] > d.clip[3] + 1) then
      add({ check = "sideways", scene = scene, win = winName, site = site,
            what = d.kind == "text" and plain(d.r.text):sub(1, 60) or tostring(d.r.texture or "color"),
            detail = "clipped by its scroll frame " .. rectText(rect) .. " in " .. rectText(d.clip) }, where)
    end
    if shown and d.win then
      local wr = Shim.rect(d.win.frame)
      if shown[1] < wr[1] - 1 or shown[3] > wr[3] + 1 or shown[2] < wr[2] - 1 or shown[4] > wr[4] + 1 then
        add({ check = "inside", scene = scene, win = winName, site = site,
              what = d.kind == "text" and plain(d.r.text):sub(1, 60) or ("tex " .. tostring(d.r.texture or "color"):match("[^\\/]*$")),
              detail = rectText(shown) .. " outside " .. rectText(wr) }, where)
      end
    end
    if d.kind == "text" and shown then
      inks[#inks + 1] = { d = d, rc = shown, win = winName, site = site }
    end
  end
  local snap, regs = Shim.snapshot(w)
  local orderOf = {}
  for i, r in ipairs(regs) do orderOf[r] = i end
  -- An opaque texture drawn after item `from` and before `to` (draw order) that covers rect rc wholly.
  local function covered(from, to, rc)
    for i = from + 1, to - 1 do
      local it = snap.items[i]
      if it.k == "tex" and it.blend ~= "ADD" and (it.a or 1) * (it.color and (it.color[4] or 1) or 1) >= 0.9 then
        local t = cut(it.r, it.clip)
        if t and t[1] <= rc[1] and t[2] <= rc[2] and t[3] >= rc[3] and t[4] >= rc[4] then return true end
      end
    end
    return false
  end
  -- Text over text in one window (unless a solid texture between them hides the one below).
  for i = 1, #inks do
    local a = inks[i]
    for j = i + 1, #inks do
      local b = inks[j]
      if a.win == b.win then
        local s = Shim.effScale(a.d.r)
        local ox = math.min(a.rc[3], b.rc[3]) - math.max(a.rc[1], b.rc[1])
        local oy = math.min(a.rc[4], b.rc[4]) - math.max(a.rc[2], b.rc[2])
        local oa, ob = orderOf[a.d.r] or 0, orderOf[b.d.r] or 0
        local both = { math.max(a.rc[1], b.rc[1]), math.max(a.rc[2], b.rc[2]), math.min(a.rc[3], b.rc[3]), math.min(a.rc[4], b.rc[4]) }
        if ox > 1 * s and oy > 2 * s and not covered(math.min(oa, ob), math.max(oa, ob), both) then
          local x, y = a, b
          if (y.site or "") < (x.site or "") then x, y = y, x end
          add({ check = "overlap", scene = scene, win = a.win, site = x.site .. " & " .. y.site,
                what = plain(x.d.r.text):sub(1, 40) .. " & " .. plain(y.d.r.text):sub(1, 40),
                detail = string.format("%.0f x %.0f", ox / s, oy / s) }, where)
        end
      end
    end
  end
  -- Text under a texture drawn after it (in the client's draw order) in its window: hidden.
  for _, ink in ipairs(inks) do
    local from = orderOf[ink.d.r]
    if from then
      local s = Shim.effScale(ink.d.r)
      for i = from + 1, #regs do
        local it, r = snap.items[i], regs[i]
        if it.k == "tex" and it.blend ~= "ADD" then
          local a = (it.a or 1) * (it.color and (it.color[4] or 1) or 1) * (it.vc and (it.vc[4] or 1) or 1)
          local rc = a >= 0.5 and cut(it.r, it.clip)
          if rc then
            local ox = math.min(ink.rc[3], rc[3]) - math.max(ink.rc[1], rc[1])
            local oy = math.min(ink.rc[4], rc[4]) - math.max(ink.rc[2], rc[2])
            local win = windowOf(r, own)
            if ox > 3 * s and oy > 3 * s and (win and win.name or "none") == ink.win then
              local what = tostring(r.texture or "color"):match("[^/\\]*$")
              add({ check = "overlap", scene = scene, win = ink.win, site = ink.site .. " under " .. (r.site or "?"),
                    what = plain(ink.d.r.text):sub(1, 40) .. " under tex " .. what,
                    detail = string.format("%.0f x %.0f covered", ox / s, oy / s) }, where)
            end
          end
        end
      end
    end
  end
  -- A scroll child wider than its scroll frame.
  for _, f in ipairs(w.frames) do
    if f.objectType == "ScrollFrame" and f:IsVisible() and f.child then
      local sw, cw = f:GetWidth() or 0, f.child.width or 0
      if cw > sw + 0.5 then
        add({ check = "sideways", scene = scene, win = (windowOf(f, own) or {}).name, site = "scroll",
              what = "content " .. cw .. " in " .. sw }, where)
      end
    end
  end
  return wins
end

-- The checks of one scale on one screen: windows on the screen, text big enough to read.
local function checkScreen(scene, w, where, sh, sw)
  local wins, own = windows(w)
  for _, win in ipairs(wins) do
    local rc = Shim.rect(win.frame)
    if rc[1] < -0.5 or rc[2] < -0.5 or rc[3] > sw + 0.5 or rc[4] > sh + 0.5 then
      add({ check = "screen", scene = scene, win = win.name, site = win.name, what = win.name,
            detail = rectText(rc) .. " on " .. sw .. "x" .. sh }, where)
    end
  end
  -- The toasts the addon puts up by itself never lie over each other.
  local TOASTS = { InviteToast = true, SettleToast = true }
  for i = 1, #wins do
    for j = i + 1, #wins do
      local a, b = wins[i], wins[j]
      if TOASTS[a.name] and TOASTS[b.name] then
        local ra, rb = Shim.rect(a.frame), Shim.rect(b.frame)
        if math.min(ra[3], rb[3]) - math.max(ra[1], rb[1]) > 1 and math.min(ra[4], rb[4]) - math.max(ra[2], rb[2]) > 1 then
          add({ check = "overlap", scene = scene, win = a.name, site = a.name .. " & " .. b.name, what = "toasts over each other",
                detail = rectText(ra) .. " and " .. rectText(rb) }, where)
        end
      end
    end
  end
  local small, minPx, example = 0, math.huge, nil
  for _, d in ipairs(drawn(w, own)) do
    if d.kind == "text" and cut(d.full, d.clip) then
      local px = d.r.font[2] * Shim.effScale(d.r) * PX_1080 / sh
      if px < READ_PX - 1e-6 then
        small = small + 1
        if px < minPx then minPx, example = px, d end
      end
    end
  end
  if small > 0 then
    add({ check = "readable", scene = scene, win = example.win and example.win.name, site = "",
          what = string.format("%d texts under %d px", small, READ_PX),
          detail = string.format("smallest %.1f px: %s (%s, font %.1f)", minPx, plain(example.r.text):sub(1, 40),
            example.r.site or "?", example.r.font[2]) }, where)
  end
end

---------------------------------------------------------------------------
-- Screens and scales
---------------------------------------------------------------------------

local function setScreen(w, sw, sh)
  w.G.UIParent:SetSize(sw, sh)
  rawset(w.G, "GetPhysicalScreenSize", function() return math.floor(PX_1080 * sw / sh + 0.5), PX_1080 end)
  if w.ns.Resize.screenChanged then w.ns.Resize.screenChanged() end
end

-- Every window at scale s, as a drag of its grip asks (Resize.set caps it); the next redraw follows.
local function setScale(w, s)
  local R, ns = w.ns.Resize, w.ns
  if ns.MainWindow.frame then R.set("main", s) end
  if ns.TableFrame.frame then R.set("table", s) end
  if ns.TableFrame.frame and ns.TableFrame.frame:IsShown() and ns.client.session then ns.TableFrame.render() end
end

local function snapshotJson(name, w)
  local snap = Shim.snapshot(w)
  snap.name = name
  local UI = w.G.UIParent
  snap.crop = { 0, 0, UI.width, UI.height }
  snap.screen = { UI.width, UI.height }
  snap.scale = PX_1080 / UI.height -- px of a 1080p screen per UI unit
  snap.faction = w.faction
  local f = assert(io.open(S.OUT .. name .. ".json", "wb"))
  f:write(Shim.json(snap))
  f:close()
  Shim.noGlyph = {}
end

-- The shots of the hardest cases: the smallest scale on the smallest screen ("min") and on the largest
-- UIParent ("tiny"), the largest scale ("max"), scale 1 on the smallest screen ("small") and on a 16:9 one ("one").
local SHOTS = {
  { screen = 1, scale = 0.6, tag = "min" }, { screen = 4, scale = 0.6, tag = "tiny" }, { screen = 4, scale = 2.0, tag = "max" },
  { screen = 1, scale = 1.0, tag = "small" }, { screen = 2, scale = 1.0, tag = "one" },
}

local total = 0
for _, sc in ipairs(SCENES) do
  local wanted = #wantScenes == 0
  for _, n in ipairs(wantScenes) do if n == sc.name then wanted = true end end
  if wanted then
    for _, P in ipairs(COMBOS) do
      if not P.only or P.only[sc.name] then
        local okRun, err = xpcall(function()
          local w = sc.fn(P)
          local combo = P.lang .. "/" .. P.faction:sub(1, 1)
          for si, scr in ipairs(SCREENS) do
            setScreen(w, scr[1], scr[2])
            for _, s in ipairs(SCALES) do
              setScale(w, s)
              local where = string.format("%s %dx%d @%.1f", combo, scr[1], scr[2], s)
              if s == 1.0 then checkLayout(sc.name, w, string.format("%s %dx%d", combo, scr[1], scr[2])) end
              checkScreen(sc.name, w, where, scr[2], scr[1])
              if shots then
                for _, sh in ipairs(SHOTS) do
                  if sh.screen == si and math.abs(sh.scale - s) < 1e-9 then
                    snapshotJson(string.format("lint_%s_%s_%s_%s", sc.name, P.lang, P.faction:sub(1, 1):lower(), sh.tag), w)
                  end
                end
              end
            end
          end
          total = total + 1
        end, debug.traceback)
        if not okRun then
          io.stderr:write("lint scene " .. sc.name .. " (" .. P.lang .. ") failed: " .. tostring(err) .. "\n")
          os.exit(1)
        end
      end
    end
  end
end

---------------------------------------------------------------------------
-- The report
---------------------------------------------------------------------------

local lines, counts, open, allowedN = {}, {}, 0, 0
local function out(s) lines[#lines + 1] = s end
for _, key in ipairs(order) do
  local f = findings[key]
  counts[f.check] = counts[f.check] or { open = 0, allowed = 0 }
  if f.why then counts[f.check].allowed = counts[f.check].allowed + 1; allowedN = allowedN + 1
  else counts[f.check].open = counts[f.check].open + 1; open = open + 1 end
end
for pass = 1, 2 do
  out(pass == 1 and "== OPEN ==" or "== ALLOWED ==")
  for _, key in ipairs(order) do
    local f = findings[key]
    if (pass == 1) == (f.why == nil) then
      local where = #f.where > 4 and (table.concat({ f.where[1], f.where[2], f.where[3] }, "; ") .. " (+" .. (#f.where - 3) .. ")")
        or table.concat(f.where, "; ")
      out(string.format("[%s] %s/%s %s: %s", f.check, f.scene, f.win or "-", f.site or "", f.what or ""))
      if f.detail then out("    " .. f.detail) end
      out("    at " .. where)
      if f.why then out("    allowed: " .. f.why) end
    end
  end
end
local summary = {}
for _, check in ipairs({ "fit", "overlap", "inside", "screen", "readable", "sideways" }) do
  local c = counts[check] or { open = 0, allowed = 0 }
  summary[#summary + 1] = string.format("%s %d open/%d allowed", check, c.open, c.allowed)
end
out(string.format("lint: %d scene runs, %d open, %d allowed (%s)", total, open, allowedN, table.concat(summary, ", ")))
local f = assert(io.open(OUT, "wb"))
f:write(table.concat(lines, "\n") .. "\n")
f:close()
print(table.concat(lines, "\n"))
os.exit(open == 0 and 0 or 1)
