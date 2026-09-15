-- Isolated synchronous context/tool lookup cost, not whole-editor latency.
local root = assert(vim.env.NVIM_BENCH_ROOT, "NVIM_BENCH_ROOT is required")
local tmp = assert(vim.env.NVIM_BENCH_TMP, "NVIM_BENCH_TMP is required")
vim.opt.runtimepath:prepend(root)
local project = require("user.core.project")
local tools = require("user.toolchain")
local base = tmp .. "/workspace"
vim.fn.mkdir(base .. "/.git", "p")
vim.fn.mkdir(base .. "/packages/web/src/deep", "p")
vim.fn.writefile({ "{}" }, base .. "/packages/web/package.json")
local source = base .. "/packages/web/src/deep/app.ts"
vim.fn.writefile({ "export const answer = 42;" }, source)
vim.cmd.edit(source)
tools.executable("sh")

local results = {}
for name, action in pairs({
	project_context = function()
		return project.context(source)
	end,
	global_tool_hit = function()
		return tools.executable("sh")
	end,
	project_tool_hit = function()
		return tools.node_executable("sh", source)
	end,
}) do
	local runs = {}
	for _ = 1, 6 do
		local start = vim.uv.hrtime()
		for _ = 1, 200 do
			action()
		end
		table.insert(runs, (vim.uv.hrtime() - start) / 200 / 1000)
	end
	local find, calls = vim.fs.root, 0
	vim.fs.root = function(...)
		calls = calls + 1
		return find(...)
	end
	action()
	vim.fs.root = find
	local samples = { unpack(runs, 2) }
	table.sort(samples)
	results[name] = { median_us = samples[3], runs_us = runs, root_searches_per_call = calls }
end
vim.fn.writefile({ vim.json.encode(results) }, assert(vim.env.NVIM_BENCH_OUTPUT, "NVIM_BENCH_OUTPUT is required"))
