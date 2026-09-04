return function(tmp)
	local root = assert(vim.env.NVIM_TEST_ROOT, "NVIM_TEST_ROOT is required")
	local helper = assert(loadfile(root .. "/scripts/workflows/python_js.lua"))()
	local deps = assert(
		vim.env.NVIM_WORKFLOW_PYTHON_JS_DEPS,
		"Prepare dependencies first: scripts/workflows/prepare-python-js.sh /tmp/nvim-python-js-deps [--allow-network]; then set NVIM_WORKFLOW_PYTHON_JS_DEPS"
	)
	assert(vim.fn.executable(deps .. "/python-env/bin/python") == 1, "Prepared Python environment is missing")
	for _, binary in ipairs({ "jest", "vitest", "tsc" }) do
		assert(
			vim.fn.executable(deps .. "/node_modules/.bin/" .. binary) == 1,
			"Prepared Node dependency is missing: " .. binary
		)
	end
	local locked =
		vim.json.decode(table.concat(vim.fn.readfile(root .. "/scripts/fixtures/python-js/package.json"), "\n"))
	for name, expected in pairs(locked.devDependencies) do
		local actual =
			vim.json.decode(table.concat(vim.fn.readfile(deps .. "/node_modules/" .. name .. "/package.json"), "\n"))
		assert(actual.version == expected, ("Prepared %s must be %s, found %s"):format(name, expected, actual.version))
	end
	local toolchain = require("user.toolchain")
	for _, command in ipairs({
		"basedpyright-langserver",
		"ruff",
		"vtsls",
		"vue-language-server",
		"js-debug-adapter",
		"prettier",
		"chromium",
	}) do
		assert(toolchain.executable(command), "Missing real-workflow dependency: " .. command)
	end
	assert(toolchain.debugpy_host().path, "Missing debugpy host")
	local project = tmp .. "/python-js"
	vim.fn.mkdir(project, "p")
	helper.command({ "cp", "-a", root .. "/scripts/fixtures/python-js/.", project })
	local python, jest, vitest, web = project .. "/python", project .. "/jest", project .. "/vitest", project .. "/web"
	helper.command({ "cp", "-a", deps .. "/python-env", python .. "/.venv" })
	for _, directory in ipairs({ jest, vitest, web }) do
		assert(vim.uv.fs_symlink(deps .. "/node_modules", directory .. "/node_modules"))
	end
	helper.command(
		{ python .. "/.venv/bin/python", "-c", "import pytest; assert pytest.__version__ == '9.1.0'" },
		python
	)
	require("lazy").load({ plugins = { "nvim-lspconfig" } })
	vim.lsp.enable(toolchain.lsp_servers, false)
	vim.lsp.enable({ "basedpyright", "ruff", "vtsls", "vue_ls" })
	helper.language(python .. "/main.py", python, "basedpyright", 'broken: int = "wrong"')
	helper.language(web .. "/main.ts", web, "vtsls", 'const broken: number = "wrong";')
	helper.language(web .. "/main.js", web, "vtsls", "const = ;")
	print("Python/JS workflow: Vue embedded TypeScript diagnostic")
	local vuebuf = helper.edit(web .. "/App.vue", web)
	helper.client(vuebuf, "vue_ls")
	helper.client(vuebuf, "vtsls")
	vim.api.nvim_buf_set_lines(vuebuf, 1, 2, false, { 'const count: number = "wrong";' })
	assert(
		vim.wait(60000, function()
			for _, diagnostic in ipairs(vim.diagnostic.get(vuebuf, { severity = vim.diagnostic.severity.ERROR })) do
				if diagnostic.lnum == 1 then
					return true
				end
			end
		end, 50),
		"Vue embedded TypeScript error was not reported: " .. vim.inspect(vim.diagnostic.get(vuebuf))
	)
	vim.bo[vuebuf].modified = false
	print("Python/JS workflow: Ruff project formatting on save")
	local formatbuf = helper.edit(python .. "/format.py", python)
	vim.cmd.write()
	local formatted = table.concat(vim.api.nvim_buf_get_lines(formatbuf, 0, -1, false), "\n")
	assert(formatted:find("message = 'project quote style wins'", 1, true), "Ruff did not use project quote-style")
	assert(formatted:find("values = [\n", 1, true), "Ruff did not use project line-length")
	print("Python/JS workflow: Prettier project formatting on save")
	local prettierbuf = helper.edit(web .. "/format.ts", web)
	vim.cmd.write()
	local prettier = table.concat(vim.api.nvim_buf_get_lines(prettierbuf, 0, -1, false), "\n")
	assert(
		prettier:find("const message = 'project prettier style wins'\n", 1, true),
		"Prettier ignored project quote/semi settings"
	)
	assert(prettier:find("const values = [\n", 1, true), "Prettier ignored project printWidth")
	-- Both environments are valid; the file-owned .venv must take precedence.
	vim.env.VIRTUAL_ENV = deps .. "/python-env"
	helper.neotest(python .. "/test_sample.py", python, "python")
	helper.neotest(jest .. "/sample.test.js", jest, "jest")
	helper.neotest(vitest .. "/sample.test.ts", vitest, "vitest")
	-- Re-enter Jest while the previous current project was Vitest.
	helper.neotest(jest .. "/sample.test.js", jest, "jest")
	helper.breakpoint(
		python .. "/main.py",
		python,
		{ type = "python", program = python .. "/main.py", justMyCode = false },
		"sys.prefix",
		python .. "/.venv"
	)
	helper.breakpoint(web .. "/main.js", web, { type = "pwa-node", program = web .. "/main.js", sourceMaps = true })
	helper.command({ deps .. "/node_modules/.bin/tsc", "--project", web .. "/tsconfig.json" }, web)
	helper.breakpoint(web .. "/main.ts", web, {
		type = "pwa-node",
		program = web .. "/dist/main.js",
		sourceMaps = true,
		pauseForSourceMap = true,
		outFiles = { web .. "/dist/**/*.js" },
	})
	print("Python/JS workflow: isolated Chromium attach")
	local browser_profile = tmp .. "/chromium-profile"
	vim.fn.mkdir(browser_profile, "p")
	local browser = vim.system({
		toolchain.executable("chromium"),
		"--headless",
		"--no-sandbox",
		"--disable-gpu",
		"--disable-dev-shm-usage",
		"--no-first-run",
		"--remote-debugging-port=0",
		"--user-data-dir=" .. browser_profile,
		"file://" .. web .. "/index.html",
	}, { text = true })
	local ok, err = xpcall(function()
		assert(
			vim.wait(15000, function()
				return vim.uv.fs_stat(browser_profile .. "/DevToolsActivePort") ~= nil
			end, 50),
			"Isolated Chromium did not publish its debugging port"
		)
		local port = assert(tonumber(vim.fn.readfile(browser_profile .. "/DevToolsActivePort")[1]))
		helper.breakpoint(web .. "/browser.js", web, {
			type = "pwa-chrome",
			request = "attach",
			port = port,
			webRoot = web,
			url = "file://" .. web .. "/index.html",
			sourceMaps = true,
		})
	end, debug.traceback)
	browser:kill(15)
	browser:wait(5000)
	assert(ok, err)
	for _, client in ipairs(vim.lsp.get_clients()) do
		client:stop(true)
	end
end
