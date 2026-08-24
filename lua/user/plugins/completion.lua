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
				["<C-k>"] = { "show_signature", "hide_signature", "fallback" },
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
				-- Large overload lists can cover the implementation. Keep signature
				-- help available on demand through C-k without opening it on `(`/`,`.
				trigger = { enabled = false },
				window = {
					border = "padded",
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
	},
}
