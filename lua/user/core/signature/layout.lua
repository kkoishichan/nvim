local M = {}
local api = vim.api

local function source_window(bufnr)
	local current = api.nvim_get_current_win()
	if api.nvim_win_get_buf(current) == bufnr then
		return current
	end
	local winid = vim.fn.bufwinid(bufnr)
	return winid ~= -1 and winid or nil
end

local function completion_visible()
	local blink = package.loaded["blink.cmp"]
	if blink and type(blink.is_menu_visible) == "function" then
		local ok, visible = pcall(blink.is_menu_visible)
		if ok and visible then
			return true
		end
	end
	return vim.fn.pumvisible() == 1
end

-- Called in the source window so folds, tabs and the view belong to that
-- window, including when another split displays the same buffer.
local function geometry(winid)
	local info = vim.fn.getwininfo(winid)[1]
	return {
		winid = winid,
		first = vim.fn.line("w0") - 1,
		last = vim.fn.line("w$") - 1,
		leftcol = vim.fn.winsaveview().leftcol,
		width = math.max(0, api.nvim_win_get_width(winid) - info.textoff),
		wrap = vim.wo.wrap,
	}
end

local function visible(view, row)
	return row >= view.first and row <= view.last and vim.fn.foldclosed(row + 1) == -1
end

local function width_at(view, bufnr, row, start_column)
	if not visible(view, row) then
		return 0
	end
	if not view.wrap then
		-- A card that begins left of the viewport would lose its marker and
		-- leading text. Neighbour placement adds padding to avoid that case.
		if start_column < view.leftcol then
			return 0
		end
		return math.max(0, view.width - (start_column - view.leftcol))
	end
	local line = api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
	local eol = vim.fn.screenpos(view.winid, row + 1, #line + 1)
	if eol.row == 0 or eol.col == 0 then
		return 0
	end
	local right = api.nvim_win_get_position(view.winid)[2] + api.nvim_win_get_width(view.winid)
	local padding = math.max(0, start_column - vim.fn.strdisplaywidth(line))
	return math.max(0, right - eol.col + 1 - padding)
end

---Available cells from a zero-based display column to the source window edge.
---Returns zero for hidden/folded rows and starts left of a scrolled viewport.
---@param bufnr integer
---@param row integer Zero-based buffer row.
---@param start_column integer Zero-based display column, including any padding.
---@return integer
function M.available_width(bufnr, row, start_column)
	local winid = source_window(bufnr)
	if not winid then
		return 0
	end
	return api.nvim_win_call(winid, function()
		return width_at(geometry(winid), bufnr, row, start_column)
	end)
end

---Choose a visible, unfolded neighbouring line, retaining its side when safe.
---The fourth return is the card's cell budget, excluding alignment padding.
---@param bufnr integer
---@param anchor integer[] One-based row and zero-based byte column.
---@param preferred_side? integer -1 above, 0 current line, 1 below.
---@param fallback_row? integer Zero-based live cursor row for the inline case.
---@return integer row
---@return string padding
---@return integer side
---@return integer width
function M.virtual_position(bufnr, anchor, preferred_side, fallback_row)
	local anchor_row = anchor[1] - 1
	fallback_row = fallback_row or anchor_row
	local winid = source_window(bufnr)
	if not winid then
		return fallback_row, "", 0, 0
	end
	local result = api.nvim_win_call(winid, function()
		local view = geometry(winid)
		local line_count = api.nvim_buf_line_count(bufnr)
		local anchor_line = api.nvim_buf_get_lines(bufnr, anchor_row, anchor_row + 1, false)[1] or ""
		local anchor_width = vim.fn.strdisplaywidth(anchor_line:sub(1, anchor[2]))
		local target_column = math.max(anchor_width, view.wrap and 0 or view.leftcol)
		local menu_visible = completion_visible()
		local function candidate(side)
			local row = anchor_row + side
			if row < 0 or row >= line_count or not visible(view, row) or (side == 1 and menu_visible) then
				return nil
			end
			local line = api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
			local line_width = vim.fn.strdisplaywidth(line)
			if line_width > anchor_width then
				return nil
			end
			return string.rep(" ", target_column - line_width)
		end

		if preferred_side ~= 0 then
			local sides = preferred_side == 1 and { 1, -1 } or { -1, 1 }
			for _, side in ipairs(sides) do
				local padding = candidate(side)
				if padding then
					return { anchor_row + side, padding, side, width_at(view, bufnr, anchor_row + side, target_column) }
				end
			end
		end
		local line = api.nvim_buf_get_lines(bufnr, fallback_row, fallback_row + 1, false)[1] or ""
		return { fallback_row, "", 0, width_at(view, bufnr, fallback_row, vim.fn.strdisplaywidth(line)) }
	end)
	return unpack(result)
end

return M
