return function(tmp)
	local api = vim.api
	local directory = tmp .. "/git-ui"
	vim.fn.mkdir(directory, "p")
	local function git(...)
		local command = { "git", "-C", directory, "-c", "commit.gpgSign=false" }
		vim.list_extend(command, { ... })
		local result = vim.system(command, { text = true }):wait()
		assert(result.code == 0, result.stderr)
	end
	git("init", "--quiet")
	local path = directory .. "/sample.txt"
	local lines = {}
	for i = 1, 24 do
		lines[i] = "stable " .. i
	end
	lines[4], lines[17] = "value = 41", "second = before"
	vim.fn.writefile(lines, path)
	git("add", "sample.txt")
	git("-c", "user.name=UI Check", "-c", "user.email=ui-check@example.invalid", "commit", "--quiet", "-m", "fixture")
	lines[4], lines[17] = "value = 42", "second = after"
	vim.fn.writefile(lines, path)

	require("lazy").load({ plugins = { "gitsigns.nvim" } })
	vim.cmd.edit(vim.fn.fnameescape(path))
	local bufnr = api.nvim_get_current_buf()
	local gs = require("gitsigns")
	assert(
		vim.wait(3000, function()
			return #(gs.get_hunks(bufnr) or {}) == 2
		end, 20),
		"Git preview fixture did not attach"
	)
	local namespace
	local function added_line()
		for _, mark in
			ipairs(api.nvim_buf_get_extmarks(bufnr, namespace or -1, 0, -1, { details = true, type = "highlight" }))
		do
			if mark[4].hl_group == "GitSignsAddPreview" then
				namespace = mark[4].ns_id
				return mark
			end
		end
	end
	local function invoke(lhs)
		local mapping = vim.fn.maparg(lhs, "n", false, true)
		assert(type(mapping.callback) == "function", "Missing Git mapping: " .. lhs)
		mapping.callback()
	end
	api.nvim_win_set_cursor(0, { 4, 0 })
	invoke("<leader>ghi")
	assert(
		vim.wait(2000, function()
			local mark = added_line()
			return mark and mark[4].number_hl_group == "UserGitPreviewNumber"
		end, 20),
		"Inline preview did not colour its number column"
	)
	assert(vim.deep_equal(api.nvim_buf_get_lines(bufnr, 0, -1, false), lines), "Preview modified the source text")
	local removed = false
	for _, mark in ipairs(api.nvim_buf_get_extmarks(bufnr, namespace, 0, -1, { details = true, type = "virt_lines" })) do
		for _, line in ipairs(mark[4].virt_lines or {}) do
			local chunks = {}
			for _, chunk in ipairs(line) do
				chunks[#chunks + 1] = chunk[1]
			end
			removed = removed or table.concat(chunks):find("value = 41", 1, true) ~= nil
		end
	end
	assert(removed, "Inline preview lost the removed source line")

	invoke("]h")
	assert(
		vim.wait(2000, function()
			local mark = added_line()
			return mark and mark[2] == 16 and mark[4].number_hl_group == "UserGitPreviewNumber"
		end, 20),
		"Hunk navigation lost the inline number background"
	)
	api.nvim_exec_autocmds("InsertEnter", { buffer = bufnr })
	assert(
		#api.nvim_buf_get_extmarks(bufnr, namespace, 0, -1, {}) == 0,
		"Inline gutter background survived preview cleanup"
	)
	assert(vim.deep_equal(vim.fn.readfile(path), lines), "Preview modified the file on disk")
	gs.detach(bufnr)
	api.nvim_buf_delete(bufnr, { force = true })
end
