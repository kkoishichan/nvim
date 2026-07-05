-- Modern-IDE panel docking. Every auxiliary window gets one fixed home, so the
-- layout is always identical instead of "whoever opens first takes the space".
-- The zones mirror VSCode / JetBrains tool-window regions:
--   left   -> navigation + structure (file tree on top, symbol outline below)
--   bottom -> output dock (terminal, problems, tasks, quickfix)
--   right  -> intentionally unused for now (VSCode secondary side bar slot)
--
-- Not docked, on purpose:
--   * dap-ui manages its own windows during a debug session (its default layout
--     already mirrors VSCode's: variables/watches/stacks/breakpoints on a side
--     column, repl/console at the bottom), so edgy leaves it alone.
--   * oil opens full-window (in-place directory editing), no IDE analogue.
--   * pickers / Glance / which-key / notifications stay floating overlays.
--
-- laststatus=3 and splitkeep=screen (edgy prerequisites) are already set in
-- core/options.lua.
local panels = require("user.core.panels")

return {
	{
		"folke/edgy.nvim",
		event = "VeryLazy",
		opts = {
			-- Snap panels into place; no slide animation (matches the config's
			-- restrained feel and avoids jank in terminals under load).
			animate = { enabled = false },
			left = {
				{
					title = "Explorer",
					ft = "neo-tree",
					filter = function(buf)
						return vim.b[buf].neo_tree_source == "filesystem"
					end,
					size = { width = panels.left_panel_width, height = 0.6 },
				},
				{
					title = "Outline",
					ft = "Outline",
					size = { height = 0.4 },
				},
				-- Any other neo-tree source (buffers / git_status) opened on the left.
				"neo-tree",
			},
			bottom = {
				{
					title = "Terminal",
					ft = "toggleterm",
					size = { height = 0.35 },
					-- Only dock non-floating toggleterms; the floating quick-REPL
					-- terminal stays a floating overlay.
					filter = function(_, win)
						return vim.api.nvim_win_get_config(win).relative == ""
					end,
				},
				{ title = "Problems", ft = "trouble", size = { height = 0.35 } },
				{ title = "Tasks", ft = "OverseerList", size = { height = 0.35 } },
				{ title = "Task Output", ft = "OverseerOutput", size = { height = 0.35 } },
				{ title = "QuickFix", ft = "qf", size = { height = 0.35 } },
			},
		},
	},
}
