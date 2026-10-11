local toolchain = require("user.toolchain")
local layout = require("user.core.layout")

local function client_supports(client, method, bufnr)
	if not client or not client.supports_method then
		return false
	end
	return client:supports_method(method, bufnr)
end

local function setup_lsp_keymaps()
	local capabilities = require("user.core.mode").capabilities()
	vim.api.nvim_create_autocmd("LspAttach", {
		group = vim.api.nvim_create_augroup("user_lsp_attach", { clear = true }),
		callback = function(event)
			local bufnr = event.buf
			local client = vim.lsp.get_client_by_id(event.data.client_id)
			local map = function(mode, lhs, rhs, desc)
				vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, desc = desc })
			end

			map("n", "K", vim.lsp.buf.hover, "Hover")
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

			local allowed = require("user.core.buffer_policy").allow(bufnr)
			if allowed and client_supports(client, "textDocument/codeLens", bufnr) then
				if capabilities.codelens then
					vim.lsp.codelens.enable(true, { bufnr = bufnr })
					map("n", "<leader>cL", vim.lsp.codelens.run, "Run code lens")
				else
					-- The explicit twin of automatic code lenses: show them for
					-- this buffer on request, run one on the next press.
					map("n", "<leader>cL", function()
						if vim.lsp.codelens.is_enabled({ bufnr = bufnr }) then
							vim.lsp.codelens.run()
						else
							vim.lsp.codelens.enable(true, { bufnr = bufnr })
							vim.notify(
								"Code lenses shown for this buffer; press again to run one",
								vim.log.levels.INFO,
								{ title = "Code lens" }
							)
						end
					end, "Show or run code lens")
				end
			end
			if client_supports(client, "textDocument/inlayHint", bufnr) then
				if capabilities.inlay_hints_auto and allowed then
					vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
				end
				map("n", "<leader>uh", function()
					vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = bufnr }), { bufnr = bufnr })
				end, "Toggle inlay hints")
			end
		end,
	})
end

return function(profile)
	profile = profile or {}
	local plugins = {}
	table.insert(plugins, {
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
	})
	if profile.extra then
		table.insert(plugins, {
			"kosayoda/nvim-lightbulb",
			event = "LspAttach",
			opts = {
				-- The plugin otherwise overwrites the global updatetime with its
				-- own 200 ms default on first attach.
				autocmd = { enabled = true, updatetime = -1 },
				sign = { enabled = true, text = require("user.core.icons").code_action, hl = "DiagnosticSignHint" },
				virtual_text = { enabled = false },
				float = { enabled = false },
				status_text = { enabled = false },
			},
		})
	end
	table.insert(plugins, {
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
		end,
	})
	table.insert(plugins, {
		"mason-org/mason.nvim",
		cmd = { "Mason", "MasonInstall", "MasonLog", "MasonUninstall", "MasonUninstallAll", "MasonUpdate" },
		config = function(_, opts)
			require("mason").setup(opts)
			toolchain.watch_mason()
		end,
		opts = {
			-- Resolve Mason binaries per plugin instead of changing Neovim's global
			-- PATH (which would leak into every :terminal child process).
			PATH = "skip",
			ui = {
				border = layout.manager_border,
				width = layout.float_scale,
				height = layout.float_scale,
				backdrop = layout.backdrop() or 100,
			},
		},
	})
	table.insert(plugins, {
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
	})
	table.insert(plugins, {
		"neovim/nvim-lspconfig",
		event = { "BufReadPre", "BufNewFile" },
		dependencies = {
			"saghen/blink.cmp",
		},
		config = function()
			setup_lsp_keymaps()

			local definitions = require("user.core.lsp_definitions")
			local capabilities = require("blink.cmp").get_lsp_capabilities()
			capabilities.textDocument.foldingRange = {
				dynamicRegistration = false,
				lineFoldingOnly = true,
			}
			definitions.configure({ capabilities = capabilities })

			local function refresh_servers()
				-- Enable newly installed servers without restarting any running
				-- client; the root and on_init guards are installed only once.
				vim.lsp.enable(definitions.resolve({ automatic = true }))
			end
			vim.api.nvim_create_autocmd("User", {
				group = vim.api.nvim_create_augroup("user_lsp_tools", { clear = true }),
				pattern = "UserToolsChanged",
				callback = refresh_servers,
			})
			refresh_servers()
		end,
	})
	return plugins
end
