local Wow = require("wow")
local Staked = require("staked")

local ME = "Иван Петров"

local function guildWow()
  local w = Wow.new{ ui = true }
  w.inGuild = true
  w.roster = { { name = ME .. "-Forever", online = true, guid = Wow.GUID } }
  w.G.RAID_CLASS_COLORS.PRIEST = { r = 1, g = 1, b = 1 }
  w:boot(); w:firstRunDone()
  w:fire("GUILD_ROSTER_UPDATE"); w:fire("PLAYER_LOGIN")
  return w
end

local function hostTable(w, game)
  local tid = w.ns.client:openTable{ game = game or "deathroll", access = "invite", turn = 45, opt = { start = 100 } }
  w:advance(0)
  return tid, w.ns.TableFrame.view
end

describe("ui: „Добави ботове“ at the table", function()
  it("shown for the host of a fun table with free seats; its text is the key's", function()
    local w = guildWow()
    local _, v = hostTable(w)
    ok(v.botsButton:IsVisible(), "button hidden")
    eq(v.botsButton.text:GetText(), "Добави ботове")
  end)

  it("hidden for a guest, a staked table, a full table and a live game", function()
    local w = guildWow()
    w:slash("bots"); w:advance(0); w:advance(0)
    w:slash("bots host dr"); w:advance(0); w:advance(0)
    w.ns.client:sit(w.ns.client.lobby:tables()[1].tid, 2); w:advance(1)
    eq(w.ns.client.session.role, "player")
    eq(w.ns.TableFrame.view.botsButton:IsVisible(), false)

    local s = Staked.guildWow and Staked.guildWow()
    ok(s, "no staked world")
    local tid = s.ns.client:openTable{ game = "deathroll", access = "guild", turn = 45, stake = 1000, opt = { start = 1000 } }
    assert(tid); s:advance(0)
    eq(s.ns.TableFrame.view.botsButton:IsVisible(), false)
  end)

  it("never at a table for real gold: a cash Холдем table gets no button, and bots refuse to fill it", function()
    local s = Staked.guildWow()
    assert(s.ns.client:openTable{ game = "holdem", access = "guild", turn = 45, stake = 1000, opt = { blinds = 10 } })
    s:advance(0)
    local sess = s.ns.client.session
    ok(sess.stake and s.ns.Stakes.cash(sess), "not a cash table")
    eq(s.ns.Bots.canFill(sess), false)
    eq(s.ns.TableFrame.view.botsButton:IsVisible(), false)
    local seated = sess:seatedCount()
    s:slash("bots fill"); s:advance(0); s:advance(1); s:advance(5)
    eq(sess:seatedCount(), seated) -- no bot sat down
    for _, name in ipairs(sess.seats) do ok(not (name and s.ns.bots and s.ns.bots.isBot[name]), "a bot sat at a cash table") end
  end)

  it("hidden when the table is full or its game runs", function()
    local w = guildWow()
    local _, v = hostTable(w)
    local sess = w.ns.client.session
    for i = 2, #sess.seats do sess.seats[i] = "Бот " .. i end
    w.ns.client.events:emit("session", sess); w:advance(0)
    eq(v.botsButton:IsVisible(), false)
    for i = 2, #sess.seats do sess.seats[i] = false end
    sess.status = "live"
    w.ns.client.events:emit("session", sess); w:advance(0)
    eq(v.botsButton:IsVisible(), false)
  end)

  it("a click turns the bots on, seats them, and says so on the table's own line", function()
    local w = guildWow()
    local _, v = hostTable(w)
    w:click(v.botsButton)
    ok(w.ns.bots, "bots not on")
    eq(#w:texts(w.ns.L("bots.on")), 1)
    w:advance(8)
    ok(w.ns.client.session:seatedCount() > 1, "no bot sat")
  end)

  it("/tavern bots fill still works", function()
    local w = guildWow()
    hostTable(w)
    w:slash("bots fill 1"); w:advance(6)
    eq(w.ns.client.session:seatedCount(), 2)
  end)
end)

describe("ui: the table's bottom row with all four buttons", function()
  it("keeps the news line at least 120 px wide and the bots button explains itself", function()
    local w = guildWow()
    local _, v = hostTable(w)
    local s = w.ns.client.session
    s.seats[2] = "Някой" -- one more player: „Започни“ shows too
    w.ns.client.events:emit("session", s); w:advance(0)
    for _, b in ipairs({ v.standButton, v.inviteButton, v.startButton, v.botsButton }) do ok(b:IsVisible(), "a button is hidden") end
    local x = 16 -- EDGE + 4
    for _, b in ipairs({ v.standButton, v.inviteButton, v.startButton, v.botsButton }) do
      local p = b.points[1]
      x = x + (p[2] == v.standButton and 0 or 0) + b:GetWidth() + (b == v.standButton and 0 or p[4])
    end
    local frameW = w.ns.TableFrame.frame:GetWidth()
    local lineLeft = x + v.line.points[1][4]
    local lineRight = frameW - 12 - 24
    ok(lineRight - lineLeft >= 120, "news line only " .. (lineRight - lineLeft) .. " px")
    w:hover(v.botsButton)
    eq(w.G.GameTooltip.lines[1], w.ns.L("table.addBots.tip"))
  end)

  it("the hall sign refreshes on GUILD_ROSTER_UPDATE", function()
    local w = guildWow()
    w.ns.MainWindow.show(); w:advance(0)
    w.guildName = false; w:fire("GUILD_ROSTER_UPDATE"); w:advance(0)
    eq(w.ns.Hall.view.sign:IsVisible(), false)
    w.guildName = "Късна"; w:fire("GUILD_ROSTER_UPDATE"); w:advance(0)
    ok(w.ns.Hall.view.sign:IsVisible(), "sign not shown")
  end)
end)
