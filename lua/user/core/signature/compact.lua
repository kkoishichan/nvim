local M = {}
local active_highlight = "BlinkCmpSignatureHelpActiveParameter"
local ellipsis = "…"

---Flatten a signature and map its zero-based, end-exclusive byte range.
---@param label string
---@param active_range? integer[]
---@return string label
---@return integer[]? active_range
function M.flatten(label, active_range)
	local flat = label:gsub("\r\n", " "):gsub("[\r\n\t]", " ")
	if
		type(active_range) ~= "table"
		or type(active_range[1]) ~= "number"
		or type(active_range[2]) ~= "number"
		or active_range[1] < 0
		or active_range[2] <= active_range[1]
		or active_range[2] > #label
		or active_range[1] % 1 ~= 0
		or active_range[2] % 1 ~= 0
	then
		return flat, nil
	end
	local first, last = active_range[1], active_range[2]
	local removed_before, removed_inside = 0, 0
	-- Only CRLF changes byte length. If a boundary falls inside the pair,
	-- retain its replacement space rather than dropping the selected newline.
	for position in label:gmatch("()\r\n") do
		local start = position - 1
		if start < first then
			removed_before = removed_before + 1
		end
		if start + 2 <= last then
			removed_inside = removed_inside + 1
		end
	end
	return flat, { first - removed_before, last - removed_inside }
end

local function is_active(highlights)
	if type(highlights) == "table" then
		for _, highlight in ipairs(highlights) do
			if highlight == active_highlight then
				return true
			end
		end
	end
	return highlights == active_highlight
end

local function ellipsis_highlights(highlights)
	if type(highlights) ~= "table" then
		return highlights == active_highlight and "BlinkCmpSignatureHelp" or highlights
	end
	local result = {}
	for _, highlight in ipairs(highlights) do
		if highlight ~= active_highlight then
			result[#result + 1] = highlight
		end
	end
	return #result > 0 and result or "BlinkCmpSignatureHelp"
end

---Fit flattened body chunks; the caller owns marker and padding budgets.
---Keep display characters whole, including combining marks and emoji sequences.
---@param chunks table[] Virtual-text chunks: {text, highlight-or-highlights}.
---@param max_width integer Available display cells, without markers/padding.
---@return table[] chunks
function M.fit_chunks(chunks, max_width)
	local budget = math.max(0, math.floor(max_width))
	local texts, spans = {}, {}
	local length, active_start, active_end = 0, nil, nil
	for _, chunk in ipairs(chunks) do
		local text = chunk[1]
		texts[#texts + 1] = text
		spans[#spans + 1] = { first = length, last = length + #text, chunk = chunk }
		if #text > 0 and is_active(chunk[2]) then
			active_start = active_start or length
			active_end = length + #text
		end
		length = length + #text
	end
	local text = table.concat(texts)
	if vim.fn.strdisplaywidth(text) <= budget then
		return chunks
	end
	local ellipsis_width = vim.fn.strdisplaywidth(ellipsis)
	if budget < ellipsis_width then
		return {}
	end

	local units, widths = {}, { [0] = 0 }
	local offset, first_active, last_active = 0, nil, nil
	-- Neovim's zero-width split respects its complete display characters. In
	-- the supported runtime this also retains emoji ZWJ/skin-tone/flag sequences.
	-- Split once, only on overflow; never rescan increasingly long prefixes.
	for index, unit in ipairs(vim.fn.split(text, "\\zs")) do
		local last = offset + #unit
		units[index] = { first = offset, last = last }
		widths[index] = widths[index - 1] + vim.fn.strdisplaywidth(unit)
		if active_start and last > active_start and offset < active_end then
			first_active = first_active or index
			last_active = index
		end
		offset = last
	end
	local count = #units
	local function width(first, last)
		return widths[last] - widths[first - 1]
	end
	local function cost(first, last)
		return width(first, last) + (first > 1 and ellipsis_width or 0) + (last < count and ellipsis_width or 0)
	end
	local first, last = first_active or 1, (first_active or 1) - 1
	if first_active and cost(first_active, last_active) <= budget then
		first, last = first_active, last_active
		local left_context, right_context = 0, 0
		while first > 1 or last < count do
			local left = first > 1 and cost(first - 1, last) <= budget
			local right = last < count and cost(first, last + 1) <= budget
			if left and (not right or left_context <= right_context) then
				left_context = left_context + width(first - 1, first - 1)
				first = first - 1
			elseif right then
				right_context = right_context + width(last + 1, last + 1)
				last = last + 1
			else
				break
			end
		end
	else
		-- An oversized parameter retains its beginning (usually its name).
		-- Without an active parameter the same rule keeps the signature prefix.
		while last < count and cost(first, last + 1) <= budget do
			last = last + 1
		end
	end
	if last < first then
		return { { ellipsis, ellipsis_highlights(chunks[1] and chunks[1][2]) } }
	end

	local result = {}
	local start_byte, end_byte = units[first].first, units[last].last
	local first_highlights, last_highlights
	for _, span in ipairs(spans) do
		local start, finish = math.max(span.first, start_byte), math.min(span.last, end_byte)
		if start < finish then
			local chunk = {}
			for key, value in pairs(span.chunk) do
				chunk[key] = value
			end
			chunk[1] = span.chunk[1]:sub(start - span.first + 1, finish - span.first)
			result[#result + 1] = chunk
			first_highlights = first_highlights or chunk[2]
			last_highlights = chunk[2]
		end
	end
	if first > 1 then
		table.insert(result, 1, { ellipsis, ellipsis_highlights(first_highlights) })
	end
	if last < count then
		result[#result + 1] = { ellipsis, ellipsis_highlights(last_highlights) }
	end
	return result
end

return M
