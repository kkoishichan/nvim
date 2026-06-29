local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"

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
		colorscheme = { "gruvbox", "habamax" },
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
	performance = {
		rtp = {
			disabled_plugins = {
				"gzip",
				"matchit",
				"matchparen",
				"netrwPlugin",
				"tarPlugin",
				"tohtml",
				"tutor",
				"zipPlugin",
			},
		},
	},
})
