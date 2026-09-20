-- mini.nvim, the editing library both modes share. Only the selected modules
-- are initialized: fast mode keeps the local character check that drives
-- autopairs and leaves surround, align and the extended text objects to load
-- when one of their keys is pressed, instead of at VeryLazy.
local mode = require("user.core.mode")

local surround_mappings = {
	add = "gsa",
	delete = "gsd",
	find = "gsf",
	find_left = "gsF",
	highlight = "gsh",
	replace = "gsr",
}

local move_mappings = {
	left = "<M-h>",
	right = "<M-l>",
	down = "<M-j>",
	up = "<M-k>",
	line_left = "<M-h>",
	line_right = "<M-l>",
	line_down = "<M-j>",
	line_up = "<M-k>",
}

local function setup_modules(treesitter_textobjects)
	local ai = require("mini.ai")
	local custom_textobjects = {
		u = ai.gen_spec.function_call(),
		U = ai.gen_spec.function_call({ name_pattern = "[%w_]" }),
	}
	if treesitter_textobjects then
		-- These queries live in nvim-treesitter-textobjects, which a fast
		-- installation does not ship; asking for them there would only fail later.
		custom_textobjects.c = ai.gen_spec.treesitter({ a = "@class.outer", i = "@class.inner" })
		custom_textobjects.f = ai.gen_spec.treesitter({ a = "@function.outer", i = "@function.inner" })
		custom_textobjects.o = ai.gen_spec.treesitter({
			a = { "@block.outer", "@conditional.outer", "@loop.outer" },
			i = { "@block.inner", "@conditional.inner", "@loop.inner" },
		})
	end
	ai.setup({ n_lines = 500, custom_textobjects = custom_textobjects })
	require("mini.move").setup({ mappings = move_mappings })
	require("mini.pairs").setup()
	require("mini.surround").setup({ mappings = surround_mappings })
	-- gaip= aligns a paragraph on "=", gA opens the interactive
	-- preview (pick delimiter, justification, etc.).
	require("mini.align").setup()
end

local function lazy_keys()
	local keys = {
		{ "ga", desc = "Align" },
		{ "gA", desc = "Align with preview" },
		{ "a", mode = { "x", "o" }, desc = "Around text object" },
		{ "i", mode = { "x", "o" }, desc = "Inside text object" },
	}
	for _, lhs in pairs(surround_mappings) do
		table.insert(keys, { lhs, mode = { "n", "x" }, desc = "Surround" })
	end
	for _, lhs in pairs(move_mappings) do
		table.insert(keys, { lhs, mode = { "n", "x" }, desc = "Move selection" })
	end
	return keys
end

return function()
	local fast = mode.is_fast()
	return {
		{
			"nvim-mini/mini.nvim",
			version = false,
			-- Autopairs has to be live before the first inserted character; the
			-- remaining modules are reached through their own keys.
			event = fast and "InsertEnter" or "VeryLazy",
			keys = fast and lazy_keys() or nil,
			config = function()
				setup_modules(not fast)
			end,
		},
	}
end
