# Changelog

## v1.0.0 (2026-05-12)

### Features

- **Snapshot management**: Save, load, list, delete, rename, and preview complete editor snapshots
- **State capture**: Buffers (with modified content), window tree layout, cursor positions, terminal content
- **Smart filtering**: Automatic exclusion of `.env` files, large files (>1 MB), and sensitive content (`API_KEY`, `SECRET_KEY`, etc.)
- **Branch-aware switching**: `:LoomSwitch` saves current state, checks out a branch, and restores the snapshot for that branch — with auto-stash support
- **Multi-repo workspaces**: `:LoomWorkspaceSave/Load` to coordinate snapshots across multiple Git repositories
- **IDE import**: Import recent files from VS Code (`.vscode/`) and JetBrains (`.idea/workspace.xml`) as buffers
- **Autosave**: Periodic or event-triggered automatic snapshots with configurable retention
- **Cleanup**: Age-based and count-based cleanup with `--dry-run` support
- **Telescope integration**: `:Telescope loom` for fuzzy-find snapshot search with metadata preview
- **which-key integration**: Auto-registered `<leader>l` group with keymap descriptions
- **Event bus**: `loom.events.on("on_save", cb)` / `on_load` hooks for custom integrations
- **Health check**: `:checkhealth loom` validates setup, disk space, snapshot integrity, and configuration

### Infrastructure

- Atomic directory writes with automatic cleanup on failure
- UUID-based snapshot identifiers stored in `meta.json`
- Git branch detection, checkout, and stash wrappers
- Repository discovery with configurable project roots and scan depth
- Workspace status board with floating window / sidebar display

### Known Limitations

- Terminal restoration is read-only by default (`restore_terminals = "readonly"`); interactive shell state (current directory, environment variables) is not preserved
- Fold state capture is disabled by default (`folds = false`) due to Neovim API limitations
- IDE import reads file lists only; editor-specific settings (breakpoints, run configurations) are not imported
- Workspace status board does not auto-refresh; press `r` to update

### Roadmap

- v1.1: Session diff / preview before load
- v1.1: Export snapshots as shell scripts for portability
- v1.2: Tree-sitter based sensitive content detection (replacing regex)
- v1.2: Remote snapshot sync (rsync / cloud storage)
