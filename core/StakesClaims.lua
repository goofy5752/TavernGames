local _, ns = ...

-- What my client says to a claim against me (core/StakesBook.lua's review):
--   my „Стани“ (db.stakeLeft, core/Stakes.lua): the one claim of that stand
--   (its gid, why "left", the table's stake, within STAKE_LEFT_WINDOW of it,
--   a creditor I left behind) -> C, once per creditor, unless my note of that
--   game holds any foul (then put to me; its roll part pending -> wait); another amount there
--   -> N "amount", any other claim at that gid -> put to me; in a team game (engine.partner) a
--   creditor who is no opponent -> N "no", and the C waits for the one R of that game by my host
--   at my stand (left.h) naming my seat (my partner's stand may have come first), put to me STAKE_OWE_WAIT after my stand
--   without it or at once with another; a "left" claim at that table more than
--   LEAVE_SLACK events after it, with no note of mine for its gid: a game I was
--   not in (N "forged") once that creditor's claim of my stand was taken and the
--   claim came within LEAVE_AT_SLACK of the leave, else put to me (in-flight
--   timing is no foul); an asked seat's leave is inert;
--   my note of its gid: roll part pending -> wait, a foul forged/roll/stand
--   -> N with it, a creditor I owe nothing at a clean loss -> N "no", another
--   amount -> N "amount", my pair clean and the claim written within
--   STAKE_LEFT_WINDOW of my note -> C (my own D when its id holds bodies of
--   more than one debt);
--   an event of my running table I have not applied yet -> wait;
--   the newest open note of that table at or before its q, written within
--   STAKE_LEFT_WINDOW of the claim: a foul -> N with it, another amount -> N
--   "amount"; anything else is put to me. A C or N names the body (dh).
local C, Util = ns.Const, ns.Util
local Book = ns.Stakes.Book

local BAD = { forged = true, roll = true, stand = true }
local LEAVE_SLACK = 4 -- events my host may order between my „Стани“ and its stand
local LEAVE_AT_SLACK = 120 -- s: a far claim is contested only this close to the stored leave (a crash may lose a later one)

local function near(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a - b) <= C.STAKE_LEFT_WINDOW end

-- Claim body b -> "C" | "N", why | "wait" | "ask" (and the leave it used;
-- `taken`: creditor -> the body a leave was used for in this scan).
function Book:judge(b, taken)
  local me, tid, q = self.env.me, b.gid:match("^(.*)/(%d+)$")
  q = tonumber(q)
  local left, note = self:left()[tid], self:seen()[b.gid]
  local lq = type(left) == "table" and tonumber(left.q) or nil
  if q == lq and left.sk ~= nil then -- an inert leave (an asked seat's) neither confirms nor contests
    local used, E = (type(left.used) == "table" and left.used[b.t]) or taken[b.t], left.g and ns.Games.engine(left.g)
    local owed = Util.contains(type(left.names) == "table" and left.names or {}, b.t)
    if E and E.partner and not owed then return "N", "no" end -- my partner, or nobody of that game
    if b.why == "left" and left.sk == b.c and near(b.at, left.at) and (not used or used == b.h) and owed then
      -- Never from a game my client holds any foul of (forged, roll, stand, unseen): that is put to me.
      if type(note) == "table" and (note.wait or note.foul) then return note.wait and "wait" or "ask" end
      if E and E.partner then -- my partner's stand may have come first: only the one R of it naming me confirms
        local n, named = self:results(b.gid, left.h)
        local due = (left.at or 0) + C.STAKE_OWE_WAIT - self.env.epoch()
        if not named and (n > 0 or due <= 0) then return "ask" end
        if not named then self.wake = self.wake or self.client:after(due + 1, function() self.wake = nil; self:review() end); return "wait" end
      end
      taken[b.t] = b.h
      return "C", nil, left
    end
    return b.c ~= left.sk and "N" or "ask", "amount"
  end
  if type(note) == "table" and not note.open then
    if note.wait then return "wait" end
    if BAD[note.foul] then return "N", note.foul end
    local p, mine
    for _, x in ipairs(note.pairs or {}) do if x.f == me then mine = true; if x.t == b.t then p = x end end end
    if mine and not p and not note.foul then return "N", "no" end -- a creditor I do not owe
    if b.c ~= (p and p.c or note.sk) then return "N", "amount" end
    return (p and not note.foul and near(b.at, note.at)) and "C" or "ask"
  end
  if lq and b.why == "left" and q > lq + LEAVE_SLACK then -- a game after I left, once my stand's own claim was taken
    local used = (type(left.used) == "table" and left.used[b.t]) or taken[b.t]
    if used and used ~= b.h and math.abs(b.at - (left.at or 0)) <= LEAVE_AT_SLACK then return "N", "forged" end
  end
  local s = self.client.session
  if s and s.tid == tid and q > s.seq then self.held = true; return "wait" end -- again at each change of my table
  local open
  for _, n in pairs(self:seen()) do
    if type(n) == "table" and n.open and n.tid == tid and (n.q or 0) <= q and near(b.at, n.at) and (not open or n.at > open.at) then open = n end
  end
  if open and BAD[open.foul] then return "N", open.foul end
  local sk = (open and open.sk) or (type(left) == "table" and left.sk)
  if sk and b.c ~= sk then return "N", "amount" end
  return "ask"
end

-- The R bodies of gid by author h in my ledger (neither denied nor put to me; LedgerView's
-- index) -> how many, and whether there is one and it names my seat alone as the loser.
function Book:results(gid, h)
  local View, rs = ns.LedgerView, {}
  for _, e in ipairs(View.results(View.of(self.client.ledger), gid)) do if ns.Ledger.author(e.i) == h then rs[#rs + 1] = e end end
  return #rs, #rs == 1 and type(rs[1].l) == "table" and #rs[1].l == 1 and type(rs[1].n) == "table" and rs[1].n[rs[1].l[1]] == self.env.me
end

-- The claim bodies of debt d (its creditor's D entries), and whether an id of
-- them holds bodies of another debt as well (then my word is my own D).
function Book:claims(d)
  local L, out, wide = self.client.ledger, {}, false
  for _, id in ipairs(d.ids) do
    local a, n = ns.Ledger.author(id)
    for _, b in ipairs(L:bodies(a, n)) do
      if b.k == "D" and b.gid == d.gid and b.f == d.f and b.t == d.t and a == d.t and not b.un and not L:denied(b) then
        out[#out + 1] = b
      elseif b.k == "D" and b.gid .. "|" .. tostring(b.f) .. "|" .. tostring(b.t) ~= d.key then wide = true end
    end
  end
  return out, wide
end

-- My word on body b of debt d: C (my own D, `wide`), or N why.
function Book:word(d, b, wide, kind, why)
  if kind == "N" then return self:make("W" .. b.h, "N", { r = b.i, dh = b.h, why = why }) end
  if wide then return self:make("O" .. d.key, "D", { gid = d.gid, g = b.g, f = d.f, t = d.t, c = b.c, why = b.why }) end
  return self:make("W" .. b.h, "C", { r = b.i, dh = b.h })
end

