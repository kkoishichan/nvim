local M = {}

-- Mason packages are deliberately pinned. Opening a file never installs this
-- list; :MasonToolsInstall is the explicit, reproducible restore operation.
M.lsp_servers = {
	"asm_lsp",
	"autotools_ls",
	"bashls",
	"basedpyright",
	"biome",
	"clangd",
	"cssls",
	"dockerls",
	"emmet_language_server",
	"gopls",
	"html",
	"jdtls",
	"jsonls",
	"kotlin_lsp",
	"lua_ls",
	"marksman",
	"neocmake",
	"ruff",
	"roslyn_ls",
	"rust_analyzer",
	"sqlls",
	"tailwindcss",
	"taplo",
	"texlab",
	"tinymist",
	"typos_lsp",
	"verible",
	"vtsls",
	"vue_ls",
	"yamlls",
}

local packages = {
	-- Language servers.
	{ "asm-lsp", version = "0.10.1" },
	{ "autotools-language-server", version = "0.0.23" },
	{ "bash-language-server", version = "5.6.0" },
	{ "basedpyright", version = "1.39.8" },
	{ "biome", version = "2.5.0" },
	{ "clangd", version = "22.1.0" },
	{ "css-lsp", version = "4.10.0" },
	{ "dockerfile-language-server", version = "0.15.0" },
	{ "emmet-language-server", version = "2.8.0" },
	{ "gopls", version = "v0.22.0" },
	{ "html-lsp", version = "4.10.0" },
	{ "jdtls", version = "v1.60.0" },
	{ "json-lsp", version = "4.10.0" },
	{ "kotlin-lsp", version = "kotlin-lsp/v262.8190.0" },
	{ "lua-language-server", version = "3.18.2" },
	{ "marksman", version = "2026-02-08" },
	{ "neocmakelsp", version = "v0.10.2" },
	{ "ruff", version = "0.15.14" },
	{ "roslyn-language-server", version = "5.8.0-1.26266.2" },
	{ "rust-analyzer", version = "2026-05-18" },
	{ "sqlls", version = "1.7.1" },
	{ "tailwindcss-language-server", version = "0.14.29" },
	{ "taplo", version = "0.10.0" },
	{ "texlab", version = "v5.25.1" },
	{ "tinymist", version = "v0.14.18" },
	{ "typos-lsp", version = "v0.1.52" },
	{ "verible", version = "v0.0-4053-g89d4d98a" },
	{ "vtsls", version = "0.3.0" },
	{ "vue-language-server", version = "3.3.1" },
	{ "yaml-language-server", version = "1.23.0" },

	-- Formatters and linters.
	{ "asmfmt", version = "v1.3.2" },
	{ "checkmake", version = "v0.3.2" },
	{ "clang-format", version = "22.1.5" },
	{ "cmakelang", version = "0.6.13" },
	{ "cmakelint", version = "1.4.3" },
	{ "csharpier", version = "1.2.6" },
	{ "gofumpt", version = "v0.10.0" },
	{ "goimports", version = "v0.45.0" },
	{ "golangci-lint", version = "v2.12.2" },
	{ "hadolint", version = "v2.14.0" },
	{ "latexindent", version = "V3.24.4" },
	{ "ktlint", version = "1.8.0" },
	{ "markdownlint-cli2", version = "0.22.1" },
	{ "prettier", version = "3.8.3" },
	{ "selene", version = "0.31.0" },
	{ "shellcheck", version = "v0.11.0" },
	{ "shfmt", version = "v3.13.1" },
	{ "sqruff", version = "v0.38.0" },
	{ "stylelint", version = "17.11.1" },
	{ "stylua", version = "v2.5.2" },
	{ "typstyle", version = "v0.14.4" },
	{ "yamllint", version = "1.38.0" },

	-- Debug adapters and Java test bundles.
	{ "codelldb", version = "v1.12.2" },
	{ "debugpy", version = "1.8.21" },
	{ "delve", version = "v1.27.0" },
	{ "js-debug-adapter", version = "v1.117.0" },
	{ "java-debug-adapter", version = "0.59.0" },
	{ "java-test", version = "0.45.0" },
	{ "kotlin-debug-adapter", version = "0.4.4" },
	{ "netcoredbg", version = "3.1.3-1062" },
}

M.packages = packages

function M.version(name)
	for _, package in ipairs(packages) do
		if package[1] == name then
			return package.version
		end
	end
end

function M.executable(name)
	local system = vim.fn.exepath(name)
	if system ~= "" then
		return system
	end

	local candidates = vim.fn.has("win32") == 1 and { name .. ".cmd", name .. ".exe", name .. ".bat", name } or { name }
	for _, candidate in ipairs(candidates) do
		local path = vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "bin", candidate)
		if vim.fn.executable(path) == 1 then
			return path
		end
	end
end

return M
