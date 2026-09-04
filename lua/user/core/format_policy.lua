local M = {}

function M.enabled(bufnr)
	return not vim.g.disable_autoformat
		and not vim.b[bufnr].disable_autoformat
		and require("user.core.buffer_policy").allow(bufnr)
end

function M.after_save(bufnr)
	return vim.bo[bufnr].filetype == "tex" or vim.bo[bufnr].filetype == "plaintex"
end

function M.go_assembly(_, context)
	local bufnr = context.buf
	if vim.b[bufnr].user_go_asm ~= nil then
		return vim.b[bufnr].user_go_asm == true
	end
	local file = vim.api.nvim_buf_get_name(bufnr)
	if not file:match("%.s$") or not vim.fs.root(file, { "go.mod", "go.work" }) then
		return false
	end
	-- Go's Plan 9 dialect uses named TEXT/DATA/GLOBL operands with (SB).
	-- A .s suffix or a Go repository alone does not establish that dialect.
	for _, line in
		ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, math.min(100, vim.api.nvim_buf_line_count(bufnr)), false))
	do
		if
			line:match("^%s*TEXT%s+[^/]+%(SB%)")
			or line:match("^%s*DATA%s+[^/]+%(SB%)")
			or line:match("^%s*GLOBL%s+[^/]+%(SB%)")
		then
			return true
		end
	end
	return false
end

return M
