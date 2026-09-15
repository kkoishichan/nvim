-- Run with -u NONE. The driver can load modules from a frozen configuration
-- while keeping this exact benchmark and its fixtures identical for both runs.
vim.opt.runtimepath:prepend(vim.env.NVIM_BENCH_ROOT or vim.fn.getcwd())
vim.o.eventignore = "all"
vim.o.columns, vim.o.lines = 180, 50
vim.o.number = true
local api = vim.api
local results =
	{ note = "Headless isolated Lua hot-path microbenchmark; no screen rendering, LSP, or Git subprocess work" }
local function bench(name, count, fn)
	local times = {}
	for sample = 1, 6 do
		collectgarbage("collect")
		local start = vim.uv.hrtime()
		for _ = 1, count do
			fn()
		end
		local elapsed = (vim.uv.hrtime() - start) / 1e6
		if sample > 1 then
			times[#times + 1] = elapsed
		end
	end
	table.sort(times)
	results[name] =
		{ iterations = count, median_ms = times[3], per_call_us = times[3] * 1000 / count, samples_ms = times }
end
local panels = require("user.core.panels")
local list_wins, scans = api.nvim_tabpage_list_wins, 0
api.nvim_tabpage_list_wins = function(...)
	scans = scans + 1
	return list_wins(...)
end
panels.enforce()
api.nvim_tabpage_list_wins = list_wins
results.panel_empty_tab_scans = scans
bench("panel_enforce_one_editor", 5000, panels.enforce)
for _ = 1, 3 do
	vim.cmd("vsplit")
end
local floats = {}
for _ = 1, 6 do
	floats[#floats + 1] = api.nvim_open_win(
		api.nvim_create_buf(false, true),
		false,
		{ relative = "editor", row = 3, col = 2, width = 12, height = 4, noautocmd = true }
	)
end
bench("panel_enforce_four_editors_six_floats", 5000, panels.enforce)
local layout = require("user.core.layout")
layout.apply_manager_float(floats[1])
local set_config, config_writes = api.nvim_win_set_config, 0
api.nvim_win_set_config = function(...)
	config_writes = config_writes + 1
	return set_config(...)
end
for _ = 1, 20 do
	layout.apply_manager_float(floats[1])
end
api.nvim_win_set_config = set_config
results.manager_stable_geometry_writes_per_20_calls = config_writes
bench("manager_stable_geometry", 5000, function()
	layout.apply_manager_float(floats[1])
end)
local current_buf = api.nvim_get_current_buf()
local views = vim.fn.win_findbuf(current_buf)
package.loaded["gitsigns.sign_renderer"] = {
	statuscolumn = function()
		return "  "
	end,
}
vim.b[current_buf].gitsigns_status_dict =
	{ head = "main", root = "/tmp/ui-fixture", gitdir = "/tmp/ui-fixture/.git", added = 3, changed = 2, removed = 1 }
vim.b[current_buf].gitsigns_head = "main"
local statuscolumn = require("user.core.statuscolumn")
bench("git_statuscolumn_wrapper_attached", 100000, statuscolumn.git)
local sign_callback, counter, hunks = nil, 0, {}
for i = 1, 100 do
	hunks[i] = { type = "change", added = { start = i * 12, count = 10 } }
end
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
		counter = counter + 1
		return { name = "ui_bench_sign_" .. counter }
	end,
	set_sign_group_callback = function(_, callback)
		sign_callback = callback
	end,
	get_sign_eligible_windows = function()
		return { views[1], views[2] }
	end,
	set_sign_group_state = function() end,
	is_sign_group_active = function()
		return true
	end,
	refresh = function() end,
}
local specs = require("user.plugins.ui")
for _, spec in ipairs(specs) do
	if spec[1] == "dstein64/nvim-scrollview" then
		spec.config(nil, spec.opts)
	end
end
local function count_sign_work()
	local buffer_vars, writes = vim.b, 0
	-- Count variable writes separately from timed samples, so instrumentation
	-- overhead cannot be mistaken for the cost of the production callback.
	vim.b = setmetatable({}, {
		__index = function(_, buf)
			return setmetatable({}, {
				__index = function(_, key)
					return buffer_vars[buf][key]
				end,
				__newindex = function(_, key, value)
					writes = writes + 1
					buffer_vars[buf][key] = value
				end,
			})
		end,
	})
	gets = 0
	sign_callback()
	vim.b = buffer_vars
	return { get_hunks = gets, buffer_var_writes = writes }
end
results.git_rail_first_refresh = count_sign_work()
bench("git_rail_same_buffer_two_views_1000_lines", 2000, sign_callback)
results.git_rail_unchanged_refresh = count_sign_work()
local output = assert(vim.env.NVIM_BENCH_OUTPUT, "NVIM_BENCH_OUTPUT is required")
vim.fn.writefile({ vim.json.encode(results) }, output)
print(vim.inspect(results))
