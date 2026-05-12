-- core.lua is the orchestration layer: coordinates capture → storage → restore → git,
-- handling user confirmation, rollback, and branch mismatch across modules.
local M = {}

-- delegates to capture/* modules, persists via storage.atomic_write_dir();
-- on failure must not leave a partially-written directory behind.
function M.save(name, opts)
  vim.notify("LoomSave: not yet implemented (name=" .. tostring(name) .. ")", vim.log.levels.WARN)
end

-- before loading, check git branch: if snapshot branch differs from current,
-- prompt for explicit authorization; silent checkout is prohibited.
function M.load(name)
  vim.notify("LoomLoad: not yet implemented (name=" .. tostring(name) .. ")", vim.log.levels.WARN)
end

function M.list()
  vim.notify("LoomList: not yet implemented", vim.log.levels.WARN)
end

function M.delete(name)
  vim.notify("LoomDelete: not yet implemented (name=" .. tostring(name) .. ")", vim.log.levels.WARN)
end

function M.rename(old_name, new_name)
  vim.notify("LoomRename: not yet implemented", vim.log.levels.WARN)
end

function M.peek(name)
  vim.notify("LoomPeek: not yet implemented", vim.log.levels.WARN)
end

function M.current()
  vim.notify("LoomCurrent: not yet implemented", vim.log.levels.WARN)
end

-- workspace_save calls save() per repo, then writes a cross-repo index file.
function M.workspace_save(name, opts)
  vim.notify("LoomWorkspaceSave: not yet implemented", vim.log.levels.WARN)
end

-- loads current repo fully; other repos only update .runtime state for statusboard,
-- they are not auto-restored to avoid unexpected context switches.
function M.workspace_load(name)
  vim.notify("LoomWorkspaceLoad: not yet implemented", vim.log.levels.WARN)
end

function M.workspace_list()
  vim.notify("LoomWorkspaceList: not yet implemented", vim.log.levels.WARN)
end

function M.workspace_delete(name)
  vim.notify("LoomWorkspaceDelete: not yet implemented", vim.log.levels.WARN)
end

function M.workspace_status()
  vim.notify("LoomWorkspaceStatus: not yet implemented", vim.log.levels.WARN)
end

-- switch: save current state first, then handle branch checkout;
-- confirm_checkout must be respected before any git operation.
function M.switch(target)
  vim.notify("LoomSwitch: not yet implemented", vim.log.levels.WARN)
end

return M
