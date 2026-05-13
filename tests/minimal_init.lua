vim.opt.rtp:prepend(vim.fn.getcwd())
vim.opt.rtp:prepend(vim.fn.expand("~/.local/share/nvim/lazy/plenary.nvim"))
require("plenary.busted")
