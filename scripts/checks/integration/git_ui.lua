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
	lines[18], lines[19] = "", "third = after"
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
	local function number_line(row)
		for _, mark in ipairs(api.nvim_buf_get_extmarks(bufnr, namespace, 0, -1, { details = true })) do
			if mark[2] == row and mark[4].number_hl_group == "UserGitPreviewNumber" then
				return mark
			end
		end
	end
	local function check_number_rows(expected)
		local added, count = {}, 0
		local marks = api.nvim_buf_get_extmarks(bufnr, namespace, 0, -1, { details = true })
		for _, mark in ipairs(marks) do
			if mark[4].hl_group == "GitSignsAddPreview" then
				added[mark[2]] = true
				assert(number_line(mark[2]), "Added line lost its number background")
			end
		end
		for _, mark in ipairs(marks) do
			if mark[4].number_hl_group == "UserGitPreviewNumber" then
				count = count + 1
				assert(added[mark[2]], "Unchanged line received an added-line number background")
				assert(mark[4].end_row == nil, "Number background extends into the following line")
			end
		end
		assert(count == expected, "Inline gutter background count differs from the added lines")
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
			return mark and number_line(mark[2]) ~= nil
		end, 20),
		"Inline preview did not colour its number column"
	)
	check_number_rows(1)
	assert(vim.deep_equal(api.nvim_buf_get_lines(bufnr, 0, -1, false), lines), "Preview modified the source text")
	-- The current-line blame text would sit on the previewed line and cut
	-- its fill short; it pauses with the preview and returns when it clears.
	local preview = require("user.core.git_preview")
	local gitsigns_config = require("gitsigns.config").config
	assert(
		preview.blame_paused() and not gitsigns_config.current_line_blame,
		"Blame text stays over the inline preview"
	)
	assert(
		vim.wait(1000, function()
			for _, mark in ipairs(api.nvim_buf_get_extmarks(bufnr, -1, 0, -1, { details = true, type = "virt_text" })) do
				for _, chunk in ipairs(mark[4].virt_text or {}) do
					if chunk[2] == "GitSignsCurrentLineBlame" then
						return false
					end
				end
			end
			return true
		end, 20),
		"Blame virtual text is still drawn during the inline preview"
	)
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
			return mark and mark[2] == 16 and number_line(mark[2]) ~= nil
		end, 20),
		"Hunk navigation lost the inline number background"
	)
	check_number_rows(3)
	api.nvim_exec_autocmds("InsertEnter", { buffer = bufnr })
	assert(
		#api.nvim_buf_get_extmarks(bufnr, namespace, 0, -1, {}) == 0,
		"Inline gutter background survived preview cleanup"
	)
	assert(
		vim.wait(1000, function()
			return not preview.blame_paused() and gitsigns_config.current_line_blame
		end, 20),
		"Blame text did not return after the preview cleared"
	)
	assert(vim.deep_equal(vim.fn.readfile(path), lines), "Preview modified the file on disk")
	gs.detach(bufnr)
	api.nvim_buf_delete(bufnr, { force = true })
end
