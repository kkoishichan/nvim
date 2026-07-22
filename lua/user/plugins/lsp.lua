local toolchain = require("user.toolchain")
local servers = toolchain.lsp_servers

local function client_supports(client, method, bufnr)
	if not client or not client.supports_method then
		return false
	end
	return client:supports_method(method, bufnr)
end

local function setup_lsp_keymaps()
	vim.api.nvim_create_autocmd("LspAttach", {
		group = vim.api.nvim_create_augroup("user_lsp_attach", { clear = true }),
		callback = function(event)
			local bufnr = event.buf
			local client = vim.lsp.get_client_by_id(event.data.client_id)
			local map = function(mode, lhs, rhs, desc)
				vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, desc = desc })
			end

			map("n", "K", function()
				vim.lsp.buf.hover()
			end, "Hover")
			map("n", "gd", "<cmd>FzfLua lsp_definitions<cr>", "Definitions")
			map("n", "gD", "<cmd>FzfLua lsp_declarations<cr>", "Declarations")
			map("n", "gi", "<cmd>FzfLua lsp_implementations<cr>", "Implementations")
			map("n", "gy", "<cmd>FzfLua lsp_typedefs<cr>", "Type definitions")
			map("n", "gr", "<cmd>FzfLua lsp_references<cr>", "References")
			map("n", "<leader>ca", vim.lsp.buf.code_action, "Code action")
			map("n", "<leader>ci", "<cmd>FzfLua lsp_incoming_calls<cr>", "Incoming calls")
			map("n", "<leader>co", "<cmd>FzfLua lsp_outgoing_calls<cr>", "Outgoing calls")
			map("n", "<leader>cpD", "<cmd>FzfLua lsp_declarations<cr>", "Declarations")
			map("n", "<leader>cpd", "<cmd>FzfLua lsp_definitions<cr>", "Definitions")
			map("n", "<leader>cpi", "<cmd>FzfLua lsp_implementations<cr>", "Implementations")
			map("n", "<leader>cpr", "<cmd>FzfLua lsp_references<cr>", "References")
			map("n", "<leader>cpt", "<cmd>FzfLua lsp_typedefs<cr>", "Type definitions")
			map("n", "<leader>cs", "<cmd>FzfLua lsp_document_symbols<cr>", "Document symbols")
			map("n", "<leader>cS", "<cmd>FzfLua lsp_workspace_symbols<cr>", "Workspace symbols")

			if client_supports(client, "textDocument/inlayHint", bufnr) then
				map("n", "<leader>uh", function()
					vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = bufnr }), { bufnr = bufnr })
				end, "Toggle inlay hints")
			end
		end,
	})
end

