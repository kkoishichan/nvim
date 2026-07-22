local java_core = require("user.core.java")
local toolchain = require("user.toolchain")

local function java_bundles()
	local share = vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "share")
	local bundles = {}
	local seen = {}
	local function append(jar)
		local realpath = vim.uv.fs_realpath(jar) or jar
		if seen[realpath] then
			return false
		end
		seen[realpath] = true
		table.insert(bundles, jar)
		return true
	end

	local debug_bundle = vim.fs.joinpath(share, "java-debug-adapter", "com.microsoft.java.debug.plugin.jar")
	local has_debug = vim.uv.fs_stat(debug_bundle) ~= nil
	if has_debug then
		append(debug_bundle)
	end
	local excluded = {
		["com.microsoft.java.test.runner-jar-with-dependencies.jar"] = true,
		["jacocoagent.jar"] = true,
	}
	local has_test = false

	for _, jar in ipairs(vim.fn.glob(vim.fs.joinpath(share, "java-test", "*.jar"), false, true)) do
		if not excluded[vim.fn.fnamemodify(jar, ":t")] and append(jar) then
			has_test = true
		end
	end

	return bundles, has_debug, has_test
end

local function install_hint(feature, packages)
	vim.notify(
		("Java %s requires Mason package(s): %s.\nRun :MasonToolsInstall or install them from :Mason, then restart Neovim."):format(
			feature,
			table.concat(packages, ", ")
		),
		vim.log.levels.WARN,
		{ title = "Java" }
	)
end

local function setup_java_keys(bufnr, jdtls, has_debug, has_test)
	local function map(mode, lhs, rhs, desc)
		vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, desc = desc, silent = true })
	end
	local function ensure_dap(feature)
		if not has_debug then
			install_hint(feature or "debugging", { "java-debug-adapter" })
			return nil
		end
		require("lazy").load({ plugins = { "nvim-dap" } })
		local ok, dap = pcall(require, "dap")
		if not ok then
			vim.notify("nvim-dap is unavailable", vim.log.levels.ERROR, { title = "Java" })
			return nil
		end
		jdtls.setup_dap({ hotcodereplace = "auto" })
		return dap
	end
	local function test(method, debug)
		return function()
			if not has_debug or not has_test then
				install_hint("testing", { "java-debug-adapter", "java-test" })
				return
			end
			if not ensure_dap("testing") then
				return
			end
			jdtls[method]({ config_overrides = { noDebug = not debug } })
		end
	end
	local function continue()
		local dap = ensure_dap("debugging")
		if dap then
			dap.continue()
		end
	end

	map("n", "<localleader>o", jdtls.organize_imports, "Java organize imports")
	map("n", "<localleader>v", jdtls.extract_variable, "Java extract variable")
	map(
		"x",
		"<localleader>v",
		"<Esc><Cmd>lua require('jdtls').extract_variable({ visual = true })<CR>",
		"Java extract variable"
	)
	map("n", "<localleader>c", jdtls.extract_constant, "Java extract constant")
	map(
		"x",
		"<localleader>c",
		"<Esc><Cmd>lua require('jdtls').extract_constant({ visual = true })<CR>",
		"Java extract constant"
	)
	map(
		"x",
		"<localleader>m",
		"<Esc><Cmd>lua require('jdtls').extract_method({ visual = true })<CR>",
		"Java extract method"
	)

	-- Preserve the configuration's generic test workflow inside Java buffers.
	map("n", "<leader>rr", test("test_nearest_method", false), "Run nearest Java test")
	map("n", "<leader>rf", test("test_class", false), "Run Java test class")
	map("n", "<leader>rd", test("test_nearest_method", true), "Debug nearest Java test")
	map("n", "<leader>rs", test("pick_test", false), "Pick Java test")
	map("n", "<F5>", continue, "Debug Java: continue / start")
	map("n", "<leader>dc", continue, "Debug Java: continue / start")
	map("n", "<leader>ro", function()
		local dap = ensure_dap("debugging")
		if dap then
			dap.repl.open()
		end
	end, "Open Java debug REPL")
	map("n", "<leader>rO", function()
		if not ensure_dap("debugging") then
			return
		end
		require("lazy").load({ plugins = { "nvim-dap-ui" } })
		require("dapui").toggle()
	end, "Toggle Java debug UI")
	map("n", "<leader>rx", function()
		local dap = ensure_dap("debugging")
		if dap then
			dap.terminate()
		end
	end, "Stop Java debug session")
	map("n", "<localleader>tp", test("pick_test", false), "Pick Java test")
