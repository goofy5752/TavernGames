-- Headless screenshots, part 1: each scene boots the tests' fake WoW client
-- (tests/helpers/wow.lua) with the addon's ui/ files, sets itself up through the
-- addon's own code paths (bots host and play real games on the fake clock), and
-- writes the visible frame tree as a draw list to tools/shots/build/<scene>.json.
-- tools/shots/render.py draws those lists. Run from the repo root:
--     luajit tools/shots/scenes.lua [scene ...]
package.path = "tests/helpers/?.lua;tools/shots/?.lua;" .. package.path
Loader = require("loader")
local Shim = require("shim")
local Wow = require("wow")

local OUT = "tools/shots/build/"
local ME = "Psychedelic"
local GUILD = "The Gilded Tankard"

-- The client's class colours (RAID_CLASS_COLORS), for the fake that knows only the mage's.
local CLASS_COLORS = {
  WARRIOR = { 0.78, 0.61, 0.43 }, PALADIN = { 0.96, 0.55, 0.73 }, HUNTER = { 0.67, 0.83, 0.45 },
  ROGUE = { 1.00, 0.96, 0.41 }, PRIEST = { 1.00, 1.00, 1.00 }, SHAMAN = { 0.00, 0.44, 0.87 },
  MAGE = { 0.25, 0.78, 0.92 }, WARLOCK = { 0.53, 0.53, 0.93 }, DRUID = { 1.00, 0.49, 0.04 },
}

local RACES = { Alliance = { "Draenei", "Draenei", 11 }, Horde = { "Orc", "Orc", 2 } } -- a shaman: the Draenei for the Alliance

