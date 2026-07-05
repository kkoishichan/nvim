-- Modern-IDE panel docking. Every auxiliary window gets one fixed home, so the
-- layout is always identical instead of "whoever opens first takes the space".
-- The zones mirror VSCode / JetBrains tool-window regions:
--   left   -> navigation + structure (file tree on top, symbol outline below)
--   bottom -> output dock (terminal, problems, tasks, quickfix)
--   right  -> AI assistant chats
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

local function pattern_escape(value)
	return (value:gsub("([^%w])", "%%%1"))
end

local function command_matches(command, executable)
	if type(command) ~= "string" or command == "" then
		return false
	end
	local escaped = pattern_escape(executable)
	return command == executable or command:match("^" .. escaped .. "%s") ~= nil
end

local function ai_terminal(buf, executable)
	local ai = vim.b[buf].user_ai_terminal
	if type(ai) == "table" then
		return ai.provider == executable
	end

	local codex = vim.b[buf].codex_terminal
	if executable == "codex" and type(codex) == "table" then
		return true
	end

	local name = vim.api.nvim_buf_get_name(buf)
	local command = type(name) == "string" and name:match("^term://.-//%d+:(.+)$") or nil
	return command_matches(command, executable)
end

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
					filter = function(buf, win)
						return vim.api.nvim_win_get_config(win).relative == "" and vim.b[buf].user_ai_terminal == nil
					end,
				},
				{ title = "Problems", ft = "trouble", size = { height = 0.35 } },
				{ title = "Tasks", ft = "OverseerList", size = { height = 0.35 } },
				{ title = "Task Output", ft = "OverseerOutput", size = { height = 0.35 } },
				{ title = "QuickFix", ft = "qf", size = { height = 0.35 } },
			},
			right = {
				{
					title = "Codex",
					ft = "",
					filter = function(buf)
						return ai_terminal(buf, "codex")
					end,
					size = { width = 0.40 },
				},
				{
					title = "Claude Code",
					ft = "",
					filter = function(buf)
						return ai_terminal(buf, "claude")
					end,
					size = { width = 0.40 },
				},
				{
					title = "OpenCode",
					ft = "toggleterm",
					filter = function(buf)
						return ai_terminal(buf, "opencode")
					end,
					size = { width = 0.40 },
				},
			},
		},
	},
}
