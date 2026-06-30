local layout = require("user.core.layout")

local function setup_neovim_remote()
	if vim.fn.executable("nvr") ~= 1 or vim.v.servername == "" then
		vim.g.lazygit_use_neovim_remote = 0
		return
	end

	vim.g.lazygit_use_neovim_remote = 1
	vim.env.NVIM_LISTEN_ADDRESS = vim.v.servername
	vim.env.GIT_EDITOR = ("nvr --servername %s -cc split --remote-wait +'set bufhidden=wipe'"):format(
		vim.fn.shellescape(vim.v.servername)
	)
end

local function toggle_diffview()
	local ok, lib = pcall(require, "diffview.lib")
	if ok and lib.get_current_view() then
		vim.cmd.DiffviewClose()
	else
		vim.cmd.DiffviewOpen()
	end
end

return {
	{
		"kdheepak/lazygit.nvim",
		cmd = {
			"LazyGit",
			"LazyGitConfig",
			"LazyGitCurrentFile",
			"LazyGitFilter",
			"LazyGitFilterCurrentFile",
		},
		dependencies = { "nvim-lua/plenary.nvim" },
		init = function()
			vim.g.lazygit_floating_window_scaling_factor = layout.float_scale
			vim.g.lazygit_floating_window_winblend = 0
			setup_neovim_remote()

			-- lazygit centres on `vim.o.lines` (no statusline reservation), so it
			-- sits one row/col lower-right than the toggleterm float, which subtracts
			-- 1 from each. Nudge it up-left by 1 so the two overlay exactly. (Resizing
			-- while open reverts to lazygit's own position until reopened.)
			vim.api.nvim_create_autocmd("FileType", {
				group = vim.api.nvim_create_augroup("user_lazygit_pos", { clear = true }),
				pattern = "lazygit",
				callback = function(ev)
					local win = vim.fn.bufwinid(ev.buf)
					if win == -1 then
						return
					end
					local cfg = vim.api.nvim_win_get_config(win)
					if cfg.relative == "" then
						return
					end
					local function n(v)
						return type(v) == "table" and (v[false] or v[1]) or v
					end
					cfg.row = math.max(0, n(cfg.row) - 1)
					cfg.col = math.max(0, n(cfg.col) - 1)
					pcall(vim.api.nvim_win_set_config, win, cfg)
					require("user.core.backdrop").open(win)
				end,
			})
		end,
		keys = {
			{ "<leader>gg", "<cmd>LazyGit<cr>", desc = "Lazygit" },
			{ "<leader>gG", "<cmd>LazyGitCurrentFile<cr>", desc = "Lazygit current file" },
		},
	},
	{
		"sindrets/diffview.nvim",
		cmd = {
			"DiffviewClose",
			"DiffviewFileHistory",
			"DiffviewFocusFiles",
			"DiffviewLog",
			"DiffviewOpen",
			"DiffviewRefresh",
			"DiffviewToggleFiles",
		},
		dependencies = { "nvim-lua/plenary.nvim" },
		opts = {
			enhanced_diff_hl = true,
			view = {
				merge_tool = {
					layout = "diff3_mixed",
				},
			},
		},
		keys = {
			{ "<leader>gd", toggle_diffview, desc = "Diffview toggle" },
			{ "<leader>gf", "<cmd>DiffviewFileHistory %<cr>", desc = "File history" },
			{ "<leader>gr", "<cmd>DiffviewFileHistory<cr>", desc = "Repo history" },
		},
	},
	{
		"akinsho/git-conflict.nvim",
		version = "*",
		event = { "BufReadPost", "BufNewFile" },
		opts = {
			default_mappings = false,
			default_commands = true,
			disable_diagnostics = true,
			list_opener = "copen",
			highlights = {
				incoming = "DiffAdd",
				current = "DiffText",
			},
		},
		keys = {
			{ "]x", "<Plug>(git-conflict-next-conflict)", desc = "Next conflict" },
			{ "[x", "<Plug>(git-conflict-prev-conflict)", desc = "Previous conflict" },
			{ "<leader>gxo", "<Plug>(git-conflict-ours)", desc = "Conflict choose ours" },
			{ "<leader>gxt", "<Plug>(git-conflict-theirs)", desc = "Conflict choose theirs" },
			{ "<leader>gxb", "<Plug>(git-conflict-both)", desc = "Conflict choose both" },
			{ "<leader>gx0", "<Plug>(git-conflict-none)", desc = "Conflict choose none" },
			{ "<leader>gxl", "<cmd>GitConflictListQf<cr>", desc = "Conflict quickfix list" },
		},
	},
	{
		"lewis6991/gitsigns.nvim",
		event = { "BufReadPost", "BufNewFile" },
		opts = {
			signs = {
				add = { text = "+" },
				change = { text = "~" },
				delete = { text = "_" },
				topdelete = { text = "-" },
				changedelete = { text = "~" },
				untracked = { text = "?" },
			},
			current_line_blame = true,
			current_line_blame_opts = {
				virt_text = true,
				virt_text_pos = "eol",
				delay = 500,
				ignore_whitespace = false,
			},
			current_line_blame_formatter = "  <author>, <author_time:%Y-%m-%d> · <summary>",
			on_attach = function(bufnr)
				local gs = package.loaded.gitsigns
				local map = function(mode, lhs, rhs, desc)
					vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, desc = desc })
				end

				map("n", "]h", function()
					gs.nav_hunk("next")
				end, "Next hunk")
				map("n", "[h", function()
					gs.nav_hunk("prev")
				end, "Previous hunk")
				map("n", "<leader>ghs", gs.stage_hunk, "Stage hunk")
				map("n", "<leader>ghr", gs.reset_hunk, "Reset hunk")
				map("v", "<leader>ghs", function()
					gs.stage_hunk({ vim.fn.line("."), vim.fn.line("v") })
				end, "Stage hunk")
				map("v", "<leader>ghr", function()
					gs.reset_hunk({ vim.fn.line("."), vim.fn.line("v") })
				end, "Reset hunk")
				map("n", "<leader>ghS", gs.stage_buffer, "Stage buffer")
				map("n", "<leader>ghu", gs.undo_stage_hunk, "Undo stage hunk")
				map("n", "<leader>ghp", gs.preview_hunk, "Preview hunk")
				map("n", "<leader>ghb", function()
					gs.blame_line({ full = true })
				end, "Blame line")
				map("n", "<leader>ghB", gs.toggle_current_line_blame, "Toggle line blame")
				map("n", "<leader>ghd", gs.diffthis, "Diff buffer")
				map({ "o", "x" }, "ih", gs.select_hunk, "Hunk")
			end,
		},
	},
}
