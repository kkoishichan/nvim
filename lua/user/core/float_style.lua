local M = {}

local padded_border = { " ", "", "", " ", "", "", " ", " " }

-- These are workspace-sized applications rather than transient popups. They
-- keep their own layout and border treatment even if the terminal is small.
local panel_filetypes = {
	Glance = true,
	["fzflua_backdrop"] = true,
	fzf = true,
	lazy = true,
	["lazy_backdrop"] = true,
	lazygit = true,
	mason = true,
	["mason_backdrop"] = true,
	["neo-tree"] = true,
	["neo-tree-preview"] = true,
	oil = true,
	["snacks_dashboard"] = true,
}

-- Notifications keep nvim-notify's own animation, colours, and frame. They are
-- intentionally outside the generic small-popup fallback.
local untouched_filetypes = {
	notify = true,
	["snacks_notif"] = true,
}

local popup_filetypes = {
	["neo-tree-popup"] = true,
	trouble = true,
}

local styled_window_highlights = {
	Normal = "Pmenu",
	NormalFloat = "Pmenu",
	NormalNC = "Pmenu",
	FloatBorder = "Pmenu",
	FloatTitle = "Pmenu",
	EndOfBuffer = "Pmenu",
}

local function border_character(item)
	return type(item) == "table" and item[1] or item
end

local function merge_winhighlight(current)
	local entries = {}
	for entry in (current or ""):gmatch("[^,]+") do
		local source = entry:match("^([^:]+):")
		if not styled_window_highlights[source] then
			entries[#entries + 1] = entry
		end
	end
	for _, source in ipairs({ "Normal", "NormalFloat", "NormalNC", "FloatBorder", "FloatTitle", "EndOfBuffer" }) do
		entries[#entries + 1] = source .. ":" .. styled_window_highlights[source]
	end
	return table.concat(entries, ",")
end

local function is_panel(winid)
	local bufnr = vim.api.nvim_win_get_buf(winid)
	local filetype = vim.bo[bufnr].filetype
	if vim.bo[bufnr].buftype == "terminal" or panel_filetypes[filetype] or untouched_filetypes[filetype] then
		return true
	end
	-- Glance's preview shows the source buffer's real filetype, so its window
	-- highlight is the reliable way to distinguish it from an LSP hover.
	return vim.wo[winid].winhighlight:find("Glance", 1, true) ~= nil
end

local function is_small_float(winid)
	local config = vim.api.nvim_win_get_config(winid)
	if config.relative == "" or is_panel(winid) then
		return false
	end
	local max_width = math.min(100, math.max(30, math.floor(vim.o.columns * 0.72)))
	local usable_lines = math.max(1, vim.o.lines - vim.o.cmdheight)
	local max_height = math.min(24, math.max(6, math.floor(usable_lines * 0.55)))
	return config.width <= max_width and config.height <= max_height
end

---Return a fresh copy suitable for plugin options that accept an 8-part border.
function M.border()
	return vim.deepcopy(padded_border)
end

---Build a borderless floating-window config with one cell of horizontal
---padding. The padding and body share Pmenu, so no frame is visible.
function M.padded(config)
	return vim.tbl_deep_extend("force", {
		border = M.border(),
		style = "minimal",
	}, config or {})
end

---Whether a window already uses the shared borderless padded border.
function M.is_padded(winid)
	if not winid or not vim.api.nvim_win_is_valid(winid) then
		return false
	end
	local border = vim.api.nvim_win_get_config(winid).border
	if type(border) ~= "table" or #border ~= #padded_border then
		return false
	end
	for index, expected in ipairs(padded_border) do
		if border_character(border[index]) ~= expected then
			return false
		end
	end
	return true
end

---Apply the shared border and Pmenu background after a popup is created.
function M.apply_padded(winid)
	if not winid or not vim.api.nvim_win_is_valid(winid) then
		return false
	end
	local config = vim.api.nvim_win_get_config(winid)
	if config.relative == "" then
		return false
	end
	pcall(vim.api.nvim_win_set_config, winid, { border = M.border() })
	vim.wo[winid].winblend = 0
	vim.wo[winid].winhighlight = merge_winhighlight(vim.wo[winid].winhighlight)
	return true
end

---Apply the style only when the window is already opted in or is genuinely a
---small transient float. The size guard keeps application-like panels intact.
function M.style_if_small(winid)
	if not winid or not vim.api.nvim_win_is_valid(winid) then
		return false
	end
	local bufnr = vim.api.nvim_win_get_buf(winid)
	local config = vim.api.nvim_win_get_config(winid)
	local known_popup = config.relative ~= "" and popup_filetypes[vim.bo[bufnr].filetype]
	if M.is_padded(winid) or known_popup or is_small_float(winid) then
		return M.apply_padded(winid)
	end
	return false
end

---Catch plugin popups that do not expose a border option. Explicit plugin
---settings still use border()/padded(); this is only the constrained fallback.
function M.setup()
	local group = vim.api.nvim_create_augroup("user_small_float_style", { clear = true })
	vim.api.nvim_create_autocmd("WinNew", {
		group = group,
		callback = function()
			vim.schedule(function()
				for _, winid in ipairs(vim.api.nvim_list_wins()) do
					M.style_if_small(winid)
				end
			end)
		end,
	})
	-- Some plugins assign the popup filetype after creating the window. Recheck
	-- just those late-bound cases without adding work to normal buffer events.
	vim.api.nvim_create_autocmd("FileType", {
		group = group,
		pattern = { "dap-float", "neo-tree-popup", "trouble" },
		callback = function(event)
			vim.schedule(function()
				if not vim.api.nvim_buf_is_valid(event.buf) then
					return
				end
				for _, winid in ipairs(vim.fn.win_findbuf(event.buf)) do
					M.style_if_small(winid)
				end
			end)
		end,
	})
end

return M
