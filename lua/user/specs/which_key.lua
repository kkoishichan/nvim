-- Shared leader help without importing the full UI plugin set in fast mode.
local float_style = require("user.core.float_style")

return function()
	local mode = require("user.core.mode")
	local fast, icons = mode.is_fast(), mode.capabilities().icons
	local key_icons = { Space = "␣" }
	if not icons then
		for _, key in ipairs({
			"Up",
			"Down",
			"Left",
			"Right",
			"C",
			"M",
			"D",
			"S",
			"CR",
			"Esc",
			"ScrollWheelDown",
			"ScrollWheelUp",
			"NL",
			"BS",
			"Space",
			"Tab",
			"F1",
			"F2",
			"F3",
			"F4",
			"F5",
			"F6",
			"F7",
			"F8",
			"F9",
			"F10",
			"F11",
			"F12",
		}) do
			key_icons[key] = key
		end
		key_icons.C, key_icons.M, key_icons.D, key_icons.S = "Ctrl-", "Alt-", "Super-", "Shift-"
		key_icons.CR, key_icons.NL = "Enter", "Enter"
	end
	return {
		{
			"folke/which-key.nvim",
			event = "VeryLazy",
			opts = function()
				-- Register every group label for normal AND visual mode, so the leader
				-- popup shows names in visual mode too (which-key prunes groups that have
				-- no mappings in the current mode).
				local groups = {
					{ "<leader>a", group = "ai" },
					{ "<leader>b", group = "buffer" },
					{ "<leader>c", group = "code" },
					{ "<leader>cp", group = "peek" },
					{ "<leader>d", group = "debug" },
					{ "<leader>f", group = "find" },
					{ "<leader>g", group = "git" },
					{ "<leader>gh", group = "hunk" },
					{ "<leader>gx", group = "conflict" },
					{ "<leader>j", group = "job" },
					{ "<leader>m", group = "markup" },
					{ "<leader>r", group = "test" },
					{ "<leader>s", group = "session" },
					{ "<leader>t", group = "terminal" },
					{ "<leader>u", group = "ui" },
					{ "<leader>v", group = "multicursor" },
					{ "<leader>x", group = "diagnostics" },
					{ "gs", group = "surround" },
				}
				for _, g in ipairs(groups) do
					g.mode = { "n", "x" }
				end
				return {
					preset = "modern",
					delay = 300,
					-- Fast mode keeps leader discovery without enabling help for
					-- every native motion, register, mark and spelling command.
					triggers = fast and { { "<leader>", mode = { "n", "x" } } } or nil,
					plugins = fast and {
						marks = false,
						registers = false,
						spelling = { enabled = false },
						presets = { enabled = false },
					} or nil,
					spec = groups,
					win = {
						border = float_style.border(),
						padding = { 1, 1 },
						wo = {
							winblend = 0,
							winhighlight = "Normal:Pmenu,NormalFloat:Pmenu,FloatBorder:Pmenu,FloatTitle:Pmenu",
						},
					},
					icons = {
						-- which-key's default Space icon is "󱁐 " -- a glyph followed by a
						-- trailing space, which makes the leader popup title read as the
						-- symbol plus a stray space. Use a plain space symbol, no trailing space.
						keys = key_icons,
						mappings = icons,
						colors = icons,
						breadcrumb = not icons and ">" or nil,
						separator = not icons and "->" or nil,
						ellipsis = not icons and "..." or nil,
					},
				}
			end,
		},
	}
end
