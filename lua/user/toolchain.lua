local M = {}

-- Mason packages are deliberately pinned. Opening a file never installs this
-- list; :MasonToolsInstall is the explicit, reproducible restore operation.
-- This list contains only servers enabled by the shared LSP setup; specialized
-- Java and Rust servers are managed by their own plugins and remain pinned below.
M.lsp_servers = {
	"asm_lsp",
	"autotools_ls",
	"bashls",
	"basedpyright",
	"biome",
	"clangd",
	"cssls",
	"dockerls",
	"emmet_language_server",
	"gopls",
	"html",
	"jsonls",
	"lua_ls",
	"marksman",
	"neocmake",
	"ruff",
	"sqlls",
	"tailwindcss",
	"taplo",
	"texlab",
	"tinymist",
	"typos_lsp",
	"verible",
	"vtsls",
	"vue_ls",
	"yamlls",
}

local packages = {
	-- Language servers.
	{ "asm-lsp", version = "0.10.1" },
	{ "autotools-language-server", version = "0.0.23" },
	{ "bash-language-server", version = "5.6.0" },
	{ "basedpyright", version = "1.39.8" },
	{ "biome", version = "2.5.0" },
	{ "clangd", version = "22.1.0" },
	{ "css-lsp", version = "4.10.0" },
	{ "dockerfile-language-server", version = "0.15.0" },
	{ "emmet-language-server", version = "2.8.0" },
	{ "gopls", version = "v0.22.0" },
	{ "html-lsp", version = "4.10.0" },
	{ "jdtls", version = "v1.60.0" },
	{ "json-lsp", version = "4.10.0" },
	{ "lua-language-server", version = "3.18.2" },
	{ "marksman", version = "2026-02-08" },
	{ "neocmakelsp", version = "v0.10.2" },
	{ "ruff", version = "0.15.14" },
	{ "rust-analyzer", version = "2026-05-18" },
	{ "sqlls", version = "1.7.1" },
	{ "tailwindcss-language-server", version = "0.14.29" },
	{ "taplo", version = "0.10.0" },
	{ "texlab", version = "v5.25.1" },
	{ "tinymist", version = "v0.14.18" },
	{ "typos-lsp", version = "v0.1.52" },
	{ "verible", version = "v0.0-4053-g89d4d98a" },
	{ "vtsls", version = "0.3.0" },
	{ "vue-language-server", version = "3.3.1" },
	{ "yaml-language-server", version = "1.23.0" },

	-- Formatters and linters.
	{ "asmfmt", version = "v1.3.2" },
	{ "checkmake", version = "v0.3.2" },
	{ "clang-format", version = "22.1.5" },
	{ "cmakelang", version = "0.6.13" },
	{ "cmakelint", version = "1.4.3" },
	{ "gofumpt", version = "v0.10.0" },
	{ "goimports", version = "v0.45.0" },
	{ "golangci-lint", version = "v2.12.2" },
	{ "hadolint", version = "v2.14.0" },
	{ "latexindent", version = "V3.24.4" },
	{ "markdownlint-cli2", version = "0.22.1" },
	{ "prettier", version = "3.8.3" },
	{ "selene", version = "0.31.0" },
	{ "shellcheck", version = "v0.11.0" },
	{ "shfmt", version = "v3.13.1" },
	{ "sqruff", version = "v0.38.0" },
	{ "stylelint", version = "17.11.1" },
	{ "stylua", version = "v2.5.2" },
	{ "typstyle", version = "v0.14.4" },
	{ "yamllint", version = "1.38.0" },

	-- Debug adapters and test support.
	{ "codelldb", version = "v1.12.2" },
	{ "debugpy", version = "1.8.21" },
	{ "delve", version = "v1.27.0" },
	{ "js-debug-adapter", version = "v1.117.0" },
	{ "java-debug-adapter", version = "0.59.0" },
	{ "java-test", version = "0.46.0" },
}

M.packages = packages

-- Profiles select explicit restores only. File opening and normal startup never
-- install tools, and all profiles reuse the single catalog of pinned versions.
M.profiles = {
	minimal = { "lua-language-server", "stylua", "selene", "ruff", "shellcheck", "shfmt" },
	python = { "basedpyright", "ruff", "debugpy" },
	web = {
		"js-debug-adapter",
		"biome",
		"css-lsp",
		"dockerfile-language-server",
		"emmet-language-server",
		"html-lsp",
		"json-lsp",
		"sqlls",
		"tailwindcss-language-server",
		"vtsls",
		"vue-language-server",
		"yaml-language-server",
		"prettier",
		"stylelint",
	},
	java = { "jdtls", "java-debug-adapter", "java-test" },
	native = {
		"asm-lsp",
		"autotools-language-server",
		"clangd",
		"gopls",
		"neocmakelsp",
		"rust-analyzer",
		"taplo",
		"verible",
		"asmfmt",
		"checkmake",
		"clang-format",
		"cmakelang",
		"cmakelint",
		"gofumpt",
		"goimports",
		"golangci-lint",
		"codelldb",
		"delve",
	},
	docs = { "marksman", "texlab", "tinymist", "typos-lsp", "latexindent", "markdownlint-cli2", "typstyle" },
	full = {}, -- The complete catalog, including tools outside the named language profiles.
}

