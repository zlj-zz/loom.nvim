local M = {}

local storage = require("loom.storage")
local git = require("loom.git")
local list_ui = require("loom.list")
local capture_buffer = require("loom.capture.buffer")
local capture_layout = require("loom.capture.layout")
local capture_terminal = require("loom.capture.terminal")
local restore_buffer = require("loom.restore.buffer")
local restore_layout = require("loom.restore.layout")

--- Generate a simple UUID v4 using vim.fn.rand to avoid global RNG state.
---@return string
local function uuid()
  local function r()
    return vim.fn.rand() % 0x10000
  end
  return string.format("%04x%04x-%04x-4%03x-%04x-%04x%04x%04x",
    r(), r(), r(), r() % 0x1000, r(), r(), r(), r())
end

--- Resolve snapshot name; falls back to timestamp when absent.
---@param name string|nil
---@param prefix_override string|nil
---@return string resolved
local function resolve_name(name, prefix_override)
  if name and name ~= "" then
    return name
  end
  local config = require("loom").get_config()
  local ts = os.date(config.naming.timestamp_format or "%Y%m%d_%H%M%S")
  local prefix = prefix_override or config.naming.default_prefix or ""
  return prefix .. ts
end

--- Build snapshot metadata.
---@param note string|nil
---@return table meta
local function build_meta(note)
  return {
    snapshot_id = uuid(),
    timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    branch = git.current_branch(),
    repo_name = git.current_repo_name(),
    commit = git.current_commit(),
    note = note,
    nvim_version = tostring(vim.version()),
  }
end

--- Checkout a branch, creating it if it does not exist locally.
---@param branch string
---@return GitResult
local function checkout_branch(branch)
  local bt = git.branch_exists(branch)
  if bt == "local" then
    return git.checkout(branch, false)
  elseif bt == "remote" then
    return git.checkout_remote(branch)
  else
    return git.checkout(branch, true)
  end
end

--- Internal save routine (no overwrite checks, no UI).
---@param name string
---@param opts {note: string|nil}
local function do_save(name, opts)
  opts = opts or {}
  local config = require("loom").get_config()

  local buffers = capture_buffer.capture_all()
  local layout = capture_layout.capture()

  local terminals = {}
  if config.save.terminals then
    for _, buf in ipairs(buffers) do
      if buf.buftype == "terminal" and not buf.excluded then
        table.insert(terminals, capture_terminal.capture(buf.bufnr))
      end
    end
  end

  local meta = build_meta(opts.note)
  local dir = storage.snapshot_dir(name)

  local ok, err = storage.atomic_write_dir(dir, function(tmp)
    storage.write_json(tmp .. "/meta.json", meta)
    storage.write_json(tmp .. "/buffers.json", buffers)
    storage.write_json(tmp .. "/layout.json", layout)
    if #terminals > 0 then
      storage.write_json(tmp .. "/terminals.json", terminals)
    end
  end)

  if not ok then
    vim.notify("Failed to save snapshot: " .. tostring(err), vim.log.levels.ERROR)
    return
  end

  vim.notify("Snapshot saved: " .. name, vim.log.levels.INFO)
  require("loom").events.emit("on_save", { name = name, branch = meta.branch })
end

--- Internal load routine (no branch checks, no UI).
---@param buffers table
---@param layout table
---@param name string
---@param meta table
local function do_load(buffers, layout, name, meta)
  local bufnr_map, cursor_map = restore_buffer.restore_all(buffers)
  restore_layout.restore(layout, bufnr_map, cursor_map)
  vim.notify("Snapshot loaded: " .. name, vim.log.levels.INFO)
  require("loom").events.emit("on_load", { name = name, branch = meta.branch })
end

--- Execute the actual checkout + optional load.
---@param target string
---@param kind "snapshot"|"local"|"remote"|"new"
---@param stashed boolean
local function execute_switch(target, kind, stashed)
  local result

  if kind == "snapshot" then
    local meta = storage.read_json(storage.snapshot_dir(target) .. "/meta.json")
    local snap_branch = meta and meta.branch
    if snap_branch then
      result = checkout_branch(snap_branch)
    else
      M.load(target)
      return
    end
  elseif kind == "local" then
    result = git.checkout(target, false)
  elseif kind == "remote" then
    result = git.checkout_remote(target)
  else
    result = git.checkout(target, true)
  end

  if result and not result.success then
    vim.notify("Switch failed: " .. result.stdout, vim.log.levels.ERROR)
    if stashed then
      git.stash_pop()
    end
    return
  end

  if kind == "snapshot" then
    M.load(target)
  end

  vim.notify("Switched to: " .. target, vim.log.levels.INFO)
