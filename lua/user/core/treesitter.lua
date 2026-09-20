local M = {}

-- Keep parser installation, validation, and FileType activation on the same
-- complete catalog instead of maintaining language-specific parser subsets.
M.install_dir = vim.fn.stdpath("data") .. "/site"

M.parsers = {
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
	"java",
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

M.filetypes = {
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
	"java",
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
	"zsh",
}

-- What a slim installation starts with: the languages a configuration and
-- operations host actually edits, together with the parsers their injections
-- and queries depend on. Every other language is added by an explicit
-- deployment parameter, never by opening a file.
M.base_parsers = {
	"bash",
	"comment",
	"json",
	"lua",
	"luadoc",
	"markdown",
	"markdown_inline",
	"python",
	"query",
	"toml",
	"vim",
	"vimdoc",
	"yaml",
}

---The parser set for a mode, plus any languages a deployment asked for. An
---unknown name is a mistake in the request, not a silent omission.
---@param mode string "full" or "fast"
---@param extra string[]|nil additional language names
function M.select(mode, extra)
	if mode ~= "fast" then
		return vim.deepcopy(M.parsers)
	end
	local catalog = {}
	for _, parser in ipairs(M.parsers) do
		catalog[parser] = true
	end
	local selected, seen = {}, {}
	local function add(name)
		assert(catalog[name], "Unknown Tree-sitter parser: " .. name)
		if not seen[name] then
			seen[name] = true
			table.insert(selected, name)
		end
	end
	for _, parser in ipairs(M.base_parsers) do
		add(parser)
	end
	for _, parser in ipairs(extra or {}) do
		add(parser)
	end
	table.sort(selected)
	return selected
end

---The parsers this installation manages. A deployment narrows the set with the
---mode it installed and NVIM_PARSERS; a full installation keeps the catalog.
function M.selected()
	return M.select(require("user.core.mode").name(), vim.split(vim.env.NVIM_PARSERS or "", ",", { trimempty = true }))
end

function M.sync()
	local treesitter = require("nvim-treesitter")
	treesitter.setup({ install_dir = M.install_dir })

	-- update() deliberately ignores missing parsers on nvim-treesitter's main
	-- branch, so install the selected set before refreshing its revisions.
	local parsers = M.selected()
	assert(treesitter.install(parsers):wait(300000), "failed to install Tree-sitter parsers")
	assert(treesitter.update(parsers):wait(300000), "failed to update Tree-sitter parsers")

	for _, parser in ipairs(parsers) do
		assert(vim.treesitter.language.add(parser), "Tree-sitter parser is not loadable after sync: " .. parser)
	end
end

function M.enable(event)
	if not require("user.core.buffer_policy").allow(event.buf) then
		return
	end

	local ok = pcall(vim.treesitter.start, event.buf)
	if not ok then
		-- No parser for this language on this host. Opening a file must not
		-- download one, so keep the native syntax and filetype indentation and
		-- record the loss where :ModeInfo and :checkhealth can report it.
		require("user.core.mode").degrade(
			"treesitter",
			"no parser for " .. vim.bo[event.buf].filetype .. "; using native syntax and indentation"
		)
		return
	end

	-- A parser does not imply that the language ships an indentation query.
	-- Keep the filetype's native indentation when no query is available.
	local lang = vim.treesitter.language.get_lang(vim.bo[event.buf].filetype)
	if lang == "python" then
		require("user.core.python_indent").setup()
	end
	local has_query, query = pcall(vim.treesitter.query.get, lang, "indents")
	if has_query and query then
		vim.bo[event.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
	end
end

return M
