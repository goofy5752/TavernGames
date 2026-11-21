describe("runner", function()
  it("deep-compares tables", function() eq({a={1,2}}, {a={1,2}}) end)
  it("catches errors", function() raises(function() error("boom") end, "boom") end)
  it("a failed eq over tables that hold each other (frames) says so instead of overflowing the stack", function()
    local parent = { name = "parent", kids = {} }
    local kid = { name = "kid", parent = parent }
    parent.kids[1], parent.self = kid, parent
    local okay, err = pcall(eq, parent, { name = "other" })
    eq(okay, false); ok(tostring(err):find("<cycle>", 1, true), tostring(err))
    ok(tostring(err):find('"parent"', 1, true), tostring(err)); ok(not tostring(err):find("overflow", 1, true), tostring(err))
    local deep = {}
    local at = deep
    for _ = 1, 40 do at.next = {}; at = at.next end
    okay, err = pcall(eq, deep, {})
    eq(okay, false); ok(tostring(err):find("{…}", 1, true), tostring(err)); ok(#tostring(err) < 600, "the message has " .. #tostring(err) .. " bytes")
    okay, err = pcall(eq, { 1, { 2, { 3 } } }, { 1, { 2, { 4 } } })
    eq(okay, false); ok(tostring(err):find("expected {[1]=1, [2]={[1]=2, [2]={[1]=4}}}, got {[1]=1, [2]={[1]=2, [2]={[1]=3}}}", 1, true), tostring(err))
  end)
end)
