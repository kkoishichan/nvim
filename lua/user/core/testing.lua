local M = {}
local toolchain = require("user.toolchain")

local loaded = {}
local configured = false
local projects = {}

local function csharp_root(directory)
	local solution = vim.fs.root(directory, function(name)
		return name:match("%.slnx?$") ~= nil
	end)
	if solution then
		return solution
	end
	return vim.fs.root(directory, function(name)
		return name:match("%.csproj$") ~= nil
	end)
end

local debug_plugins = {
	cs = "nvim-dap",
	go = "nvim-dap-go",
	javascript = "nvim-dap-vscode-js",
	javascriptreact = "nvim-dap-vscode-js",
	python = "nvim-dap-python",
	rust = "nvim-dap",
	typescript = "nvim-dap-vscode-js",
	typescriptreact = "nvim-dap-vscode-js",
	vue = "nvim-dap-vscode-js",
}

local debug_unsupported = {
	kotlin = "The Kotlin Neotest adapter cannot debug tests; use F5 for application debugging.",
}

local definitions = {
	cs = {
		{
			plugin = "neotest-vstest",
			module = "neotest-vstest",
			-- The adapter retains its selected solution in a closure. Give each
			-- registered project a fresh instance so two solutions never collide.
			cache = false,
			requires = { "dotnet" },
			root = csharp_root,
			create = function(adapter)
				return adapter({
					-- Avoid recursively scanning every descendant when Neovim was
					-- opened above a solution (for example in $HOME).
					broad_recursive_discovery = false,
					dap_settings = { type = "netcoredbg" },
				})
			end,
		},
	},
	python = {
		{
			plugin = "neotest-python",
			module = "neotest-python",
			create = function(adapter)
				return adapter({ dap = { justMyCode = false } })
			end,
		},
	},
	go = {
		{
			plugin = "neotest-golang",
			module = "neotest-golang",
			create = function(adapter)
				return adapter({})
			end,
		},
	},
	kotlin = {
		{ plugin = "neotest-kotlin", module = "neotest-kotlin", requires = { "java" } },
	},
	rust = {
		{ plugin = "rustaceanvim", module = "rustaceanvim.neotest" },
	},
	javascript = {
		{
			plugin = "neotest-jest",
			module = "neotest-jest",
			create = function(adapter)
				return adapter({})
			end,
		},
		{
			plugin = "neotest-vitest",
			module = "neotest-vitest",
			create = function(adapter)
				return adapter({})
			end,
		},
	},
}

definitions.javascriptreact = definitions.javascript
definitions.typescript = definitions.javascript
definitions.typescriptreact = definitions.javascript
definitions.vue = definitions.javascript

local function configure_once()
	if not configured then
		require("neotest").setup({ adapters = {} })
		configured = true
	end
end

local function load_adapter(definition)
	if definition.cache ~= false and loaded[definition.plugin] then
		return loaded[definition.plugin]
	end
	for _, requirement in ipairs(definition.requires or {}) do
		if not toolchain.executable(requirement) then
			vim.notify(
				("Test adapter %s requires %q on PATH."):format(definition.plugin, requirement),
				vim.log.levels.ERROR,
				{ title = "Tests" }
			)
			return nil
		end
	end

	local ok_load = pcall(function()
		require("lazy").load({ plugins = { definition.plugin } })
	end)
	local ok_module, adapter = pcall(require, definition.module)
	if not ok_load or not ok_module then
		vim.notify(("Could not load test adapter %s"):format(definition.plugin), vim.log.levels.ERROR, {
			title = "Tests",
		})
		return nil
	end

	if definition.create then
		local ok_create, created = pcall(definition.create, adapter)
		if not ok_create then
			vim.notify(
				("Could not configure test adapter %s: %s"):format(definition.plugin, created),
				vim.log.levels.ERROR,
				{
					title = "Tests",
				}
			)
			return nil
		end
		adapter = created
	end
	if definition.cache ~= false then
		loaded[definition.plugin] = adapter
	end
	return adapter
end

local function adapter_root(definition, adapter)
	local file = vim.api.nvim_buf_get_name(0)
	local directory = file ~= "" and vim.fs.dirname(vim.fs.abspath(file)) or vim.fn.getcwd()
	local ok_root, root = pcall(definition.root or adapter.root, directory)
	if ok_root and root then
		return vim.uv.fs_realpath(root) or vim.fs.abspath(root)
	end

	-- Match Neotest's fallback for a standalone test file with no project
	-- marker: scope that adapter to the file's directory.
	if file ~= "" then
		local ok_test, is_test = pcall(adapter.is_test_file, file)
		if ok_test and is_test then
			return directory
		end
	end
end

local function register_adapter(definition, adapter)
	local root = adapter_root(definition, adapter)
	if not root then
		return false
	end

	local project = projects[root]
	if not project then
		project = { adapters = {}, plugins = {} }
		projects[root] = project
	end
	if not project.plugins[definition.plugin] then
		project.plugins[definition.plugin] = true
		table.insert(project.adapters, adapter)
		require("neotest").setup_project(root, { adapters = project.adapters })
	end
	return true
end

local function ensure_adapter()
	configure_once()
	local filetype = vim.bo.filetype
	local requested = definitions[filetype]
	if not requested then
		return false
	end

	local available = false
	for _, definition in ipairs(requested) do
		local adapter = load_adapter(definition)
		available = adapter and register_adapter(definition, adapter) or available
	end
	return available
end

local function with_neotest(callback, require_adapter)
	local available = ensure_adapter()
	if require_adapter and not available then
		vim.notify(
			"No test adapter is configured for " .. (vim.bo.filetype ~= "" and vim.bo.filetype or "this buffer"),
			vim.log.levels.WARN,
			{
				title = "Tests",
			}
		)
		return
	end
	callback(require("neotest"))
end

function M.prepare()
	return ensure_adapter()
end

function M.run(target)
	if type(target) == "table" and target.strategy == "dap" then
		local unsupported = debug_unsupported[vim.bo.filetype]
		if unsupported then
			vim.notify(unsupported, vim.log.levels.WARN, { title = "Tests" })
			return
		end
		local plugin = debug_plugins[vim.bo.filetype]
		if plugin then
			require("lazy").load({ plugins = { plugin } })
		end
	end
	with_neotest(function(neotest)
		neotest.run.run(target)
	end, true)
end

function M.stop()
	with_neotest(function(neotest)
		neotest.run.stop()
	end)
end

function M.summary()
	with_neotest(function(neotest)
		neotest.summary.toggle()
	end)
end

function M.output()
	with_neotest(function(neotest)
		neotest.output.open({ enter = true, auto_close = true })
	end)
end

function M.output_panel()
	with_neotest(function(neotest)
		neotest.output_panel.toggle()
	end)
end

function M.watch()
	with_neotest(function(neotest)
		neotest.watch.toggle(vim.fn.expand("%"))
	end, true)
end

return M
