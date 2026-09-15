return function(tmp)
	local base = vim.fs.joinpath(tmp, "toolchain")
	local tools = require("user.toolchain")
	local preferences = require("user.core.preferences")
	local function write(path, lines)
		vim.fn.mkdir(vim.fs.dirname(path), "p")
		vim.fn.writefile(lines, path)
	end
	local function executable(path, output)
		write(path, { "#!/bin/sh", "printf '%s\\n' '" .. (output or "fixture") .. "'" })
		vim.fn.setfperm(path, "rwxr-xr-x")
		return path
	end
	local function buffer(path, filetype)
		local bufnr = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(bufnr, path)
		vim.api.nvim_set_current_buf(bufnr)
		if filetype then
			vim.cmd("noautocmd setlocal filetype=" .. filetype)
		end
		return bufnr
	end
	assert(vim.fn.has("win32") == 0, "Toolchain fixtures currently require a POSIX shell")

	-- Install/uninstall refresh changes admission for future buffers, preserving
	-- the root guards and never requesting a running client to stop.
	do
		local original, available = tools.executable, nil
		tools.executable = function(name, opts)
			if name == "lua-language-server" then
				return available
			end
			return original(name, opts)
		end
		require("lazy").load({ plugins = { "nvim-lspconfig" } })
		assert(not vim.lsp.is_enabled("lua_ls"), "Unavailable fixture server was enabled")
		local root, on_init = vim.lsp.config.lua_ls.root_dir, vim.lsp.config.lua_ls.on_init
		available = executable(base .. "/new-language-server")
		local original_stop, stops = vim.lsp.stop_client, 0
		vim.lsp.stop_client = function()
			stops = stops + 1
		end
		tools.refresh({ silent = true })
		assert(
			vim.lsp.is_enabled("lua_ls") and vim.lsp.config.lua_ls.cmd[1] == available,
			"Refresh did not enable a newly available server"
		)
		assert(
			vim.lsp.config.lua_ls.root_dir == root and vim.lsp.config.lua_ls.on_init == on_init,
			"Refresh wrapped LSP guards a second time"
		)
		available = nil
		tools.refresh({ silent = true })
		local started = false
		local bufnr = buffer(base .. "/new.lua")
		root(bufnr, function()
			started = true
		end)
		assert(not started, "An uninstalled server was admitted for a new buffer")
		assert(stops == 0, "Refreshing stopped a running language server")
		vim.lsp.stop_client, tools.executable = original_stop, original
		vim.api.nvim_buf_delete(bufnr, { force = true })
		vim.lsp.enable(tools.lsp_servers, false)
		assert(not package.loaded.mason and not package.loaded["mason-registry"], "Ordinary tool refresh loaded Mason")
	end

	local old_path, old_venv, old_java = vim.env.PATH, vim.env.VIRTUAL_ENV, vim.env.JAVA_HOME
	local old_stdpath, old_preferences = vim.fn.stdpath, preferences.get
	local prefer_mason = false
	preferences.get = function(section)
		return section == "tools" and { prefer_mason = prefer_mason } or old_preferences(section)
	end
	vim.fn.stdpath = function(kind)
		return kind == "data" and base .. "/data" or old_stdpath(kind)
	end
	local bin_a, bin_b = base .. "/bin-a", base .. "/bin-b"
	local system = executable(bin_a .. "/audit-tool")
	local mason = executable(base .. "/data/mason/bin/audit-tool")
	vim.env.PATH = bin_a .. ":" .. old_path
	tools.reset()
	assert(tools.resolve("audit-tool").path == system, "Default lookup did not prefer PATH")
	do
		local project = require("user.core.project")
		local original = project.context
		project.context = function()
			error("Global tool lookup must not scan project markers")
		end
		assert(tools.executable("audit-tool") == system, "Cached PATH tool changed")
		assert(tools.executable(system) == system, "Explicit tool path changed")
		assert(tools.executable("audit-tool", { prefer_mason = true }) == mason, "Mason tool changed")
		project.context = original
	end
	assert(tools.resolve("audit-tool", { prefer_mason = true }).path == mason, "Explicit Mason preference was ignored")
	prefer_mason = true
	assert(tools.resolve("audit-tool").source == "mason", "Changed preferences reused the PATH cache")
	assert(
		tools.resolve("audit-tool", { prefer_mason = false }).path == system,
		"Explicit PATH preference did not override defaults"
	)
	prefer_mason = false
	local second = executable(bin_b .. "/audit-tool")
	vim.env.PATH = bin_b .. ":" .. old_path
	assert(tools.executable("audit-tool") == second, "PATH changes reused an old executable")
	local resolved = tools.resolve("audit-tool")
	resolved.path = "changed by caller"
	assert(tools.executable("audit-tool") == second, "A caller mutated the cache")
	assert(tools.resolve(base .. "/missing").source == "missing", "Missing explicit path was not explained")
	assert(tools.resolve(second).source == "explicit", "Explicit path was not recognized")
	assert(tools.executable("installed-later") == nil, "Installation fixture already exists")
	local later = executable(bin_b .. "/installed-later")
	assert(tools.executable("installed-later") == nil, "Negative cache was not exercised")
	vim.api.nvim_exec_autocmds("User", { pattern = "MasonToolsUpdateCompleted" })
	assert(tools.executable("installed-later") == later, "Mason completion did not refresh missing tools")
	vim.lsp.enable(tools.lsp_servers, false)

	local a, b = base .. "/a", base .. "/b"
	for _, directory in ipairs({ a, b }) do
		vim.fn.mkdir(directory .. "/.git", "p")
		write(directory .. "/package.json", { "{}" })
	end
	local nested = a .. "/packages/web"
	write(nested .. "/package.json", { "{}" })
	write(nested .. "/biome.json", { "{}" })
	write(nested .. "/.stylelintrc.json", { "{}" })
	local hoisted = executable(a .. "/node_modules/.bin/biome")
	local local_biome = executable(nested .. "/node_modules/.bin/biome", "1.2.3")
	local other_biome = executable(b .. "/node_modules/.bin/biome")
	local a_buffer = buffer(nested .. "/src/application.ts", "typescript")
	assert(tools.node_executable("biome", a_buffer) == local_biome, "Node lookup missed the nearest package")
	assert(
		tools.node_executable("biome", a_buffer, { prefer_mason = true }) == local_biome,
		"Mason preference overrode project Node tools"
	)
	assert(tools.node_executable("biome", a .. "/index.js") == hoisted, "Node lookup missed the hoisted workspace tool")
	local b_buffer = buffer(b .. "/application.js", "javascript")
	assert(tools.node_executable("biome", b_buffer) == other_biome, "Node cache leaked between projects")
	vim.fn.mkdir(a .. "/foreign/.git", "p")
	assert(
		tools.node_resolve("biome", a .. "/foreign/file.js").source ~= "project",
		"Node lookup crossed a repository boundary"
	)
	assert(vim.uv.fs_symlink(a, base .. "/linked-a"), "Could not create a symlink fixture")
	assert(
		tools.node_executable("biome", base .. "/linked-a/packages/web/src/application.ts") == local_biome,
		"Symlinked files selected another tool"
	)
	vim.fn.delete(local_biome)
	assert(tools.node_executable("biome", a_buffer) == hoisted, "Removed cached Node tool was still selected")
	executable(local_biome, "1.2.3")
	tools.reset()

	-- Standard Node LSP commands and the formatter/linter integrations share
	-- the same resolver, including package-local vtsls in a monorepo.
	local vtsls = executable(nested .. "/node_modules/.bin/vtsls")
	local original_rpc, rpc_commands = vim.lsp.rpc.start, {}
	vim.lsp.rpc.start = function(command)
		table.insert(rpc_commands, command)
		return command
	end
	vim.lsp.config.biome.cmd({}, { root_dir = nested })
	vim.lsp.config.vtsls.cmd({}, { root_dir = nested })
	vim.lsp.rpc.start = original_rpc
	assert(rpc_commands[1][1] == local_biome and rpc_commands[2][1] == vtsls, "Node LSPs selected different tools")
	local lsp_root
	vim.lsp.config.vtsls.root_dir(a_buffer, function(root)
		lsp_root = root
	end)
	assert(vim.wait(1000, function()
		return lsp_root ~= nil
	end, 20) and lsp_root == nested, "Package-local Node server kept the shared parent root")
	require("lazy").load({ plugins = { "conform.nvim" } })
	assert(
		require("conform").get_formatter_info("biome", a_buffer).command == local_biome,
		"Conform did not use the shared resolver"
	)
	local stylelint = executable(nested .. "/node_modules/.bin/stylelint")
	local css_buffer = buffer(nested .. "/src/site.css", "css")
	require("lazy").load({ plugins = { "nvim-lint" } })
	local lint, lint_command = require("lint"), nil
	local original_lint = lint.lint
	lint.lint = function(config)
		lint_command = config.cmd
		return { cancel = function() end }
	end
	vim.api.nvim_buf_set_lines(css_buffer, 0, -1, false, { "body {}" })
	vim.fn.maparg("<leader>cl", "n", false, true).callback()
	assert(lint_command == stylelint, "Lint did not use the shared resolver")
	vim.api.nvim_buf_delete(css_buffer, { force = true })
	lint.lint = original_lint

	write(a .. "/pyproject.toml", { "[project]", 'name = "a"' })
	write(b .. "/pyproject.toml", { "[project]", 'name = "b"' })
	local shared_python = executable(base .. "/shared/bin/python", "Python 3.12.1")
	local python_a = a .. "/.venv/bin/python"
	vim.fn.mkdir(vim.fs.dirname(python_a), "p")
	assert(vim.uv.fs_symlink(shared_python, python_a), "Could not create a venv interpreter symlink")
	local python_b = executable(b .. "/venv/bin/python", "Python 3.13.1")
	vim.env.VIRTUAL_ENV = base .. "/shared"
	local python_buffer = buffer(a .. "/main.py", "python")
	assert(tools.python_executable(python_buffer) == python_a, "VIRTUAL_ENV overrode the project .venv")
	assert(tools.python_executable(b .. "/main.py") == python_b, "Python lookup leaked between projects")
	local environment_two = executable(base .. "/other-env/bin/python", "Python 3.13.2")
	vim.env.VIRTUAL_ENV = base .. "/other-env"
	assert(
		tools.python_executable(base .. "/standalone.py") == environment_two,
		"Python lookup reused the previous VIRTUAL_ENV"
	)
	local host = executable(bin_b .. "/debugpy-adapter")
	tools.reset()
	assert(tools.debugpy_host().path == host, "debugpy did not find its independent host")
	require("lazy").load({ plugins = { "nvim-dap-python" } })
	local dap, adapter = require("dap"), nil
	dap.adapters.python(function(value)
		adapter = value
	end, { request = "launch" })
	assert(adapter.command == host and adapter.command ~= python_a, "Target interpreter was used as the debugpy host")
	local launch
	adapter.enrich_config(
		{ request = "launch", program = a .. "/main.py", envFile = base .. "/absent.env" },
		function(config)
			launch = config
		end
	)
	assert(launch.pythonPath == python_a, "DAP enrichment did not prefer the project venv")
	adapter.enrich_config(
		{ request = "launch", python = shared_python, program = a .. "/main.py", envFile = base .. "/absent.env" },
		function(config)
			launch = config
		end
	)
	assert(launch.python == shared_python and not launch.pythonPath, "DAP overrode an explicit interpreter")
	assert(
		dap.configurations.python[1].pythonPath() == python_a,
		"Default Python launch did not use the target resolver"
	)
	local configuration_count = #dap.configurations.python
	local next_host = executable(bin_a .. "/debugpy-adapter")
	vim.env.PATH = bin_a .. ":" .. old_path
	dap.adapters.python(function(value)
		adapter = value
	end, { request = "launch" })
	assert(adapter.command == next_host, "A later debug launch kept the old debugpy host after PATH changed")
	assert(
		#dap.configurations.python == configuration_count,
		"Refreshing the debugpy host duplicated launch configurations"
	)
	vim.env.PATH = bin_b .. ":" .. old_path

	do
		local original_registry, hooks, registrations = package.loaded["mason-registry"], {}, 0
		package.loaded["mason-registry"] = {
			on = function(_, event, callback)
				hooks[event] = callback
				registrations = registrations + 1
			end,
		}
		tools.watch_mason()
		tools.watch_mason()
		assert(registrations == 2, "Mason watchers were registered more than once")
		assert(tools.executable("registry-installed") == nil, "Registry fixture already exists")
		local installed = executable(bin_b .. "/registry-installed")
		hooks["package:install:success"]()
		assert(
			vim.wait(1000, function()
				return tools.executable("registry-installed") == installed
			end, 20),
			"Individual Mason install did not refresh the cache"
		)
		package.loaded["mason-registry"] = original_registry
		vim.lsp.enable(tools.lsp_servers, false)
	end

	-- Version probes only execute short local fixtures in this report test.
	do
		local messages, old_health, old_packages = {}, vim.health, tools.packages
		vim.health = setmetatable({}, {
			__index = function(_, level)
				return function(message)
					table.insert(messages, level .. ": " .. message)
				end
			end,
		})
		tools.packages = { { "biome", version = "1.2.3" }, { "audit-missing", version = "0.1" } }
		executable(bin_b .. "/fzf", "0.35.0")
		executable(bin_b .. "/fd", "fd 10.0.0")
		executable(bin_b .. "/python", "Python 3.12.1")
		executable(bin_b .. "/java", 'openjdk version "21.0.1"')
		vim.env.PATH, vim.env.JAVA_HOME = bin_b, nil
		vim.api.nvim_set_current_buf(a_buffer)
		tools.reset()
		require("user.health").check()
		vim.health, tools.packages = old_health, old_packages
		local report = table.concat(messages, "\n")
		assert(report:find("Workspace: " .. a, 1, true), "Health omitted the workspace root")
		assert(
			report:find(local_biome, 1, true) and report:find("selected version 1.2.3", 1, true),
			"Health omitted the project tool path/version"
		)
		assert(
			report:find("fzf needs version 0.36", 1, true) and report:find("rg is missing", 1, true),
			"Health missed required search dependencies"
		)
		assert(
			report:find("JDTLS Java:", 1, true)
				and report:find("Python target:", 1, true)
				and report:find("debugpy host:", 1, true),
			"Health did not distinguish runtime roles"
		)
		assert(report:find("audit-missing", 1, true), "Health omitted unavailable tools")
	end
	for _, bufnr in ipairs({ a_buffer, b_buffer, python_buffer }) do
		vim.api.nvim_buf_delete(bufnr, { force = true })
	end
	vim.fn.stdpath, preferences.get = old_stdpath, old_preferences
	vim.env.PATH, vim.env.VIRTUAL_ENV, vim.env.JAVA_HOME = old_path, old_venv, old_java
	tools.reset()
end
