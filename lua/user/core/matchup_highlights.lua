-- Adapter for the source-checked match-up highlight helper. Cache raw line
-- captures only: its live highlight eligibility and ordering stay unchanged.
local api, ts = vim.api, vim.treesitter
local max_buffers, max_rows, max_captures = 4, 128, 4096
local pure = {
	["eq?"] = true,
	["not-eq?"] = true,
	["lua-match?"] = true,
	["any-of?"] = true,
	["set!"] = true,
}

local function same(left, right)
	if #left ~= #right then
		return false
	end
	for i, value in ipairs(left) do
		if value ~= right[i] then
			return false
		end
	end
	return true
end

return function(state, native)
	local buffers, queries, serial = {}, setmetatable({}, { __mode = "k" }), 0
	local function cacheable(query)
		if queries[query] == nil then
			local allowed = true
			for _, predicates in pairs(query.info.patterns) do
				for _, predicate in ipairs(predicates) do
					allowed = allowed and pure[predicate[1]] == true
				end
			end
			queries[query] = allowed
		end
		return queries[query]
	end
	local function context(buf, row)
		local highlighter = ts.highlighter.active[buf]
		if not highlighter then
			return nil
		end
		local key = { api.nvim_buf_get_changedtick(buf), highlighter }
		local parts, compatible = {}, true
		-- Follow the locked helper's exact traversal, including injections and
		-- its active queries. Do not parse or replace the highlighter's trees.
		highlighter.tree:for_each_tree(function(tree, language)
			local root = tree:root()
			local first, _, last = root:range()
			if first > row or last < row then
				return
			end
			local highlight_query = highlighter:get_query(language:lang())
			local query = highlight_query:query()
			if not query then
				return
			end
			if highlight_query._query ~= query or type(highlight_query.hl_cache) ~= "table" or not cacheable(query) then
				compatible = false
				return
			end
			key[#key + 1], key[#key + 2], key[#key + 3] = tree, query, query.iter_captures
			parts[#parts + 1] = { root = root, query = query, highlights = highlight_query.hl_cache }
		end, true)
		return compatible and key or nil, parts
	end
	local function clear(buf)
		if buf then
			buffers[buf] = nil
		else
			buffers = {}
		end
	end
	local function wrapper(buf, row, col)
		if not state.active then
			return native(buf, row, col)
		end
		local ok, key, parts = pcall(context, buf, row)
		if not ok or not key then
			buffers[buf] = nil
			return native(buf, row, col)
		end
		local buffer = buffers[buf]
		if not buffer or buffer.tick ~= key[1] or buffer.highlighter ~= key[2] then
			buffer = { tick = key[1], highlighter = key[2], rows = {}, count = 0, captures = 0 }
			buffers[buf] = buffer
		end
		serial = serial + 1
		buffer.used = serial
		if vim.tbl_count(buffers) > max_buffers then
			local oldest
			for number, item in pairs(buffers) do
				if not oldest or item.used < buffers[oldest].used then
					oldest = number
				end
			end
			buffers[oldest] = nil
		end
		local line = buffer.rows[row]
		if not line or not same(line.key, key) then
			local captures, count = {}, 0
			for index, part in ipairs(parts) do
				local items = {}
				for id, node, metadata in part.query:iter_captures(part.root, buf, row, row + 1) do
					items[#items + 1] = { id = id, node = node, priority = metadata.priority }
				end
				captures[index], count = items, count + #items
			end
			local valid, after = pcall(context, buf, row)
			local fresh = { key = key, captures = captures, count = count }
			if state.active and valid and after and same(key, after) and count <= max_captures then
				if buffer.count >= max_rows or buffer.captures + count > max_captures then
					buffer.rows, buffer.count, buffer.captures, line = {}, 0, 0, nil
				end
				buffer.count = buffer.count + (line and 0 or 1)
				buffer.captures = buffer.captures + count - (line and line.count or 0)
				buffer.rows[row] = fresh
			end
			line = fresh
		end
		local result = {}
		for index, part in ipairs(parts) do
			for _, item in ipairs(line.captures[index]) do
				-- Read the live highlight cache every time. Redraw may initialize
				-- new capture groups without an edit; themes can change their IDs.
				if part.highlights[item.id] and ts.is_in_node_range(item.node, row, col) then
					local capture = part.query.captures[item.id]
					if capture ~= nil then
						result[#result + 1] = { capture = capture, priority = item.priority }
					end
				end
			end
		end
		return result
	end
	return wrapper, clear
end
