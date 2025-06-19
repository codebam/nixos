vim.cmd.colorscheme("catppuccin_mocha")

vim.opt.guicursor = "n-v-c-i:block"

vim.opt.tabstop = 2

local undodir = vim.fn.stdpath("state") .. "/undo"
vim.fn.mkdir(undodir, "p")
vim.opt.undodir = undodir
vim.opt.undofile = true
