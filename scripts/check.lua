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
end

do
	local config = require("user.core.treesitter")
	local available = {}
	for _, parser in ipairs(require("nvim-treesitter").get_available()) do
		available[parser] = true
	end

	local configured = {}
	for _, parser in ipairs(config.parsers) do
		assert(not configured[parser], "duplicate Tree-sitter parser: " .. parser)
		assert(available[parser], "unknown Tree-sitter parser: " .. parser)
		assert(vim.treesitter.language.add(parser), "Tree-sitter parser is not installed or loadable: " .. parser)
		configured[parser] = true
	end

	local filetypes = {}
	for _, filetype in ipairs(config.filetypes) do
		assert(not filetypes[filetype], "duplicate Tree-sitter filetype: " .. filetype)
		filetypes[filetype] = true
		local parser = vim.treesitter.language.get_lang(filetype)
		assert(configured[parser], ("Tree-sitter filetype %s maps to unconfigured parser %s"):format(filetype, parser))
	end
end

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
	local plugins = require("lazy.core.config").plugins
	local plugin = require("lazy.core.plugin")
	local float_style = require("user.core.float_style")
	local shared_border = float_style.border()
	local function opts(name)
		return plugin.values(assert(plugins[name], "missing plugin: " .. name), "opts", false)
	end
	local function assert_shared_border(border, label)
		assert(vim.deep_equal(border, shared_border), label .. " does not use the shared borderless style")
	end

	local glance = plugins["glance.nvim"]
	assert(glance and glance.cmd == "Glance", "Glance peek UI is missing or not lazy-loaded")
	local neo_tree_opts = opts("neo-tree.nvim")
	assert(neo_tree_opts.enable_git_status, "neo-tree Git status is disabled")
	assert(neo_tree_opts.enable_diagnostics, "neo-tree diagnostics are disabled")
	assert(neo_tree_opts.filesystem.use_libuv_file_watcher, "neo-tree file watcher is disabled")
	local gitsigns_opts = opts("gitsigns.nvim")
	assert(gitsigns_opts.current_line_blame, "current-line Git blame is disabled")
	for _, signs in ipairs({ gitsigns_opts.signs, gitsigns_opts.signs_staged }) do
		for _, kind in ipairs({ "add", "change", "changedelete" }) do
			assert(signs[kind].text == "┃", "Gitsigns " .. kind .. " marker is not a centred heavy bar")
		end
	end
	assert_shared_border(gitsigns_opts.preview_config.border, "Gitsigns previews")
	assert(
		gitsigns_opts.preview_config.row == 1 and gitsigns_opts.preview_config.col == 0,
		"Gitsigns preview is misplaced"
	)
	assert_shared_border(vim.diagnostic.config().float.border, "Diagnostic floats")
	assert_shared_border(opts("nvim-ufo").preview.win_config.border, "Fold previews")
	assert_shared_border(opts("outline.nvim").preview_window.border, "Outline previews")
	assert_shared_border(opts("nvim-bqf").preview.border, "Quickfix previews")
	assert_shared_border(opts("nvim-dap-ui").floating.border, "DAP eval floats")
	assert_shared_border(opts("crates.nvim").popup.border, "Crates popups")
	local snacks_opts = opts("snacks.nvim")
	assert_shared_border(snacks_opts.styles.input.border, "vim.ui.input")
	assert(snacks_opts.styles.notification.border == "rounded", "Snacks notification style was changed")
	assert_shared_border(opts("which-key.nvim").win.border, "Which-key")
	assert(opts("blink.cmp").completion.menu.border == "padded", "Completion menu lost its borderless style")
	assert(opts("nvim-notify").stages == "fade", "nvim-notify animation or frame was changed")
	assert(
		vim.api.nvim_get_hl(0, { name = "NotifyBackground", link = false }).bg
			== require("user.core.palette").get().panel,
		"nvim-notify background was changed"
	)

	-- Other application-sized overlays deliberately keep their framed layouts.
	assert(opts("fzf-lua").winopts.border == "rounded", "Fzf main window lost its panel border")
	assert(opts("oil.nvim").float.border == "rounded", "Oil float lost its panel border")
	assert(opts("toggleterm.nvim").float_opts.border == "rounded", "Float terminal lost its panel border")
	local layout = require("user.core.layout")
	local mason_ui = opts("mason.nvim").ui
	local lazy_ui = require("lazy.core.config").options.ui
	assert(layout.manager_border == "none", "package managers still have a border or transparent shadow")
	assert(mason_ui.border == layout.manager_border, "Mason lost its borderless manager style")
	assert(lazy_ui.border == layout.manager_border, "Lazy lost its borderless manager style")
	assert(
		mason_ui.width == layout.manager_scale and mason_ui.height == layout.manager_scale,
		"Mason manager size diverged"
	)
	assert(
		lazy_ui.size.width == layout.manager_scale and lazy_ui.size.height == layout.manager_scale,
		"Lazy manager size diverged"
	)
	local scrollview_opts = opts("nvim-scrollview")
	for _, group in ipairs({ "diagnostics", "search", "marks", "keywords", "conflicts" }) do
		assert(
			vim.tbl_contains(scrollview_opts.signs_on_startup, group),
			"scrollview " .. group .. " markers are disabled"
		)
	end
	assert(scrollview_opts.signs_scrollbar_overlap == "over", "scrollview markers no longer use a single rail")
	assert(scrollview_opts.signs_max_per_row == 1, "scrollview markers can spill into multiple columns")
	assert(scrollview_opts.hide_on_float_intersect, "scrollview can draw through floating windows")
	local scrollview_symbols = {
		diagnostic_error = scrollview_opts.diagnostics_error_symbol,
		diagnostic_warn = scrollview_opts.diagnostics_warn_symbol,
		diagnostic_info = scrollview_opts.diagnostics_info_symbol,
		diagnostic_hint = scrollview_opts.diagnostics_hint_symbol,
		search = scrollview_opts.search_symbol,
		keyword_fix = scrollview_opts.keywords_fix_symbol,
		keyword_todo = scrollview_opts.keywords_todo_symbol,
		keyword_hack = scrollview_opts.keywords_hack_symbol,
		keyword_warn = scrollview_opts.keywords_warn_symbol,
		keyword_xxx = scrollview_opts.keywords_xxx_symbol,
		conflict = scrollview_opts.conflicts_top_symbol,
	}
	assert(
		vim.deep_equal(scrollview_symbols, {
			diagnostic_error = "E",
			diagnostic_warn = "W",
			diagnostic_info = "I",
			diagnostic_hint = "H",
			search = "━",
			keyword_fix = "",
			keyword_todo = "",
			keyword_hack = "",
			keyword_warn = "",
			keyword_xxx = "",
			conflict = "×",
		}),
		"scrollview markers diverged from the left gutter vocabulary"
	)
	for source, symbol in pairs(scrollview_symbols) do
		assert(vim.fn.strdisplaywidth(symbol) == 1, "scrollview " .. source .. " symbol is not one cell wide")
	end
	assert(
		scrollview_opts.diagnostics_error_priority > scrollview_opts.conflicts_top_priority
			and scrollview_opts.conflicts_top_priority > scrollview_opts.diagnostics_warn_priority
			and scrollview_opts.diagnostics_warn_priority > scrollview_opts.search_priority
			and scrollview_opts.search_priority > scrollview_opts.marks_priority
			and scrollview_opts.marks_priority > scrollview_opts.diagnostics_info_priority,
		"scrollview marker priority hierarchy changed"
	)
	local p = require("user.core.palette").get()
	assert(
		vim.api.nvim_get_hl(0, { name = "ScrollView", link = false }).bg
			== require("user.core.palette").blend(p.fg, p.bg, 0.13),
		"scrollview thumb is not using the quiet theme-derived colour"
	)
	assert(
		vim.api.nvim_get_hl(0, { name = "ScrollViewSearch", link = false }).fg
			== vim.api.nvim_get_hl(0, { name = "Special", link = false }).fg,
		"scrollview search markers lost their source-specific colour"
	)
	for group, colour in pairs({
		ScrollViewKeywordsFix = p.error,
		ScrollViewKeywordsTodo = p.info,
		ScrollViewKeywordsHack = p.warn,
		ScrollViewKeywordsWarn = p.warn,
		ScrollViewKeywordsXxx = p.warn,
	}) do
		assert(
			vim.api.nvim_get_hl(0, { name = group, link = false }).fg == colour,
			group .. " no longer matches the left gutter colour"
		)
	end
	require("lazy").load({ plugins = { "nvim-scrollview" } })
	vim.wait(200)
	local git_legend = vim.api.nvim_exec2("ScrollViewLegend! gitsigns", { output = true }).output
	assert(git_legend:find("┃", 1, true), "scrollview Git marker is not a heavy solid centred bar")
	assert(vim.fn.maparg("<leader>us", "n") == "", "search markers regained a dedicated toggle")
