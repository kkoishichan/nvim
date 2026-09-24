-- Clear editor surfaces while retaining opaque, theme-derived popup surfaces.
-- Keep the original definitions so toggling off restores links as well as RGB
-- and terminal colours, without reloading the theme or any plugins.
local M = {}
local file = vim.fn.stdpath("state") .. "/transparent.txt"
local ok, lines = pcall(vim.fn.readfile, file)
local enabled = ok and lines[1] == "1"
local originals = {}
local background
local groups = {
	"Normal",
	"NormalNC",
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
	"NormalSB",
	"SignColumnSB",
	"NeoTreeNormal",
	"NeoTreeNormalNC",
	"NeoTreeEndOfBuffer",
	"NeoTreeSignColumn",
	"NeoTreeWinSeparator",
	"EdgyNormal",
	"EdgyWinBar",
	"EdgyWinBarNC",
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
			originals[name] = vim.api.nvim_get_hl(0, { name = name, link = true, create = false })
			if name == "Normal" then
				background = value.bg
			end
			value.bg, value.ctermbg = nil, nil
			vim.api.nvim_set_hl(0, name, value)
		end
	end
end

function M.toggle()
	enabled = not enabled
	if enabled then
		M.apply()
	else
		for name, value in pairs(originals) do
			vim.api.nvim_set_hl(0, name, value)
		end
		originals, background = {}, nil
	end
	-- Framed floats use the editor colour when opaque and a solid panel colour
	-- when transparent. Refresh their groups without reloading the colorscheme.
	require("user.core.ui_highlights").apply()

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
			originals, background = {}, nil
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
