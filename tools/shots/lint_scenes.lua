-- The layout checker's scenes (tools/shots/lint.lua): every window of the addon with long two-word
-- names, two players with one first word at one table, bots, a long guild name and big amounts.
-- A WoW character's name word is at most 12 letters, Latin on Forever: the first words are the
-- widest such words ("Mwaargrimmon" is mine, "Mormogwathum", "Wolfgarmmund"), which must never break.
-- Each scene is fn(P) -> the sandbox, P = {lang = "en"|"bg", faction = "Alliance"|"Horde"}.
-- S: tools/shots/scenes.lua as a library (boot, play, myTable, ...).
return function(S)
  local ME = "Mwaargrimmon Ashmantle" -- my own plate is the one on turn: a wide 12-letter first word there too
  local LONG = { "Mormogwathum Ironfoot", "Wolfgarmmund Deepforge", "Ivan Petrovski", "Ivan Kolevski" }
  local CYR = "Mirabelle Stormwhisper" -- (the name was Cyrillic before: names are Latin on Forever)
  local BOT = "Bot Barleybrew" -- the addon's own bot names are its STARTERS (core/Bots.lua)
  local GUILD = { en = "Brotherhood of Ironforge", bg = "Братството на Сребърната" } -- 24 letters, WoW's longest
  local BAGS = 99999999999 -- 9,999,999g 99s 99c
  local MEMBERS = {
    { "Mormogwathum Ironfoot", "WARRIOR" }, { "Wolfgarmmund Deepforge", "PALADIN" }, { "Ivan Petrovski", "MAGE" },
    { "Ivan Kolevski", "ROGUE" }, { "Elowen Moonwhisperwind", "DRUID" }, { "Kazrik Shadowmantle", "WARLOCK" },
    { "Odric Lightbringer", "PRIEST" }, { CYR, "HUNTER" },
  }

  local function boot(P, seed)
    S.setMe(ME)
    local w = S.boot{ seed = seed or 9, faction = P.faction, lang = P.lang, guild = GUILD[P.lang], money = BAGS }
    -- W.fitWrap notes the text it broke by letters (the checker's "broken" check finds it still shown)
    local W = w.ns.W
    local fitWrap = W.fitWrap
    W.fitWrap = function(fs, text, ...)
      local h = fitWrap(fs, text, ...)
      fs.lintBroken = fs:GetText() ~= text and fs:GetText() or nil
      fs.lintWhole = text
      return h
    end
    return w
  end

  -- The guild's members (long names) and their ledger with big debts; one debt of mine to pay.
  local function guild(w)
    w:advance(w.ns.Const.LEDGER_ADOPT_WAIT + 1)
    local keep = {}
    for i, m in ipairs(S.MEMBERS) do keep[i] = { m[1], m[2] }; m[1], m[2] = MEMBERS[i][1], MEMBERS[i][2]; S.MEMBER_NAMES[i] = m[1] end
    S.ledgerHistory(w, true)
    for i, m in ipairs(S.MEMBERS) do m[1], m[2] = keep[i][1], keep[i][2]; S.MEMBER_NAMES[i] = m[1] end
    local net = w.ns.client.ledgerNet
    net:make("D", { gid = "Kazrik Shadowmantle#1/90", g = "holdem", f = ME, t = LONG[1], c = 98765432199, why = "lost" })
    net:make("D", { gid = "Kazrik Shadowmantle#1/91", g = "belot", f = ME, t = CYR, c = 12345678901, why = "lost" })
    S.run(w, 2)
  end

  -- My table's other seats get long names (one bot kept where the table has four seats or more);
  -- the history window's hands too; drawn again.
  local function rename(w, botToo)
    local s, v, H = w.ns.client.session, w.ns.TableFrame.view, w.ns.HandHistory
    -- with a bot: the bot and the two widest names; without: the widest and the two Ivans
    local pool, k = botToo and { BOT, LONG[1], LONG[2], CYR, LONG[3] } or { LONG[1], LONG[3], LONG[4], LONG[2], CYR }, 0
    for i = 1, #s.seats do
      if i ~= s.mySeat and s.seats[i] then
        k = k + 1
        s.seats[i] = pool[k]
      end
    end
    local b = H.tables[s.tid]
    for _, hand in ipairs(b and b.hands or {}) do hand.names = { unpack(s.seats) } end
    if b then b.ver = (b.ver or 0) + 1 end
    w.ns.TableFrame.render()
    if v.history and v.history:IsShown() then H.draw(v.history, s) end
    S.run(w, 0.25)
  end

  local function openHistory(w)
    local v = w.ns.TableFrame.view
    if v.historyButton and v.historyButton:IsVisible() and not v.history:IsShown() then w:click(v.historyButton) end
    S.run(w, 0.25)
  end

  local list = {}
  local function scene(name, fn) list[#list + 1] = { name = name, fn = fn } end

  -------------------------------------------------------------------------
  -- The hall: long-named hosts and seats, two Ivans at one table, bot tables, a cash table
  -- of a big stake, my own Hold'em table, the guild's debts.
  scene("hall", function(P)
    local w = boot(P, 9)
    guild(w)
    local bots = S.botsOn(w)
    local function tbl(host, g, st, seats, extra)
      local m = { v = 1, t = "TBL", tid = host .. "#1", g = g, h = host, e = 1, ac = "guild", tn = 45, st = st, s = seats, w = 0 }
      for k2, v2 in pairs(extra or {}) do m[k2] = v2 end
      w:deliver("GUILD", host, m)
    end
    tbl(LONG[3], "belot", "live", { LONG[3], LONG[1], LONG[4], LONG[2] }) -- the widest names on the side chairs
    tbl(CYR, "santase", "open", { CYR, false })
    tbl("Kazrik Shadowmantle", "holdem", "open", { "Kazrik Shadowmantle", "Odric Lightbringer", false, false, false, false },
      { sk = 20000, o = { betting = "nl", blinds = 200, rebuy = "top" } })
    tbl("Elowen Moonwhisperwind", "chess", "live", { "Elowen Moonwhisperwind", LONG[2] }, { sk = 98765400000 })
    for _, m in ipairs(MEMBERS) do
      local at = (m[1] == LONG[3] or m[1] == LONG[4] or m[1] == LONG[1] or m[1] == LONG[2]) and (LONG[3] .. "#1") or nil
      w:deliver("GUILD", m[1], { v = 1, t = "HI", ver = "0.1.0", cls = m[2], id = "Player-1-" .. m[1], at = at })
    end
    local b1 = bots:hostTable("deathroll"); w:advance(0); w:advance(0)
    local b = bots:idle(); w:advance(0); b:sit(b1, 2); w:advance(0); w:advance(0)
    bots:hostTable("ttt"); w:advance(0); w:advance(0)
    S.run(w, 4)
    S.myTable(w, "holdem", nil, 3)
    w.ns.TableFrame.frame:Hide()
    S.run(w, 2)
    w.ns.MainWindow.show("hall")
    S.run(w, 1)
    w.ns.TableFrame.frame:Hide()
    w:advance(0)
    return w
  end)

  -- More tables than the floor holds: the hall's list, long hosts and big stakes.
  scene("hall_list", function(P)
    local w = boot(P, 9)
    guild(w)
    local games = { "belot", "santase", "chess", "tabla", "ttt", "deathroll", "santase", "belot", "chess", "tabla" }
    for i, m in ipairs(MEMBERS) do
      local g = games[i]
      local seats = { m[1] }
      for k = 2, (g == "belot" and 4 or g == "deathroll" and 5 or 2) do seats[k] = false end
      w:deliver("GUILD", m[1], { v = 1, t = "TBL", tid = m[1] .. "#1", g = g, h = m[1], e = 1, ac = "guild", tn = 45, st = "open",
        s = seats, w = 0, sk = i % 2 == 0 and 99999990000 or nil, o = g == "deathroll" and { start = 1000 } or nil })
      w:deliver("GUILD", m[1], { v = 1, t = "HI", ver = "0.1.0", cls = m[2], id = "Player-1-" .. m[1], at = m[1] .. "#1" })
    end
    local bots = S.botsOn(w)
    bots:hostTable("ttt"); w:advance(0); w:advance(0)
    bots:hostTable("deathroll"); w:advance(0); w:advance(0)
    S.run(w, 2)
    w.ns.MainWindow.show("hall")
    S.run(w, 1)
    assert(w.ns.Hall.mode == "list", "hall_list: the hall is not a list")
    return w
  end)

  -- My Белот table, waiting: the „Покани“ picker open over it with the guild's long names.
  scene("picker", function(P)
    local w = boot(P, 9)
    guild(w)
    w.ns.client:openTable{ game = "belot", access = "guild", turn = 45 }
    w:advance(0)
    local v = w.ns.TableFrame.view
    w:click(v.inviteButton)
    S.run(w, 0.5)
    assert(v.picker:IsShown(), "picker: not open")
    return w
  end)

  -- A live Белот: „Стани“ asks first (my partner loses with me).
  scene("stand_confirm", function(P)
    local w = boot(P, 11)
    S.myTable(w, "belot")
    S.play(w, function(st, _, mine) return mine and st.phase == "play" end, 600)
    rename(w, true)
    w:click(w.ns.TableFrame.view.standButton)
    S.run(w, 0.25)
    assert(w.ns.TableFrame.view.confirm:IsShown(), "stand_confirm: no question")
    return w
  end)

  -------------------------------------------------------------------------
  -- The game tables, mid-game, long names on the seats, the history window open where there is one.
  local function game(name, g, seed, stop, opts)
    opts = opts or {}
    scene(name, function(P)
      local w = boot(P, seed)
      S.myTable(w, g, opts.opt, opts.n)
      local okStop = S.play(w, stop, opts.limit or 900, opts.think or 1, opts.choose)
      assert(okStop, name .. ": no moment found")
      openHistory(w)
      rename(w, opts.bot)
      if opts.after then opts.after(w) end
      return w
    end)
  end
  game("belot", "belot", 11, function(st, _, mine)
    return mine and st.phase == "play" and (st.round or 1) >= 2 and (st.trickNo or 1) >= 3 and #(st.trick or {}) == 2
  end, { bot = true, limit = 1200 })
  -- Белот's longest lines: the fairness line under the felt (a lapse and a claim, long names) and the
  -- news line at the bottom (the longest start refusal), the frame's narrowest room between the buttons.
  game("belot_lines", "belot", 11, function(st, _, mine)
    return mine and st.phase == "play" and (st.trickNo or 1) >= 2
  end, { limit = 1200, after = function(w)
    local Deal = w.ns.Deal
    Deal.status = function() return "fair.lapse", LONG[1], 3 end
    Deal.claim = function() return LONG[2] end
    w.ns.TableFrame.render()
    w.ns.TableFrame.say(w.ns.L("start.group"))
    S.run(w, 0.25)
  end })
  game("santase", "santase", 5, function(st, _, mine)
    return mine and st.phase == "play" and (st.hand or 1) >= 2 and #st.trick == 1
  end, { choose = function(_, _, legal) for _, a in ipairs(legal) do if a.k == "marry" then return a end end end })
  game("tabla", "tabla", 3, function(st, _, mine, acts) return mine and acts >= 9 and st.dice ~= nil and st.phase == "move" end)
  game("holdem", "holdem", 4, function(st, _, mine) return mine and #(st.board or {}) >= 4 end, {
    n = 4, bot = true, think = 1.5,
    after = function(w) -- big stacks and a big pot
      local s = w.ns.client.session
      for i, seat in pairs(s.state.seats or {}) do if type(seat) == "table" and seat.chips then seat.chips = 987654321 + i end end
      if s.state.pot then s.state.pot = 1234567890 end
      w.ns.TableFrame.render()
      S.run(w, 0.25)
    end,
  })
  game("chess", "chess", 5, function(st) return #st.moves >= 24 end, { bot = true, think = 2, limit = 1200 })
  game("ttt", "ttt", 2, function(st, s)
    return st.line ~= nil and st.winner == s.mySeat or (st.line ~= nil and st.phase == "round" and st.board[st.line[1]] == s.mySeat)
  end, { choose = function(st, s) return S.tttChoice(st, s) end, limit = 300 })
  game("deathroll", "deathroll", 4, function(st) return #(st.rolls or {}) >= 6 or st.phase == "over" end, {
    opt = { start = 100000 }, n = 3, bot = true, think = 1.5, limit = 400,
    choose = nil,
  })

  -- A cash Hold'em table of a big stake, a hand under way: the cash panel open.
  scene("holdem_cash", function(P)
    local w = boot(P, 4)
    guild(w)
    local client, E = w.ns.client, w.ns.Engines.holdem
    local names = { ME, LONG[1], LONG[3], LONG[4], CYR }
    local st = E.new{ seats = { true, true, true, true, true, false }, opt = { rebuy = "top", blinds = 200 }, staked = true,
      names = names }
    for seat = 1, 5 do assert(E.apply(st, seat, { k = "buy", n = 20000 })) end
    assert(E.apply(st, 0, { k = "hand" })); assert(E.apply(st, 0, { k = "deal", deck = E.DECK }))
    -- my own staked table, its hand drawn from the state above (a layout check, not a game)
    assert(client:openTable{ game = "holdem", access = "guild", turn = 45, stake = 20000,
      opt = { blinds = 200, rebuy = "top", betting = "nl" } })
    w:advance(0)
    local s = client.session
    s.seats = { ME, LONG[1], LONG[3], LONG[4], CYR, false }
    s.state, s.status, s.watchers = E.view(st, 1), "live", 3
    w.ns.TableFrame.render()
    local f = w.ns.TableFrame.built and w.ns.TableFrame.built.holdem
    if f and f.cash and f.cash.button and f.cash.button:IsVisible() then w:click(f.cash.button) end
    openHistory(w)
    S.run(w, 0.25)
    return w
  end)

  -------------------------------------------------------------------------
  -- The tavern window's tabs with the guild's long names and big debts.
  for _, tab in ipairs({ "ledger", "board", "history", "settings" }) do
    scene("tab_" .. tab, function(P)
      local w = boot(P, 21)
      guild(w)
      w.ns.MainWindow.show(tab)
      S.run(w, 2)
      return w
    end)
  end

  -- The deck preview over „Настройки“: the pointer on the gnomes (the longest king, Mekkatorque).
  scene("deck_preview", function(P)
    local w = boot(P, 21)
    w.ns.MainWindow.show("settings")
    S.run(w, 1)
    w:hover(w.ns.Settings.view.deckTiles.gnome.frame)
    return w
  end)

  scene("book", function(P)
    local w = boot(P, 1)
    w.ns.HelpBook.open("holdem")
    S.run(w, 1)
    return w
  end)

  -- The new-table dialog of every game, over the hall.
  for _, g in ipairs({ "belot", "santase", "tabla", "holdem", "chess", "ttt", "deathroll" }) do
    scene("newtable_" .. g, function(P)
      local w = boot(P, 1)
      w.ns.MainWindow.show("hall")
      w.ns.NewTableDialog.open(g)
      local D = w.ns.NewTableDialog
      if D.stake and D.stake.options and D.stake.options[2] then w:click(D.stake.options[2].frame) end
      S.run(w, 0.5)
      return w
    end)
  end

  -- „Плащане“: what I owe a long-named player, a big amount.
  scene("pay", function(P)
    local w = boot(P, 21)
    guild(w)
    w.ns.MainWindow.show("hall")
    w.ns.PayDialog.open(LONG[1])
    S.run(w, 0.5)
    return w
  end)

  -- The questions before sitting at a staked table: a cash Hold'em (the buy-in stepper), a Belot.
  for _, g in ipairs({ "holdem", "belot" }) do
    scene("stake_" .. g, function(P)
      local w = boot(P, 21)
      guild(w)
      local host = LONG[1]
      local seats = g == "holdem" and { host, false, false, false, false, false } or { host, false, false, false }
      w:member(host)
      w:deliver("GUILD", host, { v = 1, t = "TBL", tid = host .. "#1", g = g, h = host, e = 1, ac = "guild", tn = 45, st = "open",
        s = seats, w = 0, sk = 99999990000, o = g == "holdem" and { betting = "nl", blinds = 10, rebuy = "top" } or nil })
      w:advance(0)
      w.ns.MainWindow.show("hall")
      w.ns.StakePanels.ask(w.ns.client.lobby:get(host .. "#1"), 2)
      S.run(w, 0.5)
      return w
    end)
  end

  -- The invitation toast of a long-named host to a big-stake cash table; the settle toast; „Уредено?“.
  scene("toasts", function(P)
    local w = boot(P, 21)
    guild(w)
    w.ns.MainWindow.show("hall")
    local host = LONG[2]
    w:member(host)
    w:deliver("WHISPER", host, { v = 1, t = "INV", tid = host .. "#1", g = "holdem", h = host,
      s = { host, LONG[3], LONG[4], false, false, false }, sk = 99999990000 })
    w:advance(0)
    local me = w.ns.client.ledger.me
    w.ns.SettleToast.show(w.ns.client, { id = "x", from = LONG[1], to = me, c = 98765432199, how = "mail", at = 1 })
    w.ns.Accounts.askSettle(CYR, 12345678901)
    S.run(w, 0.5)
    return w
  end)

  -- The stake bill after a staked Морски шах match against a long-named player, won.
  scene("bill", function(P)
    local w = boot(P, 21)
    w:advance(w.ns.Const.LEDGER_ADOPT_WAIT + 1)
    local B = LONG[1]
    local tid = w.ns.client:openTable{ game = "ttt", access = "guild", turn = 45, stake = 99999990000 }
    assert(tid, "no staked table")
    w:advance(0)
    w:member(B)
    w:deliver("GUILD", B, { v = 1, t = "HI", ver = "0.1.0", cls = "PRIEST", id = "Player-1-" .. B })
    w.partyNames[B] = true
    w.group["Player-1-" .. B] = true
    w:deliver("WHISPER", B, { v = 1, t = "SIT", tid = tid, seat = 2, sk = 99999990000 })
    w:advance(0)
    local s, client = w.ns.client.session, w.ns.client
    assert(s.status == "live", "the match did not start")
    s.state.score = { 2, 0 }
    client:act({ k = "mark", c = 1 }); s:play(2, { k = "mark", c = 4 })
    client:act({ k = "mark", c = 2 }); s:play(2, { k = "mark", c = 5 })
    client:act({ k = "mark", c = 3 })
    w:advance(0)
    w.ns.TableFrame.render()
    S.run(w, 0.5)
    return w
  end)

  scene("intro", function(P)
    local w = boot(P, 1)
    w.ns.Intro.start(true)
    S.run(w, 0.25)
    return w
  end)

  return list
end
