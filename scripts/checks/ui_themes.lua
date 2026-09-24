return function(tmp)
	local theme = require("user.core.theme")
	local palette = require("user.core.palette")
	local transparency = require("user.core.transparency")
	require("lazy").load({ plugins = { "bufferline.nvim", "nvim-treesitter-context", "neo-tree.nvim" } })
	local surfaces = {
		"TreesitterContext",
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
		"WinSeparator",
		"VertSplit",
		"NeoTreeWinSeparator",
		"NeoTreeVertSplit",
	}
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
		assert(palette.highlight("TreesitterContext").bg == normal.bg, name .. " context adopted the popup background")
		local menu_bg = palette.highlight("Pmenu").bg
		local directory = palette.highlight("Directory")
		local tree_selection = palette.highlight("NeoTreeCursorLine")
		local opaque = {}
		for _, group in ipairs(surfaces) do
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
		assert(palette.get().float == float_bg, name .. " focused popup changed the float palette")
		local notify = vim.notify
		vim.notify = function() end
		transparency.toggle()
		assert(palette.highlight("Normal").bg == nil, name .. " editor stayed opaque")
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
		assert(palette.highlight("Pmenu").bg == menu_bg, name .. " borderless menu lost its background")
		for _, group in ipairs(surfaces) do
			local value = palette.highlight(group)
			assert(value.bg == nil and value.ctermbg == nil, name .. " " .. group .. " stayed opaque")
			if group:match("^BufferLine") or group == "UserBufferlineOffset" then
				assert(
					value.underline and value.sp == palette.get().strong,
					name .. " " .. group .. " lost its separator"
				)
			end
		end
		local separator = palette.highlight("WinSeparator")
		result.separator = contrast(separator.fg, normal.bg)
		local adjusted = name == "tokyonight" or name == "catppuccin"
		if adjusted then
			assert(
				result.separator > contrast(opaque.WinSeparator.fg, normal.bg),
				name .. " transparent splits did not become more visible"
			)
			assert(
				luminance(separator.fg) < luminance(palette.blend(normal.fg, normal.bg, 0.55)),
				name .. " transparent splits retained the overly bright grey"
			)
		end
		for _, group in ipairs({
			"WinSeparator",
			"VertSplit",
			"NeoTreeWinSeparator",
			"NeoTreeVertSplit",
			"BufferLineOffsetSeparator",
		}) do
			local value = palette.highlight(group)
			if adjusted and next(value) then
				assert(value.fg == separator.fg, name .. " " .. group .. " does not match the window separator")
			elseif not adjusted then
				assert(
					value.fg == opaque[group].fg and value.ctermfg == opaque[group].ctermfg,
					name .. " " .. group .. " did not keep its original foreground"
				)
			end
		end
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
		for _, group in ipairs(surfaces) do
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
