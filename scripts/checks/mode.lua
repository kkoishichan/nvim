-- Startup mode selection, capability isolation and the entries that must keep
-- working when the plugin manager or the state directory is unavailable. Every
-- case runs in its own Neovim process, because the mode is decided once per
-- process and the point of these checks is which decision was made.

local function encode(value)
	return vim.json.encode(value)
end

return function(tmp)
	local root = assert(vim.env.NVIM_TEST_ROOT, "NVIM_TEST_ROOT is required")

	local snapshot = [[
local mode = require("user.core.mode")
local capabilities = mode.capabilities()
local disabled = {}
for _, capability in ipairs(mode.capability_names()) do
  if not capabilities[capability] then
    table.insert(disabled, capability)
  end
end
local plugins = {}
local lazy = package.loaded["lazy.core.config"]
for name in pairs(lazy and lazy.plugins or {}) do
  table.insert(plugins, name)
end
table.sort(plugins)
table.sort(disabled)
local handles = { timer = 0, fs_event = 0, fs_poll = 0, process = 0 }
vim.uv.walk(function(handle)
  local kind = handle:get_type()
  if handles[kind] ~= nil and handle:is_active() and not handle:is_closing() then
    handles[kind] = handles[kind] + 1
  end
end)
local report = {
  mode = mode.name(),
  source = mode.source(),
  notices = mode.notices(),
  degradations = mode.degradations(),
  storage = mode.storage(),
  disabled = disabled,
  plugins = plugins,
  handles = handles,
  statusline = vim.o.statusline,
  undofile = vim.o.undofile,
  swapfile = vim.o.swapfile,
  shadafile = vim.o.shadafile,
  clipboard = vim.o.clipboard,
  cursorline = vim.o.cursorline,
  foldcolumn = vim.o.foldcolumn,
  signcolumn = vim.o.signcolumn,
  clients = #vim.lsp.get_clients(),
  mappings = {},
  commands = {},
  extra = {},
}
for _, mapping in ipairs(vim.api.nvim_get_keymap("n")) do
  report.mappings[mapping.lhs] = true
end
for name in pairs(vim.api.nvim_get_commands({})) do
  report.commands[name] = true
end
]]

	local finish = [[
local file = assert(vim.env.NVIM_RESULT)
vim.fn.writefile({ vim.json.encode(report) }, file)
vim.cmd("qa!")
]]

	local function case_config(name, preferences)
		local home = vim.fs.joinpath(tmp, name, "config")
		local dir = vim.fs.joinpath(home, "nvim")
		vim.fn.mkdir(dir, "p")
		for _, entry in ipairs({ "init.lua", "lua", "after", "spell", "lazy-lock.json" }) do
			local link = vim.fs.joinpath(dir, entry)
			if not vim.uv.fs_lstat(link) then
				assert(vim.uv.fs_symlink(vim.fs.joinpath(root, entry), link), "could not link " .. entry)
			end
		end
		local path = vim.fs.joinpath(dir, "preferences.json")
		if preferences then
			vim.fn.writefile({ encode(preferences) }, path)
		else
			vim.fn.delete(path)
		end
		return home
	end

	---@param options table `env` overrides, `preferences`, extra probe `code`.
	local function run(name, options)
		options = options or {}
		local case = vim.fs.joinpath(tmp, name)
		for _, directory in ipairs({ "cache", "state", "work" }) do
			vim.fn.mkdir(vim.fs.joinpath(case, directory), "p")
		end
		local script = vim.fs.joinpath(case, "probe.lua")
		local result = vim.fs.joinpath(case, "result.json")
		local body = snapshot .. (options.code or "") .. finish
		vim.fn.writefile(vim.split(body, "\n", { plain = true }), script)

		local env = {
			XDG_CONFIG_HOME = case_config(name, options.preferences),
			XDG_CACHE_HOME = vim.fs.joinpath(case, "cache"),
			XDG_STATE_HOME = options.state_home or vim.fs.joinpath(case, "state"),
			NVIM_LOG_FILE = vim.fs.joinpath(case, "nvim.log"),
			NVIM_RESULT = result,
			NVIM_PROBE = script,
			NVIM_TEST_ROOT = root,
			-- Explicitly empty so the check inherits nothing from the developer's
			-- own shell: these are exactly the inputs under test.
			NVIM_MODE = options.mode or "",
			NVIM_STATE_DIR = options.state_dir or "",
			SSH_CONNECTION = options.ssh_connection or "",
			SSH_TTY = options.ssh_tty or "",
		}
		for key, value in pairs(options.env or {}) do
			env[key] = value
		end

		local argv = {
			vim.v.progpath,
			"--headless",
			"-u",
			vim.fs.joinpath(root, "init.lua"),
			"-i",
			"NONE",
			"--cmd",
			"lua vim.opt.runtimepath:prepend(vim.env.NVIM_TEST_ROOT)",
			"-c",
			"lua dofile(vim.env.NVIM_PROBE)",
		}
		vim.list_extend(argv, options.arguments or {})

		local process = vim.system(argv, { text = true, env = env, cwd = vim.fs.joinpath(case, "work") }):wait(60000)
		assert(
			process.code == 0,
			name
				.. " exited with "
				.. tostring(process.code)
				.. ":\n"
				.. (process.stderr or "")
				.. (process.stdout or "")
		)
		local lines = vim.fn.readfile(result)
		return vim.json.decode(table.concat(lines, "\n"))
	end

	-- 1. An unconfigured host still gets the complete editor.
	local default = run("default")
	assert(default.mode == "full", "An unconfigured host did not start in full mode: " .. default.mode)
	assert(default.source:match("^default"), "Full mode was not reported as the default: " .. default.source)
	assert(#default.disabled == 0, "Full mode disabled capabilities: " .. table.concat(default.disabled, ", "))
	assert(default.clipboard == "unnamedplus" and default.cursorline, "Full mode changed its editing defaults")

	-- 2. Priority: the environment wins, then the host preference, then default.
	local env_fast = run("env_fast", { mode = "fast" })
	assert(env_fast.mode == "fast" and env_fast.source == "NVIM_MODE=fast", "NVIM_MODE=fast was not honoured")

	local preference_fast = run("preference_fast", { preferences = { runtime = { mode = "fast" } } })
	assert(preference_fast.mode == "fast", "preferences.json runtime.mode=fast was not honoured")
	assert(preference_fast.source:find("preferences.json", 1, true), "The preference source was not reported")

	local override = run("override", { mode = "full", preferences = { runtime = { mode = "fast" } } })
	assert(override.mode == "full", "NVIM_MODE did not take priority over the host preference")

	local invalid = run("invalid", { mode = "turbo", preferences = { runtime = { mode = "fast" } } })
	assert(invalid.mode == "fast", "An unknown NVIM_MODE did not fall back to the host preference")
	assert(#invalid.notices > 0 and invalid.notices[1]:find("turbo", 1, true), "An unknown NVIM_MODE was not reported")

	local invalid_preference = run("invalid_preference", { preferences = { runtime = { mode = "turbo" } } })
	assert(invalid_preference.mode == "full", "An unknown runtime.mode did not fall back to full mode")
	assert(#invalid_preference.notices > 0, "An unknown runtime.mode was accepted silently")

	-- 3. `auto` is a selection rule over the connection, not a guess about the
	--    machine, the terminal or what it can draw.
	local auto_remote = run("auto_remote", { mode = "auto", ssh_connection = "10.0.0.2 51000 10.0.0.9 22" })
	assert(auto_remote.mode == "fast", "auto did not select fast for an SSH session")
	local auto_tty = run("auto_tty", { mode = "auto", ssh_tty = "/dev/pts/3" })
	assert(auto_tty.mode == "fast", "auto ignored SSH_TTY")
	local auto_local = run("auto_local", { mode = "auto" })
	assert(auto_local.mode == "full", "auto did not select full for a local session")
	-- A server writes the preference, so a tmux shell that lost SSH_CONNECTION
	-- still starts in fast mode.
	local auto_detached = run("auto_detached", { preferences = { runtime = { mode = "fast" } } })
	assert(auto_detached.mode == "fast", "A stored fast preference did not survive a lost SSH environment")

	-- 4. Fast mode initializes a smaller editor instead of hiding a complete one.
	local fast = run("fast_runtime", {
		mode = "fast",
		arguments = { vim.fs.joinpath(root, "lua", "user", "core", "mode.lua") },
		code = [[
report.extra.treesitter = vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()] ~= nil
report.extra.indentexpr = vim.bo.indentexpr
local ok_group, events = pcall(vim.api.nvim_get_autocmds, { group = "user_prose_spell" })
report.extra.autocmds = ok_group and #events or 0
]],
	})
	assert(fast.mode == "fast", "The fast case did not start in fast mode")
	assert(fast.clients == 0, "Fast mode started a language server on its own")
	assert(fast.statusline:find("FAST", 1, true), "The native statusline did not show the mode badge")
	assert(fast.clipboard == "", "Fast mode kept automatic system clipboard synchronisation")
	assert(not fast.cursorline and fast.foldcolumn == "0", "Fast mode kept the full-mode gutter")
	assert(not fast.undofile, "Fast mode enabled persistent undo by default")
	assert(fast.extra.treesitter, "Fast mode lost Tree-sitter highlighting")
	assert(fast.extra.indentexpr ~= "", "Fast mode lost Tree-sitter indentation")
	assert(fast.extra.autocmds == 0, "Fast mode registered events for a disabled feature")
	local expected = { "conform.nvim", "fzf-lua", "lazy.nvim", "mini.nvim", "nvim-treesitter", "oil.nvim" }
	for _, name in ipairs(expected) do
		assert(vim.tbl_contains(fast.plugins, name), "The fast plugin set is missing " .. name)
	end
	for _, name in ipairs({ "blink.cmp", "gitsigns.nvim", "lualine.nvim", "nvim-lspconfig", "neo-tree.nvim" }) do
		assert(not vim.tbl_contains(fast.plugins, name), "The fast plugin set still imported " .. name)
	end
	assert(#fast.plugins < #default.plugins, "Fast mode did not reduce the imported plugin set")
	assert(fast.commands.ModeInfo, ":ModeInfo is unavailable in fast mode")
	assert(not fast.mappings["<Leader>aa"], "Fast mode kept a mapping for a workflow it does not load")

	-- A host that asks for persistent undo gets it back without leaving fast mode.
	local undo = run("fast_undo", { mode = "fast", preferences = { runtime = { persistent_undo = true } } })
	assert(undo.mode == "fast" and undo.undofile, "runtime.persistent_undo did not re-enable persistent undo")

	-- 5. A state directory that cannot be used turns disk recovery off and says
	--    so, instead of failing on every write.
	local readonly = vim.fs.joinpath(tmp, "readonly-state")
	vim.fn.mkdir(readonly, "p")
	assert(vim.uv.fs_chmod(readonly, tonumber("500", 8)), "could not make the state directory read-only")
	local locked = run("readonly_state", {
		mode = "fast",
		state_dir = vim.fs.joinpath(readonly, "nvim"),
		code = [[
local file = vim.fs.joinpath(vim.fn.getcwd(), "edited.txt")
vim.cmd.edit(vim.fn.fnameescape(file))
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "still editable" })
vim.cmd.write()
report.extra.saved = vim.uv.fs_stat(file) ~= nil
]],
	})
	vim.uv.fs_chmod(readonly, tonumber("700", 8))
	assert(not locked.storage.writable, "A read-only state directory was reported as usable")
	assert(
		not locked.undofile and not locked.swapfile,
		"Recovery files were still enabled without a writable directory"
	)
	assert(locked.shadafile == "NONE", "ShaDa was still written without a writable directory")
	assert(#locked.notices > 0 and locked.notices[1]:find("recovery", 1, true), "Lost disk recovery was not reported")
	assert(locked.extra.saved, "Editing stopped working without a writable state directory")

	-- A relocated, writable state directory moves every recovery path with it.
	local relocated = vim.fs.joinpath(tmp, "relocated-state")
	local moved = run("relocated_state", { mode = "fast", state_dir = relocated })
	assert(moved.storage.writable and moved.storage.relocated, "The configured state directory was not used")
	assert(vim.uv.fs_stat(vim.fs.joinpath(relocated, "swap")), "The relocated state directory has no swap directory")
	local permissions = vim.uv.fs_stat(relocated)
	assert(permissions.mode % 64 == 0, "The relocated state directory is readable by other accounts")

	-- 6. Without a plugin manager there is still an editor: directory browsing,
	--    saving, indenting and quitting all work, and the loss is reported.
	local orphan = vim.fs.joinpath(tmp, "no-plugins", "data")
	vim.fn.mkdir(orphan, "p")
	local native = run("no_plugins", {
		mode = "fast",
		env = { XDG_DATA_HOME = orphan },
		arguments = { vim.fs.joinpath(tmp, "no_plugins", "work") },
		code = [[
report.extra.buftype = vim.bo.buftype
report.extra.listing = vim.api.nvim_buf_get_lines(0, 0, -1, false)
require("user.core.native").browse(vim.fn.getcwd())
report.extra.browsed = vim.b.user_native_directory ~= nil
local file = vim.fs.joinpath(vim.fn.getcwd(), "native.lua")
vim.cmd.edit(vim.fn.fnameescape(file))
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local a = {", "b = 1,", "}" })
vim.cmd("normal! gg=G")
vim.cmd.write()
report.extra.indented = vim.api.nvim_buf_get_lines(0, 0, -1, false)
report.extra.saved = vim.uv.fs_stat(file) ~= nil
]],
	})
	assert(#native.degradations > 0, "A missing plugin manager was not reported")
	local reported = false
	for _, entry in ipairs(native.degradations) do
		reported = reported or entry.subject == "plugins"
	end
	assert(reported, "The missing plugin manager was not recorded against the plugin set")
	assert(native.extra.browsed, "The native directory listing did not open")
	assert(native.extra.saved, "The native entry could not save a file")
	assert(
		native.extra.indented[2]:match("^%s+b = 1,") ~= nil,
		"The native entry lost filetype indentation: " .. vim.inspect(native.extra.indented)
	)
	assert(native.clients == 0, "The native entry started a language server")

	print(
		("Mode evidence: full by default; NVIM_MODE > preference > default; auto follows SSH; fast imports %d plugins (full %d) with %d disabled capabilities; read-only and relocated state handled; native entry browsed, indented and saved without a plugin manager."):format(
			#fast.plugins,
			#default.plugins,
			#fast.disabled
		)
	)
end
