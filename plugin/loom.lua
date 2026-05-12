if vim.g.loaded_loom then
  return
end
vim.g.loaded_loom = true

local core = require("loom.core")

-- nvim_create_user_command passes raw args string; we must parse --flag=value manually
---@param s string|nil
---@return string|nil
local function nil_if_empty(s)
  if not s then
    return nil
  end
  s = vim.trim(s)
  return s ~= "" and s or nil
end

---@param args string
---@return string|nil name
local function parse_name(args)
  local name = args:match("^%s*([^%-].-)%s*$") or args:match("^%s*(.-)%s*%-%-")
  return nil_if_empty(name)
end

---@param args string
---@return string|nil name, string|nil note
local function parse_save_args(args)
  local name = parse_name(args)
  local note = args:match("%-%-note=[\"'](.-)[\"']")
  return name, note
end

---@param args string
---@return string|nil name, string[]|nil repos
local function parse_workspace_args(args)
  local name = parse_name(args)
  local repos_str = args:match("%-%-repos=(.+)")
  local repos = repos_str and vim.split(vim.trim(repos_str), ",", { trimempty = true }) or nil
  return name, repos
end

---@class LoomCommand
---@field name string
---@field nargs number|string
---@field desc string
---@field fn function

-- single source of truth for all :Loom* commands; keeps registration loop DRY
---@type LoomCommand[]
local commands = {
  {
    name = "LoomSave",
    nargs = "?",
    desc = "Save current editor snapshot",
    fn = function(args)
      local name, note = parse_save_args(args)
      core.save(name, { note = note })
    end,
  },
  {
    name = "LoomLoad",
    nargs = "?",
    desc = "Load an editor snapshot",
    fn = function(args)
      core.load(nil_if_empty(args))
    end,
  },
  {
    name = "LoomList",
    nargs = 0,
    desc = "List all snapshots",
    fn = function()
      core.list()
    end,
  },
  {
    name = "LoomDelete",
    nargs = 1,
    desc = "Delete a snapshot",
    fn = function(args)
      local name = nil_if_empty(args)
      if not name then
        vim.notify("Usage: LoomDelete <name>", vim.log.levels.ERROR)
        return
      end
      core.delete(name)
    end,
  },
  {
    name = "LoomRename",
    nargs = "+",
    desc = "Rename a snapshot",
    fn = function(args)
      local old_name, new_name = args:match("^(%S+)%s+(%S+)$")
      if not old_name or not new_name then
        vim.notify("Usage: LoomRename <old> <new>", vim.log.levels.ERROR)
        return
      end
      core.rename(old_name, new_name)
    end,
  },
  {
    name = "LoomPeek",
    nargs = "?",
    desc = "Preview snapshot metadata without loading",
    fn = function(args)
      core.peek(nil_if_empty(args))
    end,
  },
  {
    name = "LoomCurrent",
    nargs = 0,
    desc = "Show current snapshot info",
    fn = function()
      core.current()
    end,
  },
  {
    name = "LoomWorkspaceSave",
    nargs = "?",
    desc = "Save workspace index across repos",
    fn = function(args)
      local name, repos = parse_workspace_args(args)
      core.workspace_save(name, { repos = repos })
    end,
  },
  {
    name = "LoomWorkspaceLoad",
    nargs = "?",
    desc = "Load workspace (auto-restore current repo, show status for others)",
    fn = function(args)
      core.workspace_load(nil_if_empty(args))
    end,
  },
  {
    name = "LoomWorkspaceList",
    nargs = 0,
    desc = "List all workspaces",
    fn = function()
      core.workspace_list()
    end,
  },
  {
    name = "LoomWorkspaceDelete",
    nargs = 1,
    desc = "Delete a workspace",
    fn = function(args)
      local name = nil_if_empty(args)
      if not name then
        vim.notify("Usage: LoomWorkspaceDelete <name>", vim.log.levels.ERROR)
        return
      end
      core.workspace_delete(name)
    end,
  },
  {
    name = "LoomWorkspaceStatus",
    nargs = 0,
    desc = "Show workspace status board",
    fn = function()
      core.workspace_status()
    end,
  },
  {
    name = "LoomSwitch",
    nargs = "?",
    desc = "Save current state and switch to branch/snapshot",
    fn = function(args)
      core.switch(nil_if_empty(args))
    end,
  },
  {
    name = "LoomImport",
    nargs = "?",
    desc = "Import IDE recent files as buffers",
    fn = function(args)
      core.import(nil_if_empty(args))
    end,
  },
  {
    name = "LoomCleanup",
    nargs = "?",
    desc = "Clean up old snapshots",
    fn = function(args)
      local dry_run = false
      if args then
        for token in args:gmatch("%S+") do
          if token == "--dry-run" then
            dry_run = true
            break
          end
        end
      end
      core.cleanup({ dry_run = dry_run })
    end,
  },
}

for _, cmd in ipairs(commands) do
  vim.api.nvim_create_user_command(cmd.name, function(opts)
    cmd.fn(opts.args)
  end, {
    nargs = cmd.nargs,
    desc = cmd.desc,
  })
end
