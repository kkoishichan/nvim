local layout = require("user.core.layout")
local theme = require("user.core.theme")
local lsp_progress = require("user.core.lsp_progress")
local active_theme = theme.saved()

local function dashboard_header()
	return [[
⠀⠀⠀⠀⠀⠀⠈⠉⠛⠻⠿⣿⣿⣿⣷⣤⣔⡺⢿⣿⣶⣤⣄⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠉⠻⣿⣿⣿⣿⣿⣿⣿
⠀⠀⠀⠀⠀⠈⣦⡀⠀⠀⠀⠀⠈⠉⠛⠿⢿⣿⣷⣮⣝⡻⢿⣿⣷⣦⣄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠻⣿⣿⣿⣿⣿
⠀⠀⠀⠀⠀⠀⠘⠻⠳⠦⠀⠀⠀⢀⡀⠀⠀⠌⡙⠻⢿⣿⣷⣬⣛⠿⣿⣿⣦⣄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⢻⣿⣿⣿
⠀⠀⠀⠀⠀⠀⠀⠀⠈⠐⠂⠤⠄⠀⡠⠆⠐⠃⠈⠑⠠⡀⠈⠙⠻⣷⣮⡙⠿⣿⣿⣦⡀⠀⠀⠀⠀⢀⣠⣤⣤⡀⠀⠀⠹⣿⣿
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⠔⠋⠀⢀⣀⣀⠀⠀⠀⠀⠑⠠⡀⠈⠙⠻⢷⣬⡉⠀⠈⠀⠀⣠⣶⣿⣿⣿⣿⣿⡄⠀⠀⠹⣿
⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣾⣷⣾⣿⣿⣿⣿⣿⣿⣿⣣⣾⣶⣦⣤⡁⠀⠀⠀⠙⠻⣷⣄⡠⣾⣿⣿⣿⣿⣿⣿⣿⣇⠀⠀⠀⢿
⠀⠀⠀⠀⠀⠀⠀⠀⣰⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣷⣄⠀⠀⠀⠀⠙⠿⣮⣻⣿⣿⣿⣿⣿⣿⣿⢀⣠⣤⣶
⠀⠀⠀⠀⠀⠀⠀⣼⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣷⠀⡀⠀⠀⠀⠈⠻⣮⣿⣿⣿⣿⣿⡇⢸⣿⣿⣿
⠀⠀⠀⠀⠀⠀⣼⣿⣿⣿⣿⣿⣿⣿⡿⠻⢿⣿⢡⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⢸⣿⣷⡀⣢⡀⠀⠈⠹⣟⢿⣿⣿⠃⣿⣿⣿⣿
⠀⠀⠀⠀⠀⢰⣿⣿⣿⣿⣿⡏⣾⣿⣿⣾⣿⣏⣸⣿⣿⣿⣿⣿⣿⣿⣿⣿⢹⠸⣿⣿⣧⣿⣿⡆⠀⠀⠈⠳⡙⢡⢸⣿⣿⣿⣿
⠀⠀⠀⠀⢀⡿⢻⣿⣿⣿⣿⣧⣿⠿⠛⠛⢿⣿⣿⣿⣿⣿⣿⣿⣿⡿⣿⡟⠸⣄⢿⣿⣿⣿⣿⣿⣦⠀⠀⠀⠙⣆⠻⣿⣿⣿⣿
⠀⠀⠀⠀⢸⠃⢸⣿⣿⣿⣿⠿⠁⣠⣤⠤⠀⢹⣿⡏⢿⣿⣿⣿⣿⢡⠟⠑⠉⠛⠸⣿⡏⣿⣿⣿⣿⡇⠀⠀⠀⠈⢧⡙⠿⠛⠁
⡀⠀⠀⠀⡏⠀⠈⣿⣿⣿⣿⢠⣾⣿⠛⠀⠀⣻⣿⣷⣘⣿⣿⣿⡏⣀⣰⡞⠉⠲⡄⠘⠃⣿⣿⣿⣿⢣⠀⠈⢀⠀⠈⢳⡀⠀⠀
⣿⣷⣄⠀⠃⠀⢠⡹⣿⣷⠸⡟⣿⣿⢺⣬⣦⣿⣿⣿⣿⣾⣿⣟⣾⣿⡏⢀⣀⠀⣿⠀⠀⣿⣿⣿⣿⣾⡄⠀⠀⠠⠀⠀⢻⡄⢠
⣿⣿⣿⡇⢠⢀⣿⣷⣿⣿⠀⣿⣿⣿⣷⣷⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣟⣾⣷⣿⡞⣸⣿⣿⣿⣿⣿⡇⠀⠀⠀⠐⠀⠀⠹⣌
⣿⣿⣿⣿⡞⣸⣿⣿⣿⣿⡇⢿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣷⣿⡿⣱⣿⣿⣿⣿⣿⣿⡟⠀⠀⠀⠀⠈⢀⠀⠹
⣿⣿⣿⣿⢡⣿⣿⣿⣿⣿⣿⠈⢿⣿⣿⣿⣿⣿⣹⣿⣿⣿⣷⡽⣿⣿⣿⣿⣿⢟⠵⣻⣿⣿⣿⣿⣿⣿⠁⠀⠀⠀⠀⠀⠀⠀⠀
⣿⣿⣿⠇⣿⣿⣿⣿⣿⣿⡇⣰⣄⠙⢿⣿⣿⣿⣿⣿⣿⣿⣿⣱⣿⣿⣿⣫⢅⣠⣾⣿⣿⣿⣿⣿⣿⠃⠀⠀⠀⠀⠀⠀⠀⠀⠀
⣿⣿⣿⢰⣿⢿⣿⣿⡿⣿⡇⣿⣿⡟⣤⣉⠻⢿⣿⣿⣿⣿⣿⣿⣿⡿⢋⣵⣿⣿⣿⣿⣿⣿⣿⠟⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⣿⣿⣿⢸⣧⢸⣿⠏⣀⢹⡇⣿⣟⡾⠟⠋⠁⠀⠉⠛⠉⢉⣉⡤⢀⣴⣿⣿⣿⣿⣿⣿⣿⡿⠃⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⣿⣿⣿⣮⣿⡜⣿⠘⠛⠋⢷⠘⠉⠀⠀⠀⠀⣀⣾⣿⡿⢟⠋⣰⣿⣿⣿⡿⠟⡫⣾⢟⠁⣠⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⣿⣿⣿⣿⣿⠟⣹⠀⠀⠀⠈⠣⠀⠀⠀⠀⣿⣿⣿⡫⢖⠋⣼⡿⢛⡋⠁⠒⠋⠈⠀⠁⠚⠻⠿⠳⣦⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀
]]
end

