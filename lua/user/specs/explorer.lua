-- Oil, the directory-as-a-buffer explorer both modes share. Fast mode keeps the
-- editing confirmation and the muted auxiliary text, and drops the parts that
-- keep working after the listing is drawn: the change watcher, icon lookups and
-- the permission/size/mtime columns. Deletion still goes to the trash, so a
-- trash directory that cannot be written reports a failure instead of quietly
-- becoming a permanent delete.
local mode = require("user.core.mode")

return function()
	local capabilities = mode.capabilities()
	local extras = capabilities.explorer_extras
	return {
		{
			"stevearc/oil.nvim",
			cmd = "Oil",
			event = {
				"BufReadCmd oil://*",
				"BufReadCmd oil-ssh://*",
				"BufReadCmd oil-trash://*",
				"BufReadCmd oil-s3://*",
			},
			init = function()
				require("user.core.oil_registration").setup()
			end,
			keys = {
				{
					"<leader>E",
					function()
						require("oil").open(vim.fn.getcwd())
					end,
					desc = "Edit project directory",
				},
				{
					"-",
					function()
						require("oil").open()
					end,
					desc = "Edit current directory",
				},
			},
			dependencies = extras and { "nvim-mini/mini.icons" } or {},
			opts = {
				default_file_explorer = true,
				delete_to_trash = true,
				skip_confirm_for_simple_edits = false,
				watch_for_changes = extras,
				keymaps = {
					["<Esc>"] = {
						callback = function()
							if vim.api.nvim_win_get_config(0).relative ~= "" then
								require("oil").close()
								return
							end
							require("user.core.popups").close()
							vim.cmd.nohlsearch()
						end,
						desc = "Close floating Oil / dismiss popups",
						mode = "n",
					},
				},
				columns = extras and { "icon", "permissions", "size", "mtime" } or {},
				float = {
					border = "rounded",
					max_width = 0.86,
					max_height = 0.86,
				},
				view_options = {
					show_hidden = true,
					natural_order = true,
					is_always_hidden = function(name)
						return name == ".git" or name == ".jj"
					end,
				},
			},
			config = function(_, opts)
				require("oil").setup(opts)
				require("user.core.highlights").on_colorscheme("oil", function()
					local palette = require("user.core.palette")
					local p = palette.get()
					-- Auxiliary file information should be quiet UI text, not inherit
					-- the active theme's syntax comment colour (green in VS Code).
					local muted = palette.blend(p.fg, p.bg, 0.60)
					for _, group in ipairs({ "OilEmpty", "OilHidden", "OilLinkTarget", "OilTrashSourcePath" }) do
						vim.api.nvim_set_hl(0, group, { fg = muted })
					end
				end)
			end,
		},
	}
end
