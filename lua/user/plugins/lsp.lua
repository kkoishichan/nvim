local toolchain = require("user.toolchain")
local float_style = require("user.core.float_style")
local layout = require("user.core.layout")

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
				border = float_style.is_enabled() and { enable = false } or nil,
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

			if not float_style.is_enabled() then
				return
			end
			-- Make the peek panels use the completion menu's Pmenu block colours.
			-- glance sets its groups with default = true, so these explicit
			-- overrides win; re-applied on every colorscheme switch.
			require("user.core.highlights").on_colorscheme("glance", function()
				local palette = require("user.core.palette")
				local normal = vim.api.nvim_get_hl(0, { name = "Normal" })
				local pmenu_bg = vim.api.nvim_get_hl(0, { name = "Pmenu" }).bg
				local fg = normal.fg
				local dim = vim.api.nvim_get_hl(0, { name = "Comment" }).fg
				-- Two shades: the Pmenu block and a step toward the editor bg. Assign
				-- the darker to the preview and the lighter to the list, so the preview
				-- is reliably the darker panel whichever way the theme's Pmenu leans
				-- (gruvbox's Pmenu is lighter than the editor, tokyonight/catppuccin/vscode's
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
				vim.lsp.enable(definitions.resolve())
			end
			vim.api.nvim_create_autocmd("User", {
				group = vim.api.nvim_create_augroup("user_lsp_tools", { clear = true }),
				pattern = "UserToolsChanged",
				callback = refresh_servers,
			})
			refresh_servers()
		end,
	},
}
