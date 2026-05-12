---@diagnostic disable: undefined-field

describe("restore.layout", function()
  local restore_layout = require("loom.restore.layout")

  local original_wins
  local created_bufs = {}

  before_each(function()
    original_wins = vim.api.nvim_list_wins()
    created_bufs = {}
  end)

  after_each(function()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if not vim.tbl_contains(original_wins, win) then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
    for _, bufnr in ipairs(created_bufs) do
      pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    end
  end)

  local function make_buf(lines)
    local bufnr = vim.api.nvim_create_buf(false, true)
    if lines then
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    end
    table.insert(created_bufs, bufnr)
    return bufnr
  end

  it("restores single leaf layout", function()
    local bufnr = make_buf({ "single" })
    local layout = { type = "leaf", bufnr = 100, weight = 1 }
    local bufnr_map = { [100] = bufnr }

    restore_layout.restore(layout, bufnr_map, {})

    assert.equals(1, #vim.api.nvim_list_wins())
    local win = vim.api.nvim_get_current_win()
    assert.equals(bufnr, vim.api.nvim_win_get_buf(win))
  end)

  it("restores row layout with 2 windows", function()
    local buf1 = make_buf({ "left" })
    local buf2 = make_buf({ "right" })
    local layout = {
      type = "row",
      weight = 1,
      children = {
        { type = "leaf", bufnr = 100, weight = 0.5 },
        { type = "leaf", bufnr = 101, weight = 0.5 },
      },
    }
    local bufnr_map = { [100] = buf1, [101] = buf2 }

    restore_layout.restore(layout, bufnr_map, {})

    local wins = vim.api.nvim_list_wins()
    assert.equals(2, #wins)
  end)

  it("restores mixed row/col layout", function()
    local buf1 = make_buf({ "a" })
    local buf2 = make_buf({ "b" })
    local buf3 = make_buf({ "c" })
    local layout = {
      type = "row",
      weight = 1,
      children = {
        {
          type = "col",
          weight = 0.5,
          children = {
            { type = "leaf", bufnr = 100, weight = 0.5 },
            { type = "leaf", bufnr = 101, weight = 0.5 },
          },
        },
        { type = "leaf", bufnr = 102, weight = 0.5 },
      },
    }
    local bufnr_map = { [100] = buf1, [101] = buf2, [102] = buf3 }

    restore_layout.restore(layout, bufnr_map, {})

    local wins = vim.api.nvim_list_wins()
    assert.equals(3, #wins)
  end)

  it("associates buffers correctly in restored windows", function()
    local buf = make_buf({ "content" })
    local layout = {
      type = "row",
      weight = 1,
      children = {
        { type = "leaf", bufnr = 100, weight = 0.3 },
        { type = "leaf", bufnr = 100, weight = 0.7 },
      },
    }
    local bufnr_map = { [100] = buf }

    restore_layout.restore(layout, bufnr_map, {})

    local wins = vim.api.nvim_list_wins()
    assert.equals(2, #wins)
    for _, win in ipairs(wins) do
      assert.equals(buf, vim.api.nvim_win_get_buf(win))
    end
  end)

  it("restores cursor positions", function()
    local buf = make_buf({ "line1", "line2", "line3" })
    local layout = { type = "leaf", bufnr = 100, weight = 1 }
    local bufnr_map = { [100] = buf }
    local cursor_map = { [100] = { line = 2, col = 3 } }

    restore_layout.restore(layout, bufnr_map, cursor_map)

    local win = vim.api.nvim_get_current_win()
    local cursor = vim.api.nvim_win_get_cursor(win)
    assert.equals(2, cursor[1])
    assert.equals(3, cursor[2])
  end)
end)
