return function(tmp)
	local theme = require("user.core.theme")
	local palette = require("user.core.palette")
	local transparency = require("user.core.transparency")
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
		theme.set(name, false)
		local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
		assert(normal.fg and normal.bg, name .. " has no resolved normal text colors")
		assert(contrast(normal.fg, normal.bg) >= 4.5, name .. " normal text has insufficient contrast")
		local result = { normal = contrast(normal.fg, normal.bg), popup = {} }
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
		local notify = vim.notify
		vim.notify = function() end
		transparency.toggle()
		assert(palette.highlight("Normal").bg == nil, name .. " editor stayed opaque")
		assert(transparency.background() == normal.bg, name .. " saved the popup's background as the editor colour")
		local floating = palette.highlight("NormalFloat")
		assert(floating.bg and floating.bg ~= normal.bg, name .. " float uses the transparent editor's base colour")
		assert(palette.highlight("FloatBorder").bg == floating.bg, name .. " float border has a different surface")
		result.transparent_popup = contrast(floating.fg or normal.fg, floating.bg)
		assert(result.transparent_popup >= 4.5, name .. " transparent-mode float is hard to read")
		transparency.toggle()
		vim.notify = notify
		assert(palette.highlight("Normal").bg == normal.bg, name .. " opaque editor colour was not restored")
		assert(
			palette.highlight("NormalFloat").bg == normal.bg,
			name .. " framed float kept an unnecessary colour lift"
		)
		vim.api.nvim_win_close(win, true)
		vim.api.nvim_buf_delete(buf, { force = true })
		reports[name] = result
	end
	theme.set("vscode", false)
	vim.fn.writefile({ vim.json.encode(reports) }, tmp .. "/theme-contrast.json")
	print("All configured themes retain readable main and popup text")
end
