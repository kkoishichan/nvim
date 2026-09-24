return function()
	local plugins = require("lazy.core.config").plugins
	local plugin = require("lazy.core.plugin")
	local function opts(name)
		return plugin.values(assert(plugins[name], "missing plugin: " .. name), "opts", false)
	end
	local completion_opts = opts("blink.cmp")
	assert(completion_opts.completion.menu.border == "padded", "Completion menu lost its borderless style")
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
	local completion_escape = completion_opts.keymap["<Esc>"]
	assert(
		type(completion_escape[1]) == "function" and completion_escape[2] == "fallback" and completion_escape[3] == nil,
		"Escape no longer dismisses popups and leaves Insert mode in one keypress"
	)
	local blink_closed = {}
	assert(completion_escape[1]({
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
			return true
		end,
		cancel = function()
			blink_closed.completion = true
		end,
	}) == nil, "Escape popup closer consumed the key before Blink's fallback")
	assert(
		blink_closed.completion and blink_closed.documentation and blink_closed.signature,
		"Escape did not close every overlapping Blink popup"
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
	assert(signature.window.border == "padded", "Signature window lost its shared style")
	assert(signature.window.max_height == 6, "Signature popup no longer has a compact, multiline height limit")
	assert(signature.window.treesitter_highlighting, "Signature syntax highlighting is disabled")
	local active = vim.api.nvim_get_hl(0, { name = "BlinkCmpSignatureHelpActiveParameter", link = false })
	local palette = require("user.core.palette")
	assert(
		active.fg == nil and active.bg == palette.blend(palette.get().fg, palette.highlight("Pmenu").bg, 0.16),
		"Active parameter highlighting no longer preserves syntax colours on a neutral background"
	)
end
