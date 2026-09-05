-- prepare-checks.lua already restored exact plugin commits, parsers and Blink.
-- Build the remaining explicit plugin assets without fetching branches or
-- allowing Lazy.restore/update to rewrite the configuration's lockfile.
local root = assert(vim.env.NVIM_DEPLOY_ROOT, "NVIM_DEPLOY_ROOT is required")
local lock_path = root .. "/lazy-lock.json"
local original = vim.fn.readfile(lock_path, "b")
local function build()
	assert(vim.v.errmsg == "", "Staged startup failed: " .. vim.v.errmsg)
	assert(package.loaded["user.lazy"] and vim.g.lazy_did_setup, "Staged configuration did not initialize Lazy")
	local lazy = require("lazy")
	local selected = {}
	for _, plugin in ipairs(lazy.plugins()) do
		-- Tree-sitter was compiled and verified by preparation. Rebuilding it
		-- here adds no artifact; markdown-preview's standalone binary does.
		if plugin.build and plugin.name ~= "nvim-treesitter" then
			selected[#selected + 1] = plugin.name
		end
	end
	if #selected > 0 then
		lazy.load({ plugins = selected })
		lazy.build({ plugins = selected, wait = true, show = false })
	end
	local failures = {}
	-- Task status belongs to the pinned Lazy implementation, exposed through
	-- its public plugins() descriptor list. A successful command exit alone
	-- does not report build failures; independently verify Git pins afterwards.
	for _, plugin in ipairs(lazy.plugins()) do
		for _, task in ipairs(plugin._.tasks or {}) do
			if task:has_errors() then
				failures[#failures + 1] = plugin.name .. ": " .. task:output(vim.log.levels.ERROR)
			end
		end
		local docs = plugin.dir and plugin.dir .. "/doc"
		if docs and vim.uv.fs_stat(docs) then
			vim.api.nvim_cmd({ cmd = "helptags", args = { docs } }, {})
		end
	end
	assert(#failures == 0, "Plugin build failed:\n" .. table.concat(failures, "\n"))
	assert(vim.deep_equal(original, vim.fn.readfile(lock_path, "b")), "Plugin build changed the staged lockfile")
	print("Staged plugin assets and help tags prepared")
end
local ok, err = pcall(build)
if not ok then
	assert(vim.fn.writefile(original, lock_path, "b") == 0, "Could not preserve the staged lockfile")
	vim.api.nvim_err_writeln(tostring(err))
	vim.cmd("cquit 21")
end
