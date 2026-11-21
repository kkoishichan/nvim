-- 字节码缓存，加速 require
vim.loader.enable()

vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

require("config.options")
require("config.autocmds")
require("config.lazy")
require("ui").setup()
require("config.keymaps")
