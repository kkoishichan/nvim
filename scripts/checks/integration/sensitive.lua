return function(tmp)
	local sensitive = require("user.core.sensitive")
	assert(sensitive.is_sensitive("/tmp/.env.production"), "environment file was not marked sensitive")
	assert(not sensitive.is_sensitive("/tmp/.env.production.example"), "environment template was marked sensitive")
	assert(not sensitive.is_sensitive("/tmp/credentials.sample"), "credential template was marked sensitive")
	assert(
		not sensitive.is_sensitive("/tmp/password_policy.md"),
		"ordinary password-named document was marked sensitive"
	)

	do
		local notify = vim.notify
		vim.o.clipboard = ""
		vim.notify = function() end
		local buffer = vim.api.nvim_create_buf(false, false)
		local path = tmp .. "/.env.production"
		vim.api.nvim_buf_set_name(buffer, path)
		vim.api.nvim_exec_autocmds("BufNewFile", { buffer = buffer })
		assert(vim.b[buffer].user_sensitive, "sensitive buffer flag was not set")
		assert(not vim.bo[buffer].undofile, "sensitive buffer retained persistent undo")
		assert(not vim.bo[buffer].swapfile, "sensitive buffer retained a swap file")

		vim.api.nvim_set_current_buf(buffer)
		vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "TOKEN=secret" })
		vim.g.user_sensitive_clipboard_timeout_ms = 20
		vim.cmd("silent normal! yy")
		assert(
			vim.wait(200, function()
				return vim.fn.getreg('"') == ""
			end),
			"sensitive register did not expire"
		)

		vim.fn.setreg('"', "keep")
		vim.cmd([[silent normal! "_yy]])
		vim.wait(60)
		assert(vim.fn.getreg('"') == "keep", "black-hole yank cleared an unrelated register")
		vim.g.user_sensitive_clipboard_timeout_ms = nil
		vim.notify = notify
		vim.api.nvim_buf_delete(buffer, { force = true })
	end
end
