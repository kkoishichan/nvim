return function()
	local plugins = require("lazy.core.config").plugins
	local plugin = require("lazy.core.plugin")
	local function opts(name)
		return plugin.values(assert(plugins[name], "missing plugin: " .. name), "opts", false)
	end
	local layout = require("user.core.layout")
	-- Plugins that read 'winborder' themselves must not override it; the rest
	-- are handed the same border explicitly.
	local function assert_default_border(border, label)
		assert(border == nil, label .. " still sets its own border")
	end
	local function assert_float_border(border, label)
		assert(border == layout.float_border(), label .. " does not follow the global float border")
	end

	local glance = plugins["glance.nvim"]
	assert(glance and glance.cmd == "Glance", "Glance peek UI is missing or not lazy-loaded")
	local neo_tree_opts = opts("neo-tree.nvim")
	assert(neo_tree_opts.auto_clean_after_session_restore, "Neo-tree cannot clean legacy session buffers")
	local neo_tree_session_cleanup = vim.api.nvim_get_autocmds({
		group = "user_neotree_session_cleanup",
		event = "SessionLoadPost",
	})
	assert(#neo_tree_session_cleanup == 1, "Legacy Neo-tree session cleanup is not registered")
	assert(neo_tree_opts.enable_git_status, "neo-tree Git status is disabled")
	assert(neo_tree_opts.enable_diagnostics, "neo-tree diagnostics are disabled")
	assert(neo_tree_opts.filesystem.use_libuv_file_watcher, "neo-tree file watcher is disabled")
	local gitsigns_opts = opts("gitsigns.nvim")
	assert(gitsigns_opts.current_line_blame, "current-line Git blame is disabled")
	for _, signs in ipairs({ gitsigns_opts.signs, gitsigns_opts.signs_staged }) do
		for _, kind in ipairs({ "add", "change", "changedelete" }) do
			assert(signs[kind].text == "┃", "Gitsigns " .. kind .. " marker is not a centred heavy bar")
		end
	end
	assert_default_border(gitsigns_opts.preview_config.border, "Gitsigns previews")
	assert(
		gitsigns_opts.preview_config.row == 1 and gitsigns_opts.preview_config.col == 0,
		"Gitsigns preview is misplaced"
	)
	assert_default_border(vim.diagnostic.config().float.border, "Diagnostic floats")
	local ufo_opts = opts("nvim-ufo")
	assert_float_border(ufo_opts.preview.win_config.border, "Fold previews")
	assert(ufo_opts.preview.win_config.winblend == 0, "Fold previews are translucent")
	assert(ufo_opts.preview.mappings.close == "q", "Fold previews lost their original q mapping")
	assert_float_border(opts("outline.nvim").preview_window.border, "Outline previews")
	assert_float_border(opts("nvim-bqf").preview.border, "Quickfix previews")
	assert(opts("nvim-bqf").preview.winblend == 0, "Quickfix previews are translucent")
	assert_float_border(opts("nvim-dap-ui").floating.border, "DAP eval floats")
	assert_float_border(opts("crates.nvim").popup.border, "Crates popups")
	local snacks_opts = opts("snacks.nvim")
	assert_default_border(snacks_opts.styles.input.border, "vim.ui.input")
	assert(
		vim.deep_equal(snacks_opts.styles.input.keys.i_esc[2], { "cmp_close", "cancel" }),
		"vim.ui.input still needs two Escape presses"
	)
	assert(snacks_opts.styles.notification == nil, "Snacks notifier is disabled but still styled")
	assert_float_border(opts("which-key.nvim").win.border, "Which-key")
	local which_key_green = vim.api.nvim_get_hl(0, { name = "WhichKeyIconGreen", link = false }).fg
	local comment = vim.api.nvim_get_hl(0, { name = "Comment", link = false }).fg
	assert(which_key_green ~= comment, "Which-key green icons still inherit the VS Code comment green")
	assert(
		which_key_green == require("user.core.palette").get().dim,
		"Which-key green icons are not using the neutral popup colour"
	)
end