function M.ensure_installed(profiles)
	profiles = profiles or { "minimal" }
	if type(profiles) == "string" then
		profiles = { profiles }
	end
	assert(type(profiles) == "table", "Tool profiles must be a name or list of names")
	local selected, full = {}, false
	for _, name in ipairs(M.profiles.minimal) do
		selected[name] = true
	end
	for _, profile in ipairs(profiles) do
		assert(M.profiles[profile], "Unknown tool profile: " .. tostring(profile))
		full = full or profile == "full"
		for _, name in ipairs(M.profiles[profile]) do
			selected[name] = true
		end
	end
	local result = {}
	for _, package in ipairs(packages) do
		if full or selected[package[1]] then
			table.insert(result, vim.deepcopy(package))
		end
	end
	return result
end

M.node_commands = {
	["basedpyright-langserver"] = true,
	["bash-language-server"] = true,
	biome = true,
	["docker-langserver"] = true,
	["emmet-language-server"] = true,
	["markdownlint-cli2"] = true,
	prettier = true,
	["sql-language-server"] = true,
	stylelint = true,
	["tailwindcss-language-server"] = true,
	["vscode-css-language-server"] = true,
	["vscode-html-language-server"] = true,
	["vscode-json-language-server"] = true,
	vtsls = true,
	["vue-language-server"] = true,
	["yaml-language-server"] = true,
}

function M.version(name)
	for _, package in ipairs(packages) do
		if package[1] == name then
			return package.version
		end
	end
end

local executable_cache = {}
local cache_size = 0
local watched_registry

local function executable_in(directory, name)
	local candidates = vim.fn.has("win32") == 1 and { name .. ".cmd", name .. ".exe", name .. ".bat", name } or { name }
	for _, candidate in ipairs(candidates) do
		local path = vim.fs.joinpath(directory, candidate)
		if vim.fn.executable(path) == 1 then
			return path
		end
	end
end

local function preference(opts)
	if opts.prefer_mason ~= nil then
		return opts.prefer_mason
	end
	local ok, preferences = pcall(require, "user.core.preferences")
	return ok and (preferences.get("tools") or {}).prefer_mason == true or false
end

local function context(opts, source)
	return opts.context or require("user.core.project").context(source or opts.bufnr or opts.path)
end

local function cache_key(kind, name, ctx, prefer_mason)
	return table.concat({
		kind,
		name,
		ctx.root or "",
		ctx.language_root or "",
		ctx.directory or "",
		vim.fn.getcwd(),
		vim.env.PATH or "",
		vim.env.JAVA_HOME or "",
		vim.env.VIRTUAL_ENV or "",
		vim.env.CONDA_PREFIX or "",
		vim.env.PATHEXT or "",
		prefer_mason and "mason" or "system",
	}, "\0")
end

local function cached(key)
	local value = executable_cache[key]
	if value and (not value.path or vim.fn.executable(value.path) == 1) then
		return vim.deepcopy(value)
	end
end

local function remember(key, value)
	if cache_size >= 512 then
		executable_cache, cache_size = {}, 0
	end
	if not executable_cache[key] then
		cache_size = cache_size + 1
	end
	executable_cache[key] = value
	return vim.deepcopy(value)
end

local function result(path, source, reason)
	return { path = path, source = source, reason = reason }
end

local function project_directories(ctx, start)
	local project = require("user.core.project")
	local directory = start or ctx.directory
	local boundary = ctx.repository or ctx.root
	if not directory then
		return {}
	end
	if not boundary or not project.contains(boundary, directory) then
		boundary = ctx.language_root or directory
	end
	local directories = {}
	while directory and project.contains(boundary, directory) do
		table.insert(directories, directory)
		if directory == boundary then
			break
		end
		local parent = vim.fs.dirname(directory)
		if parent == directory then
			break
		end
		directory = parent
	end
	return directories
end

function M.resolve(name, opts)
	opts = opts or {}
	local ctx = context(opts)
	local prefer_mason = preference(opts)
	local key = cache_key("executable", name, ctx, prefer_mason)
	local previous = cached(key)
	if previous then
		return previous
	end
	if name:find("[/\\]") then
		local path = vim.fn.exepath(name)
		return remember(
			key,
			path ~= "" and result(path, "explicit", "Explicit executable path")
				or result(nil, "missing", "Explicit executable path is unavailable")
		)
	end
	local mason = executable_in(vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "bin"), name)
	if prefer_mason and mason then
		return remember(key, result(mason, "mason", "Mason is preferred for this tool"))
	end
	local system = vim.fn.exepath(name)
	if system ~= "" then
		return remember(key, result(system, "system", "First executable on PATH"))
	end
	return remember(
		key,
		mason and result(mason, "mason", "No executable on PATH; using Mason")
			or result(nil, "missing", "Not found on PATH or in Mason")
	)
