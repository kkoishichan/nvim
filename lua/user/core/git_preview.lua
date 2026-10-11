-- Extend Gitsigns' inline added-line background into the number column.
-- Place row-only gutter marks in its preview namespace after an explicit
-- preview; Gitsigns clears both together, including its window-local scope.
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

require("user.core.highlights").on_colorscheme("git_preview", function()
	local value = require("user.core.palette").highlight("GitSignsAddPreview")
	vim.api.nvim_set_hl(0, "UserGitPreviewNumber", { bg = value.bg, ctermbg = value.ctermbg })
end)

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
			type = "highlight",
		})
		local shown = false
		for _, mark in ipairs(marks) do
			local details = mark[4]
			if details.hl_group == "GitSignsAddPreview" then
				shown = true
				namespace = details.ns_id
				-- The text mark ends at the next row's column zero. Number
				-- highlights include that row, so attaching one to the text
				-- range would also paint the following unchanged line's gutter.
				vim.api.nvim_buf_set_extmark(bufnr, namespace, mark[2], 0, {
					number_hl_group = "UserGitPreviewNumber",
					priority = details.priority,
				})
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