end

local function start_jdtls(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) or vim.bo[bufnr].filetype ~= "java" or vim.b[bufnr].bigfile then
		return
	end

	local java, runtime = java_core.runtime()
	if not java then
		vim.notify(runtime or "Java 21 or newer is required", vim.log.levels.ERROR, { title = "Java" })
		return
	end

	local executable = toolchain.executable("jdtls")
	if not executable then
		install_hint("language support", { "jdtls" })
		return
	end

	local mason_root = vim.fs.normalize(vim.fs.joinpath(vim.fn.stdpath("data"), "mason"))
	local normalized_executable = vim.fs.normalize(executable)
	local mason_relative = normalized_executable:sub(#mason_root + 1)
	if
		normalized_executable == mason_root
		or (vim.startswith(normalized_executable, mason_root) and mason_relative:match("^[/\\]") ~= nil)
	then
		local python, python_version = java_core.python_runtime()
		if not python then
			vim.notify(python_version, vim.log.levels.ERROR, { title = "Java" })
			return
		end
	end

	local jdtls = require("jdtls")
	local root = java_core.project_root(bufnr)
	local workspace = java_core.workspace_dir(root)
	if vim.fn.mkdir(workspace, "p") == 0 and vim.fn.isdirectory(workspace) == 0 then
		vim.notify("Could not create JDTLS workspace: " .. workspace, vim.log.levels.ERROR, { title = "Java" })
		return
	end

	local cmd = { executable, "-data", workspace }
	local lombok = vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "share", "jdtls", "lombok.jar")
	if vim.uv.fs_stat(lombok) then
		table.insert(cmd, "--jvm-arg=-javaagent:" .. lombok)
	end

	local bundles, has_debug, has_test = java_bundles()
	local capabilities = require("blink.cmp").get_lsp_capabilities()
	capabilities.textDocument.foldingRange = {
		dynamicRegistration = false,
		lineFoldingOnly = true,
	}
	local extended_capabilities = vim.deepcopy(jdtls.extendedClientCapabilities)
	extended_capabilities.resolveAdditionalTextEditsSupport = true

	local config = {
		name = "jdtls",
		cmd = cmd,
		root_dir = root,
		capabilities = capabilities,
		settings = {
			java = {
				configuration = {
					updateBuildConfiguration = "interactive",
				},
				eclipse = { downloadSources = true },
				format = { enabled = true },
				inlayHints = {
					parameterNames = { enabled = "literals" },
				},
				maven = { downloadSources = true },
				signatureHelp = { enabled = true },
			},
			redhat = {
				telemetry = { enabled = false },
			},
		},
		init_options = {
			bundles = bundles,
			extendedClientCapabilities = extended_capabilities,
		},
		on_attach = function(_, attached_bufnr)
			setup_java_keys(attached_bufnr, jdtls, has_debug, has_test)
		end,
	}

	vim.api.nvim_buf_call(bufnr, function()
		jdtls.start_or_attach(config)
	end)
end

return {
	{
		"mfussenegger/nvim-jdtls",
		ft = "java",
		dependencies = { "neovim/nvim-lspconfig", "saghen/blink.cmp" },
		config = function()
			vim.api.nvim_create_autocmd("FileType", {
				group = vim.api.nvim_create_augroup("user_jdtls", { clear = true }),
				pattern = "java",
				callback = function(event)
					start_jdtls(event.buf)
				end,
			})

			-- The FileType event that loaded this plugin has already fired.
			start_jdtls(vim.api.nvim_get_current_buf())
		end,
	},
}
