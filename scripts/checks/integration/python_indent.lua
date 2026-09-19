return function()
	local api = vim.api
	require("lazy").load({ plugins = { "mini.nvim" } })
	local original = api.nvim_get_current_buf()
	local buffer = api.nvim_create_buf(false, false)
	api.nvim_set_current_buf(buffer)
	vim.bo[buffer].filetype = "python"
	local function type_keys(keys)
		api.nvim_feedkeys(vim.keycode(keys .. "<Esc>"), "xt", false)
	end
	local function fixture(lines, row)
		api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
		api.nvim_win_set_cursor(0, { row, #lines[row] })
	end
	local function expect_indent(row, expected, label)
		assert(
			vim.fn.indent(row) == expected,
			label .. ": " .. vim.inspect(api.nvim_buf_get_lines(buffer, 0, -1, false))
		)
	end

	-- Use the actual pair/newline mappings and colon reindent trigger, including
	-- the interval in which a parameter annotation has no type yet.
	type_keys("idef attention(<CR>query")
	expect_indent(2, 4, "New parameter did not start at one indentation level")
	type_keys("A:")
	expect_indent(2, 4, "Typing a parameter colon added another indentation level")
	type_keys("A Tensor,<CR>key:")
	expect_indent(2, 4, "Completing the type changed the first parameter indentation")
	expect_indent(3, 4, "The second typed parameter is misindented")

	for _, case in ipairs({
		{
			name = "async function",
			lines = { "async def attention(", "    query", ")" },
			row = 2,
			indent = 4,
		},
		{
			name = "class method",
			lines = { "class Model:", "    def attention(", "        query", "    )" },
			row = 3,
			indent = 8,
		},
		{ name = "variadic parameter", lines = { "def f(", "    *args", ")" }, row = 2, indent = 4 },
		{ name = "keyword parameter", lines = { "def f(", "    **kwargs", ")" }, row = 2, indent = 4 },
		{ name = "variable annotation", lines = { "def f():", "    value" }, row = 2, indent = 4 },
		{ name = "dictionary entry", lines = { "data = {", '    "query"', "}" }, row = 2, indent = 4 },
	}) do
		fixture(case.lines, case.row)
		type_keys("A:")
		expect_indent(case.row, case.indent, case.name .. " shifted while typing a colon")
	end

	-- Keep genuine block indentation and colon-triggered branch dedentation.
	fixture({ "" }, 1)
	type_keys("itry:<CR>work()")
	expect_indent(2, 4, "An unfinished try block lost its body indentation")
	fixture({ "try:", "    work()", "    except ValueError" }, 3)
	type_keys("A:<CR>recover()")
	expect_indent(3, 0, "The except header no longer dedents on its colon")
	expect_indent(4, 4, "The except body has incorrect indentation")
	fixture({ "if condition:", "    work()", "    elif other" }, 3)
	type_keys("A:<CR>recover()")
	expect_indent(3, 0, "The elif header no longer dedents on its colon")
	expect_indent(4, 4, "The elif body has incorrect indentation")
	fixture({ "if condition:", "    work()", "else" }, 3)
	type_keys("A:<CR>recover()")
	expect_indent(3, 0, "The else header shifted on its colon")
	expect_indent(4, 4, "The else body has incorrect indentation")

	fixture({ "def attention(", "    query: Tensor,", "    " }, 3)
	type_keys("A):<CR>return query")
	expect_indent(3, 0, "The closing parenthesis failed to align with def")
	expect_indent(4, 4, "The function body has incorrect indentation")
	local source = table.concat(api.nvim_buf_get_lines(buffer, 0, -1, false), "\n") .. "\n"
	local ruff = vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "bin", "ruff")
	local formatted = vim.system({ ruff, "format", "--stdin-filename", "sample.py", "-" }, {
		stdin = source,
		text = true,
	}):wait(5000)
	assert(formatted.code == 0, "Ruff could not format the typed function: " .. (formatted.stderr or ""))
	assert(formatted.stdout == source, "The formatter still changes the typed function indentation")

	api.nvim_set_current_buf(original)
	api.nvim_buf_delete(buffer, { force = true })
end
