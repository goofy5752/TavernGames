local _, ns = ...

-- My late key of a cash table (the sender; the receiver is core/StakesCashLate.lua).
-- My kept key of a staked table (db.bookKeep, its sk set by Book.key) goes out
-- once a login: GUILD {v, t = "KEY", tid, g, m}. The first check is
-- LEDGER_ADOPT_WAIT after the login:
--   I sit in that game again (my session, seated, state.g): nothing, for good
--     (the game's own keys path publishes it).
--   I sit at that table in ANOTHER game: its hands have all ended, the lobby check is skipped.
--   The lobby's record of that table still lists me in a seat (a relog inside
--     a hand whose snapshot is late or lost: the key is the one my running
--     hand is committed to, F3-F I2): not now; checked again every
--     LEDGER_ADOPT_WAIT.
--   Else it is spent first (db.bookSpent: it never deals again) and sent.
-- The first check stamps bookKeep.late; CASH_BOOK_WAIT after it the kept key is
-- given up and the checks stop.
local Stakes, C = ns.Stakes, ns.Const
local Late, Book = Stakes.Late, Stakes.Book

-- My kept key of a staked table -> bool.
local function due(env, kept)
  return type(kept) == "table" and kept.sk ~= nil and kept.me == env.me and type(kept.tid) == "string"
    and type(kept.g) == "number" and ns.Book.isKey(kept.key)
end

-- Does the lobby still seat me at table tid -> bool.
local function seated(client, tid)
  local rec = client.lobby:get(tid)
  return rec ~= nil and ns.Util.contains(rec.seats, client.env.me)
end

-- My kept key goes out late (see the header).
function Late.send(client)
  local env = client.env
  local db, now = env.db, env.epoch()
  local kept, s = db.bookKeep, client.session
  if not due(env, kept) then return end
  if type(kept.late) ~= "number" then kept.late = now end
  if now > kept.late + C.CASH_BOOK_WAIT then db.bookKeep = nil; return end
  if s and s.tid == kept.tid and s.mySeat and s.state and s.state.g == kept.g then return end
  local other = s and s.tid == kept.tid and s.state and s.state.g ~= kept.g -- the key's hands have all ended
  if not other and seated(client, kept.tid) then return client:after(C.LEDGER_ADOPT_WAIT, function() Late.send(client) end) end
  local spent, have = type(db.bookSpent) == "table" and db.bookSpent or {}, false
  db.bookSpent = spent
  for _, x in ipairs(spent) do have = have or (x.tid == kept.tid and x.me == env.me and x.key == kept.key) end
  if not have then
    spent[#spent + 1] = { tid = kept.tid, me = env.me, key = kept.key }
    while #spent > ns.Book.SPENT_KEPT do table.remove(spent, 1) end
  end
  client:send("GUILD", nil, { v = C.PROTOCOL, t = "KEY", tid = kept.tid, g = kept.g, m = kept.key })
end

local start = Book.start
function Book:start()
  start(self)
  local client = self.client
  if due(self.env, self.env.db.bookKeep) then client:after(C.LEDGER_ADOPT_WAIT, function() Late.send(client) end) end
end

return Late
