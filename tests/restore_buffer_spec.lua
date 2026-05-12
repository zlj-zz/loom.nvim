---@diagnostic disable: undefined-field

describe("restore.buffer", function()
  local restore_buffer = require("loom.restore.buffer")
  local created_bufs = {}

  local function cleanup_bufs()
    for _, bufnr in ipairs(created_bufs) do
      pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    end
    created_bufs = {}
  end

  after_each(cleanup_bufs)

  it("restores named buffer with lines and filetype", function()
    local captured = {
      name = "/tmp/test_restore.lua",
      lines = { "line 1", "line 2" },
      filetype = "lua",
      buftype = "",
      modified = false,
      excluded = false,
      bufnr = 999,
    }
    local bufnr = restore_buffer.restore(captured)
    table.insert(created_bufs, bufnr)

    assert.is_not_nil(bufnr)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.equals(2, #lines)
    assert.equals("line 1", lines[1])
    assert.equals("line 2", lines[2])
    assert.equals("lua", vim.api.nvim_get_option_value("filetype", { buf = bufnr }))
  end)

  it("restores unnamed buffer", function()
    local captured = {
      name = nil,
      lines = { "unnamed content" },
      filetype = "",
      buftype = "",
      modified = false,
      excluded = false,
      bufnr = 999,
    }
    local bufnr = restore_buffer.restore(captured)
    table.insert(created_bufs, bufnr)

    assert.is_not_nil(bufnr)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.equals("unnamed content", lines[1])
  end)

  it("skips excluded buffers", function()
    local captured = { excluded = true, bufnr = 999 }
    local bufnr = restore_buffer.restore(captured)
    assert.is_nil(bufnr)
  end)

  it("restores modified flag", function()
    local captured = {
      name = "/tmp/mod.lua",
      lines = { "x" },
      filetype = "lua",
      buftype = "",
      modified = true,
      excluded = false,
      bufnr = 999,
    }
    local bufnr = restore_buffer.restore(captured)
    table.insert(created_bufs, bufnr)

    assert.is_true(vim.api.nvim_get_option_value("modified", { buf = bufnr }))
  end)

  it("restore_all produces correct bufnr_map and cursor_map", function()
    local buffers = {
      {
        name = "/tmp/a.lua",
        lines = { "a" },
        filetype = "lua",
        buftype = "",
        modified = false,
        excluded = false,
        bufnr = 100,
        cursor = { line = 3, col = 5 },
      },
      {
        name = "/tmp/b.lua",
        lines = { "b" },
        filetype = "lua",
        buftype = "",
        modified = false,
        excluded = false,
        bufnr = 101,
      },
    }

    local bufnr_map, cursor_map = restore_buffer.restore_all(buffers)

    assert.is_not_nil(bufnr_map[100])
    assert.is_not_nil(bufnr_map[101])
    assert.equals(3, cursor_map[100].line)
    assert.equals(5, cursor_map[100].col)
    assert.is_nil(cursor_map[101])

    table.insert(created_bufs, bufnr_map[100])
    table.insert(created_bufs, bufnr_map[101])
  end)
end)
