return function()
	local api, ts = vim.api, vim.treesitter
	local old_ignore = vim.o.eventignore
	vim.o.eventignore = "all"
	require("lazy").load({ plugins = { "vim-matchup", "nvim-treesitter" } })
	local cache = require("user.core.matchup_cache")
	local helper = require("treesitter-matchup.third-party.utils")
	local syntax = require("treesitter-matchup.syntax")
	cache.shutdown()
	local native = helper.get_hl_groups_at_position
	assert(cache.setup())
	local wrapped = helper.get_hl_groups_at_position
	local buffers = {}
	local function buffer(lang, lines)
		local buf = api.nvim_create_buf(true, false)
		buffers[#buffers + 1] = buf
		api.nvim_set_current_buf(buf)
		api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		vim.bo[buf].filetype = lang
		ts.start(buf, lang)
		ts.get_parser(buf):parse(true)
		vim.cmd.redraw({ bang = true })
		return buf
	end
	local visible = 0
	local function compare(buf, row, col)
		local expected = native(buf, row, col)
		assert(vim.deep_equal(wrapped(buf, row, col), expected), "Native position captures/order/priority changed")
		assert(vim.deep_equal(wrapped(buf, row, col), expected), "Cached position captures/order/priority changed")
		visible = visible + #expected
		return expected
	end
	local function all_positions(buf)
		api.nvim_set_current_buf(buf)
		for row, line in ipairs(api.nvim_buf_get_lines(buf, 0, -1, false)) do
			for col = 0, #line do
				compare(buf, row - 1, col)
			end
		end
	end
	local python = {
		"def outer(value):",
		'    """Docstring (with 雪)',
		'    and a second line."""',
		"    # comment with (brackets)",
		"    message = f'value: {value!r}'",
		"    if value:",
		"        return (value + len('text'))",
		"    return None",
	}
	local buf = buffer("python", python)
	all_positions(buf)
	assert(visible > 0, "Highlight fixtures were never rendered")
	local query = ts.query.get("python", "highlights")
	local iterate, calls = query.iter_captures, 0
	query.iter_captures = function(...)
		calls = calls + 1
		return iterate(...)
	end
	for _ = 1, 3 do
		for col = 0, #python[1] do
			wrapped(buf, 0, col)
		end
	end
	assert(calls == 1, "Repeated positions on one unchanged line reran the highlight query: " .. calls)
	query.iter_captures = iterate
	local exposed = wrapped(buf, 0, 0)
	exposed[1].capture, exposed[1].priority = "changed", 999
	compare(buf, 0, 0)
	-- Live foreground definitions still select the same syntax ID; results
	-- must not retain a theme's final highlight decisions.
	local saved = api.nvim_get_hl(0, { name = "@string", link = true })
	for _, definition in ipairs({ {}, { fg = "#ff0000" }, { link = "Comment" } }) do
		api.nvim_set_hl(0, "@string", definition)
		for _, pos in ipairs({ { 2, 7 }, { 4, 8 }, { 5, 18 }, { 7, 29 } }) do
			helper.get_hl_groups_at_position = native
			local expected = syntax.synID(pos[1], pos[2], 1)
			helper.get_hl_groups_at_position = wrapped
			assert(syntax.synID(pos[1], pos[2], 1) == expected, "A theme change left stale syntax IDs")
		end
	end
	api.nvim_set_hl(0, "@string", saved)
	api.nvim_buf_set_text(buf, 0, 4, 0, 9, { "Other" })
	ts.get_parser(buf):parse(true)
	all_positions(buf)
	vim.cmd("normal! ggI# ")
	ts.get_parser(buf):parse(true)
	all_positions(buf)
	vim.cmd.undo()
	ts.get_parser(buf):parse(true)
	all_positions(buf)
	vim.cmd.redo()
	ts.get_parser(buf):parse(true)
	all_positions(buf)
	ts.get_parser(buf):invalidate(true)
	ts.get_parser(buf):parse(true)
	all_positions(buf)

	local files = {}
	for _, path in ipairs(ts.query.get_files("python", "highlights")) do
		files[#files + 1] = table.concat(vim.fn.readfile(path), "\n")
	end
	local original = table.concat(files, "\n")
	local function replace(text)
		ts.query.set("python", "highlights", text)
		ts.stop(buf)
		ts.start(buf, "python")
		ts.get_parser(buf):parse(true)
	end
	api.nvim_buf_set_lines(buf, 0, -1, false, python)
	replace("(identifier) @user.late\n(string) @string")
	-- Cache before redraw, when the active highlighter has not yet resolved
	-- these capture groups. Later rendering must update eligibility on hits.
	compare(buf, 0, 5)
	vim.cmd.redraw({ bang = true })
	assert(#compare(buf, 0, 5) > 0, "Newly initialized highlight groups were hidden by the cache")
	local enabled, priority = true, 100
	ts.query.add_predicate("user-matchup-state?", function()
		return enabled
	end, { force = true })
	ts.query.add_directive("user-matchup-priority!", function(_, _, _, _, metadata)
		metadata.priority = priority
	end, { force = true })
	replace("((identifier) @comment (#user-matchup-state?) (#user-matchup-priority!))")
	vim.cmd.redraw({ bang = true })
	assert(#compare(buf, 0, 5) > 0, "Stateful query fixture returned no captures")
	enabled = false
	assert(#compare(buf, 0, 5) == 0, "External-state predicate was cached")
	enabled, priority = true, 250
	assert(compare(buf, 0, 5)[1].priority == 250, "External-state directive was cached")
	replace(original)
	vim.cmd.redraw({ bang = true })
	all_positions(buf)
	ts.stop(buf)
	assert(#compare(buf, 0, 5) == 0, "Stopped highlighter remained active in the cache")
	ts.start(buf, "python")
	vim.cmd.redraw({ bang = true })
	all_positions(buf)

	for lang, lines in pairs({
		lua = { 'local x = "(string)" -- comment', "if x then print(x) end" },
		c = { 'int f(void) { return puts("text"); } /* comment */' },
		cpp = { 'auto text = R"tag((text))tag";' },
		javascript = { "const x = `value: ${fn('text')}`; // comment" },
		typescript = { 'const text: string = "()";' },
		rust = { 'fn f() { let s = r#"text"#; }' },
		go = { "package main", 'func f() { println("text") }' },
		java = { 'class X { String text = "()"; }' },
		html = { "<div>", "<script>let x = 'text';</script>", "</div>" },
		markdown = { "```python", "print('雪')", "```", "", "```lua", "print('text')", "```" },
	}) do
		all_positions(buffer(lang, lines))
	end
	api.nvim_set_current_buf(buf)
	all_positions(buf)
	-- Exercise row eviction and a single row that exceeds the capture bound.
	local lines = {}
	for _ = 1, 150 do
		lines[#lines + 1] = "value = 1"
	end
	api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	replace("(identifier) @variable")
	for row = 0, #lines - 1 do
		compare(buf, row, 0)
	end
	compare(buf, 0, 0)
	api.nvim_buf_set_lines(buf, 0, -1, false, { "values = [" .. string.rep("x,", 4200) .. "]" })
	ts.get_parser(buf):parse(true)
	query = ts.query.get("python", "highlights")
	iterate, calls = query.iter_captures, 0
	query.iter_captures = function(...)
		calls = calls + 1
		return iterate(...)
	end
	wrapped(buf, 0, 10)
	wrapped(buf, 0, 10)
	assert(calls == 2, "Oversized capture row was retained")
	query.iter_captures = iterate
	compare(buf, 0, 10)
	replace(original)
	local stale = wrapped
	assert(cache.setup())
	cache.shutdown()
	assert(helper.get_hl_groups_at_position == native, "Native highlight helper was not restored")
	assert(vim.deep_equal(stale(buf, 0, 10), native(buf, 0, 10)), "Retired highlight wrapper was not safe")
	helper.get_hl_groups_at_position = function()
		return {}
	end
	assert(not cache.setup(), "Unknown highlight helper implementation was wrapped")
	helper.get_hl_groups_at_position = native
	assert(cache.setup())
	vim.o.eventignore = ""
	for _, number in ipairs(buffers) do
		api.nvim_buf_delete(number, { force = true })
	end
	vim.o.eventignore = old_ignore
	print("Match-up highlights: native parity, line reuse, themes, edits, injections, custom queries and bounds passed")
end
