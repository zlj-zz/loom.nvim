local M = {}

local DEBOUNCE_MS = 5000

---@type any
local timer = nil

---@type any
local debounce_timer = nil

---@type integer[]
local autocmd_ids = {}

--- Clean up old autosaves, keeping the most recent max_keep.
---@param max_keep number
local function cleanup_old_autosaves(max_keep)
  local storage = require("loom.storage")
  local names = storage.list_autosaves()
  if #names <= max_keep then
    return
  end
  for i = 1, #names - max_keep do
    pcall(storage.delete_autosave, names[i])
  end
end

--- Perform the actual autosave.
---@return boolean saved
local function do_autosave()
  local config = require("loom").get_config()
  if not config.autosave.enabled then
    return false
  end

  local core = require("loom.core")
  local ts = os.date(config.naming.timestamp_format or "%Y%m%d_%H%M%S")
  local name = "autosave_" .. ts

  local ok = core.autosave(name, { note = "autosave" })
  if ok then
    cleanup_old_autosaves(config.autosave.max_auto_snaps or 10)
  end

  return ok
end

--- Start autosave timers and autocmds.
function M.start()
  M.stop()

  local config = require("loom").get_config()
  if not config.autosave.enabled then
    return
  end

  if config.autosave.interval_minutes and config.autosave.interval_minutes > 0 then
    timer = vim.uv.new_timer()
    if not timer then
      return
    end
    local interval_ms = config.autosave.interval_minutes * 60 * 1000
    timer:start(interval_ms, interval_ms, vim.schedule_wrap(function()
      do_autosave()
    end))
  end

  for _, event in ipairs(config.autosave.on_events or {}) do
    local id = vim.api.nvim_create_autocmd(event, {
      group = vim.api.nvim_create_augroup("loom_autosave_" .. event, { clear = true }),
      callback = function()
        if not debounce_timer then
          debounce_timer = vim.uv.new_timer()
          if not debounce_timer then
            return
          end
        end
        debounce_timer:stop()
        debounce_timer:start(DEBOUNCE_MS, 0, vim.schedule_wrap(function()
          do_autosave()
        end))
      end,
    })
    table.insert(autocmd_ids, id)
  end
end

--- Stop all autosave timers and autocmds.
function M.stop()
  if timer then
    timer:stop()
    timer:close()
    timer = nil
  end
  if debounce_timer then
    debounce_timer:stop()
    debounce_timer:close()
    debounce_timer = nil
  end
  for _, id in ipairs(autocmd_ids) do
    pcall(vim.api.nvim_del_autocmd, id)
  end
  autocmd_ids = {}
end

--- Trigger an immediate autosave (bypasses debounce).
---@return boolean saved
function M.trigger()
  return do_autosave()
end

return M
