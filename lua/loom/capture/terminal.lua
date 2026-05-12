local M = {}

---@class CapturedTerminal
---@field bufnr number
---@field shell string|nil
---@field cwd string|nil
---@field lines string[]|nil
---@field cursor {line: number, col: number}|nil

local DEFAULT_MAX_LINES = 50

--- Parse shell from terminal buffer name.
--- Neovim names terminals: term://cwd//pid:command
---@param bufname string
---@return string|nil shell
local function parse_shell_from_name(bufname)
  local shell = bufname:match("term://.-//%d+:(.+)$")
  if shell then
    shell = vim.trim(shell)
    if shell ~= "" then
      return shell
    end
  end
  return nil
end

--- Infer shell from environment or buffer name.
---@param bufnr number
---@param bufname string
---@return string|nil shell
local function infer_shell(bufnr, bufname)
  local shell = parse_shell_from_name(bufname)
  if shell then
    return shell
  end

  local chan = vim.api.nvim_get_option_value("channel", { buf = bufnr })
  if chan and chan ~= 0 then
    local ok, info = pcall(vim.api.nvim_get_chan_info, chan)
    if ok and info and info.argv and #info.argv > 0 then
      return info.argv[1]
    end
  end

  local env_shell = vim.fn.getenv("SHELL")
  return env_shell ~= vim.NIL and env_shell or nil
end

--- Parse cwd from terminal buffer name.
---@param bufname string
---@return string|nil cwd
local function parse_cwd_from_name(bufname)
  local cwd = bufname:match("^term://(.-)//")
  if cwd then
    cwd = vim.trim(cwd)
    if cwd ~= "" then
      return cwd
    end
  end
  return nil
end

---@param bufnr number
---@param bufname string
---@return string|nil cwd
local function infer_cwd(bufnr, bufname)
  local cwd = parse_cwd_from_name(bufname)
  if cwd then
    return cwd
  end

  local ok, dir = pcall(vim.api.nvim_buf_call, bufnr, function()
    return vim.fn.getcwd()
  end)
  if ok then
    return dir
  end

  return nil
end

--- Capture a terminal buffer.
---@param bufnr number
---@param max_lines number|nil
---@return CapturedTerminal
function M.capture(bufnr, max_lines)
  max_lines = max_lines or DEFAULT_MAX_LINES

  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local start_line = math.max(0, line_count - max_lines)
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line, line_count, false)

  local winnr = vim.fn.bufwinid(bufnr)
  local cursor = nil
  if winnr ~= -1 then
    local c = vim.api.nvim_win_get_cursor(winnr)
    cursor = { line = c[1], col = c[2] }
  end

  return {
    bufnr = bufnr,
    shell = infer_shell(bufnr, bufname),
    cwd = infer_cwd(bufnr, bufname),
    lines = lines,
    cursor = cursor,
  }
end

return M
