-- Profile boundaries are behavioral: omitted features must leave no lazy
-- entry, and save-triggered lint must not turn into live checking.
return function(tmp)
	local api = vim.api
	local mode = require("user.core.mode")
	local cap = mode.capabilities()
	assert(mode.name() == "standard", "Run this group in standard mode")
	assert(
		cap.lsp_auto and cap.completion and cap.format_on_save and cap.scroll_animation,
		"Standard lost automatic editing capabilities"
	)
	assert(
		cap.session and not cap.session_auto and cap.lint and not cap.lint_live,
		"Standard enabled live lint or automatic sessions"
	)
	assert(
		cap.workspace_tools and cap.lint_on_write and cap.diagnostics_text,
		"Standard lost workspace inspection capabilities"
	)
	assert(
		not cap.decorations
			and not cap.run
			and not cap.render
			and not cap.automation
			and not cap.docking
			and not cap.auxiliary_lsp
			and not cap.codelens
			and not cap.inlay_hints_auto,
		"Standard enabled extra capabilities"
	)
	local plugins = require("lazy.core.config").plugins
	for _, name in ipairs({
		"blink.cmp",
		"nvim-lspconfig",
		"rustaceanvim",
		"nvim-jdtls",
		"nvim-lint",
		"oil.nvim",
		"neo-tree.nvim",
		"fzf-lua",
		"bufferline.nvim",
		"lualine.nvim",
		"nvim-treesitter-context",
		"nvim-ufo",
		"gitsigns.nvim",
		"diffview.nvim",
		"neoscroll.nvim",
		"outline.nvim",
		"crates.nvim",
	}) do
		assert(plugins[name], "Standard lost " .. name)
	end
	for _, name in ipairs({
		"nvim-dap",
		"neotest",
		"opencode.nvim",
		"claudecode.nvim",
		"image.nvim",
		"markview.nvim",
		"vimtex",
		"typst-preview.nvim",
		"vim-matchup",
		"vim-illuminate",
		"indent-blankline.nvim",
		"nvim-highlight-colors",
		"todo-comments.nvim",
		"nvim-lightbulb",
		"dropbar.nvim",
		"nvim-scrollview",
		"edgy.nvim",
		"persistence.nvim",
		"overseer.nvim",
		"fcitx.nvim",
		"faster.nvim",
	}) do
		assert(not plugins[name], "Standard registered extra plugin " .. name)
	end
	for _, module in ipairs({ "dap", "test", "media", "tasks", "edgy", "opencode", "claudecode", "performance" }) do
		assert(not package.loaded["user.plugins." .. module], "Executed excluded module " .. module)
	end
	assert(not package.loaded["user.core.pdf"], "Statusline eagerly loaded PDF support")
	local snacks = require("lazy.core.plugin").values(plugins["snacks.nvim"], "opts", false)
	assert(
		not snacks.dashboard.enabled and snacks.scratch.enabled and snacks.input.enabled,
		"Snacks profile is incorrect"
	)
	local scratch_mapping = false
	for _, mapping in ipairs(api.nvim_get_keymap("n")) do
		scratch_mapping = scratch_mapping or mapping.lhs == " ."
	end
	assert(scratch_mapping, "Standard lost the scratch entry")
	local diagnostic = vim.diagnostic.config()
	assert(
		diagnostic.underline and diagnostic.signs and diagnostic.virtual_text and not diagnostic.virtual_lines,
		"Standard diagnostic display is incorrect"
	)
	assert(vim.o.undofile and vim.o.swapfile, "Standard lost recovery data")
	for _, command in ipairs({
		"EditorMode",
		"FastMode",
		"ManualLspStart",
		"ManualLspStop",
		"FastLspStart",
		"SessionSave",
	}) do
		assert(vim.fn.exists(":" .. command) == 2, "Missing command " .. command)
	end
	assert(#api.nvim_get_autocmds({ group = "user_workspace_session" }) == 0, "Manual sessions register autosave")
	assert(not plugins["nvim-lint"]._.loaded, "Standalone lint loaded automatically")
	require("lazy").load({ plugins = { "nvim-lint" } })
	local lint = require("lint")
	local calls, original = 0, lint.try_lint
	lint.try_lint = function(names)
		assert(vim.deep_equal(names, { "sqruff" }), "SQL check selected the wrong provider")
		calls = calls + 1
	end
	require("lazy").load({ plugins = { "nvim-lspconfig" } })
	vim.lsp.enable(require("user.core.lsp_definitions").resolve(), false)
	local toolchain = require("user.toolchain")
	local executable = toolchain.executable
	toolchain.executable = function(name, ...)
		return name == "sqruff" and "/fixture/sqruff" or executable(name, ...)
	end
	local file = tmp .. "/manual.sql"
	vim.fn.writefile({ "select 1;" }, file)
	vim.cmd.edit(vim.fn.fnameescape(file))
	vim.wait(600, function()
		return false
	end, 25)
	assert(calls == 0, "Opening a standard buffer ran standalone lint")
	assert(require("gitsigns.config").config.current_line_blame == false, "Standard enabled current-line blame")
	assert(#api.nvim_get_autocmds({ group = "user_lint", event = "BufWritePost" }) > 0, "Lint on write is missing")
	for _, event in ipairs({ "BufReadPost", "InsertLeave" }) do
		assert(
			#api.nvim_get_autocmds({ group = "user_lint", event = event }) == 0,
			"Save-only lint registered " .. event
		)
	end
	vim.cmd.write()
	assert(
		vim.wait(1000, function()
			return calls == 1
		end, 25),
		"Saving SQL did not run Sqruff once"
	)
	vim.cmd.Lint()
	toolchain.executable = executable
	assert(calls == 2, "Manual SQL lint did not run Sqruff after saving")
	lint.try_lint = original
	assert(require("user.core.session").save(tmp .. "/manual.vim"), "Manual session save failed")
	assert(vim.fn.filereadable(tmp .. "/manual.vim") == 1, "Manual session was not written")
	local definitions = require("user.core.lsp_definitions")
	definitions.configure()
	local automatic = definitions.resolve({ automatic = true })
	assert(
		not vim.tbl_contains(automatic, "typos_lsp") and not vim.tbl_contains(automatic, "emmet_language_server"),
		"Auxiliary server was automatically enabled"
	)
	assert(
		vim.tbl_contains(automatic, "ruff") and vim.tbl_contains(automatic, "basedpyright"),
		"Python lost a collaborating server"
	)
	assert(
		not definitions.project_configured("biome", 0) and not definitions.project_configured("tailwindcss", 0),
		"Unconfigured project enabled optional LSP"
	)
	vim.fn.writefile({ "{}" }, tmp .. "/biome.json")
	vim.fn.writefile({ '{"devDependencies":{"tailwindcss":"4"}}' }, tmp .. "/package.json")
	assert(
		definitions.project_configured("biome", 0) and definitions.project_configured("tailwindcss", 0),
		"Configured project did not enable optional LSP"
	)
	-- Manual discovery must not install fast-only definitions over an existing
	-- language integration or take control of its automatic client.
	vim.lsp.config("rust_analyzer", { settings = { ["rust-analyzer"] = { procMacro = { enable = true } } } })
	vim.lsp.config("jdtls", { init_options = { bundles = { "keep-this-bundle" } } })
	require("user.core.manual_lsp").resolve()
	assert(
		vim.lsp.config.rust_analyzer.settings["rust-analyzer"].procMacro.enable,
		"Manual discovery downgraded Rust analysis"
	)
	assert(
		vim.lsp.config.jdtls.init_options.bundles[1] == "keep-this-bundle",
		"Manual discovery overwrote Java bundles"
	)
	local clients, start, detach = vim.lsp.get_clients, vim.lsp.start, vim.lsp.buf_detach_client
	local starts, detached = 0, 0
	vim.lsp.get_clients = function()
		return { { id = 900123, name = "lua_ls" } }
	end
	vim.lsp.start = function()
		starts = starts + 1
	end
	vim.lsp.buf_detach_client = function()
		detached = detached + 1
	end
	vim.cmd("ManualLspStart lua_ls")
	vim.cmd.ManualLspStop()
	vim.lsp.get_clients, vim.lsp.start, vim.lsp.buf_detach_client = clients, start, detach
	assert(starts == 0 and detached == 0, "Manual LSP interfered with an already attached automatic client")
	local rust = require("user.specs.languages")()[1]
	rust.init()
	assert(
		vim.g.rustaceanvim.server.default_settings["rust-analyzer"].check.command == "clippy",
		"Standard downgraded Rust analysis"
	)
	assert(vim.g.rustaceanvim.dap.adapter() == false, "Standard enabled the Rust debugger")
	for _, item in ipairs(require("user.health").packages()) do
		assert(
			not vim.tbl_contains(
				{ "debugpy", "codelldb", "delve", "js-debug-adapter", "java-debug-adapter", "java-test" },
				item[1]
			),
			"Standard health requires an extra-only tool: " .. item[1]
		)
	end
	local root, data = vim.env.NVIM_TEST_ROOT, vim.fn.stdpath("data")
	local support = assert(loadfile(root .. "/scripts/check-support.lua"))()
	local selected = support.selected_plugins(root, data, "standard")
	local active = vim.tbl_keys(plugins)
	table.sort(active)
	assert(vim.deep_equal(selected, active), "Deployment and standard runtime plugin sets differ")
	local extra = support.selected_plugins(root, data, "extra")
	local legacy = support.selected_plugins(root, data, "full")
	local fast = support.selected_plugins(root, data, "fast")
	assert(vim.deep_equal(extra, legacy), "Legacy full deployment differs from extra")
	assert(#fast < #selected and #selected < #extra, "Plugin profiles are not strict subsets")
	for _, name in ipairs(selected) do
		assert(vim.tbl_contains(extra, name), "Standard plugin missing from extra: " .. name)
	end
	assert(mode.name() == "standard" and not mode.capabilities().lint_live, "Asset selection changed the active mode")
	print(
		("Asset evidence: fast %d, standard %d, extra %d locked plugins; runtime and deployment agree"):format(
			#fast,
			#selected,
			#extra
		)
	)
	print(
		"Standard evidence: primary editing/UI retained; workspace tools present; lint on write; extra plugins absent; manual sessions stay manual; auxiliary LSPs gated; Java/Rust definitions preserved"
	)
end
