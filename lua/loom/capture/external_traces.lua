local M = {}

---@return table
local function capture_git()
  local git_dir = vim.fn.finddir(".git", ".;")
  if git_dir == "" then
    return {}
  end

  local function exists(path)
    return vim.fn.filereadable(path) == 1 or vim.fn.isdirectory(path) == 1
  end

  return {
    in_merge = exists(git_dir .. "/MERGE_HEAD"),
    in_rebase = exists(git_dir .. "/rebase-merge") or exists(git_dir .. "/rebase-apply"),
    in_cherry_pick = exists(git_dir .. "/CHERRY_PICK_HEAD"),
    in_revert = exists(git_dir .. "/REVERT_HEAD"),
    in_bisect = exists(git_dir .. "/BISECT_LOG"),
  }
end

---@return table
local function capture_vscode()
  local result = { has_workspace = false, recent_files = {} }

  if vim.fn.isdirectory(".vscode") == 1 then
    result.has_workspace = true
  end

  local files = vim.fn.glob(".vscode/*", false, true)
  for _, path in ipairs(files) do
    if vim.fn.filereadable(path) == 1 then
      table.insert(result.recent_files, path)
    end
  end

  return result
end

---@param xml_path string
---@return string[]
local function parse_jetbrains_workspace(xml_path)
  local lines = vim.fn.readfile(xml_path, "b")
  if not lines or #lines == 0 then
    return {}
  end

  local files = {}
  local seen = {}

  for _, line in ipairs(lines) do
    for path in line:gmatch('value="%$PROJECT_DIR%$([^"]+)"') do
      if not seen[path] then
        seen[path] = true
        table.insert(files, path)
      end
    end
    for path in line:gmatch('file="file://%$PROJECT_DIR%$([^"]+)"') do
      if not seen[path] then
        seen[path] = true
        table.insert(files, path)
      end
    end
  end

  return files
end

---@return table
local function capture_jetbrains()
  local result = { has_workspace = false, recent_files = {} }

  if vim.fn.isdirectory(".idea") ~= 1 then
    return result
  end

  result.has_workspace = true

  local workspace_xml = ".idea/workspace.xml"
  if vim.fn.filereadable(workspace_xml) == 1 then
    local files = parse_jetbrains_workspace(workspace_xml)
    local cwd = vim.fn.getcwd()
    for _, path in ipairs(files) do
      local abs = cwd .. "/" .. path
      table.insert(result.recent_files, abs)
    end
  end

  return result
end

---@return table
function M.capture()
  local ok_git, git = pcall(capture_git)
  local ok_vscode, vscode = pcall(capture_vscode)
  local ok_jetbrains, jetbrains = pcall(capture_jetbrains)

  return {
    git = ok_git and git or {},
    vscode = ok_vscode and vscode or {},
    jetbrains = ok_jetbrains and jetbrains or {},
  }
end

return M
