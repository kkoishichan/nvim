local function fzf()
	return require("fzf-lua")
end

return {
	{
		"ibhagwan/fzf-lua",
		cmd = "FzfLua",
		dependencies = {
			"nvim-mini/mini.icons",
		},
		-- Route vim.ui.select (code actions, etc.) through fzf-lua, lazily: the
		-- first select call loads fzf-lua, which then replaces vim.ui.select.
		init = function()
			vim.ui.select = function(...)
				-- Loading fzf-lua runs its config, which calls register_ui_select()
				-- and replaces vim.ui.select; then dispatch to the real one.
				require("lazy").load({ plugins = { "fzf-lua" } })
				return vim.ui.select(...)
			end
		end,
		config = function(_, opts)
			local fzf_lua = require("fzf-lua")
			fzf_lua.setup(opts)
			fzf_lua.register_ui_select()
		end,
		opts = {
			defaults = {
				file_icons = "mini",
				color_icons = true,
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
				hidden = true,
				follow = false,
				no_ignore = true,
				fd_opts = "--color=never --type f --type l --hidden --no-ignore --exclude .git --exclude .jj",
				rg_opts = '--color=never --files --hidden --no-ignore -g "!.git" -g "!.jj"',
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
					fzf().global()
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
					fzf().live_grep()
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
					fzf().files()
				end,
				desc = "Find files",
			},
			{
				"<leader>fg",
				function()
					fzf().live_grep()
				end,
				desc = "Grep",
			},
			{
				"<leader>fG",
				function()
					fzf().live_grep_glob()
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
					fzf().grep_cword()
				end,
				desc = "Grep word",
			},
			{
				"<leader>fw",
				function()
					fzf().grep_visual()
				end,
				mode = "x",
				desc = "Grep selection",
			},
			{
				"<leader>gc",
				function()
					fzf().git_commits()
				end,
				desc = "Git commits",
			},
			{
				"<leader>gs",
				function()
					fzf().git_status()
				end,
				desc = "Git status",
			},
		},
	},
}
