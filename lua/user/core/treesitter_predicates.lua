local M = {}
local api, query = vim.api, vim.treesitter.query
-- Repeated redraws ask the same text-only predicates about unchanged nodes.
-- Bound both hidden-buffer retention and per-buffer text/result storage.
local buffers = {}
local serial, ready = 0, false
local kinds = { eq = true, ["lua-match"] = true, ["any-of"] = true }

local function evaluate(text, predicate, kind)
	if kind == "eq" then
		return text == predicate[3]
	elseif kind == "lua-match" then
		return text:find(predicate[3]) ~= nil
	end
	local set = predicate.string_set
	if not set then
		set = {}
		for index = 3, #predicate do
			set[predicate[index]] = true
		end
		predicate.string_set = set
	end
	return set[text] or false
end

local function matches(node, source, predicate, kind)
	if type(source) ~= "number" then
		return evaluate(vim.treesitter.get_node_text(node, source), predicate, kind)
	end
	if source == 0 then
		source = api.nvim_get_current_buf()
	end
	local tick = api.nvim_buf_get_changedtick(source)
	local buffer = buffers[source]
	if not buffer or buffer.tick ~= tick then
		buffer = { tick = tick, nodes = {}, count = 0, used = 0 }
		buffers[source] = buffer
		local count, oldest, oldest_serial = 0, nil, math.huge
		for bufnr, item in pairs(buffers) do
			count = count + 1
			if bufnr ~= source and item.used < oldest_serial then
				oldest, oldest_serial = bufnr, item.used
			end
		end
		if count > 4 then
			buffers[oldest] = nil
		end
	end
	serial = serial + 1
	buffer.used = serial
	local id = node:id()
	local sr, sc, er, ec = node:range()
	local entry = buffer.nodes[id]
	-- Node IDs can be reused by a new tree. An unchanged changedtick plus the
	-- same byte range is sufficient here: these predicates depend only on text.
	if not entry or entry[1] ~= sr or entry[2] ~= sc or entry[3] ~= er or entry[4] ~= ec then
		local text = vim.treesitter.get_node_text(node, source)
		if text == nil or #text > 1024 then
			return evaluate(text, predicate, kind)
		end
		if buffer.count >= 1024 then
			buffer.nodes, buffer.count = {}, 0
		end
		entry = { sr, sc, er, ec, text = text, values = {}, count = 0 }
		buffer.nodes[id] = entry
		buffer.count = buffer.count + 1
	end
	local result = entry.values[predicate]
	if result == nil then
		result = evaluate(entry.text, predicate, kind)
		-- A query can be replaced without editing its source buffer.
		if entry.count < 16 then
			entry.values[predicate] = result
			entry.count = entry.count + 1
		end
	end
	return result
end

local function register()
	for kind in pairs(kinds) do
		query.add_predicate("user-scroll-" .. kind .. "?", function(match, _, source, predicate)
			local nodes = match[predicate[2]]
			if not nodes or #nodes == 0 then
				return true
			end
			if kind == "eq" and type(predicate[3]) ~= "string" then
				-- Capture-to-capture equality depends on the whole match; use the
				-- native semantics without retaining a match-dependent result.
				local other = assert(match[predicate[3]], "Missing comparison capture for #eq?")
				assert(#other == 1, "#eq? does not support comparison with captures on multiple nodes")
				local value = vim.treesitter.get_node_text(other[1], source)
				for _, node in ipairs(nodes) do
					if value == nil or vim.treesitter.get_node_text(node, source) ~= value then
						return false
					end
				end
				return true
			end
			for _, node in ipairs(nodes) do
				local ok = matches(node, source, predicate, kind)
				if kind == "any-of" and ok then
					return true
				elseif kind ~= "any-of" and not ok then
					return false
				end
			end
			return kind ~= "any-of"
		end, { force = true })
	end
end

function M.rewrite(source)
	-- Parse predicate names so strings, comments, directives, and custom
	-- predicates remain byte-for-byte intact.
	local parser = vim.treesitter.get_string_parser(source, "query", { injections = { query = "" } })
	local tree = parser:parse()[1]
	assert(not tree:root():has_error(), "Invalid Python highlight query")
	local names =
		query.parse("query", [[((predicate name: (identifier) @name type: (predicate_type) @_kind) (#eq? @_kind "?"))]])
	local edits = {}
	for id, node in names:iter_captures(tree:root(), source, 0, -1) do
		if names.captures[id] == "name" and kinds[vim.treesitter.get_node_text(node, source)] then
			local _, _, start = node:start()
			edits[#edits + 1] = start
		end
	end
	for index = #edits, 1, -1 do
		local offset = edits[index]
		source = source:sub(1, offset) .. "user-scroll-" .. source:sub(offset + 1)
	end
	return source
end

function M.setup()
	if ready then
		return true
	end
	local parts = {}
	for _, path in ipairs(query.get_files("python", "highlights")) do
		local file = assert(io.open(path, "rb"))
		parts[#parts + 1] = file:read("*a")
		file:close()
	end
	local original = table.concat(parts)
	if original == "" or query.get("python", "highlights") ~= query.parse("python", original) then
		-- Public parse() memoization lets us recognize the file-backed query.
		-- Respect explicit query.set() overrides; skip on incompatible runtimes.
		return false
	end
	-- get_files() already resolved inheritance. A leading blank line keeps
	-- query.set() from interpreting the resolved files' modelines a second time.
	local source = "\n" .. M.rewrite(original)
	query.parse("python", source)
	register()
	query.set("python", "highlights", source)
	local group = api.nvim_create_augroup("user_scroll_query_cache", { clear = true })
	api.nvim_create_autocmd({ "BufUnload", "BufWipeout" }, {
		group = group,
		callback = function(event)
			buffers[event.buf] = nil
		end,
	})
	ready = true
	return true
end

return M
