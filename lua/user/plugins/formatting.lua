local toolchain = require("user.toolchain")

local function command(name)
	return function()
		return toolchain.executable(name) or name
	end
end

local function node_command(name)
	local local_name = vim.fn.has("win32") == 1 and name .. ".cmd" or name
	local resolver
	return function(self, ctx)
		resolver = resolver or require("conform.util").from_node_modules(local_name)
		local candidate = resolver(self, ctx)
		if candidate ~= local_name and vim.fn.executable(candidate) == 1 then
			return candidate
		end
		return toolchain.executable(name) or candidate
	end
end

return {
	{
		"stevearc/conform.nvim",
		event = { "BufWritePre" },
		cmd = { "ConformInfo" },
		keys = {
			{
				"<leader>cf",
				function()
					require("conform").format({ async = true, lsp_format = "fallback" })
				end,
				mode = { "n", "x" },
				desc = "Format",
			},
		},
		init = function()
			vim.api.nvim_create_user_command("FormatDisable", function(args)
				if args.bang then
					vim.b.disable_autoformat = true
				else
					vim.g.disable_autoformat = true
				end
			end, {
				bang = true,
				desc = "Disable autoformat globally, or for this buffer with !",
			})

			vim.api.nvim_create_user_command("FormatEnable", function()
				vim.b.disable_autoformat = false
				vim.g.disable_autoformat = false
			end, { desc = "Enable autoformat" })
		end,
		opts = {
			formatters_by_ft = {
				asm = { "asmfmt" },
				c = { "clang-format" },
				cs = { "csharpier" },
				cmake = { "cmake_format" },
				cpp = { "clang-format" },
				css = { "biome", "prettier", stop_after_first = true },
				go = { "goimports", "gofumpt" },
				html = { "prettier" },
				javascript = { "biome", "prettier", stop_after_first = true },
				javascriptreact = { "biome", "prettier", stop_after_first = true },
				json = { "biome", "prettier", stop_after_first = true },
				jsonc = { "biome", "prettier", stop_after_first = true },
				kotlin = { "ktlint" },
				lua = { "stylua" },
				markdown = { "prettier" },
				python = { "ruff_organize_imports", "ruff_format" },
				rust = { "rustfmt" },
				sh = { "shfmt" },
				sql = { "sqruff" },
				tex = { "latexindent" },
				toml = { "taplo" },
				typescript = { "biome", "prettier", stop_after_first = true },
				typescriptreact = { "biome", "prettier", stop_after_first = true },
				typst = { "typstyle" },
				systemverilog = { "verible" },
				verilog = { "verible" },
				vue = { "prettier" },
				yaml = { "prettier" },
				-- No zsh: shfmt parses bash and can mangle zsh-specific syntax.
			},
			formatters = {
				asmfmt = { command = command("asmfmt") },
				biome = {
					command = node_command("biome"),
					require_cwd = true,
				},
				["clang-format"] = { command = command("clang-format") },
				cmake_format = { command = command("cmake-format") },
				csharpier = {
					command = command("csharpier"),
					args = { "format" },
					condition = function()
						return toolchain.executable("dotnet") ~= nil
					end,
				},
				gofumpt = { command = command("gofumpt") },
				goimports = { command = command("goimports") },
				ktlint = {
					command = command("ktlint"),
					condition = function()
						return toolchain.executable("java") ~= nil
					end,
				},
				latexindent = { command = command("latexindent") },
				prettier = { command = node_command("prettier") },
				ruff_format = {
					command = command("ruff"),
					append_args = { "--line-length", "100" },
				},
				ruff_organize_imports = { command = command("ruff") },
				shfmt = { command = command("shfmt") },
				sqruff = { command = command("sqruff") },
				stylua = { command = command("stylua") },
				taplo = { command = command("taplo") },
				typstyle = { command = command("typstyle") },
				verible = { command = command("verible-verilog-format") },
			},
			format_on_save = function(bufnr)
				if vim.g.disable_autoformat or vim.b[bufnr].disable_autoformat or vim.b[bufnr].bigfile then
					return
				end

				return {
					timeout_ms = 2000,
					lsp_format = "fallback",
				}
			end,
		},
	},
}
