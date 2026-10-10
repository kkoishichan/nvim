return function()
	return {
		{
			"folke/flash.nvim",
			opts = {},
			keys = {
				{
					"s",
					function()
						require("flash").jump()
					end,
					mode = { "n", "x", "o" },
					desc = "Flash",
				},
				{
					"S",
					function()
						require("flash").treesitter()
					end,
					mode = { "n", "x", "o" },
					desc = "Flash treesitter",
				},
				{
					"r",
					function()
						require("flash").remote()
					end,
					mode = "o",
					desc = "Remote flash",
				},
				{
					"R",
					function()
						require("flash").treesitter_search()
					end,
					mode = { "x", "o" },
					desc = "Treesitter search",
				},
				{
					"<C-s>",
					function()
						require("flash").toggle()
					end,
					mode = "c",
					desc = "Toggle flash search",
				},
			},
		},
	}
end
