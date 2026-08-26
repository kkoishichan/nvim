local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
local layout = require("user.core.layout")

if not vim.uv.fs_stat(lazypath) then
	if vim.fn.executable("git") == 0 then
		error("git is required to install lazy.nvim")
	end

	local repo = "https://github.com/folke/lazy.nvim.git"
	local result = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", repo, lazypath })
	if vim.v.shell_error ~= 0 then
		error("Failed to clone lazy.nvim:\n" .. result)
	end
end

vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
	spec = {
		{ import = "user.plugins" },
	},
	defaults = {
		lazy = true,
		version = false,
	},
	install = {
		colorscheme = { "vscode", "habamax" },
	},
	checker = {
		enabled = false,
	},
	rocks = {
		enabled = false,
	},
	change_detection = {
		notify = false,
	},
	ui = {
		size = { width = layout.manager_scale, height = layout.manager_scale },
		border = layout.manager_border,
		backdrop = 60,
	},
	performance = {
		rtp = {
			disabled_plugins = {
				"matchit",
				"matchparen",
				"netrwPlugin",
				"tohtml",
				"tutor",
			},
		},
	},
})

-- Lazy's manager is a floating application window, so the generic transient
-- popup closer deliberately ignores it. Add the conventional close key beside
-- Lazy's built-in `q` without reaching into its private view state.
vim.api.nvim_create_autocmd("FileType", {
	group = vim.api.nvim_create_augroup("user_lazy_escape", { clear = true }),
	pattern = "lazy",
	desc = "Close Lazy manager with Escape",
	callback = function(event)
		vim.keymap.set("n", "<Esc>", "<Cmd>close<CR>", {
			buffer = event.buf,
			desc = "Close Lazy manager",
			nowait = true,
			silent = true,
		})
	end,
})
