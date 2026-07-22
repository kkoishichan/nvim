local M = {}

-- Keep parser installation, CI validation, and FileType activation on the same
-- complete catalog instead of maintaining language-specific parser subsets.
M.install_dir = vim.fn.stdpath("data") .. "/site"

M.parsers = {
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

M.filetypes = {
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

function M.sync()
	local treesitter = require("nvim-treesitter")
	treesitter.setup({ install_dir = M.install_dir })

	-- update() deliberately ignores missing parsers on nvim-treesitter's main
	-- branch, so install the complete catalog before refreshing its revisions.
	assert(treesitter.install(M.parsers):wait(300000), "failed to install Tree-sitter parsers")
	assert(treesitter.update(M.parsers):wait(300000), "failed to update Tree-sitter parsers")

	for _, parser in ipairs(M.parsers) do
		assert(vim.treesitter.language.add(parser), "Tree-sitter parser is not loadable after sync: " .. parser)
	end
end

function M.enable(event)
	if vim.b[event.buf].bigfile then
		return
	end

	local ok = pcall(vim.treesitter.start, event.buf)
	if not ok then
		return
	end

	-- A parser does not imply that the language ships an indentation query.
	-- Keep the filetype's native indentation when no query is available.
	local lang = vim.treesitter.language.get_lang(vim.bo[event.buf].filetype)
	local has_query, query = pcall(vim.treesitter.query.get, lang, "indents")
	if has_query and query then
		vim.bo[event.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
	end
end

return M
