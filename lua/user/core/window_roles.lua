local M = {}

local roles = {
	editor = true,
	panel = true,
	transient = true,
	editor_float = true,
	manager = true,
	chrome = true,
	notification = true,
}

local panels = {
	["neo-tree"] = true,
	["neo-tree-preview"] = true,
	Outline = true,
	Glance = true,
	OverseerList = true,
	OverseerOutput = true,
	["neotest-summary"] = true,
	["neotest-output-panel"] = true,
	["dap-repl"] = true,
	qf = true,
	toggleterm = true,
}
local managers = {
	lazy = true,
	mason = true,
	fzf = true,
	lazygit = true,
	oil = true,
	["snacks_dashboard"] = true,
}
local transient = {
	["dap-float"] = true,
	["neotest-output"] = true,
	["neo-tree-popup"] = true,
}

---Mark windows whose role cannot be inferred from their buffer (e.g. previews
---showing an ordinary file buffer). Pass nil to restore automatic detection.
function M.mark(winid, role)
	if not vim.api.nvim_win_is_valid(winid) then
		return false
	end
	assert(role == nil or roles[role], "Unknown window role: " .. tostring(role))
	vim.w[winid].user_window_role = role
	return true
end

---Classify by ownership and editability, never by a floating window's size.
function M.get(winid)
	winid = (winid == nil or winid == 0) and vim.api.nvim_get_current_win() or winid
	if not winid or not vim.api.nvim_win_is_valid(winid) then
		return nil
	end
	local explicit = vim.w[winid].user_window_role
	if roles[explicit] then
		return explicit
	end
	local bufnr = vim.api.nvim_win_get_buf(winid)
	local ft, bt = vim.bo[bufnr].filetype, vim.bo[bufnr].buftype
	local floating = vim.api.nvim_win_get_config(winid).relative ~= ""
	if
		vim.w[winid].treesitter_context
		or vim.w[winid].treesitter_context_line_number
		or vim.w[winid].scrollview_key == "scrollview_val"
		or ft:match("_backdrop$")
	then
		return "chrome"
	end
	if ft == "notify" or ft == "snacks_notif" then
		return "notification"
	end
	if managers[ft] or ft:match("^snacks_picker_") then
		return "manager"
	end
	if bt == "terminal" or panels[ft] or ft:match("^dapui_") or vim.wo[winid].winhighlight:find("Glance", 1, true) then
		return "panel"
	end
	if ft == "trouble" then
		return floating and "transient" or "panel"
	end
	if not floating then
		return (bt == "" or bt == "acwrite") and "editor" or "panel"
	end
	if vim.w[winid].lsp_floating_bufnr or transient[ft] or ft:match("^blink%-cmp%-") then
		return "transient"
	end
	-- A border is styling, not consent to discard an editable window. New
	-- scratch floats are editable too, even before they contain any text.
	if vim.bo[bufnr].modifiable or vim.bo[bufnr].modified or vim.api.nvim_buf_get_name(bufnr) ~= "" then
		return "editor_float"
	end
	return "transient"
end

function M.is_editor(winid)
	local role = M.get(winid)
	return role == "editor" or role == "editor_float"
end

function M.is_transient(winid)
	return M.get(winid) == "transient"
end

function M.is_panel(winid)
	local role = M.get(winid)
	return role == "panel" or role == "manager"
end

return M
