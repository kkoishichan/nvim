return function()
	local api = vim.api
	local panels = require("user.core.panels")
	local layout = require("user.core.layout")
	local roles = require("user.core.window_roles")
	local old_ignore, old_columns, old_lines = vim.o.eventignore, vim.o.columns, vim.o.lines
	vim.o.eventignore = "all"
	vim.o.columns, vim.o.lines = 180, 50
	vim.cmd.tabnew()
	local tab = api.nvim_get_current_tabpage()
	local editor = api.nvim_get_current_win()
	roles.mark(editor, "editor")

	local list_wins, scans = api.nvim_tabpage_list_wins, 0
	api.nvim_tabpage_list_wins = function(...)
		scans = scans + 1
		return list_wins(...)
	end
	panels.enforce()
	api.nvim_tabpage_list_wins = list_wins
	assert(scans == 1, "An editor-only tab repeated its layout scan")

	vim.cmd("topleft vnew")
	local panel = api.nvim_get_current_win()
	vim.bo.buftype, vim.bo.filetype = "nofile", "neo-tree"
	roles.mark(panel, "panel")
	api.nvim_set_current_win(editor)
	panels.enforce()
	local set_width, set_height, writes = api.nvim_win_set_width, api.nvim_win_set_height, 0
	api.nvim_win_set_width = function(...)
		writes = writes + 1
		return set_width(...)
	end
	api.nvim_win_set_height = function(...)
		writes = writes + 1
		return set_height(...)
	end
	panels.enforce()
	panels.enforce()
	api.nvim_win_set_width, api.nvim_win_set_height = set_width, set_height
	assert(writes == 0 and panels.editor_fits(), "An unchanged panel rewrote window geometry")
	api.nvim_win_close(panel, false)

	local manager_buf = api.nvim_create_buf(false, true)
	vim.bo[manager_buf].filetype = "lazy"
	local manager = api.nvim_open_win(manager_buf, false, {
		relative = "editor",
		row = 1,
		col = 1,
		width = 20,
		height = 4,
		border = "none",
	})
	local set_config = api.nvim_win_set_config
	writes = 0
	api.nvim_win_set_config = function(...)
		writes = writes + 1
		return set_config(...)
	end
	layout.apply_manager_float(manager)
	layout.apply_manager_float(manager)
	assert(writes == 1, "An unchanged manager float repeated its geometry update")
	vim.o.columns = 160
	layout.apply_manager_float(manager)
	assert(writes == 2 and api.nvim_win_get_width(manager) == 128, "Manager resize stopped tracking the viewport")
	api.nvim_win_set_config = set_config

	local schedule, queue = vim.schedule, {}
	vim.schedule = function(callback)
		queue[#queue + 1] = callback
	end
	layout.setup()
	local callbacks = api.nvim_get_autocmds({ group = "user_manager_float_layout", event = "VimResized" })
	for _ = 1, 30 do
		callbacks[1].callback()
	end
	assert(#queue == 1, "Manager resize burst queued multiple full-window scans")
	layout.setup()
	local all_wins, manager_scans = api.nvim_list_wins, 0
	api.nvim_list_wins = function(...)
		manager_scans = manager_scans + 1
		return all_wins(...)
	end
	queue[1]()
	api.nvim_list_wins, vim.schedule = all_wins, schedule
	assert(manager_scans == 0, "An obsolete manager callback survived setup")
	api.nvim_win_close(manager, false)
	vim.cmd.vsplit()
	local second_editor = api.nvim_get_current_win()
	api.nvim_set_current_win(editor)

	local loaded_renderer = package.loaded["gitsigns.sign_renderer"]
	local calls, rendered_buf = 0, nil
	package.loaded["gitsigns.sign_renderer"] = {
		statuscolumn = function(bufnr)
			calls, rendered_buf = calls + 1, bufnr
			return "++"
		end,
	}
	local statuscolumn = require("user.core.statuscolumn")
	vim.wo.number = true
	local bufnr = api.nvim_get_current_buf()
	vim.b[bufnr].gitsigns_head = "" -- A detached/unnamed HEAD is still attached.
	assert(statuscolumn.git() == "++" and rendered_buf == bufnr, "Git lane lost an attached buffer")
	vim.b[bufnr].gitsigns_head = nil
	assert(statuscolumn.git() == "  " and calls == 1, "Detached Git signs were still rendered")
	vim.wo.number, vim.wo.relativenumber = false, false
	assert(statuscolumn.git() == "", "Unnumbered panel acquired a Git lane")
	package.loaded["gitsigns.sign_renderer"] = loaded_renderer

	local loaded_scrollview, loaded_git = package.loaded.scrollview, package.loaded.gitsigns
	local sign_callback, refreshes, specs, names = nil, 0, 0, {}
	local hunks = { { type = "change", added = { start = 2, count = 3 } } }
	local gets = 0
	package.loaded.gitsigns = {
		get_hunks = function()
			gets = gets + 1
			return hunks
		end,
	}
	package.loaded.scrollview = {
		setup = function() end,
		register_sign_group = function() end,
		register_sign_spec = function()
			specs = specs + 1
			local name = "ui_runtime_sign_" .. specs
			names[#names + 1] = name
			return { name = name }
		end,
		set_sign_group_callback = function(_, callback)
			sign_callback = callback
		end,
		get_sign_eligible_windows = function()
			return { editor, second_editor }
		end,
		set_sign_group_state = function() end,
		is_sign_group_active = function()
			return true
		end,
		refresh = function()
			refreshes = refreshes + 1
		end,
	}
	local config, opts
	for _, spec in ipairs(require("user.plugins.ui")) do
		if spec[1] == "dstein64/nvim-scrollview" then
			config, opts = spec.config, spec.opts
		end
	end
	local timers, new_timer = {}, vim.uv.new_timer
	vim.uv.new_timer = function()
		local timer = { closed = false }
		function timer:start(_, _, callback)
			self.callback = callback
		end
		function timer:stop() end
		function timer:is_closing()
			return self.closed
		end
		function timer:close()
			self.closed = true
		end
		timers[#timers + 1] = timer
		return timer
	end
	config(nil, opts)
	sign_callback()
	assert(gets == 1, "Git overview reread hunks for the same buffer's second window")
	local function nonempty_signs()
		for _, name in ipairs(names) do
			local signs = vim.b[bufnr][name]
			if signs and #signs > 0 then
				return signs
			end
		end
		return {}
	end
	assert(vim.deep_equal(nonempty_signs(), { 2, 3, 4 }), "Git overview changed expanded hunk locations")
	hunks[1].added.start = 8
	sign_callback()
	assert(vim.deep_equal(nonempty_signs(), { 8, 9, 10 }), "Same-size hunk movement left stale Git markers")
	hunks = nil
	sign_callback()
	assert(#nonempty_signs() == 0, "Detached Git buffer retained overview markers")
	local refresh_callback = api.nvim_get_autocmds({ group = "user_scrollview_git", event = "User" })[1].callback
	for _ = 1, 100 do
		refresh_callback()
	end
	assert(#timers == 1, "Git update burst allocated more than one debounce timer")
	timers[1].callback()
	refresh_callback()
	vim.wait(10)
	assert(refreshes == 0, "A queued timer redrew after a newer Git update")
	timers[1].callback()
	vim.wait(10)
	assert(refreshes == 1, "Git update burst did not produce one refresh")
	timers[1].callback()
	config(nil, opts)
	vim.wait(10)
	assert(timers[1].closed and refreshes == 1, "Old Git timer survived reconfiguration")
	local new_refresh = api.nvim_get_autocmds({ group = "user_scrollview_git", event = "User" })[1].callback
	rawget(vim, "_user_scrollview_git_cleanup")()
	new_refresh()
	assert(#timers == 1, "A cleaned-up Git service allocated another timer")
	vim.uv.new_timer = new_timer
	package.loaded.scrollview, package.loaded.gitsigns = loaded_scrollview, loaded_git

	api.nvim_set_current_tabpage(tab)
	vim.cmd("tabclose!")
	vim.o.columns, vim.o.lines, vim.o.eventignore = old_columns, old_lines, old_ignore
	print(
		"UI runtime: one scan without panels; zero stable geometry writes; one Git hunk read per buffer; one timer per update burst"
	)
end
