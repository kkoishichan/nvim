local blink_signature = require("user.core.blink_signature")

local function dismiss_popups(cmp)
	return require("user.core.popups").close({ blink = cmp })
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
				["<Esc>"] = { dismiss_popups, "cancel", "fallback" },
				["<C-k>"] = { blink_signature.toggle, "fallback" },
				["<C-b>"] = { "scroll_signature_up", "scroll_documentation_up", "fallback" },
				["<C-f>"] = { "scroll_signature_down", "scroll_documentation_down", "fallback" },
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
				enabled = true,
				-- Show the selected overload as virtual text; C-k toggles the full popup.
				trigger = {
					enabled = true,
					-- Also ask once when Insert mode starts inside an existing call.
					show_on_insert = true,
				},
				window = {
					border = "padded",
					max_height = blink_signature.compact_height,
				},
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
		config = function(_, opts)
			require("blink.cmp").setup(opts)
			blink_signature.setup()
		end,
	},
}
