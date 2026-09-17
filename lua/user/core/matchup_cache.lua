local M = {}
local api, ts = vim.api, vim.treesitter
local owner
local max_buffers, max_matches, max_text_bytes = 4, 1024, 65536
-- This adapter depends on the locked plugin's raw-match contract. A plugin
-- update keeps its native implementation until the adapter is revalidated.
local source_hash = "c17981d46f1ca32efc0db56c893c32b5b7d0ed8559bde1b9f0854a007d6f50e4"
local syntax_hash = "dbaa69a93bdc254ca66c982fb559161c8a99cb5e27f80a4344cb97ae5db5c536"
local highlights_hash = "0aeeac94273d49ef5f1eb0563f3a0d3d39e7dceb28a0a08781d2f524c0ed7eeb"

local function same(left, right)
	if #left ~= #right then
		return false
	end
	for index, value in ipairs(left) do
		if value ~= right[index] then
			return false
		end
	end
	return true
end

local function context(bufnr)
	local parser = ts.get_parser(bufnr)
	local cursor = api.nvim_win_get_cursor(0)
	local stopline = vim.g.matchup_treesitter_stopline
	local first = math.max(cursor[1] - stopline, 0)
	local last = math.min(cursor[1] + stopline, api.nvim_buf_line_count(bufnr))
	-- Match the plugin's parse range and injection selection exactly. Parsing
	-- first also retires edited/replaced trees before any cached node is used.
	parser:parse({ first, last })
	local key = { api.nvim_buf_get_changedtick(bufnr), parser, first, last }
	local language = parser:language_for_range({ cursor[1] - 1, cursor[2], cursor[1] - 1, cursor[2] })
	while language do
		key[#key + 1] = language
		if language:lang() ~= "comment" then
			local query = ts.query.get(language:lang(), "matchup")
			-- Custom predicates/directives can depend on state outside the
			-- buffer. Leave all such queries on the original evaluation path.
			if query and next(query.info.patterns) ~= nil then
				return nil
			end
			key[#key + 1] = query or false
			key[#key + 1] = query and query.iter_matches or false
			for _, tree in ipairs(language:trees()) do
				key[#key + 1] = tree
			end
		end
		language = language:parent()
	end
	return key
end

local function copy_matches(matches)
	local result = {}
	for index, match in ipairs(matches) do
		local range = match.range
		result[index] = {
			identifier = match.identifier,
			type = match.type,
			range = { range[1], range[2], range[3], range[4] },
			length = match.length,
			last_node = match.last_node,
			text = match.text,
		}
	end
	return result
end

local function fits(matches)
	if #matches > max_matches then
		return false
	end
	local bytes = 0
	for _, match in ipairs(matches) do
		bytes = bytes + #match.text
		if bytes > max_text_bytes then
			return false
		end
	end
	return true
end

local function skip_ranges(matches)
	local result = {}
	for _, match in ipairs(matches) do
		if match.type == "skip" then
			local range = match.range
			result[("range_%d_%d_%d_%d"):format(range[1], range[2], range[3], range[4])] = true
		end
	end
	return result
end

local function has_source(fn, expected)
	if type(fn) ~= "function" then
		return false
	end
	local source = debug.getinfo(fn, "S").source
	local file = source:sub(1, 1) == "@" and io.open(source:sub(2), "rb") or nil
	if not file then
		return false
	end
	local text = file:read("*a")
	file:close()
	return vim.fn.sha256(text) == expected
end

function M.shutdown()
	local previous = owner
	if not previous then
		return
	end
	owner = nil
	previous.active, previous.buffers = false, {}
	if previous.plugin.get_matches == previous.wrapper then
		previous.plugin.get_matches = previous.native
	end
	if previous.syntax.get_skips == previous.skip_wrapper then
		previous.syntax.get_skips = previous.native_skips
	end
	if previous.highlights.get_hl_groups_at_position == previous.highlight_wrapper then
		previous.highlights.get_hl_groups_at_position = previous.native_highlights
	end
	previous.clear_highlights()
	previous.restore_bridge()
	pcall(api.nvim_del_augroup_by_id, previous.group)
	if vim._user_matchup_cache == M then
		vim._user_matchup_cache = nil
	end
end

function M.setup()
	local previous = vim._user_matchup_cache
	if previous and previous ~= M then
		previous.shutdown()
	end
	M.shutdown()
	local plugin = require("treesitter-matchup.internal")
	local syntax = require("treesitter-matchup.syntax")
	local highlights = require("treesitter-matchup.third-party.utils")
	if
		not has_source(plugin.get_matches, source_hash)
		or not has_source(syntax.get_skips, syntax_hash)
		or not has_source(highlights.get_hl_groups_at_position, highlights_hash)
	then
		return false
	end
	local state = {
		active = true,
		buffers = {},
		sequence = 0,
		plugin = plugin,
		native = plugin.get_matches,
		syntax = syntax,
		native_skips = syntax.get_skips,
		highlights = highlights,
		native_highlights = highlights.get_hl_groups_at_position,
	}
	-- The locked native consumers only read these records. They can borrow
	-- the cache internally; public callers still receive isolated copies.
	local readers, dependencies = {}, {}
	local internal_source = debug.getinfo(state.native, "S").source
	local compatible = true
	for _, name in ipairs({
		"get_delim",
		"get_matching",
		"get_active_matches",
		"do_match_result",
		"containing_scope",
		"get_scopes",
	}) do
		local fn = plugin[name]
		if type(fn) ~= "function" or debug.getinfo(fn, "S").source ~= internal_source then
			compatible = false
		else
			dependencies[name] = fn
		end
	end
	if compatible then
		readers[plugin.get_delim], readers[plugin.get_matching] = true, true
	end
	local function can_borrow(caller)
		if not readers[caller] then
			return false
		end
		for name, fn in pairs(dependencies) do
			if plugin[name] ~= fn then
				return false
			end
		end
		return true
	end
	local function obtain(bufnr)
		bufnr = (bufnr == nil or bufnr == 0) and api.nvim_get_current_buf() or bufnr
		local ok, key = pcall(context, bufnr)
		if not ok or not key then
			state.buffers[bufnr] = nil
			return nil
		end
		state.sequence = state.sequence + 1
		local cached = state.buffers[bufnr]
		if cached and same(cached.key, key) then
			cached.used = state.sequence
			return cached.matches, cached
		end
		state.buffers[bufnr] = nil
		local matches = state.native(bufnr)
		local valid, after = pcall(context, bufnr)
		-- A long native query may yield via vim.wait(). Never cache results
		-- across an edit, reparse, query replacement, shutdown or reload.
		if state.active and valid and after and same(key, after) and fits(matches) then
			if vim.tbl_count(state.buffers) >= max_buffers then
				local oldest
				for buf, entry in pairs(state.buffers) do
					if not oldest or entry.used < state.buffers[oldest].used then
						oldest = buf
					end
				end
				state.buffers[oldest] = nil
			end
			cached = { key = key, matches = matches, skips = skip_ranges(matches), used = state.sequence }
			state.buffers[bufnr] = cached
			return matches, cached
		end
		return matches
	end
	state.wrapper = function(bufnr)
		if not state.active then
			return state.native(bufnr)
		end
		local matches, cached = obtain(bufnr)
		if cached and can_borrow(debug.getinfo(2, "f").func) then
			-- get_matching also excludes its seed by strict row/column order,
			-- so sharing that record cannot change the matching candidates.
			return matches
		end
		return cached and copy_matches(matches) or matches or state.native(bufnr)
	end
	state.skip_wrapper = function(bufnr)
		if not state.active then
			return state.native_skips(bufnr)
		end
		local matches, cached = obtain(bufnr)
		if not matches then
			return state.native_skips(bufnr)
		end
		-- Most Python queries have no skip captures. Checking a candidate
		-- delimiter must not clone every unrelated match just to find none.
		local result = {}
		for range in pairs(cached and cached.skips or skip_ranges(matches)) do
			result[range] = true
		end
		return result
	end
	state.highlight_wrapper, state.clear_highlights =
		require("user.core.matchup_highlights")(state, state.native_highlights)
	owner = state
	plugin.get_matches = state.wrapper
	syntax.get_skips = state.skip_wrapper
	highlights.get_hl_groups_at_position = state.highlight_wrapper
	state.restore_bridge = require("user.core.matchup_bridge").setup()
	vim._user_matchup_cache = M
	state.group = api.nvim_create_augroup("user_matchup_cache", { clear = true })
	api.nvim_create_autocmd({ "BufUnload", "BufWipeout" }, {
		group = state.group,
		callback = function(event)
			state.buffers[event.buf] = nil
			state.clear_highlights(event.buf)
		end,
	})
	api.nvim_create_autocmd("VimLeavePre", { group = state.group, callback = M.shutdown })
	return true
end

return M
