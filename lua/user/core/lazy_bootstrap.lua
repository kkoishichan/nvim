local M = {}

function M.root()
	return vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h:h")
end

---Only the first explicit bootstrap downloads anything. Checks fail with a
---preparation instruction instead of installing a missing package manager.
function M.ensure(opts)
	opts = opts or {}
	local destination = vim.fs.joinpath(vim.fn.stdpath("data"), "lazy", "lazy.nvim")
	if vim.uv.fs_stat(destination .. "/lua/lazy/init.lua") then
		return destination
	end
	assert(vim.env.NVIM_CHECK_ONLY ~= "1", "lazy.nvim is missing; run scripts/prepare-checks.sh first")
	local root = opts.root or M.root()
	local lock = vim.json.decode(table.concat(vim.fn.readfile(root .. "/lazy-lock.json"), "\n"))
	local pin = assert(lock["lazy.nvim"] and lock["lazy.nvim"].commit, "lazy.nvim needs a lockfile commit")
	assert(pin:match("^[a-f0-9]+$") and #pin == 40, "Invalid lazy.nvim lockfile commit")
	assert(vim.fn.executable("git") == 1, "git is required to install lazy.nvim")
	local cached = opts.cache and vim.fs.joinpath(opts.cache, "lazy", "lazy.nvim")
	local source = cached and vim.uv.fs_stat(cached .. "/.git") and cached or "https://github.com/folke/lazy.nvim.git"
	assert(not opts.offline or source == cached, "Offline preparation needs cached lazy.nvim")
	vim.fn.mkdir(vim.fs.dirname(destination), "p")
	assert(not vim.uv.fs_stat(destination), "Incomplete lazy.nvim directory requires inspection: " .. destination)
	local staging = destination .. ".prepare-" .. vim.fn.getpid()
	assert(not vim.uv.fs_stat(staging), "Bootstrap staging directory already exists: " .. staging)
	local function command(args)
		local env = { GIT_TERMINAL_PROMPT = "0" }
		if opts.offline then
			env.GIT_ALLOW_PROTOCOL = "file"
		end
		local result = vim.system(args, { text = true, env = env }):wait(120000)
		assert(result.code == 0, "lazy.nvim bootstrap failed: " .. (result.stderr or ""))
	end
	local ok, err = pcall(function()
		command({ "git", "clone", "--filter=blob:none", "--no-checkout", "--no-hardlinks", source, staging })
		command({ "git", "-C", staging, "remote", "set-url", "origin", "https://github.com/folke/lazy.nvim.git" })
		local available = vim.system({ "git", "-C", staging, "cat-file", "-e", pin .. "^{commit}" }, {
			env = { GIT_ALLOW_PROTOCOL = "file", GIT_TERMINAL_PROMPT = "0" },
		}):wait(10000)
		if available.code ~= 0 then
			assert(not opts.offline, "Offline bootstrap lacks the locked lazy.nvim commit: " .. pin)
			command({ "git", "-C", staging, "fetch", "--depth=1", "origin", pin })
		end
		command({ "git", "-C", staging, "checkout", "--detach", pin })
		assert(vim.uv.fs_rename(staging, destination))
	end)
	if not ok then
		vim.fn.delete(staging, "rf")
		error(err)
	end
	return destination
end

return M
