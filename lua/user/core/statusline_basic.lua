-- Native statusline for fast mode: the current mode, the file with its
-- modified/readonly flags, and the cursor position. Everything except the mode
-- name is a built-in '%' item, so a redraw costs one Lua call that reads one
-- value; there is no component pipeline, no Git query and no diagnostic count.

local M = {}

local names = {
	n = "NORMAL",
	no = "PENDING",
	nov = "PENDING",
	noV = "PENDING",
	niI = "NORMAL",
	niR = "NORMAL",
	niV = "NORMAL",
	nt = "NORMAL",
	v = "VISUAL",
	vs = "VISUAL",
	V = "V-LINE",
	Vs = "V-LINE",
	["\22"] = "V-BLOCK",
	["\22s"] = "V-BLOCK",
	s = "SELECT",
	S = "S-LINE",
	["\19"] = "S-BLOCK",
	i = "INSERT",
	ic = "INSERT",
	ix = "INSERT",
	R = "REPLACE",
	Rc = "REPLACE",
	Rx = "REPLACE",
	Rv = "V-REPLACE",
	c = "COMMAND",
	cv = "EX",
	r = "PROMPT",
	rm = "MORE",
	["r?"] = "CONFIRM",
	["!"] = "SHELL",
	t = "TERMINAL",
}

function M.mode()
	return names[vim.api.nvim_get_mode().mode] or "NORMAL"
end

rawset(vim, "_user_statusline_mode", M.mode)

---Statusline expression, with an optional right-aligned badge such as FAST.
---@param badge string|nil
function M.value(badge)
	return table.concat({
		" %{v:lua.vim._user_statusline_mode()} ",
		"%<%f %m%r%h%w",
		"%=",
		badge and ("%#StatusLineNC# " .. badge .. " %#StatusLine#") or "",
		" %l:%-3c %P ",
	})
end

return M
