local M = {}

function M.setup(context)
	local preview
	local function load_preview()
		if not preview or not preview.is_active() then
			preview = require("user.core.pdf_preview").setup(context)
		end
		return preview
	end
	vim.api.nvim_create_autocmd("BufReadCmd", {
		group = context.augroup("pdf_preview"),
		pattern = { "*.pdf", "*.PDF" },
		callback = function(event)
			load_preview().open(event.buf, event.match)
		end,
	})
	-- A configuration reload reattaches surviving PDF buffers to the new
	-- lifecycle. Ordinary startup does not load the renderer or scan its cache.
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(bufnr) and type(vim.b[bufnr].pdf_preview_file) == "string" then
			load_preview()
			break
		end
	end
end

return M
