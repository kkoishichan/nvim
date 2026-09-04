local M = {}

local padded_border = { " ", "", "", " ", "", "", " ", " " }

local window_roles = require("user.core.window_roles")

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

---Whether a window is a short-lived popup that Esc may safely dismiss.
---Application panels, terminals, notifications, backdrops, and editor chrome
---are deliberately excluded; notification plugins need their own close API.
function M.is_transient(winid)
	if not winid or not vim.api.nvim_win_is_valid(winid) then
		return false
	end
	return vim.api.nvim_win_get_config(winid).relative ~= "" and window_roles.is_transient(winid)
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

---Style transient windows identified by ownership, preserving editable floats.
---The legacy function name remains available to plugin integrations.
function M.style_if_small(winid)
	if not winid or not vim.api.nvim_win_is_valid(winid) then
		return false
	end
	if M.is_transient(winid) then
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
		pattern = { "dap-float", "neotest-output", "neo-tree-popup", "trouble" },
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
