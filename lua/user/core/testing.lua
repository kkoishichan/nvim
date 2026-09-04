local M = {}
local toolchain = require("user.toolchain")
local float_style = require("user.core.float_style")

local loaded = {}
local configured = false
local projects = {}
local javascript_choices = {}
local javascript_contexts = {}

local function javascript_context(path)
	if not path or path == "" then
		return nil
	end
	path = vim.uv.fs_realpath(path) or vim.fs.abspath(path)
	local stat = vim.uv.fs_stat(path)
	local directory = stat and stat.type == "directory" and path or vim.fs.dirname(path)
	if javascript_contexts[directory] then
		return javascript_contexts[directory]
	end
	local start = directory
	while directory do
		local frameworks = {}
		-- A package-local configuration is more specific than dependencies shared
		-- at the workspace root. Never consult Neovim's unrelated working directory.
		for _, framework in ipairs({ "jest", "vitest" }) do
			for _, extension in ipairs({ "js", "ts", "cjs", "mjs", "cts", "mts", "json" }) do
				if vim.uv.fs_stat(vim.fs.joinpath(directory, framework .. ".config." .. extension)) then
					frameworks[framework] = true
				end
			end
		end
		local ok_read, lines = pcall(vim.fn.readfile, vim.fs.joinpath(directory, "package.json"))
		local ok_json, package = false, nil
		if ok_read then
			ok_json, package = pcall(vim.json.decode, table.concat(lines, "\n"))
		end
		if ok_json and type(package) == "table" then
			if package.jest ~= nil then
				frameworks.jest = true
			end
			if not next(frameworks) then
				for _, field in ipairs({ "dependencies", "devDependencies" }) do
					local dependencies = type(package[field]) == "table" and package[field] or {}
					frameworks.jest = frameworks.jest or dependencies.jest ~= nil
					frameworks.vitest = frameworks.vitest
						or dependencies.vitest ~= nil
						or dependencies["@vitest/ui"] ~= nil
				end
				for _, script in pairs(type(package.scripts) == "table" and package.scripts or {}) do
					if type(script) == "string" then
						frameworks.jest = frameworks.jest or script == "jest" or script:match("^jest%s") ~= nil
						frameworks.vitest = frameworks.vitest or script == "vitest" or script:match("^vitest%s") ~= nil
					end
				end
			end
		end
		if frameworks.jest or frameworks.vitest then
			local context = { root = directory, frameworks = frameworks }
			javascript_contexts[start] = context
			return context
		end
		if vim.uv.fs_stat(vim.fs.joinpath(directory, ".git")) or vim.uv.fs_stat(vim.fs.joinpath(directory, ".jj")) then
			break
		end
		local parent = vim.fs.dirname(directory)
		if parent == directory then
			break
		end
		directory = parent
	end
	return nil
end

local function javascript_framework(context)
	if not context then
		return nil
	end
	local choice = javascript_choices[context.root]
	if choice and context.frameworks[choice] then
		return choice
	end
	if context.frameworks.jest ~= context.frameworks.vitest then
		return context.frameworks.jest and "jest" or "vitest"
	end
end

local function javascript_adapter(adapter, framework)
	local wrapped = vim.tbl_extend("force", {}, adapter)
	wrapped.root = function(path)
		local context = javascript_context(path)
		return javascript_framework(context) == framework and context.root or nil
	end
	wrapped.is_test_file = function(path)
		if not path or javascript_framework(javascript_context(path)) ~= framework then
			return false
		end
		-- The upstream dependency checks fall back to process cwd. Use a
		-- filename-only check after selecting the framework from this file's tree.
		if path:match("[/\\]__tests__[/\\]") then
			return true
		end
		for _, suffix in ipairs(framework == "vitest" and { "test", "spec", "e2e" } or { "test", "spec" }) do
			for _, extension in ipairs({ "js", "jsx", "ts", "tsx", "cjs", "mjs", "cts", "mts", "coffee" }) do
				if path:match("%." .. suffix .. "%." .. extension .. "$") then
					return true
				end
			end
		end
		return false
	end
	return wrapped
end

local debug_plugins = {
	go = "nvim-dap-go",
	javascript = "nvim-dap-vscode-js",
	javascriptreact = "nvim-dap-vscode-js",
	python = "nvim-dap-python",
	rust = "nvim-dap",
	typescript = "nvim-dap-vscode-js",
	typescriptreact = "nvim-dap-vscode-js",
	vue = "nvim-dap-vscode-js",
}

local definitions = {
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
	rust = {
		{ plugin = "rustaceanvim", module = "rustaceanvim.neotest" },
	},
	javascript = {
		{
			plugin = "neotest-jest",
			module = "neotest-jest",
			framework = "jest",
			create = function(adapter)
				return javascript_adapter(adapter({}), "jest")
			end,
		},
		{
			plugin = "neotest-vitest",
			module = "neotest-vitest",
			framework = "vitest",
			create = function(adapter)
				return javascript_adapter(adapter({}), "vitest")
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
		require("neotest").setup({
			adapters = {},
			floating = { border = float_style.border() },
		})
		configured = true
		local group = vim.api.nvim_create_augroup("user_test_projects", { clear = true })
		vim.api.nvim_create_autocmd({ "FocusGained", "BufWritePost" }, {
			group = group,
			callback = function()
				javascript_contexts = {}
			end,
		})
		vim.api.nvim_create_user_command("TestAdapter", function(args)
			local context = javascript_context(vim.api.nvim_buf_get_name(0))
			if not context then
				vim.notify("No Jest or Vitest project was found for this buffer", vim.log.levels.WARN)
				return
			end
			if args.args ~= "auto" and not context.frameworks[args.args] then
				vim.notify("This project does not declare " .. args.args, vim.log.levels.WARN)
				return
			end
			javascript_choices[context.root] = args.args ~= "auto" and args.args or nil
			projects[context.root] = nil
			require("neotest").setup_project(context.root, { adapters = {} })
		end, {
			nargs = 1,
			complete = function()
				return { "jest", "vitest", "auto" }
			end,
			desc = "Choose the test framework for this JavaScript project",
		})
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
	local framework
	if requested == definitions.javascript then
		local context = javascript_context(vim.api.nvim_buf_get_name(0))
		framework = javascript_framework(context)
		if not framework then
			if context then
				vim.notify(
					"Both Jest and Vitest are declared here; choose :TestAdapter jest or :TestAdapter vitest",
					vim.log.levels.WARN
				)
			end
			return false
		end
	end
	for _, definition in ipairs(requested) do
		if not definition.framework or definition.framework == framework then
			local adapter = load_adapter(definition)
			available = adapter and register_adapter(definition, adapter) or available
		end
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
