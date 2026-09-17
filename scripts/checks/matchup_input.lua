return function()
	local api = vim.api
	local old_ignore = vim.o.eventignore
	vim.o.eventignore = "all"
	require("lazy").load({ plugins = { "vim-matchup", "nvim-treesitter" } })
	local cache = require("user.core.matchup_cache")
	local bridge = require("user.core.matchup_bridge")
	assert(cache.setup(), "Match-up adapter did not activate")
	assert(bridge.stats().automatic_yield, "Automatic input guard did not activate")
	local buf = api.nvim_create_buf(true, false)
	api.nvim_set_current_buf(buf)
	api.nvim_buf_set_lines(buf, 0, -1, false, {
		"def outer(value):",
		"    if value:",
		"        return (value + 1)",
		"    return 0",
	})
	vim.bo[buf].filetype = "python"
	vim.treesitter.start(buf, "python")
	vim.treesitter.get_parser(buf):parse(true)
	vim.fn["matchup#loader#init_buffer"]()
	vim.fn["matchup#matchparen#enable"]()
	vim.wo.foldenable = false
	vim.o.eventignore = ""
	api.nvim_exec_autocmds("CursorMoved", { group = "matchup_matchparen", buffer = buf })
	vim.o.eventignore = "all"
	local timer = assert(vim.w.matchup_timer, "The native deferred timer was not initialized")
	local callback
	for _, script in ipairs(vim.fn.getscriptinfo()) do
		if script.name:match("/autoload/matchup/matchparen%.vim$") then
			callback = "<SNR>" .. script.sid .. "_timer_callback"
		end
	end
	assert(callback, "Native match-up timer callback was not found")
	local function invoke()
		vim.w.last_cursor = nil
		vim.w.matchup_pulse_time = { 0, 0 }
		vim.fn[callback](api.nvim_get_current_win(), timer)
	end
	local function marks()
		local result = vim.fn.getmatches()
		for _, match in ipairs(result) do
			match.id = nil
		end
		table.sort(result, function(a, b)
			return vim.inspect(a) < vim.inspect(b)
		end)
		local signs = {}
		local ns = api.nvim_get_namespaces()["vim-matchup"]
		for _, mark in ipairs(api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
			signs[#signs + 1] = { mark[2], mark[3], mark[4] }
		end
		return { result, signs }
	end
	api.nvim_win_set_cursor(0, { 1, 0 })
	invoke()
	local expected = marks()
	assert(#expected[1] + #expected[2] > 0, "Idle fixture did not display pair hints")
	-- Pending normal-mode input must survive a canceled automatic search.
	-- Drive the plugin's real timer callback rather than a mock of the guard.
	api.nvim_feedkeys("j", "t", false)
	local before, position = bridge.stats().interruptions, api.nvim_win_get_cursor(0)
	invoke()
	assert(bridge.stats().interruptions > before, "Automatic search did not yield to pending input")
	assert(vim.fn.getchar(1) == string.byte("j"), "The guard consumed waiting input")
	assert(vim.deep_equal(api.nvim_win_get_cursor(0), position), "Canceled search left its temporary cursor in place")
	assert(vim.fn.getchar(0) == string.byte("j"), "Waiting input was lost")
	assert(
		vim.wait(1000, function()
			return bridge.stats().resumes > 0 and vim.deep_equal(marks(), expected)
		end, 10),
		"Idle timer failed to restore the complete pair hints"
	)
	-- Explicit matching must finish, even with more user input queued.
	api.nvim_feedkeys("j", "t", false)
	before = bridge.stats().interruptions
	local current = vim.fn["matchup#delim#get_current"]("all", "both_all")
	assert(not vim.tbl_isempty(current), "Manual delimiter lookup was canceled")
	assert(bridge.stats().interruptions == before, "Manual lookup was mistaken for automatic highlighting")
	assert(vim.fn.getchar(0) == string.byte("j"), "Manual lookup consumed waiting input")
	-- A queued retry must become inert when the adapter is shut down/reloaded.
	api.nvim_feedkeys("j", "t", false)
	invoke()
	assert(vim.fn.getchar(0) == string.byte("j"), "Reload fixture lost input")
	cache.shutdown()
	assert(cache.setup(), "Reload did not restore the adapter")
	vim.wait(20, function()
		return false
	end, 5)
	assert(bridge.stats().resumes == 0, "An old scheduled retry affected its replacement")
	vim.o.eventignore = ""
	api.nvim_buf_delete(buf, { force = true })
	vim.o.eventignore = old_ignore
	print(
		"Match-up input: pending keys preserved, automatic search yields, idle hints recover, manual lookup and reload passed"
	)
end
