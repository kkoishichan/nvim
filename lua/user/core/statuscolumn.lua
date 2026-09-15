-- Keep Git changes in their own lane next to the code while Neovim's native
-- %s segment renders diagnostics, DAP breakpoints, TODOs, and action signs on
-- the far left. Gitsigns renders its cached sign metadata and only the current
-- line's extmarks, without scanning unrelated sign namespaces.

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

	local renderer = package.loaded["gitsigns.sign_renderer"]
	if type(renderer) ~= "table" or type(renderer.statuscolumn) ~= "function" then
		return blank_git_lane
	end
	-- Gitsigns publishes/clears this scalar alongside its status dictionary.
	-- Reading the dictionary copies every field across the API for each row.
	if vim.b[bufnr].gitsigns_head == nil then
		return blank_git_lane
	end

	return renderer.statuscolumn(bufnr, vim.v.lnum)
end

rawset(vim, "_user_statuscolumn_git", M.git)

return M
