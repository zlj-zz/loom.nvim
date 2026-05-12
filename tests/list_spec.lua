---@diagnostic disable: undefined-field

describe("list.format_relative_time", function()
  local list = require("loom.list")

  it("formats 'just now' for recent timestamps", function()
    local now = os.date("!%Y-%m-%dT%H:%M:%SZ") ---@type string
    local result = list.format_relative_time(now)
    assert.equals("just now", result)
  end)

  it("formats minutes ago", function()
    local t = os.date("!%Y-%m-%dT%H:%M:%SZ", os.time() - 300)
    local result = list.format_relative_time(t)
    assert.matches("5 min", result)
  end)

  it("formats hours ago", function()
    local t = os.date("!%Y-%m-%dT%H:%M:%SZ", os.time() - 7200)
    local result = list.format_relative_time(t)
    assert.matches("2 hour", result)
  end)

  it("formats yesterday", function()
    local t = os.date("!%Y-%m-%dT%H:%M:%SZ", os.time() - 90000)
    local result = list.format_relative_time(t)
    assert.equals("yesterday", result)
  end)

  it("formats days ago", function()
    local t = os.date("!%Y-%m-%dT%H:%M:%SZ", os.time() - 172800)
    local result = list.format_relative_time(t)
    assert.matches("2 day", result)
  end)

  it("formats weeks ago", function()
    local t = os.date("!%Y-%m-%dT%H:%M:%SZ", os.time() - 1209600)
    local result = list.format_relative_time(t)
    assert.matches("2 week", result)
  end)

  it("formats months ago", function()
    local t = os.date("!%Y-%m-%dT%H:%M:%SZ", os.time() - 7776000)
    local result = list.format_relative_time(t)
    assert.matches("3 month", result)
  end)

  it("returns original string for invalid timestamps", function()
    local result = list.format_relative_time("not-a-timestamp")
    assert.equals("not-a-timestamp", result)
  end)
end)

describe("list.format_snapshot", function()
  local list = require("loom.list")

  it("formats name only", function()
    local item = { name = "test", branch = nil, time = nil, note = nil }
    local result = list.format_snapshot(item)
    assert.equals("test", result)
  end)

  it("includes branch", function()
    local item = { name = "test", branch = "main", time = nil, note = nil }
    local result = list.format_snapshot(item)
    assert.matches("main", result)
  end)

  it("truncates long notes", function()
    local item = { name = "test", note = string.rep("a", 50) }
    local result = list.format_snapshot(item)
    assert.matches("%.%.%.", result)
    assert.is_true(#result < 80)
  end)

  it("omits empty note", function()
    local item = { name = "test", note = "" }
    local result = list.format_snapshot(item)
    assert.is_not_nil(result)
    assert.is_false(result:find("%[", 1, true) ~= nil)
  end)
end)
