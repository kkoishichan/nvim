return {
	{
		"pteroctopus/faster.nvim",
		lazy = false,
		priority = 900,
		opts = {
			-- Buffer costs are handled before FileType by user.core.buffer_policy.
			-- Keep macro optimization without the global LspStop path.
			behaviours = {
				bigfile = { on = false },
				longline = { on = false },
				fastmacro = { features_disabled = { "lualine", "mini_clue" } },
			},
		},
	},
}
