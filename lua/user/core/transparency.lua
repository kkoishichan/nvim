-- Transparent background, decided by surface role rather than by theme:
--   * editor, gutters, panels, splits, tab bar, winbars, framed floats and
--     notifications lose their fill;
--   * the native completion menu and the statusline keep theirs, anchoring
--     the picture; the Glance peek drops its fill and is marked by its lines
--     instead (its owner in auto_lsp.lua reads the state from the palette);
--   * every line that only read against the old fill (window separators,
--     float borders, tab underlines) is redrawn in the palette's line colour,
--     so the same rule holds for all themes.
-- Runs first in the highlight chain (user.core.highlights) on every
-- ColorScheme, so owners that derive colours afterwards already see the
-- transparent state through the palette.
local M = {}
local file = vim.fn.stdpath("state") .. "/transparent.txt"
local ok, lines = pcall(vim.fn.readfile, file)
local enabled = ok and lines[1] == "1"
local background

-- Surfaces whose fill goes, grouped by role. Plugin groups that link to a
-- cleared group follow it; the ones listed here paint their own fill.
local surfaces = {
	editor = {
		"Normal",
		"NormalNC",
		"EndOfBuffer",
		"SignColumn",
		"FoldColumn",
		"LineNr",
		"LineNrAbove",
		"LineNrBelow",
		"CursorLine",
		"CursorLineNr",
		"CursorLineSign",
		"CursorLineFold",
		"NormalSB",
		"SignColumnSB",
		"LspInlayHint",
		"TreesitterContext",
		"TreesitterContextLineNumber",
		"TreesitterContextBottom",
		"TreesitterContextLineNumberBottom",
		"TreesitterContextSeparator",
	},
	chrome = {
		"WinSeparator",
		"VertSplit",
		"WinBar",
		"WinBarNC",
		"TabLine",
		"TabLineFill",
		"TabLineSel",
	},
	panel = {
		"DiffviewNormal",
		"DiffviewNonText",
		"DiffviewSignColumn",
		"DiffviewEndOfBuffer",
		"DiffviewWinSeparator",
		"TroubleNormal",
		"TroubleNormalNC",
		"NeoTreeNormal",
		"NeoTreeNormalNC",
		"NeoTreeFloatNormal",
		"NeoTreeFloatBorder",
		"NeoTreeFloatTitle",
		"NeoTreeTitleBar",
		"NeoTreeTabInactive",
		"NeoTreeTabSeparatorInactive",
		"NeoTreeEndOfBuffer",
		"NeoTreeSignColumn",
		"NeoTreeWinSeparator",
		"NeoTreeDimText",
		"NeoTreeIndentMarker",
		"NeoTreeExpander",
		"EdgyNormal",
		"EdgyWinBar",
		"EdgyWinBarNC",
	},
	float = {
		"NormalFloat",
		"FloatBorder",
		"FloatTitle",
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
		"FzfLuaScrollFloatEmpty",
		"BlinkCmpMenu",
		"BlinkCmpMenuBorder",
		"BlinkCmpLabel",
		"BlinkCmpLabelDeprecated",
		"BlinkCmpLabelDetail",
		"BlinkCmpLabelDescription",
		"BlinkCmpLabelMatch",
		"BlinkCmpKind",
		"BlinkCmpSource",
		"BlinkCmpScrollBarGutter",
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
		"SnacksInputTitle",
		"BqfPreviewFloat",
		"BqfPreviewBorder",
		"BqfPreviewTitle",
		"DapUIFloatNormal",
		"DapUIFloatBorder",
		"UfoPreviewWinBar",
	},
}
local roles = { "editor", "chrome", "panel", "float" }

