local M = {}

local storage = require("loom.storage")

--- Parse ISO8601 timestamp to unix seconds.
--- On macOS/BSD, strptime parses UTC time as local time; compensate.
---@param iso string
---@return number|nil
local function parse_timestamp(iso)
  local ok, parsed = pcall(vim.fn.strptime, "%Y-%m-%dT%H:%M:%SZ", iso)
  if ok and parsed and parsed > 0 then
    -- macOS/BSD strptime treats 'Z' as literal and parses as local time.
    local epoch = vim.fn.strptime("%Y-%m-%dT%H:%M:%SZ", "1970-01-01T00:00:00Z")
    if epoch ~= 0 then
      local now = os.time()
      ---@diagnostic disable-next-line: param-type-mismatch
      local offset = os.difftime(now, os.time(os.date("!*t", now)))
      parsed = parsed + offset
    end
    return parsed
  end
  return nil
end

---@class CleanupItem
---@field name string
---@field reason string

--- Collect snapshots to delete based on age and count limits.
---@return CleanupItem[]
local function collect_targets()
  local config = require("loom").get_config()
  local snapshots = storage.list_snapshots()
  local to_delete = {}
  local marked = {}

  -- Single pass: read all metadata and cache
  ---@type table<string, {meta: table|nil, time: number}>
  local cached = {}
  for _, name in ipairs(snapshots) do
    local meta = storage.read_json(storage.snapshot_dir(name) .. "/meta.json")
    local time = 0
    if meta and meta.timestamp then
      local parsed = parse_timestamp(meta.timestamp)
      if parsed then
        time = parsed
      end
    end
    cached[name] = { meta = meta, time = time }
  end

  -- Age-based cleanup
  local max_age_days = config.cleanup.auto_cleanup_after_days
  if max_age_days and max_age_days > 0 then
    local now = os.time()
    for _, name in ipairs(snapshots) do
      local item = cached[name]
      if item.time > 0 then
        local age_days = (now - item.time) / 86400
        if age_days > max_age_days then
          marked[name] = true
          table.insert(to_delete, { name = name, reason = "expired (" .. math.floor(age_days) .. " days)" })
        end
      end
    end
  end

  -- Count-based cleanup
  local max_count = config.cleanup.max_snapshots
  if max_count and max_count > 0 then
    local with_time = {}
    for _, name in ipairs(snapshots) do
      table.insert(with_time, { name = name, time = cached[name].time })
    end
    table.sort(with_time, function(a, b)
      return a.time > b.time
    end)

    for i = max_count + 1, #with_time do
      local item = with_time[i]
      if not marked[item.name] then
        marked[item.name] = true
        table.insert(to_delete, { name = item.name, reason = "exceeds max_snapshots" })
      end
    end
  end

  return to_delete
end

--- Run cleanup: delete old or excess snapshots.
---@param opts {dry_run: boolean}|nil
function M.cleanup(opts)
  opts = opts or {}
  local targets = collect_targets()

  if #targets == 0 then
    vim.notify("Cleanup: nothing to delete", vim.log.levels.INFO)
    return
  end

  if opts.dry_run then
    local lines = { "Cleanup (dry run): would delete " .. #targets .. " snapshot(s):" }
    for _, item in ipairs(targets) do
      table.insert(lines, "  - " .. item.name .. " (" .. item.reason .. ")")
    end
    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
    return
  end

  local deleted = 0
  for _, item in ipairs(targets) do
    local ok = storage.delete_snapshot(item.name)
    if ok then
      deleted = deleted + 1
    end
  end

  vim.notify("Cleanup: deleted " .. deleted .. "/" .. #targets .. " snapshot(s)", vim.log.levels.INFO)
end

return M