end

do
	local float_style = require("user.core.float_style")
	local function open_float(bufnr, width, height, border)
		return vim.api.nvim_open_win(bufnr, false, {
			relative = "editor",
			row = 1,
			col = 1,
			width = width,
			height = height,
			border = border or "rounded",
			style = "minimal",
		})
	end

	local small_buffer = vim.api.nvim_create_buf(false, true)
	local small = open_float(small_buffer, 24, 4)
	vim.wo[small].winhighlight = "Normal:ErrorMsg,CursorLine:Visual"
	assert(
		vim.wait(200, function()
			return float_style.is_padded(small)
		end),
		"small third-party float was not restyled"
	)
	assert(vim.wo[small].winhighlight:find("Normal:Pmenu", 1, true), "small float body does not use Pmenu")
	assert(vim.wo[small].winhighlight:find("FloatBorder:Pmenu", 1, true), "small float padding does not use Pmenu")
	assert(vim.wo[small].winhighlight:find("CursorLine:Visual", 1, true), "popup styling discarded a plugin highlight")

	local large_buffer = vim.api.nvim_create_buf(false, true)
	local large_width = math.max(1, vim.o.columns - 4)
	local large_height = math.max(1, vim.o.lines - vim.o.cmdheight - 4)
	local large = open_float(large_buffer, large_width, large_height)
	vim.wait(50)
	assert(not float_style.is_padded(large), "application-sized float was mistaken for a popup")

	local panel_buffer = vim.api.nvim_create_buf(false, true)
	vim.bo[panel_buffer].filetype = "Glance"
	local panel = open_float(panel_buffer, 24, 4)
	vim.wait(50)
	assert(not float_style.is_padded(panel), "small Glance pane lost its dedicated layout")

	local popup_buffer = vim.api.nvim_create_buf(false, true)
	vim.bo[popup_buffer].filetype = "neo-tree-popup"
	local popup = open_float(popup_buffer, large_width, 4)
	assert(
		vim.wait(200, function()
			return float_style.is_padded(popup)
		end),
		"Neo-tree dialog fallback was not applied"
	)

	local notification_buffer = vim.api.nvim_create_buf(false, true)
	local notification = open_float(notification_buffer, 24, 4)
	vim.bo[notification_buffer].filetype = "notify"
	vim.wait(50)
	assert(not float_style.is_padded(notification), "generic popup styling changed nvim-notify")

	local layout = require("user.core.layout")
	local lazy_buffer = vim.api.nvim_create_buf(false, true)
	local lazy_window = open_float(lazy_buffer, 30, 6, layout.manager_border)
	vim.bo[lazy_buffer].filetype = "lazy"
	local mason_buffer = vim.api.nvim_create_buf(false, true)
	local mason_window = open_float(mason_buffer, 50, 10, layout.manager_border)
	vim.bo[mason_buffer].filetype = "mason"
	assert(
		vim.wait(200, function()
			local lazy_config = vim.api.nvim_win_get_config(lazy_window)
			local mason_config = vim.api.nvim_win_get_config(mason_window)
			return lazy_config.width == mason_config.width
				and lazy_config.height == mason_config.height
				and lazy_config.row == mason_config.row
				and lazy_config.col == mason_config.col
		end),
		"Lazy and Mason manager rectangles still differ"
	)

	local backdrop_buffer = vim.api.nvim_create_buf(false, true)
	local backdrop = open_float(backdrop_buffer, 30, 6)
	vim.bo[backdrop_buffer].filetype = "lazy_backdrop"
	local backdrop_config = vim.api.nvim_win_get_config(backdrop)
	assert(backdrop_config.border == "none", "Lazy backdrop inherited the global window border")
	assert(
		backdrop_config.row == 0
			and backdrop_config.col == 0
			and backdrop_config.width == vim.o.columns
			and backdrop_config.height == vim.o.lines,
		"Lazy backdrop no longer covers the viewport exactly"
	)

	for _, winid in ipairs({ small, large, panel, popup, notification, lazy_window, mason_window, backdrop }) do
		vim.api.nvim_win_close(winid, true)
	end
