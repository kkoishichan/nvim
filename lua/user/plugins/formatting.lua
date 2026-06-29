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
				cmake = { "cmake_format" },
				cpp = { "clang-format" },
				css = { "biome", "prettier", stop_after_first = true },
				go = { "goimports", "gofumpt" },
				html = { "prettier" },
				javascript = { "biome", "prettier", stop_after_first = true },
				javascriptreact = { "biome", "prettier", stop_after_first = true },
				json = { "biome", "prettier", stop_after_first = true },
				jsonc = { "biome", "prettier", stop_after_first = true },
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
				zsh = { "shfmt" },
			},
			formatters = {
				biome = {
					require_cwd = true,
				},
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
