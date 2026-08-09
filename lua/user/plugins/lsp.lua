local toolchain = require("user.toolchain")
local float_style = require("user.core.float_style")
local layout = require("user.core.layout")
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
				local _, winid = vim.lsp.buf.hover(float_style.padded())
				float_style.apply_padded(winid)
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
			-- Resolve Mason binaries per plugin instead of changing Neovim's global
			-- PATH (which would leak into every :terminal child process).
			PATH = "skip",
			ui = {
				border = layout.manager_border,
				width = layout.manager_scale,
				height = layout.manager_scale,
				backdrop = 60,
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

			local function node_lsp_command(name, args)
				local local_name = vim.fn.has("win32") == 1 and name .. ".cmd" or name
				return function(dispatchers, config)
					local command
					local root = (config or {}).root_dir
					if root then
						local candidate = vim.fs.joinpath(root, "node_modules", ".bin", local_name)
						if vim.fn.executable(candidate) == 1 then
							command = candidate
						end
					end
					command = command or toolchain.executable(name) or name
					return vim.lsp.rpc.start(vim.list_extend({ command }, args), dispatchers)
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

			vim.lsp.config("biome", {
				cmd = node_lsp_command("biome", { "lsp-proxy" }),
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
				cmd = node_lsp_command("tailwindcss-language-server", { "--stdio" }),
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
			local enabled_servers = {}
			for _, server in ipairs(servers) do
				local config = vim.lsp.config[server]
				local cmd = config and config.cmd
				if type(cmd) == "table" and type(cmd[1]) == "string" then
					local resolved = toolchain.executable(cmd[1])
					if resolved then
						cmd = vim.deepcopy(cmd)
						cmd[1] = resolved
						vim.lsp.config(server, { cmd = cmd })
						table.insert(enabled_servers, server)
					end
				elseif type(cmd) == "function" then
					table.insert(enabled_servers, server)
				end
			end

			-- Enable only servers whose command already exists. This deliberately
			-- avoids mason-lspconfig.setup(), which refreshes the registry whenever
			-- LSP loads even with an empty ensure_installed list.
			vim.lsp.enable(enabled_servers)
		end,
	},
}
