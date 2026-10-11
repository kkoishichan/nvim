local layout = require("user.core.layout")
local palette = require("user.core.palette")
local lsp_progress = require("user.core.lsp_progress")
local icons = require("user.core.icons")
local scrollview_symbols = {
	diagnostics = icons.diagnostics.letters,
	search = "━",
	git = icons.git.bar,
	keywords = {
		fix = vim.fn.nr2char(0xF188),
		todo = vim.fn.nr2char(0xF00C),
		hack = vim.fn.nr2char(0xF490),
		warn = vim.fn.nr2char(0xF071),
		xxx = vim.fn.nr2char(0xF071),
	},
	conflict = "×",
}

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

-- Two designs, one per background. Opaque is built from layers: the bar is
-- one step below the editor, the current tab is cut out of it in the editor
-- colour, nothing is drawn as a line. Transparent is built from lines and
-- type: no fill anywhere, the whole bar underlined in one line colour, the
-- current tab told apart by its text alone. Both read the palette, so a theme
-- or transparency switch rebuilds them through bufferline's own refresh.
local function bufferline_highlights(defaults)
	local p = palette.get()
	local transparent = p.surface == nil
	-- No separator glyphs in either design: fills (opaque) or the shared
	-- underline (transparent) are enough. Decided here so a user option
	-- cannot override it.
	defaults.options.separator_style = { " ", " " }
	local highlights = {}
	local function state_of(name)
		if name:match("_selected$") then
			return "selected"
		elseif name:match("_visible$") then
			return "visible"
		end
		return "inactive"
	end
	local text = { inactive = p.muted, visible = p.dim, selected = p.fg }
	local function surface(state)
		if transparent then
			return { bg = "NONE", ctermbg = "NONE", underline = true, sp = p.line }
		end
		return { bg = state == "selected" and p.bg or p.sunken }
	end
	for name in pairs(defaults.highlights) do
		local state = state_of(name)
		local value = surface(state)
		value.fg = text[state]
		value.bold, value.italic = false, false
		highlights[name] = value
	end
	-- The name takes the colour of its worst problem; counts are not shown.
	for _, pair in ipairs({ { "error", p.error }, { "warning", p.warn } }) do
		for _, suffix in ipairs({ "", "_visible", "_selected" }) do
			highlights[pair[1] .. suffix].fg = pair[2]
		end
	end
	for _, suffix in ipairs({ "", "_visible", "_selected" }) do
		highlights["modified" .. suffix].fg = p.accent
		highlights["pick" .. suffix].fg = p.accent
		highlights["pick" .. suffix].bold = true
	end
	highlights.trunc_marker.fg = p.dim
	highlights.fill = surface("inactive")

	-- The sidebar title and the divider cell above the file tree, and the
	-- workspace name on the right. Both are plain groups outside bufferline's
	-- table. The title heads the sidebar, not the tab list, so it carries no
	-- underline; the workspace name does, as part of the bar.
	local offset = { fg = palette.highlight("Directory").fg or p.fg }
	local workspace = { fg = p.dim }
	if transparent then
		workspace = vim.tbl_extend("force", workspace, surface("inactive"))
		highlights.offset_separator = { fg = p.line, bg = "NONE", ctermbg = "NONE" }
	else
		local sidebar = palette.highlight("NeoTreeNormal")
		local divider = palette.highlight("NeoTreeWinSeparator")
		if not next(divider) then
			divider = palette.highlight("WinSeparator")
		end
		offset.bg = sidebar.bg or p.bg
		workspace.bg = p.sunken
		highlights.offset_separator = { fg = divider.fg or p.line, bg = divider.bg or p.bg }
	end
	vim.api.nvim_set_hl(0, "UserBufferlineOffset", offset)
	vim.api.nvim_set_hl(0, "UserBufferlineWorkspace", workspace)
	return highlights
end

