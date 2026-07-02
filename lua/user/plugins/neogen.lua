-- Generate documentation-comment skeletons (Doxygen for C/C++, and the idiomatic
-- convention for other languages) from the treesitter tree under the cursor.
-- Parameter names are filled in automatically; jump between the empty fields with
-- the snippet <Tab>/<S-Tab> from Neovim's native vim.snippet (blink.cmp drives it).
return {
	{
		"danymat/neogen",
		cmd = "Neogen",
		dependencies = { "nvim-treesitter/nvim-treesitter" },
		opts = {
			-- Native vim.snippet expansion -> jumpable <param> placeholders without
			-- pulling in luasnip (this config completes via blink.cmp).
			snippet_engine = "nvim",
			languages = {
				-- Emit Javadoc-style /** @brief ... */ blocks (matches the existing
				-- headers) rather than Neogen's default /// line comments.
				c = { template = { annotation_convention = "doxygen" } },
				cpp = { template = { annotation_convention = "doxygen" } },
			},
		},
		keys = {
			{
				"<leader>cc",
				function()
					require("neogen").generate()
				end,
				desc = "Generate doc comment",
			},
		},
	},
}
