return function(tmp)
	local base = vim.fs.joinpath(tmp, "languages")
	local function write(path, lines)
		vim.fn.mkdir(vim.fs.dirname(path), "p")
		vim.fn.writefile(lines, path)
	end
	local function buffer(path, filetype)
		local bufnr = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(bufnr, path)
		vim.api.nvim_set_current_buf(bufnr)
		vim.bo[bufnr].filetype = filetype
		return bufnr
	end
	local function wait_for(predicate, message)
		assert(vim.wait(5000, predicate, 25), message)
	end

	-- Keep these fixtures offline: test language behavior without launching
	-- unrelated servers or autoformatting files as a side effect of saving.
	require("lazy").load({ plugins = { "nvim-lspconfig" } })
	vim.lsp.enable(require("user.toolchain").lsp_servers, false)
	vim.g.disable_autoformat = true

	do
		local a, b = base .. "/jest", base .. "/vitest"
		write(a .. "/package.json", { '{"devDependencies":{"jest":"1"}}' })
		write(b .. "/package.json", { '{"devDependencies":{"vitest":"1"}}' })
		write(a .. "/basic.test.js", { 'test("ok", () => {});' })
		write(b .. "/basic.test.js", { 'test("ok", () => {});' })
		local previous_cwd = vim.fn.getcwd()
		vim.cmd.cd(a)
		local testing = require("user.core.testing")
		local a_buffer = buffer(a .. "/basic.test.js", "javascript")
		assert(testing.prepare(), "Jest project was not recognized")
		local jest = require("neotest.config").projects[a].adapters[1]
		assert(jest.name == "neotest-jest", "Jest project selected another framework")
		assert(jest.is_test_file(a .. "/basic.test.js"), "Jest missed its own test")
		assert(not package.loaded["neotest-vitest"], "Jest project eagerly loaded Vitest")

		vim.cmd.cd(b)
		local b_buffer = buffer(b .. "/basic.test.js", "javascript")
		assert(testing.prepare(), "Vitest project was not recognized after Jest")
		local vitest = require("neotest.config").projects[b].adapters[1]
		assert(vitest.name == "neotest-vitest", "Vitest project selected another framework")
		assert(vitest.is_test_file(b .. "/basic.test.js"), "Vitest missed its own test")
		assert(not jest.is_test_file(b .. "/basic.test.js"), "Jest claimed the other project's Vitest test")
		assert(not vitest.is_test_file(a .. "/basic.test.js"), "Vitest claimed the other project's Jest test")
		assert(not vitest.is_test_file(b .. "/application.js"), "Vitest treated ordinary source as a test")

		vim.api.nvim_set_current_buf(a_buffer)
		assert(testing.prepare() and jest.is_test_file(a .. "/basic.test.js"), "Returning to Jest lost its adapter")
		assert(#require("neotest.config").projects[a].adapters == 1, "Returning to a project duplicated its adapter")

		local mono = base .. "/monorepo"
		vim.fn.mkdir(mono .. "/.git", "p")
		write(mono .. "/package.json", { '{"devDependencies":{"jest":"1","vitest":"1"}}' })
		write(mono .. "/packages/unit/vitest.config.ts", { "export default {};" })
		write(mono .. "/packages/unit/package.json", { "{}" })
		write(mono .. "/packages/unit/unit.test.ts", { 'test("ok", () => {});' })
		local mono_buffer = buffer(mono .. "/packages/unit/unit.test.ts", "typescript")
		assert(testing.prepare(), "Package-local Vitest config did not override shared workspace dependencies")
		assert(vitest.is_test_file(mono .. "/packages/unit/unit.test.ts"), "Vitest missed the nested package")
		assert(not jest.is_test_file(mono .. "/packages/unit/unit.test.ts"), "Jest claimed the nested Vitest package")

		write(mono .. "/mixed.test.js", { 'test("ok", () => {});' })
		local mixed_buffer = buffer(mono .. "/mixed.test.js", "javascript")
		local notify, warning = vim.notify, nil
		vim.notify = function(message)
			warning = message
		end
		local ambiguous = testing.prepare()
		vim.notify = notify
		assert(not ambiguous and warning:match("TestAdapter"), "An ambiguous workspace silently chose a framework")
		vim.cmd("TestAdapter vitest")
		assert(testing.prepare(), "Explicit Vitest choice did not enable testing")
		assert(vitest.is_test_file(mono .. "/mixed.test.js"), "Explicit Vitest choice was ignored")
		assert(not jest.is_test_file(mono .. "/mixed.test.js"), "Jest ignored the explicit Vitest choice")
		vim.cmd("TestAdapter jest")
		assert(
			testing.prepare() and jest.is_test_file(mono .. "/mixed.test.js"),
			"Changing the explicit adapter failed"
		)
		assert(
			#require("neotest.config").projects[mono].adapters == 1,
			"Changing the framework retained the old adapter"
		)

		-- A nested repository without test dependencies must not inherit an
		-- unrelated parent project or the process working directory.
		vim.fn.mkdir(a .. "/foreign/.git", "p")
		write(a .. "/foreign/other.test.js", { 'test("ok", () => {});' })
		assert(
			not jest.is_test_file(a .. "/foreign/other.test.js"),
			"Test framework detection crossed a repository boundary"
		)
		local embedded = base .. "/embedded"
		write(embedded .. "/package.json", { '{"jest":{},"devDependencies":{"vitest":"1"}}' })
		assert(
			jest.is_test_file(embedded .. "/embedded.test.js"),
			"Embedded Jest configuration lost to an unrelated dependency"
		)
		write(embedded .. "/vitest.config.ts", { "export default {};" })
		vim.api.nvim_exec_autocmds("FocusGained", {})
		assert(
			not jest.is_test_file(embedded .. "/embedded.test.js"),
			"Conflicting embedded Jest and file Vitest configs were not recognized as ambiguous"
		)
		local scripted = base .. "/scripted"
		write(scripted .. "/package.json", { '{"scripts":{"test":"jest --runInBand"}}' })
		assert(jest.is_test_file(scripted .. "/scripted.test.js"), "A project test script did not identify Jest")
		vim.cmd.cd(previous_cwd)
		for _, bufnr in ipairs({ a_buffer, b_buffer, mono_buffer, mixed_buffer }) do
			vim.api.nvim_buf_delete(bufnr, { force = true })
		end
	end

	do
		assert(vim.fn.has("win32") == 0, "Java runtime fixtures currently require a POSIX shell")
		local java = require("user.core.java")
		local jdk21, jdk17 = base .. "/jdk21", base .. "/jdk17"
		for directory, version in pairs({ [jdk21] = 21, [jdk17] = 17 }) do
			write(
				directory .. "/bin/java",
				{ "#!/bin/sh", "printf 'openjdk version \"" .. version .. ".0.1\"\\n' >&2" }
			)
			vim.fn.setfperm(directory .. "/bin/java", "rwxr-xr-x")
		end
		local previous_path, previous_java_home = vim.env.PATH, vim.env.JAVA_HOME
		vim.env.PATH, vim.env.JAVA_HOME = jdk21 .. "/bin:" .. previous_path, jdk17
		assert(java.runtime() == jdk21 .. "/bin/java", "Old JAVA_HOME hid a valid PATH JDK")
		vim.env.PATH, vim.env.JAVA_HOME = jdk17 .. "/bin:" .. previous_path, jdk21
		assert(java.runtime() == jdk21 .. "/bin/java", "Old PATH JDK hid a valid JAVA_HOME")
		vim.env.PATH, vim.env.JAVA_HOME = jdk17 .. "/bin", jdk17
		assert(java.runtime() == nil, "Java 17 passed the JDTLS preflight")
		vim.env.PATH, vim.env.JAVA_HOME = base .. "/missing", nil
		assert(java.runtime() == nil, "Missing Java passed the JDTLS preflight")

		vim.env.PATH, vim.env.JAVA_HOME = jdk21 .. "/bin:" .. previous_path, jdk17
		require("lazy").load({ plugins = { "nvim-jdtls" } })
		local jdtls = require("jdtls")
		local toolchain = require("user.toolchain")
		local original_start, original_executable = jdtls.start_or_attach, toolchain.executable
		local captured
		jdtls.start_or_attach = function(config)
			captured = config
		end
		toolchain.executable = function(name, opts)
			return name == "jdtls" and base .. "/jdtls-launcher" or original_executable(name, opts)
		end
		-- Keep JDTLS's workspace allocation inside the fixture as well.
		local original_workspace = java.workspace_dir
		java.workspace_dir = function()
			return base .. "/java-workspace"
		end
		local java_buffer = buffer(base .. "/Main.java", "java")
		assert(captured, "Java FileType did not create a launch configuration")
		local index = vim.fn.index(captured.cmd, "--java-executable")
		assert(
			index >= 0 and captured.cmd[index + 2] == jdk21 .. "/bin/java",
			"JDTLS did not receive the exact validated Java runtime"
		)
		jdtls.start_or_attach, toolchain.executable, java.workspace_dir =
			original_start, original_executable, original_workspace
		vim.env.PATH, vim.env.JAVA_HOME = previous_path, previous_java_home
		vim.api.nvim_buf_delete(java_buffer, { force = true })
	end

	do
		local path = base .. "/shell/check.sh"
		write(path, { "#!/bin/bash", 'name="some value"', "echo $name" })
		vim.cmd.edit(path)
		local bufnr = vim.api.nvim_get_current_buf()
		local lint = require("lint")
		assert(require("user.toolchain").executable("shellcheck"), "ShellCheck is required for the language checks")
		local namespace = lint.get_namespace("shellcheck")
		local function diagnostics()
			return vim.diagnostic.get(bufnr, { namespace = namespace })
		end
		wait_for(function()
			return #diagnostics() > 0
		end, "ShellCheck did not diagnose the fixture on disk")
		vim.api.nvim_buf_set_lines(bufnr, 2, 3, false, { 'echo "$name"' })
		vim.api.nvim_exec_autocmds("InsertLeave", { buffer = bufnr })
		wait_for(function()
			return #diagnostics() == 0
		end, "ShellCheck retained disk diagnostics for an edited buffer")
		vim.wait(600, function()
			return false
		end)
		assert(#diagnostics() == 0, "ShellCheck republished disk diagnostics for the unsaved buffer")
		vim.cmd("silent write")
		vim.wait(400, function()
			return false
		end)
		assert(#diagnostics() == 0, "Saving the corrected shell script restored an old diagnostic")
		vim.api.nvim_buf_set_lines(bufnr, 2, 3, false, { "echo $name" })
		vim.cmd("silent write")
		wait_for(function()
			return #diagnostics() > 0
		end, "ShellCheck stopped checking saved files")
		write(base .. "/shell/library.sh", { 'name="from library"' })
		write(base .. "/shell/.shellcheckrc", { "external-sources=true" })
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
			"#!/bin/bash",
			"# shellcheck source-path=SCRIPTDIR",
			"# shellcheck source=library.sh",
			". ./library.sh",
			'echo "$name"',
		})
		vim.cmd("silent write")
		wait_for(function()
			return #diagnostics() == 0
		end, "ShellCheck lost source-path/SCRIPTDIR resolution")
		vim.api.nvim_buf_delete(bufnr, { force = true })
	end

	do
		require("lazy").load({ plugins = { "conform.nvim" } })
		local conform = require("conform")
		local ruff = assert(require("user.toolchain").executable("ruff"), "Ruff is required for the language checks")
		local source =
			"result = some_function(first_argument, second_argument, third_argument, fourth_argument, fifth_argument)"
		local outputs = {}
		for _, length in ipairs({ 88, 120 }) do
			local directory = base .. "/python" .. length
			write(directory .. "/pyproject.toml", { "[tool.ruff]", "line-length = " .. length })
			local filename = directory .. "/sample.py"
			local bufnr = buffer(filename, "python")
			local err, formatted = conform.format_lines(
				{ "ruff_format" },
				{ source },
				{ bufnr = bufnr, timeout_ms = 5000, quiet = true }
			)
			assert(not err and formatted, "Ruff formatting failed: " .. tostring(err))
			local result = vim.system(
				{ ruff, "format", "--stdin-filename", filename, "-" },
				{ text = true, stdin = source .. "\n" }
			):wait(5000)
			assert(result.code == 0, "Project Ruff command failed: " .. (result.stderr or ""))
			outputs[length] = table.concat(formatted, "\n") .. "\n"
			assert(
				outputs[length] == result.stdout,
				"Editor formatting overrode the project's Ruff line length " .. length
			)
			vim.api.nvim_buf_delete(bufnr, { force = true })
		end
		assert(outputs[88] ~= outputs[120], "Ruff fixtures did not exercise differing project line lengths")
		local settings = (vim.lsp.config.ruff.init_options or {}).settings or {}
		assert(settings.lineLength == nil, "Ruff LSP still overrides the project's line length")
	end
	vim.g.disable_autoformat = nil
end
