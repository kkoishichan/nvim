-- Coalesce vim-illuminate refreshes. The locked plugin sends a reference
-- request on every CursorMoved, CursorMovedI, ModeChanged and TextChanged, and
-- only its `delay` option waits before drawing: holding a motion key or a
-- wheel burst therefore produces one documentHighlight request per event, each
-- cancelling the previous one on the client while the server still works on
-- it. This adapter keeps the plugin's immediate clearing of a highlight the
-- cursor has left and defers the request until the cursor has rested briefly,
-- so a burst becomes a single request and a single highlight pass.
local M = {}
local api = vim.api
local owner
local debounce_ms = 100
-- The wrapper relies on this engine's public refresh entry and helper modules.
-- A plugin update keeps the native behaviour until the adapter is revalidated.
local engine_hash = "7bb618f6612d94440640f299bbca8a03ad1ff97b0b965625c0f64249b5a6088b"

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

local function close_timer(timer)
	if timer and not timer:is_closing() then
		timer:stop()
		timer:close()
	end
end

function M.shutdown()
	local previous = owner
	if not previous then
		return
	end
	owner = nil
	previous.active = false
	previous.pending = nil
	close_timer(previous.timer)
	previous.timer = nil
	if previous.engine.refresh_references == previous.wrapper then
		previous.engine.refresh_references = previous.native
	end
	if previous.group then
		pcall(api.nvim_del_augroup_by_id, previous.group)
	end
	if vim._user_illuminate_refresh == M then
		vim._user_illuminate_refresh = nil
	end
end

function M.stats()
	return {
		active = owner ~= nil,
		coalesced = owner and owner.coalesced or 0,
		refreshes = owner and owner.refreshes or 0,
	}
end

function M.setup()
	local previous = vim._user_illuminate_refresh
	if previous and previous ~= M then
		previous.shutdown()
	end
	M.shutdown()
	local engine = require("illuminate.engine")
	local reference = require("illuminate.reference")
	local highlight = require("illuminate.highlight")
	local util = require("illuminate.util")
	if
		not has_source(engine.refresh_references, engine_hash)
		or type(reference.buf_cursor_in_references) ~= "function"
		or type(reference.buf_set_references) ~= "function"
		or type(highlight.buf_clear_references) ~= "function"
		or type(util.get_cursor_pos) ~= "function"
	then
		return false
	end
	local state = {
		active = true,
		engine = engine,
		native = engine.refresh_references,
		coalesced = 0,
		refreshes = 0,
	}
	local function flush()
		local request = state.pending
		state.pending = nil
		if not state.active or not request then
			return
		end
		-- The plugin's own poll discards any answer for a window that is no
		-- longer current, so a request for one is never worth sending.
		if
			not api.nvim_buf_is_valid(request.bufnr)
			or not api.nvim_win_is_valid(request.winid)
			or api.nvim_get_current_win() ~= request.winid
			or api.nvim_win_get_buf(request.winid) ~= request.bufnr
		then
			return
		end
		state.refreshes = state.refreshes + 1
		state.native(request.bufnr, request.winid)
	end
	state.wrapper = function(bufnr, winid)
		if not state.active then
			return state.native(bufnr, winid)
		end
		bufnr = bufnr or api.nvim_get_current_buf()
		winid = winid or api.nvim_get_current_win()
		if not api.nvim_buf_is_valid(bufnr) or not api.nvim_win_is_valid(winid) then
			return
		end
		-- Leaving a highlighted word still clears at once, exactly as the
		-- plugin does before it requests; only the request itself waits.
		local ok, inside = pcall(reference.buf_cursor_in_references, bufnr, util.get_cursor_pos(winid))
		if ok and not inside then
			highlight.buf_clear_references(bufnr)
			reference.buf_set_references(bufnr, {})
		end
		if state.pending then
			state.coalesced = state.coalesced + 1
		end
		state.pending = { bufnr = bufnr, winid = winid }
		state.timer = state.timer or vim.uv.new_timer()
		-- A trailing debounce: the request goes out once the cursor rests.
		state.timer:stop()
		state.timer:start(debounce_ms, 0, vim.schedule_wrap(flush))
	end
	engine.refresh_references = state.wrapper
	owner = state
	vim._user_illuminate_refresh = M
	state.group = api.nvim_create_augroup("user_illuminate_refresh", { clear = true })
	api.nvim_create_autocmd("VimLeavePre", { group = state.group, callback = M.shutdown })
	return true
end

return M
