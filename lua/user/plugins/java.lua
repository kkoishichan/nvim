local java_core = require("user.core.java")
local pending_jdtls_buffers = {}
local jdtls_installing = false
local registry_refreshing = false
local start_jdtls

local function mason_jdtls()
	local executable = vim.fn.exepath("jdtls")
	if executable ~= "" then
		return executable
	end

	local name = vim.fn.has("win32") == 1 and "jdtls.cmd" or "jdtls"
	local fallback = vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "bin", name)
	return vim.uv.fs_stat(fallback) and fallback or nil
end

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

local function install_hint(feature)
	local packages = feature == "debugging" and "java-debug-adapter" or "java-debug-adapter and java-test"
	vim.notify(
		("Java %s requires the Mason package%s %s.\n" .. "Run :MasonJavaInstall, then restart Neovim."):format(
			feature,
			feature == "debugging" and "" or "s",
			packages
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
			install_hint(feature or "debugging")
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
				install_hint("testing")
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

local function retry_pending_jdtls()
	local buffers = pending_jdtls_buffers
	pending_jdtls_buffers = {}
	for bufnr in pairs(buffers) do
		local buffer = bufnr
		vim.schedule(function()
			start_jdtls(buffer)
		end)
	end
end

local function fail_pending_jdtls(message)
	pending_jdtls_buffers = {}
	vim.notify(message, vim.log.levels.ERROR, { title = "Java" })
end

local function install_jdtls(bufnr)
	pending_jdtls_buffers[bufnr] = true
	if jdtls_installing or registry_refreshing then
		return
	end

	local ok_registry, registry = pcall(require, "mason-registry")
	if not ok_registry then
		fail_pending_jdtls("Mason is unavailable; run :MasonInstall jdtls")
		return
	end

	local ok_package, package = pcall(registry.get_package, "jdtls")
	if not ok_package then
		-- A fresh Mason installation has no local registry yet. Refresh only for
		-- this explicit Java request; ordinary LSP startup remains offline-only.
		registry_refreshing = true
		vim.notify("Refreshing the Mason registry for JDTLS", vim.log.levels.INFO, { title = "Java" })
		local ok_refresh = pcall(registry.refresh, function(success)
			vim.schedule(function()
				registry_refreshing = false
				if not success then
					fail_pending_jdtls("Could not refresh the Mason registry; check :MasonLog")
					return
				end
				local pending_bufnr = next(pending_jdtls_buffers)
				if pending_bufnr then
					install_jdtls(pending_bufnr)
				end
			end)
		end)
		if not ok_refresh then
			registry_refreshing = false
			fail_pending_jdtls("Could not refresh the Mason registry; check :MasonLog")
		end
		return
	end

	jdtls_installing = true
	package:once("install:success", function()
		jdtls_installing = false
		retry_pending_jdtls()
	end)
	package:once("install:failed", function()
		vim.schedule(function()
			jdtls_installing = false
			fail_pending_jdtls("JDTLS installation failed; check :MasonLog")
		end)
	end)
	if not package:is_installing() then
		local ok_install = pcall(package.install, package, {
			version = require("user.toolchain").version("jdtls"),
		})
		if not ok_install then
			jdtls_installing = false
			fail_pending_jdtls("Could not start the JDTLS installation; check :MasonLog")
			return
		end
	end
	vim.notify_once("Installing JDTLS with Mason; Java support will attach when it finishes", vim.log.levels.INFO)
end

start_jdtls = function(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) or vim.bo[bufnr].filetype ~= "java" or vim.b[bufnr].bigfile then
		return
	end

	local java, runtime = java_core.runtime()
	if not java then
		vim.notify(runtime or "Java 21 or newer is required", vim.log.levels.ERROR, { title = "Java" })
		return
	end

	local executable = mason_jdtls()
	if not executable then
		install_jdtls(bufnr)
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
		dependencies = {
			"mason-org/mason.nvim",
			"neovim/nvim-lspconfig",
			"saghen/blink.cmp",
		},
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
