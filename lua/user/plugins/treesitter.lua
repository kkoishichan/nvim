local install_dir = vim.fn.stdpath("data") .. "/site"

local languages = {
	"asm",
	"bash",
	"c",
	"cmake",
	"comment",
	"cpp",
	"c_sharp",
	"css",
	"diff",
	"dockerfile",
	"doxygen",
	"git_config",
	"gitcommit",
	"gitignore",
	"go",
	"gomod",
	"gosum",
	"gowork",
	"html",
	"hyprlang",
	"java",
	"javascript",
	"json",
	"kotlin",
	"latex",
	"lua",
	"luadoc",
	"make",
	"markdown",
	"markdown_inline",
	"nasm",
	"python",
	"query",
	"rust",
	"sql",
	"systemverilog",
	"toml",
	"tsx",
	"typescript",
	"typst",
	"vim",
	"vimdoc",
	"vue",
	"yaml",
	"zsh",
}

local filetypes = {
	"asm",
	"bash",
	"c",
	"cmake",
	"cpp",
	"cs",
	"css",
	"diff",
	"dockerfile",
	"gitcommit",
	"gitconfig",
	"gitignore",
	"go",
	"gomod",
	"gosum",
	"gowork",
	"html",
	"hyprlang",
	"java",
	"javascript",
	"javascriptreact",
	"json",
	"jsonc",
	"kotlin",
	"latex",
	"lua",
	"make",
	"markdown",
	"nasm",
	"python",
	"query",
	"riscv",
	"rust",
	"sh",
	"sql",
	"systemverilog",
	"tex",
	"toml",
	"typescript",
	"typescriptreact",
	"typst",
	"vim",
	"vimdoc",
	"vue",
	"verilog",
	"yaml",
	"zsh",
}

local function enable_treesitter(event)
	if vim.b[event.buf].bigfile then
		return
	end

	local ok = pcall(vim.treesitter.start, event.buf)
	if not ok then
		return
	end

	-- A parser does not imply that the language ships an indentation query.
	-- Calling nvim-treesitter's indentexpr without one falls back badly (for
	-- example, SystemVerilog gets flattened by `=`). Keep the filetype's native
	-- indentation unless an `indents` query is actually available.
	local lang = vim.treesitter.language.get_lang(vim.bo[event.buf].filetype)
	local has_query, query = pcall(vim.treesitter.query.get, lang, "indents")
	if has_query and query then
		vim.bo[event.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
	end
end

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
			-- update() force-(re)installs the given list: installs anything missing
			-- on a fresh machine AND refreshes already-installed parsers on a plugin
			-- bump. Plain install() skips parsers that already exist, so it would
			-- never update them -- that was the stale-parser risk.
			treesitter.update(languages):wait(300000)
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
				pattern = filetypes,
				callback = enable_treesitter,
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
