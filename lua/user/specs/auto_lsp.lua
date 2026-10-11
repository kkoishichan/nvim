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
				-- Opaque: two fills tell the peek apart. Transparent: there is no
				-- fill, so lines mark its extent instead. Glance reads this option
				-- on every open; the highlight owner below keeps it in step.
				border = {
					enable = require("user.core.transparency").is_enabled(),
					top_char = "─",
					bottom_char = "─",
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
			-- A statuscolumn stops at the last result. A native left border
			-- also covers the winbar and empty rows, without per-row callbacks.
			local function update_separator()
				if not require("user.core.transparency").is_enabled() then
					return
				end
				for _, winid in ipairs(vim.api.nvim_list_wins()) do
					local bufnr = vim.api.nvim_win_get_buf(winid)
					local config = vim.api.nvim_win_get_config(winid)
					local border = config.border
					if vim.bo[bufnr].filetype == "Glance" and type(border) == "table" and border[8] == "" then
						border[1] = { "┬", "GlanceListSeparator" }
						border[7] = { "┴", "GlanceListSeparator" }
						border[8] = { "│", "GlanceListSeparator" }
						-- Reserve one column inside the existing footprint.
						vim.api.nvim_win_set_config(winid, { border = border, width = math.max(1, config.width - 1) })
					end
				end
			end
			local group = vim.api.nvim_create_augroup("user_glance_separator", { clear = true })
			vim.api.nvim_create_autocmd("FileType", {
				group = group,
				pattern = "Glance",
				callback = function()
					-- Includes :Glance resume, which bypasses before_open hooks.
					vim.schedule(update_separator)
				end,
			})
			vim.api.nvim_create_autocmd("WinResized", {
				group = group,
				-- Glance recomputes its borders and width when its parent resizes.
				callback = update_separator,
			})
			-- The peek is an overlay inside the editor. Opaque: two shades (list
			-- raised, preview on the editor colour), no lines. Transparent: no
			-- fill, lines mark its extent. Glance defines its groups with
			-- default = true, so these win; the chain re-applies them on every
			-- colorscheme and transparency toggle, and flips the line option
			-- with them so neither state leaks into the other.
			require("user.core.highlights").on_colorscheme("glance", function()
				local p = require("user.core.palette").get()
				local opaque = p.surface ~= nil
				local ok, glance_config = pcall(require, "glance.config")
				if ok and type(glance_config.options) == "table" and type(glance_config.options.border) == "table" then
					glance_config.options.border.enable = not opaque
				end
				local list_bg = opaque and p.raised or nil
				local preview_bg = opaque and p.bg or nil
				vim.api.nvim_set_hl(0, "GlanceListNormal", { fg = p.fg, bg = list_bg })
				vim.api.nvim_set_hl(0, "GlancePreviewNormal", { fg = p.fg, bg = preview_bg })
				vim.api.nvim_set_hl(0, "GlanceListCursorLine", { link = "PmenuSel" })
				vim.api.nvim_set_hl(0, "GlancePreviewCursorLine", { link = "PmenuSel" })
				vim.api.nvim_set_hl(0, "GlanceListEndOfBuffer", { fg = list_bg or p.bg, bg = list_bg })
				vim.api.nvim_set_hl(0, "GlancePreviewEndOfBuffer", { fg = preview_bg or p.bg, bg = preview_bg })
				vim.api.nvim_set_hl(0, "GlanceWinBarFilename", { fg = p.fg, bg = list_bg, bold = true })
				vim.api.nvim_set_hl(0, "GlanceWinBarFilepath", { fg = p.muted, bg = list_bg })
				vim.api.nvim_set_hl(0, "GlanceWinBarTitle", { fg = p.fg, bg = list_bg, bold = true })
				vim.api.nvim_set_hl(0, "GlanceListSeparator", { fg = p.line, bg = list_bg })
				vim.api.nvim_set_hl(0, "GlanceBorderTop", { fg = p.line, bg = list_bg })
				vim.api.nvim_set_hl(0, "GlanceListBorderBottom", { fg = p.line, bg = list_bg })
				vim.api.nvim_set_hl(0, "GlancePreviewBorderBottom", { fg = p.line, bg = preview_bg })
			end)
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
				backdrop = layout.backdrop_blend,
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
