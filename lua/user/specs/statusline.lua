local function pdf_page()
	if not require("user.core.mode").capabilities().render then
		return ""
	end
	return require("user.core.pdf").page()
end

local function has_pdf_status()
	return pdf_page() ~= ""
end

local function not_pdf_status()
	return not has_pdf_status()
end

local function pdf_zoom()
	return require("user.core.pdf").zoom()
end

local function not_dashboard()
	return vim.bo.filetype ~= "snacks_dashboard"
end

return function()
	local capabilities = require("user.core.mode").capabilities()
	local icons = require("user.core.icons")
	return {
		{
			"nvim-lualine/lualine.nvim",
			event = "VeryLazy",
			ft = "pdf",
			dependencies = capabilities.icons and { "nvim-mini/mini.icons" } or nil,
			opts = {
				options = {
					theme = "auto",
					globalstatus = true,
					icons_enabled = capabilities.icons,
					component_separators = "",
					section_separators = "",
				},
				sections = {
					lualine_a = {
						"mode",
					},
					lualine_b = capabilities.git and {
						"branch",
						{
							"diff",
							symbols = {
								added = icons.git.added,
								modified = icons.git.changed,
								removed = icons.git.removed,
							},
						},
					} or {},
					lualine_c = {
						{ "filename", path = 1, cond = not_dashboard },
					},
					lualine_x = {
						{
							function()
								local quiet = package.loaded["user.core.quiet"]
								return quiet and quiet.active() and "QUIET" or ""
							end,
						},
						{
							-- Project-wide counts, shown only while servers analyse the
							-- whole workspace; the next component keeps the buffer's own.
							"diagnostics",
							sources = { "nvim_workspace_diagnostic" },
							sections = { "error", "warn" },
							update_in_insert = false,
							symbols = icons.diagnostic_symbols(),
							fmt = function(text)
								return text ~= "" and ("ws " .. text) or ""
							end,
							cond = function()
								return require("user.core.mode").capabilities().workspace_diagnostics
							end,
						},
						{
							"diagnostics",
							sources = { "nvim_diagnostic" },
							symbols = icons.diagnostic_symbols(),
							update_in_insert = false,
						},
						{
							"lsp_status",
							ignore_lsp = { "null-ls" },
							symbols = not capabilities.icons and { spinner = { "." }, done = "", separator = " " }
								or nil,
						},
						{
							"filetype",
							icon_only = false,
							cond = not_dashboard,
						},
					},
					lualine_y = {
						{
							"progress",
							cond = not_pdf_status,
						},
						{
							pdf_zoom,
							cond = has_pdf_status,
						},
					},
					lualine_z = {
						{
							"location",
							cond = not_pdf_status,
						},
						{
							pdf_page,
							cond = has_pdf_status,
						},
					},
				},
			},
			config = function(_, opts)
				local lualine = require("lualine")
				lualine.setup(opts)
				-- Zero repairs can mean the locked bug is gone upstream, so this
				-- entry is informational rather than a degradation.
				local repaired = require("user.core.statusline_refresh").setup()
				require("user.core.adapters").record(
					"statusline_refresh",
					repaired > 0,
					repaired > 0 and ("repaired " .. repaired .. " lualine registrations")
						or "no recognised lualine registration to repair",
					{ quiet = true }
				)
			end,
		},
	}
end
