---@diagnostic disable: undefined-field

describe("git diff capture and restore", function()
  local git = require("loom.git")
  local storage = require("loom.storage")

  local tmp_repo
  local original_cwd

  before_each(function()
    original_cwd = vim.fn.getcwd()
    tmp_repo = vim.fn.tempname() .. "_git_diff_test"
    vim.fn.mkdir(tmp_repo, "p")
    vim.fn.chdir(tmp_repo)
    vim.fn.system({ "git", "init" })
    vim.fn.system({ "git", "config", "user.email", "test@test.com" })
    vim.fn.system({ "git", "config", "user.name", "Test" })

    -- create a tracked file and commit
    vim.fn.writefile({ "original content" }, tmp_repo .. "/tracked.txt")
    vim.fn.system({ "git", "add", "tracked.txt" })
    vim.fn.system({ "git", "commit", "-m", "initial" })
  end)

  after_each(function()
    vim.fn.chdir(original_cwd)
    if vim.fn.isdirectory(tmp_repo) == 1 then
      vim.fn.delete(tmp_repo, "rf")
    end
  end)

  it("diff_head captures unstaged changes", function()
    vim.fn.writefile({ "modified content" }, tmp_repo .. "/tracked.txt")

    local result = git.diff_head()

    assert.is_true(result.success)
    assert.matches("modified content", result.stdout)
  end)

  it("diff_cached captures staged changes", function()
    vim.fn.writefile({ "staged content" }, tmp_repo .. "/tracked.txt")
    vim.fn.system({ "git", "add", "tracked.txt" })

    local result = git.diff_cached()

    assert.is_true(result.success)
    assert.matches("staged content", result.stdout)
  end)

  it("diff_head returns empty when no changes", function()
    local result = git.diff_head()

    assert.is_true(result.success)
    assert.is_true(vim.trim(result.stdout) == "")
  end)

  it("untracked_files lists untracked files", function()
    vim.fn.writefile({ "hello" }, tmp_repo .. "/new.txt")

    local files = git.untracked_files()

    assert.equals(1, #files)
    assert.equals("new.txt", files[1])
  end)

  it("untracked_files returns empty when none exist", function()
    local files = git.untracked_files()

    assert.equals(0, #files)
  end)

  it("apply_patch restores unstaged changes", function()
    vim.fn.writefile({ "patch me" }, tmp_repo .. "/tracked.txt")
    local diff = git.diff_head()
    assert.is_true(diff.success)

    -- reset file
    vim.fn.writefile({ "original content" }, tmp_repo .. "/tracked.txt")

    local patch_path = tmp_repo .. "/test.patch"
    vim.fn.writefile(vim.split(diff.stdout, "\n", { plain = true }), patch_path)

    local check = git.apply_patch(patch_path, { check = true })
    assert.is_true(check.success, "patch check failed: " .. check.stdout)

    local apply = git.apply_patch(patch_path)
    assert.is_true(apply.success, "patch apply failed: " .. apply.stdout)

    local lines = vim.fn.readfile(tmp_repo .. "/tracked.txt")
    assert.equals("patch me", lines[1])
  end)

  it("apply_patch with index restores staged changes", function()
    vim.fn.writefile({ "staged patch" }, tmp_repo .. "/tracked.txt")
    vim.fn.system({ "git", "add", "tracked.txt" })
    local diff = git.diff_cached()
    assert.is_true(diff.success)

    -- reset and unstage
    vim.fn.system({ "git", "reset", "--hard", "HEAD" })

    local patch_path = tmp_repo .. "/staged.patch"
    vim.fn.writefile(vim.split(diff.stdout, "\n", { plain = true }), patch_path)

    local check = git.apply_patch(patch_path, { check = true })
    assert.is_true(check.success)

    local apply = git.apply_patch(patch_path, { index = true })
    assert.is_true(apply.success)

    -- verify staged
    local staged = vim.fn.system({ "git", "diff", "--cached", "--name-only" })
    assert.matches("tracked%.txt", staged)
  end)

  it("copy_file copies with directory creation", function()
    local src = tmp_repo .. "/src.txt"
    vim.fn.writefile({ "copy me" }, src)
    local dst = tmp_repo .. "/deep/nested/dst.txt"

    local ok = storage.copy_file(src, dst)

    assert.is_true(ok)
    assert.equals(1, vim.fn.filereadable(dst))
    local lines = vim.fn.readfile(dst)
    assert.equals("copy me", lines[1])
  end)
end)
