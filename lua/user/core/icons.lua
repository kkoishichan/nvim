-- The shared glyph vocabulary. Dense single-cell places (the sign column, the
-- overview rail) use letters and bars so every row stays one cell wide;
-- labelled places (statusline, tab bar, notifications) use one Material icon
-- set, with an ASCII form when the mode has no Nerd Font icons.
local M = {}

local capabilities = require("user.core.mode").capabilities()
M.enabled = capabilities.icons

-- Private-use glyphs are spelled as code points so no editor or tool can
-- silently drop them.
local function glyph(codepoint)
	return vim.fn.nr2char(codepoint)
end

M.diagnostics = {
	-- Sign column and overview rail: one letter per severity.
	letters = { error = "E", warn = "W", info = "I", hint = "H" },
	-- Labelled places: nf-md-close_circle, alert, information, lightbulb.
	glyphs = M.enabled
			and { error = glyph(0xF015A), warn = glyph(0xF002A), info = glyph(0xF02FD), hint = glyph(0xF0336) }
		or { error = "E", warn = "W", info = "I", hint = "H" },
}

-- Text with a trailing space, as lualine and bufferline expect.
---@return { error: string, warn: string, info: string, hint: string }
function M.diagnostic_symbols()
	local glyphs = M.diagnostics.glyphs
	return {
		error = glyphs.error .. (M.enabled and " " or ": "),
		warn = glyphs.warn .. (M.enabled and " " or ": "),
		info = glyphs.info .. (M.enabled and " " or ": "),
		hint = glyphs.hint .. (M.enabled and " " or ": "),
	}
end

M.git = {
	-- Sign column and overview rail: a heavy bar for changed lines.
	bar = "┃",
	deleted = glyph(0xF0DA),
	untracked = "┆",
	-- Labelled places: counts.
	added = "+",
	changed = "~",
	removed = "-",
}

M.modified = "●"
-- nf-md-lightbulb_on: an available code action, distinct from a hint.
M.code_action = M.enabled and glyph(0xF06E8) or "A"
M.fold = {
	open = M.enabled and glyph(0xF47C) or "v",
	closed = M.enabled and glyph(0xF460) or ">",
}

return M
