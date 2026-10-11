local function dismiss_popups(cmp)
	require("user.core.popups").close({ blink = cmp })
end

local function cycle_overload()
	return require("user.core.signature_overloads").cycle(1)
end

local function reserve_for_input_method()
	-- The desktop input method handles this first; consume the copy that reaches
	-- Neovim so it neither opens Blink nor invokes Insert-mode <C-@>.
	return true
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
			enabled = function()
				return require("user.core.buffer_policy").allow(0)
			end,
			keymap = {
				-- IDE-style completion: Tab accepts the selected (or first) item,
				-- then advances through snippet placeholders. Enter only accepts an
				-- explicitly selected item, so an untouched menu cannot steal a
				-- newline. Escape dismisses every popup and leaves Insert mode in the
				-- same keypress; the callback deliberately falls through afterward.
				preset = "super-tab",
				["<C-Space>"] = { reserve_for_input_method },
				["<M-Space>"] = { "show", "show_documentation", "hide_documentation" },
				["<CR>"] = { "accept", "fallback" },
				["<Esc>"] = { dismiss_popups, "fallback" },
				["<C-k>"] = { "show_signature", "hide_signature", "fallback" },
				["<C-s>"] = { cycle_overload, "fallback" },
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
				},
				ghost_text = {
					enabled = true,
				},
				list = {
					selection = {
						preselect = false,
					},
				},
			},
			signature = {
				enabled = true,
				-- Blink owns requests, parameter offsets and popup positioning;
				-- user.core.signature_overloads renders one overload at a time.
				trigger = {
					-- Also ask once when Insert mode starts inside an existing call.
					show_on_insert = true,
				},
				window = {
					max_height = 6,
				},
			},
			cmdline = {
				keymap = {
					preset = "cmdline",
					["<C-Space>"] = { reserve_for_input_method },
				},
				completion = {
					-- Pop the candidate menu automatically while typing `:`, like
					-- wildmenu. Border follows the global completion.menu style.
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
			require("user.core.adapters").run("signature_overloads", function()
				return require("user.core.signature_overloads").setup()
			end)
		end,
	},
}
