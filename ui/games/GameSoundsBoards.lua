local _, ns = ...

-- The board tables' sounds (ui/games/GameSounds.lua reads them), each step against the last one of the
-- same game (Табла: st.game; chess, Death Roll: a move or roll count that only grows within one game;
-- Морски шах: st.round):
--   Табла      the dice thrown (a roll counted, or the opening roll) "dice_roll"; a move: a checker hit to
--              the bar "checker_hit", else one borne off "checker_off", else "checker_move".
--   chess      the latest move: a promotion "chess_promote", check "chess_check" (not a mate: that is the
--              end jingle's), castling "chess_castle", a capture "chess_capture", else "chess_move"; my
--              last ten seconds on the clock "tick", once a second.
--   Морски шах a winning line "ttt_line", else the mark placed "ttt_x" / "ttt_o".
--   Death Roll the latest roll: a 1 (the game lost) "roll_one", else "die_roll".
-- The piece's sound comes before the dice of the same step (it was the later).
local GS = ns.GameSounds

GS.games.tabla = {
  read = function(st)
    local pos = {}
    for seat = 1, 2 do
      pos[#pos + 1] = table.concat((st.pts or {})[seat] or {}, ",")
      pos[#pos + 1] = table.concat((st.pin or {})[seat] or {}, ",")
    end
    local bar, off, rolls = st.bar or {}, st.off or {}, st.rolls or {}
    return {
      game = st.game, phase = st.phase, rolls = (rolls[1] or 0) + (rolls[2] or 0),
      dice = st.dice and (tostring(st.dice[1]) .. tostring(st.dice[2])) or nil,
      pos = table.concat(pos, ";"), bar1 = bar[1] or 0, bar2 = bar[2] or 0, off1 = off[1] or 0, off2 = off[2] or 0,
    }
  end,
  sounds = function(cur, was, out)
    if cur.game ~= was.game or was.phase == "match" then return end -- another game: a fresh board
    if cur.bar1 > was.bar1 or cur.bar2 > was.bar2 then out[#out + 1] = "checker_hit"
    elseif cur.off1 > was.off1 or cur.off2 > was.off2 then out[#out + 1] = "checker_off"
    elseif cur.pos ~= was.pos then out[#out + 1] = "checker_move" end
    local opening = was.phase == "open" and cur.dice and (cur.phase ~= "open" or cur.dice ~= was.dice)
    if cur.rolls > was.rolls or opening then out[#out + 1] = "dice_roll" end
  end,
}

-- The sound of chess move `san` (its check sign kept; a mate's is the end jingle's).
local function chessKind(san)
  if san:find("=", 1, true) then return "chess_promote" end
  if san:find("+", 1, true) then return "chess_check" end
  if san:find("O-O", 1, true) then return "chess_castle" end
  if san:find("x", 1, true) then return "chess_capture" end
  return "chess_move"
end

GS.games.chess = {
  read = function(st)
    local moves = st.moves or {}
    local last = moves[#moves]
    return { n = #moves, san = last and last.san or nil, white = st.white }
  end,
  sounds = function(cur, was, out)
    if cur.n <= was.n or cur.white ~= was.white or not cur.san then return end
    out[#out + 1] = chessKind((cur.san:gsub("#", "")))
  end,
  clock = true,
}

GS.games.ttt = {
  read = function(st)
    return { round = st.round, board = table.concat(st.board or {}, ""), line = st.line ~= nil, turn = st.turn }
  end,
  sounds = function(cur, was, out)
    if cur.round ~= was.round or cur.board == was.board then return end
    if cur.line and not was.line then out[#out + 1] = "ttt_line" end
    -- the mark placed last: of the seat that is not on turn now (X is seat 1, O seat 2), or the new one
    local mark = cur.turn and tostring(3 - cur.turn)
    if not mark then
      for i = 1, #cur.board do
        if was.board:sub(i, i) == "0" and cur.board:sub(i, i) ~= "0" then mark = cur.board:sub(i, i) end
      end
    end
    out[#out + 1] = mark == "1" and "ttt_x" or "ttt_o"
  end,
}

GS.games.deathroll = {
  read = function(st)
    local rolls = st.rolls or {}
    local last = rolls[#rolls]
    return { n = #rolls, last = last and last.n or nil, start = st.start }
  end,
  sounds = function(cur, was, out)
    if cur.n <= was.n or cur.start ~= was.start then return end
    out[#out + 1] = cur.last == 1 and "roll_one" or "die_roll"
  end,
}
