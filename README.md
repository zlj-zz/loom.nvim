# loom.nvim

> Save and restore your Neovim editor state — buffers, windows, terminals, and more.

loom.nvim captures your complete editor layout (open buffers, window tree, cursor positions, terminal content) into named **snapshots** that you can restore later. It also supports **workspaces** spanning multiple Git repositories, branch-aware switching with auto-stash, IDE file import, and automatic periodic saves.

![demo-gif-placeholder](https://via.placeholder.com/800x400?text=loom.nvim+demo+GIF)

## Features

- **Complete state capture**: buffers (with modified content), window tree, cursor positions, terminals
- **Smart exclusions**: `.env` files, large files (>1 MB by default), sensitive content (`API_KEY`, etc.)
- **Branch-aware workflows**: save/load with Git branch metadata, switch branches with auto-stash
- **Multi-repo workspaces**: save and restore snapshots across multiple Git repositories
- **IDE import**: import recent files from VS Code or JetBrains IDEs as buffers
- **Autosave**: periodic or event-triggered automatic snapshots
- **Telescope integration**: fuzzy-find and preview snapshots (`:Telescope loom`)
- **which-key integration**: discover keymaps with `<leader>l`

## Requirements

- Neovim 0.9+
- Git (for branch operations)
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) (required)
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) (optional, for `:Telescope loom`)
- [which-key.nvim](https://github.com/folke/which-key.nvim) (optional, for keymap hints)

## Installation

### lazy.nvim

```lua
{
  "your-username/loom.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
  opts = {
    -- see Configuration below
  },
}
```

### packer.nvim

```lua
use {
  "your-username/loom.nvim",
  requires = { "nvim-lua/plenary.nvim" },
  config = function()
    require("loom").setup({
      -- see Configuration below
    })
  end,
}
```

## Quick Start

```lua
require("loom").setup()
```

Then use the commands:

```vim
:LoomSave my-feature          " save current state
:LoomLoad my-feature          " restore saved state
:LoomList                     " interactive list
:LoomSwitch feature-branch    " save current, checkout branch, restore
```

Or with keymaps (if which-key is installed, press `<leader>l` to see hints):

```lua
vim.keymap.set("n", "<leader>ls", "<cmd>LoomSave<cr>")
vim.keymap.set("n", "<leader>ll", "<cmd>LoomLoad<cr>")
vim.keymap.set("n", "<leader>lL", "<cmd>LoomList<cr>")
vim.keymap.set("n", "<leader>lS", "<cmd>LoomSwitch<cr>")
```

## Commands

### Snapshots

| Command | Args | Description |
|---|---|---|
| `:LoomSave` | `[name] [--note="..."]` | Save current editor snapshot |
| `:LoomLoad` | `[name]` | Load a snapshot (interactive if no name) |
| `:LoomList` | | List all snapshots interactively |
| `:LoomDelete` | `<name>` | Delete a snapshot |
| `:LoomRename` | `<old> <new>` | Rename a snapshot |
| `:LoomPeek` | `[name]` | Preview snapshot metadata without loading |
| `:LoomCurrent` | | Show current snapshot info |
| `:LoomSwitch` | `[branch\|snapshot\|new-branch]` | Save current, switch branch, restore |

### Workspaces

| Command | Args | Description |
|---|---|---|
| `:LoomWorkspaceSave` | `[name] [--repos=a,b]` | Save workspace index across repos |
| `:LoomWorkspaceLoad` | `[name]` | Load workspace (auto-restore current repo) |
| `:LoomWorkspaceList` | | List all workspaces |
| `:LoomWorkspaceDelete` | `<name>` | Delete a workspace |
| `:LoomWorkspaceStatus` | | Show workspace status board |

### Utilities

| Command | Args | Description |
|---|---|---|
| `:LoomImport` | `[vscode\|jetbrains]` | Import IDE recent files as buffers |
| `:LoomCleanup` | `[--dry-run]` | Clean up old snapshots |

### Telescope

```vim
:Telescope loom
```

- `<CR>` — load selected snapshot
- `<C-d>` — delete selected snapshot (with confirmation)

## Configuration

Default options:

```lua
require("loom").setup({
  data_dir = nil,  -- defaults to stdpath("data").."/loom/"..$USER

  save = {
    terminals = true,
    scratch_buffers = true,
    unnamed_buffers = true,
    folds = false,
    max_file_size_mb = 1,
    exclude_patterns = { ".env", ".env.*", "*secret*", "*private*", "*credential*", "*.key", "*.pem" },
    exclude_by_content = { "API_KEY", "SECRET_KEY", "PRIVATE_KEY", "PASSWORD", "TOKEN=" },
    sensitive_scan_lines = 50,
  },

  load = {
    confirm_unsaved = true,
    warn_branch_mismatch = true,
    auto_cwd = true,
    restore_terminals = "readonly",
  },

  autosave = {
    enabled = false,
    interval_minutes = 30,
    on_events = { "BufWritePost" },
    max_auto_snaps = 10,
  },

  cleanup = {
    max_snapshots = 50,
    auto_cleanup_after_days = 90,
  },

  workspace = {
    enabled = true,
    project_roots = { "~/projects", "~/workspace" },
    scan_depth = 2,
    status_refresh_interval = 0,
    default_repos = {},
  },

  switch = {
    auto_save = true,
    auto_stash = "prompt",
    create_branch_prompt = true,
    confirm_checkout = true,
  },

  integrations = {
    telescope = true,
    which_key = true,
  },
})
```

### Events

Hook into save/load lifecycle:

```lua
local loom = require("loom")

loom.events.on("on_save", function(data)
  print("Saved: " .. data.name .. " on branch " .. data.branch)
end)

loom.events.on("on_load", function(data)
  print("Loaded: " .. data.name)
end)
```

## Health Check

Run `:checkhealth loom` to verify:

- Neovim version compatibility
- Git availability
- Data directory writable
- Disk space
- Snapshot integrity
- Autosave / cleanup configuration

## License

MIT
