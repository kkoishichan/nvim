-- Clear editor surfaces without changing syntax colours or popup backgrounds.
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

-- link=false also follows the current window's winhighlight. Resolve global
-- links ourselves so toggling from a dock cannot replace Normal's saved colour
-- with the dock's colour or overwrite its saved definition with a cleared one.
local function global_highlight(name)
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
	for _, name in ipairs(groups) do
		local value = global_highlight(name)
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