-- A fresh client in a guild, English UI, the player's name known, logged in.
-- opts.faction: "Alliance" (default) | "Horde"; opts.members: more guild members (online);
-- opts.lang: "en" (default) | "bg"; opts.guild: the guild's name; opts.money: copper in my bags;
-- opts.screen: {w, h}, UIParent's size (default the tests' 1920 x 1080).
-- The client art tools/shots/client_art.py took out of the WoW install (none: the addon's stand-ins show).
local CLIENT_ART = Shim.loadClientArt()

-- Set while a scene's Horde twin runs (see the end of the scenes): boot takes the Horde, write adds "_horde".
local VARIANT

local function boot(opts)
  opts = opts or {}
  math.randomseed(opts.seed or 7)
  Wow.FIRST = ME
  local w = Wow.new{ ui = true, noArt = not CLIENT_ART }
  -- The client has the files we took out; no atlas (their coordinates live in the client's database), so the
  -- addon takes each asset's file candidate.
  for path in pairs(Shim.clientFiles) do w:hasFile(path) end
  Shim.G = w.G
  -- A table's address feeds the deal's seed pool (Adapter's entropy): numbered
  -- instead, so a scene deals the same cards on every run.
  local ids, count, plain = setmetatable({}, { __mode = "k" }), 0, tostring
  w.G.tostring = function(v)
    local mt = type(v) == "table" and getmetatable(v)
    if type(v) == "table" and not (mt and mt.__tostring) then
      if not ids[v] then count = count + 1; ids[v] = count end
      return string.format("table: 0x%08x", ids[v])
    end
    return plain(v)
  end
  -- The 3-D portrait of a unit is the client's render, which no file holds: the addon's own fallback shows.
  w.G.SetPortraitTexture, w.G.SetPortraitToTexture = nil, nil
  w.faction = opts.faction or VARIANT or "Alliance"
  w.race = RACES[w.faction]
  w.sex = 2
  w.inGuild, w.guildName = true, opts.guild or GUILD
  if opts.screen then w.G.UIParent:SetSize(opts.screen[1], opts.screen[2]) end
  w.roster = { { name = ME .. "-Forever", online = true, guid = Wow.GUID } }
  for _, m in ipairs(opts.members or {}) do
    w.roster[#w.roster + 1] = { name = m .. "-Forever", online = true, guid = "Player-1-" .. m }
  end
  for cls, c in pairs(CLASS_COLORS) do w.G.RAID_CLASS_COLORS[cls] = { r = c[1], g = c[2], b = c[3] } end
  w.G.UnitClass = function() return "Shaman", "SHAMAN", 7 end
  w.money = opts.money or 2473650
  w:boot()
  w.ns.db.lang, w.ns.db.introDone = opts.lang or "en", true
  w.ns.Locale.set(opts.lang or "en")
  w:fire("GUILD_ROSTER_UPDATE")
  w:fire("PLAYER_LOGIN")
  w:advance(0)
  return w
end

-- Runs the fake clock for `seconds` in steps, drawing a frame at each (OnUpdate).
local function run(w, seconds, step)
  step = step or 0.25
  local t = 0
  while t < seconds do
    w:advance(step)
    w:render(step)
    t = t + step
  end
end

-- Runs until pred() or `limit` seconds -> true when pred held.
local function runUntil(w, pred, limit, step)
  step = step or 0.25
  local t = 0
  while t < (limit or 60) do
    if pred() then return true end
    w:advance(step)
    w:render(step)
    t = t + step
  end
  return pred()
end

local function botsOn(w)
  if not w.ns.bots then w:slash("bots") end
  w:advance(0); w:advance(0)
  return w.ns.bots
end

local function write(name, w, frames, opts)
  opts = opts or {}
  if VARIANT == "Horde" and not name:find("_horde$") then name = name .. "_horde" end
  local snap = Shim.snapshot(w, opts.skip)
  snap.name = name
  -- With the client's art the world shows around the window(s): a wider margin.
  snap.crop = Shim.bounds(frames, opts.margin or (CLIENT_ART and 44 or 24))
  snap.screen = { w.G.UIParent.width, w.G.UIParent.height }
  -- Output px per UI unit: about 1400 px wide, between 1.25 and 2.
  local cw = snap.crop[3] - snap.crop[1]
  snap.scale = opts.scale or math.max(1.25, math.min(2, 1400 / cw))
  snap.faction = w.faction
  local f = assert(io.open(OUT .. name .. ".json", "wb"))
  f:write(Shim.json(snap))
  f:close()
  for cp in pairs(Shim.noGlyph) do snap.missing[#snap.missing + 1] = string.format("glyph U+%04X", cp) end
  Shim.noGlyph = {}
  local miss = #snap.missing > 0 and (" (client art left out: " .. table.concat(snap.missing, ", ") .. ")") or ""
  print(string.format("%-12s %5d items%s", name, #snap.items, miss))
end

-- I open a fun table of `game` and the „Add bots“ button seats `n` bots (all
-- free seats when nil); then „Start“ when it shows. -> the session.
local function myTable(w, game, opts, n)
  local client = w.ns.client
  client:openTable{ game = game, access = "guild", turn = 45, opt = opts }
  w:advance(0)
  local v = w.ns.TableFrame.view
  if n then
    if not w.ns.bots then botsOn(w) end
    w.ns.bots:fill(n)
  else
    w:click(v.botsButton)
  end
  local s = client.session
  runUntil(w, function() return s:seatedCount() >= (n and n + 1 or #s.seats) end, 30)
  run(w, 1)
  if v.startButton:IsVisible() then w:click(v.startButton) end
  run(w, 0.5)
  return s
end

-- Plays my turns the way a bot would (the engine's bot move, else the automatic
-- move), each after `think` s, until stop(state, session) holds on my turn or
-- `limit` s pass -> true when stopped there.
-- `choose(state, session, legal)` may pick my action first. A server roll I ask
-- for (RandomRoll) is answered by the server's chat line, as the client sees it.
local function play(w, stop, limit, think, choose)
  local client, waited, acts, rolled = w.ns.client, 0, 0, #w.rolls
  think = think or 1
  local t = 0
  while t < (limit or 300) do
    local s = client.session
    local st = s and s.state
    local mine = st and s.status == "live" and st.turn == s.mySeat
    if st and stop(st, s, mine, acts) then return true end
    if mine then
      waited = waited + 0.25
      if waited >= think then
        waited = 0
        local engine = s:engine()
        local a = choose and choose(st, s, engine.legal and engine.legal(st, s.mySeat) or {})
        if a == true then -- choose pressed the view's own button
        else
          if not a then a = engine.bot and engine.bot(st, s.mySeat, math.random) end
          if a then client:act(a) else client:playAuto() end
        end
        acts = acts + 1
      end
    else
      waited = 0
    end
    while #w.rolls > rolled do
      rolled = rolled + 1
      local r = w.rolls[rolled]
      w:advance(0.5)
      w:fire("CHAT_MSG_SYSTEM", string.format(w.G.RANDOM_ROLL_RESULT, ME, math.random(r[1], r[2]), r[1], r[2]))
    end
    w:advance(0.25); w:render(0.25)
    t = t + 0.25
  end
  return false
end

local Scenes, ORDER = {}, {}
-- `extra`: a scene for checking the UI, made only when named (not a README picture).
local function scene(name, fn, extra) Scenes[name] = fn; if not extra then ORDER[#ORDER + 1] = name end end

---------------------------------------------------------------------------

-- The hall: bots host tables of several games, some running (a second bot sat
-- down), some waiting; two guild members play Santase at Elowen's table; my own
-- Hold'em table runs with three bots (its window closed, the hall in front).
local ledgerHistory, members
local function hall(w)
  w:advance(w.ns.Const.LEDGER_ADOPT_WAIT + 1)
  ledgerHistory(w) -- the guild's members and their ledger: my accounts have rows
  local bots = botsOn(w)
  local function host(game) local tid = bots:hostTable(game); w:advance(0); w:advance(0); return tid end
  -- A bot sits at a bot's table (the game starts by itself).
  local function join(tid, seat)
    local b = bots:idle()
    w:advance(0)
    b:sit(tid, seat)
    w:advance(0); w:advance(0)
  end
  local t1 = host("belot"); join(t1, 2); join(t1, 3); join(t1, 4)
  local t2 = host("chess"); join(t2, 2)
  local t3 = host("tabla"); join(t3, 2)
  host("deathroll")
  host("ttt")
  -- Elowen's table, announced to the guild: she and Thorgar play Santase.
  local tid = "Elowen#1"
  w:deliver("GUILD", "Elowen", { v = 1, t = "TBL", tid = tid, g = "santase", h = "Elowen", e = 1, ac = "guild", tn = 45,
                                 st = "live", s = { "Elowen", "Thorgar" }, w = 0 })
  for _, m in ipairs({ { "Elowen", "DRUID" }, { "Thorgar", "WARRIOR" } }) do
    w:deliver("GUILD", m[1], { v = 1, t = "HI", ver = "0.1.0", cls = m[2], id = "Player-1-" .. m[1], at = tid })
  end
  run(w, 6)
  myTable(w, "holdem", nil, 3)
  w.ns.TableFrame.frame:Hide() -- I closed the table window: the hall is in front
  run(w, 4)
  w.ns.MainWindow.show("hall")
  run(w, 1)
  w.ns.TableFrame.frame:Hide() -- a new hand brings the table window back: closed again
  w:advance(0)
end

scene("hall", function()
  local w = boot{ seed = 9 }
  hall(w)
  write("hall", w, { w.ns.MainWindow.frame })
end)

---------------------------------------------------------------------------

scene("belot", function()
  local w = boot{ seed = 11 }
  myTable(w, "belot")
  local okStop = play(w, function(st, _, mine)
    return mine and st.phase == "play" and (st.round or 1) >= 2 and #(st.trick or {}) == 2
  end, 600)
  assert(okStop, "belot: no mid-hand moment found")
  run(w, 0.5)
  write("belot", w, { w.ns.TableFrame.frame })
end)

scene("santase", function()
  -- Declare a marriage when I can; stop on my turn after the bot led, my marriage
  -- partner face up in my hand, the stock still open.
  local found
  for seed = 1, 40 do
    local w = boot{ seed = seed }
    local s = myTable(w, "santase")
    local okStop = play(w, function(st, _, mine)
      if not mine or st.phase ~= "play" or #st.trick ~= 1 or st.closed ~= nil or #st.stock <= 2 then return false end
      if (st.gp[1] or 0) + (st.gp[2] or 0) > 5 then return false end
      local shown = false
      for _, i in ipairs(st.hands[s.mySeat]) do if st.shown[i] then shown = true end end
      return (st.mar[s.mySeat] or 0) > 0 and shown
    end, 240, 1, function(st, _, legal)
      for _, a in ipairs(legal) do if a.k == "marry" then return a end end
    end)
    if okStop then found = w; break end
  end
  assert(found, "santase: no marriage moment found")
  run(found, 0.5)
  write("santase", found, { found.ns.TableFrame.frame })
end)

-- My lead with „Затвори“ offered and a last trick on the felt: the buttons beside my hand
-- (made only when named).
scene("santase_close", function()
  local found
  for seed = 1, 40 do
    local w = boot{ seed = seed }
    local s = myTable(w, "santase")
    local okStop = play(w, function(st, _, mine)
      return mine and st.phase == "play" and #st.trick == 0 and st.closed == nil and #st.stock > 2
        and #(st.last or {}) > 0
    end, 240, 1)
    if okStop then found = w; break end
  end
  assert(found, "santase: no lead with a last trick found")
  run(found, 0.5)
  write("santase_close", found, { found.ns.TableFrame.frame })
end, true)

scene("tabla", function()
  local w = boot{ seed = 3 }
  myTable(w, "tabla")
  local okStop = play(w, function(st, _, mine, acts)
    return mine and acts >= 9 and st.dice ~= nil and st.phase == "move"
  end, 600)
  assert(okStop, "tabla: no mid-game moment found")
  run(w, 0.75)
  write("tabla", w, { w.ns.TableFrame.frame })
end)

-- Hold'em at a fun table of five: my turn on the turn or river with a made hand,
-- the hand history panel open beside the table.
scene("holdem", function()
  local found
  for seed = 1, 60 do
    local w = boot{ seed = seed }
    myTable(w, "holdem", nil, 4)
    local v = w.ns.TableFrame.view
    local okStop = play(w, function(st, _, mine)
      if not mine or #(st.board or {}) < 4 then return false end
      for _, key in ipairs({ "Pair of", "Two Pair", "Three of", "Straight", "Flush", "Full House" }) do
        if #w:texts(key) > 0 then return true end
      end
      return false
    end, 400, 1.5)
    if okStop then found = w; break end
  end
  assert(found, "holdem: no made hand on the turn found")
  local v = found.ns.TableFrame.view
  if v.historyButton and v.historyButton:IsVisible() and not v.history:IsShown() then found:click(v.historyButton) end
  run(found, 0.5)
  write("holdem", found, { found.ns.TableFrame.frame, v.history })
end)

-- The „История“ window open beside a table (mockup 10), for checking it: these scenes are made only
-- when named (luajit tools/shots/scenes.lua history_belot history_long history_santase history_chess).
-- `game` played by me and bots until stop(st).
local function withHistory(w, stop, limit, think, choose)
  local okStop = play(w, function(st, _, mine) return mine and stop(st) end, limit or 900, think or 1, choose)
  local v = w.ns.TableFrame.view
  if v.historyButton:IsVisible() and not v.history:IsShown() then w:click(v.historyButton) end
  run(w, 0.5)
  return okStop, v
end

-- Белот: the third deal under way (two closed above it), the trick on the table half played.
scene("history_belot", function()
  local w = boot{ seed = 11 }
  myTable(w, "belot")
  local okStop, v = withHistory(w, function(st) return st.phase == "play" and (st.round or 1) >= 3 and (st.trickNo or 1) >= 4 and #(st.trick or {}) == 2 end, 1200)
  assert(okStop, "history_belot: no third deal")
  -- the hand under way, and the one before it opened by a click on its header
  local H = w.ns.HandHistory
  local blocks = H.blocks(w.ns.client.session)
  if blocks[2] then H.toggle(blocks[2].hand, false); H.draw(v.history, w.ns.client.session) end
  write("history_belot", w, { w.ns.TableFrame.frame, v.history })
end, true)

-- The same window with the longest names a table can have (two-word names, a bot's long one).
scene("history_long", function()
  local w = boot{ seed = 11 }
  myTable(w, "belot")
  local okStop, v = withHistory(w, function(st) return st.phase == "play" and (st.round or 1) >= 2 and (st.trickNo or 1) >= 3 and #(st.trick or {}) == 3 end, 1200)
  assert(okStop, "history_long: no second deal")
  local H, s = w.ns.HandHistory, w.ns.client.session
  for _, hand in ipairs(H.tables[s.tid].hands) do
    hand.names = { ME, "Bot Barleybrewster", "Ivan Petrov", "Ivan Kolevski" }
  end
  H.draw(v.history, s)
  write("history_long", w, { w.ns.TableFrame.frame, v.history })
end, true)

-- Сантасе: the second hand under way, the first closed to its result.
scene("history_santase", function()
  local found
  for seed = 1, 40 do
    local w = boot{ seed = seed }
    myTable(w, "santase")
    -- a hand after the first with an event (a marriage, the nine, the close) and a few tricks
    local function events()
      local b = w.ns.HandHistory.tables[w.ns.client.session.tid]
      local top = b and b.hands[#b.hands]
      return top and #top.events or 0
    end
    local okStop, v = withHistory(w, function(st)
      return st.phase == "play" and (st.hand or 1) >= 2 and (st.ntr[1] + st.ntr[2]) >= 4 and events() > 0
    end, 900, 1, function(_, _, legal) -- I declare a marriage when I can
      for _, a in ipairs(legal) do if a.k == "marry" or a.k == "swap9" then return a end end
    end)
    if okStop then found = { w, v }; break end
  end
  assert(found, "history_santase: no second hand with an event")
  write("history_santase", found[1], { found[1].ns.TableFrame.frame, found[2].history })
end, true)

-- Шах: a game well under way, the history window open beside the board.
scene("history_chess", function()
  local w = boot{ seed = 5 }
  myTable(w, "chess")
  local okStop, v = withHistory(w, function(st) return #st.moves >= 24 end, 1200, 2)
  assert(okStop, "history_chess: no long game")
  write("history_chess", w, { w.ns.TableFrame.frame, v.history })
end, true)

scene("chess", function()
  local w = boot{ seed = 5 }
  myTable(w, "chess")
  local okStop = play(w, function(_, _, mine, acts) return mine and acts >= 14 end, 900, 4)
  assert(okStop, "chess: no mid-game moment found")
  run(w, 0.5)
  write("chess", w, { w.ns.TableFrame.frame })
end)

-- Tic-tac-toe: I win a round (win, else block, else centre, else a corner).
local LINES = { { 1, 2, 3 }, { 4, 5, 6 }, { 7, 8, 9 }, { 1, 4, 7 }, { 2, 5, 8 }, { 3, 6, 9 }, { 1, 5, 9 }, { 3, 5, 7 } }
local function tttChoice(st, s)
  local b, me = st.board, s.mySeat
  local function complete(who)
    for _, l in ipairs(LINES) do
      local n, free = 0, nil
      for _, c in ipairs(l) do
        if b[c] == who then n = n + 1 elseif b[c] == 0 then free = c end
      end
      if n == 2 and free then return free end
    end
  end
  local c = complete(me) or complete(3 - me)
  if not c and b[5] == 0 then c = 5 end
  if not c then for _, k in ipairs({ 1, 3, 7, 9, 2, 4, 6, 8 }) do if b[k] == 0 then c = k; break end end end
  return c and { k = "mark", c = c }
end

scene("ttt", function()
  local w = boot{ seed = 2 }
  myTable(w, "ttt")
  local okStop = play(w, function(st, s)
    return st.line ~= nil and st.winner == s.mySeat or (st.line ~= nil and st.phase == "round" and st.board[st.line[1]] == s.mySeat)
  end, 300, 1, function(st, s) return tttChoice(st, s) end)
  assert(okStop, "ttt: no winning line")
  w:render(0.1)
  write("ttt", w, { w.ns.TableFrame.frame })
end)

scene("deathroll", function()
  local w = boot{ seed = 4 }
  myTable(w, "deathroll", { start = 1000 }, 2)
  -- My turns: the view's „Roll“ (a real /roll; the server's chat line answers it).
  local okStop = play(w, function(st, _, mine)
    return mine and #(st.rolls or {}) >= 6
  end, 300, 1.5, function()
    local V = w.ns.TableFrame.built.deathroll
    if V.rollButton:IsVisible() and V.rollButton:IsEnabled() then w:click(V.rollButton) end
    return true
  end)
  assert(okStop, "deathroll: no ladder")
  run(w, 0.5)
  write("deathroll", w, { w.ns.TableFrame.frame })
end)

---------------------------------------------------------------------------
-- The guild's ledger: results and debts of games among guild members and me,
-- as their clients announce them to the guild (live LEV messages), so the
-- leaderboard and the ledger have real rows. Bot games write no ledger entry
-- (by design), so these come from fake guild members.

local MEMBERS = {
  { "Elowen", "DRUID" }, { "Thorgar", "WARRIOR" }, { "Mirabel", "PRIEST" }, { "Kazrik", "ROGUE" },
  { "Odric", "PALADIN" }, { "Sefa", "SHAMAN" }, { "Varek", "WARLOCK" }, { "Lysa", "HUNTER" },
}
local MEMBER_NAMES = {}
for i, m in ipairs(MEMBERS) do MEMBER_NAMES[i] = m[1] end

-- The members say HI (online, their class known): the hall's „In the tavern now“ lists them.
members = function(w, list)
  for _, m in ipairs(list or MEMBERS) do
    w:member(m[1])
    w:deliver("GUILD", m[1], { v = 1, t = "HI", ver = "0.1.0", cls = m[2], id = "Player-1-" .. m[1] })
  end
  w:advance(0); w:advance(0)
end

-- `big`: the debts are large amounts (up to 9,999,999 gold).
ledgerHistory = function(w, big)
  members(w)
  local seq, games = {}, 0
  local now = w.G.GetServerTime()
  local function send(author, k, fields, ago)
    seq[author] = (seq[author] or 0) + 1
    local e = { i = author .. ":" .. seq[author], k = k, at = now - math.floor(ago) }
    for key, value in pairs(fields) do e[key] = value end
    w:deliver("GUILD", author, { v = 1, t = "LEV", ev = { e } })
  end
  local GAMES = { "belot", "santase", "tabla", "chess", "ttt", "holdem", "deathroll", "belot", "santase", "chess" }
  -- Who is good at what: the leaderboard gets a shape.
  local skill = { [ME] = 0.62, Elowen = 0.7, Thorgar = 0.45, Mirabel = 0.58, Kazrik = 0.52, Odric = 0.38, Sefa = 0.5, Varek = 0.42, Lysa = 0.55 }
  local everyone = { ME }
  for _, n in ipairs(MEMBER_NAMES) do everyone[#everyone + 1] = n end
  for k = 1, 64 do
    local g = GAMES[(k * 7) % #GAMES + 1]
    local a = everyone[math.random(#everyone)]
    local b
    repeat b = everyone[math.random(#everyone)] until b ~= a
    local pa = (skill[a] or 0.5) / ((skill[a] or 0.5) + (skill[b] or 0.5))
    local win = math.random() < pa and 1 or 2
    local host = (a ~= ME) and a or b
    games = games + 1
    local ago = (64 - k) * 2.4 * 3600 + math.random(0, 3000)
    send(host, "R", { gid = host .. "#1/" .. games, g = g, n = { a, b }, w = { win }, l = { 3 - win } }, ago)
    -- One game in four was for gold: the loser owes the winner on their own word.
    if k % 4 == 0 then
      local loser, winner = win == 1 and b or a, win == 1 and a or b
      local c = ({ 50000, 120000, 25000, 300000, 80000, 15000, 42000 })[(k / 4) % 7 + 1]
      if big then c = ({ 99999999999, 1234567890, 98765432100, 300000, 45678912345, 15000, 999999900 })[(k / 4) % 7 + 1] end
      if loser ~= ME then
        send(loser, "D", { gid = host .. "#1/" .. games, g = g, f = loser, t = winner, c = c, why = "lost" }, ago - 60)
        -- Some debts are paid back by hand later.
        if k % 3 == 0 and winner ~= ME then send(winner, "P", { f = loser, c = c, how = "hand" }, ago - 7200) end
      end
    end
  end
  if big then -- the largest debt there can be, to me
    send(MEMBER_NAMES[1], "D", { gid = MEMBER_NAMES[1] .. "#1/99", g = "belot", f = MEMBER_NAMES[1], t = ME, c = 99999999999, why = "lost" }, 30)
  end
  run(w, 3)
end

scene("leaderboard", function()
  local w = boot{ seed = 21 }
  w:advance(w.ns.Const.LEDGER_ADOPT_WAIT + 1)
  ledgerHistory(w)
  w.ns.MainWindow.show("board")
  run(w, 3)
  write("leaderboard", w, { w.ns.MainWindow.frame })
end)

scene("ledger", function()
  local w = boot{ seed = 21 }
  w:advance(w.ns.Const.LEDGER_ADOPT_WAIT + 1)
  ledgerHistory(w)
  w.ns.MainWindow.show("ledger")
  run(w, 3)
  write("ledger", w, { w.ns.MainWindow.frame })
end)

-- „Нова маса“ on Белот with a gold stake and the game drop-down open (made only when named).
scene("newtable", function()
  local w = boot()
  w.ns.MainWindow.show()
  local D = w.ns.NewTableDialog
  D.open("belot")
  w:click(D.stake.options[2].frame)
  D.goldBox:SetText("25"); D.silverBox:SetText("50")
  w:click(D.picker)
  run(w, 1)
  write("newtable", w, { w.ns.MainWindow.frame })
end, true)

scene("newtable_gold", function()
  local w = boot()
  w.ns.MainWindow.show()
  local D = w.ns.NewTableDialog
  D.open("belot")
  w:click(D.stake.options[2].frame)
  D.goldBox:SetText("25"); D.silverBox:SetText("50")
  run(w, 1)
  write("newtable_gold", w, { w.ns.MainWindow.frame })
end, true)

scene("historytab", function()
  local w = boot{ seed = 21 }
  w:advance(w.ns.Const.LEDGER_ADOPT_WAIT + 1)
  ledgerHistory(w)
  w.ns.MainWindow.show("history")
  run(w, 3)
  write("historytab", w, { w.ns.MainWindow.frame })
end, true)

---------------------------------------------------------------------------
-- Short names (ui/NameTag.lua), for checking them: made only when named
-- (luajit tools/shots/scenes.lua names_hall names_belot names_deathroll names_ledger).
-- Two-word names, two Ivans and the bots' long names at one table.

local LONG = { { "Ivan Petrovski", "MAGE" }, { "Ivan Kolevski", "WARRIOR" }, { "Konstantin Velikopreslavski", "PRIEST" },
  { "Aleksandrina Dimitrova", "DRUID" }, { "Elowen Silverleaf", "HUNTER" } }

scene("names_hall", function()
  local w = boot{ seed = 9 }
  w:advance(w.ns.Const.LEDGER_ADOPT_WAIT + 1)
  members(w, LONG)
  local bots = botsOn(w)
  local tid = "Ivan Petrovski#1"
  w:deliver("GUILD", "Ivan Petrovski", { v = 1, t = "TBL", tid = tid, g = "belot", h = "Ivan Petrovski", e = 1, ac = "guild", tn = 45,
    st = "live", s = { "Ivan Petrovski", "Ivan Kolevski", "Konstantin Velikopreslavski", "Aleksandrina Dimitrova" }, w = 0 })
  local t2 = "Elowen Silverleaf#1"
  w:deliver("GUILD", "Elowen Silverleaf", { v = 1, t = "TBL", tid = t2, g = "santase", h = "Elowen Silverleaf", e = 1, ac = "guild",
    tn = 45, st = "open", s = { "Elowen Silverleaf", false }, w = 0 })
  for _, m in ipairs(LONG) do
    local at = m[1] == "Elowen Silverleaf" and t2 or tid
    w:deliver("GUILD", m[1], { v = 1, t = "HI", ver = "0.1.0", cls = m[2], id = "Player-1-" .. m[1], at = at })
  end
  local b1 = bots:hostTable("deathroll"); w:advance(0); w:advance(0)
  local b = bots:idle(); w:advance(0); b:sit(b1, 2); w:advance(0); w:advance(0)
  run(w, 4)
  w.ns.MainWindow.show("hall")
  run(w, 1)
  write("names_hall", w, { w.ns.MainWindow.frame })
end, true)

-- My Белот table with long names on its seats (drawn as they are, the bots playing on).
scene("names_belot", function()
  local w = boot{ seed = 11 }
  myTable(w, "belot")
  local okStop, v = withHistory(w, function(st) return st.phase == "play" and (st.round or 1) >= 2 and (st.trickNo or 1) >= 3 and #(st.trick or {}) == 3 end, 1200)
  assert(okStop, "names_belot: no second deal")
  local s, H = w.ns.client.session, w.ns.HandHistory
  local names = { ME, "Bot Barleybrewster", "Ivan Petrovski", "Ivan Kolevski" }
  for i = 2, 4 do s.seats[i] = names[i] end
  for _, hand in ipairs(H.tables[s.tid].hands) do hand.names = names end
  w.ns.TableFrame.render()
  H.draw(v.history, s)
  write("names_belot", w, { w.ns.TableFrame.frame, v.history })
end, true)

-- A Death Roll of four: two Ivans and a long name beside me; seven cells on the ladder.
scene("names_deathroll", function()
  local w = boot{ seed = 4 }
  myTable(w, "deathroll", { start = 1000 }, 3)
  local okStop = play(w, function(st) return #(st.rolls or {}) >= 6 or st.phase == "over" end, 400, 1.5, function()
    local V = w.ns.TableFrame.built.deathroll
    if V.rollButton:IsVisible() and V.rollButton:IsEnabled() then w:click(V.rollButton) end
    return true
  end)
  assert(okStop, "names_deathroll: no ladder")
  local s = w.ns.client.session
  s.seats[2], s.seats[3] = "Ivan Petrovski", "Ivan Kolevski"
  s.seats[4] = "Konstantinopolskiovich Velikov"
  w.ns.TableFrame.render()
  run(w, 0.25)
  write("names_deathroll", w, { w.ns.TableFrame.frame })
end, true)

-- The ledger with long two-word names: whole, shrunk, then wrapped.
scene("names_ledger", function()
  local w = boot{ seed = 21 }
  w:advance(w.ns.Const.LEDGER_ADOPT_WAIT + 1)
  local keep = {}
  for i, m in ipairs(MEMBERS) do keep[i] = m[1] end
  local long = { "Elowen Silverleaf-Moonwhisper", "Thorgar Ironbeard", "Mirabel Starfall", "Kazrik Shadowmantle",
    "Odric Lightbringer", "Sefa Windrunner", "Varek Doomhollow", "Lysa Brightwater" }
  for i, m in ipairs(MEMBERS) do m[1] = long[i]; MEMBER_NAMES[i] = long[i] end
  ledgerHistory(w)
  for i, m in ipairs(MEMBERS) do m[1] = keep[i]; MEMBER_NAMES[i] = keep[i] end
  w.ns.MainWindow.show("ledger")
  run(w, 3)
  write("names_ledger", w, { w.ns.MainWindow.frame })
  w.ns.MainWindow.show("board")
  run(w, 3)
  write("names_board", w, { w.ns.MainWindow.frame })
end, true)

scene("settings", function()
  local w = boot()
  w.ns.MainWindow.show("settings")
  run(w, 1)
  write("settings", w, { w.ns.MainWindow.frame })
end)

-- The deck preview: the pointer on a deck tile shows the whole deck (not in the README).
for _, d in ipairs({ { "deck_orc", "orc", "Horde" }, { "deck_faction", "faction", "Alliance" }, { "deck_gnome", "gnome", "Alliance" } }) do
  scene(d[1], function()
    local w = boot{ faction = d[3] }
    w.ns.MainWindow.show("settings")
    run(w, 1)
    w:hover(w.ns.Settings.view.deckTiles[d[2]].frame)
    write(d[1], w, { w.ns.MainWindow.frame })
  end, true)
end

scene("book", function()
  local w = boot()
  w.ns.HelpBook.open("belot")
  run(w, 1)
  write("book", w, { w.ns.HelpBook.frame })
end)

scene("hall_horde", function()
  local w = boot{ faction = "Horde", seed = 9 }
  hall(w)
  write("hall_horde", w, { w.ns.MainWindow.frame })
end)

scene("belot_horde", function()
  local w = boot{ faction = "Horde", seed = 11 }
  myTable(w, "belot")
  local okStop = play(w, function(st, _, mine)
    return mine and st.phase == "play" and (st.round or 1) >= 2 and #(st.trick or {}) == 3
  end, 600)
  assert(okStop, "belot: no mid-hand moment found")
  run(w, 0.5)
  write("belot_horde", w, { w.ns.TableFrame.frame })
end)

---------------------------------------------------------------------------
-- Every README picture also in the Horde look: <name>_horde is the same scene booted as the Horde
-- (the README's „Horde look“ fold). A scene that has its own Horde version keeps it.
do
  local base = {}
  for i, name in ipairs(ORDER) do base[i] = name end
  for _, name in ipairs(base) do
    if not name:find("_horde$") and not Scenes[name .. "_horde"] then
      local fn = Scenes[name]
      scene(name .. "_horde", function()
        VARIANT = "Horde"
        local okRun, err = xpcall(fn, debug.traceback)
        VARIANT = nil
        if not okRun then error(err, 0) end
      end)
    end
  end
end

---------------------------------------------------------------------------

-- tools/shots/lint.lua takes the scenes and their helpers as a library.
if SHOTS_LIB then
  return {
    Scenes = Scenes, boot = boot, run = run, runUntil = runUntil, play = play, myTable = myTable, botsOn = botsOn,
    members = members, ledgerHistory = ledgerHistory, hall = hall, withHistory = withHistory, tttChoice = tttChoice,
    write = write, MEMBERS = MEMBERS, MEMBER_NAMES = MEMBER_NAMES, CLASS_COLORS = CLASS_COLORS, OUT = OUT,
    setMe = function(name) ME = name end, me = function() return ME end, clientArt = CLIENT_ART,
  }
end

local wanted = { ... }
-- --art: the client files the addon may ask for (wow/Art.lua's file candidates), one per line, for client_art.py.
if wanted[1] == "--art" then
  local w = boot()
  local Art, seen = w.ns.Art, {}
  local function add(kind, id, sub)
    for _, c in ipairs(Art.candidates(kind, id, sub)) do
      if c.file and not seen[c.file] then seen[c.file] = true; print(c.file) end
    end
  end
  add("crest", "alliance"); add("crest", "horde")
  local races = { "human", "nightelf", "dwarf", "gnome", "draenei", "orc", "undead", "tauren", "troll", "bloodelf" }
  for _, race in ipairs(races) do
    add("leader", race)
    add("race", race, "male"); add("race", race, "female")
  end
  local classes = {}
  for cls in pairs(CLASS_COLORS) do classes[#classes + 1] = cls end
  table.sort(classes)
  for _, cls in ipairs(classes) do add("class", cls) end
  for _, coin in ipairs({ "gold", "silver", "copper" }) do add("coin", coin) end
  os.exit(0)
end
os.execute(package.config:sub(1, 1) == "\\" and 'if not exist "tools\\shots\\build" mkdir "tools\\shots\\build"' or "mkdir -p " .. OUT)
if #wanted == 0 then wanted = ORDER end
for _, name in ipairs(wanted) do
  local fn = Scenes[name]
  if not fn then error("no scene " .. name) end
  local okRun, err = xpcall(fn, debug.traceback)
  if not okRun then
    io.stderr:write("scene " .. name .. " failed: " .. tostring(err) .. "\n")
    os.exit(1)
  end
end
