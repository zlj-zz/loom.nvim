local has_telescope, telescope = pcall(require, "telescope")
if not has_telescope then
  error("This extension requires telescope.nvim")
end

local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local previewers = require("telescope.previewers")

local core = require("loom.core")
local storage = require("loom.storage")
local list_ui = require("loom.list")
local git = require("loom.git")

---@param all_repos boolean
---@return {name: string, branch: string|nil, repo: string|nil, time: string|nil, note: string|nil, meta: table|nil}[]
local function get_items(all_repos)
  local config = require("loom").get_config()
  local filter_repo
  if not all_repos and config.list.filter_by_repo then
    filter_repo = git.current_repo_name()
  end

  local raw_items = storage.list_snapshots_with_meta(filter_repo)
  local items = {}
  for _, item in ipairs(raw_items) do
    local meta = item.meta
    table.insert(items, {
      name = item.name,
      branch = meta.branch,
      repo = meta.repo_name,
      time = meta.timestamp,
      note = meta.note,
      meta = meta,
    })
  end
  return items
end

---@param meta table|nil
---@return string[]
local function meta_to_lines(meta)
  if not meta then
    return { "No metadata available" }
  end
  local lines = {}
  for k, v in pairs(meta) do
    if type(v) == "table" then
      v = vim.json.encode(v)
    end
    table.insert(lines, k .. ": " .. tostring(v))
  end
  table.sort(lines)
  return lines
end

--- Create the loom picker.
---@param opts table|nil
local function loom_picker(opts)
  opts = opts or {}
  local all_repos = opts.all_repos or false
  local items = get_items(all_repos)

  if #items == 0 then
    local config = require("loom").get_config()
    local filter_repo = not all_repos and config.list.filter_by_repo and git.current_repo_name()
    if filter_repo then
      vim.notify("No snapshots for repo: " .. filter_repo, vim.log.levels.INFO)
    else
      vim.notify("No snapshots found", vim.log.levels.INFO)
    end
    return
  end

  local config = require("loom").get_config()
  local show_repo = all_repos and config.list.show_repo_in_all_mode

  pickers.new(opts, {
    prompt_title = all_repos and "Loom Snapshots (all repos)" or "Loom Snapshots",
    finder = finders.new_table({
      results = items,
      entry_maker = function(item)
        return {
          value = item,
          display = list_ui.format_snapshot(item, { show_repo = show_repo }),
          ordinal = item.name,
        }
      end,
    }),
    sorter = conf.generic_sorter(opts),
    previewer = previewers.new_buffer_previewer({
      title = "Snapshot Metadata",
      define_preview = function(self, entry)
        local lines = meta_to_lines(entry.value.meta)
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
        vim.api.nvim_set_option_value("filetype", "json", { buf = self.state.bufnr })
      end,
    }),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        if selection then
          actions.close(prompt_bufnr)
          core.load(selection.value.name)
        end
      end)

      local function delete_selected()
        local selection = action_state.get_selected_entry()
        if not selection then
          return
        end
        local name = selection.value.name
        actions.close(prompt_bufnr)
        vim.ui.select({ "yes", "no" }, {
          prompt = "Delete snapshot '" .. name .. "'?",
        }, function(choice)
          if choice == "yes" then
            core.delete(name)
          end
        end)
      end

      vim.keymap.set("n", "<C-d>", delete_selected, { buffer = prompt_bufnr })
      vim.keymap.set("i", "<C-d>", delete_selected, { buffer = prompt_bufnr })
      return true
    end,
  }):find()
end

return telescope.register_extension({
  exports = {
    loom = loom_picker,
  },
})
