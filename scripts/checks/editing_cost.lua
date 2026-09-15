return function(tmp)
	local policy = require("user.core.buffer_policy")
	local function open(name, lines)
		local path = vim.fs.joinpath(tmp, name)
		vim.fn.writefile(lines, path)
		vim.cmd.edit(vim.fn.fnameescape(path))
		return vim.api.nvim_get_current_buf(), path
	end
	local function drain()
		vim.wait(90, function()
			return false
		end, 5)
	end
	local function ordinary(count)
		local lines = {}
		for index = 1, count or 4000 do
			lines[index] = string.rep("a", 40)
		end
		return lines
	end
	local function policy_reads(callback)
		local get_lines, get_offset = vim.api.nvim_buf_get_lines, vim.api.nvim_buf_get_offset
		local result = { lines = 0, offsets = 0 }
		vim.api.nvim_buf_get_lines = function(...)
			local lines = get_lines(...)
			if debug.getinfo(2, "S").source:find("/core/buffer_policy.lua", 1, true) then
				result.lines = result.lines + #lines
			end
			return lines
		end
		vim.api.nvim_buf_get_offset = function(...)
			if debug.getinfo(2, "S").source:find("/core/buffer_policy.lua", 1, true) then
				result.offsets = result.offsets + 1
			end
			return get_offset(...)
		end
		local ok, err = xpcall(callback, debug.traceback)
		vim.api.nvim_buf_get_lines, vim.api.nvim_buf_get_offset = get_lines, get_offset
		assert(ok, err)
		return result
	end
	local function edit_pairs(buffer)
		for _ = 1, 100 do
			vim.api.nvim_buf_set_text(buffer, 1000, 40, 1000, 40, { "x" })
			vim.api.nvim_buf_set_text(buffer, 1000, 40, 1000, 41, { "" })
		end
	end

	local buffer = open("ordinary-cost.txt", ordinary())
	local reads = policy_reads(function()
		edit_pairs(buffer)
	end)
	assert(reads.lines <= 220 and reads.offsets <= 220, "Ordinary edits scanned unchanged lines")
	assert(policy.allow(buffer), "Ordinary edits disabled document features")
	policy.set(buffer, "off")
	drain()
	reads = policy_reads(function()
		edit_pairs(buffer)
	end)
	assert(reads.lines <= 220 and reads.offsets <= 220, "Manual disable caused full scans on each edit")
	assert(policy.inspect(buffer).reason == "disabled manually", "Cached manual reason changed")
	policy.set(buffer, "auto")
	drain()
	assert(policy.allow(buffer), "Manual disable failed to restore automatically")

	local sparse = ordinary()
	sparse[3000], sparse[3500] = string.rep("x", 2100), string.rep("y", 2200)
	buffer = open("sparse-cost.txt", sparse)
	assert(not policy.allow(buffer), "Sparse long line escaped cost detection")
	drain()
	reads = policy_reads(function()
		edit_pairs(buffer)
	end)
	assert(reads.lines <= 20 and reads.offsets <= 220, "Unchanged long line triggered repeated full scans")
	vim.api.nvim_buf_set_lines(buffer, 0, 0, false, { "prefix" })
	assert(not policy.allow(buffer), "Inserting before a long line lost its position")
	vim.api.nvim_buf_set_lines(buffer, 0, 1, false, {})
	assert(not policy.allow(buffer), "Deleting before a long line lost its position")
	vim.api.nvim_buf_set_lines(buffer, 0, 0, false, { "prefix" })
	vim.api.nvim_buf_set_lines(buffer, 3000, 3001, false, {})
	assert(not policy.allow(buffer), "Removing one long line concealed another")
	vim.api.nvim_buf_set_lines(buffer, 3499, 3500, false, {})
	assert(policy.allow(buffer), "Removing all long lines did not restore features")
	drain()

	buffer = open("undo-cost.txt", ordinary())
	vim.api.nvim_win_set_cursor(0, { 1200, 0 })
	vim.api.nvim_feedkeys(vim.keycode("A" .. string.rep("x", 2050) .. "<Esc>"), "nx", false)
	assert(not policy.allow(buffer), "Real insert did not cross the long-line boundary")
	vim.api.nvim_feedkeys("u", "nx", false)
	assert(policy.allow(buffer), "Undo did not restore ordinary content")
	vim.api.nvim_feedkeys(vim.keycode("<C-r>"), "nx", false)
	assert(not policy.allow(buffer), "Redo did not reapply the long-line boundary")
	vim.api.nvim_feedkeys("u", "nx", false)
	assert(policy.allow(buffer), "Second undo failed to recover")
	drain()

	buffer = open("paste-cost.txt", ordinary())
	vim.api.nvim_buf_set_lines(buffer, 0, 0, false, ordinary(6001))
	assert(vim.b[buffer].bigfile, "Large paste was not classified during on_lines")
	vim.cmd.undo()
	assert(policy.allow(buffer), "Undoing a large paste did not restore features")
	vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { string.rep("z", 2 * 1024 * 1024) })
	assert(not policy.allow(buffer), "Byte ceiling regressed")
	vim.api.nvim_buf_set_lines(buffer, 0, -1, false, ordinary())
	assert(policy.allow(buffer), "Recovering below byte and line ceilings failed")
	drain()

	local path
	buffer, path = open("reload-cost.txt", { string.rep("r", 2100) })
	assert(not policy.allow(buffer), "Reload fixture lacked its long line")
	vim.fn.writefile(ordinary(), path)
	vim.cmd.edit({ bang = true })
	assert(policy.allow(buffer), "Reload retained the previous long-line witness")
	vim.api.nvim_buf_set_lines(buffer, 1500, 1501, false, { string.rep("t", 2100) })
	assert(not policy.allow(buffer), "Reload lost subsequent buffer-change tracking")
	drain()

	local conflicts = ordinary()
	conflicts[200], conflicts[201], conflicts[202], conflicts[203], conflicts[204] =
		"<<<<<<< HEAD", "ours", "=======", "theirs", ">>>>>>> branch"
	buffer = open("conflict-cost.txt", conflicts)
	assert(
		vim.wait(300, function()
			return vim.b[buffer].user_has_conflicts == true
		end, 5),
		"Conflict fixture was not detected"
	)
	local defer, timers = vim.defer_fn, 0
	vim.defer_fn = function(callback, timeout)
		if debug.getinfo(2, "S").source:find("/core/conflicts.lua", 1, true) then
			timers = timers + 1
		end
		return defer(callback, timeout)
	end
	local ok, err = xpcall(function()
		for _ = 1, 100 do
			vim.api.nvim_buf_set_text(buffer, 1000, 40, 1000, 40, { "x" })
			vim.api.nvim_buf_set_text(buffer, 1000, 40, 1000, 41, { "" })
			vim.api.nvim_exec_autocmds("TextChanged", { group = "user_git_conflicts", buffer = buffer })
		end
		drain()
	end, debug.traceback)
	vim.defer_fn = defer
	assert(ok, err)
	assert(timers <= 3, "Conflict edits allocated a timer for every TextChanged event")
	assert(not vim.diagnostic.is_enabled({ bufnr = buffer }), "Conflict edits restored diagnostics prematurely")
	local get_lines, scanned = vim.api.nvim_buf_get_lines, 0
	vim.api.nvim_buf_get_lines = function(...)
		local lines = get_lines(...)
		if debug.getinfo(2, "S").source:find("/core/conflicts.lua", 1, true) then
			scanned = scanned + #lines
		end
		return lines
	end
	ok, err = xpcall(function()
		vim.diagnostic.enable(true, { bufnr = buffer })
		vim.api.nvim_exec_autocmds("BufWritePost", { group = "user_git_conflicts", buffer = buffer })
		drain()
	end, debug.traceback)
	vim.api.nvim_buf_get_lines = get_lines
	assert(ok, err)
	assert(scanned == 0, "Unchanged conflict buffer was scanned again")
	assert(
		not vim.diagnostic.is_enabled({ bufnr = buffer }),
		"Cached conflict render failed to synchronize externally enabled diagnostics"
	)
	vim.api.nvim_win_set_cursor(0, { 201, 0 })
	vim.cmd.GitConflictChooseBoth()
	assert(
		vim.wait(300, function()
			return vim.b[buffer].user_has_conflicts == false
		end, 5),
		"Conflict resolution failed to refresh"
	)
	assert(vim.diagnostic.is_enabled({ bufnr = buffer }), "Conflict resolution did not restore diagnostics")
	assert(
		vim.deep_equal(vim.api.nvim_buf_get_lines(buffer, 199, 201, false), { "ours", "theirs" }),
		"Conflict resolution changed the selected content"
	)
	print(
		"Editing cost checks passed: incremental edits, long-line recovery, undo/redo, paste, reload and conflict coalescing"
	)
end
