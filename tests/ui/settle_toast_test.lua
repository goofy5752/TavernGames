local Wow = require("wow")

-- The „Уредено“ toast (ui/SettleToast.lua): a confirmed payment that names me,
-- seen live, once per id; its second line says whether the account is clear.
local ME, B, C = "Иван Петров", "Мария Стоянова", "Тодор Ангелов"

-- In a guild, booted with the ui/ files, my login queue closed, the hall shown.
-- `saved`: the TavernGamesDB of an earlier session (a relog).
local function readyWow(saved)
  local w = Wow.new{ ui = true, saved = saved }
  w.inGuild = true
  w.roster = { { name = ME .. "-Forever", online = true, guid = Wow.GUID } }
  w:boot()
  w:firstRunDone()
  w:fire("GUILD_ROSTER_UPDATE")
  w:fire("PLAYER_LOGIN")
  w:advance(w.ns.Const.LEDGER_ADOPT_WAIT + 1)
  w.ns.MainWindow.show()
  w:advance(0)
  return w
end

-- `text` without inline colour codes.
local function plain(text) return (tostring(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

local function settle(w)
  w:advance(1)
  w:advance(0)
end

local counters = {}
-- `author`'s entries {k, fields}..., delivered live by GUILD in one LEV (the author is the sender).
local function levMany(w, author, list)
  w:member(author)
  counters[w] = counters[w] or {}
  local out = {}
  for _, item in ipairs(list) do
    local n = (counters[w][author] or 0) + 1
    counters[w][author] = n
    local e = { i = author .. ":" .. n, k = item[1], at = w.G.GetServerTime() }
    for key, value in pairs(item[2]) do e[key] = value end
    out[#out + 1] = e
  end
  w:deliver("GUILD", author, { v = 1, t = "LEV", ev = out })
  return out
end
-- One entry of `author`'s, delivered live, then the next moments.
local function lev(w, author, k, fields)
  local e = levMany(w, author, { { k, fields } })[1]
  settle(w)
  return e
end

local games = 0
local function gid() games = games + 1; return "Мария Стоянова#1/" .. games end

-- `f` owes `t` c copper, confirmed: f's own D (f is not me), or mine.
local function debt(w, f, t, c)
  local fields = { gid = gid(), g = "ttt", f = f, t = t, c = c, why = "lost" }
  if f == ME then
    local e = w.ns.client.ledgerNet:make("D", fields)
    settle(w)
    return e
  end
  return lev(w, f, "D", fields)
end

local function T(w) return w.ns.SettleToast end
local function showing(w) return T(w).frame ~= nil and T(w).frame:IsVisible() end
local function title(w) ok(showing(w), "no toast"); return plain(T(w).title:GetText()) end
local function sub(w) return plain(T(w).sub:GetText()) end

describe("the „Уредено“ toast", function()
  it("the creditor's record of my payment: „Уредено: плати 5g на Мария“, the account clear", function()
    local w = readyWow()
    debt(w, ME, B, 50000)
    eq(showing(w), false)
    lev(w, B, "P", { f = ME, c = 50000, how = "mail" })
    eq(title(w), "Уредено: плати " .. w:coins("5g") .. " на Мария Стоянова")
    eq(sub(w), "по пощата · сметката ви е чиста")
    local f = T(w).frame
    eq({ f:GetSize() }, { 360, 64 }); eq(f:GetFrameStrata(), "DIALOG")
    eq(f.points[1], { "TOP", w.G.UIParent, "TOP", 0, -160 })
    -- A click closes it.
    w:click(f)
    eq(showing(w), false)
  end)

  it("a part payment and an overpayment both say what is left, as a positive amount", function()
    local w = readyWow()
    debt(w, ME, B, 50000)
    lev(w, B, "P", { f = ME, c = 20000, how = "trade" })
    eq(title(w), "Уредено: плати " .. w:coins("2g") .. " на Мария Стоянова")
    eq(sub(w), "с размяна · остават " .. w:coins("3g"))

    local w2 = readyWow()
    debt(w2, ME, B, 50000)
    lev(w2, B, "P", { f = ME, c = 80000, how = "trade" })
    eq(title(w2), "Уредено: плати " .. w2:coins("8g") .. " на Мария Стоянова")
    eq(sub(w2), "с размяна · остават " .. w2:coins("3g")) -- a credit of 3g, never „чиста“, never -3g
  end)

  it("my own „Уредено“ for a debtor: „Уредено: Мария ти плати 5g“, by hand", function()
    local w = readyWow()
    debt(w, B, ME, 50000)
    eq(showing(w), false)
    ok(w.ns.client.pay:settle(B), "recorded")
    eq(showing(w), false) -- drawn on the next frame
    w:advance(0)
    eq(title(w), "Уредено: Мария Стоянова ти плати " .. w:coins("5g"))
    eq(sub(w), "на ръка · сметката ви е чиста")
  end)

  it("nothing for old records: the sync after a login, a stale `at`, a record seen before", function()
    local w = readyWow()
    debt(w, ME, B, 50000)
    lev(w, B, "P", { f = ME, c = 10000, how = "mail" })
    ok(showing(w), "the live one shows")
    -- A relog: the store holds it already, nothing is announced.
    local w2 = readyWow(w.G.TavernGamesDB)
    w2:advance(w2.ns.Const.LEDGER_ADOPT_WAIT + 10)
    eq(showing(w2), false)
    -- The sync's copy of an entry I have not seen: taken, never announced.
    local synced = { i = B .. ":7", k = "P", at = w2.G.GetServerTime(), f = ME, c = 10000, how = "hand" }
    eq(w2.ns.client.ledgerNet:take(synced, C, false), "new")
    settle(w2)
    eq(showing(w2), false)
    -- A live record older than FRESH is ignored; one just at FRESH shows.
    local w3 = readyWow()
    eq(T(w3).FRESH, 300)
    lev(w3, B, "P", { f = ME, c = 10000, how = "mail", at = w3.G.GetServerTime() - 301 })
    eq(showing(w3), false)
    lev(w3, B, "P", { f = ME, c = 20000, how = "mail", at = w3.G.GetServerTime() - 300 })
    eq(title(w3), "Уредено: плати " .. w3:coins("2g") .. " на Мария Стоянова")
    -- The same id delivered again, or emitted twice: one toast.
    local w4 = readyWow()
    local e = lev(w4, B, "P", { f = ME, c = 10000, how = "hand" })
    w4:deliver("GUILD", B, { v = 1, t = "LEV", ev = { e } }); settle(w4)
    w4.ns.client.events:emit("paid", { id = e.i, from = ME, to = B, c = e.c, how = e.how, at = e.at })
    settle(w4)
    ok(showing(w4), "the first")
    w4:advance(T(w4).SECONDS)
    eq(showing(w4), false); eq(#T(w4).queue, 0)
  end)

  it("three payments show one after another, six seconds each; the coin sound once per toast when the client has it", function()
    local w = readyWow()
    eq(T(w).SECONDS, 6)
    w.G.SOUNDKIT.LOOT_WINDOW_COIN_SOUND = 120
    local before = #w.sounds
    levMany(w, B, { { "P", { f = ME, c = 10000, how = "hand" } }, { "P", { f = ME, c = 20000, how = "hand" } },
      { "P", { f = ME, c = 30000, how = "hand" } } })
    eq(showing(w), false) -- the next frame
    w:advance(0)
    eq(title(w), "Уредено: плати " .. w:coins("1g") .. " на Мария Стоянова")
    eq(#w.sounds, before + 1); eq(w.sounds[#w.sounds], { 120, "SFX" })
    w:advance(5.9)
    eq(title(w), "Уредено: плати " .. w:coins("1g") .. " на Мария Стоянова")
    w:advance(0.1)
    eq(title(w), "Уредено: плати " .. w:coins("2g") .. " на Мария Стоянова")
    eq(#w.sounds, before + 2)
    w:click(T(w).frame) -- a click closes it: the next one comes
    w:advance(0)
    eq(title(w), "Уредено: плати " .. w:coins("3g") .. " на Мария Стоянова")
    eq(#w.sounds, before + 3)
    w:advance(6)
    eq(showing(w), false); eq(#w.sounds, before + 3)
    -- Muted: the toast shows, no sound.
    w.ns.db.sound = false
    lev(w, B, "P", { f = ME, c = 40000, how = "hand" })
    eq(title(w), "Уредено: плати " .. w:coins("4g") .. " на Мария Стоянова")
    eq(#w.sounds, before + 3)
  end)

  it("at most five wait; more are dropped", function()
    local w = readyWow()
    eq(T(w).MAX, 5)
    local function p(c) return { "P", { f = ME, c = c, how = "hand" } } end
    levMany(w, B, { p(100), p(200), p(300), p(400) })
    levMany(w, B, { p(500), p(600), p(700) })
    local seen = {}
    w:advance(0)
    while showing(w) do
      seen[#seen + 1] = title(w)
      w:advance(T(w).SECONDS)
    end
    eq(#seen, 5); eq(seen[5], "Уредено: плати " .. w:coins("5s") .. " на Мария Стоянова")
  end)

  it("a payment between two other people shows nothing", function()
    local w = readyWow()
    w:member(C)
    lev(w, B, "P", { f = C, c = 50000, how = "hand" })
    eq(w.ns.client.ledger:get(B .. ":1").f, C)
    eq(showing(w), false)
  end)
end)