-- Lines that must stay visible without a fill behind them.
local separators = {
	"WinSeparator",
	"VertSplit",
	"NeoTreeWinSeparator",
	"NeoTreeVertSplit",
	"DiffviewWinSeparator",
	"BufferLineOffsetSeparator",
}
local borders = {
	"FloatBorder",
	"FzfLuaBorder",
	"FzfLuaPreviewBorder",
	"FzfLuaHelpBorder",
	"BlinkCmpMenuBorder",
	"BlinkCmpDocBorder",
	"BlinkCmpSignatureHelpBorder",
	"WhichKeyBorder",
	"SnacksInputBorder",
	"BqfPreviewBorder",
	"DapUIFloatBorder",
	"NeoTreeFloatBorder",
}
local titles = {
	"FloatTitle",
	"FzfLuaTitle",
	"FzfLuaPreviewTitle",
	"WhichKeyTitle",
	"SnacksInputTitle",
	"BqfPreviewTitle",
	"NeoTreeFloatTitle",
}

function M.is_enabled()
	return enabled
end

-- Theme-derived popup and accent colours still need the opaque base colour.
function M.background()
	return background
end

---Group names by role, for checks.
function M.surfaces(role)
	return vim.deepcopy(role and surfaces[role] or surfaces)
end

function M.lines()
	return { separators = vim.deepcopy(separators), borders = vim.deepcopy(borders), titles = vim.deepcopy(titles) }
end

local function clear_fill(name)
	local palette = require("user.core.palette")
	local value = palette.highlight(name)
	if not (value.bg or value.ctermbg or value.reverse or (value.cterm and value.cterm.reverse)) then
		return
	end
	if name == "Normal" then
		background = value.bg
	elseif name == "NeoTreeTitleBar" then
		-- Some themes put dark title text on an accent-coloured block. Use the
		-- ordinary float title foreground when removing that block.
		value.fg = palette.highlight("FloatTitle").fg or palette.highlight("Normal").fg
	end
	value.bg, value.ctermbg = nil, nil
	-- Inverse video can also paint a background in terminal themes.
	value.reverse = nil
	if value.cterm then
		value.cterm.reverse = nil
	end
	vim.api.nvim_set_hl(0, name, value)
end

local function recolour(names, foreground)
	local palette = require("user.core.palette")
	for _, name in ipairs(names) do
		local value = palette.highlight(name)
		if next(value) then
			value.fg, value.ctermfg = foreground, 8 -- ANSI dark grey without true colour.
			value.bg, value.ctermbg = nil, nil
			vim.api.nvim_set_hl(0, name, value)
		end
	end
end

function M.apply()
	if not enabled then
		return
	end
	local palette = require("user.core.palette")
	-- Capture the theme's colours before any fill is removed.
	local p = palette.get()
	for _, role in ipairs(roles) do
		for _, name in ipairs(surfaces[role]) do
			clear_fill(name)
		end
	end
	recolour(separators, p.line)
	recolour(borders, p.line)
	recolour(titles, p.dim)
end

function M.toggle()
	enabled = not enabled
	-- Reloading the theme restores its opaque colours and runs the highlight
	-- chain. Plugins repaint their own groups from their ColorScheme handlers
	-- too, so apply once more after all of them finished. No per-frame work.
	vim.cmd.colorscheme(vim.g.colors_name or "default")
	M.apply()

	local saved, err = pcall(function()
		vim.fn.mkdir(vim.fn.fnamemodify(file, ":h"), "p")
		assert(vim.fn.writefile({ enabled and "1" or "0" }, file) == 0, "Could not write " .. file)
	end)
	if not saved then
		vim.notify(
			"Background changed for this session, but could not be saved: " .. tostring(err),
			vim.log.levels.WARN,
			{ title = "Transparency" }
		)
		return
	end
	vim.notify(
		"Transparent background " .. (enabled and "enabled" or "disabled"),
		vim.log.levels.INFO,
		{ title = "Transparency" }
	)
end

function M.setup()
	local group = vim.api.nvim_create_augroup("user_transparency", { clear = true })
	-- Plugins that define filled groups when they load are cleared as they
	-- arrive; ColorScheme itself is handled by the highlight chain.
	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = "LazyLoad",
		callback = M.apply,
	})
end

return M
