describe("x", function()
  it("fails", function() eq(1, 2) end)
  it("asserts nothing", function() end)   -- must fail: zero assertions
end)
