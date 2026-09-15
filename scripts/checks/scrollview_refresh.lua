return function()
	local api = vim.api
	local old_ignore, old_enabled = vim.o.eventignore, vim.g.scrollview_enabled
	vim.o.eventignore = "all"
	require("lazy").load({ plugins = { "nvim-scrollview" } })
	local real = require("scrollview")
	-- Its Vimscript initializer is deferred and must finish before the isolated
	-- scheduler fixture temporarily substitutes the exported plugin table.
	vim.wait(100, function()
		return false
	end, 1)
	local bridge = require("user.core.scrollview_refresh")
	if real._user_scrollview_refresh then
		real._user_scrollview_refresh.shutdown()
	end
	local calls, keys = 0, {}
	local function original()
		calls = calls + 1
	end
	local native_refresh, native_mouse = function() end, function() end
	local fake = {
		refresh_impl_async = original,
		refresh = native_refresh,
		handle_mouse = native_mouse,
		register_key_sequence_callback = function(key, modes, callback)
			assert(modes == "nvsit", "Wheel adapter changed unrelated input modes")
			keys[key] = callback or false
		end,
	}
	package.loaded.scrollview = fake
	vim.g.scrollview_enabled = true
	assert(bridge.setup())
	for _, key in ipairs({ "<ScrollWheelUp>", "<ScrollWheelDown>" }) do
		assert(keys[vim.keycode(key)] == false, "Obsolete wheel refresh callback survived")
	end
	assert(fake.refresh == native_refresh and fake.handle_mouse == native_mouse, "Native manual/drag paths changed")
	for _ = 1, 300 do
		fake.refresh_impl_async()
	end
	assert(calls == 0, "Scroll events synchronously invoked the renderer")
	assert(
		vim.wait(250, function()
			return calls == 1
		end, 1),
		"A scroll burst did not invoke the renderer"
	)
	assert(calls == 1, "A scroll burst invoked more than one renderer")
	local burst_calls = calls
	-- Keep requesting work before every timer deadline. A trailing debounce
	-- would starve here; a fixed queue must make progress while input continues.
	assert(
		vim.wait(250, function()
			fake.refresh_impl_async()
			return calls >= burst_calls + 3
		end, 1),
		"Continuous scroll requests starved refresh"
	)
	bridge.shutdown()
	local settled = calls
	assert(fake.refresh_impl_async == original, "Shutdown did not restore the original export")
	for _, key in ipairs({ "<ScrollWheelUp>", "<ScrollWheelDown>" }) do
		assert(keys[vim.keycode(key)] == original, "Shutdown did not restore native wheel callbacks")
	end
	assert(bridge.setup())
	fake.refresh_impl_async()
	vim.g.scrollview_enabled = false
	vim.wait(40, function()
		return false
	end, 1)
	assert(calls == settled, "Queued work refreshed a disabled scrollbar")
	fake.refresh_impl_async()
	vim.g.scrollview_enabled = true
	vim.wait(40, function()
		return false
	end, 1)
	assert(calls == settled, "A request while disabled survived re-enabling")
	fake.refresh_impl_async()
	package.loaded["user.core.scrollview_refresh"] = nil
	bridge = require("user.core.scrollview_refresh")
	assert(bridge.setup())
	assert(bridge.setup())
	vim.wait(40, function()
		return false
	end, 1)
	assert(calls == settled, "An obsolete timer survived adapter reload")
	fake.refresh_impl_async()
	assert(
		vim.wait(250, function()
			return calls == settled + 1
		end, 1),
		"Reload accumulated wrappers or lost refresh"
	)
	assert(#api.nvim_get_autocmds({ group = "user_scrollview_refresh" }) == 1, "Reload accumulated cleanup owners")
	-- Replacing both modules must find the owner outside the old plugin table.
	local old_bridge, before_double_reload = bridge, calls
	local replacement_calls = 0
	local function replacement_original()
		replacement_calls = replacement_calls + 1
	end
	local replacement = {
		refresh_impl_async = replacement_original,
		register_key_sequence_callback = function() end,
	}
	fake.refresh_impl_async()
	package.loaded.scrollview = replacement
	package.loaded["user.core.scrollview_refresh"] = nil
	bridge = require("user.core.scrollview_refresh")
	assert(bridge.setup())
	old_bridge.shutdown()
	local cleanup = api.nvim_get_autocmds({ group = "user_scrollview_refresh" })
	assert(
		#cleanup == 1 and cleanup[1].callback == bridge.shutdown,
		"An old owner removed or replaced the new cleanup handler"
	)
	assert(
		vim._user_scrollview_refresh == bridge and fake._user_scrollview_refresh == nil,
		"Double reload retained the obsolete owner"
	)
	vim.wait(40, function()
		return false
	end, 1)
	assert(calls == before_double_reload, "An obsolete timer survived replacement of both modules")
	replacement.refresh_impl_async()
	assert(
		vim.wait(250, function()
			return replacement_calls == 1
		end, 1),
		"The replacement plugin lost its refresh queue"
	)
	bridge.shutdown()
	assert(
		vim._user_scrollview_refresh == nil and replacement.refresh_impl_async == replacement_original,
		"Shutdown did not release the independent owner and plugin export"
	)
	package.loaded.scrollview = fake
	bridge.shutdown()
	fake.register_key_sequence_callback = nil
	assert(
		not bridge.setup() and fake.refresh_impl_async == original,
		"Unsupported interface did not retain native refresh"
	)
	package.loaded.scrollview = real

	-- Exercise the locked plugin itself, including its dynamic autocmd lookup,
	-- native virtual fold geometry, all enabled sign sources, and toggle rebuild.
	vim.cmd.tabnew()
	local win, buf = api.nvim_get_current_win(), api.nvim_get_current_buf()
	local lines = {}
	for index = 1, 240 do
		lines[index] = "local item = " .. index
	end
	api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo.filetype = "lua"
	vim.wo.wrap, vim.wo.foldenable, vim.wo.foldmethod = false, true, "manual"
	vim.cmd("20,200fold")
	local active_groups = {}
	for _, name in ipairs(real.get_sign_groups()) do
		active_groups[name] = real.is_sign_group_active(name)
	end
	local real_mouse, real_refresh = real.handle_mouse, real.refresh
	local renders = 0
	real.register_sign_group("refresh_check")
	real.set_sign_group_callback("refresh_check", function()
		renders = renders + 1
	end)
	real.set_sign_group_state("refresh_check", true)
	real.set_state(true)
	vim.wait(100, function()
		return false
	end, 1)
	assert(bridge.setup())
	local before = renders
	for _ = 1, 100 do
		real.refresh_impl_async()
	end
	assert(renders == before, "Locked plugin rendered synchronously")
	assert(
		vim.wait(250, function()
			return renders > before
		end, 1),
		"Locked plugin queue did not render"
	)
	assert(renders == before + 1, "Locked plugin rendered one burst repeatedly")
	assert(vim.g.scrollview_mode == "virtual", "Adapter changed the configured fold-aware mode")
	assert(vim.fn.foldclosed(20) == 20 and vim.fn.foldclosedend(20) == 200, "Refresh changed closed folds")
	assert(api.nvim_get_current_win() == win, "Refresh changed focus")
	local function bar_height()
		for _, candidate in ipairs(api.nvim_tabpage_list_wins(0)) do
			local ok, props = pcall(api.nvim_win_get_var, candidate, "scrollview_props")
			if ok and props.parent_winid == win and props.type == 0 then
				return props.height
			end
		end
	end
	local folded_height = assert(bar_height(), "Locked plugin did not render a scrollbar")
	vim.cmd.normal({ "zR", bang = true })
	before = renders
	-- Explicit refresh bypasses our queue exactly as before.
	real.refresh()
	assert(
		vim.wait(250, function()
			return renders > before
		end, 1),
		"Manual refresh was blocked"
	)
	assert(assert(bar_height()) < folded_height, "Virtual geometry stopped reflecting closed folds")
	assert(real.handle_mouse == real_mouse and real.refresh == real_refresh, "Native direct paths were replaced")
	for name, enabled in pairs(active_groups) do
		assert(real.is_sign_group_active(name) == enabled, "Adapter changed sign group " .. name)
	end
	real.set_state(false)
	real.set_state(true)
	vim.wait(100, function()
		return false
	end, 1)
	local registrations = api.nvim_get_autocmds({ group = "scrollview", event = "WinScrolled" })
	assert(
		#registrations == 1 and registrations[1].command:find("refresh_impl_async", 1, true),
		"Toggle lost its dynamic refresh route"
	)
	before = renders
	for _ = 1, 100 do
		vim.cmd(registrations[1].command)
	end
	assert(
		vim.wait(250, function()
			return renders > before
		end, 1),
		"Recreated scroll autocmd did not reach the adapter"
	)
	assert(renders == before + 1, "Toggle bypassed the coalescing adapter")
	real.deregister_sign_group("refresh_check", false)
	bridge.shutdown()
	real.set_state(old_enabled == true)
	vim.o.eventignore = old_ignore
	print(
		"Scrollview refresh passed: 300 requests -> 1 native callback, continuous-input progress, virtual folds, toggle and cleanup"
	)
end
