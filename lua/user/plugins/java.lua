local multi_module_markers = {
	"mvnw",
	"gradlew",
	"settings.gradle",
	"settings.gradle.kts",
	".git",
}

local single_module_markers = {
	"build.xml",
	"pom.xml",
	"build.gradle",
	"build.gradle.kts",
}

local function project_root(bufnr)
	local root = vim.fs.root(bufnr, multi_module_markers) or vim.fs.root(bufnr, single_module_markers)
	if root then
		return vim.fs.normalize(root)
	end

	local path = vim.api.nvim_buf_get_name(bufnr)
	return path ~= "" and vim.fs.dirname(vim.fs.normalize(path)) or vim.fn.getcwd()
end

local function workspace_dir(root)
	local project = vim.fn.fnamemodify(root, ":t"):gsub("[^%w._-]", "_")
	if project == "" then
		project = "root"
	end

	-- The hash prevents projects with the same directory name from sharing an
	-- Eclipse workspace and leaking indexes or build configuration into each other.
	return vim.fs.joinpath(
		vim.fn.stdpath("data"),
		"jdtls",
		"workspaces",
		("%s-%s"):format(project, vim.fn.sha256(root):sub(1, 12))
	)
end

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
	vim.notify(
		(
			"Java %s requires the Mason packages java-debug-adapter and java-test.\n"
			.. "Run :MasonToolsInstall, then restart Neovim."
		):format(feature),
		vim.log.levels.WARN,
		{ title = "Java" }
	)
end

local function setup_java_keys(bufnr, jdtls, has_debug, has_test)
	local function map(mode, lhs, rhs, desc)
		vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, desc = desc, silent = true })
	end
	local function test(method, debug)
		return function()
			if not has_debug or not has_test then
				install_hint("testing")
				return
			end
			jdtls[method]({ config_overrides = { noDebug = not debug } })
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
	map("n", "<localleader>tp", test("pick_test", false), "Pick Java test")
end

local function start_jdtls(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) or vim.bo[bufnr].filetype ~= "java" or vim.b[bufnr].bigfile then
		return
	end

	local executable = mason_jdtls()
	if not executable then
		local ok_registry, registry = pcall(require, "mason-registry")
		local ok_package, package = false, nil
		if ok_registry then
			ok_package, package = pcall(registry.get_package, "jdtls")
		end
		if not ok_package then
			vim.notify("JDTLS is unavailable; run :MasonInstall jdtls", vim.log.levels.ERROR, { title = "Java" })
			return
		end

		package:once("install:success", function()
			vim.schedule(function()
				start_jdtls(bufnr)
			end)
		end)
		package:once("install:failed", function()
			vim.schedule(function()
				vim.notify("JDTLS installation failed; check :MasonLog", vim.log.levels.ERROR, { title = "Java" })
			end)
		end)
		if not package:is_installing() then
			package:install()
		end
		vim.notify_once("Installing JDTLS with Mason; Java support will attach when it finishes", vim.log.levels.INFO)
		return
	end

	if vim.fn.executable("java") ~= 1 then
		vim.notify("JDTLS requires Java 21 or newer in PATH", vim.log.levels.ERROR, { title = "Java" })
		return
	end

	local jdtls = require("jdtls")
	local root = project_root(bufnr)
	local workspace = workspace_dir(root)
	vim.fn.mkdir(workspace, "p")

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
			if has_debug then
				jdtls.setup_dap({ hotcodereplace = "auto" })
			end
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
			"mfussenegger/nvim-dap",
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
