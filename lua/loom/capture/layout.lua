local M = {}

---@class LayoutLeaf
---@field type "leaf"
---@field bufnr number
---@field weight number

---@class LayoutContainer
---@field type "row" | "col"
---@field children (LayoutLeaf|LayoutContainer)[]
---@field weight number

---@alias LayoutNode LayoutLeaf|LayoutContainer

---@param winid number
---@return number bufnr
local function winid_to_bufnr(winid)
  return vim.api.nvim_win_get_buf(winid)
end

---@param winids number[]
---@return number total
local function total_width(winids)
  local total = 0
  for _, id in ipairs(winids) do
    total = total + vim.api.nvim_win_get_width(id)
  end
  return total
end

---@param winids number[]
---@return number total
local function total_height(winids)
  local total = 0
  for _, id in ipairs(winids) do
    total = total + vim.api.nvim_win_get_height(id)
  end
  return total
end

--- Recursively parse winlayout tree.
--- Returns the parsed node plus the list of leaf winids in its subtree.
---@param node table vim.fn.winlayout() node
---@return LayoutNode parsed, number[] winids
function M.parse(node)
  local t = node[1]
  if t == "leaf" then
    local winid = node[2]
    return {
      type = "leaf",
      bufnr = winid_to_bufnr(winid),
      weight = 1.0,
    }, { winid }
  end

  local children_raw = node[2]
  local child_nodes = {}
  local child_winid_lists = {}

  for _, child in ipairs(children_raw) do
    local parsed, ids = M.parse(child)
    table.insert(child_nodes, parsed)
    table.insert(child_winid_lists, ids)
  end

  local all_winids = {}
  for _, ids in ipairs(child_winid_lists) do
    vim.list_extend(all_winids, ids)
  end

  local total = (t == "row") and total_width(all_winids) or total_height(all_winids)

  for i, child in ipairs(child_nodes) do
    local ids = child_winid_lists[i]
    local child_total = (t == "row") and total_width(ids) or total_height(ids)
    child.weight = total > 0 and (child_total / total) or (1.0 / #children_raw)
  end

  return {
    type = t,
    children = child_nodes,
    weight = 1.0,
  }, all_winids
end

--- Capture the complete layout of the current tabpage.
---@return LayoutNode
function M.capture()
  local tree = vim.fn.winlayout()
  local parsed, _ = M.parse(tree)
  return parsed
end

---@param node LayoutNode
---@return number sum
local function sum_weights(node)
  if node.type == "leaf" then
    return node.weight
  end
  local sum = 0
  for _, child in ipairs(node.children) do
    sum = sum + child.weight
  end
  return sum
end

--- Verify that weights at each container level sum to ~1.0.
---@param node LayoutNode
---@return boolean ok, string|nil err
function M.validate(node)
  if node.type == "leaf" then
    return true, nil
  end
  local sum = sum_weights(node)
  if math.abs(sum - 1.0) > 0.01 then
    return false, string.format("%s weights sum to %.3f (expected 1.0)", node.type, sum)
  end
  for _, child in ipairs(node.children) do
    local ok, err = M.validate(child)
    if not ok then
      return ok, err
    end
  end
  return true, nil
end

return M
