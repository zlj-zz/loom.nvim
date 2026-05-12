local M = {}

local storage = require("loom.storage")

function M.check()
  vim.health.start("loom.nvim")

  local config = require("loom").get_config()
  if not config or not config.data_dir then
    vim.health.error("loom.setup() has not been called")
    return
  end

  -- 0.9+ required for APIs used in capture/restore (e.g. nvim_buf_set_name behavior)
  local nvim_version = vim.version()
  if nvim_version.major >= 0 and nvim_version.minor >= 9 then
    vim.health.ok("Neovim version: " .. tostring(nvim_version))
  else
    vim.health.error("Neovim 0.9+ required, found: " .. tostring(nvim_version))
  end

  if vim.fn.executable("git") == 1 then
    local git_version = vim.fn.system("git --version"):gsub("\n", "")
    vim.health.ok("Git: " .. git_version)
  else
    vim.health.warn("Git not found (required for branch operations)")
  end

  -- atomic_write_dir requires write permission; fail early if the directory is read-only
  local data_dir = storage.data_dir()
  if vim.fn.isdirectory(data_dir) == 1 then
    if vim.fn.filewritable(data_dir) == 2 then
      vim.health.ok("Data directory: " .. data_dir .. " (writable)")
    else
      vim.health.error("Data directory not writable: " .. data_dir)
    end
  else
    vim.health.warn("Data directory does not exist: " .. data_dir)
  end

  -- disk space check
  ---@diagnostic disable-next-line: undefined-field
  local stat = vim.uv and vim.uv.fs_statvfs(data_dir)
  if stat then
    local avail_mb = stat.bavail * stat.bsize / (1024 * 1024)
    local avail_gb = avail_mb / 1024
    if avail_mb > 100 then
      vim.health.ok(string.format("Disk space: %.1f GB available", avail_gb))
    else
      vim.health.warn(string.format("Disk space low: %.0f MB available", avail_mb))
    end
  end

  -- snapshot integrity
  local snapshots = storage.list_snapshots()
  local valid = 0
  local corrupted = {}
  for _, name in ipairs(snapshots) do
    local dir = storage.snapshot_dir(name)
    local meta_path = dir .. "/meta.json"
    local layout_path = dir .. "/layout.json"

    if vim.fn.filereadable(meta_path) ~= 1 or vim.fn.filereadable(layout_path) ~= 1 then
      table.insert(corrupted, name)
      goto next_snapshot
    end

    local meta = storage.read_json(meta_path)
    local layout = storage.read_json(layout_path)

    if meta and layout then
      valid = valid + 1
    else
      table.insert(corrupted, name)
    end

    ::next_snapshot::
  end

  if #corrupted == 0 then
    vim.health.ok("Snapshots: " .. valid .. " valid, 0 corrupted")
  else
    vim.health.warn("Snapshots: " .. valid .. " valid, " .. #corrupted .. " corrupted")
    for _, name in ipairs(corrupted) do
      vim.health.info("  - " .. name .. " (missing or invalid meta.json/layout.json)")
    end
  end
end

return M
