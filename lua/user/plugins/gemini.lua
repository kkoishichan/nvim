return {
	{
		"vaijab/gemini-cli.nvim",
		build = function(plugin)
			local target = vim.fn.stdpath("data") .. "/gemini/gemini-server"
			vim.fn.mkdir(vim.fn.fnamemodify(target, ":h"), "p")

			local result = vim.system({
				"go",
				"build",
				"-o",
				target,
				"./cmd/gemini-server/main.go",
			}, {
				cwd = plugin.dir,
				text = true,
			}):wait()

			if result.code ~= 0 then
				error(result.stderr ~= "" and result.stderr or result.stdout)
			end
		end,
		event = "VeryLazy",
		opts = {
			debug = false,
		},
		config = function(_, opts)
			require("gemini").setup(opts)
		end,
	},
}
