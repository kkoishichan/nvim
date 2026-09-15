local M = {}
local api = vim.api
local plugin, callbacks
local pending, timer, token = {}, nil, nil
local css_cache = {}
local active = false
local delay_ms = 50

local function cancel()
	token = nil
	if timer and not timer:is_closing() then
		timer:stop()
		timer:close()
	end
	timer = nil
end

-- The pinned plugin exposes setup/toggle, but not refresh. Discover its own
-- registered callbacks through Neovim's public autocmd API; do not inspect
-- closure upvalues or replace callbacks belonging to other plugins.
local function capture_callbacks()
	local source = debug.getinfo(plugin.setup, "S").source
	local result, ids = {}, {}
	local change_id, scroll_id = -1, -1
	local registrations = api.nvim_get_autocmds({})
	for _, registration in ipairs(registrations) do
		local callback = registration.callback
		if type(callback) == "function" and debug.getinfo(callback, "S").source == source then
			if registration.event == "TextChanged" and registration.id > change_id then
				result.change = callback
				change_id = registration.id
			elseif registration.event == "WinScrolled" or registration.event == "VimResized" then
				if registration.id > scroll_id then
					result.scroll = callback
					scroll_id = registration.id
				end
				ids[registration.id] = true
			end
		end
	end
	assert(result.change and result.scroll, "Color preview adapter could not identify the locked plugin callbacks")
	for _, registration in ipairs(registrations) do
		if ids[registration.id] then
			assert(
				registration.event == "WinScrolled" or registration.event == "VimResized",
				"Color preview adapter must preserve non-scroll plugin callbacks"
			)
		end
	end
	for id in pairs(ids) do
		api.nvim_del_autocmd(id)
	end
	return result
end

