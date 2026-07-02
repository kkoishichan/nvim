local install_dir = vim.fn.stdpath("data") .. "/site"

local languages = {
	"asm",
	"bash",
	"c",
	"cmake",
	"comment",
	"cpp",
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
	"javascript",
	"json",
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
	"javascript",
	"javascriptreact",
	"json",
	"jsonc",
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
}

local function enable_treesitter(event)
	if vim.b[event.buf].bigfile then
		return
	end

	local ok = pcall(vim.treesitter.start, event.buf)
	if not ok then
		return
	end

	vim.bo[event.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
end

return {
	{
		"nvim-treesitter/nvim-treesitter",
		branch = "main",
		event = { "BufReadPre", "BufNewFile" },
		build = function()
			local treesitter = require("nvim-treesitter")
			treesitter.setup({ install_dir = install_dir })
			treesitter.install(languages):wait(300000)
		end,
		opts = {
			install_dir = install_dir,
		},
		config = function(_, opts)
			require("nvim-treesitter").setup(opts)
			pcall(vim.treesitter.language.register, "bash", { "bash", "sh", "zsh" })
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
