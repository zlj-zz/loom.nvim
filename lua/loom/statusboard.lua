local M = {}

---@class StatusboardItem
---@field repo_name string
---@field path string
---@field branch string|nil
---@field snapshot string|nil
---@field is_current boolean

local ns = vim.api.nvim_create_namespace("loom_statusboard")

---@param workspace_name string
---@param repos StatusboardItem[]
---@param on_action fun(action: string, item: StatusboardItem|nil)|nil
function M.open(workspace_name, repos, on_action)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = bufnr })
  vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })
  vim.api.nvim_set_option_value("filetype", "loomstatus", { buf = bufnr })

  local width = math.min(80, vim.o.columns - 8)
  local height = math.min(#repos + 6, vim.o.lines - 6)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local winid = vim.api.nvim_open_win(bufnr, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " Loom Workspace: " .. workspace_name .. " ",
    title_pos = "center",
  })

  local lines = {}
  local line_to_item = {}

  table.insert(lines, "  q:close  r:refresh  <CR>:load  d:delete snapshot")
  table.insert(lines, string.rep("─", width - 2))

  for _, item in ipairs(repos) do
    local icon = item.is_current and "▸" or " "
    local status = item.snapshot and "✓" or "○"
    local branch_str = item.branch and ("[" .. item.branch .. "]") or "[no git]"
    local snap_str = item.snapshot or "none"
    local line = string.format(" %s %s %-15s %-20s → %s", icon, status, item.repo_name, branch_str, snap_str)
    table.insert(lines, line)
    line_to_item[#lines] = item

    if item.is_current then
      vim.api.nvim_buf_set_extmark(bufnr, ns, #lines - 1, 0, {
        hl_group = "CursorLine",
        end_line = #lines - 1,
        end_col = #line,
      })
    end
  end

  table.insert(lines, "")
  table.insert(lines, "  ○ = no snapshot  ✓ = has snapshot  ▸ = current repo")

  vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr })
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })

  ---@type integer|nil
  local autocmd_id = vim.api.nvim_create_autocmd("BufLeave", {
    buffer = bufnr,
    once = true,
    callback = function()
      if vim.api.nvim_win_is_valid(winid) then
        vim.api.nvim_win_close(winid, true)
      end
    end,
  })

  local function close()
    if autocmd_id then
      pcall(vim.api.nvim_del_autocmd, autocmd_id)
      autocmd_id = nil
    end
    if vim.api.nvim_win_is_valid(winid) then
      vim.api.nvim_win_close(winid, true)
    end
  end

  local function refresh()
    close()
    if on_action then
      on_action("refresh", nil)
    end
  end

  local function act(action)
    local lnum = vim.api.nvim_win_get_cursor(winid)[1]
    local item = line_to_item[lnum]
    if item and on_action then
      close()
      on_action(action, item)
    end
  end

  local opts = { buffer = bufnr, silent = true }
  vim.keymap.set("n", "q", close, opts)
  vim.keymap.set("n", "r", refresh, opts)
  vim.keymap.set("n", "<CR>", function()
    act("load")
  end, opts)
  vim.keymap.set("n", "d", function()
    act("delete")
  end, opts)
end

return M
