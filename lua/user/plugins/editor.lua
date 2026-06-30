return {
	{
		"folke/persistence.nvim",
		event = "BufReadPre",
		opts = {},
		keys = {
			{
				"<leader>ss",
				function()
					require("persistence").load()
				end,
				desc = "Restore session",
			},
			{
				"<leader>sS",
				function()
					require("persistence").select()
				end,
				desc = "Select session",
			},
			{
				"<leader>sl",
				function()
					require("persistence").load({ last = true })
				end,
				desc = "Restore last session",
			},
			{
				"<leader>sd",
				function()
					require("persistence").stop()
				end,
				desc = "Stop saving session",
			},
		},
	},
	{
		"brenoprata10/nvim-highlight-colors",
		event = { "BufReadPost", "BufNewFile" },
		opts = {
			render = "background",
			enable_named_colors = true,
			enable_tailwind = true,
		},
	},
	{
		"mbbill/undotree",
		cmd = { "UndotreeToggle", "UndotreeShow", "UndotreeFocus" },
		keys = {
			{ "<leader>uu", "<cmd>UndotreeToggle<cr>", desc = "Undo tree" },
		},
		init = function()
			vim.g.undotree_WindowLayout = 2
			vim.g.undotree_SetFocusWhenToggle = 1
			vim.g.undotree_ShortIndicators = 1
		end,
	},
	{
		"h-hg/fcitx.nvim",
		event = "VeryLazy",
		cond = function()
			return vim.fn.executable("fcitx5-remote") == 1 or vim.fn.executable("fcitx-remote") == 1
		end,
	},
	{
		"andymass/vim-matchup",
		event = { "BufReadPost", "BufNewFile" },
		init = function()
			vim.g.matchup_matchparen_deferred = 1
			vim.g.matchup_matchparen_deferred_show_delay = 80
			vim.g.matchup_matchparen_deferred_hide_delay = 300
			vim.g.matchup_matchparen_hi_surround_always = 1
			vim.g.matchup_matchparen_offscreen = {}
			vim.g.matchup_matchparen_stopline = 500
			vim.g.matchup_treesitter_stopline = 500
		end,
	},
	{
		"lukas-reineke/indent-blankline.nvim",
		main = "ibl",
		event = { "BufReadPost", "BufNewFile" },
		opts = {
			indent = {
				char = "│",
				tab_char = "│",
			},
			scope = {
				enabled = true,
				show_start = false,
				show_end = false,
			},
			exclude = {
				buftypes = { "terminal", "nofile", "quickfix", "prompt" },
				filetypes = {
					"dashboard",
					"fzf",
					"gitcommit",
					"help",
					"image",
					"lazy",
					"lspinfo",
					"mason",
					"neo-tree",
					"snacks_notif",
					"snacks_picker_input",
					"snacks_picker_list",
					"terminal",
				},
			},
		},
	},
	{
		"RRethy/vim-illuminate",
		event = { "BufReadPost", "BufNewFile" },
		opts = {
			providers = { "lsp", "treesitter", "regex" },
			delay = 120,
			filetypes_denylist = {
				"DiffviewFiles",
				"Trouble",
				"fzf",
				"gitcommit",
				"help",
				"image",
				"lazy",
				"neo-tree",
				"snacks_notif",
				"terminal",
			},
			large_file_cutoff = 3000,
			min_count_to_highlight = 2,
			under_cursor = true,
			disable_keymaps = true,
		},
		config = function(_, opts)
			require("illuminate").configure(opts)
			require("user.core.highlights").on_colorscheme(function()
				local p = require("user.core.palette").get()
				vim.api.nvim_set_hl(0, "IlluminatedWordText", { bg = p.subtle })
				vim.api.nvim_set_hl(0, "IlluminatedWordRead", { bg = p.subtle })
				vim.api.nvim_set_hl(0, "IlluminatedWordWrite", { bg = p.strong, underline = true })
			end)
		end,
		keys = {
			{
				"]r",
				function()
					require("illuminate").goto_next_reference(false)
				end,
				desc = "Next reference",
			},
			{
				"[r",
				function()
					require("illuminate").goto_prev_reference(false)
				end,
				desc = "Previous reference",
			},
		},
	},
	{
		"nvim-treesitter/nvim-treesitter-context",
		event = { "BufReadPost", "BufNewFile" },
		dependencies = {
			"nvim-treesitter/nvim-treesitter",
		},
		opts = {
			enable = true,
			multiwindow = true,
			max_lines = 5,
			min_window_height = 12,
			line_numbers = false,
			multiline_threshold = 2,
			trim_scope = "outer",
			mode = "topline",
			separator = nil,
			zindex = 20,
			on_attach = function(bufnr)
				if vim.b[bufnr].bigfile then
					return false
				end

				local disabled = {
					fzf = true,
					["fzflua_backdrop"] = true,
					["neo-tree"] = true,
					["snacks_picker_input"] = true,
					["snacks_picker_list"] = true,
					["snacks_notif"] = true,
					qf = true,
				}

				return not disabled[vim.bo[bufnr].filetype]
			end,
		},
		config = function(_, opts)
			require("treesitter-context").setup(opts)
			require("user.core.highlights").on_colorscheme(function()
				local p = require("user.core.palette").get()
				vim.api.nvim_set_hl(0, "TreesitterContext", { bg = p.bg })
				vim.api.nvim_set_hl(0, "TreesitterContextBottom", { underline = true, sp = p.strong })
			end)
		end,
		keys = {
			{
				"<leader>uc",
				"<cmd>TSContext toggle<cr>",
				desc = "Toggle sticky context",
			},
			{
				"[c",
				function()
					require("treesitter-context").go_to_context(vim.v.count1)
				end,
				desc = "Goto sticky context",
			},
		},
	},
	{
		"nvim-mini/mini.nvim",
		version = false,
		event = "VeryLazy",
		config = function()
			local ai = require("mini.ai")
			ai.setup({
				n_lines = 500,
				custom_textobjects = {
					c = ai.gen_spec.treesitter({ a = "@class.outer", i = "@class.inner" }),
					f = ai.gen_spec.treesitter({ a = "@function.outer", i = "@function.inner" }),
					o = ai.gen_spec.treesitter({
						a = { "@block.outer", "@conditional.outer", "@loop.outer" },
						i = { "@block.inner", "@conditional.inner", "@loop.inner" },
					}),
					u = ai.gen_spec.function_call(),
					U = ai.gen_spec.function_call({ name_pattern = "[%w_]" }),
				},
			})
			require("mini.move").setup({
				mappings = {
					left = "<M-h>",
					right = "<M-l>",
					down = "<M-j>",
					up = "<M-k>",
					line_left = "<M-h>",
					line_right = "<M-l>",
					line_down = "<M-j>",
					line_up = "<M-k>",
				},
			})
			require("mini.pairs").setup()
			require("mini.surround").setup()
		end,
	},
	{
		"folke/ts-comments.nvim",
		event = "VeryLazy",
		opts = {},
	},
	{
		"folke/todo-comments.nvim",
		event = { "BufReadPost", "BufNewFile" },
		dependencies = { "nvim-lua/plenary.nvim", "ibhagwan/fzf-lua" },
		opts = {
			signs = true,
		},
		keys = {
			{
				"<leader>ft",
				"<cmd>TodoFzfLua<cr>",
				desc = "Todos",
			},
			{
				"<leader>xt",
				"<cmd>TodoQuickFix<cr>",
				desc = "Todo quickfix",
			},
			{
				"]t",
				function()
					require("todo-comments").jump_next()
				end,
				desc = "Next todo",
			},
			{
				"[t",
				function()
					require("todo-comments").jump_prev()
				end,
				desc = "Previous todo",
			},
		},
	},
}
