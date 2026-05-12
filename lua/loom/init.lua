local M = {}

---@class LoomConfig
local defaults = {
  data_dir = nil,
  save = {
    terminals = true,
    scratch_buffers = true,
    unnamed_buffers = true,
    folds = false,
    max_file_size_mb = 1,
    exclude_patterns = { ".env", ".env.*", "*secret*", "*private*", "*credential*", "*.key", "*.pem" },
    exclude_by_content = { "API_KEY", "SECRET_KEY", "PRIVATE_KEY", "PASSWORD", "TOKEN=" },
    sensitive_scan_lines = 50,
  },
  load = {
    confirm_unsaved = true,
    warn_branch_mismatch = true,
    auto_cwd = true,
    restore_terminals = "readonly",
  },
  autosave = { enabled = false, interval_minutes = 30, on_events = { "BufWritePost" }, max_auto_snaps = 10 },
  cleanup = { max_snapshots = 50, auto_cleanup_after_days = 90 },
  naming = { default_prefix = "", timestamp_format = "%Y%m%d_%H%M%S" },
  workspace = {
    enabled = true,
    project_roots = { "~/projects", "~/workspace" },
    scan_depth = 2,
    status_refresh_interval = 0,
    default_repos = {},
  },
  switch = {
    auto_save = true,
    auto_stash = "prompt",
    create_branch_prompt = true,
    confirm_checkout = true,
  },
  integrations = { telescope = true, which_key = true },
}

-- expand resolves ~/env vars; resolve makes absolute paths for consistent comparison later
local function resolve_paths(project_roots)
  local resolved = {}
  for _, root in ipairs(project_roots) do
    table.insert(resolved, vim.fn.resolve(vim.fn.expand(root)))
  end
  return resolved
end

function M.setup(opts)
  local config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})

  if not config.data_dir then
    local user = os.getenv("USER") or os.getenv("USERNAME") or "default"
    config.data_dir = vim.fn.stdpath("data") .. "/loom/" .. user
  end

  config.workspace.project_roots = resolve_paths(config.workspace.project_roots)

  -- global config is the single source of truth; modules read vim.g.loom_config instead of requiring init
  vim.g.loom_config = config

  -- health check reads config.data_dir, so register after setup has resolved it
  vim.health.register("loom", function()
    require("loom.health").check()
  end)
end

function M.get_config()
  return vim.g.loom_config or vim.deepcopy(defaults)
end

return M
