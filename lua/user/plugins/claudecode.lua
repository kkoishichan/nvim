-- Claude Code's official-style IDE integration: a WebSocket server that the
-- `claude` CLI connects to (same protocol as the VS Code / JetBrains
-- extensions), running Claude Code in a terminal split with selection sharing,
-- @-mentions, and reviewable diffs.
return {
	{
		"coder/claudecode.nvim",
		init = function()
			-- claudecode's native provider opens its terminal with `enew`, which
			-- leaves the buffer `buflisted` — so it shows up in the bufferline
			-- unlike the codex/opencode terminals. Ask the provider for its exact
			-- managed buffer instead of matching a command-line substring (which
			-- would also catch an unrelated `:term echo claude`).
			vim.api.nvim_create_autocmd("TermOpen", {
				group = vim.api.nvim_create_augroup("user_claudecode_unlist", { clear = true }),
				callback = function(args)
					vim.schedule(function()
						if not vim.api.nvim_buf_is_valid(args.buf) or vim.bo[args.buf].buftype ~= "terminal" then
							return
						end
						local terminal = package.loaded["claudecode.terminal"]
						if not terminal then
							return
						end
						local ok, managed = pcall(terminal.get_active_terminal_bufnr)
						if ok and managed == args.buf then
							vim.bo[args.buf].buflisted = false
						end
					end)
				end,
			})
		end,
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
