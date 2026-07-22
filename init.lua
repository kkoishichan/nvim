if vim.fn.has("nvim-0.12") ~= 1 then
	error("This configuration requires Neovim 0.12 or newer")
end

vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

require("user.core.options")
require("user.core.commands")
require("user.core.keymaps")
require("user.core.conflicts").setup()
require("user.core.autocmds")
require("user.core.diagnostics")
require("user.lazy")
