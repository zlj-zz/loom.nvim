local M = {}

---@return string
function M.data_dir()
  local config = vim.g.loom_config
  if config and config.data_dir then
    return config.data_dir
  end
  local user = os.getenv("USER") or os.getenv("USERNAME") or "default"
  return vim.fn.stdpath("data") .. "/loom/" .. user
end

---@param name string
---@return string
function M.snapshot_dir(name)
  return M.data_dir() .. "/snapshots/" .. name
end

---@param name string
---@return string
function M.workspace_file(name)
  return M.data_dir() .. "/workspaces/" .. name .. ".json"
end

---@param name string
---@return string
function M.autosave_dir(name)
  return M.data_dir() .. "/autosaves/" .. name
end

---@return string
function M.runtime_dir()
  return M.data_dir() .. "/.runtime"
end

---@param dir string
function M.ensure_dir(dir)
  vim.fn.mkdir(dir, "p")
end

---@param dir string
---@param writer fun(tmpdir: string)
---@return boolean success, string|nil error
function M.atomic_write_dir(dir, writer)
  M.ensure_dir(vim.fn.fnamemodify(dir, ":h"))

  local tmp = dir .. ".tmp." .. vim.fn.getpid()
  local ok, err = pcall(writer, tmp)
  if not ok then
    vim.fn.delete(tmp, "rf")
    return false, err
  end

  if vim.fn.isdirectory(dir) == 1 then
    vim.fn.delete(dir, "rf")
  end

  local ret = vim.fn.rename(tmp, dir)
  if ret ~= 0 then
    vim.fn.delete(tmp, "rf")
    return false, "rename failed: " .. tmp .. " -> " .. dir
  end

  return true
end

---@param path string
---@param data table
---@return boolean success, string|nil error
function M.write_json(path, data)
  local dir = vim.fn.fnamemodify(path, ":h")
  M.ensure_dir(dir)
  local encoded = vim.json.encode(data)
  local ok = vim.fn.writefile({ encoded }, path)
  if ok ~= 0 then
    return false, "failed to write " .. path
  end
  return true
end

---@param path string
---@return table|nil
function M.read_json(path)
  if vim.fn.filereadable(path) ~= 1 then
    return nil
  end
  local lines = vim.fn.readfile(path, "b")
  local content = table.concat(lines, "\n")
  local ok, decoded = pcall(vim.json.decode, content)
  if not ok then
    return nil
  end
  return decoded
end

--- Copy a file from src to dst, creating parent directories.
---@param src string
---@param dst string
---@return boolean success
function M.copy_file(src, dst)
  local dir = vim.fn.fnamemodify(dst, ":h")
  M.ensure_dir(dir)

  local src_f = io.open(src, "rb")
  if not src_f then
    return false
  end
  local data = src_f:read("*a")
  src_f:close()

  local dst_f = io.open(dst, "wb")
  if not dst_f then
    return false
  end
  dst_f:write(data)
  dst_f:close()

  return true
end

---@return string[]
function M.list_snapshots()
  local dir = M.data_dir() .. "/snapshots"
  if vim.fn.isdirectory(dir) ~= 1 then
    return {}
  end
  local items = vim.fn.glob(dir .. "/*/", false, true)
  local names = {}
  for _, path in ipairs(items) do
    table.insert(names, vim.fn.fnamemodify(path, ":p:h:t"))
  end
  table.sort(names)
  return names
end

---@return string[]
function M.list_workspaces()
  local dir = M.data_dir() .. "/workspaces"
  if vim.fn.isdirectory(dir) ~= 1 then
    return {}
  end
  local files = vim.fn.glob(dir .. "/*.json", false, true)
  local names = {}
  for _, path in ipairs(files) do
    table.insert(names, vim.fn.fnamemodify(path, ":t:r"))
  end
  table.sort(names)
  return names
end

---@param name string
---@return boolean success, string|nil error
function M.delete_snapshot(name)
  local dir = M.snapshot_dir(name)
  if vim.fn.isdirectory(dir) == 1 then
    vim.fn.delete(dir, "rf")
    return true
  end
  return false, "snapshot not found: " .. name
end

---@param name string
---@return boolean success, string|nil error
function M.delete_workspace(name)
  local path = M.workspace_file(name)
  if vim.fn.filereadable(path) == 1 then
    vim.fn.delete(path)
    return true
  end
  return false, "workspace not found: " .. name
end

---@param name string
---@return boolean
function M.snapshot_exists(name)
  return vim.fn.isdirectory(M.snapshot_dir(name)) == 1
end

---@param name string
---@return boolean
function M.workspace_exists(name)
  return vim.fn.filereadable(M.workspace_file(name)) == 1
end

---@param name string
---@return boolean success, string|nil error
function M.delete_autosave(name)
  local dir = M.autosave_dir(name)
  if vim.fn.isdirectory(dir) == 1 then
    vim.fn.delete(dir, "rf")
    return true
  end
  return false, "autosave not found: " .. name
end

---@return string[]
function M.list_autosaves()
  local dir = M.data_dir() .. "/autosaves"
  if vim.fn.isdirectory(dir) ~= 1 then
    return {}
  end
  local items = vim.fn.glob(dir .. "/*/", false, true)
  local names = {}
  for _, path in ipairs(items) do
    table.insert(names, vim.fn.fnamemodify(path, ":p:h:t"))
  end
  table.sort(names)
  return names
end

return M