local function viewports(bufnr)
	local ranges = {}
	for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
		if api.nvim_win_is_valid(win) and api.nvim_win_get_buf(win) == bufnr then
			local range = api.nvim_win_call(win, function()
				return { first = vim.fn.line("w0"), last = vim.fn.line("w$"), win = win }
			end)
			ranges[#ranges + 1] = range
		end
	end
	table.sort(ranges, function(a, b)
		return a.first < b.first or (a.first == b.first and a.last < b.last)
	end)
	return ranges
end

local function redraw(bufnr)
	if not api.nvim_buf_is_valid(bufnr) or not api.nvim_buf_is_loaded(bufnr) or not plugin.is_active() then
		return
	end
	local ranges = viewports(bufnr)
	if #ranges == 0 then
		return
	end
	local utils = require("nvim-highlight-colors.utils")
	local colors = require("nvim-highlight-colors.color.utils")
	local original = utils.get_visible_rows_by_buffer_id
	local original_lsp = utils.highlight_with_lsp
	local original_css = colors.get_css_var_color
	local tick = api.nvim_buf_get_changedtick(bufnr)
	local lsp_request
	local selected
	-- The pinned helper uses bufwinid(), which always selects the first split.
	-- Adapt only this synchronous call, so each actual viewport is covered.
	-- This is a plugin compatibility shim, never a Neovim API override.
	utils.get_visible_rows_by_buffer_id = function(buffer)
		if buffer == bufnr and selected then
			return { selected.first, selected.last }
		end
		return original(buffer)
	end
	-- documentColor describes the whole document. Collect the viewport matches
	-- and retain one original LSP pass per buffer, rather than one per split.
	utils.highlight_with_lsp = function(buffer, namespace, positions, options)
		if buffer ~= bufnr then
			return original_lsp(buffer, namespace, positions, options)
		end
		lsp_request = lsp_request or { namespace = namespace, positions = {}, options = options }
		vim.list_extend(lsp_request.positions, positions)
	end
	-- The upstream variable resolver searches the whole current buffer per use.
	-- Reuse its exact result for this text version, including missing variables.
	-- Keep the override inside the synchronous target-window render only.
	colors.get_css_var_color = function(color, row_offset)
		if api.nvim_get_current_buf() ~= bufnr then
			return original_css(color, row_offset)
		end
		local entry = css_cache[bufnr]
		if not entry or entry.tick ~= tick then
			entry = { tick = tick, values = {} }
			css_cache[bufnr] = entry
		end
		local offset = row_offset or false
		entry.values[offset] = entry.values[offset] or {}
		local values = entry.values[offset]
		if values[color] == nil then
			values[color] = original_css(color, row_offset) or false
		end
		return values[color] or nil
	end
	local ok, err = xpcall(function()
		local covered, clear = 0, true
		for _, range in ipairs(ranges) do
			if range.last > covered then
				selected = { first = math.max(range.first, covered + 1), last = range.last }
				api.nvim_win_call(range.win, function()
					local callback = clear and callbacks.change or callbacks.scroll
					callback({ buf = bufnr, event = "WinScrolled", match = tostring(range.win) })
				end)
				clear, covered = false, range.last
			end
		end
	end, debug.traceback)
	utils.get_visible_rows_by_buffer_id = original
	utils.highlight_with_lsp = original_lsp
	colors.get_css_var_color = original_css
	if ok and lsp_request then
		ok, err = xpcall(function()
			-- Query capabilities afresh: dynamic registration can change without
			-- LspAttach. Avoid the upstream vim.version()/API metadata work when
			-- attached clients (for example typos_lsp) cannot provide colors.
			if #vim.lsp.get_clients({ bufnr = bufnr, method = "textDocument/documentColor" }) > 0 then
				original_lsp(bufnr, lsp_request.namespace, lsp_request.positions, lsp_request.options)
			end
		end, debug.traceback)
	end
	if not ok then
		vim.notify(err, vim.log.levels.ERROR, { title = "Color preview" })
	end
end

local function queue_buffer(bufnr)
	if
		not active
		or not api.nvim_buf_is_valid(bufnr)
		or not api.nvim_buf_is_loaded(bufnr)
		or vim.bo[bufnr].buftype ~= ""
	then
		return
	end
	pending[bufnr] = true
	if token then
		return
	end
	local request = {}
	token = request
	timer = vim.defer_fn(function()
		if token ~= request or not active then
			return
		end
		timer, token = nil, nil
		local batch = pending
		pending = {}
		for buffer in pairs(batch) do
			redraw(buffer)
		end
	end, delay_ms)
end

local function queue_window(win)
	if win and api.nvim_win_is_valid(win) then
		queue_buffer(api.nvim_win_get_buf(win))
	end
end

local function queue_visible()
	for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
		queue_window(win)
	end
end

function M.shutdown()
	active = false
	cancel()
	pending = {}
	css_cache = {}
	if vim._user_color_preview == M then
		vim._user_color_preview = nil
	end
end

function M.setup(opts)
	local previous = vim._user_color_preview
	if previous and previous ~= M then
		previous.shutdown()
	end
	M.shutdown()
	plugin = require("nvim-highlight-colors")
	-- Store the callbacks on their actual plugin instance, so reloading this
	-- adapter reuses them, while a new plugin instance is captured afresh.
	callbacks = plugin._user_color_preview_callbacks or capture_callbacks()
	plugin._user_color_preview_callbacks = callbacks
	vim._user_color_preview = M
	local group = api.nvim_create_augroup("user_color_preview", { clear = true })
	active = true
	api.nvim_create_autocmd("WinScrolled", {
		group = group,
		callback = function(event)
			-- event.buf can refer to the focused buffer while the mouse scrolls
			-- another split. Match and v:event identify the windows that moved.
			queue_window(tonumber(event.match))
			for key in pairs(vim.v.event) do
				queue_window(tonumber(key))
			end
		end,
	})
	api.nvim_create_autocmd({ "VimResized", "TabEnter" }, { group = group, callback = queue_visible })
	api.nvim_create_autocmd({ "BufWinEnter", "BufReadPost" }, {
		group = group,
		callback = function(event)
			queue_buffer(event.buf)
		end,
	})
	api.nvim_create_autocmd({ "BufUnload", "BufWipeout" }, {
		group = group,
		callback = function(event)
			pending[event.buf] = nil
			css_cache[event.buf] = nil
			if not next(pending) then
				cancel()
			end
		end,
	})
	api.nvim_create_autocmd("VimLeavePre", { group = group, callback = M.shutdown })
	plugin.setup(opts)
	queue_visible()
end

return M
