---@diagnostic disable: undefined-field

describe("capture.buffer", function()
  local buffer = require("loom.capture.buffer")

  local function make_test_buf(name, lines)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, name)
    vim.api.nvim_set_option_value("buftype", "", { buf = bufnr })
    if lines then
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    end
    return bufnr
  end

  it("excludes .env files by pattern", function()
    local bufnr = make_test_buf("/tmp/test/.env", { "SECRET=value" })

    local captured = buffer.capture(bufnr)

    assert.is_true(captured.excluded)
    assert.is_not_nil(captured.exclude_reason)
    assert.matches("pattern", captured.exclude_reason)

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("excludes large files", function()
    local bufnr = make_test_buf("/tmp/test/large_file.txt")

    local big_line = string.rep("x", 1024)
    local lines = {}
    for _ = 1, 1025 do
      table.insert(lines, big_line)
    end
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

    local captured = buffer.capture(bufnr)

    assert.is_true(captured.large_file)
    assert.is_nil(captured.lines)

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("preserves modified content", function()
    local bufnr = make_test_buf("/tmp/test/modified.lua", { "original line" })
    vim.api.nvim_set_option_value("modified", true, { buf = bufnr })

    local captured = buffer.capture(bufnr)

    assert.is_false(captured.excluded)
    assert.is_not_nil(captured.lines)
    assert.equals("original line", captured.lines[1])
    assert.is_true(captured.modified)

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("excludes sensitive content", function()
    local bufnr = make_test_buf("/tmp/test/config.lua", { "local API_KEY = 'super_secret'" })

    local captured = buffer.capture(bufnr)

    assert.is_true(captured.excluded)
    assert.is_not_nil(captured.exclude_reason)
    assert.matches("sensitive", captured.exclude_reason)

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end)
