return function(tmp)
	local api = vim.api
	local call = require("user.core.signature.call")
	local parameters = require("user.core.signature.parameters")
	local old_ignore = vim.o.eventignore
	vim.o.eventignore = "all"
	local function signature(label, labels)
		return {
			label = label,
			parameters = vim.tbl_map(function(value)
				return { label = value }
			end, labels),
		}
	end
	local function probe(filetype, text, help, cursor)
		local buf = api.nvim_create_buf(false, true)
		api.nvim_buf_set_name(buf, tmp .. "/signature-parameters-" .. buf)
		local lines = vim.split(text, "\n", { plain = true })
		api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		vim.bo[buf].filetype = filetype
		cursor = cursor or { #lines, #lines[#lines] - 1 }
		local state = assert(call.call_arguments(buf, cursor), "No call recognized: " .. text)
		local before = help and vim.deepcopy(help)
		local normalized = help and parameters.normalize_signature_help({ bufnr = buf, cursor = cursor }, help)
		assert(not help or vim.deep_equal(before, help), "Parameter normalization mutated the LSP response")
		api.nvim_buf_delete(buf, { force = true })
		return normalized, state
	end
	local function active(filetype, text, help, expected, cursor)
		local normalized = probe(filetype, text, help, cursor)
		assert(normalized.activeParameter == expected, "Wrong active parameter for " .. text)
		assert(
			normalized.signatures[normalized.activeSignature + 1].activeParameter == expected,
			"Signature-local parameter disagrees with the selected parameter"
		)
		return normalized
	end

	local typed = {
		activeSignature = 1,
		activeParameter = 0,
		signatures = {
			signature("pick(value: string)", { "value: string" }),
			signature("pick(value: number)", { "value: number" }),
		},
	}
	assert(probe("typescript", "pick(42)", typed).activeSignature == 1, "Equal arity discarded the server's overload")
	local overloads = { activeSignature = 1, activeParameter = 0, signatures = {} }
	for _, count in ipairs({ 1, 2, 3, 4, 1, 2 }) do
		local labels = {}
		for index = 1, count do
			labels[index] = "int arg" .. index
		end
		local entry = signature("foo(" .. table.concat(labels, ", ") .. ")", labels)
		entry.activeParameter = 1 -- stale signature-local response
		overloads.signatures[#overloads.signatures + 1] = entry
	end
	for count, expected in ipairs({ 0, 1, 2, 3, 3 }) do
		local arguments = {}
		for index = 1, count do
			arguments[index] = tostring(index)
		end
		local normalized = active("cpp", "foo(" .. table.concat(arguments, ",") .. ")", overloads, count - 1)
		assert(normalized.activeSignature == expected, "Arity correction regressed for argument count " .. count)
	end
	local complete = "foo(1, 2, 3)"
	local normalized, state = probe("cpp", complete, overloads, { 1, assert(complete:find(",", 1, true)) - 1 })
	assert(state.argument_count == 3 and normalized.activeSignature == 2, "Moving the cursor hid later arguments")
	assert(normalized.activeParameter == 0, "Moving inside the first argument changed its index")
	for count = 2, 4 do
		local incomplete = "foo(" .. string.rep("1, ", count - 1)
		local result = active("cpp", incomplete, overloads, count - 1, { 1, #incomplete })
		assert(result.activeSignature == count - 1, "An incomplete call lost arity correction")
	end

	local named = {
		activeSignature = 0,
		activeParameter = 1,
		signatures = { signature("foo(first: int, second: int)", { "first: int", "second: int" }) },
	}
	active("python", "foo(second=2, first=1)", named, 0)
	-- Assignment expressions in JavaScript must retain positional semantics.
	active("typescript", "foo(second=2, first=1)", named, 1)
	local unusual = {
		activeParameter = 0,
		signatures = { signature("foo((first): int, (second): int)", { "(first): int", "(second): int" }) },
	}
	active("python", "foo(second=2, first=1)", unusual, 0)
	unusual.signatures[1].activeParameter = 1
	active("python", "foo(second=2, first=1)", unusual, 1)
	unusual.signatures[1].activeParameter = 99
	active("python", "foo(second=2, first=1)", unusual, 1)
	local variadic = {
		activeSignature = 0,
		activeParameter = 0,
		signatures = { signature("log(format: str, *args: object)", { "format: str", "*args: object" }) },
	}
	local tail = active("python", 'log("fmt", 1, 2, 3)', variadic, 1)
	local tail_range = assert(parameters.active_parameter_range(tail), "Variadic tail lost its highlight")
	assert(
		tail.signatures[1].label:sub(tail_range[1] + 1, tail_range[2]) == "*args: object",
		"Wrong variadic highlight"
	)
	local keyword_tail = {
		signatures = { signature("foo(*args: int, flag: bool)", { "*args: int", "flag: bool" }) },
	}
	active("python", "foo(1, flag=True)", keyword_tail, 1)
	active("python", "foo(1, 2, 3)", keyword_tail, 0)

	-- Real installed parsers provide top-level separators without treating
	-- language operators, string contents or nested expressions as comments.
	for _, fixture in ipairs({
		{ "python", "foo(10 // 2, value)", 2 },
		{ "cpp", "foo(i--, value)", 2 },
		{ "lua", "foo(#items, value)", 2 },
		{ "python", "foo(a<b, c>d, value)", 3 },
		{ "typescript", "foo(/a,b/, value)", 2 },
		{ "cpp", "foo(1'000, value)", 2 },
		{ "cpp", "foo(std::pair<int, int>{1, 2}, value)", 2 },
		{ "python", "foo(1, # ignored, comma\n  value)", 2 },
		{ "lua", "foo(#items, -- ignored, comma\n  value)", 2 },
	}) do
		local _, parsed = probe(fixture[1], fixture[2])
		assert(parsed.argument_count == fixture[3], "Wrong argument count for " .. fixture[2])
		assert(parsed.active_parameter == fixture[3] - 1, "Wrong parameter index for " .. fixture[2])
	end
	assert(#call.split_arguments("10 // 2, value", "python") == 2, "Python fallback treated division as a comment")
	assert(#call.split_arguments("i--, value", "cpp") == 2, "C++ fallback treated decrement as a comment")
	assert(#call.split_arguments("#items, value", "lua") == 2, "Lua fallback treated length as a comment")

	local function utf16_parameter(label, substring)
		local first, last = label:find(substring, 1, true)
		assert(first, "Parameter missing from Unicode fixture")
		return { vim.str_utfindex(label, "utf-16", first - 1), vim.str_utfindex(label, "utf-16", last) }, {
			first - 1,
			last,
		}
	end
	for _, fixture in ipairs({
		{ "f(名字: str, n: int)", "名字: str" },
		{ 'f(name: str = "😀", value: int)', "value: int" },
		{ "f(\n  名字:\n    str,\n  count: int\n)", "名字:\n    str" },
	}) do
		local label, substring = unpack(fixture)
		local offsets, expected = utf16_parameter(label, substring)
		for _, parameter in ipairs({ offsets, substring }) do
			local help = { activeParameter = 0, signatures = { signature(label, { parameter }) } }
			local range = parameters.active_parameter_range(help)
			assert(vim.deep_equal(range, expected), "Original Unicode/multiline label byte range was lost")
			assert(label:sub(range[1] + 1, range[2]) == substring, "Parameter range splits a Unicode codepoint")
		end
	end
	local repeated = { activeParameter = 1, signatures = { signature("f(int, int)", { "int", "int" }) } }
	assert(
		vim.deep_equal(parameters.active_parameter_range(repeated), { 7, 10 }),
		"Repeated parameter selected the first label"
	)
	local same_name = { activeParameter = 0, signatures = { signature("f(f)", { "f" }) } }
	assert(
		vim.deep_equal(parameters.active_parameter_range(same_name), { 2, 3 }),
		"Parameter highlighted the callee name"
	)
	local unicode_label = "f(名字: str, count: int)"
	local unicode_named = {
		activeParameter = 1,
		signatures = {
			signature(unicode_label, {
				(utf16_parameter(unicode_label, "名字: str")),
				(utf16_parameter(unicode_label, "count: int")),
			}),
		},
	}
	active("python", "f(count=2, 名字='x')", unicode_named, 0)
	local invalid = { activeParameter = 0, signatures = { signature("f(x)", { { 0, 500 } }) } }
	assert(parameters.active_parameter_range(invalid) == nil, "Invalid UTF-16 offsets escaped validation")
	assert(parameters.active_parameter_range(nil) == nil, "Missing help produced a parameter range")
	vim.o.eventignore = old_ignore
	print("Signature parameters passed: overload ties, arity correction, named/variadic arguments and Unicode ranges")
end
