-- Extend Gitsigns' inline added-line background into the number column.
-- Update its own marks through the native API after an explicit preview;
-- Gitsigns then clears both together, including its window-local scope.
local M = {}
local namespace

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
		for _, mark in ipairs(marks) do
			local details = mark[4]
			if details.hl_group == "GitSignsAddPreview" then
				namespace = details.ns_id
				details.ns_id, details.invalid = nil, nil
				details.id = mark[1]
				details.number_hl_group = "UserGitPreviewNumber"
				vim.api.nvim_buf_set_extmark(bufnr, namespace, mark[2], mark[3], details)
			end
		end
	end
end

function M.inline()
	require("gitsigns").preview_hunk_inline(finish(vim.api.nvim_get_current_buf()))
end

function M.navigate(direction)
	require("gitsigns").nav_hunk(direction, nil, finish(vim.api.nvim_get_current_buf()))
end

return M
