-- Colorscheme switching with persistence. The chosen theme is written to a state
-- file and re-applied on the next launch. Inactive themes are lazy-loaded, so
-- only the active one pays a startup cost.

local M = {}

-- name -> { plugin? = <lazy plugin name>, colorscheme = <:colorscheme arg> }
M.themes = {
	default = { colorscheme = "default" },
	-- `plugin` is the lazy.nvim plugin name (its `name`, or the repo basename
	-- when no name is set), used for lazy.load.
	gruvbox = { plugin = "gruvbox", colorscheme = "gruvbox" },
	tokyonight = { plugin = "tokyonight.nvim", colorscheme = "tokyonight" },
	catppuccin = { plugin = "catppuccin", colorscheme = "catppuccin" },
	vscode = { plugin = "vscode.nvim", colorscheme = "vscode" },
}

M.default = "vscode"

local bootstrapped = false

-- Theme names sorted alphabetically. The spec factory uses the same order, so
-- the picker and the installed set never disagree about which theme is which.
function M.names()
	local names = vim.tbl_keys(M.themes)
	table.sort(names)
	return names
end

---Built-in themes and themes whose plugin is part of this installation. A fast
---installation ships only the active plugin theme.
function M.installed()
	local ok, config = pcall(require, "lazy.core.config")
	local names = {}
	for _, name in ipairs(M.names()) do
		local plugin = M.themes[name].plugin
		if not plugin or (ok and config.plugins[plugin]) then
			table.insert(names, name)
		end
	end
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
	if theme.plugin then
		local ok_load = pcall(function()
			require("lazy").load({ plugins = { theme.plugin } })
		end)
		if not ok_load then
			vim.notify("Theme " .. name .. " is not installed in this mode", vim.log.levels.WARN)
			return
		end
	end
	local ok, err = pcall(vim.cmd.colorscheme, theme.colorscheme)
	if not ok then
		vim.notify("Failed to apply theme " .. name .. ": " .. tostring(err), vim.log.levels.ERROR)
		return
	end
	require("user.core.transparency").apply()
	if persist then
		save(name)
	end
end

---Apply the persisted theme (used at startup).
function M.apply_saved()
	M.set(M.saved(), false)
end

---Set up theme-following highlights and apply the startup theme exactly once.
---Called before plugin setup for built-ins, or by the active theme's plugin.
function M.bootstrap()
	if bootstrapped then
		return
	end
	bootstrapped = true
	vim.o.background = "dark"
	require("user.core.ui_highlights").setup()
	require("user.core.transparency").setup()
	M.apply_saved()
end

---Pick a theme interactively and persist the choice.
function M.pick()
	local names = M.installed()
	if #names == 0 then
		names = M.names()
	end
	vim.ui.select(names, {
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
