return function()
	local compact = require("user.core.signature.compact")
	local active = "BlinkCmpSignatureHelpActiveParameter"
	local function text(chunks)
		local parts = {}
		for _, chunk in ipairs(chunks) do
			parts[#parts + 1] = chunk[1]
		end
		return table.concat(parts)
	end
	local function active_text(chunks)
		local parts = {}
		for _, chunk in ipairs(chunks) do
			if chunk[2] == active or (type(chunk[2]) == "table" and vim.tbl_contains(chunk[2], active)) then
				parts[#parts + 1] = chunk[1]
			end
		end
		return table.concat(parts)
	end
	local function fit(chunks, budget)
		local before = vim.deepcopy(chunks)
		local result = compact.fit_chunks(chunks, budget)
		assert(
			vim.fn.strdisplaywidth(text(result)) <= math.max(0, budget),
			"Compact signature exceeded its cell budget"
		)
		assert(vim.deep_equal(before, chunks), "Clipping mutated the syntax chunks")
		return result
	end
	local function map(label, selected, expected_label, expected_parameter)
		local start, finish = assert(label:find(selected, 1, true))
		local range = { start - 1, finish }
		local flat, mapped = compact.flatten(label, range)
		assert(flat == expected_label, "Signature whitespace was not flattened exactly")
		assert(flat:sub(mapped[1] + 1, mapped[2]) == expected_parameter, "Flattened parameter byte range drifted")
		assert(range[1] == start - 1 and range[2] == finish, "Flattening changed the original server range")
		return flat, mapped
	end
	map(
		"call(\r\n\t参数: string,\r\n next: bool)",
		"参数: string",
		"call(  参数: string,  next: bool)",
		"参数: string"
	)
	map(
		"call(\r\n\t参数:\r\n\tlist[😀],\r next: bool\n)",
		"参数:\r\n\tlist[😀]",
		"call(  参数:  list[😀],  next: bool )",
		"参数:  list[😀]"
	)
	map("call(\tfirst: int,\n last: bool)", "last: bool", "call( first: int,  last: bool)", "last: bool")
	local crlf, whole_crlf = compact.flatten("a\r\nb", { 1, 3 })
	assert(crlf == "a b" and vim.deep_equal(whole_crlf, { 1, 2 }), "A CRLF pair did not map to one space")
	local _, half_crlf = compact.flatten("a\r\nb", { 2, 3 })
	assert(vim.deep_equal(half_crlf, { 1, 2 }), "A range touching half a CRLF lost the replacement space")
	for _, range in ipairs({ {}, { -1, 2 }, { 1, 1 }, { 1, 10 }, { 0.5, 2 }, { "0", 2 } }) do
		local flat, invalid = compact.flatten("a\tb", range)
		assert(flat == "a b" and invalid == nil, "Invalid server range was retained")
	end
	local unchanged =
		{ { "f(", "@function" }, { "参数", { "@variable.parameter", active } }, { ")", "@punctuation" } }
	assert(fit(unchanged, 7) == unchanged, "A fitting signature did not retain its original chunks")
	assert(text(fit({ { "abcdef", "Normal" } }, 4)) == "abc…", "A signature without active parameter lost its prefix")
	assert(text(fit({ { "abcdef", "Normal" } }, 1)) == "…", "A one-cell budget did not show a safe omission marker")
	assert(#fit({ { "abcdef", "Normal" } }, 0) == 0, "Zero budget produced visible text")
	assert(#fit({ { "abcdef", "Normal" } }, -1) == 0, "Negative budget produced visible text")

	local highlights = { "@type", "BlinkCmpSignatureVirtual", active }
	local current = {
		{ "very_long_function(previous_argument: integer, ", "@function" },
		{ "当前", { "@variable.parameter", active } },
		{ ": ", { "@punctuation", active } },
		{ "类型😀", highlights },
		{ ", following_argument: string) -> result", "@type" },
	}
	local parameter = "当前: 类型😀"
	local exact = fit(current, vim.fn.strdisplaywidth(parameter) + 2)
	assert(text(exact) == "…" .. parameter .. "…", "An entire fitting current parameter was not prioritized")
	assert(active_text(exact) == parameter, "Clipping lost or extended the current parameter highlight")
	assert(exact[#exact - 1][2] == highlights, "Syntax highlight stacks were replaced")
	local context = text(fit(current, vim.fn.strdisplaywidth(parameter) + 12))
	local at = assert(context:find(parameter, 1, true))
	assert(
		at > #"…" + 1 and at + #parameter - 1 < #context - #"…",
		"Available width did not retain both context sides"
	)
	local oversized =
		fit({ { "call(", "@function" }, { "very_long_parameter_name", active }, { ")", "@punctuation" } }, 10)
	assert(active_text(oversized) == "very_lon", "An oversized parameter did not retain its highlighted beginning")
	assert(text(oversized) == "…very_lon…", "Clipping an oversized parameter lost omission indicators")

	local clusters = { "中", "😀", "é", "👩🏽‍💻", "🇹🇼", "1️⃣", "ö́" }
	for _, cluster in ipairs(clusters) do
		local source = { { "prefix_prefix_", "@function" }, { cluster, active }, { "_suffix_suffix", "@type" } }
		local width = vim.fn.strdisplaywidth(cluster)
		for budget = 0, width + 12 do
			local result = fit(source, budget)
			local selected = active_text(result)
			assert(selected == "" or selected == cluster, "A display character was split during clipping")
			if budget >= width + 2 then
				assert(selected == cluster, "A fitting Unicode parameter was omitted")
			end
		end
	end
	-- Syntax boundaries can divide a grapheme; crop only at the combined text's
	-- display boundaries while keeping every original highlight fragment.
	local split_cluster =
		{ { "long_prefix_", "Normal" }, { "e", active }, { "́", { "@type", active } }, { "_suffix", "Normal" } }
	local composed = fit(split_cluster, 3)
	assert(
		text(composed) == "…é…" and active_text(composed) == "é",
		"A chunk boundary detached a combining mark"
	)
	assert(composed[2][2] == active and composed[3][2][1] == "@type", "Combining-mark syntax highlights changed")
	local flat, mapped = map(
		"f(\r\n前: int,\r\n 当前:\t字符串\n)",
		"当前:\t字符串",
		"f( 前: int,  当前: 字符串 )",
		"当前: 字符串"
	)
	local multiline = {
		{ flat:sub(1, mapped[1]), "Normal" },
		{ flat:sub(mapped[1] + 1, mapped[2]), active },
		{ flat:sub(mapped[2] + 1), "Normal" },
	}
	assert(
		active_text(fit(multiline, 16)) == "当前: 字符串",
		"Multiline flattening and clipping lost the active parameter"
	)
	local old_ambiwidth = vim.o.ambiwidth
	local character_options = { "fillchars", "listchars" }
	local original_globals, original_windows = {}, {}
	for _, option in ipairs(character_options) do
		original_globals[option] = vim.api.nvim_get_option_value(option, { scope = "global" })
	end
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		original_windows[win] = {}
		for _, option in ipairs(character_options) do
			original_windows[win][option] = vim.api.nvim_get_option_value(option, { scope = "local", win = win })
		end
	end
	local ok, err = pcall(function()
		-- The complete configuration uses narrow Unicode separators. Isolate
		-- both the defaults and every window-local override before widening them.
		for option, value in pairs({ fillchars = "fold:-,vert:|,eob: ", listchars = "tab:> ,trail:." }) do
			vim.api.nvim_set_option_value(option, value, { scope = "global" })
			for win in pairs(original_windows) do
				vim.api.nvim_set_option_value(option, value, { scope = "local", win = win })
			end
		end
		vim.o.ambiwidth = "double"
		for budget = 0, 16 do
			fit(current, budget)
		end
	end)
	-- Restore width first, while all character options are still ASCII, so
	-- restoring the user's Unicode separators cannot raise E834/E835.
	vim.o.ambiwidth = old_ambiwidth
	for _, option in ipairs(character_options) do
		vim.api.nvim_set_option_value(option, original_globals[option], { scope = "global" })
		for win, values in pairs(original_windows) do
			if vim.api.nvim_win_is_valid(win) then
				vim.api.nvim_set_option_value(option, values[option], { scope = "local", win = win })
			end
		end
	end
	assert(ok, err)

	-- Guard linear width work on overflow, and no character splitting when the
	-- whole text fits. Count input bytes, avoiding machine-dependent timings.
	local original_width, original_split = vim.fn.strdisplaywidth, vim.fn.split
	local measured_bytes, splits = 0, 0
	vim.fn.strdisplaywidth = function(value, ...)
		measured_bytes = measured_bytes + #value
		return original_width(value, ...)
	end
	vim.fn.split = function(...)
		splits = splits + 1
		return original_split(...)
	end
	local long = string.rep("参数é😀", 2000)
	local counts_ok, counts_err = pcall(function()
		compact.fit_chunks({ { long, "Normal" } }, 20)
		assert(measured_bytes <= 2 * #long + #"…", "Clipping repeatedly measured growing text prefixes")
		assert(splits == 1, "Overflow was split more than once")
		measured_bytes, splits = 0, 0
		local full = { { long, "Normal" } }
		assert(
			compact.fit_chunks(full, original_width(long)) == full and splits == 0,
			"The fitting path split text into characters"
		)
	end)
	vim.fn.strdisplaywidth, vim.fn.split = original_width, original_split
	assert(counts_ok, counts_err)
	print(
		"Compact signatures passed: mapped multiline ranges, cell budgets, Unicode clusters, syntax/active highlights and linear width work"
	)
end
