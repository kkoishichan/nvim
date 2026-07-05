return {
	{
		"yaadata/codex.nvim",
		url = "https://codeberg.org/yaadata/codex.nvim.git",
		version = "1.0.0",
		cmd = {
			"Codex",
			"CodexFocus",
			"CodexClose",
			"CodexClearInput",
			"CodexSendSelection",
			"CodexSendFile",
			"CodexMentionFile",
			"CodexMentionDirectory",
			"CodexResume",
		},
		opts = {
			launch = {
				auto_start = false,
			},
			terminal = {
				provider = "native",
				auto_close = true,
				provider_opts = {
					native = {
						window = "vsplit",
						vsplit = {
							side = "right",
							size_pct = 40,
						},
					},
				},
			},
		},
		config = function(_, opts)
			require("codex").setup(opts)
		end,
	},
}
