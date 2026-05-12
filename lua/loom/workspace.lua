local M = {}

local storage = require("loom.storage")
local git = require("loom.git")

---@class WorkspaceRepoEntry
---@field name string
---@field path string
---@field branch string|nil
---@field snapshot string
---@field updated_at string

---@class Workspace
---@field name string
---@field created_at string
---@field updated_at string
---@field repos table<string, WorkspaceRepoEntry>

---@param name string
---@return Workspace|nil
function M.read(name)
  local path = storage.workspace_file(name)
  local data = storage.read_json(path)
  if not data then
    return nil
  end
  if type(data.repos) ~= "table" then
    return nil
  end
  return data
end

---@param name string
---@return Workspace
function M.get_or_create(name)
  local ws = M.read(name)
  if ws then
    return ws
  end
  local ts = tostring(os.date("!%Y-%m-%dT%H:%M:%SZ"))
  return {
    name = name,
    created_at = ts,
    updated_at = ts,
    repos = {},
  }
end

---@param workspace Workspace
---@return boolean success, string|nil error
function M.write(workspace)
  local path = storage.workspace_file(workspace.name)
  return storage.write_json(path, workspace)
end

---@return string[]
function M.list()
  return storage.list_workspaces()
end

---@param name string
---@return boolean success, string|nil error
function M.delete(name)
  return storage.delete_workspace(name)
end

---@param workspace Workspace
---@param repo_path string
---@param snapshot_name string
function M.upsert_repo(workspace, repo_path, snapshot_name)
  local ts = tostring(os.date("!%Y-%m-%dT%H:%M:%SZ"))
  workspace.repos[repo_path] = {
    name = vim.fn.fnamemodify(repo_path, ":t"),
    path = repo_path,
    branch = git.current_branch(),
    snapshot = snapshot_name,
    updated_at = ts,
  }
  workspace.updated_at = ts
end

---@param workspace Workspace
---@param repo_path string
---@return WorkspaceRepoEntry|nil
function M.get_repo(workspace, repo_path)
  return workspace.repos[repo_path]
end

---@param workspace Workspace
---@param repo_path string
function M.clear_snapshot(workspace, repo_path)
  local entry = workspace.repos[repo_path]
  if entry then
    entry.snapshot = nil
    workspace.updated_at = tostring(os.date("!%Y-%m-%dT%H:%M:%SZ"))
  end
end

---@param workspace Workspace
---@return number
function M.repo_count(workspace)
  return vim.tbl_count(workspace.repos)
end

---@param workspace Workspace
---@return WorkspaceRepoEntry[]
function M.list_repos(workspace)
  local items = {}
  for _, entry in pairs(workspace.repos) do
    table.insert(items, entry)
  end
  table.sort(items, function(a, b)
    return a.path < b.path
  end)
  return items
end

return M
