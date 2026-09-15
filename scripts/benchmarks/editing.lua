local root = assert(vim.env.NVIM_BENCH_ROOT, "NVIM_BENCH_ROOT is required")
vim.opt.rtp:prepend(root)
vim.o.swapfile, vim.o.undofile = false, false
local policy = require("user.core.buffer_policy")
policy.setup()
require("user.core.conflicts").setup()
require("user.core.sensitive").setup()
local report = {
	scope = "core modules only; no plugins, parsing or redraw; actual buffer callbacks + TextChanged events",
	scenes = {},
}
local iterations = tonumber(vim.env.NVIM_BENCH_ITERATIONS) or 300
assert(iterations >= 20 and iterations % 1 == 0, "Use at least 20 integer iterations")
report.iterations = iterations
local active
local defer = vim.defer_fn
vim.defer_fn = function(callback, timeout)
	if active then
		active.timer_requests = active.timer_requests + 1
	end
	return defer(function()
		local started = vim.uv.hrtime()
		callback()
		if active then
			active.timer_callbacks = active.timer_callbacks + 1
			active.deferred_ns = active.deferred_ns + vim.uv.hrtime() - started
		end
	end, timeout)
end
local original_inspect = policy.inspect
policy.inspect = function(...)
	local started = vim.uv.hrtime()
	local value = original_inspect(...)
	if active then
		active.policy_calls = active.policy_calls + 1
		active.policy_ns = active.policy_ns + vim.uv.hrtime() - started
	end
	return value
end
local api_get_lines, api_get_offset, api_extmark =
	vim.api.nvim_buf_get_lines, vim.api.nvim_buf_get_offset, vim.api.nvim_buf_set_extmark
vim.api.nvim_buf_get_lines = function(...)
	local lines = api_get_lines(...)
	if active then
		active.lines_read = active.lines_read + #lines
		active.line_reads = active.line_reads + 1
	end
	return lines
end
vim.api.nvim_buf_get_offset = function(...)
	if active then
		active.offset_reads = active.offset_reads + 1
	end
	return api_get_offset(...)
end
vim.api.nvim_buf_set_extmark = function(...)
	if active then
		active.extmark_writes = active.extmark_writes + 1
	end
	return api_extmark(...)
end
local function wait()
	vim.wait(70, function()
		return false
	end, 1)
end
local function scene(name, count, kind)
	local buffer = vim.api.nvim_create_buf(true, false)
	vim.api.nvim_set_current_buf(buffer)
	local lines = {}
	for i = 1, count do
		lines[i] = string.rep("a", 79)
	end
	if kind == "long" then
		lines[count - 20] = string.rep("x", 2100)
	end
	if kind == "conflict" then
		lines[count - 50], lines[count - 48], lines[count - 46] = "<<<<<<< HEAD", "=======", ">>>>>>> branch"
	end
	vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
	vim.api.nvim_exec_autocmds("BufReadPost", { buffer = buffer })
	wait()
	if kind == "manual" then
		policy.set(buffer, "off")
		wait()
	end
	active = {
		name = name,
		policy_calls = 0,
		policy_ns = 0,
		lines_read = 0,
		line_reads = 0,
		offset_reads = 0,
		extmark_writes = 0,
		timer_requests = 0,
		timer_callbacks = 0,
		deferred_ns = 0,
	}
	local times = {}
	local start = vim.uv.hrtime()
	for i = 1, iterations do
		local row = math.floor(count / 2)
		local tick = vim.uv.hrtime()
		if kind == "paste" then
			vim.api.nvim_buf_set_lines(buffer, row, row + 1, false, { string.rep("x", 2100) })
			vim.api.nvim_buf_set_lines(buffer, row, row + 1, false, { string.rep("a", 79) })
		else
			vim.api.nvim_buf_set_text(buffer, row, 79, row, 79, { "z" })
			vim.api.nvim_buf_set_text(buffer, row, 79, row, 80, { "" })
		end
		vim.api.nvim_exec_autocmds("TextChanged", { buffer = buffer })
		times[i] = (vim.uv.hrtime() - tick) / 1e6
	end
	active.edit_ms = (vim.uv.hrtime() - start) / 1e6
	table.sort(times)
	active.p50_pair_ms, active.p95_pair_ms = times[math.ceil(iterations * 0.5)], times[math.ceil(iterations * 0.95)]
	vim.api.nvim_exec_autocmds("TextChanged", { buffer = buffer })
	wait()
	active.policy_ms = active.policy_ns / 1e6
	active.deferred_ms = active.deferred_ns / 1e6
	active.policy_ns = nil
	active.deferred_ns = nil
	active.heavy, active.has_conflict = vim.b[buffer].bigfile, vim.b[buffer].user_has_conflicts
	table.insert(report.scenes, active)
	active = nil
	vim.api.nvim_buf_delete(buffer, { force = true })
end
for _, count in ipairs({ 100, 2500, 7500 }) do
	for _, kind in ipairs({ "ordinary", "long", "manual", "conflict" }) do
		scene(kind .. "_" .. count, count, kind)
	end
end
scene("paste_restore_7500", 7500, "paste")
vim.fn.writefile({ vim.json.encode(report) }, assert(vim.env.NVIM_BENCH_OUTPUT, "NVIM_BENCH_OUTPUT is required"))
