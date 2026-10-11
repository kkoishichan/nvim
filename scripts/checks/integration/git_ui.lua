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
	for i = 1, 36 do
		lines[i] = "stable " .. i
	end
	lines[4], lines[17], lines[30] = "    removed = 旧值", "    value = 41", "    second = before"
	lines[31], lines[32] = "    old_middle", "    third = before"
	vim.fn.writefile(lines, path)
	git("add", "sample.txt")
	git("-c", "user.name=UI Check", "-c", "user.email=ui-check@example.invalid", "commit", "--quiet", "-m", "fixture")
	lines[17], lines[30] = "    value = 42", "    second = after"
	lines[31], lines[32] = "", "    third = after"
	table.remove(lines, 4)
	vim.fn.writefile(lines, path)

	require("lazy").load({ plugins = { "gitsigns.nvim" } })
	vim.cmd.edit(vim.fn.fnameescape(path))
	local bufnr = api.nvim_get_current_buf()
	local gs = require("gitsigns")
	assert(
		vim.wait(3000, function()
			return #(gs.get_hunks(bufnr) or {}) == 3
		end, 20),
		"Git preview fixture did not attach"
	)
	local namespace
	local function removed_lines()
		local result = {}
		for _, mark in ipairs(api.nvim_buf_get_extmarks(bufnr, namespace or -1, 0, -1, { details = true })) do
			for _, line in ipairs(mark[4].virt_lines or {}) do
				local text, removed = {}, false
				for _, chunk in ipairs(line) do
					text[#text + 1] = chunk[1]
					local groups = type(chunk[2]) == "table" and chunk[2] or { chunk[2] }
					removed = removed or vim.list_contains(groups, "GitSignsDeleteVirtLn")
				end
				if removed then
					namespace = mark[4].ns_id
					result[#result + 1] = { text = table.concat(text), leftcol = mark[4].virt_lines_leftcol }
				end
			end
		end
		return result
	end
	local function check_preview(expected_added, expected_removed)
		expected_removed = type(expected_removed) == "table" and expected_removed or { expected_removed }
		assert(
			vim.wait(2000, function()
				local removed = removed_lines()
				if #removed ~= #expected_removed then
					return false
				end
				for i, expected in ipairs(expected_removed) do
					if removed[i].leftcol or not vim.startswith(removed[i].text, expected) then
						return false
					end
				end
				return true
			end, 20),
			"Removed preview does not start at the code column: " .. vim.inspect(expected_removed)
		)
		for i, removed in ipairs(removed_lines()) do
			assert(
				removed.text:sub(#expected_removed[i] + 1):match("^ *$"),
				"Removed code gained an extra gutter or indentation"
			)
		end
		local count = 0
		for _, mark in ipairs(api.nvim_buf_get_extmarks(bufnr, namespace, 0, -1, { details = true })) do
			if mark[4].hl_group == "GitSignsAddPreview" then
				count = count + 1
				assert(mark[4].hl_eol, "Added code lost its full-line diff background")
			end
			assert(not mark[4].number_hl_group and not mark[4].sign_hl_group, "Inline preview painted the gutter")
		end
		assert(count == expected_added, "Inline preview lost added lines")
	end
	local function invoke(lhs)
		local mapping = vim.fn.maparg(lhs, "n", false, true)
		assert(type(mapping.callback) == "function", "Missing Git mapping: " .. lhs)
		mapping.callback()
	end
	api.nvim_win_set_cursor(0, { 3, 0 })
	invoke("<leader>ghi")
	-- A pure deletion must work on the first preview, before any added-line
	-- highlight has exposed Gitsigns' preview namespace.
	check_preview(0, "    removed = 旧值")
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
	invoke("]h")
	check_preview(1, "    value = 41")
	invoke("]h")
	check_preview(3, { "    second = before", "    old_middle", "    third = before" })
	api.nvim_exec_autocmds("InsertEnter", { buffer = bufnr })
	assert(
		#api.nvim_buf_get_extmarks(bufnr, namespace, 0, -1, {}) == 0,
		"Inline diff background survived preview cleanup"
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
