return function()
	local plugins = require("lazy.core.config").plugins
	local plugin = require("lazy.core.plugin")
	local float_style = require("user.core.float_style")
	local shared_border = float_style.border()
	local function opts(name)
		return plugin.values(assert(plugins[name], "missing plugin: " .. name), "opts", false)
	end
	local function assert_shared_border(border, label)
		assert(vim.deep_equal(border, shared_border), label .. " does not use the shared borderless style")
	end

	assert(plugins["lsp_signature.nvim"] == nil, "lsp_signature.nvim is still configured")
	assert(opts("nvim-notify").stages == "fade", "nvim-notify animation or frame was changed")
	assert(
		vim.api.nvim_get_hl(0, { name = "NotifyBackground", link = false }).bg == require("user.core.palette").get().bg,
		"nvim-notify does not fade toward the opaque editor background"
	)

	-- Other application-sized overlays deliberately keep their framed layouts.
	local fzf_plugin = plugins["fzf-lua"]
	local fzf_opts = opts("fzf-lua")
	assert(fzf_opts.winopts.border == "rounded", "Fzf main window lost its panel border")
	do
		-- The theme picker and other vim.ui.select callers use a compact popup,
		-- while regular FzfLua commands retain the application-sized style above.
		local registered_ui_select
		local loaded_fzf = package.loaded["fzf-lua"]
		package.loaded["fzf-lua"] = {
			setup = function() end,
			register_ui_select = function(callback)
				registered_ui_select = callback
			end,
		}
		fzf_plugin.config(nil, fzf_opts)
		package.loaded["fzf-lua"] = loaded_fzf
		assert(type(registered_ui_select) == "function", "vim.ui.select was not registered with FzfLua")
		local select_opts = registered_ui_select({ prompt = "Colorscheme" }, { "one", "two", "three", "four" })
		assert_shared_border(select_opts.winopts.border, "Theme picker")
		assert(select_opts.winopts.backdrop == 60, "Theme picker backdrop is disabled")
		assert(select_opts.fzf_opts["--no-scrollbar"], "Theme picker still reserves an extra right-hand cell")
		assert(select_opts.hls.normal == "Pmenu", "Theme picker body does not use Pmenu")
		assert(select_opts.hls.cursorline == "PmenuSel", "Theme picker selection does not use PmenuSel")
		assert(
			select_opts.hls.fzf.normal == "Pmenu" and select_opts.hls.fzf.gutter == "Pmenu",
			"Theme picker terminal surface does not use Pmenu"
		)
		assert(select_opts.hls.fzf.cursorline == "PmenuSel", "Theme picker terminal selection does not use PmenuSel")
	end
	local oil_opts = opts("oil.nvim")
	assert(oil_opts.float.border == "rounded", "Oil float lost its panel border")
	assert(type(oil_opts.keymaps["<Esc>"].callback) == "function", "Floating Oil cannot be closed with Escape")
	assert(opts("toggleterm.nvim").float_opts.border == "rounded", "Float terminal lost its panel border")
	local layout = require("user.core.layout")
	local mason_ui = opts("mason.nvim").ui
	local lazy_ui = require("lazy.core.config").options.ui
	assert(layout.manager_border == "none", "package managers still have a border or transparent shadow")
	assert(mason_ui.border == layout.manager_border, "Mason lost its borderless manager style")
	assert(lazy_ui.border == layout.manager_border, "Lazy lost its borderless manager style")
	local lazy_escape = vim.api.nvim_get_autocmds({ group = "user_lazy_escape", event = "FileType", pattern = "lazy" })
	assert(#lazy_escape == 1, "Lazy manager cannot be closed with Escape")
	assert(
		mason_ui.width == layout.manager_scale and mason_ui.height == layout.manager_scale,
		"Mason manager size diverged"
	)
	assert(
		lazy_ui.size.width == layout.manager_scale and lazy_ui.size.height == layout.manager_scale,
		"Lazy manager size diverged"
	)
	local scrollview_opts = opts("nvim-scrollview")
	for _, group in ipairs({ "diagnostics", "search", "marks", "keywords", "conflicts" }) do
		assert(
			vim.tbl_contains(scrollview_opts.signs_on_startup, group),
			"scrollview " .. group .. " markers are disabled"
		)
	end
	assert(scrollview_opts.signs_scrollbar_overlap == "over", "scrollview markers no longer use a single rail")
	assert(scrollview_opts.signs_max_per_row == 1, "scrollview markers can spill into multiple columns")
	assert(scrollview_opts.hide_on_float_intersect, "scrollview can draw through floating windows")
	local scrollview_symbols = {
		diagnostic_error = scrollview_opts.diagnostics_error_symbol,
		diagnostic_warn = scrollview_opts.diagnostics_warn_symbol,
		diagnostic_info = scrollview_opts.diagnostics_info_symbol,
		diagnostic_hint = scrollview_opts.diagnostics_hint_symbol,
		search = scrollview_opts.search_symbol,
		keyword_fix = scrollview_opts.keywords_fix_symbol,
		keyword_todo = scrollview_opts.keywords_todo_symbol,
		keyword_hack = scrollview_opts.keywords_hack_symbol,
		keyword_warn = scrollview_opts.keywords_warn_symbol,
		keyword_xxx = scrollview_opts.keywords_xxx_symbol,
		conflict = scrollview_opts.conflicts_top_symbol,
	}
	assert(
		vim.deep_equal(scrollview_symbols, {
			diagnostic_error = "E",
			diagnostic_warn = "W",
			diagnostic_info = "I",
			diagnostic_hint = "H",
			search = "━",
			keyword_fix = "",
			keyword_todo = "",
			keyword_hack = "",
			keyword_warn = "",
			keyword_xxx = "",
			conflict = "×",
		}),
		"scrollview markers diverged from the left gutter vocabulary"
	)
	for source, symbol in pairs(scrollview_symbols) do
		assert(vim.fn.strdisplaywidth(symbol) == 1, "scrollview " .. source .. " symbol is not one cell wide")
	end
	assert(
		scrollview_opts.diagnostics_error_priority > scrollview_opts.conflicts_top_priority
			and scrollview_opts.conflicts_top_priority > scrollview_opts.diagnostics_warn_priority
			and scrollview_opts.diagnostics_warn_priority > scrollview_opts.search_priority
			and scrollview_opts.search_priority > scrollview_opts.marks_priority
			and scrollview_opts.marks_priority > scrollview_opts.diagnostics_info_priority,
		"scrollview marker priority hierarchy changed"
	)
	local p = require("user.core.palette").get()
	assert(
		vim.api.nvim_get_hl(0, { name = "ScrollView", link = false }).bg
			== require("user.core.palette").blend(p.fg, p.bg, 0.13),
		"scrollview thumb is not using the quiet theme-derived colour"
	)
	assert(
		vim.api.nvim_get_hl(0, { name = "ScrollViewSearch", link = false }).fg
			== vim.api.nvim_get_hl(0, { name = "Special", link = false }).fg,
		"scrollview search markers lost their source-specific colour"
	)
	for group, colour in pairs({
		ScrollViewKeywordsFix = p.error,
		ScrollViewKeywordsTodo = p.info,
		ScrollViewKeywordsHack = p.warn,
		ScrollViewKeywordsWarn = p.warn,
		ScrollViewKeywordsXxx = p.warn,
	}) do
		assert(
			vim.api.nvim_get_hl(0, { name = group, link = false }).fg == colour,
			group .. " no longer matches the left gutter colour"
		)
	end
	require("lazy").load({ plugins = { "nvim-scrollview" } })
	vim.wait(200)
	local git_legend = vim.api.nvim_exec2("ScrollViewLegend! gitsigns", { output = true }).output
	assert(git_legend:find("┃", 1, true), "scrollview Git marker is not a heavy solid centred bar")
	assert(vim.fn.maparg("<leader>us", "n") == "", "search markers regained a dedicated toggle")
end
