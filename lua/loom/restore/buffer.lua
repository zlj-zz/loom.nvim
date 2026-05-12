local M = {}

---@class restore.CapturedBuffer
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

---@param captured restore.CapturedBuffer
---@return number|nil new_bufnr
function M.restore(captured)
  if captured.excluded then
    return nil
  end

  local bufnr
  if captured.name then
    bufnr = vim.fn.bufnr(captured.name)
    if bufnr == -1 then
      bufnr = vim.api.nvim_create_buf(true, false)
    end
  else
    bufnr = vim.api.nvim_create_buf(true, false)
  end

  -- set_lines before set_name so captured content isn't overwritten by disk read
  if captured.lines then
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, captured.lines)
  end

  if captured.name then
    vim.api.nvim_buf_set_name(bufnr, captured.name)
  end

  if captured.filetype and captured.filetype ~= "" then
    vim.api.nvim_set_option_value("filetype", captured.filetype, { buf = bufnr })
  end

  -- nvim_buf_set_lines resets modified; restore it if the snapshot was dirty
  if captured.modified then
    vim.api.nvim_set_option_value("modified", true, { buf = bufnr })
  end

  return bufnr
end

---@param buffers restore.CapturedBuffer[]
---@return table<number, number> bufnr_map, table<number, {line: number, col: number}> cursor_map
function M.restore_all(buffers)
  local bufnr_map = {}
  local cursor_map = {}
  for _, captured in ipairs(buffers) do
    local new_bufnr = M.restore(captured)
    if new_bufnr then
      bufnr_map[captured.bufnr] = new_bufnr
      if captured.cursor then
        cursor_map[captured.bufnr] = captured.cursor
      end
    end
  end
  return bufnr_map, cursor_map
end

return M
