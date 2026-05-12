---@diagnostic disable: undefined-field

describe("core.save and core.load", function()
  local core = require("loom.core")
  local storage = require("loom.storage")

  local test_name = "_test_roundtrip_"

  after_each(function()
    pcall(storage.delete_snapshot, test_name)
  end)

  it("save creates meta.json with snapshot_id", function()
    local ok = core.save(test_name, { note = "test" })
    assert.is_true(ok)

    local meta = storage.read_json(storage.snapshot_dir(test_name) .. "/meta.json")
    assert.is_not_nil(meta)
    if not meta then
      return
    end
    assert.is_not_nil(meta.snapshot_id)
    assert.matches("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-4%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$", meta.snapshot_id)
    assert.equals("test", meta.note)
  end)

  it("round-trip preserves buffer content", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, "/tmp/test_roundtrip_file.lua")
    vim.api.nvim_set_option_value("buftype", "", { buf = bufnr })
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "line 1", "line 2", "line 3" })
    vim.api.nvim_set_current_buf(bufnr)

    local saved = core.save(test_name, { note = "round-trip test" })
    assert.is_true(saved)

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "modified 1", "modified 2" })

    core.load(test_name)

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.equals(3, #lines)
    assert.equals("line 1", lines[1])
    assert.equals("line 2", lines[2])
    assert.equals("line 3", lines[3])

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("save writes buffers.json and layout.json", function()
    local saved = core.save(test_name, {})
    assert.is_true(saved)

    local buffers = storage.read_json(storage.snapshot_dir(test_name) .. "/buffers.json")
    local layout = storage.read_json(storage.snapshot_dir(test_name) .. "/layout.json")

    assert.is_not_nil(buffers)
    assert.is_true(type(buffers) == "table")
    assert.is_not_nil(layout)
    assert.is_true(type(layout) == "table")
  end)
end)
