-- Theme-following UI highlights (notifications, floats, matchparen). Pulled out
-- of any single colorscheme's config so they apply for whatever theme is active;
-- M.setup() registers a ColorScheme autocmd that re-derives them on every switch.

local palette = require("user.core.palette")

local M = {}

local function set_notify_highlights()
	local p = palette.get()
	local bg = p.panel
	-- Per-level accent pulled from the theme's diagnostic colours.
	local levels = {
		ERROR = p.error,
		WARN = p.warn,
		INFO = p.info,
		DEBUG = p.hint,
		TRACE = p.gray,
	}

	vim.api.nvim_set_hl(0, "NotifyBackground", { bg = bg })
	vim.api.nvim_set_hl(0, "NotifyLogTime", { fg = p.gray })
	vim.api.nvim_set_hl(0, "NotifyLogTitle", { fg = p.warn, bold = true })

	for level, accent in pairs(levels) do
		-- Border is a dimmed-toward-bg version of the accent so it reads quieter.
		vim.api.nvim_set_hl(0, "Notify" .. level .. "Border", { fg = palette.blend(accent, bg, 0.7), bg = bg })
		vim.api.nvim_set_hl(0, "Notify" .. level .. "Icon", { fg = accent, bg = bg, bold = true })
		vim.api.nvim_set_hl(0, "Notify" .. level .. "Title", { fg = accent, bg = bg, bold = true })
		vim.api.nvim_set_hl(0, "Notify" .. level .. "Body", { fg = p.fg, bg = bg })
	end
end

-- Floats use no global border (see winborder in core/options); each window that
-- wants one sets border = "rounded" itself. Make the border share the editor
-- background so it never shows an off-colour ring around the float.
local function set_float_highlights()
	local p = palette.get()
	vim.api.nvim_set_hl(0, "NormalFloat", { fg = p.fg, bg = p.bg })
	vim.api.nvim_set_hl(0, "FloatBorder", { fg = p.gray, bg = p.bg })
	vim.api.nvim_set_hl(0, "FloatTitle", { fg = p.gray, bg = p.bg, bold = true })
	-- Two tiers, by role:
	--   * Popups that hover over code you're reading (blink completion/doc/signature,
	--     hover, dict, diagnostics) get the quiet grey FloatBorder so they don't
	--     compete with the buffer.
	--   * Big takeover windows that cover most of the buffer (fzf-lua, lazygit,
	--     scratch) keep a white border (Normal fg) -- they ARE the focus, and white
	--     also matches lazygit's own white inner panels. Those are left at their
	--     plugin defaults (link -> Normal) / set via winhighlight, so nothing to do
	--     here for them.
	-- blink sets its groups with default = true, so these explicit links win.
	vim.api.nvim_set_hl(0, "BlinkCmpMenu", { link = "NormalFloat" })
	vim.api.nvim_set_hl(0, "BlinkCmpMenuBorder", { link = "FloatBorder" })
	vim.api.nvim_set_hl(0, "BlinkCmpDocBorder", { link = "FloatBorder" })
	vim.api.nvim_set_hl(0, "BlinkCmpSignatureHelpBorder", { link = "FloatBorder" })
end

---Apply all theme-derived UI highlights from the current colorscheme.
function M.apply()
	set_notify_highlights()
	set_float_highlights()
	local p = palette.get()
	vim.api.nvim_set_hl(0, "MatchParen", { bg = p.strong, fg = p.warn, bold = true })
end

---Register the ColorScheme autocmd so the highlights are re-derived on switch.
function M.setup()
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = vim.api.nvim_create_augroup("user_ui_highlights", { clear = true }),
		callback = M.apply,
	})
end

return M
