local Wow = require("wow")

-- Booted with the ui/ files, PLAYER_LOGIN fired.
local function boot()
  local w = Wow.new{ ui = true }
  w:boot()
  w:firstRunDone()
  w:fire("PLAYER_LOGIN")
  return w
end

-- `s` with every magic character escaped, for gsub.
local function esc(s) return (s:gsub("%p", "%%%0")) end

local function rgba(T, token) return { T.color[token][1], T.color[token][2], T.color[token][3], 1 } end

describe("ui: widgets", function()
  it("the gold button (mockup `.btn`): gold face, darker lip, dark label, the rim lit under the mouse and while lit", function()
    local w = boot(); local W, T = w.ns.W, w.ns.Theme; local clicks = 0
    local b = W.GoldButton(w.G.UIParent, "Обяви 40", function() clicks = clicks + 1 end)
    eq({ b:GetSize() }, { 124, 24 }); eq(b.text:GetText(), "Обяви 40")
    eq(b.fill.color, { 0xdc / 255, 0xb4 / 255, 0x67 / 255, 1 }); eq(b.lip.color, { 0x8a / 255, 0x5a / 255, 0x2b / 255, 1 })
    eq({ b.text:GetTextColor() }, rgba(T, "woodDark")); eq(b.edges[1].vertex, rgba(T, "brass"))
    w:hover(b); eq(b.edges[1].vertex, rgba(T, "gold"))
    b.scripts.OnLeave(b); eq(b.edges[1].vertex, rgba(T, "brass"))
    b.lit = true; w:hover(b); b.scripts.OnLeave(b); eq(b.edges[1].vertex, rgba(T, "gold"))
    w:click(b); eq(clicks, 1)
  end)

  it("the window chrome: tinted wood inside the skin's frame, a cap on each top corner", function()
    local w = boot(); local W, T = w.ns.W, w.ns.Theme
    local f = w.G.CreateFrame("Frame", nil, w.G.UIParent); f:SetSize(300, 200)
    local c = W.chrome(f, 300, 200)
    eq(c.wood:GetTexture(), T.tex.wood); eq(c.wood.points[1], { "TOPLEFT", f, "TOPLEFT", 4, -4 })
    eq(c.wood.points[2], { "BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 4 })
    eq(c.wood.texCoord, { 0, 292 / T.texSize.wood, 0, 192 / T.texSize.wood })
    eq(c.wood.vertex, { T.S.woodTint[1], T.S.woodTint[2], T.S.woodTint[3], 1 })
    eq(#c.frame.pieces, 8)
    for _, p in ipairs(c.frame.pieces) do eq(p:GetTexture(), T.tex.frame); eq(p.layer, "BORDER") end
    eq(T.tex.frame, "Interface\\AddOns\\TavernGames\\media\\skin\\frame_alliance")
    for _, cap in ipairs({ c.caps.left, c.caps.right }) do
      eq(cap:GetTexture(), T.tex.cap); eq({ cap:GetSize() }, { 34, 34 }); eq(cap.layer, "OVERLAY")
    end
    eq(c.caps.left.points[1], { "CENTER", f, "TOPLEFT", 5, -5 }); eq(c.caps.right.points[1], { "CENTER", f, "TOPRIGHT", -5, -5 })
  end)

  it("the crest: ours as a stand-in, the client's when it has one; the mask only where the client masks", function()
    local w = boot(); local W, T = w.ns.W, w.ns.Theme
    local f = w.G.CreateFrame("Frame", nil, w.G.UIParent)
    local c = W.crest(f, 28)
    eq(c:GetTexture(), T.tex.crest_alliance); eq(c.standIn, true); eq({ c:GetSize() }, { 28, 28 })
    eq(W.crest(f, 20, "horde"):GetTexture(), T.tex.crest_horde)
    w:hasFile("Interface\\Timer\\Alliance-Logo"); w.ns.Art.reset()
    local real = W.crest(f, 28, "alliance")
    eq(real:GetTexture(), "Interface\\Timer\\Alliance-Logo"); ok(not real.standIn)
    local tex = f:CreateTexture()
    local m = W.mask(tex, f)
    ok(m); eq(m.objectType, "MaskTexture"); eq(m:GetTexture(), T.tex.mask)
    eq(m.wrap, { "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE" }); eq(tex.masks, { m })
    eq(W.mask({ SetTexture = function() end }, f), nil)
    eq(W.mask(f:CreateTexture(), { CreateTexture = f.CreateTexture }), nil)
  end)

  it("the book is parchment with the faction's wax seal", function()
    local w = boot(); local W, T = w.ns.W, w.ns.Theme
    local f = w.G.CreateFrame("Frame", nil, w.G.UIParent)
    local paper = W.paper(f)
    eq(paper:GetTexture(), T.tex.parchment)
    eq(T.rgb("paperHead") ~= nil, true)
    local s = W.seal(f, 56)
    eq({ s:GetSize() }, { 56, 56 })
    eq(s.points[1], { "TOPRIGHT", f, "TOPRIGHT", -22, 14 })
    eq(s.disc:GetTexture(), T.tex.chair); eq(s.disc.vertex, rgba(T, "banner"))
    eq({ s.crest:GetSize() }, { 56 * 0.62, 56 * 0.62 })
    eq(s.crest:GetTexture(), T.tex.crest_alliance); ok(s.crest.standIn)
    eq(s.crest.alpha, 0.85)
    -- the crest draws on the wax, never under it (same layer, a higher sublevel)
    eq({ s.disc.layer, s.disc.sublayer or 0 }, { "ARTWORK", 0 }); eq({ s.crest.layer, s.crest.sublayer }, { "ARTWORK", 1 })
    local label = W.Label(f, "paperHeading", "x", 18)
    eq({ label:GetTextColor() }, rgba(T, "paperHead"))
  end)

  it("a panel is a dark translucent fill", function()
    local w = boot()
    eq(w.ns.W.Panel(w.G.UIParent).fill.color, { 0, 0, 0, 0.38 })
  end)

  it("the ghost button (mockup `.btn.ghost`): dark fill, brass rim, its label in the colour asked for", function()
    local w = boot(); local W, T = w.ns.W, w.ns.Theme; local clicks = 0
    local b = W.GhostButton(w.G.UIParent, "Смени деветката", "brassLight", function() clicks = clicks + 1 end)
    eq({ b:GetSize() }, { 124, 24 }); eq(b.fill.color, W.DARK_FILL); eq({ b.text:GetTextColor() }, rgba(T, "brassLight"))
    eq(b.edges[1].vertex, rgba(T, "brass")); w:hover(b); eq(b.edges[1].vertex, rgba(T, "gold"))
    b.scripts.OnLeave(b); eq(b.edges[1].vertex, rgba(T, "brass"))
    b.lit = true; b.scripts.OnLeave(b); eq(b.edges[1].vertex, rgba(T, "gold"))
    w:click(b); eq(clicks, 1)
  end)

  it("W.money is Util.money with coins for letters, amount for amount", function()
    local w = boot(); local W = w.ns.W
    local function back(text)
      return (text:gsub(esc(W.coinTag("gold")), "g"):gsub(esc(W.coinTag("silver")), "s"):gsub(esc(W.coinTag("copper")), "c"))
    end
    for _, c in ipairs({ 0, 1, 99, 100, 10000, 10001, 123456, 99999999999, 50000.7, 1090909 }) do
      local shown = W.money(c)
      ok(not shown:find("%d[gsc]"), "a letter left in " .. shown)
      eq(back(shown), w.ns.Util.money(c), tostring(c))
    end
    local T = w.ns.Theme
    local gold, silver, copper = W.coinTag("gold"), W.coinTag("silver"), W.coinTag("copper")
    eq(W.money(123456), "12" .. gold .. " 34" .. silver .. " 56" .. copper)
    eq(W.money(0), "0" .. copper)
    eq(W.money(50000), "5" .. gold)
    eq(W.money(10203), "1" .. gold .. " 2" .. silver .. " 3" .. copper)
    eq(w:coins("12g 34s"), "12" .. gold .. " 34" .. silver)
    eq(w:coins("Дължиш 5g, не 50s"), "Дължиш 5" .. gold .. ", не 50" .. silver)
    eq(gold, "|T" .. T.tex.coins .. ":0:0:0:0:128:32:0:32:0:32|t")
  end)

  it("the client's coin icons are used when the client has them, ours otherwise", function()
    local w = boot(); local W, T = w.ns.W, w.ns.Theme
    eq(T.tex.coins, "Interface\\AddOns\\TavernGames\\media\\skin\\coins")
    eq(W.coinTag("gold"), "|T" .. T.tex.coins .. ":0:0:0:0:128:32:0:32:0:32|t")
    eq(W.coinTag("silver"), "|T" .. T.tex.coins .. ":0:0:0:0:128:32:32:64:0:32|t")
    eq(W.coinTag("copper"), "|T" .. T.tex.coins .. ":0:0:0:0:128:32:64:96:0:32|t")
    w:hasFile("Interface\\MoneyFrame\\UI-GoldIcon"); w:hasFile("Interface\\MoneyFrame\\UI-CopperIcon"); w.ns.Art.reset()
    eq(W.coinTag("gold"), "|TInterface\\MoneyFrame\\UI-GoldIcon:0|t")
    eq(W.coinTag("silver"), "|T" .. T.tex.coins .. ":0:0:0:0:128:32:32:64:0:32|t")
    eq(W.coinTag("copper"), "|TInterface\\MoneyFrame\\UI-CopperIcon:0|t")
    eq(W.money(1020304), "102|TInterface\\MoneyFrame\\UI-GoldIcon:0|t 3" .. W.coinTag("silver") .. " 4|TInterface\\MoneyFrame\\UI-CopperIcon:0|t")
    eq(w:coins("102g 3s 4c"), W.money(1020304))
    local bare = Wow.new{ ui = true, noArt = true }
    bare:boot(); bare:firstRunDone(); bare:fire("PLAYER_LOGIN")
    eq(bare.ns.W.coinTag("gold"), "|T" .. T.tex.coins .. ":0:0:0:0:128:32:0:32:0:32|t")
    eq(bare.ns.W.money(5), "5|T" .. T.tex.coins .. ":0:0:0:0:128:32:64:96:0:32|t")
  end)

  it("no ui file formats gold with letters any more", function()
    local seen = 0
    for p in io.lines("tests/.files.txt") do
      p = p:gsub("\r", "")
      if p:match("^ui/.+%.lua$") then
        local n = 0
        for line in io.lines(p) do
          local code = line:gsub("%-%-.*$", "")
          if code:find("Util.money", 1, true) then n = n + 1 end
        end
        -- W.money itself is the one pass over Util.money's text.
        eq(n, p == "ui/Widgets.lua" and 1 or 0, p)
        seen = seen + 1
      end
    end
    ok(seen > 20, "ui files scanned: " .. seen)
  end)
end)

describe("ui: W.fit measures the whole text (final fix)", function()
  it("a font string with its own width: the client bounds GetStringWidth by it, W.fit still shrinks", function()
    local w = boot(); local W = w.ns.W
    local fs = W.Label(w.G.UIParent, "ui", "", 12)
    fs:SetFont(w.ns.Theme.font.ui, 12, "") -- a whole size: 6 px a character in the fake
    fs:SetWidth(40); fs:SetText("123456789012") -- 12 characters at 6 px: 72 px of text in 40
    eq({ fs:GetStringWidth(), fs:GetUnboundedStringWidth(), W.textWidth(fs) }, { 40, 72, 72 })
    W.fit(fs, "1234567890", 40)
    eq(select(2, fs:GetFont()), 8) -- 10 characters fit 40 px only at 8 (the floor)
    W.fit(fs, "1234567890", 40, 10); eq(select(2, fs:GetFont()), 10) -- a floor of its own
    W.fit(fs, "123", 40); eq(select(2, fs:GetFont()), 12)          -- a short text keeps the size
    local bare = { GetStringWidth = function() return 7 end }
    eq(W.textWidth(bare), 7) -- a client without GetUnboundedStringWidth
  end)
end)

describe("ui: W.fitWrap shrinks, then wraps: never clips", function()
  it("a short text keeps its size; a long one shrinks to the floor, then wraps; a long word breaks", function()
    local w = boot(); local W = w.ns.W
    local fs = W.Label(w.G.UIParent, "ui", "", 12)
    fs:SetFont(w.ns.Theme.font.ui, 12, "") -- 6 px a character in the fake
    local h = W.fitWrap(fs, "Ivan", 46)
    eq({ fs:GetText(), select(2, fs:GetFont()), fs.wordWrap, fs:GetWidth(), h }, { "Ivan", 12, true, 46, 15 })
    W.fitWrap(fs, "Barleybrew", 46) -- 10 characters: 60 px at 12, 45 at 9
    eq({ fs:GetText(), (select(2, fs:GetFont())) }, { "Barleybrew", 9 })
    -- 14 characters at the floor (4.5 px): 63 px in 46, broken after 10 letters
    W.fitWrap(fs, "Barleybrewster", 46)
    eq({ fs:GetText(), (select(2, fs:GetFont())) }, { "Barleybrew\nster", 9 })
    -- words wrap at their spaces; only the word too long alone is broken
    W.fitWrap(fs, "a Barleybrewster b", 46)
    eq(fs:GetText(), "a Barleybrew\nster b")
    -- a colour-coded word is never cut inside its codes
    W.fitWrap(fs, "|cffff0000Barleybrewster|r", 46)
    eq(fs:GetText(), "|cffff0000Barleybrewster|r")
  end)

  -- Review: a colour-coded word wider than the room was never broken; a width of 0 meant unbounded.
  it("a colour-coded word too wide is broken by the client where it can; the width is never 0", function()
    local w = boot(); local W = w.ns.W
    local fs = W.Label(w.G.UIParent, "ui", "", 12)
    fs:SetFont(w.ns.Theme.font.ui, 12, "")
    W.fitWrap(fs, "|cffff0000Barleybrewster|r", 46) -- no SetNonSpaceWrap (an old client): no fault
    local nonSpace
    fs.SetNonSpaceWrap = function(_, on) nonSpace = on end
    W.fitWrap(fs, "|cffff0000Barleybrewster|r", 46)
    eq(nonSpace, true)
    W.fitWrap(fs, "Barleybrewster", 46) -- broken by its letters here: the client's own breaking off
    eq(nonSpace, false)
    W.fitWrap(fs, "Ivan", 0)
    eq(fs:GetWidth(), 1)
    W.fitWrap(fs, "Ivan", -5)
    eq(fs:GetWidth(), 1)
  end)
end)

describe("ui: a name on screen (ui/NameTag.lua)", function()
  it("short: a person's first word, a bot's own name with the brass cog after it, an initial for two alike", function()
    local w = boot(); local W, T = w.ns.W, w.ns.Theme
    eq(W.BOT_MARK, "|T" .. T.tex.botmark .. ":0|t")
    eq(T.tex.botmark, "Interface\\AddOns\\TavernGames\\media\\botmark")
    eq(W.short("Ivan Petrovski-Forever"), "Ivan")
    eq(W.short("Bot Barleybrew"), "Barleybrew " .. W.BOT_MARK)
    eq(W.short("Bot Number12"), "Number12 " .. W.BOT_MARK)
    local seats = { "Ivan Petrovski", "Ivan Kolev", "Bot Ivanov", false }
    eq({ W.short(seats[1], seats), W.short(seats[2], seats), W.short(seats[3], seats) },
      { "Ivan P.", "Ivan K.", "Ivanov " .. W.BOT_MARK })
    -- in a sentence: the name in its class colour, the mark after the colour (it keeps its brass)
    eq(W.shortColored(nil, "Bot Petrova"), W.paint("Petrova", w.ns.classColor(nil)) .. " " .. W.BOT_MARK)
    eq(W.shortColored(nil, "Ivan Petrovski"), W.paint("Ivan", w.ns.classColor(nil)))
    eq(W.shortColored(nil, nil), "?")
    eq({ W.fullName("Ivan Petrovski-Forever"), W.fullName(nil) }, { "Ivan Petrovski", "?" })
  end)

  it("a hover shows the whole name without the realm; the frame's own hover still works", function()
    local w = boot(); local W = w.ns.W
    local f = w.G.CreateFrame("Frame", nil, w.G.UIParent)
    local lit, who = 0, "Ivan Petrovski-Forever"
    f:SetScript("OnEnter", function() lit = lit + 1 end)
    f:SetScript("OnLeave", function() lit = lit - 1 end)
    W.nameTip(f, function() return who end)
    eq(f.mouse, true)
    w:hover(f)
    eq(lit, 1); eq(w.G.GameTooltip.lines, { "Ivan Petrovski" }); eq(w.G.GameTooltip:IsShown(), true)
    f.scripts.OnLeave(f)
    eq(lit, 0); eq(w.G.GameTooltip:IsShown(), false)
    -- several names (a list with an empty seat and one name twice): each once, in order
    who = { "Bot Petrova", false, "Maria Stoyanova", "Bot Petrova" }
    w:hover(f)
    eq(w.G.GameTooltip.lines, { "Bot Petrova", "Maria Stoyanova" })
    f.scripts.OnLeave(f)
    -- nothing to name: no tooltip
    who = nil
    w:hover(f)
    eq(w.G.GameTooltip:IsShown(), false)
  end)
end)
