local panels = require("user.core.panels")
local float_style = require("user.core.float_style")

return {
	{
		"stevearc/oil.nvim",
		lazy = false,
		keys = {
			{
				"<leader>E",
				function()
					require("oil").open(vim.fn.getcwd())
				end,
				desc = "Edit project directory",
			},
			{
				"-",
				function()
					require("oil").open()
				end,
				desc = "Edit current directory",
			},
		},
		dependencies = {
			"nvim-mini/mini.icons",
		},
		opts = {
			default_file_explorer = true,
			delete_to_trash = true,
			skip_confirm_for_simple_edits = false,
			watch_for_changes = true,
			keymaps = {
				["<Esc>"] = {
					callback = function()
						if vim.api.nvim_win_get_config(0).relative ~= "" then
							require("oil").close()
							return
						end
						require("user.core.popups").close()
						vim.cmd.nohlsearch()
					end,
					desc = "Close floating Oil / dismiss popups",
					mode = "n",
				},
			},
			columns = {
				"icon",
				"permissions",
				"size",
				"mtime",
			},
			float = {
				border = "rounded",
				max_width = 0.86,
				max_height = 0.86,
			},
			view_options = {
				show_hidden = true,
				natural_order = true,
				is_always_hidden = function(name)
					return name == ".git" or name == ".jj"
				end,
			},
		},
	},
	{
		"nvim-neo-tree/neo-tree.nvim",
		cmd = "Neotree",
		keys = {
			{
				"<leader>e",
				"<cmd>Neotree toggle reveal position=left<cr>",
				desc = "Explorer",
			},
		},
		dependencies = {
			"nvim-lua/plenary.nvim",
			"MunifTanjim/nui.nvim",
			"nvim-mini/mini.icons",
		},
		opts = {
			close_if_last_window = true,
			enable_diagnostics = true,
			enable_git_status = true,
			sources = {
				"filesystem",
				"buffers",
				"git_status",
			},
			source_selector = {
				winbar = true,
				statusline = false,
				content_layout = "center",
				tabs_layout = "equal",
				padding = { left = 1, right = 1 },
				separator = { left = " ", right = " " },
				sources = {
					{ source = "filesystem", display_name = "Files" },
					{ source = "buffers", display_name = "Buffers" },
					{ source = "git_status", display_name = "Git" },
				},
			},
			-- Neo-tree accepts only named border presets here; float_style's
			-- neo-tree-popup FileType fallback replaces the created dialog border.
			popup_border_style = "rounded",
			default_component_configs = {
				indent = {
					with_expanders = true,
				},
				git_status = {
					symbols = {
						added = "A",
						conflict = "C",
						deleted = "D",
						ignored = "I",
						modified = "M",
						renamed = "R",
						staged = "S",
						unstaged = "U",
						untracked = "?",
					},
				},
			},
			window = {
				position = "left",
				width = panels.left_panel_width,
			},
			filesystem = {
				bind_to_cwd = false,
				follow_current_file = {
					enabled = true,
				},
				filtered_items = {
					hide_dotfiles = false,
					hide_gitignored = true,
					hide_hidden = false,
				},
				use_libuv_file_watcher = true,
			},
			buffers = {
				bind_to_cwd = false,
				follow_current_file = {
					enabled = true,
				},
				group_empty_dirs = true,
				show_unloaded = true,
			},
		},
	},
	{
		"hedyhli/outline.nvim",
		cmd = { "Outline", "OutlineOpen" },
		dependencies = { "epheien/outline-treesitter-provider.nvim" },
		keys = {
			{ "<leader>o", "<cmd>Outline<cr>", desc = "Symbol outline" },
		},
		opts = {
			outline_window = {
				-- Docked on the left below the file tree (edgy stacks them), the
				-- way JetBrains keeps Structure and VSCode keeps Outline in the
				-- explorer sidebar. edgy governs the final width/height.
				position = "left",
				width = 25,
				relative_width = true,
				auto_close = false,
				auto_jump = false,
			},
			outline_items = {
				show_symbol_details = true,
				show_symbol_lineno = false,
			},
			symbol_folding = {
				autofold_depth = 1,
				auto_unfold = { hovered = true },
			},
			preview_window = {
				auto_preview = false,
				border = float_style.border(),
				winhl = "Normal:Pmenu,NormalFloat:Pmenu,FloatBorder:Pmenu,FloatTitle:Pmenu,EndOfBuffer:Pmenu",
				winblend = 0,
			},
			providers = {
				priority = { "lsp", "markdown", "norg", "treesitter" },
			},
		},
	},
	{
		"folke/flash.nvim",
		opts = {},
		keys = {
			{
				"s",
				function()
					require("flash").jump()
				end,
				mode = { "n", "x", "o" },
				desc = "Flash",
			},
			{
				"S",
				function()
					require("flash").treesitter()
				end,
				mode = { "n", "x", "o" },
				desc = "Flash treesitter",
			},
			{
				"r",
				function()
					require("flash").remote()
				end,
				mode = "o",
				desc = "Remote flash",
			},
			{
				"R",
				function()
					require("flash").treesitter_search()
				end,
				mode = { "x", "o" },
				desc = "Treesitter search",
			},
			{
				"<C-s>",
				function()
					require("flash").toggle()
				end,
				mode = "c",
				desc = "Toggle flash search",
			},
		},
	},
}
