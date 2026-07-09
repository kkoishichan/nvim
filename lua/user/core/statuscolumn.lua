-- Keep Git changes in their own lane next to the code while Neovim's native
-- %s segment renders diagnostics, DAP breakpoints, TODOs, and action signs on
-- the far left. Gitsigns provides an optimized statuscolumn renderer backed by
-- its own sign cache, so this avoids scanning extmarks for every screen line.

local M = {}

local blank_git_lane = "  "

function M.git()
	local bufnr = vim.api.nvim_get_current_buf()
	if vim.bo[bufnr].buftype ~= "" or not (vim.wo.number or vim.wo.relativenumber) then
		return ""
	end
	if vim.v.virtnum ~= 0 then
		return blank_git_lane
	end

	local gitsigns = package.loaded.gitsigns
	if type(gitsigns) ~= "table" or type(vim.b[bufnr].gitsigns_status_dict) ~= "table" then
		return blank_git_lane
	end

	local ok, value = pcall(gitsigns.statuscolumn, bufnr, vim.v.lnum)
	return ok and type(value) == "string" and value or blank_git_lane
end

return M