end

function M.executable(name, opts)
	return M.resolve(name, opts).path
end

function M.node_resolve(name, source, opts)
	opts = opts or {}
	local ctx = context(opts, source)
	local key = cache_key("node", name, ctx, preference(opts))
	local previous = cached(key)
	if previous then
		return previous
	end
	for _, directory in ipairs(project_directories(ctx)) do
		local path = executable_in(vim.fs.joinpath(directory, "node_modules", ".bin"), name)
		if path then
			return remember(key, result(path, "project", "Project node_modules/.bin in " .. directory))
		end
	end
	return remember(key, M.resolve(name, vim.tbl_extend("force", opts, { context = ctx })))
end

function M.node_executable(name, source, opts)
	return M.node_resolve(name, source, opts).path
end

local function venv_python(directory)
	local path = vim.fs.joinpath(directory, vim.fn.has("win32") == 1 and "Scripts/python.exe" or "bin/python")
	return vim.fn.executable(path) == 1 and path or nil
end

function M.python_resolve(source)
	local ctx = context({}, source)
	local key = cache_key("python-target", "python", ctx, false)
	local previous = cached(key)
	if previous then
		return previous
	end
	for _, directory in ipairs(project_directories(ctx, ctx.language_root or ctx.directory)) do
		for _, environment in ipairs({ ".venv", "venv" }) do
			local path = venv_python(vim.fs.joinpath(directory, environment))
			if path then
				return remember(key, result(path, "project", "Project " .. environment .. " in " .. directory))
			end
		end
	end
	if vim.env.VIRTUAL_ENV then
		local path = venv_python(vim.env.VIRTUAL_ENV)
		if path then
			return remember(key, result(path, "environment", "VIRTUAL_ENV"))
		end
	end
	-- A target interpreter is a project/runtime choice, never Mason's private
	-- debugpy interpreter. Preserve the venv path even when it is a symlink.
	for _, name in ipairs({ "python", "python3" }) do
		local path = vim.fn.exepath(name)
		if path ~= "" then
			return remember(key, result(path, "system", name .. " on PATH"))
		end
	end
	return remember(key, result(nil, "missing", "No project virtualenv, VIRTUAL_ENV, or Python on PATH"))
end

function M.python_executable(source)
	return M.python_resolve(source).path
end

function M.debugpy_host()
	local ctx = context({})
	local key = cache_key("debugpy-host", "debugpy", ctx, false)
	local previous = cached(key)
	if previous then
		return previous
	end
	if vim.fn.has("win32") ~= 1 then
		local adapter = vim.fn.exepath("debugpy-adapter")
		if adapter ~= "" then
			return remember(key, result(adapter, "system", "Standalone debugpy adapter on PATH"))
		end
	end
	for _, name in ipairs({ "python3", "python" }) do
		local python = vim.fn.exepath(name)
		if python ~= "" then
			local ok, process = pcall(vim.system, { python, "-c", "import debugpy" }, { text = true })
			if ok and process:wait(2000).code == 0 then
				return remember(key, result(python, "system", "Python on PATH with the debugpy module"))
			end
		end
	end
	local python = venv_python(vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "packages", "debugpy", "venv"))
	return remember(
		key,
		python and result(python, "mason", "Mason's private debugpy host")
			or result(
				nil,
				"missing",
				"No debugpy adapter or Python host with debugpy; install the debugpy Mason package"
			)
	)
end

function M.clear_executable_cache()
	executable_cache, cache_size = {}, 0
end

M.reset = M.clear_executable_cache

function M.refresh(opts)
	require("user.core.preferences").refresh()
	M.clear_executable_cache()
	local java = package.loaded["user.core.java"]
	if java then
		java.clear_runtime_cache()
	end
	vim.api.nvim_exec_autocmds("User", { pattern = "UserToolsChanged", modeline = false })
	if not (opts and opts.silent) then
		vim.notify(
			"Tool paths refreshed. See :checkhealth user for sources and active language servers.",
			vim.log.levels.INFO,
			{ title = "Tools" }
		)
	end
end

function M.watch_mason()
	local registry = require("mason-registry")
	if watched_registry == registry then
		return
	end
	watched_registry = registry
	local pending = false
	local function refresh()
		if pending then
			return
		end
		pending = true
		vim.schedule(function()
			pending = false
			M.refresh({ silent = true })
		end)
	end
	registry:on("package:install:success", refresh)
	registry:on("package:uninstall:success", refresh)
end

function M.setup()
	local group = vim.api.nvim_create_augroup("user_toolchain", { clear = true })
	vim.api.nvim_create_autocmd({ "FocusGained", "DirChanged" }, { group = group, callback = M.clear_executable_cache })
	vim.api.nvim_create_autocmd("BufWritePost", {
		group = group,
		pattern = { "package.json", "*lock*", "pyproject.toml", "pyvenv.cfg" },
		callback = M.clear_executable_cache,
	})
	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = "MasonToolsUpdateCompleted",
		callback = function()
			M.refresh({ silent = true })
		end,
	})
end

M.setup()

return M