return {
	{
		"smjonas/inc-rename.nvim",
		cmd = "IncRename",
		opts = {},
		keys = {
			{
				"<leader>cr",
				function()
					return ":IncRename " .. vim.fn.expand("<cword>")
				end,
				expr = true,
				desc = "Rename symbol",
			},
		},
	},
	{
		"kosayoda/nvim-lightbulb",
		event = "LspAttach",
		opts = {
			autocmd = { enabled = true },
			sign = { enabled = true, text = "󰌶", hl = "DiagnosticSignHint" },
			virtual_text = { enabled = false },
			float = { enabled = false },
			status_text = { enabled = false },
		},
	},
	{
		"mason-org/mason.nvim",
		cmd = { "Mason", "MasonInstall", "MasonLog", "MasonUninstall", "MasonUninstallAll", "MasonUpdate" },
		opts = {
			-- Resolve Mason binaries per plugin instead of changing Neovim's global
			-- PATH (which would leak into every :terminal child process).
			PATH = "skip",
			ui = {
				border = "rounded",
			},
		},
		init = function()
			local function install_command(name, package_names, description)
				vim.api.nvim_create_user_command(name, function()
					require("lazy").load({ plugins = { "mason.nvim" } })
					local packages = {}
					for _, package_name in ipairs(package_names) do
						table.insert(packages, ("%s@%s"):format(package_name, toolchain.version(package_name)))
					end
					vim.cmd("MasonInstall " .. table.concat(packages, " "))
				end, { desc = description, force = true })
			end

			install_command(
				"MasonCSharpInstall",
				{ "roslyn-language-server", "csharpier", "netcoredbg" },
				"Install the pinned C# toolchain"
			)
			install_command(
				"MasonJavaInstall",
				{ "jdtls", "java-debug-adapter", "java-test" },
				"Install the pinned Java toolchain"
			)
			install_command(
				"MasonKotlinInstall",
				{ "kotlin-lsp", "ktlint", "kotlin-debug-adapter" },
				"Install the pinned Kotlin toolchain"
			)
		end,
	},
	{
		"WhoIsSethDaniel/mason-tool-installer.nvim",
		cmd = {
			"MasonToolsClean",
			"MasonToolsInstall",
			"MasonToolsInstallSync",
			"MasonToolsUpdate",
			"MasonToolsUpdateSync",
		},
		-- No event/VeryLazy: tool installation is a manual, on-demand step
		-- (:MasonToolsInstall) rather than part of every startup, so a slow or
		-- offline network never blocks/backgrounds work at launch.
		dependencies = { "mason-org/mason.nvim" },
		opts = {
			ensure_installed = toolchain.packages,
			auto_update = false,
			run_on_start = false,
		},
	},
	{
		"neovim/nvim-lspconfig",
		event = { "BufReadPre", "BufNewFile" },
		dependencies = {
			"saghen/blink.cmp",
		},
		config = function()
			setup_lsp_keymaps()

			local capabilities = require("blink.cmp").get_lsp_capabilities()
			capabilities.textDocument.foldingRange = {
				dynamicRegistration = false,
				lineFoldingOnly = true,
			}

			vim.lsp.config("*", {
				capabilities = capabilities,
			})

			vim.lsp.config("asm_lsp", {
				filetypes = { "asm", "riscv", "vmasm" },
			})

			vim.lsp.config("clangd", {
				cmd = {
					"clangd",
					"--log=error",
					"--background-index",
					"--clang-tidy",
					"--completion-style=detailed",
					"--header-insertion=iwyu",
					"--header-insertion-decorators",
					"--fallback-style=llvm",
				},
				init_options = {
					clangdFileStatus = true,
					completeUnimported = true,
					usePlaceholders = true,
				},
			})

			vim.lsp.config("gopls", {
				settings = {
					gopls = {
						analyses = {
							nilness = true,
							shadow = true,
							unusedparams = true,
							unusedwrite = true,
						},
						gofumpt = true,
						staticcheck = true,
					},
				},
			})

			vim.lsp.config("lua_ls", {
				settings = {
					Lua = {
						completion = {
							callSnippet = "Replace",
						},
						diagnostics = {
							globals = { "vim", "Snacks", "MiniIcons" },
						},
						runtime = {
							version = "LuaJIT",
						},
						workspace = {
							checkThirdParty = false,
						},
					},
				},
			})

			vim.lsp.config("basedpyright", {
				settings = {
					basedpyright = {
						analysis = {
							autoImportCompletions = true,
						},
					},
				},
			})

			vim.lsp.config("ruff", {
				init_options = {
					settings = {
						lineLength = 100,
					},
				},
			})

			vim.lsp.config("typos_lsp", {
				-- Prose uses Neovim's spell checker. Restrict typos-lsp to code and
				-- structured data so the two systems do not duplicate diagnostics.
				filetypes = {
					"asm",
					"bash",
					"c",
					"cmake",
					"cpp",
					"cs",
					"css",
					"dockerfile",
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
					"lua",
					"make",
					"nasm",
					"python",
					"query",
					"riscv",
					"rust",
					"sh",
					"sql",
					"systemverilog",
					"toml",
					"typescript",
					"typescriptreact",
					"verilog",
					"vim",
					"vue",
					"yaml",
					"zsh",
				},
				init_options = {
					-- Surface typos quietly; they are hints, not errors.
					diagnosticSeverity = "Hint",
				},
			})

			vim.lsp.config("verible", {
				cmd = { "verible-verilog-ls", "--rules_config_search" },
				filetypes = { "systemverilog", "verilog" },
				root_markers = { ".git" },
			})

			local function vue_language_server_path()
				local executable = toolchain.executable("vue-language-server")
				local realpath = executable and (vim.uv.fs_realpath(executable) or executable)
				local package = realpath and vim.fs.dirname(vim.fs.dirname(vim.fs.normalize(realpath)))
				if package and vim.uv.fs_stat(vim.fs.joinpath(package, "package.json")) then
					return package
				end

				-- Windows Mason shims are regular .cmd files rather than symlinks, so
				-- their realpath cannot reveal the npm package directory.
				local mason_package = vim.fs.joinpath(
					vim.fn.stdpath("data"),
					"mason",
					"packages",
					"vue-language-server",
					"node_modules",
					"@vue",
					"language-server"
				)
				return vim.uv.fs_stat(vim.fs.joinpath(mason_package, "package.json")) and mason_package or nil
			end

			local vue_plugin = vue_language_server_path()
			local vtsls_filetypes = {
				"javascript",
				"javascriptreact",
				"typescript",
				"typescriptreact",
			}
			local vtsls_settings = {}
			if vue_plugin then
				table.insert(vtsls_filetypes, "vue")
				vtsls_settings.tsserver = {
					globalPlugins = {
						{
							name = "@vue/typescript-plugin",
							location = vue_plugin,
							languages = { "vue" },
							configNamespace = "typescript",
						},
					},
				}
			end
			vim.lsp.config("vtsls", {
				filetypes = vtsls_filetypes,
				settings = {
					vtsls = vtsls_settings,
				},
			})

			vim.lsp.config("jsonls", {
				settings = {
					json = {
						validate = { enable = true },
					},
				},
			})

			vim.lsp.config("yamlls", {
				settings = {
					yaml = {
						keyOrdering = false,
					},
				},
			})

			vim.lsp.config("tailwindcss", {
				filetypes = {
					"astro",
					"css",
					"html",
					"javascript",
					"javascriptreact",
					"typescript",
					"typescriptreact",
					"vue",
				},
			})

			-- nvim-lspconfig defaults use command names. Resolve each command to an
			-- absolute system-or-Mason path so Mason can keep PATH="skip".
			local server_requirements = {
				roslyn_ls = { "dotnet" },
			}
			local enabled_servers = {}
			for _, server in ipairs(servers) do
				if server ~= "jdtls" and server ~= "rust_analyzer" then
					local requirements_met = true
					for _, requirement in ipairs(server_requirements[server] or {}) do
						if not toolchain.executable(requirement) then
							requirements_met = false
							break
						end
					end
					local config = vim.lsp.config[server]
					local cmd = config and config.cmd
					if requirements_met and type(cmd) == "table" and type(cmd[1]) == "string" then
						local resolved = toolchain.executable(cmd[1])
						if resolved then
							cmd = vim.deepcopy(cmd)
							cmd[1] = resolved
							vim.lsp.config(server, { cmd = cmd })
							table.insert(enabled_servers, server)
						end
					elseif requirements_met and type(cmd) == "function" then
						table.insert(enabled_servers, server)
					end
				end
			end

			-- Enable only servers whose command already exists. This deliberately
			-- avoids mason-lspconfig.setup(), which refreshes the registry whenever
			-- LSP loads even with an empty ensure_installed list.
			vim.lsp.enable(enabled_servers)
		end,
	},
}
