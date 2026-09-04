local toolchain = require("user.toolchain")

local function command(name, opts)
	return function()
		return toolchain.executable(name, opts) or name
	end
end

local function node_command(name)
	return function(_, ctx)
		return toolchain.node_executable(name, ctx.buf or ctx.filename) or name
	end
end

local function latexindent_args()
	local cruft = vim.fs.joinpath(vim.fn.stdpath("cache"), "latexindent")
	vim.fn.mkdir(cruft, "p")
	return { "--cruft=" .. cruft }
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
				-- No zsh: shfmt parses bash and can mangle zsh-specific syntax.
			},
			formatters = {
				asmfmt = { command = command("asmfmt"), condition = require("user.core.format_policy").go_assembly },
				biome = {
					command = node_command("biome"),
					require_cwd = true,
				},
				["clang-format"] = { command = command("clang-format") },
				cmake_format = { command = command("cmake-format") },
				gofumpt = { command = command("gofumpt") },
				goimports = { command = command("goimports") },
				-- TeX distributions may expose latexindent even when its Perl modules
				-- are incomplete. Mason ships a self-contained binary, so prefer it
				-- when available and retain the system command as a fallback.
				latexindent = {
					command = command("latexindent", { prefer_mason = true }),
					prepend_args = latexindent_args,
				},
				prettier = { command = node_command("prettier") },
				ruff_format = { command = command("ruff") },
				ruff_organize_imports = { command = command("ruff") },
				shfmt = { command = command("shfmt") },
				sqruff = { command = command("sqruff") },
				stylua = { command = command("stylua") },
				taplo = { command = command("taplo") },
				typstyle = { command = command("typstyle") },
				verible = { command = command("verible-verilog-format") },
			},
			format_on_save = function(bufnr)
				local policy = require("user.core.format_policy")
				if not policy.enabled(bufnr) or policy.after_save(bufnr) then
					return
				end

				return {
					timeout_ms = require("user.core.preferences").get("format").timeout_ms,
					lsp_format = "fallback",
				}
			end,
			format_after_save = function(bufnr)
				local policy = require("user.core.format_policy")
				if policy.enabled(bufnr) and policy.after_save(bufnr) then
					return { timeout_ms = 10000, lsp_format = "never" }
				end
			end,
		},
	},
}
