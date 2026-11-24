local Wow = require("wow")
local Chess = require("chess")

local A, BOT = "Иван Петров", "Bot Ivanov"
local sq = Chess.sq

-- In a guild, booted with the ui/ files, own name resolved, PLAYER_LOGIN fired; bots on and heard.
local function guildWow()
  local w = Wow.new{ ui = true }
  w.inGuild = true
  w.roster = { { name = A .. "-Forever", online = true, guid = Wow.GUID } }
  w.G.RAID_CLASS_COLORS.PRIEST = { r = 1, g = 1, b = 1 }
  local K = w.G.SOUNDKIT
  K.IG_ABILITY_ICON_DROP, K.IG_BACKPACK_CLOSE, K.IG_PLAYER_INVITE, K.IG_QUEST_LIST_COMPLETE = 701, 702, 703, 704
  w:boot()
  w:firstRunDone()
  w:fire("GUILD_ROSTER_UPDATE")
  w:fire("PLAYER_LOGIN")
  w:slash("bots")
  w:advance(0); w:advance(0)
  return w
end
local SOUND = { move = 701, capture = 702, check = 703, over = 704 }
local function count(w, id)
  local n = 0
  for _, s in ipairs(w.sounds) do if s[1] == id then n = n + 1 end end
  return n
end

