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

-- Formatters and linters only. LSP servers (incl. their CLIs like biome, ruff,
-- taplo, verible) are installed via mason-lspconfig's ensure_installed below, so
-- they must not be duplicated here.
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
			map("n", "gd", "<cmd>Glance definitions<cr>", "Peek definition")
			map("n", "gD", "<cmd>Glance declarations<cr>", "Peek declaration")
			map("n", "gi", "<cmd>Glance implementations<cr>", "Peek implementation")
			map("n", "gy", "<cmd>Glance type_definitions<cr>", "Peek type definition")
			map("n", "gr", "<cmd>Glance references<cr>", "Peek references")
			map("n", "<leader>ca", vim.lsp.buf.code_action, "Code action")
			map("n", "<leader>ci", "<cmd>FzfLua lsp_incoming_calls<cr>", "Incoming calls")
			map("n", "<leader>co", "<cmd>FzfLua lsp_outgoing_calls<cr>", "Outgoing calls")
			map("n", "<leader>cpD", "<cmd>Glance declarations<cr>", "Peek declaration")
			map("n", "<leader>cpd", "<cmd>Glance definitions<cr>", "Peek definition")
			map("n", "<leader>cpi", "<cmd>Glance implementations<cr>", "Peek implementation")
			map("n", "<leader>cpr", "<cmd>Glance references<cr>", "Peek references")
			map("n", "<leader>cpt", "<cmd>Glance type_definitions<cr>", "Peek type definition")
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
		"dnlhc/glance.nvim",
		cmd = "Glance",
		opts = function()
			local actions = require("glance").actions

			return {
				height = 18,
				preserve_win_context = true,
				detached = function(winid)
					return vim.api.nvim_win_get_width(winid) < 110
				end,
				border = {
					enable = false,
				},
				list = {
					position = "right",
					width = 0.34,
				},
				preview_win_opts = {
					cursorline = true,
					number = true,
					wrap = false,
				},
				theme = {
					enable = true,
					mode = "auto",
				},
				folds = {
					fold_closed = "",
					fold_open = "",
					folded = true,
				},
				mappings = {
					list = {
						["<Esc>"] = actions.close,
						q = actions.close,
						Q = actions.close,
					},
					preview = {
						["<Esc>"] = actions.close,
						q = actions.close,
						Q = actions.close,
					},
				},
			}
		end,
		config = function(_, opts)
			local glance = require("glance")

			glance.register_method({
				method = "textDocument/declaration",
				name = "declarations",
				label = "Declarations",
			})
			glance.setup(opts)

			-- Make the peek panels use the completion menu's Pmenu block colours.
			-- glance sets its groups with default = true, so these explicit
			-- overrides win; re-applied on every colorscheme switch.
			require("user.core.highlights").on_colorscheme(function()
				local palette = require("user.core.palette")
				local normal = vim.api.nvim_get_hl(0, { name = "Normal" })
				local pmenu_bg = vim.api.nvim_get_hl(0, { name = "Pmenu" }).bg
				local fg = normal.fg
				local dim = vim.api.nvim_get_hl(0, { name = "Comment" }).fg
				-- Two shades: the Pmenu block and a step toward the editor bg. Assign
				-- the darker to the preview and the lighter to the list, so the preview
				-- is reliably the darker panel whichever way the theme's Pmenu leans
				-- (gruvbox's Pmenu is lighter than the editor, tokyonight/catppuccin's
				-- darker -- this picks correctly for each instead of a fixed order).
				local function lum(c)
					return 0.299 * (math.floor(c / 65536) % 256)
						+ 0.587 * (math.floor(c / 256) % 256)
						+ 0.114 * (c % 256)
				end
				local a, b = pmenu_bg, palette.blend(pmenu_bg, normal.bg, 0.5)
				local list_bg, preview_bg = a, b
				if lum(a) < lum(b) then
					list_bg, preview_bg = b, a
				end
				vim.api.nvim_set_hl(0, "GlanceListNormal", { fg = fg, bg = list_bg })
				vim.api.nvim_set_hl(0, "GlancePreviewNormal", { fg = fg, bg = preview_bg })
				vim.api.nvim_set_hl(0, "GlanceListCursorLine", { link = "PmenuSel" })
				vim.api.nvim_set_hl(0, "GlancePreviewCursorLine", { link = "PmenuSel" })
				vim.api.nvim_set_hl(0, "GlanceListEndOfBuffer", { fg = list_bg, bg = list_bg })
				vim.api.nvim_set_hl(0, "GlancePreviewEndOfBuffer", { fg = preview_bg, bg = preview_bg })
				vim.api.nvim_set_hl(0, "GlanceWinBarFilename", { fg = fg, bg = list_bg, bold = true })
				vim.api.nvim_set_hl(0, "GlanceWinBarFilepath", { fg = dim, bg = list_bg })
				vim.api.nvim_set_hl(0, "GlanceWinBarTitle", { fg = fg, bg = list_bg, bold = true })
			end)
		end,
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
		event = "VeryLazy",
		dependencies = { "mason-org/mason.nvim" },
		opts = {
			ensure_installed = tools,
			auto_update = false,
			run_on_start = true,
			start_delay = 3000,
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
			-- doesn't expose an option for -- so wrap it and set it on the window.
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

			vim.lsp.config("bashls", {
				filetypes = { "bash", "sh", "zsh" },
			})

			vim.lsp.config("clangd", {
				cmd = {
					"clangd",
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
					python = {
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
				-- rust_analyzer is enabled by rustaceanvim, not here, to avoid a
				-- duplicate client. mason still installs it via ensure_installed.
				automatic_enable = vim.tbl_filter(function(name)
					return name ~= "rust_analyzer"
				end, servers),
			})
		end,
	},
}
