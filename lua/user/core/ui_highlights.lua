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
	-- Every float shares one accent border (theme-derived). FloatBorder is the
	-- single source of truth; plugins that draw into their own groups are linked
	-- back to it below so nothing escapes the scheme (e.g. tokyonight ships its
	-- own blue FzfLuaBorder, which we override here).
	vim.api.nvim_set_hl(0, "FloatBorder", { fg = p.accent, bg = p.bg })
	vim.api.nvim_set_hl(0, "FloatTitle", { fg = p.accent, bg = p.bg, bold = true })
	-- blink completion menus are borderless background blocks (border = "padded"),
	-- not framed floats: lift the bg to Pmenu, blend the padding cells into that
	-- bg (so no visible ring), and use PmenuSel for a strong selected row. These
	-- high-frequency popups stay quiet instead of flashing the accent border.
	-- (blink sets its groups with default = true, so these explicit links win.)
	-- Borderless background blocks: lift the bg to the theme's Pmenu, blend the
	-- padding cells into it (no visible ring), and use the theme's native PmenuSel
	-- for the selected row.
	vim.api.nvim_set_hl(0, "BlinkCmpMenu", { link = "Pmenu" })
	vim.api.nvim_set_hl(0, "BlinkCmpMenuBorder", { link = "Pmenu" })
	vim.api.nvim_set_hl(0, "BlinkCmpMenuSelection", { link = "PmenuSel" })
	vim.api.nvim_set_hl(0, "BlinkCmpDoc", { link = "Pmenu" })
	vim.api.nvim_set_hl(0, "BlinkCmpDocBorder", { link = "Pmenu" })
	-- The detail/docs separator line defaults to NormalFloat (editor bg), so its
	-- row shows through against the Pmenu doc bg. Match the doc bg, grey line.
	vim.api.nvim_set_hl(0, "BlinkCmpDocSeparator", { fg = p.gray, bg = vim.api.nvim_get_hl(0, { name = "Pmenu" }).bg })
	vim.api.nvim_set_hl(0, "BlinkCmpSignatureHelp", { link = "Pmenu" })
	vim.api.nvim_set_hl(0, "BlinkCmpSignatureHelpBorder", { link = "Pmenu" })
	-- fzf-lua: override the theme's own FzfLua* border/title onto the shared accent.
	vim.api.nvim_set_hl(0, "FzfLuaBorder", { link = "FloatBorder" })
	vim.api.nvim_set_hl(0, "FzfLuaPreviewBorder", { link = "FloatBorder" })
	vim.api.nvim_set_hl(0, "FzfLuaHelpBorder", { link = "FloatBorder" })
	vim.api.nvim_set_hl(0, "FzfLuaTitle", { link = "FloatTitle" })
	vim.api.nvim_set_hl(0, "FzfLuaPreviewTitle", { link = "FloatTitle" })
	-- lazygit (sets its groups with default = true, so these win).
	vim.api.nvim_set_hl(0, "LazyGitBorder", { link = "FloatBorder" })
	vim.api.nvim_set_hl(0, "LazyGitFloat", { link = "NormalFloat" })
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
