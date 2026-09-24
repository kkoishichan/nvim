-- Clear editor and framed float surfaces; borderless menus keep their fill.
-- Reload the active colorscheme on toggles so plugins can rebuild their cached
-- UI colours, including bufferline's dynamically created file icons.
local M = {}
local file = vim.fn.stdpath("state") .. "/transparent.txt"
local ok, lines = pcall(vim.fn.readfile, file)
local enabled = ok and lines[1] == "1"
local background
local groups = {
	"Normal",
	"NormalNC",
	"NormalFloat",
	"FloatBorder",
	"FloatTitle",
	"EndOfBuffer",
	"SignColumn",
	"FoldColumn",
	"LineNr",
	"LineNrAbove",
	"LineNrBelow",
	"WinSeparator",
	"VertSplit",
	"WinBar",
	"WinBarNC",
	"TabLine",
	"TabLineFill",
	"TabLineSel",
	"TreesitterContext",
	"TreesitterContextLineNumber",
	"TreesitterContextBottom",
	"TreesitterContextLineNumberBottom",
	"TreesitterContextSeparator",
	"NormalSB",
	"SignColumnSB",
	"NeoTreeNormal",
	"NeoTreeNormalNC",
	"NeoTreeEndOfBuffer",
	"NeoTreeSignColumn",
	"NeoTreeWinSeparator",
	"NeoTreeDimText",
	"NeoTreeIndentMarker",
	"NeoTreeExpander",
	"EdgyNormal",
	"EdgyWinBar",
	"EdgyWinBarNC",
	-- Fzf can supply its own theme groups when the unified popup style is off.
	-- Its terminal palette must also inherit the transparent background.
	"FzfLuaNormal",
	"FzfLuaPreviewNormal",
	"FzfLuaHelpNormal",
	"FzfLuaBorder",
	"FzfLuaPreviewBorder",
	"FzfLuaHelpBorder",
	"FzfLuaTitle",
	"FzfLuaPreviewTitle",
	"FzfLuaFzfNormal",
	"FzfLuaFzfGutter",
	"FzfLuaFzfQuery",
}
local separators = {
	"WinSeparator",
	"VertSplit",
	"NeoTreeWinSeparator",
	"NeoTreeVertSplit",
	"BufferLineOffsetSeparator",
}

function M.is_enabled()
	return enabled
end

-- Theme-derived popup and accent colours still need the opaque base colour.
function M.background()
	return background
end

function M.apply()
	if not enabled then
		return
	end
	local palette = require("user.core.palette")
	for _, name in ipairs(groups) do
		local value = palette.highlight(name)
		if value.bg or value.ctermbg then
			if name == "Normal" then
				background = value.bg
			end
			value.bg, value.ctermbg = nil, nil
			vim.api.nvim_set_hl(0, name, value)
		end
	end
	-- Theme borders can be almost as dark as their opaque background. Use a
	-- brighter theme-derived grey for splits, retaining any underline/style.
	local p = palette.get()
	local foreground = palette.blend(p.fg, p.bg, 0.55)
	for _, name in ipairs(separators) do
		local value = palette.highlight(name)
		if next(value) then
			value.fg, value.ctermfg = foreground, 7 -- ANSI grey for terminals without true colour.
			value.bg, value.ctermbg = nil, nil
			vim.api.nvim_set_hl(0, name, value)
		end
	end
end

function M.toggle()
	enabled = not enabled
	-- A normal theme refresh restores opaque colours and invalidates plugin
	-- colour caches through their own ColorScheme handlers. No per-frame work.
	vim.cmd.colorscheme(vim.g.colors_name or "default")
	M.apply()

	local saved, err = pcall(function()
		vim.fn.mkdir(vim.fn.fnamemodify(file, ":h"), "p")
		assert(vim.fn.writefile({ enabled and "1" or "0" }, file) == 0, "Could not write " .. file)
	end)
	if not saved then
		vim.notify(
			"Background changed for this session, but could not be saved: " .. tostring(err),
			vim.log.levels.WARN
		)
		return
	end
	vim.notify("Transparent background " .. (enabled and "enabled" or "disabled"), vim.log.levels.INFO)
end

function M.setup()
	local group = vim.api.nvim_create_augroup("user_transparency", { clear = true })
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = group,
		callback = function()
			background = nil
			if enabled then
				-- Direct :colorscheme calls also run after every plugin's callback.
				vim.schedule(M.apply)
			end
		end,
	})
	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = "LazyLoad",
		callback = M.apply,
	})
end

return M
