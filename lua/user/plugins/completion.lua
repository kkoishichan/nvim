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
				preset = "enter",
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
				},
			},
			signature = {
				enabled = true,
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
		config = function(_, opts)
			-- With a "padded" menu, blink puts the scrollbar at `width + 1` -- the
			-- exact column the documentation window's left edge lands on -- so they
			-- overlap. Nudge only the menu's scrollbar one column left (into the
			-- menu's right padding) to clear it; the docs' own scrollbar is untouched.
			local ok_geo, geo = pcall(require, "blink.cmp.lib.window.scrollbar.geometry")
			if ok_geo then
				local get_geometry = geo.get_geometry
				geo.get_geometry = function(target_win)
					local g = get_geometry(target_win)
					local ok_menu, menu = pcall(require, "blink.cmp.completion.windows.menu")
					if ok_menu and menu.win and menu.win:get_win() == target_win then
						if g.thumb then
							g.thumb.col = g.thumb.col - 1
						end
						if g.gutter then
							g.gutter.col = g.gutter.col - 1
						end
					end
					return g
				end
			end
			require("blink.cmp").setup(opts)
		end,
	},
}
