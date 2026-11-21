local _, ns = ...

-- The guild's gold ledger: append-only entries `i = "<author>:<n>"` of the
-- kinds R (result), D (debt), C (confirm), N (contest), P (paid) and X (deny),
-- their canonical form, hash (16 hex) and validation. The per-guild store is
-- core/LedgerStore.lua. A stored entry keeps its own hash in `h`, plus `dr`
-- (got from its author) or `rl` (relayed). An X's own field `h` (the denied
-- entry's hash) is kept as `rh` in the store; `wire` and `canon` give it back as `h`.
-- A C or N names the exact D it attests or contests: `r` its id, `dh` its 16-hex hash.
local Ledger = {}
ns.Ledger = Ledger

local C, Sha256 = ns.Const, ns.Sha256
local concat, floor = table.concat, math.floor

local FIELDS = { "i", "k", "at", "gid", "g", "f", "t", "c", "why", "r", "h", "how", "sk", "n", "w", "l", "dh" }
local NAME_MAX, SIZE_MAX = 64, 600
Ledger.ID_MAX = 999999999 -- the highest number of an id (9 digits)
local PAID_MAX = 99999999999 -- copper: a payment is any whole amount up to the gold cap

local function set(...) local s = {} for _, v in ipairs({ ... }) do s[v] = true end return s end
-- The fields of each kind: true = required, false = optional.
local KINDS = {
  R = { gid = true, g = true, n = true, w = true, l = true, sk = false, why = false },
  D = { gid = true, g = true, f = true, t = true, c = true, why = true },
  C = { r = true, dh = true }, N = { r = true, dh = true, why = true }, P = { f = true, c = true, how = true }, X = { r = true, h = true },
}
local WHY = { D = set("lost", "left", "offline", "idle"), N = set("forged", "roll", "stand", "amount", "no"),
  R = set("left", "offline", "idle") }
local HOW = set("trade", "mail", "hand")

local function whole(v) return type(v) == "number" and v == floor(v) end
function Ledger.id(author, n) return author .. ":" .. n end
-- The author and number of an id (the text before the last colon), or nil.
function Ledger.author(id)
  if type(id) ~= "string" then return nil end
  local a, n = id:match("^(.*):([1-9]%d*)$")
  if not a or a == "" or #n > #tostring(Ledger.ID_MAX) then return nil end
  return a, tonumber(n)
end
-- Field f of an entry of either form as it is sent: h is an X's denied hash
-- (`rh` when stored), never the local hash.
local function field(e, f)
  if f ~= "h" then return e[f] end
  return e.k == "X" and (e.rh or e.h) or nil
end
local function part(v)
  if v == nil then return "" elseif v == false then return "-" elseif type(v) ~= "table" then return tostring(v) end
  local out = {}
  for j, x in ipairs(v) do out[j] = part(x) end
  return concat(out, ",")
end
-- The fields in FIELDS order joined by "|"; hash: its first 16 hex of SHA-256.
function Ledger.canon(e)
  local out = {}
  for j, f in ipairs(FIELDS) do out[j] = part(field(e, f)) end
  return concat(out, "|")
end
function Ledger.hash(e) return Sha256.hex(Ledger.canon(e)):sub(1, 16) end
-- A stored body as an item of a list (L:list, the sync's LID): "<n>.<its 16-hex h>".
function Ledger.item(b) return select(2, Ledger.author(b.i)) .. "." .. b.h end

-- The entry as sent: its canonical fields only (lists copied), an X's denied hash as h.
function Ledger.wire(e)
  local w = {}
  for _, f in ipairs(FIELDS) do
    local v = field(e, f)
    w[f] = type(v) == "table" and { unpack(v) } or v
  end
  return w
end

-- A name: 1..64 bytes, no separator of the canonical form, not "-" (that is false there).
local function name(v) return type(v) == "string" and v ~= "" and v ~= "-" and #v <= NAME_MAX and not v:find("[|,]") end
local function seat(v) return whole(v) and v >= 1 and v <= C.MAX_SEATS end
local function nameOrEmpty(v) return v == false or name(v) end
-- A list of min..MAX_SEATS elements and no other keys, each passing `each`.
local function list(v, each, min)
  if type(v) ~= "table" then return false end
  local count = 0
  for _ in pairs(v) do count = count + 1 end
  if count < min or count > C.MAX_SEATS then return false end
  for j = 1, count do if v[j] == nil or not each(v[j]) then return false end end
  return true
end
-- Each field's check: the reason when it fails, else false (c and why are checked per kind).
local function person(v) return not name(v) and "name" end
local function seats(v) return not list(v, seat, 0) and "shape" end
local function hex16(v) return not (type(v) == "string" and #v == 16 and v:find("^[0-9a-f]+$")) and "shape" end
local CHECK = {
  gid = function(v) return not (type(v) == "string" and not v:find("|", 1, true) and v:find("./%d+$")) and "shape" end,
  g = function(v) return not (type(v) == "string" and #v <= 32 and v:find("^[%w_]+$")) and "shape" end,
  f = person, t = person, w = seats, l = seats,
  n = function(v) return not list(v, nameOrEmpty, 1) and "name" end,
  sk = function(v) return not ns.Stake.valid(v) and "amount" end,
  r = function(v) return not name(Ledger.author(v)) and "shape" end,
  h = hex16, dh = hex16,
  how = function(v) return not HOW[v] and "shape" end,
}
local function amount(e)
  if e.k == "D" then return ns.Stake.valid(e.c) end
  return whole(e.c) and e.c >= 1 and e.c <= PAID_MAX
end
local function right(e, author)
  if e.k == "D" then return e.f ~= e.t and (author == e.f or author == e.t) end
  if e.k == "P" then return author ~= e.f end
  return e.k ~= "X" or Ledger.author(e.r) == author
end

-- Is `e` a well-formed entry its author may write -> true | nil, reason.
function Ledger.valid(e, now)
  if type(e) ~= "table" then return nil, "shape" end
  local author = Ledger.author(e.i)
  if not author then return nil, "id" end
  local fields = KINDS[e.k]
  if not fields then return nil, "kind" end
  if not whole(e.at) or e.at < 0 or (now and e.at > now + C.LEDGER_FUTURE) then return nil, "time" end
  if not name(author) then return nil, "name" end
  for j = 4, #FIELDS do
    local f, v = FIELDS[j], field(e, FIELDS[j])
    if (fields[f] == nil and v ~= nil) or (fields[f] == true and v == nil) then return nil, "shape" end
    local why = v ~= nil and CHECK[f] and CHECK[f](v)
    if why then return nil, why end
  end
  if e.why ~= nil and not WHY[e.k][e.why] then return nil, "shape" end
  if fields.c and not amount(e) then return nil, "amount" end
  if not right(e, author) then return nil, "right" end
  if #Ledger.canon(e) > SIZE_MAX then return nil, "size" end
  return true
end

return Ledger
