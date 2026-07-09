-- Colorscheme switching with persistence. The chosen theme is written to a state
-- file and re-applied on the next launch. Inactive themes are lazy-loaded, so
-- only the active one pays a startup cost.

local M = {}

-- name -> { plugin = <lazy plugin name>, colorscheme = <:colorscheme arg> }
M.themes = {
	-- `plugin` is the lazy.nvim plugin name (its `name`, or the repo basename
	-- when no name is set), used for lazy.load.
	gruvbox = { plugin = "gruvbox", colorscheme = "gruvbox" },
	tokyonight = { plugin = "tokyonight.nvim", colorscheme = "tokyonight" },
	catppuccin = { plugin = "catppuccin", colorscheme = "catppuccin" },
}

M.default = "catppuccin"

local bootstrapped = false

-- Theme names sorted alphabetically, for the picker.
local function sorted_names()
	local names = vim.tbl_keys(M.themes)
	table.sort(names)
	return names
end

local file = vim.fn.stdpath("state") .. "/theme.txt"

local function save(name)
	pcall(vim.fn.mkdir, vim.fn.fnamemodify(file, ":h"), "p")
	pcall(vim.fn.writefile, { name }, file)
end

---The persisted theme name, or the default if none/invalid.
function M.saved()
	local ok, lines = pcall(vim.fn.readfile, file)
	local name = ok and lines and lines[1]
	if name and M.themes[name] then
		return name
	end
	return M.default
end

---Apply a theme by name. Loads its plugin on demand; persists when asked.
function M.set(name, persist)
	local theme = M.themes[name]
	if not theme then
		vim.notify("Unknown theme: " .. tostring(name), vim.log.levels.WARN)
		return
	end
	require("lazy").load({ plugins = { theme.plugin } })
	local ok, err = pcall(vim.cmd.colorscheme, theme.colorscheme)
	if not ok then
		vim.notify("Failed to apply theme " .. name .. ": " .. tostring(err), vim.log.levels.ERROR)
		return
	end
	if persist then
		save(name)
	end
end

---Apply the persisted theme (used at startup).
function M.apply_saved()
	M.set(M.saved(), false)
end

---Set up theme-following highlights and apply the startup theme exactly once.
---Called by whichever colorscheme plugin is selected for eager loading.
function M.bootstrap()
	if bootstrapped then
		return
	end
	bootstrapped = true
	vim.o.background = "dark"
	require("user.core.ui_highlights").setup()
	M.apply_saved()
end

---Pick a theme interactively and persist the choice.
function M.pick()
	vim.ui.select(sorted_names(), {
		prompt = "Colorscheme",
		format_item = function(name)
			-- Prefix match: catppuccin reports colors_name as "catppuccin-mocha".
			local active = vim.startswith(vim.g.colors_name or "", M.themes[name].colorscheme)
			return active and (name .. "  (current)") or name
		end,
	}, function(choice)
		if choice then
			M.set(choice, true)
		end
	end)
end

return M
