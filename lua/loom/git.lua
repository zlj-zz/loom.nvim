local M = {}

---@class GitResult
---@field success boolean
---@field stdout string
---@field stderr string
---@field exit_code number

---@param args string[]
---@return GitResult
local function git_cmd(args)
  local output = vim.fn.system(args)
  local exit_code = vim.v.shell_error
  return {
    success = exit_code == 0,
    stdout = output or "",
    stderr = output or "",
    exit_code = exit_code,
  }
end

---@param result GitResult
---@return string|nil
local function trim_stdout(result)
  if not result.success then
    return nil
  end
  local trimmed = vim.trim(result.stdout)
  return trimmed ~= "" and trimmed or nil
end

---@return string|nil
function M.current_branch()
  return trim_stdout(git_cmd({ "git", "branch", "--show-current" }))
end

---@return boolean has_changes, string details
function M.has_uncommitted_changes()
  local result = git_cmd({ "git", "status", "--porcelain" })
  if result.success then
    local output = vim.trim(result.stdout)
    return output ~= "", output
  end
  return false, ""
end

---@param branch string
---@return "local" | "remote" | "none"
function M.branch_exists(branch)
  local all = git_cmd({ "git", "branch", "-a", "--list", branch, "origin/" .. branch })
  local output = vim.trim(all.stdout)
  if output == "" then
    return "none"
  end
  for line in output:gmatch("[^\r\n]+") do
    line = vim.trim(line)
    if line:match("^%*?%s*" .. vim.pesc(branch) .. "$") then
      return "local"
    end
    if line:match("^%s*remotes/origin/" .. vim.pesc(branch) .. "$") then
      return "remote"
    end
  end
  return "none"
end

---@param branch string
---@param create boolean
---@return GitResult
function M.checkout(branch, create)
  if create then
    return git_cmd({ "git", "checkout", "-b", branch })
  end
  return git_cmd({ "git", "checkout", branch })
end

---@param branch string
---@return GitResult
function M.checkout_remote(branch)
  return git_cmd({ "git", "checkout", "-t", "origin/" .. branch })
end

---@param message string|nil
---@return GitResult
function M.stash(message)
  if message and message ~= "" then
    return git_cmd({ "git", "stash", "push", "-m", message })
  end
  return git_cmd({ "git", "stash", "push" })
end

---@return GitResult
function M.stash_pop()
  return git_cmd({ "git", "stash", "pop" })
end

---@return string|nil name, string|nil path
function M.current_repo_name()
  local path = trim_stdout(git_cmd({ "git", "rev-parse", "--show-toplevel" }))
  if path then
    return vim.fn.fnamemodify(path, ":t"), path
  end
  return nil, nil
end

---@return string|nil
function M.current_commit()
  return trim_stdout(git_cmd({ "git", "rev-parse", "--short", "HEAD" }))
end

---@return GitResult
function M.diff_head()
  return git_cmd({ "git", "diff", "HEAD" })
end

---@return GitResult
function M.diff_cached()
  return git_cmd({ "git", "diff", "--cached" })
end

---@param path string
---@param opts {check: boolean, index: boolean}|nil
---@return GitResult
function M.apply_patch(path, opts)
  local args = { "git", "apply" }
  if opts and opts.check then
    table.insert(args, "--check")
  end
  if opts and opts.index then
    table.insert(args, "--index")
  end
  table.insert(args, path)
  return git_cmd(args)
end

---@return string[]
function M.untracked_files()
  local result = git_cmd({ "git", "ls-files", "--others", "--exclude-standard" })
  local files = {}
  if result.success then
    for line in result.stdout:gmatch("[^\r\n]+") do
      line = vim.trim(line)
      if line ~= "" then
        table.insert(files, line)
      end
    end
  end
  return files
end

--- Run a git command in a specific directory without changing global cwd.
---@param dir string
---@param args string[]
---@return GitResult
function M.git_in_dir(dir, args)
  local cmd = { "git", "-C", dir }
  vim.list_extend(cmd, args)
  return git_cmd(cmd)
end

return M
