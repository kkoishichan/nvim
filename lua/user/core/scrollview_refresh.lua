local M = {}
local plugin, original, timer, pending, group
local active, wheel_removed = false, false
local modes = "nvsit"
local wheel_keys = { "<ScrollWheelUp>", "<ScrollWheelDown>" }

local function cancel()
	pending = nil
	if timer and not timer:is_closing() then
		timer:stop()
		timer:close()
	end
	timer = nil
end

local function queue()
	if not active or not vim.g.scrollview_enabled or pending then
		return
	end
	local request = {}
	pending = request
	-- A fixed window, not a restarted debounce: continuous input still redraws.
	-- The upstream callback retains its two deferred turns and native geometry.
	-- The rail needs fewer frames than the text. A 40 ms cap avoids repeatedly
	-- invalidating syntax highlights under its floating windows during a swipe.
	timer = vim.defer_fn(function()
		if pending ~= request or not active then
			return
		end
		timer, pending = nil, nil
		if vim.g.scrollview_enabled then
			original()
		end
	end, 40)
end

function M.shutdown()
	active = false
	cancel()
	if plugin then
		if plugin.refresh_impl_async == queue then
			plugin.refresh_impl_async = original
		end
		if wheel_removed then
			for _, key in ipairs(wheel_keys) do
				pcall(plugin.register_key_sequence_callback, vim.keycode(key), modes, original)
			end
		end
		if plugin._user_scrollview_refresh == M then
			plugin._user_scrollview_refresh = nil
		end
	end
	if group then
		pcall(vim.api.nvim_del_augroup_by_id, group)
	end
	if vim._user_scrollview_refresh == M then
		vim._user_scrollview_refresh = nil
	end
	plugin, original, group = nil, nil, nil
	wheel_removed = false
end

function M.setup()
	local scrollview = require("scrollview")
	-- A plugin reload replaces its table as well. Keep an independent owner so
	-- its old timer and cleanup group are retired before creating a new one.
	local previous = vim._user_scrollview_refresh or scrollview._user_scrollview_refresh
	if previous and previous ~= M then
		previous.shutdown()
	end
	M.shutdown()
	-- These exports belong to the locked scrollview version. If its interface
	-- changes, keep the native implementation instead of patching internals.
	if
		type(scrollview.refresh_impl_async) ~= "function"
		or type(scrollview.register_key_sequence_callback) ~= "function"
	then
		return false, "Scrollview refresh adapter is unavailable for this plugin interface"
	end
	plugin, original = scrollview, scrollview.refresh_impl_async
	if vim.fn.has("nvim-0.9") == 1 then
		-- Upstream added this duplicate route for non-current-window scrolling
		-- before 0.9. Modern WinScrolled covers every affected window. Preserve
		-- all fold-key callbacks and the separate native mouse drag handler.
		wheel_removed = true
		local ok, err = pcall(function()
			for _, key in ipairs(wheel_keys) do
				plugin.register_key_sequence_callback(vim.keycode(key), modes, nil)
			end
		end)
		if not ok then
			M.shutdown()
			return false, err
		end
	end
	active = true
	plugin.refresh_impl_async = queue
	plugin._user_scrollview_refresh = M
	vim._user_scrollview_refresh = M
	group = vim.api.nvim_create_augroup("user_scrollview_refresh", { clear = true })
	vim.api.nvim_create_autocmd("VimLeavePre", { group = group, callback = M.shutdown })
	return true
end

return M
