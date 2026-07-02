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
			-- pulling in luasnip (this config completes via blink.cmp). Each language
			-- uses its default convention (doxygen for C/C++, jsdoc/tsdoc, google
			-- docstrings for Python, emmylua for Lua, rustdoc, ...).
			snippet_engine = "nvim",
		},
		keys = {
			{
				"<leader>cc",
				function()
					require("neogen").generate()
				end,
				desc = "Generate doc comment",
			},
			{
				"<leader>cF",
				function()
					require("neogen").generate({ type = "file" })
				end,
				desc = "Generate file header",
			},
		},
	},
}
