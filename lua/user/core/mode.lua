-- Startup mode selection. The entry point loads this before anything else, so
-- it stays free of plugin requires, language probing and subprocesses: it reads
-- environment variables, the host preference file, and the one state directory
-- this session is going to write recovery data into.
--
-- The mode is decided once per process. Changing it means restarting, which is
-- deliberate: unloading plugins, reclaiming every mapping and rebuilding
-- language clients inside a live session cannot be made reliable.

local M = {}

local runtime_modes = { fast = true, standard = true, extra = true }

function M.canonical(name)
	return name == "full" and "extra" or name
end

-- The vocabulary the rest of the configuration uses to ask what this session is
-- allowed to do. Extra grants all of it, standard a curated set. Fast keeps the theme
-- and Tree-sitter highlighting, and drops the work that would otherwise run
-- while a file is opened, typed into, saved or scrolled.
local optional_capabilities = {
	"automation", -- automatic workflows, including input-method switching
	"codelens", -- inline LSP code lenses, refreshed as the buffer changes
	"completion", -- Blink, snippets, automatic candidate menus
	"conflicts", -- automatic Git conflict scanning and highlighting
	"cursorline", -- full-width current line colouring
	"decorations", -- matchup, illuminate, indent lines, colours, TODO, line blame
	"diagnostics_expanded", -- automatic current-line virtual messages
	"diagnostics_live", -- underline, virtual lines and live markers
	"diagnostics_text", -- trailing virtual text for the diagnostic on each line
	"docking", -- Edgy panel layout and dashboard
	"explorer_extras", -- Oil watchers/icons/metadata columns, Neo-tree
	"folding_provider", -- UFO and automatic fold computation
	"format_on_save",
	"git", -- Gitsigns, blame, diff watchers, Git statusline segments
	"icons", -- Nerd Font glyphs in the interface
	"inlay_hints_auto", -- inlay hints on attach
	"lint", -- standalone linter available on request
	"lint_live", -- standalone lint on read and InsertLeave, in addition to saves
	"lint_on_write", -- standalone linter runs after a save (BufWritePost only)
	"auxiliary_lsp", -- automatic Emmet/typos and unrestricted optional project servers
	"lsp_auto", -- language servers started without an explicit request
	"picker_extras", -- picker icons and automatic preview
	"plugin_manager_auto", -- install of missing plugins, change detection
	"render", -- images, PDF, markup and browser previews, VimTeX
	"run", -- debugging, tests, tasks and AI agents
	"scroll_animation",
	"session_auto", -- save a workspace on exit
	"session", -- manual workspace save/restore
	"signature", -- automatic signature rendering
	"spell_auto",
	"statusline_plugin", -- shared lualine theme and layout
	"system_clipboard", -- automatic unnamedplus synchronisation
	"terminal_manager", -- terminal manager and task panels
	"ui_panels", -- panel layout, bufferline, notify
	"undofile", -- persistent undo on disk
	"workspace_diagnostics", -- basedpyright and vtsls analyse the whole project below a size threshold
	"workspace_tools", -- on-request inspection: Outline, crates.nvim, dictionary, scratch
}

-- Standard is an explicit whitelist. New optional capabilities stay in extra
-- until their ongoing cost and role in everyday editing have been considered.
local standard = {}
for _, name in ipairs({
	"completion",
	"conflicts",
	"cursorline",
	"diagnostics_live",
	"diagnostics_text",
	"explorer_extras",
	"folding_provider",
	"format_on_save",
	"git",
	"icons",
	"lint",
	"lint_on_write",
	"lsp_auto",
	"picker_extras",
	"scroll_animation",
	"session",
	"signature",
	"statusline_plugin",
	"system_clipboard",
	"terminal_manager",
	"ui_panels",
	"undofile",
	"workspace_tools",
}) do
	standard[name] = true
end

-- Fast keeps the shared statusline; its tools are otherwise explicit requests.
local fast = { lint = true, statusline_plugin = true }

