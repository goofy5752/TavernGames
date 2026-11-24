local Wow = require("wow")

local ME = "Иван Петров"

local function guildWow(name)
  local w = Wow.new{ ui = true }
  w.inGuild = true
  w.guildName = name
  w.roster = { { name = ME .. "-Forever", online = true, guid = Wow.GUID } }
  w:boot(); w:firstRunDone()
  w:fire("GUILD_ROSTER_UPDATE"); w:fire("PLAYER_LOGIN")
  w.ns.MainWindow.show()
  w:advance(0)
  return w
end

-- The edges of the sign inside the centre panel, and what the title and hint need.
local function span(w)
  local v = w.ns.Hall.view
  local sign, W = v.sign, w.ns.W
  local half = v.centreW / 2
  return half - sign:GetWidth() / 2, half + sign:GetWidth() / 2, 10 + W.textWidth(v.title), v.centreW - 10 - W.textWidth(v.hint)
end

describe("ui: the tavern sign in the hall header", function()
  it("shows the guild's name between two crests, with the note and the tooltip", function()
    local w = guildWow("Златна кана")
    local sign = w.ns.Hall.view.sign
    ok(sign:IsVisible(), "sign hidden")
    eq(sign.name:GetText(), "Златна кана")
    eq(sign.name:GetFont(), w.ns.Theme.font.heading)
    ok(sign.crestL:IsVisible() and sign.crestR:IsVisible(), "crests")
    eq({ sign.crestL:GetWidth(), sign.crestR:GetWidth() }, { 18, 18 })
    eq(sign.note:GetText(), "само за гилдията")
    w:hover(sign)
    eq(w.G.GameTooltip.lines, { "Златна кана", "Масите в механата виждат и на тях сядат само членовете на гилдията." })
  end)

  it("is hidden outside a guild and while the name is not known", function()
    local w = guildWow(false)
    eq(w.ns.Hall.view.sign:IsVisible(), false)
    local n = Wow.new{ ui = true }
    n:boot(); n:firstRunDone(); n:fire("PLAYER_LOGIN"); n.ns.MainWindow.show(); n:advance(0)
    eq(n.ns.Hall.view.sign:IsVisible(), false)
  end)

  it("appears when the guild's name becomes known (PLAYER_GUILD_UPDATE)", function()
    local w = guildWow(false)
    w.guildName = "Късна гилдия"
    w:fire("PLAYER_GUILD_UPDATE"); w:advance(0)
    ok(w.ns.Hall.view.sign:IsVisible(), "still hidden")
    eq(w.ns.Hall.view.sign.name:GetText(), "Късна гилдия")
  end)

  it("a very long name shrinks and never overlaps the title or the hint", function()
    local w = guildWow(string.rep("Дълго име ", 12))
    local sign = w.ns.Hall.view.sign
    local left, right, titleEnd, hintStart = span(w)
    ok(sign:IsVisible(), "hidden")
    ok(left >= titleEnd, "overlaps the title: " .. left .. " < " .. titleEnd)
    ok(right <= hintStart, "overlaps the hint: " .. right .. " > " .. hintStart)
    ok(sign.name:GetFont() ~= nil)
    -- never cut: at 9 at the least, wrapped, the sign as tall as its lines
    ok(select(2, sign.name:GetFont()) >= 9 - 0.01, "smaller than readable")
    eq(sign.name.wordWrap, true)
    ok(sign.name:GetStringHeight() <= sign:GetHeight(), "taller than the sign")
    eq(sign.name:GetText(), string.rep("Дълго име ", 12))
  end)

  it("a short name leaves the sign compact and centred", function()
    local w = guildWow("Кана")
    local left, right = span(w)
    local v = w.ns.Hall.view
    ok(math.abs((left + right) / 2 - v.centreW / 2) < 0.01, "not centred")
    ok(v.sign:GetWidth() < 300, "too wide")
  end)
end)
