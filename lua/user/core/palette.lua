-- Semantic colours derived from the *active* colorscheme, so custom highlights
-- follow whatever theme is loaded instead of hard-coding gruvbox hex values.
-- Everything is pulled from standard highlight groups every theme defines
-- (Normal, Comment, Diagnostic*), with neutral bg shades blended from fg/bg.

local M = {}

local function attr(name, key)
	local h = vim.api.nvim_get_hl(0, { name = name, link = false })
	return h[key]
end

---Mix two 0xRRGGBB colours; `alpha` is the weight of `a` (1 = all a, 0 = all b).
---@param a integer?
---@param b integer?
---@param alpha number
---@return integer?
function M.blend(a, b, alpha)
	if not a or not b then
		return a or b
	end
	local function mix(shift)
		local ca = math.floor(a / shift) % 256
		local cb = math.floor(b / shift) % 256
		return math.floor(ca * alpha + cb * (1 - alpha) + 0.5)
	end
	return mix(65536) * 65536 + mix(256) * 256 + mix(1)
end

---Snapshot of theme colours. Cheap; call it fresh each time the highlights are
---applied (startup + every ColorScheme) so it always reflects the live theme.
function M.get()
	local fg = attr("Normal", "fg") or 0xebdbb2
	local bg = attr("Normal", "bg") or 0x1d2021
	return {
		fg = fg,
		bg = bg,
		gray = attr("Comment", "fg") or 0x928374,
		-- Float-border accent: a cyan/blue that stays in the same family across
		-- themes (gruvbox aqua, tokyonight/catppuccin blue), unlike Function/Title
		-- which go green in gruvbox.
		accent = attr("DiagnosticInfo", "fg") or 0x83a598,
		panel = M.blend(fg, bg, 0.05), -- barely-lifted panel bg (notifications)
		subtle = M.blend(fg, bg, 0.15), -- soft highlight bg (word under cursor, folds)
		strong = M.blend(fg, bg, 0.25), -- heavier highlight bg (write refs, matchparen)
		error = attr("DiagnosticError", "fg") or 0xfb4934,
		warn = attr("DiagnosticWarn", "fg") or 0xfabd2f,
		info = attr("DiagnosticInfo", "fg") or 0x83a598,
		hint = attr("DiagnosticHint", "fg") or 0x8ec07c,
	}
end

return M
