local _, ns = ...

-- A cash table's word on claims (Stakes.cash; the notes are core/StakesCashOwe.lua's).
--   My word on a cash claim is my own D, why "cash" (never a C: an F1/F2
--     client keeps it pending); whether the claim is of a cash game is read from
--     my own note of that event, never from the creditor's entry.
--   A cash note without a pair for the creditor (H13), a note with no pairs
--     included: contested "no" when clean, asked when unseen.
--   An unseen note's debt nobody claimed is put to me (Book:owing, Book:admit).
local Stakes, C = ns.Stakes, ns.Const
local Book, View, cashGame = Stakes.Book, ns.LedgerView, Stakes.cashGame

-- My word on a claim of a cash game (my note's game; without a note, the claim's): my own D (why "cash"), never a C.
local word = Book.word
function Book:word(d, b, wide, kind, why)
  local note = self:seen()[d.gid]
  local g = type(note) == "table" and note.g or b.g
  if kind ~= "C" or not cashGame(g) then return word(self, d, b, wide, kind, why) end
  return self:make("O" .. d.key, "D", { gid = d.gid, g = g, f = d.f, t = d.t, c = b.c, why = "cash" })
end

-- H13: a final cash note of mine without a pair f = me, t = the creditor.
local judge = Book.judge
function Book:judge(b, taken)
  local note, me = self:seen()[b.gid], self.env.me
  if type(note) == "table" and not note.open and not note.wait and cashGame(note.g) and (not note.foul or note.foul == "unseen") then
    for _, p in ipairs(note.pairs or {}) do if p.f == me and p.t == b.t then return judge(self, b, taken) end end
    if note.foul then return "ask" end
    return "N", "no"
  end
  return judge(self, b, taken)
end

-- My final unseen cash notes' debts nobody claimed, STAKE_OWE_WAIT after the note -> {{gid, t, c, key}} (by key).
function Book:owing()
  local L, me, now, out = self.client.ledger, self.env.me, self.env.epoch(), {}
  if not L then return out end
  local have = {}
  for _, d in ipairs(View.of(L).debts) do have[d.key] = true end
  for gid, n in pairs(self:seen()) do
    if type(n) == "table" and n.why == "cash" and n.foul == "unseen" and not n.wait and not n.open
        and type(n.at) == "number" and n.at + C.STAKE_OWE_WAIT <= now then
      for _, p in ipairs(type(n.pairs) == "table" and n.pairs or {}) do
        local key = gid .. "|" .. me .. "|" .. tostring(p.t)
        if p.f == me and not have[key] and not self.answered[key] then out[#out + 1] = { gid = gid, t = p.t, c = p.c, key = key } end
      end
    end
  end
  table.sort(out, function(x, y) return x.key < y.key end)
  return out
end

-- My answer to a debt of Book:owing (yes: my own D, why "cash"); remembered for this run -> true | nil.
function Book:admit(key, yes)
  for _, o in ipairs(self:owing()) do
    if o.key == key then
      if yes then self:make("O" .. key, "D", { gid = o.gid, g = self:seen()[o.gid].g, f = self.env.me, t = o.t, c = o.c, why = "cash" }) end
      self.answered[key] = true
      self.client.events:emit("debtAsk")
      return true
    end
  end
  return nil
end

-- One wake-up ("debtAsk") per unseen final cash note, at its due time (Book:owing); a due one needs none.
function Book:armOwing()
  local now = self.env.epoch()
  self.owingArmed = self.owingArmed or {}
  for gid, n in pairs(self:seen()) do
    if type(n) == "table" and n.why == "cash" and n.foul == "unseen" and not n.wait and not n.open and not self.owingArmed[gid]
        and type(n.at) == "number" and n.at + C.STAKE_OWE_WAIT > now then
      self.owingArmed[gid] = true
      self.client:after(n.at + C.STAKE_OWE_WAIT - now + 1, function() self.client.events:emit("debtAsk") end)
    end
  end
end