end

do
	local toolchain = require("user.toolchain")
	local seen = {}
	for _, package in ipairs(toolchain.packages) do
		assert(type(package[1]) == "string" and package[1] ~= "", "invalid Mason package name")
		assert(type(package.version) == "string" and package.version ~= "", "missing tool pin: " .. package[1])
		assert(not seen[package[1]], "duplicate tool pin: " .. package[1])
		seen[package[1]] = true
		assert(toolchain.version(package[1]) == package.version, "tool pin lookup is inconsistent: " .. package[1])
	end

	seen = {}
	for _, server in ipairs(toolchain.lsp_servers) do
		assert(type(server) == "string" and server ~= "", "invalid LSP server name")
		assert(not seen[server], "duplicate LSP server: " .. server)
		seen[server] = true
	end

	local mason_bin = vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "bin")
	local latexindent_candidates = vim.fn.has("win32") == 1
			and { "latexindent.cmd", "latexindent.exe", "latexindent.bat", "latexindent" }
		or { "latexindent" }
	local mason_latexindent
	for _, candidate in ipairs(latexindent_candidates) do
		local executable = vim.fs.joinpath(mason_bin, candidate)
		if vim.fn.executable(executable) == 1 then
			mason_latexindent = executable
			break
		end
	end
	if mason_latexindent then
		assert(
			toolchain.executable("latexindent", { prefer_mason = true }) == mason_latexindent,
			"latexindent did not prefer Mason's self-contained executable"
		)
		local result = vim.system({ mason_latexindent, "--version" }, { text = true }):wait(5000)
		assert(result.code == 0, "Mason's latexindent executable is not runnable: " .. (result.stderr or ""))

		require("lazy").load({ plugins = { "conform.nvim" } })
		local buffer = vim.api.nvim_create_buf(false, false)
		vim.api.nvim_buf_set_name(buffer, vim.fs.joinpath(tmp, "latexindent-audit.tex"))
		vim.bo[buffer].filetype = "tex"
		local format_err, formatted = require("conform").format_lines({ "latexindent" }, {
			"\\begin{itemize}",
			"\\item outer",
			"\\begin{itemize}",
			"\\item inner",
			"\\end{itemize}",
			"\\end{itemize}",
		}, { bufnr = buffer, timeout_ms = 10000, quiet = true })
		assert(not format_err and formatted, "latexindent formatting failed: " .. tostring(format_err))
		assert(
			vim.uv.fs_stat(vim.fs.joinpath(vim.fn.stdpath("cache"), "latexindent", "indent.log")),
			"latexindent log was not redirected to Neovim's cache"
		)
		vim.api.nvim_buf_delete(buffer, { force = true })
	end
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
	local attach = vim.api.nvim_get_autocmds({ group = "user_lsp_attach", event = "LspAttach" })[1]
	assert(attach and type(attach.callback) == "function", "LSP attach callback is missing")
	local keymap_buffer = vim.api.nvim_create_buf(false, true)
	attach.callback({ buf = keymap_buffer, data = { client_id = -1 } })
	local lsp_keymaps = {}
	for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(keymap_buffer, "n")) do
		lsp_keymaps[mapping.lhs] = mapping.rhs
	end
	for lhs, command in pairs({
		gd = "definitions",
		gD = "declarations",
		gi = "implementations",
		gy = "type_definitions",
		gr = "references",
		[" cpd"] = "definitions",
		[" cpD"] = "declarations",
		[" cpi"] = "implementations",
		[" cpt"] = "type_definitions",
		[" cpr"] = "references",
	}) do
		assert(lsp_keymaps[lhs] == "<Cmd>Glance " .. command .. "<CR>", lhs .. " no longer uses Glance")
	end
	vim.api.nvim_buf_delete(keymap_buffer, { force = true })
	for _, server in ipairs(require("user.toolchain").lsp_servers) do
		local config = vim.lsp.config[server]
		assert(type(config) == "table", "missing LSP config: " .. server)
		assert(type(config.filetypes) == "table" and #config.filetypes > 0, "LSP has no filetypes: " .. server)
	end
	local rpc_start = vim.lsp.rpc.start
	local ok_commands, web_commands = pcall(function()
		vim.lsp.rpc.start = function(command)
			return command
		end
		local config = { root_dir = tmp .. "/web-lsp-command-audit" }
		return {
			biome = vim.lsp.config.biome.cmd({}, config),
			tailwindcss = vim.lsp.config.tailwindcss.cmd({}, config),
		}
	end)
	vim.lsp.rpc.start = rpc_start
	assert(ok_commands, "Web LSP command resolution failed: " .. tostring(web_commands))
	local web_command_specs = {
		biome = { executable = "biome", argument = "lsp-proxy" },
		tailwindcss = { executable = "tailwindcss-language-server", argument = "--stdio" },
	}
	local toolchain = require("user.toolchain")
	for server, spec in pairs(web_command_specs) do
		local resolved = toolchain.executable(spec.executable)
		assert(
			not resolved or web_commands[server][1] == resolved,
			server .. " did not resolve its Mason/system binary"
		)
		assert(web_commands[server][2] == spec.argument, server .. " lost its LSP transport argument")
	end

	local vue = require("user.toolchain").executable("vue-language-server")
	if vue then
		local plugins = vim.lsp.config.vtsls.settings.vtsls.tsserver.globalPlugins
		assert(
			plugins and vim.uv.fs_stat(plugins[1].location .. "/package.json"),
			"vtsls has an invalid Vue plugin path"
		)
	end

	lazy.load({ plugins = { "nvim-jdtls" } })
	assert(not package.loaded.mason and not package.loaded["mason-registry"], "Java support started Mason")
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
	assert(type(dap.adapters.codelldb) == "function", "codelldb adapter is missing")
	assert(#(dap.configurations.c or {}) >= 2, "C launch/attach configurations are missing")
	assert(#(dap.configurations.cpp or {}) >= 2, "C++ launch/attach configurations are missing")
end

do
	require("lazy").load({ plugins = { "nvim-lint" } })
	local lint = require("lint")
	for filetype, names in pairs(lint.linters_by_ft) do
		for _, name in ipairs(names) do
			assert(lint.linters[name] ~= nil, ("unknown linter %s for %s"):format(name, filetype))
		end
	end
end

do
	local base = tmp .. "/tests"
	vim.fn.mkdir(base .. "/python", "p")
	vim.fn.writefile({}, base .. "/python/pyproject.toml")
	vim.fn.writefile({ "def test_ok():", "    assert True" }, base .. "/python/test_ok.py")
	vim.fn.mkdir(base .. "/go", "p")
	vim.fn.writefile({ "module example.test", "", "go 1.24" }, base .. "/go/go.mod")
	vim.fn.writefile({ "package example" }, base .. "/go/example_test.go")

	require("lazy").load({ plugins = { "neotest" } })
	local testing = require("user.core.testing")
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
	assert(not package.loaded["neotest-vitest"], "unrelated test adapter was loaded")
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
