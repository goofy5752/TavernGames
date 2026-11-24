-- Chess test helpers: local Chess = require("chess"), on the shared namespace of tests/helpers/sim.lua.
--   Chess.sq("e4")              -> 29
--   Chess.at(fen, opts)         -> E.new(opts or { first = 2, opt = { clock = 10 } }) with the position
--                                  of `fen`, the seat of its side on turn and seen = { [R.key] = 1 }
--   Chess.play(state, "e2e4 e7e5 e7e8q", dt) -> state: each word applied for the seat on turn
local ns = require("sim").ns
local R, E = ns.ChessRules, ns.Engines.chess

local Chess = { E = E, R = R, ns = ns }

function Chess.sq(name)
  local file, rank = ("abcdefgh"):find(name:sub(1, 1), 1, true), tonumber(name:sub(2, 2))
  assert(file and rank and rank >= 1 and rank <= 8, "bad square " .. tostring(name))
  return (rank - 1) * 8 + file
end

function Chess.at(fen, opts)
  local s, pos = E.new(opts or { first = 2, opt = { clock = 10 } }), assert(R.fromFen(fen), "bad fen")
  s.board, s.side, s.castle, s.ep, s.half, s.full = pos.board, pos.side, pos.castle, pos.ep, pos.half, pos.full
  s.turn = pos.side == 1 and s.white or 3 - s.white
  s.seen = { [R.key(s)] = 1 }
  return s
end

function Chess.play(s, words, dt)
  for w in words:gmatch("%S+") do
    local p = w:sub(5, 5)
    local a = { k = "move", f = Chess.sq(w:sub(1, 2)), t = Chess.sq(w:sub(3, 4)), p = p ~= "" and p or nil }
    local seat = s.turn
    local r, why = E.apply(s, seat, a, dt)
    ok(r, "seat " .. tostring(seat) .. " " .. w .. " rejected: " .. tostring(why))
  end
  return s
end

return Chess
