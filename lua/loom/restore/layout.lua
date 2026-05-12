local M = {}

---@class restore.LayoutLeaf
---@field type "leaf"
---@field bufnr number
---@field weight number
---@field _tl number|nil
---@field _br number|nil

---@class restore.LayoutContainer
---@field type "row" | "col"
---@field children (restore.LayoutLeaf|restore.LayoutContainer)[]
---@field weight number
---@field _tl number|nil
---@field _br number|nil

---@alias restore.LayoutNode restore.LayoutLeaf|restore.LayoutContainer

---@param node restore.LayoutNode
---@param bufnr_map table<number, number>
---@param cursor_map table<number, {line: number, col: number}>|nil
local function build_layout(node, bufnr_map, cursor_map)
  if node.type == "leaf" then
    local winid = vim.api.nvim_get_current_win()
    node._tl = winid
    node._br = winid
    local old_bufnr = node.bufnr
    local new_bufnr = bufnr_map[old_bufnr]
    if new_bufnr then
      vim.api.nvim_win_set_buf(winid, new_bufnr)
      local cursor = cursor_map and cursor_map[old_bufnr]
      if cursor then
        pcall(vim.api.nvim_win_set_cursor, winid, { cursor.line, cursor.col })
      end
    end
    return
  end

  for i, child in ipairs(node.children) do
    if i == 1 then
      build_layout(child, bufnr_map, cursor_map)
      node._tl = child._tl
      node._br = child._br
    else
      vim.api.nvim_set_current_win(node._br)
      if node.type == "row" then
        vim.cmd("rightbelow vnew")
      else
        vim.cmd("rightbelow new")
      end
      build_layout(child, bufnr_map, cursor_map)
      node._br = child._br
    end
  end
end

---@param winids number[]
---@param weights number[]
---@param get_dim fun(winid: number): number
---@param set_dim fun(winid: number, val: number)
local function distribute(winids, weights, get_dim, set_dim)
  local total = 0
  for _, winid in ipairs(winids) do
    total = total + get_dim(winid)
  end
  local remaining = total
  local remaining_weight = 1.0
  for i = 1, #winids - 1 do
    local target = math.floor(remaining * weights[i] / remaining_weight)
    set_dim(winids[i], target)
    remaining = remaining - target
    remaining_weight = remaining_weight - weights[i]
  end
end

---@param node restore.LayoutNode
local function apply_weights(node)
  if node.type == "leaf" then
    return
  end

  local winids = {}
  local weights = {}
  for _, child in ipairs(node.children) do
    table.insert(winids, child._tl)
    table.insert(weights, child.weight)
  end

  if node.type == "row" then
    distribute(winids, weights, vim.api.nvim_win_get_width, vim.api.nvim_win_set_width)
  else
    distribute(winids, weights, vim.api.nvim_win_get_height, vim.api.nvim_win_set_height)
  end

  for _, child in ipairs(node.children) do
    apply_weights(child)
  end
end

---@param layout restore.LayoutNode
---@param bufnr_map table<number, number>
---@param cursor_map table<number, {line: number, col: number}>|nil
function M.restore(layout, bufnr_map, cursor_map)
  vim.cmd("only")
  vim.cmd("enew")
  local scratch = vim.api.nvim_get_current_buf()

  build_layout(layout, bufnr_map, cursor_map)
  apply_weights(layout)

  pcall(vim.api.nvim_buf_delete, scratch, { force = true })
end

return M
