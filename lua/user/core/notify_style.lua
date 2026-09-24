local M = {}
local namespace = vim.api.nvim_create_namespace("user_notify_background")

-- Notify resets NormalNC:NONE on every animation frame. Fill the rendered rows
-- instead of fighting its window options; supplied groups retain the fade and
-- follow severity changes on replacement without an extra timer or callback.
function M.render(bufnr, notification, highlights, config)
	require("notify.render").default(bufnr, notification, highlights, config)
	vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
	vim.api.nvim_buf_set_extmark(bufnr, namespace, 0, 0, {
		end_row = vim.api.nvim_buf_line_count(bufnr),
		hl_group = highlights.body,
		hl_eol = true,
		priority = 0,
	})
	-- Uncoloured spaces in the default header's virtual text replace the line
	-- background too. Give those chunks the same body group; keep title/icon
	-- colours and placement from the standard renderer.
	for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, -1, 0, -1, { details = true })) do
		local details = mark[4]
		if details.virt_text then
			for _, chunk in ipairs(details.virt_text) do
				if chunk[2] == nil or chunk[2] == "" then
					chunk[2] = highlights.body
				end
			end
			vim.api.nvim_buf_set_extmark(bufnr, details.ns_id, mark[2], mark[3], {
				id = mark[1],
				virt_text = details.virt_text,
				virt_text_pos = not details.virt_text_win_col and details.virt_text_pos or nil,
				virt_text_win_col = details.virt_text_win_col,
				priority = details.priority,
			})
		end
	end
end

return M
