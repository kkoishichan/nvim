local M = {}

function M.command(args, cwd)
	local env = { GIT_TERMINAL_PROMPT = "0" }
	if vim.env.NVIM_PREPARE_OFFLINE == "1" then
		env.GIT_ALLOW_PROTOCOL = "file"
	end
	local result = vim.system(args, { cwd = cwd, text = true, env = env }):wait(120000)
	assert(result.code == 0, table.concat(args, " ") .. "\n" .. (result.stderr or ""))
	return vim.trim(result.stdout or "")
end

function M.json(path)
	return vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
end

---The mode this preparation or verification is working for. Deployment sets it
---the same way a session does, so the assets it prepares are the assets that
---mode will actually load.
function M.mode()
	local root = vim.env.NVIM_TEST_ROOT
	if root and root ~= "" then
		vim.opt.rtp:prepend(root)
	end
	return require("user.core.mode").name()
end

local configured_lazy = false

---Parse the locked Lazy spec without starting plugins or installers.
---@param opts table|nil `{ mode = "fast" }` reads the slim set instead.
function M.spec(root, data, opts)
	vim.opt.rtp:prepend(root)
	vim.opt.rtp:prepend(data .. "/lazy/lazy.nvim")
	if not configured_lazy then
		configured_lazy = true
		require("lazy.core.config").setup({
			root = data .. "/lazy",
			lockfile = root .. "/lazy-lock.json",
			install = { missing = false },
			pkg = { enabled = false },
			rocks = { enabled = false },
			performance = { rtp = { reset = false } },
		})
	end
	local source = { { import = "user.plugins" } }
	if opts and opts.mode == "fast" then
		source = require("user.core.mode").as("fast", function()
			return require("user.specs").base()
		end)
	end
	local spec = require("lazy.core.plugin").Spec.new(source, { pkg = false })
	for _, message in ipairs(spec.notifs) do
		assert(message.level ~= vim.log.levels.ERROR, message.msg)
	end
	local plugins = spec.plugins
	for name, plugin in pairs(spec.disabled) do
		plugins[name] = plugin
	end
	plugins["lazy.nvim"] =
		{ name = "lazy.nvim", url = "https://github.com/folke/lazy.nvim.git", dir = data .. "/lazy/lazy.nvim" }
	return plugins
end

function M.plugins(root, data)
	local lock, plugins = M.json(root .. "/lazy-lock.json"), M.spec(root, data)
	for name, plugin in pairs(plugins) do
		assert(lock[name], "Configured plugin has no lock entry: " .. name)
		assert(plugin.url, "Check preparation requires a locked Git plugin: " .. name)
	end
	for name, pin in pairs(lock) do
		assert(plugins[name], "Stale lock entry without a configured plugin: " .. name)
		assert(
			type(pin.commit) == "string" and pin.commit:match("^[a-f0-9]+$") and #pin.commit == 40,
			"Invalid lock commit for " .. name
		)
	end
	return lock, plugins
end

---Plugin names a mode installs, dependencies included. The lock itself stays
---the complete one: a slim installation is a choice about what to put on disk,
---never a reason to clean an entry out of the shared lockfile.
---@return string[]
function M.selected_plugins(root, data, mode)
	local plugins = M.spec(root, data, { mode = mode })
	local names = vim.tbl_keys(plugins)
	local profiles = vim.env.NVIM_DEPLOY_PROFILES
	if mode == "fast" and profiles and profiles ~= "" and profiles ~= "none" then
		-- Installer dependency only: it never enters the fast runtime spec.
		table.insert(names, "mason.nvim")
	end
	table.sort(names)
	return names
end

function M.parser_info(data)
	vim.opt.rtp:prepend(data .. "/lazy/nvim-treesitter")
	local catalog = require("user.core.treesitter")
	require("nvim-treesitter").setup({ install_dir = data .. "/site" })
	return catalog.selected(), require("nvim-treesitter.parsers")
end

-- Inspect the prepared matcher without calling Blink's downloader. A matching
-- tag alone does not prove that the cached binary is intact or loadable.
function M.verify_blink(data, commit)
	local directory = data .. "/lazy/blink.cmp"
	vim.opt.rtp:prepend(directory)
	local files = require("blink.cmp.fuzzy.download.files")
	assert(vim.uv.fs_stat(files.version_path), "Missing prepared Blink matcher version")
	local version = vim.trim(table.concat(vim.fn.readfile(files.version_path), "\n"))
	assert(
		M.command({ "git", "rev-parse", version .. "^{commit}" }, directory) == commit,
		"Blink matcher version differs from locked plugin"
	)
	if #version ~= 40 then
		assert(vim.uv.fs_stat(files.checksum_path), "Missing prepared Blink matcher checksum")
		local expected = table.concat(vim.fn.readfile(files.checksum_path), "\n"):match("^(%x+)")
		local command = assert(files.get_checksum_command(files.lib_path), "Unsupported matcher checksum platform")
		local actual = M.command(command):match("^(%x+)")
		assert(expected and expected == actual, "Blink matcher checksum differs from prepared asset")
	end
	local loaded, err = pcall(require, "blink.cmp.fuzzy.rust")
	assert(loaded, "Prepared Blink native matcher cannot load: " .. tostring(err))
end

M.tools = { "stylua", "selene", "ruff", "shellcheck" }

return M
