return function(tmp)
	local root = assert(vim.env.NVIM_TEST_ROOT, "NVIM_TEST_ROOT is required")
	local deps = assert(
		vim.env.NVIM_JAVA_WORKFLOW_DEPS,
		"Prepare dependencies with scripts/workflows/prepare-java-docs.sh, then set NVIM_JAVA_WORKFLOW_DEPS"
	)
	local fixtures = root .. "/scripts/fixtures/java-docs"
	local base = tmp .. "/java-docs"
	vim.fn.mkdir(base, "p")
	assert(
		vim.fn.system({ "cp", "-R", fixtures .. "/.", base }) == "" and vim.v.shell_error == 0,
		"Could not copy workflow fixtures"
	)
	local function write(path, lines)
		vim.fn.mkdir(vim.fs.dirname(path), "p")
		vim.fn.writefile(lines, path)
	end
	local function wait_for(predicate, message, timeout)
		assert(vim.wait(timeout or 30000, predicate, 25), message)
	end
	local function run(command, cwd, expected)
		local result = vim.system(command, { cwd = cwd, text = true }):wait(60000)
		assert(
			result.code == (expected or 0),
			vim.inspect(command) .. "\n" .. (result.stdout or "") .. (result.stderr or "")
		)
		return result
	end
	local stdpath = vim.fn.stdpath
	local original_data = stdpath("data")
	vim.fn.mkdir(base .. "/data", "p")
	if vim.env.NVIM_JAVA_TEST_BUNDLES then
		vim.fn.mkdir(base .. "/data/mason/share", "p")
		for _, directory in ipairs({ "bin", "packages" }) do
			assert(vim.uv.fs_symlink(original_data .. "/mason/" .. directory, base .. "/data/mason/" .. directory))
		end
		for _, directory in ipairs(vim.fn.readdir(original_data .. "/mason/share")) do
			local target = directory == "java-test" and vim.env.NVIM_JAVA_TEST_BUNDLES
				or original_data .. "/mason/share/" .. directory
			assert(vim.uv.fs_symlink(target, base .. "/data/mason/share/" .. directory))
		end
		print("Java workflow: using isolated test bundles " .. vim.env.NVIM_JAVA_TEST_BUNDLES)
	else
		assert(vim.uv.fs_symlink(original_data .. "/mason", base .. "/data/mason"))
	end
	vim.fn.stdpath = function(kind)
		return kind == "data" and base .. "/data" or stdpath(kind)
	end
	local original_java_options, original_gradle_home = vim.env.JAVA_TOOL_OPTIONS, vim.env.GRADLE_USER_HOME
	vim.env.JAVA_TOOL_OPTIONS = "-Duser.home=" .. base .. "/java-home -Dmaven.repo.local=" .. deps .. "/repository"
	vim.env.GRADLE_USER_HOME = base .. "/gradle-cache"
	write(base .. "/java-home/.m2/settings.xml", {
		"<settings><localRepository>" .. deps .. "/repository</localRepository><offline>true</offline></settings>",
	})
	require("lazy").load({ plugins = { "nvim-lspconfig" } })
	vim.lsp.enable(require("user.toolchain").lsp_servers, false)
	vim.g.disable_autoformat = true
	local java = require("user.core.java")
	java.clear_runtime_cache()
	local runtime, major = java.runtime()
	assert(runtime and major >= 21, "A real JDK 21 or newer is required")
	local maven = base .. "/maven"
	local source = maven .. "/src/main/java/sample/Calculator.java"
	assert(java.project_root(source) == maven, "Maven root was not selected")
	assert(
		java.project_root(base .. "/gradle/src/main/java/App.java") == base .. "/gradle",
		"Gradle root was not selected"
	)
	vim.fn.mkdir(maven .. "/foreign/.git", "p")
	assert(
		java.project_root(maven .. "/foreign/New.java") == maven .. "/foreign",
		"Java imported an outer build across a repository boundary"
	)
	assert(vim.uv.fs_symlink(maven, base .. "/maven-alias"))
	assert(
		java.workspace_dir(maven) == java.workspace_dir(base .. "/maven-alias"),
		"Symlinked Java projects used separate indexes"
	)
	run({
		"mvn",
		"--batch-mode",
		"--no-transfer-progress",
		"--offline",
		"-Dmaven.repo.local=" .. deps .. "/repository",
		"test-compile",
	}, maven)
	local compiled_class = assert(vim.uv.fs_open(maven .. "/target/classes/sample/Calculator.class", "r", 0))
	local class_header = vim.uv.fs_read(compiled_class, 8, 0)
	vim.uv.fs_close(compiled_class)
	assert(class_header:byte(7) * 256 + class_header:byte(8) == 61, "Maven ignored the Java 17 bytecode target")
	print("Java workflow: Maven compiled main and test sources for Java 17")
	run({ "gradle", "--offline", "--no-daemon", "--console=plain", "classes" }, base .. "/gradle")
	assert(
		vim.uv.fs_stat(base .. "/gradle/build/classes/java/main/sample/GradleMain.class"),
		"Gradle did not compile the Java fixture"
	)
	print("Java workflow: actual Gradle Java compilation passed")
	require("user.core.project").set(maven)
	vim.cmd.edit(source)
	local main_buffer = vim.api.nvim_get_current_buf()
	local client
	wait_for(function()
		client = vim.lsp.get_clients({ bufnr = main_buffer, name = "jdtls" })[1]
		return client and client.initialized
	end, "JDTLS did not initialize; inspect " .. stdpath("log") .. "/lsp.log", 60000)
	print("Java workflow: JDTLS initialized with " .. runtime)
	local symbols = client:request_sync(
		"textDocument/documentSymbol",
		{ textDocument = { uri = vim.uri_from_bufnr(main_buffer) } },
		30000,
		main_buffer
	)
	assert(symbols and not symbols.err and #symbols.result > 0, "JDTLS did not return real document symbols")
	local settings = client:request_sync("workspace/executeCommand", {
		command = "java.project.getSettings",
		arguments = { vim.uri_from_bufnr(main_buffer), { "org.eclipse.jdt.core.compiler.compliance" } },
	}, 30000, main_buffer)
	assert(
		settings and not settings.err and settings.result["org.eclipse.jdt.core.compiler.compliance"] == "17",
		"JDTLS ignored the project's Java 17 compliance level: " .. vim.inspect(settings)
	)
	local original_lines = vim.api.nvim_buf_get_lines(main_buffer, 0, -1, false)
	local definition = client:request_sync("textDocument/definition", {
		textDocument = { uri = vim.uri_from_bufnr(main_buffer) },
		position = { line = 9, character = assert(original_lines[10]:find("add", 1, true)) - 1 },
	}, 30000, main_buffer)
	local location = definition and definition.result and definition.result[1]
	assert(
		location
			and (location.targetUri or location.uri) == vim.uri_from_bufnr(main_buffer)
			and (location.targetSelectionRange or location.range).start.line == 3,
		"Java definition jumped to the wrong file or method"
	)
	vim.api.nvim_buf_set_lines(
		main_buffer,
		#original_lines - 1,
		#original_lines - 1,
		false,
		{ '    private int invalid = "wrong type";' }
	)
	wait_for(function()
		return #vim.diagnostic.get(main_buffer, { severity = vim.diagnostic.severity.ERROR }) > 0
	end, "JDTLS did not publish the unsaved Java type error")
	vim.api.nvim_buf_set_lines(main_buffer, 0, -1, false, original_lines)
	vim.bo[main_buffer].modified = false
	wait_for(function()
		return #vim.diagnostic.get(main_buffer, { severity = vim.diagnostic.severity.ERROR }) == 0
	end, "JDTLS did not clear the repaired in-memory error")
	assert(
		java.supports_command(main_buffer, { "vscode.java.startDebugSession" }),
		"JDTLS did not load the actual debug capability"
	)
	assert(
		java.supports_command(
			main_buffer,
			{ "vscode.java.test.search.codelens", "vscode.java.test.findTestTypesAndMethods" }
		),
		"JDTLS did not load a compatible test extension"
	)
	print("Java workflow: project compliance, definition, unsaved diagnostic and recovery passed")
	require("lazy").load({ plugins = { "nvim-dap" } })
	local jdtls, dap = require("jdtls"), require("dap")
	jdtls.setup_dap({ hotcodereplace = "auto" })
	local junit_file = maven .. "/src/test/java/sample/CalculatorJUnitTest.java"
	vim.cmd.edit(junit_file)
	local junit_buffer = vim.api.nvim_get_current_buf()
	wait_for(function()
		return vim.lsp.buf_is_attached(junit_buffer, client.id)
	end, "JDTLS did not attach to the JUnit file")
	for _, test in ipairs({ { line = 9, failed = false }, { line = 14, failed = true } }) do
		vim.api.nvim_set_current_buf(junit_buffer)
		local done, results
		jdtls.test_nearest_method({
			bufnr = junit_buffer,
			lnum = test.line,
			config_overrides = { noDebug = true, console = "internalConsole" },
			after_test = function(_, tests)
				results, done = tests, true
			end,
		})
		wait_for(function()
			return done
		end, "JUnit test did not finish", 45000)
		assert(
			results and #results == 1 and results[1].failed == test.failed,
			"JUnit result did not match the real assertion: " .. vim.inspect(results)
		)
		print("Java workflow: JUnit " .. (test.failed and "failure" or "success") .. " reported")
	end
	local testng_file = maven .. "/src/test/java/sample/CalculatorTestNGTest.java"
	vim.cmd.edit(testng_file)
	local testng_buffer = vim.api.nvim_get_current_buf()
	wait_for(function()
		return vim.lsp.buf_is_attached(testng_buffer, client.id)
	end, "JDTLS did not attach to the TestNG file")
	local testng_namespace = vim.api.nvim_create_namespace("testng")
	for _, test in ipairs({ { line = 9, failed = false }, { line = 14, failed = true } }) do
		vim.api.nvim_set_current_buf(testng_buffer)
		local done
		jdtls.test_nearest_method({
			bufnr = testng_buffer,
			lnum = test.line,
			config_overrides = { noDebug = true, console = "internalConsole" },
			after_test = function()
				done = true
			end,
		})
		wait_for(function()
			return done
		end, "TestNG test did not finish", 45000)
		local failures = vim.diagnostic.get(testng_buffer, { namespace = testng_namespace })
		local marks = vim.api.nvim_buf_get_extmarks(testng_buffer, testng_namespace, 0, -1, {})
		assert(
			test.failed and #failures == 1 or not test.failed and #failures == 0 and #marks > 0,
			"TestNG did not report the actual test outcome"
		)
		print("Java workflow: TestNG " .. (test.failed and "failure" or "success") .. " reported")
	end
	vim.api.nvim_set_current_buf(main_buffer)
	vim.api.nvim_win_set_cursor(0, { 5, 0 })
	dap.set_breakpoint()
	local configs
	require("jdtls.dap").fetch_main_configs({ config_overrides = { console = "internalConsole" } }, function(value)
		configs = value
	end)
	wait_for(function()
		return configs ~= nil
	end, "Java main-class discovery did not finish")
	assert(#configs > 0, "JDTLS did not discover Calculator.main")
	local stopped, terminated
	dap.listeners.after.event_stopped.java_workflow = function(_, body)
		stopped = body
	end
	dap.listeners.after.event_terminated.java_workflow = function()
		terminated = true
	end
	dap.run(configs[1])
	wait_for(function()
		return stopped ~= nil and dap.session() and dap.session().current_frame ~= nil
	end, "Java never hit the actual breakpoint", 45000)
	assert(stopped.reason == "breakpoint", "Java stopped for another reason: " .. vim.inspect(stopped))
	assert(dap.session().current_frame.line == 5, "Java stopped at another source line")
	print("Java workflow: real breakpoint hit")
	dap.continue()
	wait_for(function()
		return terminated
	end, "Java debug program did not terminate")
	dap.listeners.after.event_stopped.java_workflow = nil
	dap.listeners.after.event_terminated.java_workflow = nil
	client:stop()
	wait_for(function()
		return vim.lsp.get_client_by_id(client.id) == nil
	end, "JDTLS process did not exit before temporary-directory cleanup")
	dofile(root .. "/scripts/workflows/java-documents.lua")(base)
	vim.fn.stdpath = stdpath
	vim.env.JAVA_TOOL_OPTIONS, vim.env.GRADLE_USER_HOME = original_java_options, original_gradle_home
end
