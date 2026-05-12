---@diagnostic disable: undefined-field

describe("core.switch", function()
  local core = require("loom.core")
  local storage = require("loom.storage")
  local git = require("loom.git")

  local original_snapshot_exists
  local original_branch_exists
  local original_checkout
  local original_checkout_remote
  local original_snapshot_dir
  local original_read_json
  local original_stash_pop
  local original_notify
  local original_load
  local load_calls

  before_each(function()
    original_snapshot_exists = storage.snapshot_exists
    original_branch_exists = git.branch_exists
    original_checkout = git.checkout
    original_checkout_remote = git.checkout_remote
    original_snapshot_dir = storage.snapshot_dir
    original_read_json = storage.read_json
    original_stash_pop = git.stash_pop
    original_notify = vim.notify
    original_load = core.load
    load_calls = {}

    -- Mock core.load to avoid actual restore
    core.load = function(name)
      table.insert(load_calls, name)
    end

    vim.notify = function(_, _) end
  end)

  after_each(function()
    storage.snapshot_exists = original_snapshot_exists
    git.branch_exists = original_branch_exists
    git.checkout = original_checkout
    git.checkout_remote = original_checkout_remote
    storage.snapshot_dir = original_snapshot_dir
    storage.read_json = original_read_json
    git.stash_pop = original_stash_pop
    vim.notify = original_notify
    core.load = original_load
  end)

  describe("resolve_target", function()
    it("returns snapshot when storage.snapshot_exists is true", function()
      storage.snapshot_exists = function(_)
        return true
      end
      git.branch_exists = function(_)
        return nil
      end

      local kind = core._resolve_target("my-snap")

      assert.equals("snapshot", kind)
    end)

    it("returns local when git.branch_exists returns local", function()
      storage.snapshot_exists = function(_)
        return false
      end
      git.branch_exists = function(_)
        return "local"
      end

      local kind = core._resolve_target("feature-branch")

      assert.equals("local", kind)
    end)

    it("returns remote when git.branch_exists returns remote", function()
      storage.snapshot_exists = function(_)
        return false
      end
      git.branch_exists = function(_)
        return "remote"
      end

      local kind = core._resolve_target("origin/feature")

      assert.equals("remote", kind)
    end)

    it("returns new when nothing matches", function()
      storage.snapshot_exists = function(_)
        return false
      end
      git.branch_exists = function(_)
        return nil
      end

      local kind = core._resolve_target("brand-new")

      assert.equals("new", kind)
    end)
  end)

  describe("execute_switch", function()
    it("loads snapshot directly when branch is nil in meta", function()
      storage.snapshot_dir = function(name)
        return "/tmp/snapshots/" .. name
      end
      storage.read_json = function(_)
        return { branch = nil }
      end
      git.checkout = function(_, _)
        return { success = true }
      end

      core._execute_switch("snap1", "snapshot", false)

      assert.equals(1, #load_calls)
      assert.equals("snap1", load_calls[1])
    end)

    it("checks out branch and loads snapshot when meta has branch", function()
      storage.snapshot_dir = function(name)
        return "/tmp/snapshots/" .. name
      end
      storage.read_json = function(_)
        return { branch = "main" }
      end
      git.checkout = function(branch, create)
        assert.equals("main", branch)
        assert.is_false(create)
        return { success = true }
      end

      core._execute_switch("snap2", "snapshot", false)

      assert.equals(1, #load_calls)
      assert.equals("snap2", load_calls[1])
    end)

    it("stashes rollback when checkout fails and stashed is true", function()
      local stash_popped = false
      storage.snapshot_dir = function(name)
        return "/tmp/snapshots/" .. name
      end
      storage.read_json = function(_)
        return { branch = "main" }
      end
      git.checkout = function(_, _)
        return { success = false, stdout = "error" }
      end
      git.stash_pop = function()
        stash_popped = true
      end

      core._execute_switch("snap3", "snapshot", true)

      assert.is_true(stash_popped)
      assert.equals(0, #load_calls)
    end)

    it("does not stash pop when checkout fails and stashed is false", function()
      local stash_popped = false
      storage.snapshot_dir = function(_)
        return "/tmp/snapshots/x"
      end
      storage.read_json = function(_)
        return { branch = "main" }
      end
      git.checkout = function(_, _)
        return { success = false, stdout = "error" }
      end
      git.stash_pop = function()
        stash_popped = true
      end

      core._execute_switch("snap4", "snapshot", false)

      assert.is_false(stash_popped)
    end)

    it("checks out local branch for kind=local", function()
      local checked_out = false
      git.checkout = function(branch, create)
        assert.equals("feature", branch)
        assert.is_false(create)
        checked_out = true
        return { success = true }
      end

      core._execute_switch("feature", "local", false)

      assert.is_true(checked_out)
      assert.equals(0, #load_calls)
    end)

    it("checks out remote branch for kind=remote", function()
      local checked_out = false
      git.checkout_remote = function(branch)
        assert.equals("origin/dev", branch)
        checked_out = true
        return { success = true }
      end

      core._execute_switch("origin/dev", "remote", false)

      assert.is_true(checked_out)
      assert.equals(0, #load_calls)
    end)

    it("creates new branch for kind=new", function()
      local checked_out = false
      git.checkout = function(branch, create)
        assert.equals("new-branch", branch)
        assert.is_true(create)
        checked_out = true
        return { success = true }
      end

      core._execute_switch("new-branch", "new", false)

      assert.is_true(checked_out)
      assert.equals(0, #load_calls)
    end)
  end)
end)
