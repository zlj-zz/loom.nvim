local M = {}

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
  if vim.fn.isdirectory(config.data_dir) == 1 then
    if vim.fn.writable(config.data_dir) == 1 then
      vim.health.ok("Data directory: " .. config.data_dir .. " (writable)")
    else
      vim.health.error("Data directory not writable: " .. config.data_dir)
    end
  else
    vim.health.warn("Data directory does not exist: " .. config.data_dir)
  end
end

return M
