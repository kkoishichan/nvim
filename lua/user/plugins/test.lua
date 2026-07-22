local function testing()
	return require("user.core.testing")
end

return {
	{
		"nvim-neotest/neotest",
		dependencies = { "nvim-neotest/nvim-nio", "nvim-lua/plenary.nvim" },
		keys = {
			{
				"<leader>rr",
				function()
					testing().run()
				end,
				desc = "Run nearest test",
			},
			{
				"<leader>rf",
				function()
					testing().run(vim.fn.expand("%"))
				end,
				desc = "Run file tests",
			},
			{
				"<leader>rd",
				function()
					testing().run({ strategy = "dap" })
				end,
				desc = "Debug nearest test",
			},
			{
				"<leader>rx",
				function()
					testing().stop()
				end,
				desc = "Stop test",
			},
			{
				"<leader>rs",
				function()
					testing().summary()
				end,
				desc = "Toggle summary",
			},
			{
				"<leader>ro",
				function()
					testing().output()
				end,
				desc = "Show output",
			},
			{
				"<leader>rO",
				function()
					testing().output_panel()
				end,
				desc = "Toggle output panel",
			},
			{
				"<leader>rw",
				function()
					testing().watch()
				end,
				desc = "Toggle watch",
			},
		},
	},
	{ "codymikol/neotest-kotlin", lazy = true },
	{ "Nsidorenco/neotest-vstest", lazy = true },
	{ "nvim-neotest/neotest-python", lazy = true },
	{ "nvim-neotest/neotest-jest", lazy = true },
	{ "fredrikaverpil/neotest-golang", lazy = true },
	{ "marilari88/neotest-vitest", lazy = true },
}
