if vim.fn.has("nvim-0.12") ~= 1 then
	error("This configuration requires Neovim 0.12 or newer")
end

-- Spread Lua collection across smaller steps during allocation-heavy redraws.
-- Keep automatic collection enabled and retain its default pause threshold.
collectgarbage("setstepmul", 100)

vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

require("user.core.options")
require("user.core.buffer_policy").setup()
require("user.core.project").setup()
require("user.core.commands")
require("user.core.keymaps")
require("user.core.conflicts").setup()
require("user.core.autocmds")
require("user.core.float_style").setup()
require("user.core.layout").setup()
require("user.core.diagnostics")
require("user.lazy")
