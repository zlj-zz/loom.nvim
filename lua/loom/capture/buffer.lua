local M = {}

---@class CapturedBuffer
---@field bufnr number
---@field name string|nil
---@field lines string[]|nil
---@field filetype string|nil
---@field buftype string|nil
---@field modified boolean
---@field cursor {line: number, col: number}|nil
---@field excluded boolean
---@field exclude_reason string|nil
---@field large_file boolean

---@return LoomConfig
local function config()
  return require("loom").get_config()
end

---@param name string
---@param patterns string[]
---@return boolean matched, string|nil pattern
local function match_patterns(name, patterns)
  for _, pat in ipairs(patterns) do
    local regex = vim.fn.glob2regpat(pat)
    if regex and vim.fn.match(name, regex) ~= -1 then
      return true, pat
    end
  end
  return false, nil
end

--- Estimate buffer size in bytes without loading all lines into Lua.
---@param bufnr number
---@param name string|nil
---@return number bytes
local function estimate_buffer_size(bufnr, name)
  if name and vim.fn.filereadable(name) == 1 then
    local size = vim.fn.getfsize(name)
    if size > 0 then
      return size
    end
  end
  local ok, last_byte = pcall(vim.api.nvim_buf_call, bufnr, function()
    return vim.fn.line2byte(vim.api.nvim_buf_line_count(bufnr) + 1)
  end)
  if ok and last_byte and last_byte > 0 then
    return last_byte - 1
  end
  return 0
end

---@param lines string[]
---@param cfg LoomConfig
---@return boolean has_sensitive, string|nil matched
local function scan_sensitive_content(lines, cfg)
  local max_lines = cfg.save.sensitive_scan_lines or 50
  for i = 1, math.min(#lines, max_lines) do
    local line = lines[i]
    for _, keyword in ipairs(cfg.save.exclude_by_content or {}) do
      if line:find(keyword, 1, true) then
        return true, keyword
      end
    end
  end
  return false, nil
end

---@param bufnr number
---@return {line: number, col: number}|nil
local function get_cursor(bufnr)
  local winnr = vim.fn.bufwinid(bufnr)
  if winnr == -1 then
    return nil
  end
  local cursor = vim.api.nvim_win_get_cursor(winnr)
  return { line = cursor[1], col = cursor[2] }
end

---@param bufnr number
---@return CapturedBuffer
function M.capture(bufnr)
  local cfg = config()
  local save_cfg = cfg.save

  local raw_name = vim.api.nvim_buf_get_name(bufnr)
  local name = raw_name ~= "" and raw_name or nil

  local buftype = vim.api.nvim_get_option_value("buftype", { buf = bufnr })
  local filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
  local modified = vim.api.nvim_get_option_value("modified", { buf = bufnr })

  local result = {
    bufnr = bufnr,
    name = name,
    filetype = filetype,
    buftype = buftype,
    modified = modified,
    excluded = false,
    exclude_reason = nil,
    large_file = false,
    lines = nil,
    cursor = nil,
  }

  local excluded_buftypes = { ["help"] = true, ["quickfix"] = true, ["prompt"] = true, ["nofile"] = true }
  if excluded_buftypes[buftype] then
    result.excluded = true
    result.exclude_reason = "buftype: " .. buftype
    return result
  end

  if buftype == "terminal" then
    if not save_cfg.terminals then
      result.excluded = true
      result.exclude_reason = "terminal disabled in config"
    end
    return result
  end

  if not name then
    if not save_cfg.unnamed_buffers then
      result.excluded = true
      result.exclude_reason = "unnamed buffer disabled in config"
      return result
    end
    if not modified then
      result.excluded = true
      result.exclude_reason = "empty unchanged unnamed buffer"
      return result
    end
  end

  local is_scratch = false
  if name then
    if filetype == "scratch" then
      is_scratch = true
    end
    if buftype == "" and vim.fn.filereadable(name) ~= 1 and vim.fn.isdirectory(name) ~= 1 then
      is_scratch = true
    end
  end
  if is_scratch and not save_cfg.scratch_buffers then
    result.excluded = true
    result.exclude_reason = "scratch buffer disabled in config"
    return result
  end

  if name then
    local matched, pat = match_patterns(name, save_cfg.exclude_patterns or {})
    if matched then
      result.excluded = true
      result.exclude_reason = "pattern: " .. pat
      return result
    end
  end

  local max_bytes = (save_cfg.max_file_size_mb or 1) * 1024 * 1024
  local size = estimate_buffer_size(bufnr, name)
  if size > max_bytes then
    result.large_file = true
    result.lines = nil
    result.exclude_reason = "large file (>" .. tostring(save_cfg.max_file_size_mb) .. "MB)"
  else
    result.lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    if not result.excluded then
      local has_sensitive, keyword = scan_sensitive_content(result.lines, cfg)
      if has_sensitive then
        result.excluded = true
        result.exclude_reason = "sensitive content: " .. keyword
        result.lines = nil
      end
    end
  end

  result.cursor = get_cursor(bufnr)
  return result
end

---@return CapturedBuffer[]
function M.capture_all()
  local bufs = vim.api.nvim_list_bufs()
  local results = {}
  for _, bufnr in ipairs(bufs) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local captured = M.capture(bufnr)
      table.insert(results, captured)
    end
  end
  return results
end

return M
