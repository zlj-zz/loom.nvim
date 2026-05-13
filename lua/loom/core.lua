local M = {}

local storage = require("loom.storage")
local git = require("loom.git")
local list_ui = require("loom.list")
local workspace = require("loom.workspace")
local statusboard = require("loom.statusboard")
local capture_buffer = require("loom.capture.buffer")
local capture_layout = require("loom.capture.layout")
local capture_terminal = require("loom.capture.terminal")
local restore_buffer = require("loom.restore.buffer")
local restore_layout = require("loom.restore.layout")
local external_traces = require("loom.capture.external_traces")

local DIFF_PATCH = "diff.patch"
local DIFF_STAGED_PATCH = "diff_staged.patch"
local UNTRACKED_DIR = "untracked"

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
  local ok, traces = pcall(external_traces.capture)
  return {
    snapshot_id = uuid(),
    timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    branch = git.current_branch(),
    repo_name = git.current_repo_name(),
    commit = git.current_commit(),
    note = note,
    nvim_version = tostring(vim.version()),
    external_traces = ok and traces or nil,
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
---@param opts {note: string|nil, silent: boolean|nil}
---@param dir_override string|nil
local function do_save(name, opts, dir_override)
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
  local dir = dir_override or storage.snapshot_dir(name)

  local ok, err = storage.atomic_write_dir(dir, function(tmp)
    storage.write_json(tmp .. "/meta.json", meta)
    storage.write_json(tmp .. "/buffers.json", buffers)
    storage.write_json(tmp .. "/layout.json", layout)
    if #terminals > 0 then
      storage.write_json(tmp .. "/terminals.json", terminals)
    end

    if config.save.capture_git_diff then
      local staged_result = git.diff_cached()
      if staged_result.success and staged_result.stdout ~= "" then
        vim.fn.writefile(vim.split(staged_result.stdout, "\n", { plain = true }), tmp .. "/" .. DIFF_STAGED_PATCH)
      end
      local diff_result = git.diff_unstaged()
      if diff_result.success and diff_result.stdout ~= "" then
        vim.fn.writefile(vim.split(diff_result.stdout, "\n", { plain = true }), tmp .. "/" .. DIFF_PATCH)
      end
    end

    if config.save.capture_untracked then
      local untracked = git.untracked_files()
      local total_size = 0
      local max_bytes = (config.save.max_untracked_total_mb or 10) * 1024 * 1024
      for _, file in ipairs(untracked) do
        local src = vim.fn.getcwd() .. "/" .. file
        local size = vim.fn.getfsize(src)
        if size > 0 then
          total_size = total_size + size
          if total_size <= max_bytes then
            local dst = tmp .. "/" .. UNTRACKED_DIR .. "/" .. file
            storage.copy_file(src, dst)
          end
        end
      end
    end
  end)

  if not ok then
    vim.notify("Failed to save snapshot: " .. tostring(err), vim.log.levels.ERROR)
    return false
  end

  if not opts.silent then
    vim.notify("Snapshot saved: " .. name, vim.log.levels.INFO)
    require("loom").events.emit("on_save", { name = name, branch = meta.branch })
  end
  return true
end

--- Internal load routine (no branch checks, no UI).
---@param buffers table
---@param layout table
---@param name string
---@param meta table
local function do_load(buffers, layout, name, meta)
  local config = require("loom").get_config()
  local dir = storage.snapshot_dir(name)

  if config.load.restore_git_diff then
    local has_changes = git.has_uncommitted_changes()
    if has_changes then
      vim.notify(
        "Working directory has changes; skipping diff apply. Stash or commit first.",
        vim.log.levels.WARN
      )
    else
      local function try_apply_patch(path, apply_opts, label)
        local check = git.apply_patch(path, { check = true })
        if check.success then
          git.apply_patch(path, apply_opts)
        elseif check.exit_code ~= 128 then
          vim.notify("Snapshot " .. label .. " diff cannot be applied: " .. check.stdout, vim.log.levels.WARN)
        end
      end

      try_apply_patch(dir .. "/" .. DIFF_STAGED_PATCH, { index = true }, "staged")
      try_apply_patch(dir .. "/" .. DIFF_PATCH, {}, "unstaged")
    end

    local untracked_dir = dir .. "/" .. UNTRACKED_DIR
    if vim.fn.isdirectory(untracked_dir) == 1 then
      local files = vim.fn.glob(untracked_dir .. "/**", false, true)
      for _, src in ipairs(files) do
        if vim.fn.isdirectory(src) ~= 1 then
          local rel = src:sub(#untracked_dir + 2)
          local dst = vim.fn.getcwd() .. "/" .. rel
          if not storage.copy_file(src, dst) then
            vim.notify("Failed to restore untracked file: " .. rel, vim.log.levels.WARN)
          end
        end
      end
    end
  end

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
    return true
  end

  return do_save(name, opts)
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

--- Resolve workspace name; prompts when absent.
---@param name string|nil
---@param cb fun(resolved: string)
local function resolve_workspace_name(name, cb)
  if name and name ~= "" then
    cb(name)
    return
  end
  local names = workspace.list()
  if #names == 1 then
    cb(names[1])
    return
  end
  if #names == 0 then
    vim.ui.input({ prompt = "Workspace name: " }, function(input)
      if input and input ~= "" then
        cb(input)
      end
    end)
    return
  end
  list_ui.select_workspace(vim.tbl_map(function(n)
    local ws = workspace.read(n)
    return { name = n, repo_count = ws and workspace.repo_count(ws) or 0, updated_at = ws and ws.updated_at }
  end, names), cb)
end

---@param resolved_name string
---@param ws Workspace
local function show_statusboard(resolved_name, ws)
  local _, current_repo_path = git.current_repo_name()
  local repos = workspace.list_repos(ws)

  local items = {}
  for _, entry in ipairs(repos) do
    table.insert(items, {
      repo_name = entry.name,
      path = entry.path,
      branch = entry.branch,
      snapshot = entry.snapshot,
      is_current = current_repo_path == entry.path,
    })
  end

  statusboard.open(resolved_name, items, function(action, item)
    if not item then
      return
    end
    if action == "load" then
      if item.snapshot then
        if vim.fn.getcwd() ~= item.path then
          local ok_cd = pcall(function()
            vim.cmd("cd " .. vim.fn.fnameescape(item.path))
          end)
          if not ok_cd then
            vim.notify("Failed to change directory to " .. item.path, vim.log.levels.ERROR)
            return
          end
        end
        M.load(item.snapshot)
      else
        vim.notify("No snapshot for " .. item.repo_name, vim.log.levels.WARN)
      end
    elseif action == "delete" then
      if item.snapshot then
        M.delete(item.snapshot)
        workspace.clear_snapshot(ws, item.path)
        workspace.write(ws)
        show_statusboard(resolved_name, ws)
      end
    elseif action == "refresh" then
      local fresh = workspace.read(resolved_name)
      if fresh then
        show_statusboard(resolved_name, fresh)
      end
    end
  end)
end

---@param name string|nil
---@param opts {repos: string[]|nil}
function M.workspace_save(name, opts)
  opts = opts or {}

  resolve_workspace_name(name, function(resolved_name)
    local repo_name, repo_path = git.current_repo_name()
    if not repo_path then
      vim.notify("Not in a git repository", vim.log.levels.ERROR)
      return
    end

    local config = require("loom").get_config()
    local ts = tostring(os.date(config.naming.timestamp_format or "%Y%m%d_%H%M%S"))
    local snap_name = resolved_name .. "_" .. repo_name .. "_" .. ts

    local saved = do_save(snap_name, { note = "Workspace: " .. resolved_name })
    if not saved then
      return
    end

    local ws = workspace.get_or_create(resolved_name)
    workspace.upsert_repo(ws, repo_path, snap_name)

    local ok, err = workspace.write(ws)
    if ok then
      vim.notify("Workspace saved: " .. resolved_name, vim.log.levels.INFO)
      require("loom").events.emit("on_workspace_save", { name = resolved_name, repo = repo_path, snapshot = snap_name })
    else
      vim.notify("Failed to save workspace: " .. tostring(err), vim.log.levels.ERROR)
    end
  end)
end

---@param name string|nil
function M.workspace_load(name)
  resolve_workspace_name(name, function(resolved_name)
    local ws = workspace.read(resolved_name)
    if not ws then
      vim.notify("Workspace not found: " .. resolved_name, vim.log.levels.ERROR)
      return
    end

    local _, repo_path = git.current_repo_name()
    if repo_path then
      local entry = workspace.get_repo(ws, repo_path)
      if entry and entry.snapshot then
        M.load(entry.snapshot)
      else
        vim.notify("No snapshot for current repo in workspace: " .. resolved_name, vim.log.levels.WARN)
      end
    end

    show_statusboard(resolved_name, ws)
  end)
end

---@param on_select fun(name: string)|nil
function M.workspace_list(on_select)
  local names = workspace.list()
  if #names == 0 then
    vim.notify("No workspaces found", vim.log.levels.INFO)
    return
  end

  local items = {}
  for _, n in ipairs(names) do
    local ws = workspace.read(n)
    table.insert(items, {
      name = n,
      repo_count = ws and workspace.repo_count(ws) or 0,
      updated_at = ws and ws.updated_at,
    })
  end

  list_ui.select_workspace(items, on_select or function(selected)
    vim.notify("Selected workspace: " .. selected, vim.log.levels.INFO)
  end)
end

---@param name string|nil
function M.workspace_delete(name)
  resolve_workspace_name(name, function(resolved_name)
    local ok, err = workspace.delete(resolved_name)
    if ok then
      vim.notify("Deleted workspace: " .. resolved_name, vim.log.levels.INFO)
    else
      vim.notify("Failed to delete workspace: " .. tostring(err), vim.log.levels.ERROR)
    end
  end)
end

---@param name string|nil
function M.workspace_status(name)
  resolve_workspace_name(name, function(resolved_name)
    local ws = workspace.read(resolved_name)
    if not ws then
      vim.notify("Workspace not found: " .. resolved_name, vim.log.levels.ERROR)
      return
    end
    show_statusboard(resolved_name, ws)
  end)
end

--- Import recent files from another IDE into nvim buffers.
---@param source string|nil "jetbrains", "vscode", "auto", or nil
function M.import(source)
  source = source or "auto"

  local function detect_source()
    if vim.fn.isdirectory(".idea") == 1 then
      return "jetbrains"
    end
    if vim.fn.isdirectory(".vscode") == 1 then
      return "vscode"
    end
    return nil
  end

  if source == "auto" then
    source = detect_source()
    if not source then
      vim.notify("No IDE workspace detected (.idea/ or .vscode/)", vim.log.levels.WARN)
      return
    end
  end

  local files = {}

  if source == "jetbrains" then
    local traces = external_traces.capture()
    local jetbrains = traces and traces.jetbrains
    if jetbrains and jetbrains.recent_files then
      files = jetbrains.recent_files
    end
  elseif source == "vscode" then
    local result = vim.fn.systemlist({ "git", "ls-files" })
    if vim.v.shell_error == 0 then
      local cwd = vim.fn.getcwd()
      for _, line in ipairs(result) do
        line = vim.trim(line)
        if line ~= "" then
          table.insert(files, cwd .. "/" .. line)
        end
      end
    else
      vim.notify("VSCode import: no git-tracked files found", vim.log.levels.WARN)
      return
    end
  else
    vim.notify("Unknown import source: " .. source, vim.log.levels.ERROR)
    return
  end

  if #files == 0 then
    vim.notify("No files to import from " .. source, vim.log.levels.WARN)
    return
  end

  for _, path in ipairs(files) do
    if vim.fn.filereadable(path) == 1 then
      pcall(function()
        vim.cmd("edit " .. vim.fn.fnameescape(path))
      end)
    end
  end

  vim.notify("Imported " .. #files .. " file(s) from " .. source, vim.log.levels.INFO)
end

--- Run cleanup on old snapshots.
---@param opts {dry_run: boolean}|nil
function M.cleanup(opts)
  require("loom.cleanup").cleanup(opts)
end

--- Save an autosave snapshot to the autosaves directory.
---@param name string|nil
---@param opts {note: string|nil}|nil
---@return boolean
function M.autosave(name, opts)
  opts = opts or {}
  name = name or resolve_name(nil, "autosave_")
  local autosave_opts = vim.tbl_extend("force", opts, { silent = true })
  local dir = storage.autosave_dir(name)
  return do_save(name, autosave_opts, dir)
end

-- Expose internal functions for unit testing
M._resolve_target = resolve_target
M._execute_switch = execute_switch

return M
