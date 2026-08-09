local M = {
	-- Shared by lazygit, the floating terminal, and the scratch buffer. 0.9 is fine
	-- now that lazygit is nudged up a row (see git.lua) so its bottom border clears
	-- the global statusline (laststatus=3); the terminal already self-corrects.
	float_scale = 0.9,
	-- Package managers are the same 80% rectangle with no border. Do not use the
	-- "shadow" preset here: FloatShadowThrough exposes/tints the underlying text
	-- along its bottom and right edges, which looks like a leaking outer frame.
	manager_scale = 0.8,
	manager_border = "none",
}

local manager_filetypes = { lazy = true, mason = true }
local manager_backdrop_filetypes = { lazy_backdrop = true, mason_backdrop = true }

---Normalize Lazy and Mason after their different upstream viewport calculations.
---Lazy includes cmdheight in its height while Mason excludes it, otherwise
---leaving identically configured 80% windows one row apart.
function M.apply_manager_float(winid)
	if not winid or not vim.api.nvim_win_is_valid(winid) then
		return false
	end
	local config = vim.api.nvim_win_get_config(winid)
	if config.relative == "" then
		return false
	end
	local usable_lines = math.max(1, vim.o.lines - vim.o.cmdheight)
	local width = math.max(1, math.floor(vim.o.columns * M.manager_scale))
	local height = math.max(1, math.floor(usable_lines * M.manager_scale))
	local border_offset = M.manager_border == "none" and 0 or 1
	local row = math.max(0, math.floor((usable_lines - height) / 2) - border_offset)
	local col = math.max(0, math.floor((vim.o.columns - width) / 2) - border_offset)
	vim.api.nvim_win_set_config(winid, {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = height,
		border = M.manager_border,
	})
	return true
end

---Lazy omits `border` when creating its full-screen backdrop, so Neovim applies
---the global rounded winborder. Remove that inherited frame while retaining the
---dim layer. Mason already requests none explicitly; normalizing both is safer.
function M.apply_manager_backdrop(winid)
	if not winid or not vim.api.nvim_win_is_valid(winid) then
		return false
	end
	local config = vim.api.nvim_win_get_config(winid)
	if config.relative == "" then
		return false
	end
	vim.api.nvim_win_set_config(winid, {
		relative = "editor",
		row = 0,
		col = 0,
		width = vim.o.columns,
		height = vim.o.lines,
		border = "none",
	})
	return true
end

local function normalize_open_managers()
	for _, winid in ipairs(vim.api.nvim_list_wins()) do
		local bufnr = vim.api.nvim_win_get_buf(winid)
		local filetype = vim.bo[bufnr].filetype
		if manager_filetypes[filetype] then
			M.apply_manager_float(winid)
		elseif manager_backdrop_filetypes[filetype] then
			M.apply_manager_backdrop(winid)
		end
	end
end

function M.setup()
	local group = vim.api.nvim_create_augroup("user_manager_float_layout", { clear = true })
	vim.api.nvim_create_autocmd("FileType", {
		group = group,
		pattern = { "lazy", "mason", "lazy_backdrop", "mason_backdrop" },
		callback = function(event)
			local filetype = vim.bo[event.buf].filetype
			if manager_backdrop_filetypes[filetype] then
				for _, winid in ipairs(vim.fn.win_findbuf(event.buf)) do
					M.apply_manager_backdrop(winid)
				end
				return
			end
			vim.schedule(function()
				if not vim.api.nvim_buf_is_valid(event.buf) then
					return
				end
				for _, winid in ipairs(vim.fn.win_findbuf(event.buf)) do
					M.apply_manager_float(winid)
				end
			end)
		end,
	})
	vim.api.nvim_create_autocmd({ "VimResized" }, {
		group = group,
		callback = function()
			vim.schedule(normalize_open_managers)
		end,
	})
	vim.api.nvim_create_autocmd("OptionSet", {
		group = group,
		pattern = "cmdheight",
		callback = function()
			vim.schedule(normalize_open_managers)
		end,
	})
	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = "LazyFloatResized",
		callback = function()
			vim.schedule(normalize_open_managers)
		end,
	})
end

return M
