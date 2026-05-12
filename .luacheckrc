globals = {
  "vim",
}

ignore = {
  "631", -- max_line_length
}

files = {}
files["lua/loom/health.lua"] = {
  globals = {
    "vim.health",
  },
}

std = "luajit"
