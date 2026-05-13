---@diagnostic disable: undefined-field

-- Load plugin commands so :Loom* are available
vim.cmd("runtime plugin/loom.lua")

describe("e2e commands", function()
  local core = require("loom.core")
  local storage = require("loom.storage")

  local orig_save, orig_load, orig_cleanup, orig_workspace_save
  local captured
  local orig_ui_select
  local select_idx

  before_each(function()
    captured = nil
    select_idx = 1

    orig_save = core.save
    orig_load = core.load
    orig_cleanup = core.cleanup
    orig_workspace_save = core.workspace_save
    orig_ui_select = vim.ui.select

    vim.ui.select = function(items, _, on_choice)
      on_choice(items[select_idx])
    end
  end)

  after_each(function()
    core.save = orig_save
    core.load = orig_load
    core.cleanup = orig_cleanup
    core.workspace_save = orig_workspace_save
    vim.ui.select = orig_ui_select
  end)

  local function ensure_deleted(name)
    if storage.snapshot_exists(name) then
      storage.delete_snapshot(name)
    end
  end

  it("LoomSave parses name and --note flag", function()
    core.save = function(name, opts)
      captured = { name = name, opts = opts }
    end

    vim.cmd("LoomSave my_snap --note='wip feature'")

    assert.equals("my_snap", captured.name)
    assert.equals("wip feature", captured.opts.note)
  end)

  it("LoomSave parses double-quoted --note", function()
    core.save = function(name, opts)
      captured = { name = name, opts = opts }
    end

    vim.cmd('LoomSave --note="double quoted"')

    assert.is_nil(captured.name)
    assert.equals("double quoted", captured.opts.note)
  end)

  it("LoomWorkspaceSave parses --repos flag", function()
    core.workspace_save = function(name, opts)
      captured = { name = name, opts = opts }
    end

    vim.cmd("LoomWorkspaceSave my_ws --repos=a,b,c")

    assert.equals("my_ws", captured.name)
    assert.is_not_nil(captured.opts.repos)
    assert.equals(3, #captured.opts.repos)
    assert.equals("a", captured.opts.repos[1])
    assert.equals("b", captured.opts.repos[2])
    assert.equals("c", captured.opts.repos[3])
  end)

  it("LoomCleanup parses --dry-run flag", function()
    core.cleanup = function(opts)
      captured = { opts = opts }
    end

    vim.cmd("LoomCleanup --dry-run")

    assert.is_true(captured.opts.dry_run)
  end)

  it("LoomSave overwrite prompts and overwrites when selected", function()
    ensure_deleted("cmd_overwrite")

    -- first save
    core.save("cmd_overwrite", {})
    assert.is_true(storage.snapshot_exists("cmd_overwrite"))

    -- mock to capture the second save
    local second_captured
    core.save = function(name, opts)
      second_captured = { name = name, opts = opts }
      -- call real save to actually overwrite
      orig_save(name, opts)
    end

    -- simulate user selecting "overwrite" (first option)
    select_idx = 1
    vim.cmd("LoomSave cmd_overwrite --note='second'")

    assert.equals("cmd_overwrite", second_captured.name)
    assert.equals("second", second_captured.opts.note)

    ensure_deleted("cmd_overwrite")
  end)

  it("LoomSave cancel does not overwrite when selected", function()
    ensure_deleted("cmd_cancel")

    -- first save with a note
    core.save("cmd_cancel", { note = "first" })
    assert.is_true(storage.snapshot_exists("cmd_cancel"))

    -- verify first note
    local meta1 = storage.read_json(storage.snapshot_dir("cmd_cancel") .. "/meta.json")
    assert.equals("first", meta1.note)

    -- simulate user selecting "cancel" (third option)
    select_idx = 3
    vim.cmd("LoomSave cmd_cancel --note='second'")

    -- verify note unchanged
    local meta2 = storage.read_json(storage.snapshot_dir("cmd_cancel") .. "/meta.json")
    assert.equals("first", meta2.note)

    ensure_deleted("cmd_cancel")
  end)
end)
