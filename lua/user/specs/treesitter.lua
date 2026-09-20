-- Tree-sitter highlighting and indentation. Both modes use the same parsers and
-- queries: fast mode does not rewrite highlight rules to look quicker, it
-- accepts the parser's cost and drops the work layered on top of it.
local treesitter_config = require("user.core.treesitter")

return function()
	return {
		{
			"nvim-treesitter/nvim-treesitter",
			branch = "main",
			-- The main branch does not support lazy-loading (per its README): load at
			-- startup so parsers and queries never desync from the plugin version.
			lazy = false,
			build = treesitter_config.sync,
			opts = {
				install_dir = treesitter_config.install_dir,
			},
			config = function(_, opts)
				require("nvim-treesitter").setup(opts)
				-- zsh has its own parser (installed above), so it is not routed to bash.
				pcall(vim.treesitter.language.register, "bash", { "bash", "sh" })
				pcall(vim.treesitter.language.register, "asm", "riscv")

				vim.api.nvim_create_autocmd("FileType", {
					group = vim.api.nvim_create_augroup("user_treesitter", { clear = true }),
					pattern = treesitter_config.filetypes,
					callback = treesitter_config.enable,
				})
			end,
		},
	}
end