end

--- Continuation of switch after optional stash prompt.
---@param target string
---@param kind "snapshot"|"local"|"remote"|"new"
---@param stashed boolean
---@param config LoomConfig
local function continue_switch(target, kind, stashed, config)
  if config.switch.confirm_checkout then
    vim.ui.select({ "yes", "no" }, {
      prompt = "Switch to '" .. target .. "'?",
    }, function(choice)
      if choice == "yes" then
        execute_switch(target, kind, stashed)
      elseif stashed then
        git.stash_pop()
      end
    end)
    return
  end

  execute_switch(target, kind, stashed)
end

--- Resolve target type for switch.
---@param target string
---@return "snapshot"|"local"|"remote"|"new"
local function resolve_target(target)
  if storage.snapshot_exists(target) then
    return "snapshot"
  end
  local bt = git.branch_exists(target)
  if bt == "local" then
    return "local"
  elseif bt == "remote" then
    return "remote"
  end
  return "new"
end

function M.save(name, opts)
  opts = opts or {}
  name = resolve_name(name)

  if storage.snapshot_exists(name) then
    vim.ui.select({ "overwrite", "rename", "cancel" }, {
      prompt = "Snapshot '" .. name .. "' already exists:",
    }, function(choice)
      if choice == "overwrite" then
        do_save(name, opts)
      elseif choice == "rename" then
        vim.ui.input({ prompt = "New name: " }, function(new_name)
          if new_name and new_name ~= "" then
            M.save(new_name, opts)
          end
        end)
      end
    end)
    return
  end

  do_save(name, opts)
end

function M.load(name)
  if not name then
    M.list(function(selected)
      if selected then
        M.load(selected)
      end
    end)
    return
  end

  local dir = storage.snapshot_dir(name)
  local meta = storage.read_json(dir .. "/meta.json")
  if not meta then
    vim.notify("Snapshot not found: " .. name, vim.log.levels.ERROR)
    return
  end

  local current_branch = git.current_branch()
  local snapshot_branch = meta.branch

  if snapshot_branch and snapshot_branch ~= current_branch then
    local actions = {}
    local options = {}

    local function add_option(label, action_fn)
      table.insert(options, label)
      actions[label] = action_fn
    end

    add_option("checkout branch '" .. snapshot_branch .. "' and load", function()
      return git.checkout(snapshot_branch, false)
    end)
    add_option("load only (keep current branch)", nil)
    add_option("cancel", nil)

    local branch_type = git.branch_exists(snapshot_branch)
    if branch_type == "remote" then
      table.insert(options, 3, "checkout from remote")
      actions["checkout from remote"] = function()
        return git.checkout_remote(snapshot_branch)
      end
    elseif branch_type == "none" then
      table.insert(options, 3, "create new branch '" .. snapshot_branch .. "'")
      actions["create new branch '" .. snapshot_branch .. "'"] = function()
        return git.checkout(snapshot_branch, true)
      end
    end

    vim.ui.select(options, {
      prompt = "Snapshot saved on branch '"
        .. snapshot_branch
        .. "' (current: '"
        .. (current_branch or "none")
        .. "'). Action:",
    }, function(choice)
      if not choice or choice == "cancel" then
        return
      end

      local action = actions[choice]
      if action then
        local result = action()
        if not result.success then
          vim.notify("Checkout failed: " .. result.stdout, vim.log.levels.ERROR)
          return
        end
      end

      local buffers = storage.read_json(dir .. "/buffers.json")
      local layout = storage.read_json(dir .. "/layout.json")
      if not buffers or not layout then
        vim.notify("Snapshot corrupted: " .. name, vim.log.levels.ERROR)
        return
      end
      do_load(buffers, layout, name, meta)
    end)
    return
  end

  local buffers = storage.read_json(dir .. "/buffers.json")
  local layout = storage.read_json(dir .. "/layout.json")
  if not buffers or not layout then
    vim.notify("Snapshot corrupted: " .. name, vim.log.levels.ERROR)
    return
  end
  do_load(buffers, layout, name, meta)
end

