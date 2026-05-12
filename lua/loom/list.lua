local M = {}

local TIME_THRESHOLDS = {
  { 60, "just now" },
  { 3600, function(m) return string.format("%d min%s ago", m, m > 1 and "s" or "") end, 60 },
  { 86400, function(h) return string.format("%d hour%s ago", h, h > 1 and "s" or "") end, 3600 },
  { 172800, "yesterday" },
  { 604800, function(d) return string.format("%d days ago", d) end, 86400 },
  { 2592000, function(w) return string.format("%d week%s ago", w, w > 1 and "s" or "") end, 604800 },
}

-- On macOS/BSD, strptime parses UTC time as local time. Detect and compute offset.
local function needs_utc_offset()
  local epoch = vim.fn.strptime("%Y-%m-%dT%H:%M:%SZ", "1970-01-01T00:00:00Z")
  return epoch ~= 0
end

local NEEDS_UTC_OFFSET = needs_utc_offset()

local function get_utc_offset()
  ---@diagnostic disable-next-line: param-type-mismatch
  local now = os.time()
  ---@diagnostic disable-next-line: param-type-mismatch
  local utc_as_local = os.time(os.date("!*t", now))
  return os.difftime(now, utc_as_local)
end

local UTC_OFFSET = NEEDS_UTC_OFFSET and get_utc_offset() or 0

---@param iso_timestamp string
---@return string
function M.format_relative_time(iso_timestamp)
  local ok, parsed = pcall(vim.fn.strptime, "%Y-%m-%dT%H:%M:%SZ", iso_timestamp)
  if ok and parsed and parsed > 0 then
    if NEEDS_UTC_OFFSET then
      parsed = parsed + UTC_OFFSET
    end
  else
    ok, parsed = pcall(vim.fn.strptime, "%Y-%m-%dT%H:%M:%S+%%z", iso_timestamp)
    if not ok or parsed == 0 then
      return iso_timestamp
    end
  end

  local diff = vim.fn.localtime() - parsed
  for _, threshold in ipairs(TIME_THRESHOLDS) do
    local limit, label, divisor = threshold[1], threshold[2], threshold[3]
    if diff < limit then
      if type(label) == "function" then
        return label(math.floor(diff / divisor))
      end
      return label
    end
  end

  local months = math.floor(diff / 2592000)
  return string.format("%d month%s ago", months, months > 1 and "s" or "")
end

---@class SnapshotItem
---@field name string
---@field branch string|nil
---@field time string|nil
---@field note string|nil

---@param item SnapshotItem
---@return string
function M.format_snapshot(item)
  local parts = { item.name }
  if item.branch then
    table.insert(parts, "  (" .. item.branch .. ")")
  end
  if item.time then
    table.insert(parts, "  " .. M.format_relative_time(item.time))
  end
  if item.note and item.note ~= "" then
    local short = item.note:sub(1, 40)
    if #item.note > 40 then
      short = short .. "..."
    end
    table.insert(parts, "  [" .. short .. "]")
  end
  return table.concat(parts)
end

---@param items SnapshotItem[]
---@param on_select fun(name: string)|nil
function M.select_snapshot(items, on_select)
  vim.ui.select(items, {
    prompt = "Select snapshot:",
    format_item = M.format_snapshot,
  }, function(choice)
    if choice and on_select then
      on_select(choice.name)
    end
  end)
end

---@class WorkspaceItem
---@field name string
---@field repo_count number
---@field updated_at string|nil

---@param item WorkspaceItem
---@return string
local function format_workspace(item)
  local parts = { item.name .. "  (" .. item.repo_count .. " repos)" }
  if item.updated_at then
    table.insert(parts, "  " .. M.format_relative_time(item.updated_at))
  end
  return table.concat(parts)
end

---@param items WorkspaceItem[]
---@param on_select fun(name: string)
function M.select_workspace(items, on_select)
  vim.ui.select(items, {
    prompt = "Select workspace:",
    format_item = format_workspace,
  }, function(choice)
    if choice then
      on_select(choice.name)
    end
  end)
end

return M
