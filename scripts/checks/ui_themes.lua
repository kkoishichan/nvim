return function(tmp)
	local theme = require("user.core.theme")
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
		reports[name] = result
	end
	theme.set("vscode", false)
	vim.fn.writefile({ vim.json.encode(reports) }, tmp .. "/theme-contrast.json")
	print("All four themes retain readable main and popup text")
end
