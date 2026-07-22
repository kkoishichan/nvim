local servers = {
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
	"lua_ls",
	"marksman",
	"neocmake",
	"ruff",
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

-- Formatters, linters, and auxiliary packages only. LSP servers (incl. their
-- CLIs like biome, jdtls, ruff, taplo, and verible) are installed through
-- mason-lspconfig below, so they must not be duplicated here.
local tools = {
	"asmfmt",
	"checkmake",
	"clang-format",
	"cmakelang",
	"cmakelint",
	"gofumpt",
	"goimports",
	"golangci-lint",
	"hadolint",
	"java-debug-adapter",
	"java-test",
	"latexindent",
	"markdownlint-cli2",
	"prettier",
	"selene",
	"shellcheck",
	"shfmt",
	"sqruff",
	"stylelint",
	"stylua",
	"typstyle",
	"yamllint",
}

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
			ui = {
				border = "rounded",
			},
		},
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
			ensure_installed = tools,
			auto_update = false,
			run_on_start = false,
		},
	},
	{
		"neovim/nvim-lspconfig",
		event = { "BufReadPre", "BufNewFile" },
		dependencies = {
			"saghen/blink.cmp",
			"mason-org/mason.nvim",
			"mason-org/mason-lspconfig.nvim",
		},
		config = function()
			setup_lsp_keymaps()

			-- Style LSP floating previews (hover, etc.) as borderless background
			-- blocks, matching the completion docs: a space "border" for padding
			-- (no lines) plus a Pmenu bg via winhighlight, which open_floating_preview
			-- doesn't expose an option for -- so wrap the (public) API and set it on
			-- the window. Guarded by a global flag so re-running this config (e.g.
			-- :Lazy reload) wraps exactly once instead of stacking wrappers, which
			-- would otherwise compound the padding on every reload.
			if not vim.g.user_lsp_preview_patched then
				vim.g.user_lsp_preview_patched = true
				local orig_preview = vim.lsp.util.open_floating_preview
				-- Left/right padding only (no lines, no top/bottom rows), like blink's
				-- "padded" border.
				local pad = { " ", "", "", " ", "", "", " ", " " }
				function vim.lsp.util.open_floating_preview(contents, syntax, opts, ...)
					opts = opts or {}
					if opts.border == nil then
						opts.border = pad
					end
					local bufnr, winid = orig_preview(contents, syntax, opts, ...)
					if winid and vim.api.nvim_win_is_valid(winid) then
						vim.wo[winid].winhighlight = "Normal:Pmenu,NormalFloat:Pmenu,FloatBorder:Pmenu"
					end
					return bufnr, winid
				end
			end

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

			local vue_language_server_path = vim.fn.stdpath("data")
				.. "/mason/packages/vue-language-server/node_modules/@vue/language-server"
			vim.lsp.config("vtsls", {
				filetypes = {
					"javascript",
					"javascriptreact",
					"typescript",
					"typescriptreact",
					"vue",
				},
				settings = {
					vtsls = {
						tsserver = {
							globalPlugins = {
								{
									name = "@vue/typescript-plugin",
									location = vue_language_server_path,
									languages = { "vue" },
									configNamespace = "typescript",
								},
							},
						},
					},
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

			require("mason-lspconfig").setup({
				ensure_installed = servers,
				-- Dedicated plugins manage these servers; Mason still installs them
				-- through ensure_installed, but automatic_enable must not create a
				-- duplicate client.
				automatic_enable = vim.tbl_filter(function(name)
					return name ~= "jdtls" and name ~= "rust_analyzer"
				end, servers),
			})
		end,
	},
}
