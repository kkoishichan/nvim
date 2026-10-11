-- Keep inline diff backgrounds inside the code area, like Diffview.
-- Gitsigns renders deleted lines with a synthetic, coloured number column;
-- remove that prefix and let Neovim reserve the normal gutter instead.
-- The current-line blame text is paused while the preview is shown: its
-- end-of-line virtual text sits on the previewed line and cuts the added-line
-- fill short, and "Not Committed Yet" says nothing the preview does not.
local M = {}
local namespace
local blame_paused = false

local function resume_blame()
	if blame_paused then
		blame_paused = false
		require("gitsigns").toggle_current_line_blame(true)
	end
end

local function pause_blame(bufnr)
	local config = require("gitsigns.config").config
	if blame_paused or not config.current_line_blame then
		return
	end
	blame_paused = true
	require("gitsigns").toggle_current_line_blame(false)
	-- Gitsigns clears the preview on these events; resume with it.
	vim.api.nvim_create_autocmd({ "CursorMoved", "InsertEnter", "BufLeave" }, {
		group = vim.api.nvim_create_augroup("user_git_preview_blame", { clear = true }),
		buffer = bufnr,
		once = true,
		callback = function()
			vim.schedule(resume_blame)
		end,
	})
end

local function has_group(groups, name)
	return groups == name or (type(groups) == "table" and vim.list_contains(groups, name))
end

local function code_lines(lines)
	local result = {}
	for _, line in ipairs(lines) do
		local chunks, prefix = {}, true
		for _, chunk in ipairs(line) do
			-- Prefix chunks carry this documented group even when stacked
			-- with number/sign colours. Keep code indentation and syntax intact.
			if not prefix or not has_group(chunk[2], "GitSignsVirtLnum") then
				prefix = false
				chunks[#chunks + 1] = chunk
			end
		end
		result[#result + 1] = chunks
	end
	return result
end

local function is_removed_preview(details)
	if not details.virt_lines or not details.virt_lines_leftcol then
		return false
	end
	for _, line in ipairs(details.virt_lines) do
		for _, chunk in ipairs(line) do
			if has_group(chunk[2], "GitSignsDeleteVirtLn") then
				return true
			end
		end
	end
	return false
end

local function finish(bufnr)
	return function(err)
		if err then
			vim.notify(tostring(err), vim.log.levels.ERROR, { title = "Git preview" })
			return
		end
		if not vim.api.nvim_buf_is_valid(bufnr) then
			return
		end
		-- Discover the namespace from the documented preview highlight rather
		-- than depending on a private Gitsigns module or namespace name. Once
		-- found, only that namespace is queried on subsequent requests.
		local marks = vim.api.nvim_buf_get_extmarks(bufnr, namespace or -1, 0, -1, {
			details = true,
		})
		local shown = false
		for _, mark in ipairs(marks) do
			local details = mark[4]
			if details.hl_group == "GitSignsAddPreview" or is_removed_preview(details) then
				shown = true
				namespace = details.ns_id
				if details.virt_lines then
					-- Update the native mark so its window scope and automatic
					-- cleanup remain owned by Gitsigns, including pure deletions.
					vim.api.nvim_buf_set_extmark(bufnr, namespace, mark[2], mark[3], {
						id = mark[1],
						virt_lines = code_lines(details.virt_lines),
						virt_lines_above = details.virt_lines_above,
						virt_lines_leftcol = false,
						virt_lines_overflow = details.virt_lines_overflow,
					})
				end
			end
		end
		if shown then
			pause_blame(bufnr)
		end
	end
end

---Whether the current-line blame is paused for a preview, for checks.
function M.blame_paused()
	return blame_paused
end

function M.inline()
	require("gitsigns").preview_hunk_inline(finish(vim.api.nvim_get_current_buf()))
end

function M.navigate(direction)
	require("gitsigns").nav_hunk(direction, nil, finish(vim.api.nvim_get_current_buf()))
end

return M
