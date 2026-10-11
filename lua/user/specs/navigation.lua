local panels = require("user.core.panels")
local mode = require("user.core.mode")

local function toggle_explorer()
	local name = vim.api.nvim_buf_get_name(0)
	local args = {
		toggle = true,
		position = "left",
		reveal = vim.bo.buftype == "" and name ~= "" and not name:match("^%w[%w+.-]*://"),
	}
	if vim.bo.filetype == "oil" then
		-- Oil names its buffers with a URI; Neo-tree's reveal expects a file path.
		-- Open the displayed local directory, leaving remote adapters on cwd.
		args.dir = require("oil").get_current_dir() or vim.fn.getcwd()
	end
	require("neo-tree.command").execute(args)
end

local function has_invalid_restored_neotree_buffer()
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		local name = vim.fn.bufname(bufnr)
		local has_source = pcall(vim.api.nvim_buf_get_var, bufnr, "neo_tree_source")
		if name:match("neo%-tree [^ ]+ %[%d+]") and not has_source then
			return true
		end
	end
	return false
end

return function(profile)
	profile = profile or {}
	local plugins = require("user.specs.explorer")()
	table.insert(plugins, {
		"nvim-neo-tree/neo-tree.nvim",
		cmd = "Neotree",
		init = function()
			-- Sessions saved before `sessionoptions-=blank` may already contain a
			-- plain buffer named `neo-tree filesystem [1]`. Load Neo-tree only when
			-- such a legacy entry exists, then let its own cleaner remove it.
			vim.api.nvim_create_autocmd("SessionLoadPost", {
				group = vim.api.nvim_create_augroup("user_neotree_session_cleanup", { clear = true }),
				desc = "Clean invalid Neo-tree buffers restored by old sessions",
				callback = function()
					if not has_invalid_restored_neotree_buffer() then
						return
					end
					require("lazy").load({ plugins = { "neo-tree.nvim" } })
					require("neo-tree.ui.renderer").clean_invalid_neotree_buffers(true)
				end,
			})
		end,
		keys = {
			{
				"<leader>e",
				toggle_explorer,
				desc = "Explorer",
			},
		},
		dependencies = {
			"nvim-lua/plenary.nvim",
			"MunifTanjim/nui.nvim",
			"nvim-mini/mini.icons",
		},
		opts = {
			auto_clean_after_session_restore = true,
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
			-- "" follows 'winborder' for the input and confirmation dialogs.
			popup_border_style = "",
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
				-- Oil owns directory buffers regardless of which browser loads first.
				hijack_netrw_behavior = "disabled",
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
	})
	if mode.capabilities().workspace_tools then
		table.insert(plugins, {
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
					width = require("user.core.panels").left_panel_width,
					relative_width = false,
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
					border = require("user.core.layout").float_border(),
				},
				providers = {
					priority = { "lsp", "markdown", "norg", "treesitter" },
				},
			},
		})
	end
	vim.list_extend(plugins, require("user.specs.flash")())
	return plugins
end
