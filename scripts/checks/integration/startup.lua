return function()
	assert(require("user.core.theme").saved() == "vscode", "default theme is not vscode")
	assert(vim.g.colors_name == "vscode", "vscode was not applied at startup")
	assert(
		vim.api.nvim_get_hl(0, { name = "Pmenu", link = false }).bg == 0x2d2d30,
		"vscode popup background override was not applied"
	)
	do
		local visual = vim.api.nvim_get_hl(0, { name = "Visual", link = false })
		local snippet = vim.api.nvim_get_hl(0, { name = "SnippetTabstop", link = false })
		local active_snippet = vim.api.nvim_get_hl(0, { name = "SnippetTabstopActive", link = true })
		assert(visual.bg == 0x264f78, "vscode Visual selection colour was overridden")
		assert(
			snippet.bg == require("user.core.palette").get().subtle and snippet.fg == nil,
			"Native snippet placeholders are not using the theme-derived neutral grey"
		)
		assert(snippet.bg ~= visual.bg, "Native snippet placeholders still inherit Visual")
		assert(active_snippet.link == "SnippetTabstop", "Active snippet placeholder does not inherit snippet grey")
	end
	assert(vim.o.shada:match("<0"), "ShaDa still persists register contents")
	assert(
		not vim.tbl_contains(vim.opt.sessionoptions:get(), "blank"),
		"Sessions still serialize plugin panels as ordinary file buffers"
	)
	assert(vim.tbl_contains(vim.opt.sessionoptions:get(), "buffers"), "Sessions no longer preserve hidden file buffers")
	assert(vim.g.user_lsp_preview_patched == nil, "LSP floating-preview API was monkeypatched")
	assert(
		type(vim.fn.maparg("<Esc>", "n", false, true).callback) == "function",
		"Normal Escape is not a semantic popup closer"
	)
	assert(
		type(vim.fn.maparg("<Esc>", "x", false, true).callback) == "function",
		"Visual Escape is not a semantic popup closer"
	)

	do
		local plugins = require("lazy.core.config").plugins
		local edgy = plugins["edgy.nvim"]
		local codex
		for _, panel in ipairs(edgy.opts.right) do
			if panel.title == "Codex" then
				codex = panel
				break
			end
		end
		assert(codex and codex.ft == "toggleterm", "Codex is not docked as a toggleterm panel")

		local bufferline_opts = plugins["bufferline.nvim"].opts
		local indicator = bufferline_opts.options.diagnostics_indicator
		assert(bufferline_opts.options.numbers == "none", "Bufferline numbers are still visible")
		assert(indicator(0, 0, { info = 2 }):match("2"), "Bufferline hides info-only diagnostics")
		assert(indicator(0, 0, { hint = 3 }):match("3"), "Bufferline hides hint-only diagnostics")
		assert(bufferline_opts.options.indicator.style == "none", "Current Bufferline item still has an indicator")
		assert(type(bufferline_opts.highlights) == "function", "Bufferline has no theme-derived inactive colours")
	end
end
