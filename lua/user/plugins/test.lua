return {
	{
		"nvim-neotest/neotest",
		dependencies = {
			"nvim-neotest/nvim-nio",
			"nvim-lua/plenary.nvim",
			"nvim-neotest/neotest-python",
			"nvim-neotest/neotest-jest",
			"fredrikaverpil/neotest-golang",
			"marilari88/neotest-vitest",
			"mrcjkb/rustaceanvim",
		},
		keys = {
			{
				"<leader>rr",
				function()
					require("neotest").run.run()
				end,
				desc = "Run nearest test",
			},
			{
				"<leader>rf",
				function()
					require("neotest").run.run(vim.fn.expand("%"))
				end,
				desc = "Run file tests",
			},
			{
				"<leader>rd",
				function()
					require("neotest").run.run({ strategy = "dap" })
				end,
				desc = "Debug nearest test",
			},
			{
				"<leader>rx",
				function()
					require("neotest").run.stop()
				end,
				desc = "Stop test",
			},
			{
				"<leader>rs",
				function()
					require("neotest").summary.toggle()
				end,
				desc = "Toggle summary",
			},
			{
				"<leader>ro",
				function()
					require("neotest").output.open({ enter = true, auto_close = true })
				end,
				desc = "Show output",
			},
			{
				"<leader>rO",
				function()
					require("neotest").output_panel.toggle()
				end,
				desc = "Toggle output panel",
			},
			{
				"<leader>rw",
				function()
					require("neotest").watch.toggle(vim.fn.expand("%"))
				end,
				desc = "Toggle watch",
			},
		},
		config = function()
			require("neotest").setup({
				adapters = {
					require("neotest-python")({ dap = { justMyCode = false } }),
					require("neotest-golang")({}),
					require("neotest-jest")({}),
					require("neotest-vitest")({}),
					require("rustaceanvim.neotest"),
				},
			})
		end,
	},
}
