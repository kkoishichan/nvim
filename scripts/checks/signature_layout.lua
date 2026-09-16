return function(_)
	local layout = require("user.core.signature.layout")
	local api = vim.api
	local original_win = api.nvim_get_current_win()
	local original_blink = package.loaded["blink.cmp"]
	local blink = original_blink or {}
	local original_menu_visible = blink.is_menu_visible
	local menu_visible = false
	blink.is_menu_visible = function()
		return menu_visible
	end
	package.loaded["blink.cmp"] = blink
	local bufnr = api.nvim_create_buf(false, true)
	local winid = api.nvim_open_win(bufnr, true, {
		relative = "editor",
		row = 1,
		col = 1,
		width = 48,
		height = 10,
		style = "minimal",
	})
	vim.wo.wrap = false
	vim.wo.foldmethod = "manual"
	vim.wo.foldenable = true
	vim.wo.scrolloff = 0
	vim.wo.sidescrolloff = 0
	local function reset()
		menu_visible = false
		vim.cmd("normal! zE")
		local lines = {}
		for _ = 1, 40 do
			lines[#lines + 1] = ""
		end
		lines[10] = "    call(value)"
		api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
		api.nvim_win_set_cursor(winid, { 10, 8 })
		vim.fn.winrestview({ topline = 6, leftcol = 0 })
	end
	local function position(preferred)
		return layout.virtual_position(bufnr, { 10, 8 }, preferred)
	end
	reset()
	local row, padding, side, budget = position()
	assert(row == 8 and padding == string.rep(" ", 8) and side == -1, "Ordinary placement changed")
	assert(budget == 40, "Card budget did not subtract its display column")

	-- A call at the viewport's first/last row must not select the physical
	-- neighbour outside the screen, even when that side was previously kept.
	vim.cmd("normal! zt")
	assert(vim.fn.line("w0") == 10, "Top-edge fixture did not scroll")
	row, _, side = position(-1)
	assert(row == 10 and side == 1, "Top-edge card was placed above the viewport")
	reset()
	vim.cmd("normal! zb")
	assert(vim.fn.line("w$") == 10, "Bottom-edge fixture did not scroll")
	row, _, side = position(1)
	assert(row == 8 and side == -1, "Bottom-edge card was placed below the viewport")

	-- Both fold interiors and their closed header lines are unavailable.
	reset()
	vim.cmd("8,9fold")
	row, _, side = position(-1)
	assert(row == 10 and side == 1, "Card was placed inside a closed fold")
	reset()
	api.nvim_buf_set_lines(bufnr, 8, 9, false, { "previous_line_is_too_long" })
	vim.cmd("11,12fold")
	row, _, side = position(1)
	assert(row == 9 and side == 0, "Card was placed on a closed fold header")
	assert(layout.available_width(bufnr, 10, 8) == 0, "Closed fold received a visible width budget")

	-- Opening completion must invalidate a remembered below position as well
	-- as a fresh below candidate. The inline fallback remains stable.
	reset()
	api.nvim_buf_set_lines(bufnr, 8, 9, false, { "previous_line_is_too_long" })
	row, _, side = position()
	assert(row == 10 and side == 1, "Menu fixture did not initially choose below")
	menu_visible = true
	row, padding, side = position(side)
	assert(row == 9 and padding == "" and side == 0, "Remembered below card did not avoid completion")
	menu_visible = false
	row, _, side = position(0)
	assert(row == 9 and side == 0, "Existing inline-side stability changed")
	api.nvim_buf_set_lines(bufnr, 8, 9, false, { "" })
	menu_visible = true
	row, _, side = position(1)
	assert(row == 8 and side == -1, "Remembered below card did not reuse available above space")

	-- Width is measured in source-window cells, including its actual gutter.
	reset()
	vim.wo.number = true
	vim.wo.numberwidth = 4
	vim.wo.signcolumn = "yes"
	vim.wo.foldcolumn = "1"
	local gutter = vim.fn.getwininfo(winid)[1].textoff
	assert(gutter > 0, "Gutter fixture has no gutter")
	assert(layout.available_width(bufnr, 9, 8) == 48 - gutter - 8, "Width ignored the source window gutter")
	api.nvim_win_set_width(winid, 30)
	assert(layout.available_width(bufnr, 9, 8) == 30 - gutter - 8, "Width was stale after resizing")
	vim.wo.number = false
	vim.wo.signcolumn = "no"
	vim.wo.foldcolumn = "0"
	api.nvim_win_set_width(winid, 48)

	-- A scrolled window has more space to the right of a still-visible call;
	-- an anchor already left of the viewport pads neighbours to its left edge.
	reset()
	api.nvim_buf_set_lines(bufnr, 9, 10, false, { string.rep(" ", 20) .. "call(" .. string.rep("x", 70) .. ")" })
	api.nvim_win_set_cursor(winid, { 10, 45 })
	vim.fn.winrestview({ topline = 6, leftcol = 12 })
	assert(vim.fn.winsaveview().leftcol == 12, "Horizontal fixture did not scroll")
	row, padding, side, budget = layout.virtual_position(bufnr, { 10, 20 })
	assert(row == 8 and side == -1 and #padding == 20 and budget == 40, "Visible anchor ignored horizontal scrolling")
	row, padding, side, budget = layout.virtual_position(bufnr, { 10, 4 })
	assert(
		row == 8 and side == -1 and #padding == 12 and budget == 48,
		"Scrolled-out anchor did not keep the card visible"
	)
	assert(layout.available_width(bufnr, 8, 4) == 0, "A clipped card start received a width budget")
	assert(layout.available_width(bufnr, 8, 80) == 0, "Offscreen right start received a negative/nonzero budget")

	-- Display columns account for tabs/wide characters using this buffer's
	-- settings, and geometry follows the active split when it shows the buffer.
	reset()
	vim.bo[bufnr].tabstop = 4
	api.nvim_buf_set_lines(bufnr, 9, 10, false, { "\t界call(value)" })
	row, padding, side, budget = layout.virtual_position(bufnr, { 10, 4 })
	assert(row == 8 and side == -1 and #padding == 6 and budget == 42, "Display width treated bytes as cells")
	local second = api.nvim_open_win(bufnr, true, {
		relative = "editor",
		row = 2,
		col = 2,
		width = 24,
		height = 8,
		style = "minimal",
	})
	vim.wo.wrap = false
	vim.wo.scrolloff = 0
	api.nvim_win_set_cursor(second, { 10, 4 })
	vim.fn.winrestview({ topline = 6, leftcol = 0 })
	assert(layout.available_width(bufnr, 9, 6) == 18, "Geometry used another window displaying the same buffer")
	api.nvim_win_close(second, true)
	api.nvim_set_current_win(winid)

	reset()
	vim.wo.wrap = true
	api.nvim_buf_set_lines(bufnr, 8, 9, false, { string.rep("x", 53) })
	local eol = vim.fn.screenpos(winid, 9, 54)
	local right = api.nvim_win_get_position(winid)[2] + api.nvim_win_get_width(winid)
	assert(eol.row > 0 and eol.col > 0, "Wrapped-line fixture was not visible")
	assert(layout.available_width(bufnr, 8, 53) == right - eol.col + 1, "Wrapped EOL width ignored its screen row")

	api.nvim_win_close(winid, true)
	api.nvim_set_current_win(original_win)
	assert(layout.available_width(bufnr, 9, 0) == 0, "Hidden buffer received a visible budget")
	api.nvim_buf_delete(bufnr, { force = true })
	blink.is_menu_visible = original_menu_visible
	package.loaded["blink.cmp"] = original_blink
end
