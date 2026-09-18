return function(_)
	require("lazy").load({ plugins = { "blink.cmp" } })
	local api = vim.api
	local signature = require("user.core.blink_signature")
	local window = require("blink.cmp.signature.window")
	local blink = require("blink.cmp")
	assert(signature.setup())
	local original_win = api.nvim_get_current_win()
	local bufnr = api.nvim_create_buf(false, true)
	local winid = api.nvim_open_win(bufnr, true, {
		relative = "editor",
		row = 1,
		col = 1,
		width = 44,
		height = 12,
		style = "minimal",
	})
	vim.wo.wrap = false
	vim.wo.scrolloff = 0
	local lines = vim.fn["repeat"]({ "" }, 30)
	lines[10] = "    build(1, 2, value)"
	api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	api.nvim_win_set_cursor(winid, { 10, #lines[10] - 1 })
	vim.fn.winrestview({ topline = 5 })
	local context = { id = 901, bufnr = bufnr, cursor = api.nvim_win_get_cursor(winid) }
	local help = {
		activeSignature = 0,
		activeParameter = 2,
		signatures = {
			{
				label = "build(first: SomeVeryLongType, second: AnotherLongType, value: string)",
				parameters = {
					{ label = "first: SomeVeryLongType" },
					{ label = "second: AnotherLongType" },
					{ label = "value: string" },
				},
			},
		},
	}
	local namespace = api.nvim_get_namespaces().user_blink_signature
	local function card()
		local marks = api.nvim_buf_get_extmarks(bufnr, namespace, 0, -1, { details = true })
		assert(#marks == 1, "Visible signature did not have exactly one card")
		local text, highlighted = "", ""
		for _, chunk in ipairs(marks[1][4].virt_text) do
			text = text .. chunk[1]
			if type(chunk[2]) == "table" and vim.tbl_contains(chunk[2], "BlinkCmpSignatureHelpActiveParameter") then
				highlighted = highlighted .. chunk[1]
			end
		end
		local row = marks[1][2]
		local source = api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
		assert(
			vim.fn.strdisplaywidth(source .. text) <= api.nvim_win_get_width(winid),
			"Card overflowed its source window"
		)
		return row, text, highlighted
	end
	window.open_with_signature_help(context, help)
	local row, text, highlighted = card()
	assert(row == 8 and text:find("…", 1, true), "Long signature was not visibly shortened")
	assert(highlighted == "value: string", "Narrow card lost its complete current parameter")
	api.nvim_win_set_width(winid, 32)
	api.nvim_exec_autocmds("WinResized", { group = "user_blink_signature_virtual" })
	vim.wait(50, function()
		return false
	end, 10)
	_, _, highlighted = card()
	assert(highlighted == "value: string", "Resizing lost a parameter that still fits")

	-- Scrolling without typing must relocate the extmark into the viewport.
	vim.cmd("normal! zt")
	api.nvim_exec_autocmds("WinScrolled", { group = "user_blink_signature_virtual", pattern = tostring(winid) })
	assert(
		vim.wait(100, function()
			return card() == 10
		end),
		"Scrolling left the card above the viewport"
	)
	local original_menu = blink.is_menu_visible
	blink.is_menu_visible = function()
		return true
	end
	api.nvim_exec_autocmds("User", { group = "user_blink_signature_virtual", pattern = "BlinkCmpShow" })
	assert(
		vim.wait(100, function()
			return card() == 9
		end),
		"Completion did not displace an existing below card"
	)
	blink.is_menu_visible = original_menu

	-- Compact and expanded views must agree on a multiline UTF-16 parameter.
	api.nvim_win_set_width(winid, 60)
	lines[10] = "f(value)"
	api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	api.nvim_win_set_cursor(winid, { 10, 6 })
	vim.fn.winrestview({ topline = 5 })
	context = { id = 902, bufnr = bufnr, cursor = api.nvim_win_get_cursor(winid) }
	local label = "f(\r\n  名字: str,\r\n  n: int\r\n)"
	local start_byte = assert(label:find("名字: str", 1, true)) - 1
	local end_byte = start_byte + #"名字: str"
	help = {
		activeParameter = 0,
		signatures = {
			{
				label = label,
				parameters = {
					{
						label = {
							vim.str_utfindex(label, "utf-16", start_byte),
							vim.str_utfindex(label, "utf-16", end_byte),
						},
					},
				},
			},
		},
	}
	window.open_with_signature_help(context, help)
	_, _, highlighted = card()
	assert(highlighted == "名字: str", "Compact multiline Unicode parameter was not highlighted")
	signature.set_expanded(true)
	assert(window.win:is_open(), "Expanded Unicode signature did not open")
	local popup_buf = window.win:get_buf()
	local full_namespace = api.nvim_get_namespaces().user_blink_signature_full_parameter
	local marks = api.nvim_buf_get_extmarks(popup_buf, full_namespace, 0, -1, { details = true })
	assert(#marks == 1, "Expanded parameter mark is missing or duplicated")
	local mark = marks[1]
	local marked = api.nvim_buf_get_text(popup_buf, mark[2], mark[3], mark[4].end_row, mark[4].end_col, {})
	assert(table.concat(marked) == "名字: str", "Expanded UTF-16 parameter range disagrees with compact view")
	assert(
		help.signatures[1].activeParameter == nil and help.activeParameter == 0,
		"Rendering changed the server response"
	)

	-- Model the insertion cursor at EOL with virtualedit=onemore. A signature
	-- must not become part of that cursor's display column or scroll the source
	-- viewport, even when the card occupies the cursor's neighbouring line.
	signature.set_expanded(false)
	api.nvim_win_set_width(winid, 44)
	vim.wo.virtualedit = "onemore"
	vim.wo.sidescrolloff = 8
	vim.bo[bufnr].tabstop = 4
	local trigger = require("blink.cmp.signature.trigger")
	local blocked = string.rep("x", 140)
	local cases = {
		{ name = "same line", lines = { blocked, "call(value", blocked }, row = 2 },
		{ name = "cursor on neighbour", lines = { blocked, "    call(", "  " }, row = 3 },
		{ name = "tabs and Unicode", lines = { blocked, "\t界call(value", blocked }, row = 2 },
		{
			name = "horizontal viewport",
			lines = { blocked, "call(" .. string.rep("x", 60), blocked },
			row = 2,
			leftcol = 35,
		},
		{ name = "wrapped line", lines = { blocked, string.rep("x", 48) .. "(value", blocked }, row = 2, wrap = true },
	}
	local function source_view()
		return {
			view = vim.fn.winsaveview(),
			cursor = api.nvim_win_get_cursor(winid),
			column = vim.fn.virtcol("."),
			row = vim.fn.winline(),
		}
	end
	help = {
		signatures = {
			{
				label = "call(value: SomeVeryLongType, other: string)",
				parameters = { { label = "value: SomeVeryLongType" } },
			},
		},
	}
	for index, case in ipairs(cases) do
		trigger.hide_emitter:emit()
		vim.wo.wrap = case.wrap or false
		api.nvim_buf_set_lines(bufnr, 0, -1, false, case.lines)
		api.nvim_win_set_cursor(winid, { case.row, #case.lines[case.row] })
		vim.fn.winrestview({ topline = 1, leftcol = case.leftcol or 0, skipcol = 0 })
		vim.cmd("redraw!")
		local expected = source_view()
		context = { id = 910 + index, bufnr = bufnr, cursor = api.nvim_win_get_cursor(winid) }
		for _ = 1, 3 do
			window.open_with_signature_help(context, help)
			vim.cmd("redraw!")
			assert(#api.nvim_buf_get_extmarks(bufnr, namespace, 0, -1, {}) == 1, case.name .. ": signature is missing")
			assert(
				vim.deep_equal(source_view(), expected),
				case.name .. ": showing a signature moved the source view/cursor"
			)
			trigger.hide_emitter:emit()
			vim.cmd("redraw!")
			assert(
				vim.deep_equal(source_view(), expected),
				case.name .. ": hiding a signature moved the source view/cursor"
			)
		end
	end

	signature.teardown()
	api.nvim_win_close(winid, true)
	api.nvim_set_current_win(original_win)
	api.nvim_buf_delete(bufnr, { force = true })
end
