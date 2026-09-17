return function()
	local api, ts = vim.api, vim.treesitter
	local old_ignore = vim.o.eventignore
	vim.o.eventignore = "all"
	require("lazy").load({ plugins = { "vim-matchup", "nvim-treesitter" } })
	local plugin = require("treesitter-matchup.internal")
	local syntax = require("treesitter-matchup.syntax")
	local cache = require("user.core.matchup_cache")
	cache.shutdown()
	local native = plugin.get_matches
	local native_skips = syntax.get_skips
	assert(cache.setup(), "Locked match-up adapter did not activate")
	local function buffer(lang, lines)
		local buf = api.nvim_create_buf(true, false)
		api.nvim_set_current_buf(buf)
		api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		vim.bo[buf].filetype = lang
		ts.get_parser(buf, lang):parse(true)
		return buf
	end
	local function normalize(matches)
		local result = {}
		for _, match in ipairs(matches) do
			result[#result + 1] = {
				match.identifier,
				match.type,
				match.range,
				match.length,
				match.text,
				match.last_node:type(),
				{ match.last_node:range() },
			}
		end
		return result
	end
	local function compare(buf, row, col)
		api.nvim_set_current_buf(buf)
		api.nvim_win_set_cursor(0, { row or 1, col or 0 })
		local expected = normalize(native(buf))
		assert(vim.deep_equal(normalize(plugin.get_matches(buf)), expected), "Native match ranges/text/nodes changed")
		assert(vim.deep_equal(normalize(plugin.get_matches(buf)), expected), "Cached match ranges/text/nodes changed")
		local wrapped = plugin.get_matches
		plugin.get_matches = native
		local expected_skips = native_skips(buf)
		plugin.get_matches = wrapped
		assert(vim.deep_equal(syntax.get_skips(buf), expected_skips), "Skip regions changed")
		return expected
	end
	local python = {
		"def outer(value):",
		"    if value:",
		"        for item in value:",
		"            if item:",
		"                return item",
		"    else:",
		"        return '雪'",
		"    return None",
		"",
		"def second():",
		'    text = "word"',
		"    return text",
	}
	local buf = buffer("python", python)
	local expected = compare(buf)
	assert(#expected > 0, "Python fixture has no match-up captures")
	-- Count actual native query iterations, not a mock of the cached result.
	local query = ts.query.get("python", "matchup")
	local iterate, calls = query.iter_matches, 0
	query.iter_matches = function(...)
		calls = calls + 1
		return iterate(...)
	end
	plugin.get_matches(buf)
	local warm_calls = calls
	assert(warm_calls > 0, "Probe did not execute the native query")
	for row = 1, #python do
		api.nvim_win_set_cursor(0, { row, 0 })
		assert(vim.deep_equal(normalize(plugin.get_matches(buf)), expected), "Cursor-only reuse changed captures")
	end
	assert(calls == warm_calls, "Cursor-only movement rescanned the same Python range")
	local exposed = plugin.get_matches(buf)
	exposed[1].range[1], exposed[1].text = 999, "mutated"
	assert(vim.deep_equal(normalize(plugin.get_matches(buf)), expected), "Caller mutation leaked into cached records")
	query.iter_matches = iterate
	-- Changed text, ranges and tree objects must retire old TSNodes, including
	-- edits made through APIs before TextChanged has been dispatched.
	api.nvim_buf_set_text(buf, 0, 4, 0, 9, { "other" })
	compare(buf)
	api.nvim_buf_set_lines(buf, 2, 3, false, { "        return value", "        # shifted" })
	compare(buf, 4)
	vim.cmd("normal! ggI# ")
	compare(buf)
	vim.cmd.undo()
	compare(buf)
	vim.cmd.redo()
	compare(buf)
	ts.get_parser(buf):invalidate(true)
	compare(buf)
	api.nvim_buf_set_lines(buf, 0, -1, false, python)
	local stopline = vim.g.matchup_treesitter_stopline
	vim.g.matchup_treesitter_stopline = 2
	for row = 1, #python do
		compare(buf, row)
	end
	vim.g.matchup_treesitter_stopline = stopline
	compare(buf)

	-- Explicit replacement queries and stateful custom predicates must be
	-- observed immediately without changing any runtime query implementation.
	local files = {}
	for _, path in ipairs(ts.query.get_files("python", "matchup")) do
		files[#files + 1] = table.concat(vim.fn.readfile(path), "\n")
	end
	local original_query = table.concat(files, "\n")
	ts.query.set("python", "matchup", '(return_statement "return" @open.test) @scope.test')
	compare(buf)
	ts.query.set("python", "matchup", "(string) @skip.test")
	compare(buf)
	local skips = syntax.get_skips(buf)
	assert(next(skips), "Skip fixture has no regions")
	skips[next(skips)] = nil
	compare(buf)
	local enabled = true
	ts.query.add_predicate("user-matchup-test?", function()
		return enabled
	end, { force = true })
	ts.query.set("python", "matchup", "((return_statement) @skip.test (#user-matchup-test?))")
	assert(#compare(buf) > 0, "Enabled predicate produced no matches")
	enabled = false
	assert(#compare(buf) == 0, "Stateful predicate was incorrectly memoized")
	ts.query.set("python", "matchup", original_query)
	compare(buf)

	-- Exercise the actual Vimscript consumers, not only the raw query table:
	-- the same matching motions, text object, matchadd positions and end signs.
	api.nvim_set_current_buf(buf)
	ts.start(buf, "python")
	vim.fn["matchup#loader#init_buffer"]()
	vim.wo.foldenable = false
	local wrapped = plugin.get_matches
	local wrapped_skips = syntax.get_skips
	local function implementation(use)
		plugin.get_matches = use
		syntax.get_skips = use == native and native_skips or wrapped_skips
	end
	local positions = { { 1, 0 }, { 1, 10 }, { 2, 4 }, { 4, 12 }, { 5, 17 }, { 7, 16 } }
	local moved, visible = false, false
	local function display(use, position)
		implementation(use)
		vim.fn["matchup#matchparen#disable"]()
		vim.fn["matchup#matchparen#enable"]()
		api.nvim_win_set_cursor(0, position)
		vim.fn["matchup#matchparen#highlight_surrounding"]()
		local highlights = vim.fn.getmatches()
		for _, match in ipairs(highlights) do
			match.id = nil
		end
		table.sort(highlights, function(a, b)
			return vim.inspect(a) < vim.inspect(b)
		end)
		local marks = {}
		local ns = api.nvim_get_namespaces()["vim-matchup"]
		for _, mark in ipairs(ns and api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true }) or {}) do
			marks[#marks + 1] = { mark[2], mark[3], mark[4] }
		end
		visible = visible or #highlights + #marks > 0
		return { highlights, marks }
	end
	for _, position in ipairs(positions) do
		assert(vim.deep_equal(display(native, position), display(wrapped, position)), "Pair highlighting changed")
		for _, motion in ipairs({ "%", "g%", "[%", "]%" }) do
			local targets = {}
			for _, use in ipairs({ native, wrapped }) do
				implementation(use)
				api.nvim_win_set_cursor(0, position)
				vim.cmd.normal(motion)
				targets[#targets + 1] = api.nvim_win_get_cursor(0)
			end
			assert(vim.deep_equal(targets[1], targets[2]), "Match motion changed: " .. motion)
			moved = moved or not vim.deep_equal(position, targets[1])
		end
	end
	assert(moved and visible, "Matching motion/highlight fixture did not exercise the plugin")
	local selections = {}
	for _, use in ipairs({ native, wrapped }) do
		implementation(use)
		api.nvim_win_set_cursor(0, { 1, 13 })
		vim.fn.setreg("z", "")
		vim.cmd.normal('"zyi%')
		selections[#selections + 1] = vim.fn.getreg("z")
	end
	assert(selections[1] == "value" and selections[1] == selections[2], vim.inspect(selections))
	implementation(wrapped)
	ts.stop(buf)

	-- Real installed queries: inheritance, directives and mixed language
	-- regions take the same path and retain the same captures as the plugin.
	local fixtures = {
		lua = { "local function f(x)", "  if x then", "    return x", "  end", "end" },
		c = { "int f(int x) {", "  if (x) return x;", "  else return 0;", "}" },
		cpp = { "template<typename T> T f(T x) {", "  if (x) return x;", "  return 0;", "}" },
		javascript = { "function f(x) {", "  if (x) return x;", "  else return 0;", "}" },
		typescript = { "function f(x: number): number {", "  if (x) return x;", "  return 0;", "}" },
		rust = { "fn f(x: i32) -> i32 {", "  if x > 0 { x } else { 0 }", "}" },
		go = { "package main", "func f(x int) int {", "  if x > 0 { return x }", "  return 0", "}" },
		java = { "class Example {", "  int f(int x) {", "    if (x > 0) return x;", "    return 0;", "  }", "}" },
		html = { "<div>", "<script>", "function f(x) { return x; }", "</script>", "</div>" },
		markdown = { "# Test", "```python", "def f(x):", "    return x", "```", "", "```lua", "return true", "```" },
	}
	local buffers = { buf }
	for lang, lines in pairs(fixtures) do
		local item = buffer(lang, lines)
		buffers[#buffers + 1] = item
		for row = 1, #lines do
			compare(item, row)
		end
	end
	for _, item in ipairs(buffers) do
		compare(item)
	end
	-- Buffers that were evicted are still correct, and oversized result sets
	-- remain uncached rather than retaining an unbounded set of nodes/text.
	local many = {}
	for row = 1, 1500 do
		many[row] = "value = 0"
	end
	local large = buffer("python", many)
	buffers[#buffers + 1] = large
	vim.g.matchup_treesitter_stopline = 2000
	ts.query.set("python", "matchup", "(identifier) @scope.test")
	local large_query = ts.query.get("python", "matchup")
	local large_iterate, large_calls = large_query.iter_matches, 0
	large_query.iter_matches = function(...)
		large_calls = large_calls + 1
		return large_iterate(...)
	end
	for _ = 1, 2 do
		assert(#plugin.get_matches(large) == 1500, "Large-query fallback lost matches")
	end
	assert(large_calls == 2, "Oversized node set was retained")
	api.nvim_buf_set_lines(large, 0, -1, false, { string.rep("x", 70000) .. " = 0" })
	local before_long = large_calls
	for _ = 1, 2 do
		assert(#plugin.get_matches(large)[1].text == 70000, "Long text was truncated")
	end
	assert(large_calls == before_long + 2, "Oversized text was retained")
	large_query.iter_matches = large_iterate
	ts.query.set("python", "matchup", original_query)
	vim.g.matchup_treesitter_stopline = stopline

	-- Repeated setup/reload/shutdown must leave exactly one owner. An old
	-- callback or saved wrapper must remain safe after replacement.
	local stale = plugin.get_matches
	assert(cache.setup())
	assert(cache.setup())
	assert(vim.deep_equal(normalize(stale(buf)), normalize(native(buf))))
	package.loaded["user.core.matchup_cache"] = nil
	local replacement = require("user.core.matchup_cache")
	assert(replacement.setup())
	cache.shutdown()
	assert(vim._user_matchup_cache == replacement, "Obsolete owner removed the replacement")
	assert(#api.nvim_get_autocmds({ group = "user_matchup_cache" }) == 3, "Reload duplicated cleanup handlers")
	replacement.shutdown()
	assert(plugin.get_matches == native, "Shutdown did not restore native matching")
	assert(syntax.get_skips == native_skips, "Shutdown did not restore native skip regions")
	plugin.get_matches = function()
		return {}
	end
	local incompatible = plugin.get_matches
	assert(not replacement.setup() and plugin.get_matches == incompatible, "Unknown plugin implementation was wrapped")
	plugin.get_matches = native
	assert(replacement.setup())
	vim.o.eventignore = ""
	for _, item in ipairs(buffers) do
		api.nvim_buf_delete(item, { force = true })
	end
	vim.o.eventignore = "all"
	local reopened = buffer("python", python)
	compare(reopened)
	api.nvim_buf_delete(reopened, { force = true })
	vim.o.eventignore = old_ignore
	print("Match-up cache: native query parity, cursor reuse, edits, query changes, injections and lifecycle passed")
end
