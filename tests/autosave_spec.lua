---@diagnostic disable: undefined-field, duplicate-set-field

describe("autosave", function()
  local autosave = require("loom.autosave")
  local core = require("loom.core")

  local original_new_timer
  local original_get_config
  local original_autosave
  local timer_spy
  local core_autosave_spy

  before_each(function()
    original_new_timer = vim.uv.new_timer
    original_get_config = require("loom").get_config
    original_autosave = core.autosave

    timer_spy = { starts = {}, stops = 0, closes = 0 }
    vim.uv.new_timer = function()
      return {
        start = function(_, interval, _)
          table.insert(timer_spy.starts, interval)
        end,
        stop = function()
          timer_spy.stops = timer_spy.stops + 1
        end,
        close = function()
          timer_spy.closes = timer_spy.closes + 1
        end,
      }
    end

    core_autosave_spy = { calls = 0 }
    core.autosave = function(_, _)
      core_autosave_spy.calls = core_autosave_spy.calls + 1
      return true
    end
  end)

  after_each(function()
    vim.uv.new_timer = original_new_timer
    core.autosave = original_autosave
    require("loom").get_config = original_get_config
    autosave.stop()
  end)

  it("start creates timer with correct interval", function()
    require("loom").get_config = function()
      return {
        autosave = { enabled = true, interval_minutes = 30, on_events = {}, max_auto_snaps = 10 },
        naming = {},
      }
    end

    autosave.start()

    assert.equals(1, #timer_spy.starts)
    assert.equals(30 * 60 * 1000, timer_spy.starts[1])
  end)

  it("stop closes timer", function()
    require("loom").get_config = function()
      return {
        autosave = { enabled = true, interval_minutes = 30, on_events = {}, max_auto_snaps = 10 },
        naming = {},
      }
    end

    autosave.start()
    autosave.stop()

    assert.is_true(timer_spy.closes >= 1)
  end)

  it("trigger returns false when disabled", function()
    require("loom").get_config = function()
      return {
        autosave = { enabled = false, interval_minutes = 30, on_events = {}, max_auto_snaps = 10 },
        naming = {},
      }
    end

    local result = autosave.trigger()

    assert.is_false(result)
  end)

  it("start does nothing when disabled", function()
    require("loom").get_config = function()
      return {
        autosave = { enabled = false, interval_minutes = 30, on_events = {}, max_auto_snaps = 10 },
        naming = {},
      }
    end

    autosave.start()

    assert.equals(0, #timer_spy.starts)
  end)
end)
