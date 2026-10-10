-- Workspace symbol search that follows what the buffer actually has. A
-- language server that answers workspace/symbol gets a live query, because
-- vtsls, basedpyright and clangd return little or nothing for the empty query
-- a static picker sends. Without such a server, ripgrep lists the filetype's
-- definition lines and the picker fuzzy-filters them, which is what a tags
-- file would have offered without anything to regenerate.
local M = {}

-- ripgrep (Rust) regex syntax: no backreferences, (?i) for case folding.
local patterns = {
	python = [[^\s*(async\s+def|def|class)\s+\w+]],
	lua = [[^\s*(local\s+)?function\s+[\w.:]+|^\s*(local\s+)?[\w.]+\s*=\s*function\b]],
	sh = [[^\s*(function\s+)?[A-Za-z_]\w*\s*\(\s*\)]],
	go = [[^(func|type)\s+(\(\s*\w+\s+\*?\w+\s*\)\s*)?\w+]],
	rust = [[^\s*(pub(\([^)]*\))?\s+)?(async\s+|unsafe\s+|const\s+)*(fn|struct|enum|trait|impl|type|mod|const|static)\s+[\w<]+]],
	c = [[^\w[\w\s\*]*\b\w+\s*\([^;]*$|^\s*(struct|enum|union|typedef)\s+\w+]],
	javascript = [[^\s*(export\s+)?(default\s+)?(async\s+)?(function\*?|class|interface|type|enum|const|let|var)\s+\w+]],
	java = [[^\s*(public|private|protected|static|final|abstract|sealed|\s)*(class|interface|enum|record)\s+\w+]],
	markdown = [[^#{1,6}\s+\S]],
	yaml = [[^[\w.-]+\s*:]],
	sql = [[(?i)^\s*create\s+(or\s+replace\s+)?(table|view|materialized\s+view|function|procedure|index|type)\s+[\w."]+]],
	vim = [[^\s*fu(n|nction)?!?\s+[\w#:.]+]],
	make = [[^[\w.-]+\s*:]],
}

local aliases = {
	bash = "sh",
	zsh = "sh",
	cpp = "c",
	typescript = "javascript",
	typescriptreact = "javascript",
	javascriptreact = "javascript",
	vue = "javascript",
	plaintex = "markdown",
}

M.patterns = patterns

---The ripgrep definition pattern for a filetype, or nil when there is none.
function M.pattern_for(filetype)
	return patterns[aliases[filetype] or filetype]
end

---True when a client attached to the buffer answers workspace/symbol.
function M.supported(bufnr)
	for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
		if client:supports_method("workspace/symbol", bufnr) then
			return true
		end
	end
	return false
end

---Open the best available workspace symbol search for the current buffer and
---report which route was taken: "lsp", "definitions", "grep" or "native".
---@param opts { cwd?: string }|nil
function M.workspace(opts)
	opts = opts or {}
	local bufnr = vim.api.nvim_get_current_buf()
	local root = opts.cwd or require("user.core.project").root()
	local native = require("user.core.native_search")
	if M.supported(bufnr) then
		if native.usable() then
			require("fzf-lua").lsp_live_workspace_symbols({ cwd = root })
		else
			vim.lsp.buf.workspace_symbol()
		end
		return "lsp"
	end
	if not native.usable() then
		native.grep({ cwd = root })
		return "native"
	end
	local pattern = M.pattern_for(vim.bo[bufnr].filetype)
	if not pattern then
		require("fzf-lua").live_grep({ cwd = root })
		return "grep"
	end
	require("fzf-lua").grep({ cwd = root, search = pattern, no_esc = true, prompt = "Definitions> " })
	return "definitions"
end

---Project-wide TODO search: the explicit twin of the todo-comments layer.
---@param opts { cwd?: string }|nil
function M.todos(opts)
	opts = opts or {}
	local root = opts.cwd or require("user.core.project").root()
	local native = require("user.core.native_search")
	local pattern = [[\b(TODO|FIXME|FIX|HACK|WARN|WARNING|XXX|BUG|NOTE)\b]]
	if not native.usable() then
		native.grep({ cwd = root })
		return "native"
	end
	require("fzf-lua").grep({ cwd = root, search = pattern, no_esc = true, prompt = "Todos> " })
	return "todos"
end

return M
