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

local function botsAtMyTable(w, n)
  local _, v = hostTable(w)
  w:slash("bots fill " .. (n or 1)); w:advance(8)
  return v
end

describe("ui: „Махни ботовете“ at my table", function()
  it("shown (in the place of „Добави ботове“) with a bot seated at my fun table; the news line stays at 120 px", function()
    local w = guildWow()
    local v = botsAtMyTable(w)
    ok(w.ns.client.session:seatedCount() == 2, "no bot sat")
    ok(v.clearButton:IsVisible(), "button hidden")
    eq(v.clearButton.text:GetText(), "Махни ботовете")
    eq(v.botsButton:IsVisible(), false) -- one slot: clear takes the place of fill
    local x = 16
    for _, b in ipairs({ v.standButton, v.inviteButton, v.startButton, v.botsButton, v.clearButton }) do
      if b:IsVisible() then x = x + b:GetWidth() + (b == v.standButton and 0 or b.points[1][4]) end
    end
    local lineLeft = x + v.line.points[1][4]
    local lineRight = w.ns.TableFrame.frame:GetWidth() - 12 - 24
    ok(lineRight - lineLeft >= 120, "news line only " .. (lineRight - lineLeft) .. " px")
  end)

  it("hidden with no bots, as a guest, at a staked table and in a live game", function()
    local w = guildWow()
    local _, v = hostTable(w)
    w:slash("bots"); w:advance(0)
    w.ns.client.events:emit("session", w.ns.client.session); w:advance(0)
    eq(v.clearButton:IsVisible(), false)
    w:slash("bots fill 1"); w:advance(8)
    ok(v.clearButton:IsVisible(), "no button with a bot")
    local sess = w.ns.client.session
    sess.status = "live"
    w.ns.client.events:emit("session", sess); w:advance(0)
    eq(v.clearButton:IsVisible(), false)
    eq(w.ns.Bots.canClear(sess), false)
    sess.status = "open"
    sess.stake = 1000
    eq(w.ns.Bots.canClear(sess), false)
    sess.stake = nil
    sess.role = "player"
    eq(w.ns.Bots.canClear(sess), false)
  end)

  it("a click stands the bots up and says so on the table's line", function()
    local w = guildWow()
    local v = botsAtMyTable(w, 2)
    eq(w.ns.client.session:seatedCount(), 3)
    w:click(v.clearButton); w:advance(0)
    eq(w.ns.client.session:seatedCount(), 1)
    eq(#w:texts(w.ns.L("bots.cleared")), 1)
    eq(v.clearButton:IsVisible(), false)
    w:advance(8)
    eq(w.ns.client.session:seatedCount(), 1) -- the fill was cancelled, nobody sits again
  end)

  it("/tavern bots clear does the same", function()
    local w = guildWow()
    botsAtMyTable(w)
    w:slash("bots clear"); w:advance(0)
    eq(w.ns.client.session:seatedCount(), 1)
    w:slash("bots clear")
    eq(#w:chatWith(w.ns.L("bots.noclear")), 1)
  end)
end)

describe("ui: „Закрий“ for a table of bots only", function()
  local function botTable(w, n)
    w:slash("bots"); w:advance(0); w:advance(0)
    for _ = 1, n or 1 do w:slash("bots host dr") end
    w:advance(0); w:advance(0)
    local bots, tid = w.ns.bots, nil
    local rec = w.ns.client.lobby:tables()[1]
    for _ = 1, 8 do w:advance(1) end
    return rec and rec.tid
  end

  it("the floor plan: a Close button under a bot-hosted bot-only table; a click closes it", function()
    local w = guildWow()
    w.ns.MainWindow.show()
    local tid = botTable(w)
    ok(tid, "no bot table")
    w:advance(0)
    local t = w.ns.Hall.view.tables[1]
    ok(t.closeButton:IsVisible(), "no Close button")
    eq(t.closeButton.text:GetText(), "Закрий")
    w:click(t.closeButton); w:advance(0); w:advance(0)
    eq(#w.ns.client.lobby:tables(), 0)
    for _, bot in ipairs(w.ns.bots.list) do eq(bot.session, nil) end
  end)

  it("not offered while a human sits there", function()
    local w = guildWow()
    w.ns.MainWindow.show()
    local tid = botTable(w)
    w.ns.client:sit(tid, 2); w:advance(2); w:advance(0)
    eq(w.ns.client.session.tid, tid)
    ok(not w.ns.Hall.view.tables[1].closeButton:IsVisible(), "offered with me seated")
    ok(not w.ns.bots:botOnly(w.ns.client.lobby:get(tid)), "botOnly")
  end)

  it("not for a table hosted by a real player", function()
    local w = guildWow()
    w:slash("bots"); w:advance(0)
    local rec = { tid = "x", host = "Мария Стоянова", seats = { "Мария Стоянова", false } }
    eq(w.ns.bots:botOnly(rec), nil)
  end)

  it("the list mode gets a Close row action", function()
    local w = guildWow()
    w.ns.MainWindow.show()
    botTable(w, 9)
    eq(w.ns.Hall.mode, "list")
    local r = w.ns.Hall.view.rows[1]
    eq(r.action.text:GetText(), "Закрий")
    w:click(r.action); w:advance(0); w:advance(0)
    eq(#w.ns.client.lobby:tables(), 8)
  end)

  it("/tavern bots close closes them all", function()
    local w = guildWow()
    botTable(w, 3)
    eq(#w.ns.client.lobby:tables(), 3)
    w:slash("bots close"); w:advance(0)
    eq(#w.ns.client.lobby:tables(), 0)
    w:slash("bots close")
    eq(#w:chatWith(w.ns.L("bots.noclose")), 1)
  end)
end)
