local tmp = assert(vim.env.NVIM_TEST_TMP, "NVIM_TEST_TMP is required")

assert(require("user.core.theme").saved() == "vscode", "default theme is not vscode")
assert(vim.g.colors_name == "vscode", "vscode was not applied at startup")
assert(
	vim.api.nvim_get_hl(0, { name = "Pmenu", link = false }).bg == 0x2d2d30,
	"vscode popup background override was not applied"
)
do
	local visual = vim.api.nvim_get_hl(0, { name = "Visual", link = false })
	local snippet = vim.api.nvim_get_hl(0, { name = "SnippetTabstop", link = false })
	local active_snippet = vim.api.nvim_get_hl(0, { name = "SnippetTabstopActive", link = true })
	assert(visual.bg == 0x264f78, "vscode Visual selection colour was overridden")
	assert(
		snippet.bg == require("user.core.palette").get().subtle and snippet.fg == nil,
		"Native snippet placeholders are not using the theme-derived neutral grey"
	)
	assert(snippet.bg ~= visual.bg, "Native snippet placeholders still inherit Visual")
	assert(active_snippet.link == "SnippetTabstop", "Active snippet placeholder does not inherit snippet grey")
end
assert(vim.o.shada:match("<0"), "ShaDa still persists register contents")
assert(vim.g.user_lsp_preview_patched == nil, "LSP floating-preview API was monkeypatched")
assert(
	type(vim.fn.maparg("<Esc>", "n", false, true).callback) == "function",
	"Normal Escape is not a semantic popup closer"
)
assert(
	type(vim.fn.maparg("<Esc>", "x", false, true).callback) == "function",
	"Visual Escape is not a semantic popup closer"
)

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
	local ufo_opts = opts("nvim-ufo")
	assert_shared_border(ufo_opts.preview.win_config.border, "Fold previews")
	assert(ufo_opts.preview.mappings.close == "q", "Fold previews lost their original q mapping")
	assert_shared_border(opts("outline.nvim").preview_window.border, "Outline previews")
	assert_shared_border(opts("nvim-bqf").preview.border, "Quickfix previews")
	assert_shared_border(opts("nvim-dap-ui").floating.border, "DAP eval floats")
	assert_shared_border(opts("crates.nvim").popup.border, "Crates popups")
	local snacks_opts = opts("snacks.nvim")
	assert_shared_border(snacks_opts.styles.input.border, "vim.ui.input")
	assert(
		vim.deep_equal(snacks_opts.styles.input.keys.i_esc[2], { "cmp_close", "cancel" }),
		"vim.ui.input still needs two Escape presses"
	)
	assert(snacks_opts.styles.notification.border == "rounded", "Snacks notification style was changed")
	assert_shared_border(opts("which-key.nvim").win.border, "Which-key")
	local completion_opts = opts("blink.cmp")
	assert(completion_opts.completion.menu.border == "padded", "Completion menu lost its borderless style")
	assert(completion_opts.keymap.preset == "super-tab", "Completion no longer uses IDE-style Tab acceptance")
	assert(
		type(completion_opts.keymap["<C-Space>"][1]) == "function"
			and completion_opts.keymap["<C-Space>"][1]() == true
			and completion_opts.keymap["<C-Space>"][2] == nil
			and type(completion_opts.cmdline.keymap["<C-Space>"][1]) == "function"
			and completion_opts.cmdline.keymap["<C-Space>"][1]() == true,
		"Ctrl-Space is no longer reserved exclusively for the input method"
	)
	assert(
		vim.deep_equal(completion_opts.keymap["<M-Space>"], { "show", "show_documentation", "hide_documentation" }),
		"Manual completion was not moved to Alt-Space"
	)
	assert(
		vim.deep_equal(completion_opts.keymap["<CR>"], { "accept", "fallback" }),
		"Enter no longer safely confirms an explicitly selected completion"
	)
	local completion_escape = completion_opts.keymap["<Esc>"]
	assert(
		type(completion_escape[1]) == "function" and completion_escape[2] == "fallback" and completion_escape[3] == nil,
		"Escape no longer dismisses popups and leaves Insert mode in one keypress"
	)
	local blink_closed = {}
	assert(completion_escape[1]({
		is_documentation_visible = function()
			return true
		end,
		hide_documentation = function()
			blink_closed.documentation = true
		end,
		is_signature_visible = function()
			return true
		end,
		hide_signature = function()
			blink_closed.signature = true
		end,
		is_visible = function()
			return true
		end,
		cancel = function()
			blink_closed.completion = true
		end,
	}) == nil, "Escape popup closer consumed the key before Blink's fallback")
	assert(
		blink_closed.completion and blink_closed.documentation and blink_closed.signature,
		"Escape did not close every overlapping Blink popup"
	)
	assert(
		type(completion_opts.keymap["<C-k>"][1]) == "function" and completion_opts.keymap["<C-k>"][2] == "fallback",
		"C-k no longer toggles the compact/full signature view"
	)
	assert(
		vim.deep_equal(
			completion_opts.keymap["<C-b>"],
			{ "scroll_signature_up", "scroll_documentation_up", "fallback" }
		)
			and vim.deep_equal(
				completion_opts.keymap["<C-f>"],
				{ "scroll_signature_down", "scroll_documentation_down", "fallback" }
			),
		"Expanded signatures cannot be scrolled"
	)
	assert(completion_opts.signature.enabled, "Blink signature help is disabled")
	assert(completion_opts.signature.trigger.enabled, "Signature help no longer opens automatically")
	assert(
		completion_opts.signature.trigger.show_on_insert,
		"Signature help is not requested when entering an existing call"
	)
	assert(completion_opts.signature.window.border == "padded", "Blink signature window lost its padded style")
	assert(completion_opts.signature.window.max_height == 1, "Automatic signature help is not limited to one line")
	local signature_renderer = require("user.core.blink_signature")
	local overloads = {
		activeSignature = 1,
		activeParameter = 2,
		signatures = {
			{ label = "pick(value: string)" },
			{ label = "pick(value: number, base: number)" },
			{ label = "pick(value: boolean)" },
		},
	}
	local compact_overload = signature_renderer.signature_help_view(overloads, false)
	assert(
		compact_overload.activeSignature == 0
			and compact_overload.activeParameter == 2
			and #compact_overload.signatures == 1
			and compact_overload.signatures[1].label == "pick(value: number, base: number)",
		"Compact signature help does not show the LSP-selected overload"
	)
	local expanded_overloads = signature_renderer.signature_help_view(overloads, true)
	assert(
		#expanded_overloads.signatures == 3
			and expanded_overloads.signatures[1].label == "pick(value: number, base: number)"
			and expanded_overloads.signatures[2].label == "pick(value: string)"
			and expanded_overloads.signatures[3].label == "pick(value: boolean)",
		"Expanded signature help does not put the active overload before every alternative"
	)
	assert(overloads.activeSignature == 1, "Signature rendering mutated the LSP response")
	local virtual_chunks = signature_renderer.virtual_chunks("pick(value: number, base: number)", "python", { 20, 32 })
	local virtual_label = ""
	local active_parameter = ""
	local has_syntax = false
	local indicator_uses_yellow = false
	for _, chunk in ipairs(virtual_chunks) do
		virtual_label = virtual_label .. chunk[1]
		if type(chunk[2]) == "table" then
			assert(
				vim.tbl_contains(chunk[2], "BlinkCmpSignatureVirtual"),
				"Virtual signature lost its popup background"
			)
			if vim.tbl_contains(chunk[2], "BlinkCmpSignatureHelpActiveParameter") then
				active_parameter = active_parameter .. chunk[1]
			end
			for _, highlight in ipairs(chunk[2]) do
				has_syntax = has_syntax or vim.startswith(highlight, "@")
				if chunk[1]:find(signature_renderer.virtual_indicator, 1, true) then
					indicator_uses_yellow = indicator_uses_yellow or highlight == "BlinkCmpSignatureVirtualIndicator"
				end
			end
		end
	end
	assert(virtual_label == " ◀ pick(value: number, base: number) ", "Virtual signature text changed")
	assert(
		virtual_chunks[1][1] == " " and virtual_chunks[1][2] == "BlinkCmpSignatureVirtual",
		"Virtual signature has no background-coloured left padding"
	)
	assert(
		vim.fn.strdisplaywidth(signature_renderer.virtual_indicator) == 1,
		"Virtual signature indicator is not one cell wide"
	)
	assert(indicator_uses_yellow, "Virtual signature indicator does not use its yellow highlight")
	assert(
		vim.api.nvim_get_hl(0, { name = "BlinkCmpSignatureVirtualIndicator", link = false }).fg
			== require("user.core.palette").get().warn,
		"Virtual signature indicator is not theme yellow"
	)
	assert(
		vim.api.nvim_get_hl(0, { name = "BlinkCmpSignatureIndicator", link = false }).fg == 0xc586c0,
		"Full signature indicator is not VS Code purple"
	)
	assert(active_parameter == "base: number", "Virtual signature lost its active parameter")
	assert(has_syntax, "Virtual signature lost Tree-sitter highlighting")
	local signature_background = vim.api.nvim_get_hl(0, { name = "BlinkCmpSignatureVirtual", link = false }).bg
	assert(
		signature_background == vim.api.nvim_get_hl(0, { name = "Pmenu", link = false }).bg,
		"Virtual signature background differs from Blink"
	)
	local active_parameter_highlight =
		vim.api.nvim_get_hl(0, { name = "BlinkCmpSignatureHelpActiveParameter", link = false })
	assert(
		active_parameter_highlight.bg
			== require("user.core.palette").blend(require("user.core.palette").get().fg, signature_background, 0.16),
		"Active signature parameter background is not a lighter neutral grey"
	)
	assert(active_parameter_highlight.fg == nil, "Active signature parameter overrides syntax foreground colours")
	local source_buffer = vim.api.nvim_get_current_buf()
	local position_buffer = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_set_current_buf(position_buffer)
	local call_line = "    pick(value"
	local call_cursor = { 2, #call_line }
	local cursor_width = vim.fn.strdisplaywidth(call_line)
	vim.api.nvim_buf_set_lines(position_buffer, 0, -1, false, { "", call_line, "" })
	local live_cursor = { 2, 4 }
	vim.api.nvim_win_set_cursor(0, live_cursor)
	assert(
		vim.deep_equal(signature_renderer.display_cursor(position_buffer, { 1, 0 }), live_cursor),
		"Virtual signature still uses Blink's stale request cursor"
	)
	local signature_row, signature_padding, signature_side =
		signature_renderer.virtual_position(position_buffer, call_cursor)
	assert(
		signature_row == 0 and signature_side == -1 and vim.fn.strdisplaywidth(signature_padding) == cursor_width,
		"Virtual signature did not use available space on the previous line"
	)
	vim.api.nvim_buf_set_lines(position_buffer, 0, 1, false, { string.rep("x", cursor_width + 1) })
	signature_row, signature_padding, signature_side = signature_renderer.virtual_position(position_buffer, call_cursor)
	assert(
		signature_row == 2 and signature_side == 1 and vim.fn.strdisplaywidth(signature_padding) == cursor_width,
		"Virtual signature did not fall back to available space on the next line"
	)
	vim.api.nvim_buf_set_lines(position_buffer, 2, 3, false, { string.rep("x", cursor_width + 1) })
	signature_row, signature_padding, signature_side = signature_renderer.virtual_position(position_buffer, call_cursor)
	assert(
		signature_row == 1 and signature_side == 0 and signature_padding == "",
		"Virtual signature used a neighbouring line whose anchor cell contains text"
	)
	local far_line = string.rep(" ", vim.api.nvim_win_get_width(0) + 4) .. "pick("
	local far_cursor = { 2, #far_line }
	vim.api.nvim_buf_set_lines(position_buffer, 0, -1, false, { "", far_line, "" })
	signature_row, _, signature_side = signature_renderer.virtual_position(position_buffer, far_cursor)
	assert(
		signature_row == 0 and signature_side == -1,
		"Virtual signature still requires its full width to fit in the window"
	)
	local nested_call = "outer(inner(value), other)"
	local inner_start = assert(nested_call:find("inner(", 1, true))
	local value_start = assert(nested_call:find("value", 1, true))
	vim.api.nvim_buf_set_lines(position_buffer, 0, -1, false, { nested_call })
	vim.bo[position_buffer].filetype = "python"
	assert(
		vim.deep_equal(signature_renderer.find_call_anchor(position_buffer, { 1, value_start }), { 1, inner_start - 1 }),
		"Signature anchor did not select the innermost function name"
	)
	local qualified_call = "torch.arange("
	vim.api.nvim_buf_set_lines(position_buffer, 0, -1, false, { qualified_call })
	assert(
		vim.deep_equal(signature_renderer.find_call_anchor(position_buffer, { 1, #qualified_call }), { 1, 0 }),
		"Signature anchor did not find a just-typed qualified function name"
	)
	vim.bo[position_buffer].filetype = "text"
	assert(
		vim.deep_equal(signature_renderer.find_call_anchor(position_buffer, { 1, #qualified_call }), { 1, 0 }),
		"Signature anchor has no lexical fallback when a Tree-sitter parser is unavailable"
	)

	local function overload(label, parameters)
		return {
			label = label,
			-- Reproduce a stale signature-local value, which Neovim gives
			-- precedence over SignatureHelp.activeParameter.
			activeParameter = 1,
			parameters = vim.tbl_map(function(parameter)
				return { label = parameter }
			end, parameters),
		}
	end
	local cpp_overloads = {
		-- Reproduce clangd/Blink retaining the two-argument overload even after
		-- the call grows beyond every available fixed arity.
		activeSignature = 1,
		activeParameter = 0,
		signatures = {
			overload("int foo(int b)", { "int b" }),
			overload("int foo(int c, int d)", { "int c", "int d" }),
			overload("int foo(int e, int f, int g)", { "int e", "int f", "int g" }),
			overload("int foo(int h, int i, int j, int k)", { "int h", "int i", "int j", "int k" }),
			overload("float foo(float p)", { "float p" }),
			overload("int foo(float m, float n)", { "float m", "float n" }),
		},
	}
	local function assert_corrected_call(
		call,
		expected_signature,
		expected_parameter,
		label,
		cursor,
		expected_argument_count
	)
		local lines = vim.split(call, "\n", { plain = true })
		vim.api.nvim_buf_set_lines(position_buffer, 0, -1, false, lines)
		vim.bo[position_buffer].filetype = "cpp"
		cursor = cursor or { #lines, #lines[#lines] }
		vim.api.nvim_win_set_cursor(0, cursor)
		local call_state = assert(signature_renderer.call_arguments(position_buffer, cursor))
		assert(
			call_state.active_parameter == expected_parameter,
			("Signature argument scanner chose parameter %d for %s"):format(call_state.active_parameter, call)
		)
		assert(
			call_state.argument_count == (expected_argument_count or expected_parameter + 1),
			("Signature argument scanner counted %d arguments for %s"):format(call_state.argument_count, call)
		)
		-- A Normal-mode test cursor cannot occupy the insertion cell just after
		-- EOL. Hide the fixture buffer so the renderer uses the supplied Insert
		-- cursor snapshot instead of that one-cell-short Normal cursor.
		vim.api.nvim_set_current_buf(source_buffer)
		local corrected =
			signature_renderer.normalize_signature_help({ bufnr = position_buffer, cursor = cursor }, cpp_overloads)
		vim.api.nvim_set_current_buf(position_buffer)
		assert(corrected ~= cpp_overloads, "Signature correction mutated the LSP response in place")
		assert(
			corrected.activeSignature == expected_signature and corrected.activeParameter == expected_parameter,
			("Signature correction chose overload %d parameter %d for %s"):format(
				corrected.activeSignature,
				corrected.activeParameter,
				call
			)
		)
		local selected = corrected.signatures[expected_signature + 1]
		assert(selected.label == label, "Signature correction selected the wrong overload for " .. call)
		assert(
			selected.activeParameter == expected_parameter,
			"Signature-local activeParameter still overrides the corrected live parameter"
		)
	end
	assert_corrected_call("foo(1, ", 1, 1, "int foo(int c, int d)")
	assert_corrected_call("foo(1, 2, ", 2, 2, "int foo(int e, int f, int g)")
	assert_corrected_call("foo(1, 2, 3, ", 3, 3, "int foo(int h, int i, int j, int k)")
	assert_corrected_call("foo(1.0f", 0, 0, "int foo(int b)")
	assert_corrected_call("foo(1.0f, ", 1, 1, "int foo(int c, int d)")
	assert_corrected_call("foo(\n  1,\n  2,\n  ", 2, 2, "int foo(int e, int f, int g)")
	assert_corrected_call("foo(std::pair<int, int>{1, 2}, ", 1, 1, "int foo(int c, int d)")
	local overflow_call = "int a = foo(a, d, f, g, h)"
	assert_corrected_call(overflow_call, 3, 4, "int foo(int h, int i, int j, int k)", { 1, #overflow_call - 1 }, 5)
	local complete_call = "foo(1, 2, 3)"
	local first_comma = assert(complete_call:find(",", 1, true))
	local second_comma = assert(complete_call:find(",", first_comma + 1, true))
	assert_corrected_call(complete_call, 2, 0, "int foo(int e, int f, int g)", { 1, first_comma - 1 }, 3)
	assert_corrected_call(complete_call, 2, 1, "int foo(int e, int f, int g)", { 1, second_comma - 1 }, 3)
	assert_corrected_call(complete_call, 2, 2, "int foo(int e, int f, int g)", { 1, #complete_call - 1 }, 3)
	assert(cpp_overloads.activeSignature == 1, "Overload correction changed the original activeSignature")
	assert(
		cpp_overloads.signatures[2].activeParameter == 1,
		"Parameter correction changed the original signature-local activeParameter"
	)

	vim.api.nvim_set_current_buf(source_buffer)
	vim.api.nvim_buf_delete(position_buffer, { force = true })
	local toggle_signature = completion_opts.keymap["<C-k>"][1]
	local requested_signature = false
	assert(
		toggle_signature({
			is_signature_visible = function()
				return false
			end,
			show_signature = function()
				requested_signature = true
				return true
			end,
		}),
		"C-k did not request a hidden signature"
	)
	assert(not requested_signature, "C-k touched signature UI synchronously inside its expression mapping")
	local blink_signature_config = require("blink.cmp.config").signature.window
	local blink_signature_window = require("blink.cmp.signature.window")
	local expanded_signature_height = vim.api.nvim_win_get_height(0)
	assert(
		vim.wait(200, function()
			return requested_signature
				and blink_signature_config.max_height == expanded_signature_height
				and blink_signature_window.win.config.max_height == expanded_signature_height
		end),
		"C-k did not expand signature help"
	)
	assert(
		toggle_signature({
			is_signature_visible = function()
				return true
			end,
		}),
		"C-k did not collapse an expanded signature"
	)
	assert(
		vim.wait(200, function()
			return blink_signature_config.max_height == 1 and blink_signature_window.win.config.max_height == 1
		end),
		"C-k did not restore compact signature help"
	)
	assert(
		toggle_signature({
			is_signature_visible = function()
				return false
			end,
			show_signature = function()
				return true
			end,
		}),
		"C-k did not re-expand signature help"
	)
	assert(
		vim.wait(200, function()
			return blink_signature_config.max_height == expanded_signature_height
				and blink_signature_window.win.config.max_height == expanded_signature_height
		end),
		"C-k did not re-expand signature help asynchronously"
	)
	require("blink.cmp.signature.trigger").hide_emitter:emit()
	assert(
		blink_signature_config.max_height == 1 and blink_signature_window.win.config.max_height == 1,
		"A new signature would inherit the previous expanded height"
	)
	local anchor_buffer = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_set_current_buf(anchor_buffer)
	local anchored_line = "outer(inner(value), other)"
	local anchored_start = assert(anchored_line:find("inner(", 1, true)) - 1
	local anchored_argument = anchored_start + #"inner("
	local anchored_row = 8
	local anchored_lines = vim.fn["repeat"]({ "" }, 15)
	anchored_lines[anchored_row] = anchored_line
	vim.api.nvim_buf_set_lines(anchor_buffer, 0, -1, false, anchored_lines)
	vim.bo[anchor_buffer].filetype = "python"
	vim.api.nvim_win_set_cursor(0, { anchored_row, anchored_argument })
	local anchored_context = {
		id = 91,
		bufnr = anchor_buffer,
		cursor = { anchored_row, anchored_argument },
		line = anchored_line,
		is_retrigger = false,
		trigger = { kind = 2, character = "(" },
	}
	local anchored_help = {
		activeSignature = 0,
		activeParameter = 0,
		signatures = {
			{ label = "inner(value: string)" },
			{ label = "inner(value: number)" },
		},
	}
	blink_signature_window.open_with_signature_help(anchored_context, anchored_help)
	signature_renderer.set_expanded(true)
	assert(blink_signature_window.win:is_open(), "C-k full signature fixture did not open")
	local full_indicator_namespace = vim.api.nvim_get_namespaces().user_blink_signature_full_indicator
	local full_indicator_marks = vim.api.nvim_buf_get_extmarks(
		blink_signature_window.win:get_buf(),
		full_indicator_namespace,
		0,
		-1,
		{ details = true }
	)
	assert(#full_indicator_marks == 2, "Full signature window does not mark every overload")
	for index, mark in ipairs(full_indicator_marks) do
		local indicator_chunk = mark[4].virt_text and mark[4].virt_text[1]
		assert(
			mark[2] == index - 1
				and indicator_chunk[1] == signature_renderer.indicator .. " "
				and indicator_chunk[2] == "BlinkCmpSignatureIndicator",
			"Full signature overload has an incorrect function marker"
		)
	end
	local anchored_window = blink_signature_window.win:get_win()
	assert(
		vim.api.nvim_win_get_width(anchored_window)
			>= #anchored_help.signatures[1].label + vim.fn.strdisplaywidth(signature_renderer.indicator .. " "),
		"Full signature window did not reserve room for its function marker"
	)
	local anchored_config = vim.api.nvim_win_get_config(anchored_window)
	assert(
		anchored_config.relative == "win"
			and anchored_config.win == vim.api.nvim_get_current_win()
			and vim.deep_equal(anchored_config.bufpos, { anchored_row - 1, anchored_start }),
		"Full signature window is not anchored to the function name"
	)
	vim.api.nvim_buf_set_text(
		anchor_buffer,
		anchored_row - 1,
		anchored_argument,
		anchored_row - 1,
		anchored_argument,
		{ "typed" }
	)
	blink_signature_window.update_position()
	local typed_config = vim.api.nvim_win_get_config(anchored_window)
	assert(
		vim.deep_equal(typed_config.bufpos, anchored_config.bufpos),
		"Full signature anchor moved while an argument was typed"
	)
	vim.api.nvim_win_set_cursor(0, { anchored_row, #vim.api.nvim_get_current_line() - 1 })
	blink_signature_window.update_position()
	local moved_config = vim.api.nvim_win_get_config(anchored_window)
	assert(
		moved_config.relative == "win"
			and moved_config.win == anchored_config.win
			and vim.deep_equal(moved_config.bufpos, anchored_config.bufpos)
			and moved_config.row == anchored_config.row
			and moved_config.col == anchored_config.col,
		"Full signature window followed the live cursor instead of its call anchor"
	)
	local completion_menu = require("blink.cmp.completion.windows.menu")
	completion_menu.win:open()
	completion_menu.win:set_height(3)
	vim.api.nvim_win_set_config(completion_menu.win:get_win(), {
		relative = "win",
		win = vim.api.nvim_get_current_win(),
		bufpos = { anchored_row - 1, anchored_argument },
		anchor = "NW",
		row = 1,
		col = 0,
	})
	blink_signature_window.update_position()
	local completion_below_config = vim.api.nvim_win_get_config(anchored_window)
	assert(
		completion_below_config.anchor == "SW" and completion_below_config.row == 0,
		"Full signature window did not move opposite a completion menu below the cursor"
	)
	vim.api.nvim_win_set_config(completion_menu.win:get_win(), {
		relative = "win",
		win = vim.api.nvim_get_current_win(),
		bufpos = { anchored_row - 1, anchored_argument },
		anchor = "SW",
		row = 0,
		col = 0,
	})
	blink_signature_window.update_position()
	local completion_above_config = vim.api.nvim_win_get_config(anchored_window)
	assert(
		completion_above_config.anchor == "NW" and completion_above_config.row == 1,
		"Full signature window did not move opposite a completion menu above the cursor"
	)
	completion_menu.win:close()
	signature_renderer.set_expanded(false)
	require("blink.cmp.signature.trigger").hide_emitter:emit()
	vim.api.nvim_set_current_buf(source_buffer)
	vim.api.nvim_buf_delete(anchor_buffer, { force = true })
	assert(plugins["lsp_signature.nvim"] == nil, "lsp_signature.nvim is still configured")
	assert(opts("nvim-notify").stages == "fade", "nvim-notify animation or frame was changed")
	assert(
		vim.api.nvim_get_hl(0, { name = "NotifyBackground", link = false }).bg
			== require("user.core.palette").get().panel,
		"nvim-notify background was changed"
	)

	-- Other application-sized overlays deliberately keep their framed layouts.
	assert(opts("fzf-lua").winopts.border == "rounded", "Fzf main window lost its panel border")
	local oil_opts = opts("oil.nvim")
	assert(oil_opts.float.border == "rounded", "Oil float lost its panel border")
	assert(type(oil_opts.keymaps["<Esc>"].callback) == "function", "Floating Oil cannot be closed with Escape")
	assert(opts("toggleterm.nvim").float_opts.border == "rounded", "Float terminal lost its panel border")
	local layout = require("user.core.layout")
	local mason_ui = opts("mason.nvim").ui
	local lazy_ui = require("lazy.core.config").options.ui
	assert(layout.manager_border == "none", "package managers still have a border or transparent shadow")
	assert(mason_ui.border == layout.manager_border, "Mason lost its borderless manager style")
	assert(lazy_ui.border == layout.manager_border, "Lazy lost its borderless manager style")
	local lazy_escape = vim.api.nvim_get_autocmds({ group = "user_lazy_escape", event = "FileType", pattern = "lazy" })
	assert(#lazy_escape == 1, "Lazy manager cannot be closed with Escape")
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
	assert(float_style.is_transient(small), "small third-party float is not dismissible")

	local large_buffer = vim.api.nvim_create_buf(false, true)
	local large_width = math.max(1, vim.o.columns - 4)
	local large_height = math.max(1, vim.o.lines - vim.o.cmdheight - 4)
	local large = open_float(large_buffer, large_width, large_height)
	vim.wait(50)
	assert(not float_style.is_padded(large), "application-sized float was mistaken for a popup")
	assert(not float_style.is_transient(large), "application-sized float is dismissible")

	local panel_buffer = vim.api.nvim_create_buf(false, true)
	vim.bo[panel_buffer].filetype = "Glance"
	local panel = open_float(panel_buffer, 24, 4)
	vim.wait(50)
	assert(not float_style.is_padded(panel), "small Glance pane lost its dedicated layout")
	assert(not float_style.is_transient(panel), "Glance application pane is dismissible as a popup")

	local popup_buffer = vim.api.nvim_create_buf(false, true)
	vim.bo[popup_buffer].filetype = "neo-tree-popup"
	local popup = open_float(popup_buffer, large_width, 4)
	assert(
		vim.wait(200, function()
			return float_style.is_padded(popup)
		end),
		"Neo-tree dialog fallback was not applied"
	)
	assert(float_style.is_transient(popup), "known large dialog is not dismissible")

	local notification_buffer = vim.api.nvim_create_buf(false, true)
	local notification = open_float(notification_buffer, 24, 4)
	vim.bo[notification_buffer].filetype = "notify"
	vim.wait(50)
	assert(not float_style.is_padded(notification), "generic popup styling changed nvim-notify")
	assert(not float_style.is_transient(notification), "notification bypasses its lifecycle-aware closer")

	local context_buffer = vim.api.nvim_create_buf(false, true)
	local context = open_float(context_buffer, 24, 2)
	vim.w[context].treesitter_context = true
	local scroll_buffer = vim.api.nvim_create_buf(false, true)
	local scroll = open_float(scroll_buffer, 1, 4)
	vim.w[scroll].scrollview_key = "scrollview_val"
	vim.wait(50)
	assert(not float_style.is_transient(context), "Tree-sitter Context was mistaken for a popup")
	assert(not float_style.is_transient(scroll), "scrollview rail was mistaken for a popup")

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

	local notify = package.loaded.notify
	local dismiss = notify and notify.dismiss
	local notification_dismissed = false
	if notify then
		notify.dismiss = function(...)
			notification_dismissed = true
			return dismiss(...)
		end
	end
	assert(require("user.core.popups").close(), "unified popup closer found no transient windows")
	if notify then
		notify.dismiss = dismiss
	end
	assert(not notification_dismissed, "Escape dismissed an auto-expiring notification")
	assert(not vim.api.nvim_win_is_valid(small), "Escape fallback left a small popup open")
	assert(not vim.api.nvim_win_is_valid(popup), "Escape fallback left a known dialog open")
	for label, winid in pairs({
		application = large,
		context = context,
		glance = panel,
		notification = notification,
		scrollview = scroll,
	}) do
		assert(vim.api.nvim_win_is_valid(winid), "popup closer incorrectly closed " .. label)
	end

	for _, winid in ipairs({
		small,
		large,
		panel,
		popup,
		notification,
		context,
		scroll,
		lazy_window,
		mason_window,
		backdrop,
	}) do
		if vim.api.nvim_win_is_valid(winid) then
			vim.api.nvim_win_close(winid, true)
		end
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
