---@diagnostic disable: undefined-field

-- Pre-load loom so cached module survives cwd changes during tests
require("loom")

describe("e2e git workflow", function()
  local core = require("loom.core")
  local storage = require("loom.storage")

  local tmp_repo
  local original_cwd
  local original_notify
  local notify_calls
  local test_buf

  local function setup_repo()
    original_cwd = vim.fn.getcwd()
    tmp_repo = vim.fn.tempname() .. "_loom_e2e"
    vim.fn.mkdir(tmp_repo, "p")
    vim.fn.chdir(tmp_repo)
    vim.fn.system({ "git", "init" })
    vim.fn.system({ "git", "config", "user.email", "test@test.com" })
    vim.fn.system({ "git", "config", "user.name", "Test" })
    vim.fn.system({ "git", "checkout", "-b", "e2e_branch" })

    vim.fn.writefile({ "original" }, tmp_repo .. "/tracked.txt")
    vim.fn.system({ "git", "add", "tracked.txt" })
    vim.fn.system({ "git", "commit", "-m", "initial" })
  end

  local function teardown_repo()
    vim.fn.chdir(original_cwd)
    if vim.fn.isdirectory(tmp_repo) == 1 then
      vim.fn.delete(tmp_repo, "rf")
    end
  end

  before_each(function()
    setup_repo()
    test_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(test_buf)

    original_notify = vim.notify
    notify_calls = {}
    vim.notify = function(msg, level)
      table.insert(notify_calls, { msg = msg, level = level })
    end
  end)

  after_each(function()
    vim.notify = original_notify
    pcall(vim.api.nvim_buf_delete, test_buf, { force = true })
    teardown_repo()
  end)

  local function ensure_deleted(name)
    if storage.snapshot_exists(name) then
      storage.delete_snapshot(name)
    end
  end

  it("restores tracked file modified outside nvim", function()
    local name = "e2e_tracked"
    ensure_deleted(name)

    vim.fn.writefile({ "modified by sed" }, tmp_repo .. "/tracked.txt")
    core.save(name, {})

    vim.fn.system({ "git", "reset", "--hard", "HEAD" })
    local lines_before = vim.fn.readfile(tmp_repo .. "/tracked.txt")
    assert.equals("original", lines_before[1])

    core.load(name)

    local lines_after = vim.fn.readfile(tmp_repo .. "/tracked.txt")
    assert.equals("modified by sed", lines_after[1])

    ensure_deleted(name)
  end)

  it("restores untracked files", function()
    local name = "e2e_untracked"
    ensure_deleted(name)

    vim.fn.writefile({ "untracked content" }, tmp_repo .. "/new.lua")
    core.save(name, {})

    vim.fn.delete(tmp_repo .. "/new.lua")
    assert.equals(0, vim.fn.filereadable(tmp_repo .. "/new.lua"))

    core.load(name)

    assert.equals(1, vim.fn.filereadable(tmp_repo .. "/new.lua"))
    local lines = vim.fn.readfile(tmp_repo .. "/new.lua")
    assert.equals("untracked content", lines[1])

    ensure_deleted(name)
  end)

  it("restores staged state", function()
    local name = "e2e_staged"
    ensure_deleted(name)

    vim.fn.writefile({ "staged content" }, tmp_repo .. "/tracked.txt")
    vim.fn.system({ "git", "add", "tracked.txt" })
    core.save(name, {})

    vim.fn.system({ "git", "reset", "--hard", "HEAD" })
    local lines = vim.fn.readfile(tmp_repo .. "/tracked.txt")
    assert.equals("original", lines[1])

    core.load(name)

    local lines_after = vim.fn.readfile(tmp_repo .. "/tracked.txt")
    assert.equals("staged content", lines_after[1])

    local staged = vim.fn.system({ "git", "diff", "--cached", "--name-only" })
    assert.matches("tracked%.txt", staged)

    ensure_deleted(name)
  end)

  it("full workflow: staged + unstaged + untracked", function()
    local name = "e2e_full"
    ensure_deleted(name)

    vim.fn.writefile({ "staged_line" }, tmp_repo .. "/tracked.txt")
    vim.fn.system({ "git", "add", "tracked.txt" })
    vim.fn.writefile({ "staged_line", "unstaged_line" }, tmp_repo .. "/tracked.txt")
    vim.fn.writefile({ "untracked_data" }, tmp_repo .. "/extra.lua")

    core.save(name, {})

    vim.fn.system({ "git", "reset", "--hard", "HEAD" })
    vim.fn.delete(tmp_repo .. "/extra.lua")
    assert.equals(0, vim.fn.filereadable(tmp_repo .. "/extra.lua"))

    core.load(name)

    local lines = vim.fn.readfile(tmp_repo .. "/tracked.txt")
    assert.equals("staged_line", lines[1])
    assert.equals("unstaged_line", lines[2])

    local staged = vim.fn.system({ "git", "diff", "--cached", "--name-only" })
    assert.matches("tracked%.txt", staged)

    local unstaged = vim.fn.system({ "git", "diff", "--name-only" })
    assert.matches("tracked%.txt", unstaged)

    assert.equals(1, vim.fn.filereadable(tmp_repo .. "/extra.lua"))
    local untracked_lines = vim.fn.readfile(tmp_repo .. "/extra.lua")
    assert.equals("untracked_data", untracked_lines[1])

    ensure_deleted(name)
  end)

  it("skips diff apply when working dir is dirty", function()
    local name = "e2e_dirty"
    ensure_deleted(name)

    vim.fn.writefile({ "snapshot_content" }, tmp_repo .. "/tracked.txt")
    vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, { "buffer content" })
    core.save(name, {})

    vim.fn.writefile({ "dirty_content" }, tmp_repo .. "/tracked.txt")
    vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, { "mutated" })

    core.load(name)

    local warned = false
    for _, call in ipairs(notify_calls) do
      if call.msg and call.msg:match("skipping diff apply") then
        warned = true
        break
      end
    end
    assert.is_true(warned, "expected warning about skipping diff apply")

    ensure_deleted(name)
  end)
end)
