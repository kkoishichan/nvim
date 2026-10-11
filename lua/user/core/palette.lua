-- Semantic colours derived from the *active* colorscheme, so custom highlights
-- follow whatever theme is loaded instead of hard-coding one theme's values.
-- Everything is pulled from standard highlight groups every theme defines
-- (Normal, Diagnostic*), with the neutral shades blended from fg/bg. Every
-- custom highlight in the configuration names one of these keys; the blend
-- ratios live here and nowhere else.

local M = {}

-- Resolve global links explicitly: get_hl(link=false) also follows the current
-- window's winhighlight. Opening a float with its own Normal must not turn its
-- colours into the base palette when a theme or transparency setting changes.
function M.highlight(name)
	local seen = {}
	while not seen[name] do
		seen[name] = true
		local value = vim.api.nvim_get_hl(0, { name = name, link = true, create = false })
		if not value.link then
			return value
		end
		name = value.link
	end
	return {}
end

local function attr(name, key)
	return M.highlight(name)[key]
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

-- Neutral fallbacks for a theme that leaves a standard group undefined.
local fallback = {
	fg = 0xd0d0d0,
	bg = 0x1e1e1e,
	error = 0xe06c75,
	warn = 0xe5c07b,
	info = 0x61afef,
	hint = 0x98c379,
}

---The darkest shade, used by the dimming backdrop behind application floats.
M.shade = 0x000000

---Snapshot of theme colours. Cheap; call it fresh each time the highlights are
---applied (startup + every ColorScheme) so it always reflects the live theme.
---@return { fg: integer, bg: integer, surface: integer?, raised: integer, sunken: integer, line: integer, muted: integer, dim: integer, subtle: integer, strong: integer, accent: integer, accent_soft: integer, warn_soft: integer, error: integer, warn: integer, info: integer, hint: integer }
function M.get()
	local transparency = require("user.core.transparency")
	local fg = attr("Normal", "fg") or fallback.fg
	local bg = attr("Normal", "bg") or transparency.background() or fallback.bg
	local accent = attr("DiagnosticInfo", "fg") or fallback.info
	local warn = attr("DiagnosticWarn", "fg") or fallback.warn
	return {
		fg = fg,
		bg = bg,
		-- Floats and notifications keep the theme's own popup fill when opaque
		-- and have no fill at all when the background is transparent.
		surface = not transparency.is_enabled() and (attr("NormalFloat", "bg") or bg) or nil,
		-- One step above the editor: the peek list beside its preview.
		raised = M.blend(fg, bg, 0.06),
		-- One step below the editor: the sticky context rows pinned on top.
		sunken = M.blend(M.shade, bg, 0.22),
		-- Lines: window separators, tab underlines, transparent float borders.
		line = M.blend(fg, bg, 0.20),
		-- Secondary text: inactive tabs, hidden entries, overload markers.
		muted = M.blend(fg, bg, 0.60),
		-- Visible but receding text: visible tabs, low-priority icons, titles.
		dim = M.blend(fg, bg, 0.72),
		-- Soft and heavier highlight surfaces: word under cursor, folded line,
		-- active parameter, snippet tabstop / write references, MatchParen.
		subtle = M.blend(fg, bg, 0.15),
		strong = M.blend(fg, bg, 0.25),
		-- One accent, kept in the blue/cyan family across themes.
		accent = accent,
		accent_soft = M.blend(accent, bg, 0.38),
		warn_soft = M.blend(warn, bg, 0.28),
		error = attr("DiagnosticError", "fg") or fallback.error,
		warn = warn,
		info = attr("DiagnosticInfo", "fg") or fallback.info,
		hint = attr("DiagnosticHint", "fg") or fallback.hint,
	}
end

---Two-way Git diffs: old text is red, new text is green, with stronger inline fills.
function M.git_diff()
	local p = M.get()
	local added = attr("GitSignsAdd", "fg") or attr("Added", "fg") or fallback.hint
	local deleted = attr("GitSignsDelete", "fg") or attr("Removed", "fg") or p.error
	return {
		add = M.blend(added, p.bg, 0.18),
		delete = M.blend(deleted, p.bg, 0.18),
		add_text = M.blend(added, p.bg, 0.36),
		delete_text = M.blend(deleted, p.bg, 0.36),
	}
end

return M