return function(profile)
	profile = profile or {}
	local workspace_tools = require("user.core.mode").capabilities().workspace_tools
	local plugins = vim.list_extend(require("user.specs.theme")(), require("user.specs.which_key")())
	local snacks_keys = {
		{
			"<leader>z",
			function()
				Snacks.zen()
			end,
			desc = "Zen mode",
		},
	}
	if workspace_tools then
		table.insert(snacks_keys, 1, {
			"<leader>.",
			function()
				Snacks.scratch()
			end,
			desc = "Scratch buffer",
		})
	end
	table.insert(plugins, {
		"nvim-mini/mini.icons",
		lazy = false,
		opts = {},
		config = function(_, opts)
			require("mini.icons").setup(opts)
			MiniIcons.mock_nvim_web_devicons()
		end,
	})
	if profile.extra then
		table.insert(plugins, {
			"Bekaboo/dropbar.nvim",
			event = { "BufReadPost", "BufNewFile" },
			dependencies = { "nvim-mini/mini.icons" },
			opts = {
				bar = {
					-- Coalesce context updates while a repeated movement key is held.
					update_debounce = 80,
				},
			},
			keys = {
				{
					"<leader>cb",
					function()
						require("dropbar.api").pick()
					end,
					desc = "Pick breadcrumb",
				},
			},
		})
	end
	table.insert(plugins, {
		"folke/snacks.nvim",
		lazy = false,
		priority = 1000,
		opts = {
			bigfile = { enabled = false },
			dashboard = {
				enabled = require("user.core.mode").capabilities().docking,
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
							action = ":lua require('user.core.session').load()",
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
			scratch = { enabled = workspace_tools },
			terminal = { enabled = false },
			words = { enabled = false },
			styles = {
				input = {
					keys = {
						-- One Escape cancels the prompt; Snacks otherwise uses the
						-- first press only to leave Insert mode.
						i_esc = { "<Esc>", { "cmp_close", "cancel" }, mode = "i", expr = true },
					},
				},
				dashboard = {
					wo = { foldcolumn = "0" },
				},
				scratch = {
					-- An application float: the shared rectangle on the float surface.
					width = layout.float_scale,
					height = layout.float_scale,
					wo = { winhighlight = "Normal:NormalFloat,NormalNC:NormalFloat" },
				},
				zen = {
					backdrop = { transparent = true, blend = layout.backdrop_blend },
				},
			},
		},
		keys = snacks_keys,
	})
	table.insert(plugins, {
		"karb94/neoscroll.nvim",
		keys = {
			{ "<C-u>", mode = { "n", "x" } },
			{ "<C-d>", mode = { "n", "x" } },
			{ "<C-b>", mode = { "n", "x" } },
			{ "<C-f>", mode = { "n", "x" } },
			{ "<C-y>", mode = { "n", "x" } },
			{ "<C-e>", mode = { "n", "x" } },
			{ "zt", mode = { "n", "x" } },
			{ "zz", mode = { "n", "x" } },
			{ "zb", mode = { "n", "x" } },
		},
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
			duration_multiplier = 0.65,
			performance_mode = false,
		},
	})
	if profile.extra then
		table.insert(plugins, {
			-- A single overview rail: diagnostics, search hits, marks, TODO/FIXME,
			-- conflicts, and Git changes all occupy the same stable rightmost column.
			-- Every source occupies one cell but has its own shape, so colour conveys
			-- severity while shape conveys provenance. Vim marks retain their letters
			-- because those are the actual jump targets. The scrollbar thumb already
			-- conveys cursor position, so no cursor sign is needed.
			"dstein64/nvim-scrollview",
			event = { "BufReadPost", "BufNewFile" },
			cmd = { "ScrollViewToggle", "ScrollViewEnable", "ScrollViewDisable" },
			dependencies = { "lewis6991/gitsigns.nvim" },
			opts = {
				mode = "virtual",
				visibility = "overflow",
				winblend = 0,
				winblend_gui = 0,
				hide_on_float_intersect = true,
				signs_scrollbar_overlap = "over",
				signs_max_per_row = 1,
				signs_on_startup = { "diagnostics", "search", "marks", "keywords", "conflicts" },
				diagnostics_error_priority = 100,
				diagnostics_warn_priority = 90,
				diagnostics_info_priority = 60,
				diagnostics_hint_priority = 40,
				diagnostics_error_symbol = scrollview_symbols.diagnostics.error,
				diagnostics_warn_symbol = scrollview_symbols.diagnostics.warn,
				diagnostics_info_symbol = scrollview_symbols.diagnostics.info,
				diagnostics_hint_symbol = scrollview_symbols.diagnostics.hint,
				conflicts_top_priority = 95,
				conflicts_middle_priority = 95,
				conflicts_bottom_priority = 95,
				conflicts_top_symbol = scrollview_symbols.conflict,
				conflicts_middle_symbol = scrollview_symbols.conflict,
				conflicts_bottom_symbol = scrollview_symbols.conflict,
				search_priority = 80,
				search_symbol = scrollview_symbols.search,
				marks_priority = 75,
				keywords_fix_priority = 50,
				keywords_hack_priority = 50,
				keywords_todo_priority = 50,
				keywords_warn_priority = 50,
				keywords_xxx_priority = 50,
				keywords_fix_symbol = scrollview_symbols.keywords.fix,
				keywords_hack_symbol = scrollview_symbols.keywords.hack,
				keywords_todo_symbol = scrollview_symbols.keywords.todo,
				keywords_warn_symbol = scrollview_symbols.keywords.warn,
				keywords_xxx_symbol = scrollview_symbols.keywords.xxx,
				excluded_filetypes = {
					"neo-tree",
					"oil",
					"snacks_dashboard",
					"notify",
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
				require("user.core.adapters").run("scrollview_refresh", function()
					return require("user.core.scrollview_refresh").setup()
				end)
				local cleanup_key = "_user_scrollview_git_cleanup"
				local previous_cleanup = rawget(vim, cleanup_key)
				if type(previous_cleanup) == "function" then
					previous_cleanup()
				end

				-- Git change bars. scrollview ships no gitsigns integration, so register
				-- a custom sign group that mirrors gitsigns' hunks as the coloured
				-- add/change/delete stripes an IDE draws down the scrollbar.
				local group = "gitsigns"
				scrollview.register_sign_group(group)
				local names = {}
				for kind, spec in pairs({
					add = { highlight = "GitSignsAdd", priority = 30 },
					change = { highlight = "GitSignsChange", priority = 31 },
					delete = { highlight = "GitSignsDelete", priority = 32 },
				}) do
					names[kind] = scrollview.register_sign_spec({
						group = group,
						symbol = scrollview_symbols.git,
						highlight = spec.highlight,
						priority = spec.priority,
					}).name
				end

				local rendered = {}
				scrollview.set_sign_group_callback(group, function()
					local ok, gitsigns = pcall(require, "gitsigns")
					if not ok then
						return
					end
					local seen = {}
					for _, winid in ipairs(scrollview.get_sign_eligible_windows()) do
						local bufnr = vim.api.nvim_win_get_buf(winid)
						-- Sign locations belong to the buffer, even when several splits
						-- show it. get_hunks also constructs patch text, so call it once.
						if not seen[bufnr] then
							seen[bufnr] = true
							local add, change, delete = {}, {}, {}
							local hunks = gitsigns.get_hunks(bufnr)
							local changed_lines = 0
							for _, hunk in ipairs(hunks or {}) do
								changed_lines = changed_lines + math.max(hunk.added.count, 1)
							end
							local expand_hunks = changed_lines <= 1000
							for _, hunk in ipairs(hunks or {}) do
								local start = hunk.added.start
								if hunk.type == "delete" then
									delete[#delete + 1] = start
								else
									local bucket = hunk.type == "add" and add or change
									local count = math.max(hunk.added.count, 1)
									bucket[#bucket + 1] = start
									if expand_hunks then
										for line = start + 1, start + count - 1 do
											bucket[#bucket + 1] = line
										end
									elseif count > 1 then
										bucket[#bucket + 1] = start + count - 1
									end
								end
							end
							local lines = { add = add, change = change, delete = delete }
							-- Scrolling still reads the latest hunks, but unchanged signs do
							-- not need another Lua-to-Vim copy of all changed line numbers.
							if not vim.deep_equal(rendered[bufnr], lines) then
								for kind, values in pairs(lines) do
									vim.b[bufnr][names[kind]] = values
								end
								rendered[bufnr] = lines
							end
						end
					end
				end)
				scrollview.set_sign_group_state(group, true)

				local refresh_generation = 0
				local refresh_timer
				local closed = false
				local function cleanup()
					closed = true
					if refresh_timer then
						refresh_timer:stop()
						if not refresh_timer:is_closing() then
							refresh_timer:close()
						end
						refresh_timer = nil
					end
					if rawget(vim, cleanup_key) == cleanup then
						rawset(vim, cleanup_key, nil)
					end
				end
				rawset(vim, cleanup_key, cleanup)
				local refresh_group = vim.api.nvim_create_augroup("user_scrollview_git", { clear = true })
				vim.api.nvim_create_autocmd("VimLeavePre", { group = refresh_group, once = true, callback = cleanup })
				vim.api.nvim_create_autocmd("BufWipeout", {
					group = refresh_group,
					callback = function(event)
						rendered[event.buf] = nil
					end,
				})
				vim.api.nvim_create_autocmd("User", {
					pattern = "GitSignsUpdate",
					group = refresh_group,
					callback = function()
						if closed then
							return
						end
						refresh_generation = refresh_generation + 1
						local generation = refresh_generation
						-- Restart one timer instead of allocating one timer per update.
						refresh_timer = refresh_timer or vim.uv.new_timer()
						refresh_timer:start(
							120,
							0,
							vim.schedule_wrap(function()
								if
									not closed
									and generation == refresh_generation
									and scrollview.is_sign_group_active(group)
								then
									scrollview.refresh()
								end
							end)
						)
					end,
				})
			end,
			keys = {
				{ "<leader>uv", "<cmd>ScrollViewToggle<cr>", desc = "Toggle scrollbar" },
			},
		})
	end
	table.insert(plugins, {
		"rcarriga/nvim-notify",
		event = "VeryLazy",
		cmd = "Notifications",
		opts = {
			background_colour = "NotifyBackground",
			fps = 30,
			level = vim.log.levels.INFO,
			max_width = function()
				return math.min(math.max(math.floor(vim.o.columns * 0.38), 44), 72)
			end,
			max_height = function()
				return math.min(math.max(math.floor(vim.o.lines * 0.5), 10), 20)
			end,
			minimum_width = 44,
			render = function(...)
				return require("user.core.notify_style").render(...)
			end,
			stages = "fade",
			timeout = 3000,
			top_down = true,
		},
		config = function(_, opts)
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
	})
	table.insert(plugins, {
		"akinsho/bufferline.nvim",
		version = "*",
		event = "VeryLazy",
		dependencies = { "nvim-mini/mini.icons" },
		opts = function()
			return {
				highlights = bufferline_highlights,
				options = {
					mode = "buffers",
					-- themable sets every group with default = true, which lets a
					-- theme that ships bufferline groups (vscode) override the two
					-- designs above. Ours are the only source.
					themable = false,
					numbers = "none",
					close_command = function(bufnr)
						require("user.core.buffers").close(bufnr)
					end,
					right_mouse_command = function(bufnr)
						require("user.core.buffers").close(bufnr)
					end,
					middle_mouse_command = function(bufnr)
						require("user.core.buffers").close(bufnr)
					end,
					left_mouse_command = "buffer %d",
					indicator = { style = "none" },
					modified_icon = icons.modified,
					left_trunc_marker = "",
					right_trunc_marker = "",
					max_name_length = 24,
					max_prefix_length = 16,
					-- Size each tab to its name; the default pads every tab to 18
					-- cells and splits the padding unevenly.
					tab_size = 0,
					truncate_names = true,
					-- A tab is icon, name and modified mark, and never changes width:
					-- no close buttons (right or middle click and <leader>bd close),
					-- no counts. Problems colour the name (see bufferline_highlights).
					diagnostics = "nvim_lsp",
					diagnostics_update_in_insert = false,
					diagnostics_indicator = function()
						return ""
					end,
					custom_filter = require("user.core.tabbar").belongs,
					custom_areas = {
						right = function()
							return {
								{
									text = " " .. require("user.core.tabbar").label() .. " ",
									link = "UserBufferlineWorkspace",
								},
							}
						end,
					},
					offsets = {
						{
							filetype = "neo-tree",
							text = "Explorer",
							highlight = "UserBufferlineOffset",
							text_align = "left",
							separator = true,
						},
					},
					show_buffer_close_icons = false,
					show_close_icon = false,
					show_duplicate_prefix = true,
					-- One file needs no list; the bar (and the workspace label on its
					-- right) appears once there is a choice to make. bufferline counts
					-- every listed buffer for that, so the workspace-aware count in
					-- the config below decides instead.
					always_show_bufferline = false,
					auto_toggle_bufferline = false,
					-- New files open beside the one being read, not at the far end.
					sort_by = "insert_after_current",
					groups = {
						items = {
							require("bufferline.groups").builtin.pinned:with({ icon = icons.pinned }),
						},
					},
				},
			}
		end,
		config = function(_, opts)
			require("bufferline").setup(opts)
			require("user.core.tabbar").setup()
		end,
		keys = {
			{ "[b", "<cmd>BufferLineCyclePrev<cr>", desc = "Previous buffer" },
			{ "]b", "<cmd>BufferLineCycleNext<cr>", desc = "Next buffer" },
			{ "[B", "<cmd>BufferLineMovePrev<cr>", desc = "Move buffer left" },
			{ "]B", "<cmd>BufferLineMoveNext<cr>", desc = "Move buffer right" },
			{ "<leader>bp", "<cmd>BufferLinePick<cr>", desc = "Pick buffer" },
			{
				"<leader>bd",
				function()
					require("user.core.buffers").close()
				end,
				desc = "Close current buffer",
			},
			{ "<leader>bD", "<cmd>BufferLinePickClose<cr>", desc = "Pick buffer close" },
			{ "<leader>bP", "<cmd>BufferLineTogglePin<cr>", desc = "Toggle buffer pin" },

			{ "<leader>bo", "<cmd>BufferLineCloseOthers<cr>", desc = "Close other buffers" },
			{ "<leader>bl", "<cmd>BufferLineCloseLeft<cr>", desc = "Close buffers left" },
			{ "<leader>br", "<cmd>BufferLineCloseRight<cr>", desc = "Close buffers right" },
		},
	})
	vim.list_extend(plugins, require("user.specs.statusline")())
	return plugins
end
