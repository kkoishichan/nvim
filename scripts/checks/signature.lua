return function(tmp)
	for _, topic in ipairs({ "signature_parameters", "signature_layout", "signature_compact", "signature_render" }) do
		local path = vim.fs.joinpath(vim.env.NVIM_TEST_ROOT, "scripts", "checks", topic .. ".lua")
		assert(loadfile(path))()(tmp)
	end
	require("lazy").load({ plugins = { "blink.cmp" } })
	local signature = require("user.core.blink_signature")
	local window = require("blink.cmp.signature.window")
	local trigger = require("blink.cmp.signature.trigger")
	-- Blink finishes installing its own listeners on the scheduled startup turn.
	vim.wait(100, function()
		return false
	end, 10)
	signature.teardown()
	local original_open, original_update = window.open_with_signature_help, window.update_position
	local original_height = window.win.config.max_height
	local listeners = #trigger.hide_emitter.listeners
	local namespace = vim.api.nvim_get_namespaces().user_blink_signature
	local bufnr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_set_current_buf(bufnr)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "", "call(value)", "" })
	vim.api.nvim_win_set_cursor(0, { 2, 8 })
	local context = { id = 501, bufnr = bufnr, cursor = { 2, 8 } }
	local help = { signatures = { { label = "call(value: string)", parameters = { { label = "value: string" } } } } }
	local function marks()
		return vim.api.nvim_buf_get_extmarks(bufnr, namespace, 0, -1, {})
	end
	local autocmd_count
	for _ = 1, 3 do
		assert(signature.setup(), "Supported Blink internals did not activate")
		assert(#trigger.hide_emitter.listeners == listeners + 1, "Repeated setup stacked hide listeners")
		local count = #vim.api.nvim_get_autocmds({ group = "user_blink_signature_virtual" })
		autocmd_count = autocmd_count or count
		assert(count == autocmd_count, "Repeated setup stacked refresh callbacks")
		window.open_with_signature_help(context, help)
		assert(#marks() == 1, "Compact signature did not produce exactly one card")
	end

	-- Capture the actual debounce handle; cleanup must close it, and scheduled
	-- redraw/toggle work must not recreate a card after the owner has gone away.
	local original_defer = vim.defer_fn
	local timer
	vim.defer_fn = function(callback, delay)
		timer = original_defer(callback, delay)
		return timer
	end
	trigger.context = nil
	vim.api.nvim_exec_autocmds("CursorMovedI", { group = "user_blink_signature_virtual", buffer = bufnr })
	vim.defer_fn = original_defer
	assert(timer and not timer:is_closing(), "Discovery debounce was not scheduled")
	local requested = 0
	signature.toggle({
		is_signature_visible = function()
			return false
		end,
		show_signature = function()
			requested = requested + 1
			return true
		end,
	})
	signature.teardown()
	signature.teardown()
	assert(timer:is_closing(), "Teardown left the discovery timer alive")
	vim.wait(100, function()
		return false
	end, 10)
	assert(#marks() == 0 and requested == 0, "Stale callbacks survived signature teardown")
	assert(window.open_with_signature_help == original_open, "Teardown did not restore the original renderer")
	assert(window.update_position == original_update, "Teardown did not restore the original positioning")
	assert(window.win.config.max_height == original_height, "Teardown did not restore Blink's window height")
	assert(#trigger.hide_emitter.listeners == listeners, "Teardown leaked hide listeners")
	assert(vim.fn.exists("#user_blink_signature_virtual") == 0, "Teardown leaked its autocmd group")

	-- A complete config-module reload must release callbacks owned by the old
	-- Lua instance before capturing Blink functions for the new instance.
	assert(signature.setup(), "Could not set up reload fixture")
	local mapped_toggle = signature.toggle
	for _, name in ipairs({ "user.core.blink_signature", "user.core.signature.render", "user.core.signature.adapter" }) do
		package.loaded[name] = nil
	end
	signature = require("user.core.blink_signature")
	assert(signature.setup(), "Reloaded signature module did not activate")
	assert(#trigger.hide_emitter.listeners == listeners + 1, "Reload retained the previous owner")
	window.open_with_signature_help(context, help)
	assert(#marks() == 1, "Reloaded renderer duplicated the card")
	mapped_toggle({
		is_signature_visible = function()
			return false
		end,
	})
	assert(
		vim.wait(200, function()
			return window.win:is_open()
		end),
		"A mapping retained the inactive renderer after module reload"
	)
	signature.teardown()
	assert(window.open_with_signature_help == original_open, "Reload wrapped an older custom renderer")
	assert(window.update_position == original_update, "Reload wrapped older custom positioning")

	-- Simulate an upstream internal method disappearing while the public Blink
	-- API remains usable. This must leave Blink's normal signature path intact.
	local original_width = rawget(window.win, "get_content_width")
	window.win.get_content_width = false
	local enabled, reason = signature.setup()
	assert(not enabled and type(reason) == "string", "Missing internal capability did not select fallback")
	assert(window.open_with_signature_help == original_open, "Fallback changed Blink's normal renderer")
	local blink_fallback = 0
	signature.toggle({
		show_signature = function()
			blink_fallback = blink_fallback + 1
			return true
		end,
	})
	assert(blink_fallback == 0, "Fallback touched UI during the expression mapping")
	assert(
		vim.wait(200, function()
			return blink_fallback == 1
		end),
		"Public Blink signature fallback did not run"
	)
	window.win.get_content_width = original_width

	local native_fallback = 0
	local original_native = vim.lsp.buf.signature_help
	vim.lsp.buf.signature_help = function()
		native_fallback = native_fallback + 1
	end
	signature.toggle({
		show_signature = function()
			error("Public Blink signature API unavailable")
		end,
	})
	assert(
		vim.wait(200, function()
			return native_fallback == 1
		end),
		"Native LSP fallback did not run"
	)
	vim.lsp.buf.signature_help = original_native
	assert(signature.setup(), "Custom signatures did not recover when capabilities returned")
	signature.teardown()
	vim.api.nvim_buf_delete(bufnr, { force = true })
end
