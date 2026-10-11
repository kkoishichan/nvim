return function(tmp)
	local theme = require("user.core.theme")
	local palette = require("user.core.palette")
	local transparency = require("user.core.transparency")
	require("lazy").load({
		plugins = {
			"bufferline.nvim",
			"nvim-treesitter-context",
			"neo-tree.nvim",
			"which-key.nvim",
			"nvim-bqf",
			"nvim-ufo",
			"glance.nvim",
			"trouble.nvim",
			"diffview.nvim",
			"gitsigns.nvim",
		},
	})
	-- Two listed buffers, so the tab bar has a gap between tabs to inspect.
	for _, file in ipairs({ "first.lua", "second.lua" }) do
		local bufnr = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(bufnr, tmp .. "/" .. file)
	end
	local solid_surfaces = {
		"Pmenu",
		"PmenuBorder",
		"PmenuKind",
		"PmenuExtra",
		"PmenuMatch",
		"PmenuSbar",
	}
	local popup_surfaces = {
		"BlinkCmpMenu",
		"BlinkCmpMenuBorder",
		"BlinkCmpDoc",
		"BlinkCmpDocBorder",
		"BlinkCmpDocSeparator",
		"BlinkCmpSignatureHelp",
		"BlinkCmpSignatureHelpBorder",
		"WhichKeyNormal",
		"WhichKeyBorder",
		"WhichKeyTitle",
		"SnacksInputNormal",
		"SnacksInputBorder",
		"BqfPreviewFloat",
		"BqfPreviewBorder",
		"BqfPreviewTitle",
		"DapUIFloatNormal",
		"DapUIFloatBorder",
		"UfoPreviewWinBar",
	}
	-- The peek overlay: two shades when opaque, lines only when transparent.
	local peek_surfaces = { "GlanceListNormal", "GlancePreviewNormal", "GlanceWinBarTitle", "GlanceBorderTop" }
	local surfaces = {
		"TroubleNormal",
		"TroubleNormalNC",
		"CursorLineNr",
		"CursorLine",
		"LspInlayHint",
		"DiffviewNormal",
		"DiffviewNonText",
		"DiffviewSignColumn",
		"DiffviewEndOfBuffer",
		"DiffviewWinSeparator",
		"TreesitterContext",
		"TreesitterContextLineNumber",
		"TreesitterContextBottom",
		"TabLine",
		"TabLineFill",
		"TabLineSel",
		"BufferLineFill",
		"BufferLineBackground",
		"BufferLineBufferVisible",
		"BufferLineBufferSelected",
		"BufferLineSeparator",
		"BufferLineSeparatorSelected",
		"BufferLineOffsetSeparator",
		"UserBufferlineOffset",
		"NeoTreeDimText",
		"NeoTreeIndentMarker",
		"NeoTreeExpander",
		"NeoTreeTitleBar",
		"NeoTreeTabInactive",
		"NeoTreeTabSeparatorInactive",
		"WinSeparator",
		"VertSplit",
		"NeoTreeWinSeparator",
		"NeoTreeVertSplit",
	}
	-- Framed popups and editor panels follow the transparency switch.
	vim.list_extend(surfaces, popup_surfaces)
	local all_surfaces = vim.list_extend(vim.deepcopy(surfaces), solid_surfaces)
	local reports = {}
	local function luminance(color)
		local function channel(value)
			value = value / 255
			return value <= 0.04045 and value / 12.92 or ((value + 0.055) / 1.055) ^ 2.4
		end
		return 0.2126 * channel(math.floor(color / 65536))
			+ 0.7152 * channel(math.floor(color / 256) % 256)
			+ 0.0722 * channel(color % 256)
	end
	local function contrast(foreground, background)
		local light, dark = luminance(foreground), luminance(background)
		return (math.max(light, dark) + 0.05) / (math.min(light, dark) + 0.05)
	end
	for _, name in ipairs(vim.tbl_keys(theme.themes)) do
		-- Load the theme first, then capture its own float colour without our
		-- ColorScheme customisations. The normal path must preserve that surface.
		theme.set(name, false)
		vim.cmd.colorscheme({ theme.themes[name].colorscheme, mods = { noautocmd = true } })
		local float_bg = palette.highlight("NormalFloat").bg or palette.highlight("Normal").bg
		theme.set(name, false)
		local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
		assert(normal.fg and normal.bg, name .. " has no resolved normal text colors")
		assert(contrast(normal.fg, normal.bg) >= 4.5, name .. " normal text has insufficient contrast")
		local result = { normal = contrast(normal.fg, normal.bg), popup = {} }
		assert(palette.highlight("NormalFloat").bg == float_bg, name .. " replaced the theme's float background")
		assert(
			palette.highlight("TreesitterContext").bg == palette.get().sunken,
			name .. " context rows are not one step below the editor"
		)
		assert(
			palette.highlight("TreesitterContextLineNumber").bg == palette.highlight("TreesitterContext").bg,
			name .. " context gutter differs from the context rows"
		)
		local menu_selection = palette.highlight("PmenuSel")
		local diff_colours = {}
		for _, group in ipairs({
			"DiffAdd",
			"DiffDelete",
			"DiffChange",
			"DiffText",
			"UserDiffviewAdd",
			"UserDiffviewDelete",
			"UserDiffviewAddText",
			"UserDiffviewDeleteText",
			"GitSignsAddPreview",
			"GitSignsDeleteVirtLn",
		}) do
			diff_colours[group] = palette.highlight(group)
		end
		local opaque_statusline = palette.highlight("StatusLine")
		assert(
			palette.highlight("GlanceListNormal").bg and palette.highlight("GlancePreviewNormal").bg,
			name .. " opaque peek lost its fill"
		)
		do
			-- The Explorer title heads the sidebar and its divider continues the
			-- window separator: no tab-bar shade of their own when opaque.
			local function resolved(group, fallback)
				local value = palette.highlight(group)
				return next(value) and value or palette.highlight(fallback)
			end
			assert(
				palette.highlight("UserBufferlineOffset").bg == (resolved("NeoTreeNormal", "Normal").bg or normal.bg),
				name .. " Explorer title is not on the sidebar colour"
			)
			local divider = resolved("NeoTreeWinSeparator", "WinSeparator")
			local offset_separator = palette.highlight("BufferLineOffsetSeparator")
			assert(
				offset_separator.bg == (divider.bg or normal.bg) and offset_separator.fg == divider.fg,
				name .. " Explorer divider breaks the window separator below it"
			)
		end
		assert(
			palette.highlight("GlanceListNormal").bg ~= palette.highlight("GlancePreviewNormal").bg,
			name .. " opaque peek list and preview share one shade"
		)
		assert(require("glance.config").options.border.enable == false, name .. " opaque peek draws lines")
		-- Opaque tab bar: one step below the editor, the current tab cut out in
		-- the editor colour, no underline and no separator anywhere.
		vim.cmd.redrawtabline()
		local opaque_bar = vim.api.nvim_eval_statusline(vim.o.tabline, { use_tabline = true }).str
		assert(not opaque_bar:find("│", 1, true), name .. " opaque tab bar draws separators: " .. opaque_bar)
		assert(palette.highlight("BufferLineFill").bg == palette.get().sunken, name .. " tab bar is not sunken")
		assert(
			palette.highlight("BufferLineBackground").bg == palette.get().sunken,
			name .. " inactive tab left the bar"
		)
		assert(palette.highlight("BufferLineBufferSelected").bg == normal.bg, name .. " current tab is not cut out")
		assert(not palette.highlight("BufferLineBufferSelected").underline, name .. " opaque tab bar draws lines")
		local directory = palette.highlight("Directory")
		local tree_selection = palette.highlight("NeoTreeCursorLine")
		local opaque = {}
		for _, group in ipairs(all_surfaces) do
			opaque[group] = palette.highlight(group)
		end
		for _, group in ipairs({ "Pmenu", "NormalFloat", "BlinkCmpMenu", "BlinkCmpSignatureHelp" }) do
			local value = vim.api.nvim_get_hl(0, { name = group, link = false })
			local ratio = contrast(value.fg or normal.fg, value.bg or normal.bg)
			assert(ratio >= 4.5, name .. " " .. group .. " text has insufficient contrast")
			result.popup[group] = ratio
		end
		for _, severity in ipairs({ "Error", "Warn", "Info", "Hint" }) do
			local diagnostic = vim.api.nvim_get_hl(0, { name = "Diagnostic" .. severity, link = false })
			assert(
				diagnostic.fg and diagnostic.fg ~= normal.bg,
				name .. " has an invisible " .. severity .. " diagnostic"
			)
		end
		-- A focused popup can remap Normal to its own colours. Transparency must
		-- still save/restore the global editor palette, not the popup's surface.
		local buf = vim.api.nvim_create_buf(false, true)
		local win = vim.api.nvim_open_win(buf, true, {
			relative = "editor",
			row = 1,
			col = 1,
			width = 24,
			height = 3,
			border = "rounded",
			style = "minimal",
		})
		vim.wo[win].winhighlight = "Normal:Pmenu,NormalFloat:Pmenu"
		assert(palette.get().bg == normal.bg, name .. " focused popup changed the base palette")
		assert(palette.get().surface == float_bg, name .. " focused popup changed the float palette")
		local notify = vim.notify
		vim.notify = function() end
		-- Neither state may leak into the other: every highlight group must be
		-- identical after a round trip, in both directions.
		-- Rendering creates groups lazily (tab bar areas, icons), so compare
		-- the groups a snapshot had; a group gaining a different value is a leak.
		-- Evaluating the tab bar is the draw that recreates its lazy groups.
		local function draw_bar()
			return vim.api.nvim_eval_statusline(vim.o.tabline, { use_tabline = true }).str
		end
		local function unchanged(snapshot, label)
			-- A theme reload drops the lazily created groups until the next draw.
			draw_bar()
			local now = vim.api.nvim_get_hl(0, {})
			for group, value in pairs(snapshot) do
				-- Per-icon tab groups are created by whichever tabs a draw shows
				-- and dropped by every theme reload; their colours come from the
				-- state groups compared here, so they carry no information.
				if not group:match("^BufferLine.*Icons") then
					assert(
						vim.deep_equal(now[group], value),
						("%s %s changed after %s: %s -> %s"):format(
							name,
							group,
							label,
							vim.inspect(value),
							vim.inspect(now[group])
						)
					)
				end
			end
		end
		draw_bar()
		local opaque_table = vim.api.nvim_get_hl(0, {})
		transparency.toggle()
		draw_bar()
		local transparent_table = vim.api.nvim_get_hl(0, {})
		transparency.toggle()
		unchanged(opaque_table, "a transparency round trip")
		transparency.toggle()
		unchanged(transparent_table, "a round trip back to transparent")
		assert(palette.highlight("Normal").bg == nil, name .. " editor stayed opaque")
		for group, value in pairs(diff_colours) do
			assert(vim.deep_equal(palette.highlight(group), value), name .. " " .. group .. " lost its diff colours")
		end
		assert(transparency.background() == normal.bg, name .. " saved the popup's background as the editor colour")
		for _, group in ipairs({
			"NormalFloat",
			"FloatBorder",
			"FloatTitle",
			"NotifyINFOBody",
			"NotifyINFOTitle",
			"NotifyINFOBorder",
		}) do
			local floating = palette.highlight(group)
			assert(floating.bg == nil and floating.ctermbg == nil, name .. " " .. group .. " stayed opaque")
		end
		assert(
			vim.deep_equal(palette.highlight("PmenuSel"), menu_selection),
			name .. " removed the popup menu's selection highlight"
		)
		for _, group in ipairs(solid_surfaces) do
			assert(
				vim.deep_equal(palette.highlight(group), opaque[group]),
				name .. " " .. group .. " changed the borderless popup surface"
			)
		end
		for _, group in ipairs(surfaces) do
			local value = palette.highlight(group)
			assert(value.bg == nil and value.ctermbg == nil, name .. " " .. group .. " stayed opaque")
			assert(
				not value.reverse and not (value.cterm and value.cterm.reverse),
				name .. " " .. group .. " retained an inverse-video background"
			)
			if group == "UserBufferlineOffset" or group == "BufferLineOffsetSeparator" then
				-- The sidebar title heads the sidebar, not the tab list: no line.
				assert(not value.underline, name .. " " .. group .. " underlines the sidebar title")
			elseif group:match("^BufferLine") then
				-- One underline colour for the whole bar, the current tab included.
				assert(value.underline and value.sp == palette.get().line, name .. " " .. group .. " lost its baseline")
			end
		end
		-- Lines keep reading without a fill behind them, in every theme: the
		-- separators and float borders take the palette's line colour and the
		-- titles its dim text colour, all visibly lighter than the old fill.
		local p = palette.get()
		local lines_by_role = transparency.lines()
		result.separator = contrast(p.line, normal.bg)
		assert(result.separator >= 1.5, name .. " transparent lines are not visible against the old background")
		for _, group in ipairs(lines_by_role.separators) do
			local value = palette.highlight(group)
			if next(value) then
				assert(value.fg == p.line, name .. " " .. group .. " does not use the palette line colour")
				assert(value.bg == nil, name .. " " .. group .. " kept a fill")
			end
		end
		for _, group in ipairs(lines_by_role.borders) do
			local value = palette.highlight(group)
			if next(value) then
				assert(value.fg == p.line, name .. " " .. group .. " border does not use the palette line colour")
			end
		end
		for _, group in ipairs(lines_by_role.titles) do
			local value = palette.highlight(group)
			if next(value) then
				assert(value.fg == p.dim, name .. " " .. group .. " title does not use the palette dim colour")
			end
		end
		-- No separator glyphs in the transparent bar either.
		assert(not draw_bar():find("│", 1, true), name .. " transparent tab bar draws separators")
		-- The statusline anchors the picture and keeps its fill.
		if opaque_statusline.bg then
			assert(palette.highlight("StatusLine").bg == opaque_statusline.bg, name .. " statusline lost its fill")
		end
		for _, group in ipairs(peek_surfaces) do
			assert(
				palette.highlight(group).bg == nil,
				name .. " " .. group .. " kept a fill over the transparent editor"
			)
		end
		assert(palette.highlight("GlanceBorderTop").fg == p.line, name .. " peek lines are not in the line colour")
		assert(require("glance.config").options.border.enable == true, name .. " transparent peek has no lines")
		assert(vim.deep_equal(palette.highlight("Directory"), directory), name .. " changed Directory globally")
		assert(
			vim.deep_equal(palette.highlight("NeoTreeCursorLine"), tree_selection),
			name .. " removed the explorer's selection background"
		)
		transparency.toggle()
		vim.notify = notify
		assert(palette.highlight("Normal").bg == normal.bg, name .. " opaque editor colour was not restored")
		assert(
			palette.highlight("NormalFloat").bg == float_bg,
			name .. " framed float did not recover its theme background"
		)
		for _, group in ipairs(all_surfaces) do
			local value = palette.highlight(group)
			assert(vim.deep_equal(value, opaque[group]), name .. " " .. group .. " did not recover its theme colours")
		end
		vim.api.nvim_win_close(win, true)
		vim.api.nvim_buf_delete(buf, { force = true })
		reports[name] = result
	end
	theme.set("vscode", false)
	vim.fn.writefile({ vim.json.encode(reports) }, tmp .. "/theme-contrast.json")
	print("All configured themes retain readable main and popup text")
end
