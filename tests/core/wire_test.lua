Loader.lib("Libs/LibStub/LibStub.lua")
Loader.lib("Libs/AceSerializer-3.0/AceSerializer-3.0.lua")
Loader.lib("Libs/LibDeflate/LibDeflate.lua")

local ns = Loader.ns()
local wire = ns.Wire.new(LibStub("AceSerializer-3.0"), LibStub("LibDeflate"))

local m = {v=1, t="TBL", tid="Иван Петров#1763650000", s={"Иван Петров", false}, e=1}   -- file scope: used by tests 1 and 3

local snap = {
  v = 1, t = "SNP", tid = "Иван Петров#1763650000", e = 2, q = 17, left = 31,
  tbl = {
    tid = "Иван Петров#1763650000", g = "ttt", h = "Иван Петров", e = 2, ac = "invite",
    tn = 45, st = "live", s = { "Иван Петров", "Мария Стоянова" }, w = 8,
  },
  st = { board = { 1, 2, 0, 0, 1, 0, 2, 0, 0 }, turn = 1, score = { 2, 1 }, round = 4, first = 2 },
  inv = {
    "Георги Димитров", "Елена Николова", "Стоян Колев", "Румяна Василева",
    "Тодор Ангелов", "Цветелина Борисова", "Пламен Христов", "Яна Жекова",
  },
  note = "Вечерта в кръчмата започна тихо: ханджията бършеше чаши, а край огнището двама ловци спореха " ..
         "за цената на вълчата кожа. После вратата изскърца и влезе пътник с прашно наметало, поръча " ..
         "греяно вино и седна до прозореца. Никой не позна гласа му, но всички видяха пръстена с " ..
         "герба на изчезнал род, затова разговорите утихнаха чак до полунощ.",
}

describe("wire", function()
  it("round-trips Cyrillic names and nested tables", function()
    eq(wire:unpack(wire:pack(m)), m)
  end)

  it("snapshot above 255 bytes survives pack/unpack", function()
    ok(#wire:pack(snap) > 255); eq(wire:unpack(wire:pack(snap)), snap)
  end)

  it("packed text has no NUL byte", function() ok(not wire:pack(m):find("%z")) end)

  it("garbage returns nil instead of raising", function() eq(wire:unpack("not a message"), nil); eq(wire:unpack(""), nil) end)

  it("round-trips INA and HND with an invited list", function()
    local ina = { v = 1, t = "INA", tid = "Иван Петров#1763650000", e = 3, n = "Яна Жекова" }
    local hnd = { v = 1, t = "HND", tid = "Иван Петров#1763650000", e = 3, to = "Мария Стоянова",
                  inv = { "Яна Жекова", "Тодор Ангелов" } }
    eq(wire:unpack(wire:pack(ina)), ina); eq(wire:unpack(wire:pack(hnd)), hnd)
  end)

  it("non-table payloads and bad input never raise", function()
    eq(wire:unpack(wire:pack("just a string")), nil)
    eq(wire:unpack(nil), nil)
    eq(wire:unpack(LibStub("LibDeflate"):EncodeForWoWAddonChannel("not deflate data")), nil)
  end)
end)
