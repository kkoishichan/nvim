-- fzf-lua, the file and text search both modes share. It loads on its keys in
-- either mode, so search processes only exist while a picker is open. Fast mode
-- additionally drops icon lookups and leaves the preview closed.
local float_style = require("user.core.float_style")
local mode = require("user.core.mode")

-- Every picker entry goes through here, so a host that never installed fzf
-- falls back to the native open, completion and quickfix search entries instead
-- of loading a picker whose process cannot start.
local function fzf()
	local native = require("user.core.native_search")
	if not native.usable() then
		return native
	end
	return require("fzf-lua")
end

local function workspace_opts(opts)
	return vim.tbl_extend("keep", opts or {}, { cwd = require("user.core.project").root() })
end

return function()
	local capabilities = mode.capabilities()
	local extras = capabilities.picker_extras
	local spec = {
		{
			"ibhagwan/fzf-lua",
			cmd = "FzfLua",
			dependencies = extras and { "nvim-mini/mini.icons" } or {},
			-- Route vim.ui.select (code actions, etc.) through fzf-lua, lazily: the
			-- first select call loads fzf-lua, which then replaces vim.ui.select.
			init = function()
				if not require("user.core.native_search").usable() then
					-- Keep Neovim's own prompt rather than routing selections into
					-- a picker whose process cannot start on this host.
					return
				end
				local fallback = vim.ui.select
				local wrapper
				wrapper = function(...)
					-- Loading fzf-lua runs its config, which calls register_ui_select()
					-- and replaces vim.ui.select; then dispatch to the real one.
					local ok = pcall(function()
						require("lazy").load({ plugins = { "fzf-lua" } })
					end)
					if ok and vim.ui.select ~= wrapper then
						return vim.ui.select(...)
					end
					return fallback(...)
				end
				vim.ui.select = wrapper
			end,
			config = function(_, opts)
				local fzf_lua = require("fzf-lua")
				fzf_lua.setup(opts)
				-- Size vim.ui.select to its contents so a 2-3 option prompt (code
				-- actions, theme picker, ...) isn't a huge mostly-empty window.
				fzf_lua.register_ui_select(function(ui_opts, items)
					local height = math.min(math.max(#items + 4, 6), math.floor(vim.o.lines * 0.8))
					local width = vim.fn.strdisplaywidth(ui_opts.prompt or "Select one of:")
					for _, item in ipairs(items) do
						local label = ui_opts.format_item and ui_opts.format_item(item) or tostring(item)
						width = math.max(width, vim.fn.strdisplaywidth(label))
					end
					width = math.min(math.max(width + 8, 30), math.floor(vim.o.columns * 0.8))
					return {
						fzf_opts = {
							-- The scrollbar owns fzf's last terminal cell even when all
							-- choices fit, which makes the right padding look one cell wider.
							["--no-scrollbar"] = true,
						},
						winopts = {
							height = height,
							width = width,
							row = 0.4,
							col = 0.5,
							border = float_style.border(),
							backdrop = 60,
						},
						hls = {
							normal = "Pmenu",
							border = "Pmenu",
							title = "Pmenu",
							cursorline = "PmenuSel",
							-- fzf paints its terminal cells from this nested palette; setting
							-- only `normal` leaves an editor-coloured rectangle inside the
							-- Pmenu padding after recent fzf-lua updates.
							fzf = {
								normal = "Pmenu",
								cursorline = "PmenuSel",
								border = "Pmenu",
								gutter = "Pmenu",
								query = "Pmenu",
							},
						},
					}
				end)
			end,
			opts = {
				defaults = {
					file_icons = extras and "mini" or false,
					color_icons = extras,
				},
				previewers = {
					builtin = {
						-- A picker should never turn a large binary/generated file into a
						-- hidden full-buffer load just because the selection moved over it.
						limit_b = 2 * 1024 * 1024,
						syntax_limit_b = 512 * 1024,
						treesitter = { context = false },
					},
				},
				fzf_colors = true,
				fzf_opts = {
					["--ansi"] = true,
					["--border"] = "none",
					["--height"] = "100%",
					["--info"] = "inline-right",
					["--layout"] = "reverse",
				},
				winopts = {
					width = 0.86,
					height = 0.86,
					row = 0.48,
					col = 0.5,
					border = "rounded",
					backdrop = 60,
					preview = {
						-- Moving the selection should not parse and highlight the
						-- file under the cursor unless the mode asked for previews.
						hidden = not extras,
						border = "rounded",
						layout = "flex",
						flip_columns = 120,
						horizontal = "right:58%",
						vertical = "down:45%",
						scrollbar = "float",
						title = true,
						title_pos = "center",
						winopts = {
							cursorline = true,
							number = true,
							relativenumber = false,
							signcolumn = "no",
							wrap = false,
						},
					},
				},
				files = {
					-- Respect .gitignore by default so file search never surfaces
					-- secrets (.env), credentials, or build/vendor dirs. `hidden`
					-- still shows non-ignored dotfiles (.github, .config, ...). Use
					-- <leader>fF ("find all") to include ignored files on demand.
					hidden = true,
					follow = false,
					fd_opts = "--color=never --type f --type l --hidden --exclude .git --exclude .jj",
					rg_opts = '--color=never --files --hidden -g "!.git" -g "!.jj"',
				},
				grep = {
					rg_opts = table.concat({
						"--column",
						"--line-number",
						"--no-heading",
						"--color=always",
						"--smart-case",
						"--hidden",
						'-g "!.git"',
						'-g "!.jj"',
					}, " "),
				},
				oldfiles = {
					include_current_session = true,
				},
			},
			keys = {
				{
					"<leader><space>",
					function()
						fzf().global(workspace_opts())
					end,
					desc = "Smart find",
				},
				{
					"<leader>,",
					function()
						fzf().buffers()
					end,
					desc = "Buffers",
				},
				{
					"<leader>/",
					function()
						fzf().live_grep(workspace_opts())
					end,
					desc = "Grep",
				},
				{
					"<leader>:",
					function()
						fzf().command_history()
					end,
					desc = "Command history",
				},
				{
					"<leader>?",
					function()
						fzf().keymaps()
					end,
					desc = "Keymaps",
				},
				{
					"<leader>fb",
					function()
						fzf().buffers()
					end,
					desc = "Buffers",
				},
				{
					"<leader>fc",
					function()
						fzf().commands()
					end,
					desc = "Commands",
				},
				{
					"<leader>ff",
					function()
						fzf().files(workspace_opts())
					end,
					desc = "Find files",
				},
				{
					"<leader>fF",
					function()
						-- Escape hatch: include .gitignored files (secrets, build, vendor).
						fzf().files(workspace_opts({ no_ignore = true, hidden = true }))
					end,
					desc = "Find all files (incl. ignored)",
				},
				{
					"<leader>fg",
					function()
						fzf().live_grep(workspace_opts())
					end,
					desc = "Grep",
				},
				{
					"<leader>fG",
					function()
						fzf().live_grep_glob(workspace_opts())
					end,
					desc = "Grep glob",
				},
				{
					"<leader>fh",
					function()
						fzf().helptags()
					end,
					desc = "Help",
				},
				{
					"<leader>fk",
					function()
						fzf().keymaps()
					end,
					desc = "Keymaps",
				},
				{
					"<leader>fl",
					function()
						fzf().blines()
					end,
					desc = "Buffer lines",
				},
				{
					"<leader>fL",
					function()
						fzf().lines()
					end,
					desc = "Open buffer lines",
				},
				{
					"<leader>fq",
					function()
						fzf().quickfix()
					end,
					desc = "Quickfix",
				},
				{
					"<leader>fo",
					function()
						fzf().oldfiles()
					end,
					desc = "Recent files",
				},
				{
					"<leader>fw",
					function()
						fzf().grep_cword(workspace_opts())
					end,
					desc = "Grep word",
				},
				{
					"<leader>fw",
					function()
						fzf().grep_visual(workspace_opts())
					end,
					mode = "x",
					desc = "Grep selection",
				},
				{
					"<leader>gc",
					function()
						fzf().git_commits(workspace_opts())
					end,
					desc = "Git commits",
				},
				{
					"<leader>gs",
					function()
						fzf().git_status(workspace_opts())
					end,
					desc = "Git status",
				},
			},
		},
	}
	if not capabilities.git then
		-- Without Git integration these keys would start a repository query the
		-- mode does not otherwise support.
		spec[1].keys = vim.tbl_filter(function(key)
			return not vim.startswith(key[1], "<leader>g")
		end, spec[1].keys)
	end
	return spec
end
