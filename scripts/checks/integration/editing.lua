return function()
	do
		local buffer = vim.api.nvim_create_buf(false, false)
		vim.api.nvim_set_current_buf(buffer)
		vim.api.nvim_buf_set_lines(buffer, 0, -1, false, {
			"<<<<<<< HEAD",
			"ours",
			"=======",
			"theirs",
			">>>>>>> branch",
		})
		vim.api.nvim_exec_autocmds("BufReadPost", { buffer = buffer })
		assert(
			vim.wait(200, function()
				return vim.b[buffer].user_has_conflicts == true
			end),
			"conflict highlighting did not activate"
		)
		assert(not vim.diagnostic.is_enabled({ bufnr = buffer }), "conflict diagnostics were not disabled")

		vim.api.nvim_win_set_cursor(0, { 2, 0 })
		vim.cmd.GitConflictChooseBoth()
		assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), { "ours", "theirs" }))
		assert(
			vim.wait(200, function()
				return vim.b[buffer].user_has_conflicts == false
			end),
			"conflict highlighting did not clear"
		)
		assert(vim.diagnostic.is_enabled({ bufnr = buffer }), "conflict diagnostics were not restored")
		vim.api.nvim_buf_delete(buffer, { force = true })
	end

	do
		local buffer = vim.api.nvim_create_buf(false, false)
		vim.api.nvim_set_current_buf(buffer)
		vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "intro", "", "Setext heading", "=====", "# ATX" })
		vim.bo[buffer].filetype = "markdown"
		vim.v.errmsg = ""
		vim.api.nvim_exec_autocmds("FileType", { buffer = buffer })
		vim.api.nvim_exec_autocmds("FileType", { buffer = buffer })
		assert(not vim.v.errmsg:match("E31"), "Markdown FileType replay left stale mappings")

		local callback
		for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(buffer, "x")) do
			if mapping.lhs == "]]" then
				callback = mapping.callback
				break
			end
		end
		assert(type(callback) == "function", "Markdown visual heading motion is missing")
		vim.api.nvim_win_set_cursor(0, { 1, 0 })
		vim.cmd.normal({ "V", bang = true })
		callback()
		assert(vim.api.nvim_win_get_cursor(0)[1] == 3, "Markdown motion skipped a Setext heading")
		vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
		vim.api.nvim_buf_delete(buffer, { force = true })
	end
end
