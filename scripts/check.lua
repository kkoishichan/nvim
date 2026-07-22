local tmp = assert(vim.env.NVIM_TEST_TMP, "NVIM_TEST_TMP is required")

assert(require("user.core.theme").saved() == "catppuccin", "default theme is not catppuccin")
assert(vim.startswith(vim.g.colors_name or "", "catppuccin"), "catppuccin was not applied at startup")
assert(vim.o.shada:match("<0"), "ShaDa still persists register contents")
assert(vim.g.user_lsp_preview_patched == nil, "LSP floating-preview API was monkeypatched")

do
	local plugins = require("lazy.core.config").plugins
	local edgy = plugins["edgy.nvim"]
	local codex
	for _, panel in ipairs(edgy.opts.right) do
		if panel.title == "Codex" then
			codex = panel
			break
		end
	end
	assert(codex and codex.ft == "toggleterm", "Codex is not docked as a toggleterm panel")

	local indicator = plugins["bufferline.nvim"].opts.options.diagnostics_indicator
	assert(indicator(0, 0, { info = 2 }):match("2"), "Bufferline hides info-only diagnostics")
	assert(indicator(0, 0, { hint = 3 }):match("3"), "Bufferline hides hint-only diagnostics")

	local conform = plugins["conform.nvim"].opts
	assert(vim.deep_equal(conform.formatters_by_ft.cs, { "csharpier" }), "C# formatter is missing")
	assert(vim.deep_equal(conform.formatters_by_ft.kotlin, { "ktlint" }), "Kotlin formatter is missing")
	assert(plugins["neotest-vstest"], "C# test plugin is missing")
	assert(plugins["neotest-kotlin"], "Kotlin test plugin is missing")
end

assert(vim.treesitter.language.add("c_sharp"), "C# Tree-sitter parser is missing")
assert(vim.treesitter.language.add("kotlin"), "Kotlin Tree-sitter parser is missing")

local sensitive = require("user.core.sensitive")
assert(sensitive.is_sensitive("/tmp/.env.production"), "environment file was not marked sensitive")
assert(not sensitive.is_sensitive("/tmp/.env.production.example"), "environment template was marked sensitive")
assert(not sensitive.is_sensitive("/tmp/credentials.sample"), "credential template was marked sensitive")
assert(not sensitive.is_sensitive("/tmp/password_policy.md"), "ordinary password-named document was marked sensitive")

