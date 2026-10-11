return function()
	local plugins = require("lazy.core.config").plugins
	local plugin = require("lazy.core.plugin")
	local function opts(name)
		return plugin.values(assert(plugins[name], "missing plugin: " .. name), "opts", false)
	end
	local completion_opts = opts("blink.cmp")
	assert(completion_opts.keymap.preset == "super-tab", "Completion no longer uses IDE-style Tab acceptance")
	assert(
		type(completion_opts.keymap["<C-Space>"][1]) == "function"
			and completion_opts.keymap["<C-Space>"][1]() == true
			and completion_opts.keymap["<C-Space>"][2] == nil
			and type(completion_opts.cmdline.keymap["<C-Space>"][1]) == "function"
			and completion_opts.cmdline.keymap["<C-Space>"][1]() == true,
		"Ctrl-Space is no longer reserved exclusively for the input method"
	)
	assert(
		vim.deep_equal(completion_opts.keymap["<M-Space>"], { "show", "show_documentation", "hide_documentation" }),
		"Manual completion was not moved to Alt-Space"
	)
	assert(
		vim.deep_equal(completion_opts.keymap["<CR>"], { "accept", "fallback" }),
		"Enter no longer safely confirms an explicitly selected completion"
	)
	-- Blink stays out of prompt buffers, whose Escape and completion belong to
	-- vim.ui.input and the DAP REPL.
	do
		local prompt = vim.api.nvim_create_buf(false, true)
		vim.bo[prompt].buftype = "prompt"
		local plain = vim.api.nvim_create_buf(false, true)
		local enabled = completion_opts.enabled
		assert(vim.api.nvim_buf_call(prompt, enabled) == false, "Blink is enabled in a prompt buffer")
		assert(vim.api.nvim_buf_call(plain, enabled) == true, "Blink is disabled in an ordinary buffer")
		vim.api.nvim_buf_delete(prompt, { force = true })
		vim.api.nvim_buf_delete(plain, { force = true })
	end
	local completion_escape = completion_opts.keymap["<Esc>"]
	assert(
		type(completion_escape[1]) == "function" and completion_escape[2] == "fallback" and completion_escape[3] == nil,
		"Escape no longer dismisses popups and leaves Insert mode in one keypress"
	)
	local blink_closed = {}
	local function stub(menu_visible)
		return {
			is_documentation_visible = function()
				return true
			end,
			hide_documentation = function()
				blink_closed.documentation = true
			end,
			is_signature_visible = function()
				return true
			end,
			hide_signature = function()
				blink_closed.signature = true
			end,
			is_visible = function()
				return menu_visible
			end,
			cancel = function(cancel_opts)
				blink_closed.completion = true
				blink_closed.callback = cancel_opts and cancel_opts.callback
				menu_visible = false
				return true
			end,
		}
	end
	-- Menu open: the key is consumed, the cancel runs in Insert mode and only
	-- its callback leaves Insert mode (the preview undo needs Insert mode).
	assert(completion_escape[1](stub(true)) == true, "Escape with the menu open fell through before the cancel")
	assert(blink_closed.completion and type(blink_closed.callback) == "function", "Escape did not cancel the menu")
	local fed
	local feedkeys = vim.api.nvim_feedkeys
	vim.api.nvim_feedkeys = function(keys, mode)
		fed = { keys = keys, mode = mode }
	end
	blink_closed.callback()
	vim.api.nvim_feedkeys = feedkeys
	assert(fed and fed.keys == vim.keycode("<Esc>") and fed.mode == "n", "Escape was not fed after the cancel")
	assert(blink_closed.documentation and blink_closed.signature, "Other popups were not closed after the cancel")
	-- No menu: the other popups close and Blink's fallback leaves Insert mode.
	blink_closed = {}
	assert(completion_escape[1](stub(false)) == nil, "Escape popup closer consumed the key before Blink's fallback")
	assert(
		not blink_closed.completion and blink_closed.documentation and blink_closed.signature,
		"Escape without a menu did not close the documentation and signature popups"
	)
	assert(
		vim.deep_equal(completion_opts.keymap["<C-k>"], { "show_signature", "hide_signature", "fallback" }),
		"C-k no longer uses Blink's public signature toggle"
	)
	assert(
		vim.deep_equal(
			completion_opts.keymap["<C-b>"],
			{ "scroll_signature_up", "scroll_documentation_up", "fallback" }
		)
			and vim.deep_equal(
				completion_opts.keymap["<C-f>"],
				{ "scroll_signature_down", "scroll_documentation_down", "fallback" }
			),
		"Signatures cannot be scrolled"
	)
	require("lazy").load({ plugins = { "blink.cmp" } })
	local signature = require("blink.cmp.config").signature
	assert(signature.enabled and signature.trigger.enabled, "Automatic signature help is disabled")
	assert(signature.trigger.show_on_insert, "Signature help is not requested when entering an existing call")
	assert(signature.window.max_height == 6, "Signature popup no longer has a compact, multiline height limit")
	assert(signature.window.treesitter_highlighting, "Signature syntax highlighting is disabled")
	local active = vim.api.nvim_get_hl(0, { name = "BlinkCmpSignatureHelpActiveParameter", link = false })
	local palette = require("user.core.palette")
	assert(
		active.fg == nil and active.bg == palette.get().subtle,
		"Active parameter highlighting no longer preserves syntax colours on a neutral background"
	)
end
