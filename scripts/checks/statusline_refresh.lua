return function(tmp)
	local api = vim.api
	require("lazy").load({ plugins = { "lualine.nvim" } })
	local lualine = require("lualine")
	local refresh = require("user.core.statusline_refresh")
	local original_config = lualine.get_config()
	local original_ignore, original_columns = vim.o.eventignore, vim.o.columns
	local original_background = vim.o.background
	local original_theme = vim.g.colors_name or "default"
	local original_tab = api.nvim_get_current_tabpage()
	local count = 0
	local evidence = {}
	local opts = vim.deepcopy(original_config)
	opts.options.globalstatus = true
	-- Suppress the unrelated 1 s fallback while counting one event batch. The
	-- real plugin's default 16 ms queue and original events remain unchanged.
	opts.options.refresh.statusline = 60000
	opts.sections = {
		lualine_a = { "mode" },
		lualine_b = {},
		lualine_c = {
			function()
				count = count + 1
				return "counted"
			end,
			{ "filename", path = 2 },
		},
		lualine_x = {},
		lualine_y = {},
		lualine_z = { "location" },
	}
	opts.inactive_sections = vim.deepcopy(opts.sections)
	local function settle()
		vim.wait(40, function()
			return false
		end, 1)
	end
	local function fire(event, repetitions)
		settle()
		count = 0
		for _ = 1, repetitions or 1 do
			api.nvim_exec_autocmds(event, { group = "lualine_stl_refresh", modeline = false })
		end
		assert(count == 0, "Statusline event bypassed lualine's queued refresh")
		settle()
		return count
	end
	local function event_names()
		local names = {}
		for _, registration in ipairs(api.nvim_get_autocmds({ group = "lualine_stl_refresh" })) do
			names[#names + 1] = registration.event
		end
		table.sort(names)
		return names
	end
	local function scope_is_correct()
		for _, registration in ipairs(api.nvim_get_autocmds({ group = "lualine_stl_refresh" })) do
			assert(
				registration.command:find("'scope': 'window'", 1, true),
				"A theme event restored the wrong refresh scope"
			)
		end
	end
	local test_tab
	local theme_events = 0
	local observer = api.nvim_create_augroup("statusline_refresh_check", { clear = true })
	api.nvim_create_autocmd("ColorScheme", {
		group = observer,
		callback = function()
			theme_events = theme_events + 1
		end,
	})
	local ok, err = xpcall(function()
		vim.o.eventignore = "all"
		vim.o.columns = 220
		vim.cmd.tabnew()
		test_tab = api.nvim_get_current_tabpage()
		vim.o.eventignore = original_ignore
		for _, size in ipairs({ 2, 4 }) do
			vim.o.eventignore = "all"
			while #api.nvim_tabpage_list_wins(0) < size do
				vim.cmd.vsplit()
			end
			vim.o.eventignore = original_ignore
			-- Real setup recreates the locked plugin's original registrations,
			-- including when the production config already installs the adapter.
			lualine.setup(opts)
			settle()
			local events = event_names()
			local before = fire("CursorMoved")
			assert(before == size, "Could not reproduce the locked global statusline scope defect")
			assert(refresh.setup() == #events, "Not all original refresh registrations were corrected")
			assert(vim.deep_equal(events, event_names()), "Statusline refresh changed its event list")
			assert(lualine.get_config().options.refresh.refresh_time == 16, "Refresh coalescing changed")
			local after = fire("CursorMoved")
			assert(after == 1, "Global statusline still recomputed once per split")
			assert(fire("CursorMovedI", 20) == 1, "Insert cursor burst was not coalesced into one refresh")
			assert(refresh.setup() == 0, "Repeated adapter setup was not idempotent")
			evidence[#evidence + 1] = { windows = size, original_calls = before, corrected_calls = after }
		end

		local buffer = api.nvim_create_buf(true, false)
		api.nvim_buf_set_name(buffer, tmp .. "/statusline-first.txt")
		api.nvim_buf_set_lines(buffer, 0, -1, false, { "first", "second", "third" })
		api.nvim_set_current_buf(buffer)
		api.nvim_win_set_cursor(0, { 2, 3 })
		assert(fire("BufEnter") == 1, "File switch triggered duplicate refreshes")
		local line = vim.wo.statusline
		assert(line:find("statusline%-first.txt"), "Refreshed statusline lost its filename")
		assert(line:match("2:4"), "Refreshed statusline lost its cursor location")
		api.nvim_buf_set_name(buffer, tmp .. "/statusline-renamed.txt")
		assert(fire("BufWritePost") == 1, "Write-triggered refresh duplicated work")
		assert(vim.wo.statusline:find("statusline%-renamed.txt"), "Filename did not update after rename")
		assert(fire("ModeChanged") == 1, "Mode-change refresh lost its window scope")
		local focused = api.nvim_get_current_win()
		local other = vim.tbl_filter(function(win)
			return win ~= focused
		end, api.nvim_tabpage_list_wins(0))[1]
		local other_buffer = api.nvim_create_buf(true, false)
		api.nvim_buf_set_name(other_buffer, tmp .. "/statusline-other.txt")
		api.nvim_buf_set_lines(other_buffer, 0, -1, false, { "first", "second", "third" })
		api.nvim_win_set_buf(other, other_buffer)
		api.nvim_set_current_win(other)
		api.nvim_win_set_cursor(other, { 3, 1 })
		assert(fire("WinEnter") == 1, "Changing focus triggered duplicate global refreshes")
		assert(vim.wo.statusline:find("statusline%-other.txt"), "Global statusline retained the previous window's file")
		assert(vim.wo.statusline:match("3:2"), "Global statusline retained the previous window's cursor")

		-- Run the actual ColorScheme event chain twice. The upstream callback
		-- re-registers itself during setup and changes its position in the chain.
		for _ = 1, 2 do
			local before_event = theme_events
			vim.cmd.colorscheme(original_theme)
			assert(theme_events > before_event, "The theme check did not execute a real ColorScheme event")
			settle()
			scope_is_correct()
			assert(fire("CursorMoved") == 1, "A real theme switch reintroduced repeated global rendering")
		end
		vim.o.background = original_background == "dark" and "light" or "dark"
		-- OptionSet is suppressed during -l startup; explicitly dispatch the
		-- real event so the plugin's background handler participates in this test.
		api.nvim_exec_autocmds("OptionSet", { pattern = "background", modeline = false })
		settle()
		scope_is_correct()
		assert(fire("CursorMoved") == 1, "Background changes reintroduced repeated global rendering")

		-- Retire an owner with a queued repair, then leave wrong registrations
		-- intentionally unowned. Its old scheduled work must not repair them.
		api.nvim_exec_autocmds("ColorScheme", { group = "user_lualine_theme", modeline = false })
		package.loaded["user.core.statusline_refresh"] = nil
		refresh = require("user.core.statusline_refresh")
		refresh.setup()
		refresh.shutdown()
		lualine.setup(opts)
		settle()
		local unowned = api.nvim_get_autocmds({ group = "lualine_stl_refresh", event = "CursorMoved" })[1]
		assert(
			unowned.command:find("'kind': 'window'", 1, true),
			"Retired statusline owner executed its pending repair"
		)
		assert(refresh.setup() > 0, "Reloaded statusline owner did not repair registrations")
		refresh.setup()
		assert(#api.nvim_get_autocmds({ group = "user_lualine_theme" }) == 3, "Lifecycle hooks duplicated after reload")
		local before_event = theme_events
		vim.cmd.colorscheme(original_theme)
		assert(theme_events > before_event, "Reload check did not execute a real ColorScheme event")
		settle()
		scope_is_correct()
		assert(fire("CursorMoved") == 1, "Module reload lost theme lifecycle handling")
		lualine.setup(opts)
		local extra_calls = 0
		local extra = api.nvim_create_autocmd("CursorMoved", {
			group = "lualine_stl_refresh",
			callback = function()
				extra_calls = extra_calls + 1
			end,
		})
		assert(refresh.setup() == 0, "Adapter rebuilt a group containing an unknown callback")
		api.nvim_exec_autocmds("CursorMoved", { group = "lualine_stl_refresh", modeline = false })
		assert(extra_calls == 1, "An unrelated refresh callback was removed")
		api.nvim_del_autocmd(extra)
		assert(refresh.setup() > 0, "Adapter did not resume for the recognized plugin registrations")
		opts.options.globalstatus = false
		lualine.setup(opts)
		assert(refresh.setup() == 0, "Adapter changed per-window statusline behavior")
		assert(fire("CursorMoved") == 4, "Per-window statuslines stopped updating every split")
	end, debug.traceback)
	vim.o.eventignore = "all"
	api.nvim_del_augroup_by_id(observer)
	if api.nvim_tabpage_is_valid(original_tab) then
		api.nvim_set_current_tabpage(original_tab)
	end
	if test_tab and api.nvim_tabpage_is_valid(test_tab) then
		api.nvim_set_current_tabpage(test_tab)
		vim.cmd("tabclose!")
	end
	vim.o.columns = original_columns
	vim.o.background = original_background
	vim.o.eventignore = original_ignore
	lualine.setup(original_config)
	refresh.setup()
	assert(ok, err)
	vim.fn.writefile({ vim.json.encode(evidence) }, tmp .. "/statusline-refresh.json")
	print(
		"Statusline refresh evidence: 2/4 split render counts became 1; cursor/insert/file events, real theme/background changes and cancelled retired owners passed"
	)
end