do
	local notify = vim.notify
	vim.o.clipboard = ""
	vim.notify = function() end
	local buffer = vim.api.nvim_create_buf(false, false)
	local path = tmp .. "/.env.production"
	vim.api.nvim_buf_set_name(buffer, path)
	vim.api.nvim_exec_autocmds("BufNewFile", { buffer = buffer })
	assert(vim.b[buffer].user_sensitive, "sensitive buffer flag was not set")
	assert(not vim.bo[buffer].undofile, "sensitive buffer retained persistent undo")
	assert(not vim.bo[buffer].swapfile, "sensitive buffer retained a swap file")

	vim.api.nvim_set_current_buf(buffer)
	vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "TOKEN=secret" })
	vim.g.user_sensitive_clipboard_timeout_ms = 20
	vim.cmd("silent normal! yy")
	assert(
		vim.wait(200, function()
			return vim.fn.getreg('"') == ""
		end),
		"sensitive register did not expire"
	)

	vim.fn.setreg('"', "keep")
	vim.cmd([[silent normal! "_yy]])
	vim.wait(60)
	assert(vim.fn.getreg('"') == "keep", "black-hole yank cleared an unrelated register")
	vim.g.user_sensitive_clipboard_timeout_ms = nil
	vim.notify = notify
	vim.api.nvim_buf_delete(buffer, { force = true })
end

do
	local seen = {}
	local toolchain = require("user.toolchain")
	for _, package in ipairs(toolchain.packages) do
		assert(package.version and not seen[package[1]], "invalid or duplicate tool pin: " .. package[1])
		seen[package[1]] = true
	end
	for name, version in pairs({
		["csharpier"] = "1.2.6",
		["kotlin-debug-adapter"] = "0.4.4",
		["kotlin-lsp"] = "kotlin-lsp/v262.8190.0",
		["ktlint"] = "1.8.0",
		["netcoredbg"] = "3.1.3-1062",
		["roslyn-language-server"] = "5.8.0-1.26266.2",
	}) do
		assert(toolchain.version(name) == version, "missing or stale tool pin: " .. name)
	end
	assert(vim.tbl_contains(toolchain.lsp_servers, "roslyn_ls"), "C# LSP is not registered")
	assert(vim.tbl_contains(toolchain.lsp_servers, "kotlin_lsp"), "Kotlin LSP is not registered")
	assert(not vim.tbl_contains(toolchain.lsp_servers, "kotlin_language_server"), "legacy Kotlin LSP is enabled")
end

do
	local base = tmp .. "/root/project"
	vim.fn.mkdir(base .. "/module/src", "p")
	vim.fn.mkdir(base .. "/.git", "p")
	vim.fn.writefile({}, base .. "/module/pom.xml")
	assert(
		require("user.core.java").project_root(base .. "/module/src/Main.java") == base .. "/module",
		"nested Java root was ignored"
	)
end

do
	local lazy = require("lazy")
	local before = vim.env.PATH
	lazy.load({ plugins = { "nvim-lspconfig" } })
	assert(vim.env.PATH == before, "LSP changed PATH")
	assert(not package.loaded.mason and not package.loaded["mason-registry"], "ordinary LSP load started Mason")
	assert(vim.fn.exists(":MasonCSharpInstall") == 2, "MasonCSharpInstall command is missing")
	assert(vim.fn.exists(":MasonJavaInstall") == 2, "MasonJavaInstall command is missing")
	assert(vim.fn.exists(":MasonKotlinInstall") == 2, "MasonKotlinInstall command is missing")
	assert(vim.tbl_contains(vim.lsp.config.roslyn_ls.filetypes, "cs"), "Roslyn is not configured for C#")
	assert(vim.tbl_contains(vim.lsp.config.kotlin_lsp.filetypes, "kotlin"), "Kotlin LSP filetype is missing")

	local vue = require("user.toolchain").executable("vue-language-server")
	if vue then
		local plugins = vim.lsp.config.vtsls.settings.vtsls.tsserver.globalPlugins
		assert(
			plugins and vim.uv.fs_stat(plugins[1].location .. "/package.json"),
			"vtsls has an invalid Vue plugin path"
		)
	end

	lazy.load({ plugins = { "nvim-jdtls" } })
	assert(not package.loaded.dap, "nvim-dap loaded before Java debugging")

	lazy.load({ plugins = { "rustaceanvim" } })
	assert(vim.g.rustaceanvim.dap.autoload_configurations == false, "Rust DAP still autoloads on LSP attach")
	assert(not package.loaded.dap, "nvim-dap loaded before Rust debugging")
	local codelldb = require("user.toolchain").executable("codelldb")
	if codelldb then
		assert(
			vim.g.rustaceanvim.dap.adapter().executable.command == codelldb,
			"Rust DAP did not resolve codelldb by absolute path"
		)
	end
	vim.lsp.enable(require("user.toolchain").lsp_servers, false)
end

do
	require("lazy").load({ plugins = { "nvim-dap" } })
	local dap = require("dap")
	assert(type(dap.adapters.netcoredbg) == "function", "netcoredbg adapter is missing")
	assert(type(dap.adapters.kotlin) == "function", "Kotlin debug adapter is missing")
	assert(#(dap.configurations.cs or {}) >= 2, "C# launch/attach configurations are missing")
	assert(#(dap.configurations.kotlin or {}) >= 2, "Kotlin launch/attach configurations are missing")
end

do
	require("lazy").load({ plugins = { "nvim-lint" } })
	assert(vim.deep_equal(require("lint").linters_by_ft.kotlin, { "ktlint" }), "Kotlin linter is missing")
end

do
	local base = tmp .. "/tests"
	vim.fn.mkdir(base .. "/python", "p")
	vim.fn.writefile({}, base .. "/python/pyproject.toml")
	vim.fn.writefile({ "def test_ok():", "    assert True" }, base .. "/python/test_ok.py")
	vim.fn.mkdir(base .. "/go", "p")
	vim.fn.writefile({ "module example.test", "", "go 1.24" }, base .. "/go/go.mod")
	vim.fn.writefile({ "package example" }, base .. "/go/example_test.go")
	vim.fn.mkdir(base .. "/csharp", "p")
	vim.fn.writefile({ '<Project Sdk="Microsoft.NET.Sdk">', "</Project>" }, base .. "/csharp/example.csproj")
	vim.fn.writefile(
		{ "public class ExampleTests {", "  [Fact] public void Works() {}", "}" },
		base .. "/csharp/ExampleTests.cs"
	)
	vim.fn.mkdir(base .. "/kotlin/src/test/kotlin", "p")
	vim.fn.writefile({}, base .. "/kotlin/gradlew")
	vim.fn.writefile({
		"package example",
		"import io.kotest.core.spec.style.StringSpec",
		"class ExampleSpec : StringSpec({",
		'  "works" { }',
		"})",
	}, base .. "/kotlin/src/test/kotlin/ExampleSpec.kt")

	require("lazy").load({ plugins = { "neotest" } })
	local testing = require("user.core.testing")
	local function run_async(callback)
		local done, success, result, traceback
		require("nio").run(callback, function(ok, value, trace)
			success, result, traceback = ok, value, trace
			done = true
		end)
		assert(
			vim.wait(5000, function()
				return done
			end),
			"test discovery timed out"
		)
		assert(success, ("test discovery failed: %s\n%s"):format(result, traceback or ""))
		return result
	end
	local python_buffer = vim.api.nvim_create_buf(false, false)
	vim.api.nvim_buf_set_name(python_buffer, base .. "/python/test_ok.py")
	vim.api.nvim_set_current_buf(python_buffer)
	vim.bo[python_buffer].filetype = "python"
	assert(testing.prepare(), "Python test adapter unavailable")
	local consumer = require("neotest").run

	local go_buffer = vim.api.nvim_create_buf(false, false)
	vim.api.nvim_buf_set_name(go_buffer, base .. "/go/example_test.go")
	vim.api.nvim_set_current_buf(go_buffer)
	vim.bo[go_buffer].filetype = "go"
	assert(testing.prepare(), "Go test adapter unavailable")
	assert(require("neotest").run == consumer, "Neotest client was replaced while adding an adapter")
	assert(not package.loaded["neotest-jest"], "unrelated test adapter was loaded")

	local csharp_buffer = vim.api.nvim_create_buf(false, false)
	vim.api.nvim_buf_set_name(csharp_buffer, base .. "/csharp/ExampleTests.cs")
	vim.api.nvim_set_current_buf(csharp_buffer)
	vim.bo[csharp_buffer].filetype = "cs"
	assert(testing.prepare(), "C# test adapter unavailable")
	assert(require("neotest-vstest").name == "neotest-vstest", "unexpected C# test adapter")

	local kotlin_buffer = vim.api.nvim_create_buf(false, false)
	vim.api.nvim_buf_set_name(kotlin_buffer, base .. "/kotlin/src/test/kotlin/ExampleSpec.kt")
	vim.api.nvim_set_current_buf(kotlin_buffer)
	vim.bo[kotlin_buffer].filetype = "kotlin"
	assert(testing.prepare(), "Kotlin test adapter unavailable")
	assert(require("neotest-kotlin").name == "neotest-kotest", "unexpected Kotlin test adapter")
	local kotlin_positions = run_async(function()
		return require("neotest-kotlin").discover_positions(base .. "/kotlin/src/test/kotlin/ExampleSpec.kt")
	end)
	assert(kotlin_positions and #kotlin_positions:to_list() > 1, "Kotlin tests were not discovered")
	assert(not package.loaded["neotest-vitest"], "unrelated test adapter was loaded")
	vim.api.nvim_buf_delete(kotlin_buffer, { force = true })
	vim.api.nvim_buf_delete(csharp_buffer, { force = true })
	vim.api.nvim_buf_delete(go_buffer, { force = true })
	vim.api.nvim_buf_delete(python_buffer, { force = true })
end

do
	local buffer = vim.api.nvim_create_buf(false, false)
	vim.api.nvim_set_current_buf(buffer)
	vim.api.nvim_buf_set_lines(buffer, 0, -1, false, {
		"<<<<<<< HEAD",
		"ours",
		"=======",
		"theirs",
		">>>>>>> branch",
	})
	vim.api.nvim_exec_autocmds("BufReadPost", { buffer = buffer })
	assert(
		vim.wait(200, function()
			return vim.b[buffer].user_has_conflicts == true
		end),
		"conflict highlighting did not activate"
	)
	assert(not vim.diagnostic.is_enabled({ bufnr = buffer }), "conflict diagnostics were not disabled")

	vim.api.nvim_win_set_cursor(0, { 2, 0 })
	vim.cmd.GitConflictChooseBoth()
	assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), { "ours", "theirs" }))
	assert(
		vim.wait(200, function()
			return vim.b[buffer].user_has_conflicts == false
		end),
		"conflict highlighting did not clear"
	)
	assert(vim.diagnostic.is_enabled({ bufnr = buffer }), "conflict diagnostics were not restored")
	vim.api.nvim_buf_delete(buffer, { force = true })
end

do
	local buffer = vim.api.nvim_create_buf(false, false)
	vim.api.nvim_set_current_buf(buffer)
	vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "intro", "", "Setext heading", "=====", "# ATX" })
	vim.bo[buffer].filetype = "markdown"
	vim.v.errmsg = ""
	vim.api.nvim_exec_autocmds("FileType", { buffer = buffer })
	vim.api.nvim_exec_autocmds("FileType", { buffer = buffer })
	assert(not vim.v.errmsg:match("E31"), "Markdown FileType replay left stale mappings")

	local callback
	for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(buffer, "x")) do
		if mapping.lhs == "]]" then
			callback = mapping.callback
			break
		end
	end
	assert(type(callback) == "function", "Markdown visual heading motion is missing")
	vim.api.nvim_win_set_cursor(0, { 1, 0 })
	vim.cmd.normal({ "V", bang = true })
	callback()
	assert(vim.api.nvim_win_get_cursor(0)[1] == 3, "Markdown motion skipped a Setext heading")
	vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
	vim.api.nvim_buf_delete(buffer, { force = true })
end

print("Neovim integration checks passed.")