local notices = {}
local degradations = {}
local state

local function note(message)
	notices[#notices + 1] = message
end

---Record something this session cannot provide for a reason beyond the mode (a
---missing plugin, an unwritable directory, an absent parser). `:ModeInfo`
---reports these; startup only shows one short line that points at the command.
---A subject that happens to be a capability name also clears that capability.
---@param subject string
---@param reason string
function M.degrade(subject, reason)
	for _, entry in ipairs(degradations) do
		if entry.subject == subject and entry.reason == reason then
			return
		end
	end
	degradations[#degradations + 1] = { subject = subject, reason = reason }
	if state and state.values[subject] ~= nil then
		state.values[subject] = false
	end
end

function M.degradations()
	return vim.deepcopy(degradations)
end

local function select_mode(runtime, configured_by_host)
	local env = vim.env.NVIM_MODE
	if env and env ~= "" then
		local value = M.canonical(env:lower())
		if runtime_modes[value] then
			return value, "NVIM_MODE=" .. env:lower()
		end
		note(("NVIM_MODE=%s is not fast, standard or extra; using the host preference"):format(env))
	end

	local configured = configured_by_host and M.canonical(runtime.mode) or nil
	if runtime_modes[configured] then
		return configured, "preferences.json runtime.mode=" .. runtime.mode
	end
	return "standard", "default (no NVIM_MODE, no runtime.mode)"
end

local function directory_problem(path)
	local stat = vim.uv.fs_stat(path)
	if not stat then
		-- mkdir() raises on a permission error rather than returning zero, and a
		-- state directory that cannot be created is a report, not a failed start.
		local created = pcall(vim.fn.mkdir, path, "p", tonumber("700", 8))
		if not created then
			return "could not create " .. path
		end
		stat = vim.uv.fs_stat(path)
	end
	if not stat or stat.type ~= "directory" then
		return path .. " is not a directory"
	end
	local uid = vim.uv.getuid and vim.uv.getuid()
	if uid then
		if stat.uid ~= uid then
			return path .. " belongs to another user"
		end
		-- Recovery data is private. Tighten a shared directory once rather than
		-- writing undo, swap and ShaDa files other accounts can read.
		if stat.mode % 64 ~= 0 and not vim.uv.fs_chmod(path, tonumber("700", 8)) then
			return path .. " is readable by other accounts"
		end
	end
	if not vim.uv.fs_access(path, "W") then
		return path .. " is not writable"
	end
end

-- A relocated state directory under a shared temporary root survives only until
-- the next cleanup or logout. Say so instead of implying durable recovery.
local function is_volatile(path)
	for _, root in ipairs({ vim.env.TMPDIR, "/tmp", "/var/tmp", "/dev/shm" }) do
		if root and root ~= "" then
			root = vim.fs.normalize(root)
			if path == root or vim.startswith(path, root .. "/") then
				return true
			end
		end
	end
	return false
end

local function resolve_storage(runtime)
	local configured = runtime.state_dir
	if configured == "" then
		configured = vim.env.NVIM_STATE_DIR or ""
	end
	local relocated = configured ~= ""
	local path = relocated and vim.fs.normalize(vim.fn.expand(configured)) or vim.fs.normalize(vim.fn.stdpath("state"))
	local problem = directory_problem(path)
	if problem then
		-- Never redirect silently. A host that named a state directory asked to
		-- keep recovery data off the default path, and a host that named none
		-- has no second place to offer: report the loss instead.
		note("State directory is unusable: " .. problem .. "; disk recovery is off")
	end
	return {
		path = path,
		relocated = relocated,
		writable = problem == nil,
		reason = problem,
		volatile = problem == nil and is_volatile(path) or false,
	}
end

local function resolve()
	if state then
		return state
	end

	local preferences = require("user.core.preferences")
	local runtime = preferences.get("runtime")
	for _, message in ipairs(preferences.errors()) do
		if message:find("runtime.", 1, true) then
			note(message)
		end
	end

	local name, source = select_mode(runtime, preferences.provided("runtime.mode"))
	local values = {}
	for _, capability in ipairs(optional_capabilities) do
		values[capability] = name == "extra"
			or (name == "standard" and standard[capability] == true)
			or (name == "fast" and fast[capability] == true)
	end
	-- Persistent undo is recovery data, not a cache. Fast mode leaves it off by
	-- default and lets a host that wants it back say so.
	values.undofile = name ~= "fast" or runtime.persistent_undo

	local storage = resolve_storage(runtime)
	if not storage.writable then
		if values.undofile then
			M.degrade("undofile", storage.reason)
		end
		values.undofile = false
	end

	state = {
		name = name,
		source = source,
		values = values,
		storage = storage,
		preference = runtime.mode,
	}
	return state
end

---The resolved mode name: "fast", "standard" or "extra".
function M.name()
	return resolve().name
end

function M.is_fast()
	return resolve().name == "fast"
end

---Save the default, then restart to apply it; never unload the active plugin set.
function M.set_default(name)
	local ok, err = require("user.core.preferences").set("runtime", "mode", name)
	if not ok then
		vim.notify(err, vim.log.levels.ERROR, { title = "Editor mode" })
		return false
	end
	local target = M.canonical(name)
	if target == M.name() then
		vim.notify(
			"Saved editor mode: " .. name .. " (already active).",
			vim.log.levels.INFO,
			{ title = "Editor mode" }
		)
	else
		require("user.core.mode_restart").restart({ apply_mode = true })
	end
	return true
end

function M.toggle()
	return M.set_default(M.is_fast() and "standard" or "fast")
end

---Where the mode came from, for `:ModeInfo` and health output.
function M.source()
	return resolve().source
end

---Read-only capability set. Asking for a name that is not a capability is a
---typo, not a disabled feature, so it raises instead of reading as `false`.
function M.capabilities()
	local values = resolve().values
	return setmetatable({}, {
		__index = function(_, key)
			local value = values[key]
			if value == nil then
				error("Unknown capability: " .. tostring(key), 2)
			end
			return value
		end,
		__newindex = function()
			error("Capabilities are read-only; restart with a different mode", 2)
		end,
	})
end

---Capability names in a stable order, for reporting.
function M.capability_names()
	return vim.deepcopy(optional_capabilities)
end

---The single state directory this session writes recovery data into, with the
---reason it is unusable when that is the case. Resolved once per process.
function M.storage()
	return vim.deepcopy(resolve().storage)
end

function M.notices()
	resolve()
	return vim.deepcopy(notices)
end

---Emit the one-line startup notice, if this session has anything to say. The
---detail stays in `:ModeInfo` so a normal launch prints at most a single line.
function M.announce()
	local messages = M.notices()
	local count = #messages
	for _, entry in ipairs(degradations) do
		count = count + 1
		if #messages == 0 then
			messages = { entry.subject .. ": " .. entry.reason }
		end
	end
	if count == 0 then
		return
	end
	local summary = messages[1] .. (count > 1 and " (:ModeInfo for the rest)" or "")
	vim.schedule(function()
		vim.notify(summary, vim.log.levels.WARN, { title = "Editor mode" })
	end)
end

---Reset the cached decision. Only checks use this; a live session keeps the
---mode it started with.
function M.reset()
	state, notices, degradations = nil, {}, {}
end

---Evaluate `callback` as if this process had started in `name`. Preparation,
---verification and deployment tooling use this to ask what another mode would
---install; a live session never changes the mode it started with.
---@param name string
---@param callback function
function M.as(name, callback)
	local previous = { env = vim.env.NVIM_MODE, state = state, notices = notices, degradations = degradations }
	vim.env.NVIM_MODE = name
	state, notices, degradations = nil, {}, {}
	local ok, result = pcall(callback)
	vim.env.NVIM_MODE = previous.env
	state, notices, degradations = previous.state, previous.notices, previous.degradations
	if not ok then
		error(result, 0)
	end
	return result
end

return M
