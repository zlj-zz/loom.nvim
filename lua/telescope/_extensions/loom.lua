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

---@return {name: string, branch: string|nil, time: string|nil, note: string|nil, meta: table|nil}[]
local function get_items()
  local names = storage.list_snapshots()
  local items = {}
  for _, n in ipairs(names) do
    local meta = storage.read_json(storage.snapshot_dir(n) .. "/meta.json")
    table.insert(items, {
      name = n,
      branch = meta and meta.branch,
      time = meta and meta.timestamp,
      note = meta and meta.note,
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
  local items = get_items()

  if #items == 0 then
    vim.notify("No snapshots found", vim.log.levels.INFO)
    return
  end

  pickers.new(opts, {
    prompt_title = "Loom Snapshots",
    finder = finders.new_table({
      results = items,
      entry_maker = function(item)
        return {
          value = item,
          display = list_ui.format_snapshot(item),
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
