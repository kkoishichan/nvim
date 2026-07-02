local disabled_filetypes = {
	["fzflua_backdrop"] = true,
	["neo-tree"] = true,
	["snacks_picker_input"] = true,
	["snacks_picker_list"] = true,
	["snacks_notif"] = true,
	["TelescopePrompt"] = true,
	["fzf"] = true,
	["qf"] = true,
}

return {
	{
		"kevinhwang91/nvim-ufo",
		event = { "BufReadPost", "BufNewFile" },
		dependencies = {
			"kevinhwang91/promise-async",
		},
		opts = {
			open_fold_hl_timeout = 150,
			close_fold_current_line_for_ft = {
				default = false,
			},
			preview = {
				win_config = {
					border = "rounded",
					winblend = 0,
					winhighlight = "Normal:Normal,FloatBorder:FloatBorder,CursorLine:Visual",
					maxheight = 20,
				},
				mappings = {
					scrollU = "<C-u>",
					scrollD = "<C-d>",
					jumpTop = "[",
					jumpBot = "]",
					close = "q",
					switch = "<Tab>",
					trace = "<CR>",
				},
			},
			provider_selector = function(bufnr, filetype, buftype)
				if buftype ~= "" or vim.b[bufnr].bigfile or disabled_filetypes[filetype] then
					return ""
				end

				-- LSP folds by the language's logical regions and keeps the closing
				-- brace as a structural anchor (IDE convention); treesitter fills in
				-- until the server attaches or where it has no folding support.
				--
				-- Returning a custom function (rather than { "lsp", "treesitter" })
				-- so we can catch UfoFallbackException at every stage and add a
				-- never-throwing `indent` terminal. ufo's built-in two-slot chain
				-- has no catch after the fallback: when the fallback provider itself
				-- throws (e.g. an oil/acwrite buffer that has neither LSP folding
				-- nor a treesitter parser), the throw escapes as an unhandled
				-- promise rejection. This chain resolves to indent folds instead.
				return function()
					local ufo = require("ufo")
					local function fallback(err, next_provider)
						if type(err) == "string" and err:match("UfoFallbackException") then
							return ufo.getFolds(bufnr, next_provider)
						end
						return require("promise").reject(err)
					end
					return ufo.getFolds(bufnr, "lsp")
						:catch(function(err)
							return fallback(err, "treesitter")
						end)
						:catch(function(err)
							return fallback(err, "indent")
						end)
				end
			end,
		},
		keys = {
			{
				"zR",
				function()
					require("ufo").openAllFolds()
				end,
				desc = "Open all folds",
			},
			{
				"zM",
				function()
					require("ufo").closeAllFolds()
				end,
				desc = "Close all folds",
			},
			{
				"zr",
				function()
					require("ufo").openFoldsExceptKinds()
				end,
				desc = "Open folds",
			},
			{
				"zm",
				function()
					require("ufo").closeFoldsWith()
				end,
				desc = "Close folds",
			},
			{
				"zK",
				function()
					local winid = require("ufo").peekFoldedLinesUnderCursor()
					if not winid then
						vim.notify("No fold under cursor", vim.log.levels.INFO)
					end
				end,
				desc = "Peek fold",
			},
		},
		config = function(_, opts)
			require("ufo").setup(opts)
			require("user.core.highlights").on_colorscheme(function()
				local p = require("user.core.palette").get()
				vim.api.nvim_set_hl(0, "UfoFoldedEllipsis", { fg = p.gray })
				vim.api.nvim_set_hl(0, "UfoCursorFoldedLine", { bg = p.subtle })
			end)
		end,
	},
}
