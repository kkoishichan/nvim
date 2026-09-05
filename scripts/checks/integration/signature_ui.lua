return function()
	local plugins = require("lazy.core.config").plugins
	local plugin = require("lazy.core.plugin")
	local function opts(name)
		return plugin.values(assert(plugins[name], "missing plugin: " .. name), "opts", false)
	end
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
end
