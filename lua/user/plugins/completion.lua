local signature_highlight = require("user.core.signature_highlight")

local function close_full_signature()
	local signature_helper = package.loaded["lsp_signature.helper"]
	if not signature_helper then
		return false
	end

	-- lsp_signature.toggle_float_win() also clears the virtual-text namespace.
	-- Close only the full float so the lightweight active-parameter hint remains.
	local windows = vim.api.nvim_list_wins()
	signature_helper.close_float_win(true)
	for _, window in ipairs(windows) do
		if not vim.api.nvim_win_is_valid(window) then
			signature_highlight.stop_float(vim.api.nvim_get_current_buf())
			return true
		end
	end
	return false
end

return {
	{
		"saghen/blink.cmp",
		version = "1.*",
		event = { "InsertEnter", "CmdlineEnter" },
		dependencies = {
			"rafamadriz/friendly-snippets",
		},
		opts = {
			keymap = {
				-- IDE-style completion: Tab accepts the selected (or first) item,
				-- then advances through snippet placeholders. Enter only accepts an
				-- explicitly selected item, so an untouched menu cannot steal a
				-- newline. Escape dismisses the menu before leaving Insert mode.
				preset = "super-tab",
				["<CR>"] = { "accept", "fallback" },
				["<Esc>"] = { "cancel", "fallback" },
				-- lsp_signature.nvim owns signature help and its C-k mapping.
				["<C-k>"] = false,
			},
			appearance = {
				nerd_font_variant = "mono",
			},
			completion = {
				documentation = {
					auto_show = true,
					auto_show_delay_ms = 300,
					window = {
						-- "padded" = inner padding, no border lines. Paired with a
						-- lifted Pmenu background (see ui_highlights) this reads as a
						-- clean background block instead of a framed float.
						border = "padded",
					},
				},
				ghost_text = {
					enabled = true,
				},
				list = {
					selection = {
						preselect = false,
					},
				},
				menu = {
					border = "padded",
					-- Blink places the scrollbar in the padded border column, where it
					-- can collide with the documentation window. Its public switch is
					-- preferable to patching private geometry modules.
					scrollbar = false,
				},
			},
			signature = {
				-- Dedicated signature UI is provided by lsp_signature.nvim below.
				enabled = false,
			},
			cmdline = {
				completion = {
					-- Pop the candidate menu automatically while typing `:`, like
					-- wildmenu. Border comes from the global completion.menu ("padded").
					menu = { auto_show = true },
				},
			},
			sources = {
				default = { "lazydev", "lsp", "path", "snippets", "buffer" },
				providers = {
					-- Lua dev: completes vim.uv/require paths via lazydev, ahead of
					-- the LSP source so it isn't duplicated.
					lazydev = {
						name = "LazyDev",
						module = "lazydev.integrations.blink",
						score_offset = 100,
					},
				},
			},
			fuzzy = {
				implementation = "prefer_rust_with_warning",
			},
		},
		opts_extend = { "sources.default" },
	},
	{
		"ray-x/lsp_signature.nvim",
		event = "InsertEnter",
		init = function()
			signature_highlight.setup()
			vim.api.nvim_create_autocmd("User", {
				group = vim.api.nvim_create_augroup("user_signature_completion", { clear = true }),
				pattern = "BlinkCmpShow",
				desc = "Close signature help when completion opens",
				callback = function()
					close_full_signature()
				end,
			})
		end,
		keys = {
			{
				"<C-k>",
				function()
					if close_full_signature() then
						return
					end

					local source_buffer = vim.api.nvim_get_current_buf()
					local function toggle_signature()
						require("lsp_signature").toggle_float_win()
						signature_highlight.request_float(source_buffer)
					end

					local cmp = require("blink.cmp")
					if cmp.is_menu_visible() then
						cmp.hide({ callback = toggle_signature })
					else
						toggle_signature()
					end
				end,
				mode = { "i", "s" },
				desc = "Toggle signature help",
			},
		},
		opts = {
			bind = true,
			-- A Tree-sitter renderer consumes status_line() for the virtual hint;
			-- lsp_signature's built-in hint only supports one colour for all tokens.
			floating_window = false,
			hint_enable = false,
			hi_parameter = "LspSignatureActiveParameter",
			doc_lines = 0,
			max_width = function()
				return math.min(100, math.max(40, math.floor(vim.api.nvim_win_get_width(0) * 0.72)))
			end,
			-- Full signature help is manual, so prefer the unobstructed side above
			-- the cursor. Completion opening later closes it via BlinkCmpShow.
			floating_window_above_cur_line = true,
			handler_opts = {
				border = require("user.core.float_style").border(),
			},
		},
	},
}