-- A chess table of mine with the bot in seat 2, the table frame drawn; the bot has not moved yet.
-- `fen` (nil: the start) is set by hand with me as white; every action I send is recorded in `acts`.
local function setup(fen, minutes)
  local w = guildWow()
  local client, T = w.ns.client, w.ns.TableFrame
  client:openTable{ game = "chess", access = "invite", turn = 45, opt = { clock = minutes == nil and 10 or minutes } }
  w:advance(0)
  w:click(T.view.inviteButton)
  for _, r in ipairs(T.view.picker.rows) do
    if r.frame:IsVisible() and r.name:GetText() == BOT then w:click(r.frame) end
  end
  w:advance(0)
  w:advance(3)
  local s = client.session
  assert(s and s.state, "no game")
  local acts, orig = {}, client.act
  client.act = function(c, a) acts[#acts + 1] = a; return orig(c, a) end
  local function set(st)
    s.state = st
    w.ns.Clock.mark(s, true)
    T.render()
  end
  set(Chess.at(fen or "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", { first = 1, opt = { clock = minutes == nil and 10 or minutes } }))
  return w, T, T.built.chess, s, acts, set
end

-- The cell of the square `name` (a1 ...) as drawn.
local function cell(f, name)
  for i, c in ipairs(f.model.cells) do
    if c.sq == sq(name) then return f.cells[i], c end
  end
end
local function click(w, f, name) w:click(cell(f, name).button) end
-- The squares showing `what` ("dot" | "ring") as names.
local function marked(f, what)
  local out = {}
  for i, c in ipairs(f.cells) do
    if c[what]:IsShown() then out[#out + 1] = ("abcdefgh"):sub((f.model.cells[i].sq - 1) % 8 + 1, (f.model.cells[i].sq - 1) % 8 + 1) .. math.floor((f.model.cells[i].sq - 1) / 8 + 1) end
  end
  table.sort(out)
  return out
end
local function plain(t) return (tostring(t):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

describe("ui: the chess view", function()
  it("the view lives inside the scaled table frame", function()
    local w, T, f = setup()
    eq({ T.frame:GetWidth(), T.frame:GetHeight() }, { T.views.chess.size[1], T.views.chess.size[2] })
    local before = #w.frames
    local function inside(fr)
      local p = fr
      while p do if p == T.frame then return true end; p = p:GetParent() end
      return false
    end
    -- the promotion picker and the resign dialog are built now; every frame made since lives in the table frame
    click(w, f, "e2"); click(w, f, "e4")
    w.ns.ChessPanels.confirmResign(f, function() end)
    w.ns.ChessPanels.promotion(f, f.cells[1], 1, function() end)
    for i = before + 1, #w.frames do ok(inside(w.frames[i]), "frame " .. i .. " is outside the table frame") end
    ok(#w.frames > before, "no frame was built")
    for _, fr in ipairs(w.frames) do
      local p = fr
      while p and p ~= f do p = p:GetParent() end
      if p == f then ok(inside(fr), "a board frame is outside the table frame") end
    end
  end)

  it("two clicks move a piece", function()
    local w, _, f, s, acts = setup()
    click(w, f, "e2")
    eq(marked(f, "dot"), { "e3", "e4" })
    ok(cell(f, "e2").edges[1]:IsShown(), "the selection is edged")
    click(w, f, "e4")
    eq(acts, { { k = "move", f = sq("e2"), t = sq("e4") } })
    eq(s.state.board[sq("e4")], 1)
    eq(marked(f, "dot"), {})
  end)

  it("a refused move leaves no dots behind", function()
    local w, _, f, s, acts = setup()
    w.ns.client.act = function(_, a) acts[#acts + 1] = a; return nil, "refused" end
    click(w, f, "e2")
    eq(marked(f, "dot"), { "e3", "e4" })
    click(w, f, "e4")
    eq(#acts, 1); eq(marked(f, "dot"), {}); eq(cell(f, "e2").edges[1]:IsShown(), false)
  end)

  it("the plates' clock is set again only when it changed", function()
    local w, T = setup()
    local p = T.view.plates[1]
    local sets = 0
    local setText = p.clock.SetText
    p.clock.SetText = function(fs, t) sets = sets + 1; return setText(fs, t) end
    T.tick(); T.tick(); eq(sets, 0)
    w:advance(31); T.tick(); eq(sets, 1)
  end)

  it("a click on the table's own button cancels the picker", function()
    local w, T = setup("4k3/P7/8/8/8/8/8/4K3 w - - 0 1")
    local f = T.built.chess
    click(w, f, "a7"); click(w, f, "a8")
    local c = f.side.promo.catcher
    eq(c:GetParent(), T.frame)
    ok(c:GetFrameLevel() > T.view.standButton:GetFrameLevel() and c:GetFrameLevel() > T.view.plates[1].frame:GetFrameLevel(), "above the table's buttons and plates")
  end)

  it("a capture shows a ring, a click elsewhere clears, another own piece reselects", function()
    local w, _, f, _, acts = setup("rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2")
    click(w, f, "e4")
    eq(marked(f, "dot"), { "e5" }); eq(marked(f, "ring"), { "d5" })
    click(w, f, "g1")
    eq(marked(f, "dot"), { "e2", "f3", "h3" }); eq(marked(f, "ring"), {})
    click(w, f, "a6")
    eq(marked(f, "dot"), {}); eq(cell(f, "g1").edges[1]:IsShown(), false)
    click(w, f, "g1"); click(w, f, "g1")
    eq(marked(f, "dot"), {}, "the same piece again clears")
    click(w, f, "d8"); eq(marked(f, "dot"), {}, "an enemy piece is not selected")
    eq(acts, {})
  end)

  it("nothing moves when it is not my turn", function()
    local w, _, f, _, acts, set = setup()
    local st = Chess.at("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b KQkq - 0 1", { first = 1, opt = { clock = 10 } })
    set(st)
    for _, c in ipairs(f.cells) do eq(c.button:IsEnabled(), false) end
    local c = cell(f, "e7")
    c.button.scripts.OnClick(c.button)
    cell(f, "e5").button.scripts.OnClick(cell(f, "e5").button)
    eq({ acts, marked(f, "dot") }, { {}, {} })
    eq(f.status:GetText(), "На ход е " .. BOT)
  end)

  it("a promotion asks for the piece", function()
    local w, _, f, _, acts = setup("4k3/P7/8/8/8/8/8/4K3 w - - 0 1")
    click(w, f, "a7"); click(w, f, "a8")
    local pick = f.side.promo
    ok(pick and pick.frame:IsVisible(), "the picker is open")
    eq(acts, {})
    -- the queen nearest the top: every button hangs from the picker's top, the queen highest
    local function top(b)
      local p = b.points[#b.points]
      eq({ p[1], p[2], p[3] }, { "TOPLEFT", pick.frame, "TOPLEFT" })
      return p[5]
    end
    for _, letter in ipairs({ "r", "b", "n" }) do ok(top(pick.buttons.q) > top(pick.buttons[letter]), "the queen is below " .. letter) end
    w:click(pick.buttons.n)
    eq(acts, { { k = "move", f = 49, t = 57, p = "n" } })
    ok(not pick.frame:IsVisible(), "the picker is closed")
    -- a click outside closes it and sends nothing
    local w2, _, f2, _, acts2 = setup("4k3/P7/8/8/8/8/8/4K3 w - - 0 1")
    click(w2, f2, "a7"); click(w2, f2, "a8")
    w2:click(f2.side.promo.catcher)
    ok(not f2.side.promo.frame:IsVisible(), "closed by a click outside"); eq(acts2, {})
  end)

  it("a new state clears the selection and the picker, and the board turns to my colour", function()
    local w, T, f, s, _, set = setup("4k3/P7/8/8/8/8/8/4K3 w - - 0 1")
    click(w, f, "a7"); click(w, f, "a8")
    ok(f.side.promo.frame:IsVisible(), "picker open")
    local st = s.state
    w.ns.Engines.chess.apply(st, 2, { k = "resign" }) -- the opponent's event; it is my turn still
    T.render()
    ok(not f.side.promo.frame:IsVisible(), "the picker is dropped")
    eq(marked(f, "dot"), {}); eq(f.sel, nil)
    ok(f.strip:IsVisible() and f.strip.text:GetText():find("се предаде", 1, true), "the end text")
    -- a new game with the colours swapped: black (seat 1) at the bottom, h8 at its left
    eq(f.model.cells[57].sq, 1)
    w:click(T.view.startButton); T.render()
    eq(s.state.white, 2)
    eq({ f.model.bottom, f.model.cells[57].sq, f.model.cells[1].sq }, { -1, 64, 8 })
  end)

  it("both clocks stand on the plates", function()
    local w, T, f, s = setup()
    local p = T.view.plates
    eq({ p[1].clock:GetText(), p[2].clock:GetText() }, { "10:00", "10:00" })
    ok(p[1].bar:IsShown() and not p[2].bar:IsShown(), "the turn bar is on the plate on turn")
    local full = p[1].bar:GetWidth()
    w:advance(31); T.tick()
    eq({ p[1].clock:GetText(), p[2].clock:GetText() }, { "9:29", "10:00" })
    ok(p[1].bar:GetWidth() < full and p[1].bar:GetWidth() > 0, "the bar shrinks")
    eq({ p[1].clock.textColor[1], p[1].clock.textColor[2] }, { w.ns.Theme.color.gold[1], w.ns.Theme.color.gold[2] })
    s.state.clock[1] = 250; w.ns.Clock.mark(s, true); T.render()
    eq(p[1].clock:GetText(), "0:25")
    eq({ p[1].clock.textColor[1], p[1].clock.textColor[2], p[1].clock.textColor[3] }, { w.ns.Theme.color.clockLow[1], w.ns.Theme.color.clockLow[2], w.ns.Theme.color.clockLow[3] })
    -- the plates stand in the side column: mine at the bottom
    ok(p[1].frame.points[1][5] < p[2].frame.points[1][5], "my plate is lower")
    eq(p[1].frame:GetWidth(), 220)
  end)

  it("a clock's text is made once a whole second, not every frame", function()
    local w, T = setup()
    local p, M = T.view.plates, w.ns.ChessModel
    local made, clockText = 0, M.clockText
    M.clockText = function(...) made = made + 1; return clockText(...) end
    for _ = 1, 3 do w:advance(0.2); T.tick() end -- 0.6 s: both clocks still show the same second
    local still = made
    w:advance(1); T.tick() -- the clock on turn shows the next second
    M.clockText = clockText
    eq({ still, made }, { 0, 1 })
    eq({ p[1].clock:GetText(), p[2].clock:GetText() }, { "9:59", "10:00" })
  end)

  it("without a limit both plates show the sign and no bar", function()
    local w, T = setup(nil, 0)
    local p = T.view.plates
    eq({ p[1].clock:GetText(), p[2].clock:GetText() }, { "∞", "∞" })
    eq({ p[1].bar:IsShown(), p[2].bar:IsShown() }, { false, false })
    w:advance(31); T.tick()
    eq({ p[1].clock:GetText(), p[2].clock:GetText() }, { "∞", "∞" })
  end)

  it("a view without seatClock keeps the plates as they were", function()
    local w = guildWow()
    local client, T = w.ns.client, w.ns.TableFrame
    client:openTable{ game = "ttt", access = "invite", turn = 45 }; w:advance(0)
    eq(T.views.ttt.seatClock, nil)
    ok(not T.view.plates[1].clock:IsShown(), "no clock without a deadline")
  end)

  it("the offer strip", function()
    local w, T, f, s = setup()
    ok(not f.strip:IsShown(), "no strip")
    ok(f.offer:IsShown(), "I may offer on my turn")
    eq(s.state.wait, { 0, 0 })
    s.state.turn, s.state.offer = 2, 2 -- the opponent's offer stands (by hand: the bot is on its seat)
    s.state.turn = 1
    T.render()
    ok(f.strip:IsVisible(), "the strip shows")
    eq(#w:texts("Приеми"), 1); eq(#w:texts("Откажи"), 1)
    ok(plain(f.strip.text:GetText()):find(BOT, 1, true), "names the offerer")
    ok(not f.offer:IsShown(), "no offer of mine while theirs stands")
    w:click(f.decline); T.render()
    eq(s.state.offer, nil); eq(s.state.wait[2], 3)
    ok(not f.strip:IsShown(), "gone after the answer")
    -- my own offer is not shown as a question to me
    s.state.offer = 1; T.render()
    ok(not f.accept:IsShown(), "no buttons for my own offer"); eq(f.status:GetText(), "Предложи реми. Чакаме отговор.")
    -- a watcher sees no buttons
    s.mySeat, s.state.offer = nil, 2; T.render()
    ok(not f.accept:IsShown() and not f.decline:IsShown() and not f.offer:IsShown() and not f.resign:IsShown(), "a watcher has none")
  end)

  it("resign asks first", function()
    local w, T, f, s, acts = setup()
    w:click(f.resign)
    local d = f.side.confirm
    ok(d.frame:IsVisible(), "the dialog is open")
    w:click(d.no)
    ok(not d.frame:IsVisible(), "closed"); eq(acts, {})
    w:click(f.resign); w:click(d.yes); T.render()
    eq(acts, { { k = "resign" } })
    eq(s.state.phase, "over"); eq(s.state.result.reason, "resign")
    eq(f.strip.text:GetText(), A .. " се предаде")
    ok(not f.resign:IsShown(), "no resign after the end")
    ok(not T.view.plates[1].bar:IsShown() and not T.view.plates[2].bar:IsShown(), "no turn bar after the end")
  end)

  it("the end banner", function()
    local w, T, f, s, _, set = setup()
    set(Chess.play(Chess.at("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", { first = 1, opt = { clock = 10 } }), "f2f3 e7e5 g2g4 d8h4"))
    ok(f.strip:IsVisible(), "the strip")
    eq(f.strip.text:GetText(), "Мат! " .. BOT .. " печели")
    ok(cell(f, "e1").check:IsShown() and not cell(f, "e8").check:IsShown(), "the king is red")
    eq(f.status:GetText(), "")
  end)

  it("the claim button", function()
    local w, T, f, s, acts, set = setup()
    set(Chess.at("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b KQkq - 0 1", { first = 1, opt = { clock = 10 } }))
    ok(not f.claim:IsShown(), "no claim while their time runs")
    w:advance(602); T.render()
    ok(w.ns.Clock.canClaim(s), "their time is up by my clock")
    ok(f.claim:IsShown(), "the claim is shown")
    local called
    local claim = w.ns.Clock.claim
    w.ns.Clock.claim = function(client) called = client; return claim(client) end
    w:click(f.claim)
    w.ns.Clock.claim = claim
    eq(called, w.ns.client)
    eq(s.state.claimed, 0, "the host took the claim")
  end)

  it("the claim button comes by itself: a host that withholds its flag sends no event", function()
    local w, T, f, s, _, set = setup()
    set(Chess.at("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b KQkq - 0 1", { first = 1, opt = { clock = 10 } }))
    w:advance(602)
    ok(w.ns.Clock.canClaim(s), "their time is up by my clock")
    ok(not f.claim:IsShown(), "nothing has redrawn the table yet")
    w:render(); w:advance(0) -- one frame: the plates' clock sees the claim open and asks for a redraw
    ok(f.claim:IsShown(), "the claim is shown")
  end)

  it("leaving the table with the promotion picker open closes it", function()
    local w, T, f = setup("4k3/P7/8/8/8/8/8/4K3 w - - 0 1")
    click(w, f, "a7"); click(w, f, "a8")
    local pick = f.side.promo
    ok(pick.catcher:IsShown(), "the picker is open")
    w:click(T.view.standButton); w:advance(0)
    if T.view.confirm:IsShown() then w:click(T.view.confirm.yes); w:advance(0) end
    eq(w.ns.client.session, nil)
    ok(not pick.catcher:IsShown() and not pick.frame:IsShown(), "the picker is closed")
  end)

  it("the sounds", function()
    local w, T, f, s = setup()
    T.render()
    local E = w.ns.Engines.chess
    local function ply(word, a)
      ok(E.apply(s.state, s.state.turn, a or { k = "move", f = sq(word:sub(1, 2)), t = sq(word:sub(3, 4)) }))
      T.render()
    end
    local base = { count(w, SOUND.move), count(w, SOUND.capture), count(w, SOUND.check), count(w, SOUND.over) }
    local function heard() -- since the table was set up (the bot's own first move was heard on the way)
      return { count(w, SOUND.move) - base[1], count(w, SOUND.capture) - base[2], count(w, SOUND.check) - base[3], count(w, SOUND.over) - base[4] }
    end
    eq(heard(), { 0, 0, 0, 0 }, "setting the position by hand plays nothing")
    ply("e2e4"); eq(heard(), { 1, 0, 0, 0 })
    T.render(); eq(heard(), { 1, 0, 0, 0 }, "drawing the same state again plays nothing")
    ply("d7d5"); eq(heard(), { 2, 0, 0, 0 })
    ply("e4d5"); eq(heard(), { 2, 1, 0, 0 }, "the first capture of the table is heard")
    ply("d8d5"); eq(heard(), { 2, 2, 0, 0 })
    ply("b1c3"); eq(heard(), { 3, 2, 0, 0 })
    ply("d5e5"); eq(heard(), { 3, 2, 1, 0 }, "a check beats a quiet move")
    ply("f1e2"); eq(heard(), { 4, 2, 1, 0 })
    ply(nil, { k = "resign" }); eq(heard(), { 4, 2, 1, 1 })
    T.render(); eq(heard(), { 4, 2, 1, 1 })
  end)

  it("the sounds of a mate: the end covers the check", function()
    local w, T, f, s = setup()
    local E = w.ns.Engines.chess
    local base = { count(w, SOUND.move), count(w, SOUND.check), count(w, SOUND.over) }
    for _, word in ipairs({ "f2f3", "e7e5", "g2g4", "d8h4" }) do
      ok(E.apply(s.state, s.state.turn, { k = "move", f = sq(word:sub(1, 2)), t = sq(word:sub(3, 4)) })); T.render()
    end
    eq({ count(w, SOUND.move) - base[1], count(w, SOUND.check) - base[2], count(w, SOUND.over) - base[3] }, { 3, 0, 1 })
  end)

  it("the table's own sounds are not touched and the theme names the chess textures", function()
    local w = guildWow()
    local Theme = w.ns.Theme
    -- the 31 names of the textures (tools/gen_chess_textures.py) with their sizes
    local want = { dot = { 64, 64 }, ring = { 64, 64 }, check = { 64, 64 },
      sq_alliance_l = { 64, 64 }, sq_alliance_d = { 64, 64 }, sq_horde_l = { 64, 64 }, sq_horde_d = { 64, 64 } }
    for _, name in ipairs({ "alliance_wp", "alliance_wn", "alliance_wb", "alliance_wr", "alliance_wq", "alliance_wk",
        "alliance_bp", "alliance_bn", "alliance_bb", "alliance_br", "alliance_bq", "alliance_bk",
        "horde_wp", "horde_wn", "horde_wb", "horde_wr", "horde_wq", "horde_wk",
        "horde_bp", "horde_bn", "horde_bb", "horde_br", "horde_bq", "horde_bk" }) do
      want[name] = { 128, 128 }
    end
    eq(Theme.chessTexSize, want)
    for name in pairs(want) do eq(Theme.chessTex(name), Theme.chessTex("dot"):sub(1, -4) .. name) end
    eq(Theme.chessTex("dot"), "Interface\\AddOns\\TavernGames\\media\\chess\\dot")
    for _, skin in ipairs({ "alliance", "horde" }) do
      local c = Theme.SKINS[skin].color
      ok(c.sqLast and c.sqSel and c.sqDot and c.coord, skin)
    end
    eq({ Theme.SKINS.alliance.color.sqLast[1] * 255, Theme.SKINS.horde.color.sqLast[2] * 255 }, { 0xff, 0x8c })
    eq(Theme.color.clockLow, { 1, 0x5a / 255, 0x4a / 255 })
  end)
end)
