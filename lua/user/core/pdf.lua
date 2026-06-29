local M = {}

function M.status(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if not vim.api.nvim_buf_is_valid(bufnr) or type(vim.b[bufnr].pdf_preview_file) ~= "string" then
		return ""
	end

	local page = tonumber(vim.b[bufnr].pdf_preview_page) or 1
	local pages = tonumber(vim.b[bufnr].pdf_preview_pages)
	local total = pages and pages > 0 and tostring(pages) or "?"
	local zoom = tonumber(vim.b[bufnr].pdf_preview_zoom) or 100

	return ("%d/%s %d%%"):format(page, total, zoom)
end

function M.page(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if not vim.api.nvim_buf_is_valid(bufnr) or type(vim.b[bufnr].pdf_preview_file) ~= "string" then
		return ""
	end

	local page = tonumber(vim.b[bufnr].pdf_preview_page) or 1
	local pages = tonumber(vim.b[bufnr].pdf_preview_pages)
	local total = pages and pages > 0 and tostring(pages) or "?"
	return ("%d/%s"):format(page, total)
end

function M.zoom(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if not vim.api.nvim_buf_is_valid(bufnr) or type(vim.b[bufnr].pdf_preview_file) ~= "string" then
		return ""
	end

	local zoom = tonumber(vim.b[bufnr].pdf_preview_zoom) or 100
	return ("%d%%%%"):format(zoom)
end

return M
