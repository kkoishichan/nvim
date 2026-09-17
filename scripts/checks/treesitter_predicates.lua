return function()
	local api, query = vim.api, vim.treesitter.query
	local cache = require("user.core.treesitter_predicates")
	local parts = {}
	for _, path in ipairs(query.get_files("python", "highlights")) do
		local file = assert(io.open(path, "rb"))
		parts[#parts + 1] = file:read("*a")
		file:close()
	end
	local original = table.concat(parts)
	assert(original ~= "", "Python highlight queries are missing")
	local explicit = "(identifier) @test.explicit"
	query.set("python", "highlights", explicit)
	assert(cache.setup() == false, "An explicit highlight query was replaced")
	assert(query.get("python", "highlights") == query.parse("python", explicit), "Explicit query was not retained")
	query.set("python", "highlights", original)
	assert(cache.setup(), "The file-backed Python query was not optimized")
	local installed = query.get("python", "highlights")
	assert(cache.setup() and query.get("python", "highlights") == installed, "Repeated setup replaced the query")
	assert(#api.nvim_get_autocmds({ group = "user_scroll_query_cache" }) == 2, "Setup duplicated cleanup handlers")

	local literal = [[; #eq? and #lua-match? in comments must survive
((identifier) @x
  (#eq? @x "#eq? #any-of? 雪")
  (#set! label "#lua-match?"))
((identifier) @y (#not-eq? @y "cls"))
]]
	local rewritten = cache.rewrite(literal)
	assert(rewritten:find("; #eq? and #lua-match? in comments must survive", 1, true))
	assert(rewritten:find('(#user-scroll-eq? @x "#eq? #any-of? 雪")', 1, true))
	assert(rewritten:find('(#set! label "#lua-match?")', 1, true))
	assert(rewritten:find('(#not-eq? @y "cls")', 1, true))

	local native = query.parse("python", original)
	local function captures(q, root, source, first, last)
		local result = {}
		for id, node, metadata in q:iter_captures(root, source, first or 0, last or -1) do
			result[#result + 1] = { q.captures[id], { node:range() }, vim.deepcopy(metadata) }
		end
		return result
	end
	local function compare(buf, first, last)
		local root = vim.treesitter.get_parser(buf, "python"):parse()[1]:root()
		assert(
			vim.deep_equal(captures(native, root, buf, first, last), captures(installed, root, buf, first, last)),
			"Cached Python highlight captures/ranges/metadata diverged"
		)
	end
	local function buffer(lines)
		local buf = api.nvim_create_buf(true, false)
		api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		return buf
	end
	local lines = {
		"#!/usr/bin/env python3",
		"from typing import TypeAlias, TypeVar",
		"import re as pattern",
		"Alias: TypeAlias = list[int]",
		"T = TypeVar('T')",
		"MAX_SIZE = 10",
		"class Example(BaseException):",
		'    """A multiline docstring',
		'    with 雪 and #eq? inside it."""',
		"    @classmethod",
		"    def create(cls, other: int = 1, *args, **kwargs):",
		"        self.value = f'{other!r} {len(args)}'",
		"        return cls(__name__, quit, Ellipsis, None, True, 1.5)",
		"lower = lambda value: value + MAX_SIZE",
		"re.compile(r'[a-z]+')",
		"雪 = Example.create(other=3)",
	}
	local buf = buffer(lines)
	compare(buf)
	for first = 0, #lines - 1 do
		compare(buf, first, first + 3)
	end
	-- Same-length edits change naming-convention captures and must invalidate
	-- text as well as previously cached false predicate results.
	for _, name in ipairs({ "lowering", "MAX_SIZE", "__name__", "TypeName", "lowering" }) do
		api.nvim_buf_set_text(buf, 5, 0, 5, 8, { name })
		compare(buf)
	end
	api.nvim_set_current_buf(buf)
	vim.bo.filetype = "python"
	vim.cmd("normal! ggIedited_")
	compare(buf)
	vim.cmd.undo()
	compare(buf)
	vim.cmd.redo()
	compare(buf)

	-- Quantified captures, empty captures and capture-to-capture equality must
	-- retain the built-ins' different all/any semantics.
	for _, predicate in ipairs({
		'#eq? @value "self"',
		'#lua-match? @value "^[a-z]+$"',
		'#any-of? @value "self" "cls"',
	}) do
		local source = "((list (identifier)* @value) @container (" .. predicate .. "))"
		local before, after = query.parse("python", source), query.parse("python", cache.rewrite(source))
		for _, text in ipairs({ "[]", "[self]", "[self, other]", "[other, cls]", "[OTHER, VALUE]" }) do
			api.nvim_buf_set_lines(buf, 0, -1, false, { text })
			local root = vim.treesitter.get_parser(buf, "python"):parse()[1]:root()
			assert(vim.deep_equal(captures(before, root, buf), captures(after, root, buf)), predicate .. ": " .. text)
			local string_root = vim.treesitter.get_string_parser(text, "python"):parse()[1]:root()
			assert(
				vim.deep_equal(captures(before, string_root, text), captures(after, string_root, text)),
				"String-source predicate semantics changed"
			)
		end
	end
	local paired = "((assignment left: (identifier) @a right: (identifier) @b) (#eq? @a @b))"
	local before, after = query.parse("python", paired), query.parse("python", cache.rewrite(paired))
	for _, text in ipairs({ "same = same", "same = other", "雪 = 雪" }) do
		api.nvim_buf_set_lines(buf, 0, -1, false, { text })
		local root = vim.treesitter.get_parser(buf, "python"):parse()[1]:root()
		assert(vim.deep_equal(captures(before, root, buf), captures(after, root, buf)), "Capture equality changed")
	end

	-- Exercise capacity eviction and switching among hidden buffers; the
	-- results must remain native even when an old buffer is revisited.
	local buffers = {}
	for index = 1, 6 do
		local content = {}
		for row = 1, 400 do
			content[row] = ("Value_%d_%d = TypeName(self.value, cls, None)"):format(index, row)
		end
		buffers[index] = buffer(content)
		compare(buffers[index])
	end
	for _, item in ipairs(buffers) do
		compare(item)
		api.nvim_buf_delete(item, { force = true })
	end
	api.nvim_buf_set_lines(buf, 0, -1, false, { 'text = """', string.rep("x", 1500), '"""' })
	compare(buf)
	local multiline = '((string) @value (#lua-match? @value "x"))'
	before, after = query.parse("python", multiline), query.parse("python", cache.rewrite(multiline))
	local root = vim.treesitter.get_parser(buf, "python"):parse()[1]:root()
	assert(vim.deep_equal(captures(before, root, buf), captures(after, root, buf)), "Long multiline fallback changed")
	api.nvim_buf_delete(buf, { force = true })
	local reopened = buffer(lines)
	compare(reopened)
	api.nvim_buf_delete(reopened, { force = true })

	-- Built-in predicate handlers and other languages were never overwritten.
	assert(query.parse("python", original) == native, "Native queries were replaced")
	print(
		"Python predicate cache: native capture parity, edits/undo/redo, quantified predicates, Unicode and eviction passed"
	)
end
