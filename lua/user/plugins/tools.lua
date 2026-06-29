return {
	{
		"kevinhwang91/nvim-bqf",
		ft = "qf",
		main = "bqf",
		opts = {
			auto_resize_height = true,
			preview = {
				auto_preview = true,
				border = "rounded",
				winblend = 0,
			},
		},
	},
	{
		"folke/trouble.nvim",
		cmd = "Trouble",
		opts = {
			focus = true,
		},
		keys = {
			{ "<leader>xx", "<cmd>Trouble diagnostics toggle<cr>", desc = "Diagnostics" },
			{ "<leader>xX", "<cmd>Trouble diagnostics toggle filter.buf=0<cr>", desc = "Buffer diagnostics" },
			{ "<leader>xl", "<cmd>Trouble loclist toggle<cr>", desc = "Location list" },
			{ "<leader>xq", "<cmd>Trouble qflist toggle<cr>", desc = "Quickfix list" },
			{ "<leader>xr", "<cmd>Trouble lsp_references toggle<cr>", desc = "References" },
		},
	},
	{
		"MagicDuck/grug-far.nvim",
		cmd = { "GrugFar", "GrugFarWithin" },
		opts = {
			headerMaxWidth = 80,
		},
		keys = {
			{
				"<leader>fR",
				function()
					require("grug-far").open()
				end,
				mode = { "n", "x" },
				desc = "Search and replace",
			},
		},
	},
	{
		"folke/lazydev.nvim",
		ft = "lua",
		cmd = "LazyDev",
		opts = {
			library = {
				{ path = "${3rd}/luv/library", words = { "vim%.uv" } },
				{ path = "lazy.nvim", words = { "LazyVim", "lazy" } },
				{ path = "snacks.nvim", words = { "Snacks" } },
				{ path = "nvim-lspconfig", words = { "vim%.lsp%.config" } },
			},
		},
	},
}
