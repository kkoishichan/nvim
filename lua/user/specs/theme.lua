-- Colourscheme plugins. Both modes use the same theme with the same colours, so
-- this factory is shared rather than duplicated. Full mode keeps every theme
-- available to the picker and loads only the selected one; a fast installation
-- ships just the selected theme, because an absent plugin would otherwise be
-- reported as missing on every launch.
local theme = require("user.core.theme")

local function specs()
	return {
		gruvbox = {
			"ellisonleao/gruvbox.nvim",
			name = "gruvbox",
			priority = 1001,
			opts = {
				terminal_colors = true,
				undercurl = true,
				underline = true,
				bold = true,
				strikethrough = true,
				invert_selection = false,
				invert_signs = false,
				invert_tabline = false,
				inverse = true,
				contrast = "hard",
				dim_inactive = false,
				transparent_mode = false,
			},
			config = function(_, opts)
				require("gruvbox").setup(opts)
				theme.bootstrap()
			end,
		},
		tokyonight = {
			"folke/tokyonight.nvim",
			priority = 1000,
			opts = { style = "night" },
			config = function(_, opts)
				require("tokyonight").setup(opts)
				theme.bootstrap()
			end,
		},
		catppuccin = {
			"catppuccin/nvim",
			name = "catppuccin",
			priority = 1000,
			opts = { flavour = "mocha" },
			config = function(_, opts)
				require("catppuccin").setup(opts)
				theme.bootstrap()
			end,
		},
		vscode = {
			"Mofiqul/vscode.nvim",
			priority = 1000,
			opts = {
				style = "dark",
				transparent = false,
				-- The stock popup is #202020 against a #1F1F1F editor. Our small
				-- borderless floats use Pmenu, so lift it enough to remain legible.
				color_overrides = { vscPopupBack = "#2D2D30" },
				italic_comments = true,
				underline_links = true,
				terminal_colors = true,
			},
			config = function(_, opts)
				require("vscode").setup(opts)
				theme.bootstrap()
			end,
		},
	}
end

---@param opts table|nil `{ single = true }` installs only the active theme.
return function(opts)
	local active = theme.saved()
	local available = specs()
	if opts and opts.single then
		if not theme.themes[active].plugin then
			return {}
		end
		local selected = available[active] or available[theme.default]
		selected.lazy = false
		return { selected }
	end
	local result = {}
	for _, name in ipairs(theme.names()) do
		local spec = available[name]
		if spec then
			spec.lazy = name ~= active
			table.insert(result, spec)
		end
	end
	return result
end
