---@diagnostic disable: undefined-field

describe("capture.layout", function()
  local layout = require("loom.capture.layout")
  local original_wins

  before_each(function()
    original_wins = vim.api.nvim_list_wins()
  end)

  after_each(function()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if not vim.tbl_contains(original_wins, win) then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
  end)

  it("weights sum to 1.0 for row layout", function()
    vim.cmd("vsplit")
    vim.cmd("vsplit")

    local captured = layout.capture()
    local ok, err = layout.validate(captured)

    assert.is_true(ok, err)
  end)

  it("weights sum to 1.0 for col layout", function()
    vim.cmd("split")
    vim.cmd("split")

    local captured = layout.capture()
    local ok, err = layout.validate(captured)

    assert.is_true(ok, err)
  end)

  it("validates mixed row/col layout", function()
    vim.cmd("vsplit")
    vim.cmd("wincmd l")
    vim.cmd("split")

    local captured = layout.capture()
    local ok, err = layout.validate(captured)

    assert.is_true(ok, err)
  end)
end)
