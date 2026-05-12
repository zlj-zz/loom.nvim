local M = {}

local git = require("loom.git")

---@class DiscoveredRepo
---@field name string
---@field path string
---@field branch string|nil

---@param roots string[]
---@param max_depth number
---@return DiscoveredRepo[]
function M.discover(roots, max_depth)
  local repos = {}
  local seen = {}

  for _, root in ipairs(roots) do
    local expanded = vim.fn.expand(root)
    if vim.fn.isdirectory(expanded) ~= 1 then
      goto continue
    end

    local depth = math.max(1, math.min(max_depth, 5))
    local cmd = { "find", expanded, "-maxdepth", tostring(depth), "-type", "d", "-name", ".git" }
    local output = vim.fn.system(table.concat(cmd, " "))

    for line in output:gmatch("[^\r\n]+") do
      line = vim.trim(line)
      if line == "" then
        goto inner_continue
      end

      local repo_path = vim.fn.fnamemodify(line, ":h")
      local resolved = vim.fn.resolve(repo_path)

      if seen[resolved] then
        goto inner_continue
      end
      seen[resolved] = true

      local branch = git.git_in_dir(resolved, { "branch", "--show-current" })
      local branch_name = nil
      if branch.success then
        branch_name = vim.trim(branch.stdout)
        if branch_name == "" then
          branch_name = nil
        end
      end

      table.insert(repos, {
        name = vim.fn.fnamemodify(resolved, ":t"),
        path = resolved,
        branch = branch_name,
      })

      ::inner_continue::
    end

    ::continue::
  end

  table.sort(repos, function(a, b)
    return a.path < b.path
  end)

  return repos
end

return M
