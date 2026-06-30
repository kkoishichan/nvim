-- A dimming backdrop behind a float, matching the fzf-lua / snacks look (a
-- full-editor black window at winblend 60, sitting just below the float). Used
-- to give lazygit and the floating terminal the same modal dim that fzf-lua and
-- the scratch buffer get out of the box.

local M = {}

vim.api.nvim_set_hl(0, "UserBackdrop", { bg = "#000000" })

---Open a backdrop behind `target`. It resizes with the editor and closes itself
---when `target` is closed, so callers don't have to track it.
---@param target integer window id to dim behind
---@param blend? integer winblend, 0 (opaque) .. 99 (invisible); default 60
---@return integer? win backdrop window id
function M.open(target, blend)
	if not (target and vim.api.nvim_win_is_valid(target)) then
		return
	end
	-- A blend over a colourless background renders oddly; skip if Normal has none.
	if not vim.api.nvim_get_hl(0, { name = "Normal" }).bg then
		return
	end

	local target_zindex = vim.api.nvim_win_get_config(target).zindex or 50
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].bufhidden = "wipe"

	local win = vim.api.nvim_open_win(buf, false, {
		relative = "editor",
		row = 0,
		col = 0,
		width = vim.o.columns,
		height = vim.o.lines,
		focusable = false,
		style = "minimal",
		border = "none",
		zindex = math.max(1, target_zindex - 2),
		noautocmd = true,
	})
	vim.wo[win].winhighlight = "Normal:UserBackdrop,NormalNC:UserBackdrop,EndOfBuffer:UserBackdrop"
	vim.wo[win].winblend = blend or 60

	local group = vim.api.nvim_create_augroup("user_backdrop_" .. win, { clear = true })
	local function close()
		pcall(vim.api.nvim_del_augroup_by_id, group)
		if vim.api.nvim_win_is_valid(win) then
			pcall(vim.api.nvim_win_close, win, true)
		end
	end

	vim.api.nvim_create_autocmd("WinClosed", {
		group = group,
		pattern = tostring(target),
		callback = close,
	})
	vim.api.nvim_create_autocmd("VimResized", {
		group = group,
		callback = function()
			if vim.api.nvim_win_is_valid(win) then
				pcall(vim.api.nvim_win_set_config, win, {
					relative = "editor",
					row = 0,
					col = 0,
					width = vim.o.columns,
					height = vim.o.lines,
				})
			end
		end,
	})

	return win
end

return M
