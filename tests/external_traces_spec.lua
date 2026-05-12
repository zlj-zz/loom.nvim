---@diagnostic disable: undefined-field

describe("capture.external_traces", function()
  local et = require("loom.capture.external_traces")
  local original_cwd
  local tmp_dirs = {}

  local function mk_temp(prefix)
    local dir = vim.fn.tempname() .. "_" .. prefix
    table.insert(tmp_dirs, dir)
    return dir
  end

  before_each(function()
    original_cwd = vim.fn.getcwd()
    tmp_dirs = {}
  end)

  after_each(function()
    vim.fn.chdir(original_cwd)
    for _, d in ipairs(tmp_dirs) do
      if vim.fn.isdirectory(d) == 1 then
        vim.fn.delete(d, "rf")
      end
    end
  end)

  it("detects git merge state", function()
    local dir = mk_temp("git")
    vim.fn.mkdir(dir .. "/.git", "p")
    vim.fn.writefile({ "" }, dir .. "/.git/MERGE_HEAD")
    vim.fn.chdir(dir)

    local result = et.capture()

    assert.is_true(result.git.in_merge)
    assert.is_false(result.git.in_rebase)
  end)

  it("returns empty git table outside git repo", function()
    vim.fn.chdir("/tmp")
    local result = et.capture()
    assert.is_true(vim.tbl_isempty(result.git))
  end)

  it("parses jetbrains workspace.xml", function()
    local dir = mk_temp("jetbrains")
    vim.fn.mkdir(dir .. "/.idea", "p")
    local xml = {
      '<component name="RecentDirectoriesManager">',
      '  <option name="recentPaths"><list><option value="$PROJECT_DIR$/src/main.lua" /></list></option>',
      '</component>',
    }
    vim.fn.writefile(xml, dir .. "/.idea/workspace.xml")
    vim.fn.chdir(dir)

    local result = et.capture()

    assert.is_true(result.jetbrains.has_workspace)
    assert.equals(1, #result.jetbrains.recent_files)
    assert.matches("src/main%.lua", result.jetbrains.recent_files[1])
  end)

  it("returns empty tables on errors", function()
    vim.fn.chdir("/tmp")
    local result = et.capture()
    -- should not error even in a non-project directory
    assert.is_not_nil(result.git)
    assert.is_not_nil(result.vscode)
    assert.is_not_nil(result.jetbrains)
  end)

  it("detects vscode workspace", function()
    local dir = mk_temp("vscode")
    vim.fn.mkdir(dir .. "/.vscode", "p")
    vim.fn.writefile({ "{}" }, dir .. "/.vscode/settings.json")
    vim.fn.chdir(dir)

    local result = et.capture()

    assert.is_true(result.vscode.has_workspace)
    assert.is_true(#result.vscode.recent_files >= 1)
  end)
end)
