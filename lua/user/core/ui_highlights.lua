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

-- Large panels retain the shared accent frame. Most transient popups override
-- their window-local Normal/FloatBorder to Pmenu through float_style.lua;
-- nvim-notify deliberately keeps the independent groups defined above.
local function set_float_highlights()
	local p = palette.get()
	vim.api.nvim_set_hl(0, "NormalFloat", { fg = p.fg, bg = p.bg })
	-- FloatBorder remains the source of truth for application-sized panels.
	vim.api.nvim_set_hl(0, "FloatBorder", { fg = p.accent, bg = p.bg })
	vim.api.nvim_set_hl(0, "FloatTitle", { fg = p.accent, bg = p.bg, bold = true })
	-- Borderless popup blocks use Pmenu for both body and padding, and PmenuSel
	-- for selected rows. Explicit links cover plugins that reset winhighlight
	-- after creating their windows.
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
	vim.api.nvim_set_hl(0, "BqfPreviewFloat", { link = "Pmenu" })
	vim.api.nvim_set_hl(0, "BqfPreviewBorder", { link = "Pmenu" })
	vim.api.nvim_set_hl(0, "BqfPreviewTitle", { link = "Pmenu" })
	vim.api.nvim_set_hl(0, "DapUIFloatNormal", { link = "Pmenu" })
	vim.api.nvim_set_hl(0, "DapUIFloatBorder", { link = "Pmenu" })
	vim.api.nvim_set_hl(0, "SnacksInputNormal", { link = "Pmenu" })
	vim.api.nvim_set_hl(0, "SnacksInputBorder", { link = "Pmenu" })
	vim.api.nvim_set_hl(0, "WhichKeyNormal", { link = "Pmenu" })
	vim.api.nvim_set_hl(0, "WhichKeyBorder", { link = "Pmenu" })
	vim.api.nvim_set_hl(0, "WhichKeyTitle", { link = "Pmenu" })
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
