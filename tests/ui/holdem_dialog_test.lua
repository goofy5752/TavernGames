local Staked = require("staked")

describe("the new-table dialog at Холдем", function()
  it("a fun Холдем dialog sends no rebuy", function()
    local w = Staked.guildWow(); w.ns.MainWindow.show(); local D = w.ns.NewTableDialog
    D.open("holdem")
    local ids = {}
    for id in pairs(D.options) do ids[#ids + 1] = id end
    table.sort(ids)
    eq(ids, { "betting", "blinds", "stack" }); eq(D.set.count, 3)
    local sent
    w.ns.client.openTable = function(_, o) sent = o; return nil, "busy" end
    w:click(D.openButton)
    eq(sent.opt, { betting = "nl", blinds = 10, stack = 100 })
  end)
end)