---@param on_select fun(name: string)|nil
function M.list(on_select)
  local names = storage.list_snapshots()
  if #names == 0 then
    vim.notify("No snapshots found", vim.log.levels.INFO)
    return
  end

  local items = {}
  for _, n in ipairs(names) do
    local meta = storage.read_json(storage.snapshot_dir(n) .. "/meta.json")
    table.insert(items, {
      name = n,
      branch = meta and meta.branch,
      time = meta and meta.timestamp,
      note = meta and meta.note,
    })
  end

  list_ui.select_snapshot(items, on_select)
end

function M.delete(name)
  if not name or name == "" then
    vim.notify("Usage: LoomDelete <name>", vim.log.levels.ERROR)
    return
  end
  local ok, err = storage.delete_snapshot(name)
  if ok then
    vim.notify("Deleted snapshot: " .. name, vim.log.levels.INFO)
  else
    vim.notify("Failed to delete: " .. tostring(err), vim.log.levels.ERROR)
  end
end

function M.rename(old_name, new_name)
  if not old_name or not new_name or old_name == "" or new_name == "" then
    vim.notify("Usage: LoomRename <old> <new>", vim.log.levels.ERROR)
    return
  end
  local old_dir = storage.snapshot_dir(old_name)
  local new_dir = storage.snapshot_dir(new_name)

  local ret = vim.fn.rename(old_dir, new_dir)
  if ret == 0 then
    vim.notify("Renamed: " .. old_name .. " -> " .. new_name, vim.log.levels.INFO)
  else
    vim.notify("Rename failed (target may already exist)", vim.log.levels.ERROR)
  end
end

function M.peek(name)
  if not name then
    M.list(function(selected)
      if selected then
        M.peek(selected)
      end
    end)
    return
  end

  local meta = storage.read_json(storage.snapshot_dir(name) .. "/meta.json")
  if not meta then
    vim.notify("Snapshot not found: " .. name, vim.log.levels.ERROR)
    return
  end

  local lines = {
    "Snapshot:   " .. name,
    "  ID:        " .. (meta.snapshot_id or "n/a"),
    "  Branch:    " .. (meta.branch or "n/a"),
    "  Repo:      " .. (meta.repo_name or "n/a"),
    "  Timestamp: " .. (meta.timestamp or "n/a"),
    "  Note:      " .. (meta.note or "n/a"),
  }
  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

function M.current()
  local repo_name = git.current_repo_name()
  local branch = git.current_branch()
  local commit = git.current_commit()
  vim.notify(
    string.format("Repo: %s\nBranch: %s\nCommit: %s", repo_name or "n/a", branch or "n/a", commit or "n/a"),
    vim.log.levels.INFO
  )
end

function M.switch(target)
  if not target or target == "" then
    vim.ui.input({ prompt = "Branch or snapshot name: " }, function(input)
      if input and input ~= "" then
        M.switch(input)
      end
    end)
    return
  end

  local config = require("loom").get_config()
  local kind = resolve_target(target)

  if config.switch.auto_save then
    do_save(resolve_name(nil, "autosave_"), { note = "Auto-save before switch" })
  end

  local behavior = config.switch.auto_stash
  local stashed = false

  if behavior ~= "never" then
    local has_changes = git.has_uncommitted_changes()
    if has_changes then
      if behavior == "always" then
        local r = git.stash("loom auto-stash before switch")
        stashed = r.success
      elseif behavior == "prompt" then
        vim.ui.select({ "yes", "no" }, {
          prompt = "Uncommitted changes. Stash before switching?",
        }, function(choice)
          if choice == "yes" then
            local r = git.stash("loom auto-stash before switch")
            stashed = r.success
          end
          continue_switch(target, kind, stashed, config)
        end)
        return
      end
    end
  end

  continue_switch(target, kind, stashed, config)
end

---@diagnostic disable-next-line: unused-local
function M.workspace_save(name, opts)
  vim.notify("LoomWorkspaceSave: not yet implemented", vim.log.levels.WARN)
end

---@diagnostic disable-next-line: unused-local
function M.workspace_load(name)
  vim.notify("LoomWorkspaceLoad: not yet implemented", vim.log.levels.WARN)
end

function M.workspace_list()
  vim.notify("LoomWorkspaceList: not yet implemented", vim.log.levels.WARN)
end

---@diagnostic disable-next-line: unused-local
function M.workspace_delete(name)
  vim.notify("LoomWorkspaceDelete: not yet implemented", vim.log.levels.WARN)
end

function M.workspace_status()
  vim.notify("LoomWorkspaceStatus: not yet implemented", vim.log.levels.WARN)
end

return M
