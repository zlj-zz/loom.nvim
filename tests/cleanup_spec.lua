---@diagnostic disable: undefined-field

describe("cleanup", function()
  local cleanup = require("loom.cleanup")
  local storage = require("loom.storage")

  local original_list, original_read, original_delete, original_get_config
  local deleted

  before_each(function()
    original_list = storage.list_snapshots
    original_read = storage.read_json
    original_delete = storage.delete_snapshot
    original_get_config = require("loom").get_config
    deleted = {}
  end)

  after_each(function()
    storage.list_snapshots = original_list
    storage.read_json = original_read
    storage.delete_snapshot = original_delete
    require("loom").get_config = original_get_config
  end)

  it("deletes snapshots older than threshold", function()
    require("loom").get_config = function()
      return { cleanup = { auto_cleanup_after_days = 30, max_snapshots = 0 } }
    end
    storage.list_snapshots = function() return { "old", "new" } end
    storage.read_json = function(path)
      if path:find("old") then
        return { timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ", os.time() - 86400 * 100) }
      else
        return { timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ") }
      end
    end
    storage.delete_snapshot = function(name)
      deleted[name] = true
      return true
    end

    cleanup.cleanup({ dry_run = false })

    assert.is_true(deleted["old"])
    assert.is_nil(deleted["new"])
  end)

  it("respects max_snapshots limit", function()
    require("loom").get_config = function()
      return { cleanup = { auto_cleanup_after_days = 0, max_snapshots = 5 } }
    end
    local names = {}
    for i = 1, 10 do
      table.insert(names, "snap_" .. i)
    end
    storage.list_snapshots = function() return names end
    storage.read_json = function(path)
      local idx = tonumber(path:match("snap_(%d+)")) or 1
      return { timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ", os.time() - idx * 3600) }
    end
    storage.delete_snapshot = function(name)
      deleted[name] = true
      return true
    end

    cleanup.cleanup({ dry_run = false })

    -- oldest 5 should be deleted
    for i = 6, 10 do
      assert.is_true(deleted["snap_" .. i], "expected snap_" .. i .. " to be deleted")
    end
    for i = 1, 5 do
      assert.is_nil(deleted["snap_" .. i])
    end
  end)

  it("dry_run does not delete", function()
    require("loom").get_config = function()
      return { cleanup = { auto_cleanup_after_days = 30, max_snapshots = 0 } }
    end
    storage.list_snapshots = function() return { "old" } end
    storage.read_json = function(_)
      return { timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ", os.time() - 86400 * 100) }
    end
    storage.delete_snapshot = function(name)
      deleted[name] = true
      return true
    end

    cleanup.cleanup({ dry_run = true })

    assert.is_nil(deleted["old"])
  end)

  it("combined age and count cleanup does not duplicate", function()
    require("loom").get_config = function()
      return { cleanup = { auto_cleanup_after_days = 30, max_snapshots = 1 } }
    end
    -- 3 snapshots: 2 old (age) + 1 new, max_snapshots=1
    -- Should delete exactly 2, not 3
    storage.list_snapshots = function() return { "a", "b", "c" } end
    storage.read_json = function(path)
      if path:find("/a/") or path:find("/b/") then
        return { timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ", os.time() - 86400 * 100) }
      end
      return { timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ") }
    end
    local delete_count = 0
    storage.delete_snapshot = function(_)
      delete_count = delete_count + 1
      return true
    end

    cleanup.cleanup({ dry_run = false })

    assert.equals(2, delete_count)
  end)
end)
