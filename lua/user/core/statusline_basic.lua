-- Native statusline for fast mode: the current mode, the file with its
-- modified/readonly flags, attached servers, diagnostics and cursor position.
-- Server status is computed in one call, without a timer or component pipeline.

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

function M.status()
	local clients = vim.lsp.get_clients({ bufnr = 0 })
	if #clients == 0 then
		return ""
	end
	local client_names = {}
	for _, client in ipairs(clients) do
		client_names[#client_names + 1] = client.name:gsub("%%", "%%%%")
	end
	table.sort(client_names)
	local counts = vim.diagnostic.count(0)
	return (" %s E:%d W:%d "):format(
		table.concat(client_names, ","),
		counts[vim.diagnostic.severity.ERROR] or 0,
		counts[vim.diagnostic.severity.WARN] or 0
	)
end

rawset(vim, "_user_statusline_status", M.status)

---Statusline expression, with an optional right-aligned badge such as FAST.
---@param badge string|nil
function M.value(badge)
	return table.concat({
		" %{v:lua.vim._user_statusline_mode()} ",
		"%<%f %m%r%h%w",
		"%=",
		badge and ("%#StatusLineNC# " .. badge .. " %#StatusLine#") or "",
		"%{%v:lua.vim._user_statusline_status()%}",
		" %l:%-3c %P ",
	})
end

return M
