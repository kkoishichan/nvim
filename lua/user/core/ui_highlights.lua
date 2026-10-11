-- Theme-following UI highlights (notifications, popups, overview rail,
-- snippets, matchparen). Registered as one owner in the highlight chain, so
-- they are re-derived after the transparency pass on every colorscheme.

local palette = require("user.core.palette")

local M = {}

local function set_notify_highlights()
	local p = palette.get()
	local bg = p.surface
	-- Per-level accent pulled from the theme's diagnostic colours.
	local levels = {
		ERROR = p.error,
		WARN = p.warn,
		INFO = p.info,
		DEBUG = p.hint,
		TRACE = p.muted,
	}

	-- nvim-notify uses this as the fade destination, not the window's fill.
	vim.api.nvim_set_hl(0, "NotifyBackground", { bg = p.bg })
	vim.api.nvim_set_hl(0, "NotifyLogTime", { fg = p.muted })
	vim.api.nvim_set_hl(0, "NotifyLogTitle", { fg = p.warn, bold = true })

	for level, accent in pairs(levels) do
		-- A quiet border; the icon and title carry the severity colour.
		vim.api.nvim_set_hl(0, "Notify" .. level .. "Border", { fg = p.muted, bg = bg })
		vim.api.nvim_set_hl(0, "Notify" .. level .. "Icon", { fg = accent, bg = bg, bold = true })
		vim.api.nvim_set_hl(0, "Notify" .. level .. "Title", { fg = accent, bg = bg, bold = true })
		vim.api.nvim_set_hl(0, "Notify" .. level .. "Body", { fg = p.fg, bg = bg })
	end
end

-- Popup colours that do not come from a theme. Borders and surfaces are the
-- plugins' and the colorscheme's own.
local function set_popup_highlights()
	local p = palette.get()
	-- Mark the active signature parameter with a quiet neutral lift instead of
	-- the default blue/cyan LspSignatureActiveParameter background. With no
	-- foreground here, the signature's Tree-sitter colours remain visible.
	vim.api.nvim_set_hl(0, "BlinkCmpSignatureHelpActiveParameter", { bg = p.subtle })
	-- The "(n/m)" overload marker appended by user.core.signature_overloads.
	vim.api.nvim_set_hl(0, "BlinkCmpSignatureHelpOverload", { fg = p.muted })
	-- which-key classifies find/search/diagnostic/AI mappings as "green". The
	-- VS Code palette maps MiniIconsGreen to its comment green, which is too
	-- prominent in the leader popup; keep that one icon class theme-neutral.
	vim.api.nvim_set_hl(0, "WhichKeyIconGreen", { fg = p.dim })
end

-- Keep the scrollbar quieter than editor selections and encode overview-ruler
-- information primarily through colour. The thumb is a low-contrast neutral;
-- hovering turns it into a stronger theme accent without introducing a frame.
local function set_scrollview_highlights()
	local p = palette.get()
	local function foreground(name, fallback)
		return palette.highlight(name).fg or fallback
	end
	local search = foreground("Special", p.warn)
	local mark = foreground("Identifier", p.accent)
	local conflict = foreground("Statement", p.error)
	vim.api.nvim_set_hl(0, "ScrollView", { bg = p.line })
	vim.api.nvim_set_hl(0, "ScrollViewHover", {
		fg = p.fg,
		bg = p.accent_soft,
		bold = true,
	})
	vim.api.nvim_set_hl(0, "ScrollViewRestricted", { bg = p.warn_soft })
	vim.api.nvim_set_hl(0, "ScrollViewSearch", { fg = search, bold = true })
	vim.api.nvim_set_hl(0, "ScrollViewMarks", { fg = mark, bold = true })
	vim.api.nvim_set_hl(0, "ScrollViewConflictsTop", { fg = conflict, bold = true })
	vim.api.nvim_set_hl(0, "ScrollViewConflictsMiddle", { fg = conflict, bold = true })
	vim.api.nvim_set_hl(0, "ScrollViewConflictsBottom", { fg = conflict, bold = true })
	vim.api.nvim_set_hl(0, "ScrollViewKeywordsFix", { fg = p.error })
	vim.api.nvim_set_hl(0, "ScrollViewKeywordsHack", { fg = p.warn })
	vim.api.nvim_set_hl(0, "ScrollViewKeywordsTodo", { fg = p.info })
	vim.api.nvim_set_hl(0, "ScrollViewKeywordsWarn", { fg = p.warn, bold = true })
	vim.api.nvim_set_hl(0, "ScrollViewKeywordsXxx", { fg = p.warn, bold = true })
end

local function set_snippet_highlights()
	local p = palette.get()
	-- Native snippet tabstops default to Visual, which makes editable
	-- placeholders look like editor selections. Give them their own neutral,
	-- theme-derived surface so Visual can retain the colorscheme's accent.
	vim.api.nvim_set_hl(0, "SnippetTabstop", { bg = p.subtle })
	vim.api.nvim_set_hl(0, "SnippetTabstopActive", { link = "SnippetTabstop" })
end

---Apply all theme-derived UI highlights from the current colorscheme.
function M.apply()
	set_notify_highlights()
	set_popup_highlights()
	set_scrollview_highlights()
	set_snippet_highlights()
	local p = palette.get()
	vim.api.nvim_set_hl(0, "MatchParen", { bg = p.strong, fg = p.warn, bold = true })
end

---Register with the highlight chain; applies now and on every colorscheme.
function M.setup()
	require("user.core.highlights").on_colorscheme("ui", M.apply)
end

return M
