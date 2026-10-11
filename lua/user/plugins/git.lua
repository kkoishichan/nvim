local layout = require("user.core.layout")
local icons = require("user.core.icons")

local function toggle_diffview()
	local ok, lib = pcall(require, "diffview.lib")
	if ok and lib.get_current_view() then
		vim.cmd.DiffviewClose()
	else
		vim.cmd.DiffviewOpen()
	end
end

local function style_diff_window(_, winid, ctx)
	-- A two-way diff has an old and a new side. Merge layouts keep their
	-- native colours because their panes do not have that binary meaning.
	if not ctx.layout_name:match("^diff2_") then
		return
	end
	local prefix = ctx.symbol == "a" and "UserDiffviewDelete" or "UserDiffviewAdd"
	vim.api.nvim_win_call(winid, function()
		vim.opt_local.winhighlight:append({
			DiffAdd = prefix,
			DiffChange = prefix,
			DiffText = prefix .. "Text",
			DiffTextAdd = prefix .. "Text",
		})
	end)
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
			-- Do not mutate process-wide GIT_EDITOR/NVIM_LISTEN_ADDRESS. Lazygit
			-- uses its terminal editor unless the user configured one in the shell.
			vim.g.lazygit_use_neovim_remote = 0

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
			hooks = {
				diff_buf_win_enter = style_diff_window,
			},
			view = {
				merge_tool = {
					layout = "diff3_mixed",
				},
			},
		},
		config = function(_, opts)
			require("diffview").setup(opts)
			require("user.core.highlights").on_colorscheme("diffview", function()
				local colours = require("user.core.palette").git_diff()
				-- Background only: keep the file's syntax colours on both sides.
				vim.api.nvim_set_hl(0, "UserDiffviewAdd", { bg = colours.add })
				vim.api.nvim_set_hl(0, "UserDiffviewDelete", { bg = colours.delete })
				vim.api.nvim_set_hl(0, "UserDiffviewAddText", { bg = colours.add_text })
				vim.api.nvim_set_hl(0, "UserDiffviewDeleteText", { bg = colours.delete_text })
			end)
		end,
		keys = {
			{ "<leader>gd", toggle_diffview, desc = "Diffview toggle" },
			{ "<leader>gf", "<cmd>DiffviewFileHistory %<cr>", desc = "File history" },
			{ "<leader>gr", "<cmd>DiffviewFileHistory<cr>", desc = "Repo history" },
		},
	},
	{
		"lewis6991/gitsigns.nvim",
		event = { "BufReadPost", "BufNewFile" },
		opts = {
			max_file_length = 20000,
			update_debounce = 180,
			preview_config = {
				relative = "cursor",
				row = 1,
				col = 0,
			},
			signs = {
				add = { text = icons.git.bar },
				change = { text = icons.git.bar },
				delete = { text = icons.git.deleted },
				topdelete = { text = icons.git.deleted },
				changedelete = { text = icons.git.bar },
				untracked = { text = icons.git.untracked },
			},
			signs_staged = {
				add = { text = icons.git.bar },
				change = { text = icons.git.bar },
				delete = { text = icons.git.deleted },
				topdelete = { text = icons.git.deleted },
				changedelete = { text = icons.git.bar },
				untracked = { text = icons.git.untracked },
			},
			current_line_blame = require("user.core.mode").capabilities().decorations,
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
				local function navigate(direction)
					local preview = package.loaded["user.core.git_preview"]
					if preview then
						preview.navigate(direction)
					else
						gs.nav_hunk(direction)
					end
				end

				map("n", "]h", function()
					navigate("next")
				end, "Next hunk")
				map("n", "[h", function()
					navigate("prev")
				end, "Previous hunk")
				map("n", "<leader>ghs", gs.stage_hunk, "Stage/unstage hunk")
				map("n", "<leader>ghr", gs.reset_hunk, "Reset hunk")
				map("v", "<leader>ghs", function()
					gs.stage_hunk({ vim.fn.line("."), vim.fn.line("v") })
				end, "Stage hunk")
				map("v", "<leader>ghr", function()
					gs.reset_hunk({ vim.fn.line("."), vim.fn.line("v") })
				end, "Reset hunk")
				map("n", "<leader>ghS", gs.stage_buffer, "Stage buffer")
				-- No undo_stage_hunk map: deprecated upstream; stage_hunk toggles.
				map("n", "<leader>ghp", gs.preview_hunk, "Preview hunk")
				map("n", "<leader>ghi", function()
					require("user.core.git_preview").inline()
				end, "Preview hunk inline")
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
