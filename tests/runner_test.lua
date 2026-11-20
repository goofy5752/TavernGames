describe("runner", function()
  it("deep-compares tables", function() eq({a={1,2}}, {a={1,2}}) end)
  it("catches errors", function() raises(function() error("boom") end, "boom") end)
end)
