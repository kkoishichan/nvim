local bootstrap = require("user.core.lazy_bootstrap")
local lazypath = bootstrap.ensure()
local layout = require("user.core.layout")

vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
	lockfile = vim.fs.joinpath(bootstrap.root(), "lazy-lock.json"),
	spec = {
		{ import = "user.plugins" },
	},
	defaults = {
		lazy = true,
		version = false,
	},
	install = {
		missing = vim.env.NVIM_CHECK_ONLY ~= "1",
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
