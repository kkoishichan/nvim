-- Claude Code's official-style IDE integration: a WebSocket server that the
-- `claude` CLI connects to (same protocol as the VS Code / JetBrains
-- extensions), running Claude Code in a terminal split with selection sharing,
-- @-mentions, and reviewable diffs.
return {
	{
		"coder/claudecode.nvim",
		opts = {
			terminal = {
				provider = "native",
				split_side = "right",
				split_width_percentage = 0.40,
				show_native_term_exit_tip = false,
			},
		},
		cmd = {
			"ClaudeCode",
			"ClaudeCodeFocus",
			"ClaudeCodeSelectModel",
			"ClaudeCodeAdd",
			"ClaudeCodeSend",
			"ClaudeCodeTreeAdd",
			"ClaudeCodeStatus",
			"ClaudeCodeStart",
			"ClaudeCodeStop",
			"ClaudeCodeOpen",
			"ClaudeCodeClose",
			"ClaudeCodeDiffAccept",
			"ClaudeCodeDiffDeny",
			"ClaudeCodeCloseAllDiffs",
		},
	},
}
