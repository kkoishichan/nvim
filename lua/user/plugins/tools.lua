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
		"voldikss/vim-translator",
		cmd = { "Translate", "TranslateW", "TranslateR", "TranslateX" },
		init = function()
			-- Engines that need no API key; auto-detects EN <-> ZH direction.
			vim.g.translator_default_engines = { "google", "bing" }
			vim.g.translator_target_lang = "zh"
			vim.g.translator_window_borderchars = { "─", "│", "─", "│", "╭", "╮", "╯", "╰" }
		end,
		keys = {
			{ "<leader>kt", "<Plug>TranslateW", desc = "Translate popup" },
			{ "<leader>kt", "<Plug>TranslateWV", mode = "x", desc = "Translate selection popup" },
			{ "<leader>kr", "<Plug>TranslateR", desc = "Translate replace" },
			{ "<leader>kr", "<Plug>TranslateRV", mode = "x", desc = "Translate selection replace" },
			{ "<leader>kc", "<Plug>Translate", desc = "Translate echo" },
			{ "<leader>kc", "<Plug>TranslateV", mode = "x", desc = "Translate selection echo" },
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
