local layout = require("user.core.layout")

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

local function setup_lsp_progress_notifications(notify)
	local spinner = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
	local spinner_interval = 120
	local frame = 1
	local progress = {}
	local records = {}
	local timer = vim.uv.new_timer()
	local spinner_running = false

	local function has_active_progress()
		for _, items in pairs(progress) do
			if #items > 0 then
				return true
			end
		end
		return false
	end

	local function progress_message(items)
		local lines = {}
		for _, item in ipairs(items) do
			table.insert(lines, item.message)
		end
		return table.concat(lines, "\n")
	end

	local function notify_client_progress(client, items, done_items)
		local active = #items > 0
		local message = progress_message(active and items or done_items)

		if message == "" then
			return
		end

		records[client.id] = notify(message, vim.log.levels.INFO, {
			title = client.name,
			icon = active and spinner[frame] or " ",
			replace = records[client.id],
			timeout = active and false or 1200,
			hide_from_history = active,
			animate = records[client.id] == nil,
		})

		if not active then
			vim.defer_fn(function()
				records[client.id] = nil
			end, 1300)
		end
	end

	local function redraw_spinner()
		frame = frame % #spinner + 1

		for client_id, items in pairs(progress) do
			if #items > 0 then
				local client = vim.lsp.get_client_by_id(client_id)
				if client then
					notify_client_progress(client, items, items)
				end
			end
		end

		if not has_active_progress() then
			timer:stop()
			spinner_running = false
		end
	end

	local function start_spinner()
		if spinner_running then
			return
		end

		spinner_running = true
		timer:start(0, spinner_interval, vim.schedule_wrap(redraw_spinner))
	end

	vim.api.nvim_create_autocmd("LspProgress", {
		group = vim.api.nvim_create_augroup("user_lsp_progress_notify", { clear = true }),
		callback = function(event)
			local client = vim.lsp.get_client_by_id(event.data.client_id)
			local params = event.data.params
			local value = params and params.value
			if not client or type(value) ~= "table" then
				return
			end

			local client_progress = progress[client.id] or {}
			progress[client.id] = client_progress

			local percentage = value.kind == "end" and 100 or value.percentage or 0
			local title = value.title or "Working"
			local message = value.message and (" " .. value.message) or ""
			local progress_item = {
				token = params.token,
				message = ("[%3d%%] %s%s"):format(percentage, title, message),
				done = value.kind == "end",
			}

			local updated = false
			for index, item in ipairs(client_progress) do
				if item.token == params.token then
					client_progress[index] = progress_item
					updated = true
					break
				end
			end
			if not updated then
				table.insert(client_progress, progress_item)
			end

			local done_items = {}
			local active_items = {}
			for _, item in ipairs(client_progress) do
				table.insert(done_items, item)
				if not item.done then
					table.insert(active_items, item)
				end
			end

			progress[client.id] = active_items
			notify_client_progress(client, active_items, done_items)

			if has_active_progress() then
				start_spinner()
			else
				timer:stop()
				spinner_running = false
			end
		end,
	})
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
		-- gruvbox is the default + fallback, so it loads eagerly and hosts the
		-- theme bootstrap: it registers the theme-following UI highlights and then
		-- applies the persisted colorscheme (which may lazy-load another theme).
		"ellisonleao/gruvbox.nvim",
		name = "gruvbox",
		lazy = false,
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
			invert_intend_guides = false,
			inverse = true,
			contrast = "hard",
			dim_inactive = false,
			transparent_mode = false,
		},
		config = function(_, opts)
			vim.o.background = "dark"
			require("gruvbox").setup(opts)
			require("user.core.ui_highlights").setup()
			require("user.core.theme").apply_saved()
		end,
	},
	{
		"folke/tokyonight.nvim",
		lazy = true,
		priority = 1000,
		opts = { style = "night" },
	},
	{
		"catppuccin/nvim",
		name = "catppuccin",
		lazy = true,
		priority = 1000,
		opts = { flavour = "mocha" },
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
		config = function(_, opts)
			require("snacks").setup(opts)
			Snacks.input.enable()
		end,
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
		"rcarriga/nvim-notify",
		event = "VeryLazy",
		cmd = "Notifications",
		opts = {
			background_colour = "NotifyBackground",
			fps = 60,
			level = vim.log.levels.INFO,
			max_width = function()
				return math.min(math.max(math.floor(vim.o.columns * 0.38), 42), 72)
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
			notify.setup(opts)
			local function stable_notify(message, level, notify_opts)
				if notify_opts and notify_opts.replace and notify_opts.animate == nil then
					notify_opts = vim.tbl_extend("force", notify_opts, { animate = false })
				end

				return notify(message, level, notify_opts)
			end

			vim.notify = stable_notify
			setup_lsp_progress_notifications(stable_notify)
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
