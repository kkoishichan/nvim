local heavy_features = {
	"bigfile_flag",
	"illuminate",
	"matchparen",
	"lsp",
	"treesitter",
	"indent_blankline",
	"vimopts",
	"syntax",
	"filetype",
}

return {
	{
		"pteroctopus/faster.nvim",
		lazy = false,
		priority = 900,
		opts = {
			behaviours = {
				bigfile = {
					filesize = 1.5,
					features_disabled = heavy_features,
					notify = true,
				},
				longline = {
					filesize = 0.01,
					avg_bytes_per_line = 250,
					features_disabled = heavy_features,
					notify = true,
				},
				fastmacro = {
					features_disabled = { "lualine", "mini_clue" },
				},
			},
			features = {
				bigfile_flag = {
					on = true,
					defer = false,
					disable = function()
						vim.b.bigfile = true
					end,
					enable = function()
						vim.b.bigfile = false
					end,
					is_active = function(bufnr)
						return vim.b[bufnr].bigfile == true
					end,
				},
			},
		},
	},
}
