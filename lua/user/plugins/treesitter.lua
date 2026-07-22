local install_dir = vim.fn.stdpath("data") .. "/site"
local treesitter_config = require("user.core.treesitter")

return {
	{
		"nvim-treesitter/nvim-treesitter",
		branch = "main",
		-- The main branch does not support lazy-loading (per its README): load at
		-- startup so parsers and queries never desync from the plugin version.
		lazy = false,
		build = function()
			local treesitter = require("nvim-treesitter")
			treesitter.setup({ install_dir = install_dir })
			-- install() supplies parsers missing on a fresh machine; update() then
			-- refreshes parsers whose pinned grammar revision changed. update() alone
			-- deliberately ignores missing parsers on nvim-treesitter's main branch.
			assert(treesitter.install(treesitter_config.parsers):wait(300000), "failed to install Tree-sitter parsers")
			assert(treesitter.update(treesitter_config.parsers):wait(300000), "failed to update Tree-sitter parsers")
		end,
		opts = {
			install_dir = install_dir,
		},
		config = function(_, opts)
			require("nvim-treesitter").setup(opts)
			-- zsh has its own parser (installed above), so it is not routed to bash.
			pcall(vim.treesitter.language.register, "bash", { "bash", "sh" })
			pcall(vim.treesitter.language.register, "asm", "riscv")

			vim.api.nvim_create_autocmd("FileType", {
				group = vim.api.nvim_create_augroup("user_treesitter", { clear = true }),
				pattern = treesitter_config.filetypes,
				callback = treesitter_config.enable,
			})
		end,
	},
	{
		"nvim-treesitter/nvim-treesitter-textobjects",
		branch = "main",
		event = { "BufReadPost", "BufNewFile" },
		dependencies = { "nvim-treesitter/nvim-treesitter" },
		config = function()
			require("nvim-treesitter-textobjects").setup({
				move = { set_jumps = true },
			})

			-- In-buffer symbol motions (select stays with mini.ai). Functions take
			-- a capture and the "textobjects" query group.
			local move = require("nvim-treesitter-textobjects.move")
			local function map(lhs, fn, query, desc)
				vim.keymap.set({ "n", "x", "o" }, lhs, function()
					fn(query, "textobjects")
				end, { silent = true, desc = desc })
			end

			map("]m", move.goto_next_start, "@function.outer", "Next function start")
			map("[m", move.goto_previous_start, "@function.outer", "Previous function start")
			map("]M", move.goto_next_end, "@function.outer", "Next function end")
			map("[M", move.goto_previous_end, "@function.outer", "Previous function end")
			map("]]", move.goto_next_start, "@class.outer", "Next class start")
			map("[[", move.goto_previous_start, "@class.outer", "Previous class start")
			map("][", move.goto_next_end, "@class.outer", "Next class end")
			map("[]", move.goto_previous_end, "@class.outer", "Previous class end")
		end,
	},
}