local function pdf_page()
	return require("user.core.pdf").page()
end

local function has_pdf_status()
	return pdf_page() ~= ""
end

local function not_pdf_status()
	return not has_pdf_status()
end

local function pdf_zoom()
	return require("user.core.pdf").zoom()
end

return {
	{
		"nvim-mini/mini.icons",
		lazy = false,
		opts = {},
		config = function(_, opts)
			require("mini.icons").setup(opts)
			MiniIcons.mock_nvim_web_devicons()
		end,
	},
	{
		"Bekaboo/dropbar.nvim",
		event = { "BufReadPost", "BufNewFile" },
		dependencies = { "nvim-mini/mini.icons" },
		opts = {},
		keys = {
			{
				"<leader>cb",
				function()
					require("dropbar.api").pick()
				end,
				desc = "Pick breadcrumb",
			},
		},
	},
	{
		"ellisonleao/gruvbox.nvim",
		name = "gruvbox",
		lazy = active_theme ~= "gruvbox",
		priority = 1001,
		opts = {
			terminal_colors = true,
			undercurl = true,
			underline = true,
			bold = true,
			strikethrough = true,
			invert_selection = false,
			invert_signs = false,
			invert_tabline = false,
			inverse = true,
			contrast = "hard",
			dim_inactive = false,
			transparent_mode = false,
		},
		config = function(_, opts)
			require("gruvbox").setup(opts)
			theme.bootstrap()
		end,
	},
	{
		"folke/tokyonight.nvim",
		lazy = active_theme ~= "tokyonight",
		priority = 1000,
		opts = { style = "night" },
		config = function(_, opts)
			require("tokyonight").setup(opts)
			theme.bootstrap()
		end,
	},
	{
		"catppuccin/nvim",
		name = "catppuccin",
		lazy = active_theme ~= "catppuccin",
		priority = 1000,
		opts = { flavour = "mocha" },
		config = function(_, opts)
			require("catppuccin").setup(opts)
			theme.bootstrap()
		end,
	},
	{
		"folke/snacks.nvim",
		lazy = false,
		priority = 1000,
		opts = {
			bigfile = { enabled = false },
			dashboard = {
				enabled = true,
				width = 50,
				preset = {
					header = dashboard_header(),
					keys = {
						{
							icon = " ",
							key = "f",
							desc = "Find File",
							action = ":lua Snacks.dashboard.pick('files')",
						},
						{ icon = " ", key = "n", desc = "New File", action = ":ene | startinsert" },
						{
							icon = " ",
							key = "g",
							desc = "Find Text",
							action = ":lua Snacks.dashboard.pick('live_grep')",
						},
						{ icon = " ", key = "p", desc = "Projects", action = ":ProjectPick" },
						{ icon = " ", key = "d", desc = "Open Directory", action = ":DirectoryPick" },
						{
							icon = " ",
							key = "s",
							desc = "Restore Session",
							action = ":lua require('persistence').load()",
						},
						{ icon = " ", key = "q", desc = "Quit", action = ":qa" },
					},
				},
				sections = {
					{ section = "header", padding = 2 },
					{ section = "keys", gap = 1, padding = 2 },
					{
						icon = " ",
						title = "Recent Files",
						section = "recent_files",
						indent = 2,
						padding = 2,
						limit = 6,
					},
					{ section = "startup" },
				},
			},
			explorer = { enabled = false },
			image = {
				enabled = false,
				formats = {},
			},
			indent = { enabled = false },
			input = { enabled = true },
			lazygit = { enabled = false },
			notifier = { enabled = false },
			picker = { enabled = false },
			quickfile = { enabled = false },
			scroll = { enabled = false },
			scratch = { enabled = true },
			terminal = { enabled = false },
			words = { enabled = false },
			styles = {
				notification = {
					border = "rounded",
				},
				dashboard = {
					wo = { foldcolumn = "0" },
				},
				scratch = {
					-- Uses the shared accent FloatBorder like every other float; only
					-- remap NormalFloat to keep the editor background.
					-- Size tracks the shared float_scale so it matches lazygit/terminal.
					width = layout.float_scale,
					height = layout.float_scale,
					wo = { winhighlight = "NormalFloat:Normal" },
				},
			},
		},
		keys = {
			{
				"<leader>.",
				function()
					Snacks.scratch()
				end,
				desc = "Scratch buffer",
			},
			{
				"<leader>z",
				function()
					Snacks.zen()
				end,
				desc = "Zen mode",
			},
		},
	},
	{
		"karb94/neoscroll.nvim",
		event = "VeryLazy",
		opts = {
			mappings = {
				"<C-u>",
				"<C-d>",
				"<C-b>",
				"<C-f>",
				"<C-y>",
				"<C-e>",
				"zt",
				"zz",
				"zb",
			},
			hide_cursor = true,
			stop_eof = true,
			respect_scrolloff = true,
			cursor_scrolls_alone = true,
			easing = "quadratic",
			duration_multiplier = 0.8,
			performance_mode = false,
		},
	},
	{
		-- Virtual scrollbar that stripes whole-file markers on the right edge,
		-- the way a modern IDE does: diagnostics, search hits, marks, TODO/FIXME
		-- keywords, merge conflicts, and git add/change/delete bars (wired to
		-- gitsigns below -- scrollview has no built-in git). The scrollbar thumb
		-- already conveys cursor position, so the `cursor` sign is left off.
		-- Diagnostic signs default to E/W/I/H already, matching diagnostics.lua.
		"dstein64/nvim-scrollview",
		event = { "BufReadPost", "BufNewFile" },
		cmd = { "ScrollViewToggle", "ScrollViewEnable", "ScrollViewDisable" },
		dependencies = { "lewis6991/gitsigns.nvim" },
		opts = {
			mode = "virtual",
			winblend = 0,
			signs_on_startup = { "diagnostics", "search", "marks", "keywords", "conflicts" },
			excluded_filetypes = {
				"neo-tree",
				"oil",
				"snacks_dashboard",
				"snacks_picker_input",
				"snacks_picker_list",
				"snacks_notif",
				"notify",
				"TelescopePrompt",
				"fzf",
				"qf",
				"lazy",
				"mason",
				"help",
				"trouble",
			},
		},
		config = function(_, opts)
			local scrollview = require("scrollview")
			scrollview.setup(opts)

			-- Git change bars. scrollview ships no gitsigns integration, so register
			-- a custom sign group that mirrors gitsigns' hunks as the coloured
			-- add/change/delete stripes an IDE draws down the scrollbar.
			local group = "gitsigns"
			scrollview.register_sign_group(group)
			local names = {}
			for kind, spec in pairs({
				add = { symbol = "│", highlight = "GitSignsAdd" },
				change = { symbol = "│", highlight = "GitSignsChange" },
				delete = { symbol = "▁", highlight = "GitSignsDelete" },
			}) do
				names[kind] = scrollview.register_sign_spec({
					group = group,
					symbol = spec.symbol,
					highlight = spec.highlight,
					priority = 60,
				}).name
			end

			scrollview.set_sign_group_callback(group, function()
				local ok, gitsigns = pcall(require, "gitsigns")
				if not ok then
					return
				end
				for _, winid in ipairs(scrollview.get_sign_eligible_windows()) do
					local bufnr = vim.api.nvim_win_get_buf(winid)
					local add, change, delete = {}, {}, {}
					local hunks = gitsigns.get_hunks(bufnr)
					for _, hunk in ipairs(hunks or {}) do
						local start = hunk.added.start
						if hunk.type == "delete" then
							delete[#delete + 1] = start
						else
							local bucket = hunk.type == "add" and add or change
							for ln = start, start + math.max(hunk.added.count - 1, 0) do
								bucket[#bucket + 1] = ln
							end
						end
					end
					vim.b[bufnr][names.add] = add
					vim.b[bufnr][names.change] = change
					vim.b[bufnr][names.delete] = delete
				end
			end)
			scrollview.set_sign_group_state(group, true)

			vim.api.nvim_create_autocmd("User", {
				pattern = "GitSignsUpdate",
				group = vim.api.nvim_create_augroup("user_scrollview_git", { clear = true }),
				callback = function()
					if scrollview.is_sign_group_active(group) then
						vim.cmd("silent! ScrollViewRefresh")
					end
				end,
			})
		end,
		keys = {
			{ "<leader>uv", "<cmd>ScrollViewToggle<cr>", desc = "Toggle scrollbar" },
		},
	},
	{
		"rcarriga/nvim-notify",
		event = "VeryLazy",
		cmd = "Notifications",
		opts = {
			background_colour = "NotifyBackground",
			fps = 60,
			level = vim.log.levels.INFO,
			max_width = function()
				return math.min(math.max(math.floor(vim.o.columns * 0.38), 44), 72)
			end,
			max_height = function()
				return math.min(math.max(math.floor(vim.o.lines * 0.5), 10), 20)
			end,
			minimum_width = 44,
			render = "default",
			stages = "slide",
			timeout = 3000,
			top_down = true,
		},
		config = function(_, opts)
			require("user.core.ui_highlights").apply()
			local notify = require("notify")
			-- Tear down the previous generation while its nvim-notify service is
			-- still current. notify.setup() replaces that service, after which its
			-- timeout=false progress windows could no longer be dismissed publicly.
			local previous_cleanup = rawget(vim, "_user_lsp_progress_cleanup")
			if type(previous_cleanup) == "function" then
				pcall(previous_cleanup)
			end
			notify.setup(opts)
			local function stable_notify(message, level, notify_opts)
				if notify_opts and notify_opts.replace and notify_opts.animate == nil then
					notify_opts = vim.tbl_extend("force", notify_opts, { animate = false })
				end

				return notify(message, level, notify_opts)
			end

			vim.notify = stable_notify
			lsp_progress.setup(stable_notify, function()
				notify.dismiss({ pending = true, silent = true })
			end)
		end,
		keys = {
			{ "<leader>n", "<cmd>Notifications<cr>", desc = "Notifications" },
			{
				"<leader>un",
				function()
					require("notify").dismiss({ pending = true, silent = true })
				end,
				desc = "Dismiss notifications",
			},
		},
	},
	{
		"akinsho/bufferline.nvim",
		version = "*",
		event = "VeryLazy",
		dependencies = { "nvim-mini/mini.icons" },
		opts = {
			options = {
				mode = "buffers",
				themable = true,
				numbers = "ordinal",
				close_command = function(bufnr)
					vim.api.nvim_buf_delete(bufnr, { force = false })
				end,
				right_mouse_command = function(bufnr)
					vim.api.nvim_buf_delete(bufnr, { force = false })
				end,
				left_mouse_command = "buffer %d",
				middle_mouse_command = nil,
				indicator = {
					style = "underline",
				},
				buffer_close_icon = "×",
				close_icon = "×",
				modified_icon = "●",
				left_trunc_marker = "",
				right_trunc_marker = "",
				max_name_length = 24,
				max_prefix_length = 16,
				truncate_names = true,
				separator_style = "thin",
				diagnostics = "nvim_lsp",
				diagnostics_update_in_insert = false,
				diagnostics_indicator = function(_, _, diagnostics_dict)
					local parts = {}
					if diagnostics_dict.error then
						table.insert(parts, " " .. diagnostics_dict.error)
					end
					if diagnostics_dict.warning then
						table.insert(parts, " " .. diagnostics_dict.warning)
					end
					if diagnostics_dict.info then
						table.insert(parts, " " .. diagnostics_dict.info)
					end
					if diagnostics_dict.hint then
						table.insert(parts, "󰌵 " .. diagnostics_dict.hint)
					end

					return #parts > 0 and " " .. table.concat(parts, " ") or ""
				end,
				offsets = {
					{
						filetype = "neo-tree",
						text = "Explorer",
						highlight = "Directory",
						text_align = "left",
						separator = true,
					},
				},
				show_buffer_close_icons = false,
				show_close_icon = false,
				show_duplicate_prefix = true,
				always_show_bufferline = false,
				hover = {
					enabled = true,
					delay = 150,
					reveal = { "close" },
				},
			},
		},
		keys = {
			{ "[b", "<cmd>BufferLineCyclePrev<cr>", desc = "Previous buffer" },
			{ "]b", "<cmd>BufferLineCycleNext<cr>", desc = "Next buffer" },
			{ "<M-1>", "<cmd>BufferLineGoToBuffer 1<cr>", desc = "Buffer 1" },
			{ "<M-2>", "<cmd>BufferLineGoToBuffer 2<cr>", desc = "Buffer 2" },
			{ "<M-3>", "<cmd>BufferLineGoToBuffer 3<cr>", desc = "Buffer 3" },
			{ "<M-4>", "<cmd>BufferLineGoToBuffer 4<cr>", desc = "Buffer 4" },
			{ "<M-5>", "<cmd>BufferLineGoToBuffer 5<cr>", desc = "Buffer 5" },
			{ "<M-6>", "<cmd>BufferLineGoToBuffer 6<cr>", desc = "Buffer 6" },
			{ "<M-7>", "<cmd>BufferLineGoToBuffer 7<cr>", desc = "Buffer 7" },
			{ "<M-8>", "<cmd>BufferLineGoToBuffer 8<cr>", desc = "Buffer 8" },
			{ "<M-9>", "<cmd>BufferLineGoToBuffer 9<cr>", desc = "Buffer 9" },
			{ "<M-0>", "<cmd>BufferLineGoToBuffer -1<cr>", desc = "Last buffer" },
			{ "[B", "<cmd>BufferLineMovePrev<cr>", desc = "Move buffer left" },
			{ "]B", "<cmd>BufferLineMoveNext<cr>", desc = "Move buffer right" },
			{ "<leader>bp", "<cmd>BufferLinePick<cr>", desc = "Pick buffer" },
			{
				"<leader>bd",
				function()
					vim.api.nvim_buf_delete(0, { force = false })
				end,
				desc = "Close current buffer",
			},
			{ "<leader>bD", "<cmd>BufferLinePickClose<cr>", desc = "Pick buffer close" },
			{ "<leader>bP", "<cmd>BufferLineTogglePin<cr>", desc = "Toggle buffer pin" },
			{ "<leader>bo", "<cmd>BufferLineCloseOthers<cr>", desc = "Close other buffers" },
			{ "<leader>bl", "<cmd>BufferLineCloseLeft<cr>", desc = "Close buffers left" },
			{ "<leader>br", "<cmd>BufferLineCloseRight<cr>", desc = "Close buffers right" },
		},
	},
	{
		"nvim-lualine/lualine.nvim",
		event = "VeryLazy",
		ft = "pdf",
		dependencies = { "nvim-mini/mini.icons" },
		opts = {
			options = {
				theme = "auto",
				globalstatus = true,
				component_separators = "",
				section_separators = "",
			},
			sections = {
				lualine_a = {
					"mode",
				},
				lualine_b = {
					"branch",
					{
						"diff",
						symbols = { added = "+", modified = "~", removed = "-" },
					},
				},
				lualine_c = {
					{ "filename", path = 1 },
				},
				lualine_x = {
					{
						"diagnostics",
						sources = { "nvim_diagnostic" },
						update_in_insert = false,
					},
					{
						"lsp_status",
						ignore_lsp = { "null-ls" },
					},
					{
						"filetype",
						icon_only = false,
					},
				},
				lualine_y = {
					{
						"progress",
						cond = not_pdf_status,
					},
					{
						pdf_zoom,
						cond = has_pdf_status,
					},
				},
				lualine_z = {
					{
						"location",
						cond = not_pdf_status,
					},
					{
						pdf_page,
						cond = has_pdf_status,
					},
				},
			},
		},
		config = function(_, opts)
			local lualine = require("lualine")
			lualine.setup(opts)
			-- theme = "auto" only resolves at setup time, so re-run setup on a
			-- colorscheme switch to refresh the statusline colours live.
			vim.api.nvim_create_autocmd("ColorScheme", {
				group = vim.api.nvim_create_augroup("user_lualine_theme", { clear = true }),
				callback = function()
					lualine.setup(opts)
				end,
			})
		end,
	},
	{
		"folke/which-key.nvim",
		event = "VeryLazy",
		opts = function()
			-- Register every group label for normal AND visual mode, so the leader
			-- popup shows names in visual mode too (which-key prunes groups that have
			-- no mappings in the current mode).
			local groups = {
				{ "<leader>a", group = "ai" },
				{ "<leader>b", group = "buffer" },
				{ "<leader>c", group = "code" },
				{ "<leader>cp", group = "peek" },
				{ "<leader>d", group = "debug" },
				{ "<leader>f", group = "find" },
				{ "<leader>g", group = "git" },
				{ "<leader>gh", group = "hunk" },
				{ "<leader>gx", group = "conflict" },
				{ "<leader>j", group = "job" },
				{ "<leader>m", group = "markup" },
				{ "<leader>r", group = "test" },
				{ "<leader>s", group = "session" },
				{ "<leader>t", group = "terminal" },
				{ "<leader>u", group = "ui" },
				{ "<leader>v", group = "multicursor" },
				{ "<leader>x", group = "diagnostics" },
				{ "gs", group = "surround" },
			}
			for _, g in ipairs(groups) do
				g.mode = { "n", "x" }
			end
			return {
				preset = "modern",
				delay = 300,
				spec = groups,
				icons = {
					-- which-key's default Space icon is "󱁐 " -- a glyph followed by a
					-- trailing space, which makes the leader popup title read as the
					-- symbol plus a stray space. Use a plain space symbol, no trailing space.
					keys = { Space = "␣" },
				},
			}
		end,
	},
}
