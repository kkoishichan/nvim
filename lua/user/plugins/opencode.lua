return {
	{
		"nickjvandyke/opencode.nvim",
		version = "*",
		config = function()
			vim.o.autoread = true

			local config = require("opencode.config")
			config.opts.server.start = function()
				require("user.core.ai").open_cli("opencode", true)
			end
		end,
	},
}
