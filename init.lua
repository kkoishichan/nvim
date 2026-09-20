if vim.fn.has("nvim-0.12") ~= 1 then
	error("This configuration requires Neovim 0.12 or newer")
end

-- Spread Lua collection across smaller steps during allocation-heavy redraws.
-- Keep automatic collection enabled and retain its default pause threshold.
collectgarbage("setstepmul", 100)

vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- The mode is decided before anything registers an event, a mapping or a timer,
-- so a disabled feature is never initialized and then hidden.
local capabilities = require("user.core.mode").capabilities()

require("user.core.options")
require("user.core.buffer_policy").setup()
require("user.core.project").setup()
require("user.core.commands")
require("user.core.keymaps")
if capabilities.conflicts then
	require("user.core.conflicts").setup()
end
require("user.core.autocmds")
require("user.core.float_style").setup()
if capabilities.ui_panels then
	-- Panel budgets and manager float geometry only matter once side panels and
	-- docks exist; without them this would be per-window work for nothing.
	require("user.core.layout").setup()
end
require("user.core.diagnostics")
if not capabilities.lsp_auto then
	-- No client starts on its own, so the explicit entry has to exist.
	require("user.core.fast_lsp").setup()
end
require("user.lazy")
