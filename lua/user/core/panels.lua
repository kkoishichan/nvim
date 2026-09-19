local M = {}

-- Left sidebar is reserved for the tree (neo-tree); oil is a buffer-style
-- directory editor and opens full-window (in-place), not in a side panel.
M.left_panel_width = 34
local scheduled = false
local applying = false
local generation = 0
local left = { ["neo-tree"] = true, Outline = true, ["neotest-summary"] = true }
local bottom = {
	toggleterm = true,
	trouble = true,
	OverseerList = true,
	OverseerOutput = true,
	qf = true,
	["neotest-output"] = true,
	["neotest-output-panel"] = true,
	daprepl = true,
	["dap-repl"] = true,
	dapui_console = true,
}

function M.side(winid)
	if not vim.api.nvim_win_is_valid(winid) or vim.api.nvim_win_get_config(winid).relative ~= "" then
		return nil
	end
	local bufnr = vim.api.nvim_win_get_buf(winid)
	local filetype = vim.bo[bufnr].filetype
	if vim.b[bufnr].user_ai_terminal or vim.b[bufnr].codex_terminal then
		return "right"
	elseif left[filetype] or (filetype:match("^dapui_") and not bottom[filetype]) then
		return "left"
	elseif bottom[filetype] or vim.bo[bufnr].buftype == "terminal" then
		return "bottom"
	end
end

local function windows()
	local result = {}
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		local side = M.side(win)
		if side then
			result[#result + 1] = { win = win, side = side }
		end
	end
	return result
end

---Share the horizontal budget across both sidebars; bottom views share a dock.
---Return zero for a sidebar that cannot coexist with a usable editor.
function M.budget(columns, lines, present, preferred)
	columns, lines = columns or vim.o.columns, lines or vim.o.lines
	if not present then
		present = {}
		for _, panel in ipairs(windows()) do
			present[panel.side] = true
		end
	end
	preferred = preferred or M.side(vim.api.nvim_get_current_win()) or "left"
	local minimum = require("user.core.preferences").get("ui")
	local count = (present.left and 1 or 0) + (present.right and 1 or 0)
	local available = math.max(0, columns - minimum.min_editor_width - count)
	local sizes = {
		left = present.left and M.left_panel_width or 0,
		right = present.right and math.floor(columns * 0.4) or 0,
	}
	if count > 0 and available < count * 20 then
		local keep = present[preferred] and (preferred == "left" or preferred == "right") and preferred
			or (present.left and "left" or "right")
		for _, side in ipairs({ "left", "right" }) do
			sizes[side] = side == keep
					and available >= 20
					and math.min(sizes[side], columns - minimum.min_editor_width - 1)
				or 0
		end
	else
		while sizes.left + sizes.right > available do
			local side = sizes.right >= sizes.left and "right" or "left"
			sizes[side] = sizes[side] - 1
		end
	end
	local tabline = vim.o.showtabline == 2 or (vim.o.showtabline == 1 and #vim.api.nvim_list_tabpages() > 1)
	local usable = lines - vim.o.cmdheight - (vim.o.laststatus > 0 and 1 or 0) - (tabline and 1 or 0)
	local bottom_max = math.max(0, usable - minimum.min_editor_height - 2)
	sizes.bottom = present.bottom and math.min(math.floor(lines * 0.35), bottom_max) or 0
	return sizes
end

local function hide(winid)
	local bufnr = vim.api.nvim_win_get_buf(winid)
	if vim.bo[bufnr].modified or not require("user.core.window_roles").is_panel(winid) then
		return false
	end
	local hidden = vim.bo[bufnr].bufhidden
	-- Hiding an output window must not wipe the buffer and terminate its job.
	vim.bo[bufnr].bufhidden = "hide"
	local ok = pcall(vim.api.nvim_win_close, winid, false)
	if vim.api.nvim_buf_is_valid(bufnr) then
		vim.bo[bufnr].bufhidden = hidden
	end
	return ok
end

function M.editor_fits()
	local minimum = require("user.core.preferences").get("ui")
	local roles = require("user.core.window_roles")
	local found = false
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		-- In-place Oil occupies the main editing area, although its manager role
		-- keeps close actions routed through Oil. It can coexist with a sidebar.
		local role = roles.get(win)
		local oil = role == "manager"
			and vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "oil"
			and vim.api.nvim_win_get_config(win).relative == ""
		if role == "editor" or oil then
			found = true
			if
				vim.api.nvim_win_get_width(win) < minimum.min_editor_width
				or vim.api.nvim_win_get_height(win) < minimum.min_editor_height
			then
				return false
			end
		end
	end
	return found
end

function M.enforce()
	if applying then
		return
	end
	applying = true
	local ok, err = pcall(function()
		local panels = windows()
		-- Completion menus and overview rails create windows too. There is no
		-- layout to constrain when the tab only contains editors and floats.
		if #panels == 0 then
			return
		end
		local present = {}
		for _, panel in ipairs(panels) do
			present[panel.side] = true
		end
		local sizes = M.budget(nil, nil, present)
		for _, panel in ipairs(panels) do
			if sizes[panel.side] == 0 then
				hide(panel.win)
			elseif vim.api.nvim_win_is_valid(panel.win) then
				local dimension = panel.side == "bottom" and "height" or "width"
				local custom = vim.w[panel.win]["edgy_" .. dimension]
				if type(custom) == "number" and custom > sizes[panel.side] then
					vim.w[panel.win]["edgy_" .. dimension] = sizes[panel.side]
				end
				if vim.api["nvim_win_get_" .. dimension](panel.win) ~= sizes[panel.side] then
					pcall(vim.api["nvim_win_set_" .. dimension], panel.win, sizes[panel.side])
				end
			end
		end
		if M.editor_fits() then
			return
		end
		local current = vim.api.nvim_get_current_win()
		table.sort(panels, function(a, b)
			local a_priority = a.win == current and 10 or (a.side == "bottom" and 0 or 1)
			local b_priority = b.win == current and 10 or (b.side == "bottom" and 0 or 1)
			return a_priority < b_priority or (a_priority == b_priority and a.win < b.win)
		end)
		for _, panel in ipairs(panels) do
			if vim.api.nvim_win_is_valid(panel.win) then
				hide(panel.win)
				if M.editor_fits() then
					return
				end
			end
		end
	end)
	applying = false
	if not ok then
		vim.notify("Panel layout: " .. tostring(err), vim.log.levels.ERROR)
	end
end

function M.setup()
	generation = generation + 1
	scheduled = false
	local current = generation
	local group = vim.api.nvim_create_augroup("user_panel_budget", { clear = true })
	vim.api.nvim_create_autocmd({ "VimResized", "WinResized", "WinNew", "BufWinEnter", "TabEnter" }, {
		group = group,
		callback = function()
			if scheduled or applying then
				return
			end
			scheduled = true
			vim.schedule(function()
				if current == generation then
					scheduled = false
					M.enforce()
				end
			end)
		end,
	})
end

function M.open_oil(path)
	require("oil").open(path or vim.fn.getcwd())
end

return M
