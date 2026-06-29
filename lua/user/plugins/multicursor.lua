return {
	{
		"jake-stewart/multicursor.nvim",
		event = "VeryLazy",
		config = function()
			local mc = require("multicursor-nvim")
			mc.setup()

			-- Disable mini.pairs while a multicursor session is active so autopairs
			-- doesn't fight the per-cursor input replay.
			mc.onSafeState(function()
				vim.g.minipairs_disable = mc.hasCursors()
			end)

			local function map(mode, lhs, rhs, desc)
				vim.keymap.set(mode, lhs, rhs, { desc = desc })
			end

			-- Add / skip cursors by matching the word (or visual selection).
			map({ "n", "x" }, "<M-n>", function()
				mc.matchAddCursor(1)
			end, "Add next match")
			map({ "n", "x" }, "<M-p>", function()
				mc.matchAddCursor(-1)
			end, "Add previous match")
			map({ "n", "x" }, "<leader>vn", function()
				mc.matchAddCursor(1)
			end, "Add next match")
			map({ "n", "x" }, "<leader>vN", function()
				mc.matchAddCursor(-1)
			end, "Add previous match")
			map({ "n", "x" }, "<M-s>", function()
				mc.matchSkipCursor(1)
			end, "Skip next match")
			map({ "n", "x" }, "<leader>vs", function()
				mc.matchSkipCursor(1)
			end, "Skip next match")
			map({ "n", "x" }, "<leader>vS", function()
				mc.matchSkipCursor(-1)
			end, "Skip previous match")
			map({ "n", "x" }, "<M-a>", function()
				mc.matchAllAddCursors()
			end, "Add all matches")
			map({ "n", "x" }, "<leader>va", function()
				mc.matchAllAddCursors()
			end, "Add all matches")

			-- Add cursors above / below.
			map({ "n", "x" }, "<M-Down>", function()
				mc.lineAddCursor(1)
			end, "Add cursor below")
			map({ "n", "x" }, "<M-Up>", function()
				mc.lineAddCursor(-1)
			end, "Add cursor above")
			map({ "n", "x" }, "<leader>vj", function()
				mc.lineAddCursor(1)
			end, "Add cursor below")
			map({ "n", "x" }, "<leader>vk", function()
				mc.lineAddCursor(-1)
			end, "Add cursor above")

			-- Operate on a range / selection.
			map("x", "<leader>vm", function()
				mc.matchCursors()
			end, "Match within selection")
			map("x", "<leader>vc", function()
				mc.visualToCursors()
			end, "Selection to cursors")

			map({ "n", "x" }, "<leader>v=", function()
				mc.alignCursors()
			end, "Align cursors")
			map({ "n", "x" }, "<leader>vl", function()
				if mc.cursorsEnabled() then
					mc.disableCursors()
				else
					mc.enableCursors()
				end
			end, "Toggle cursor lock")

			-- Mouse: ctrl-click toggles a cursor.
			map({ "n", "i" }, "<M-LeftMouse>", mc.handleMouse, "Toggle cursor with mouse")

			-- Keys active only while multiple cursors exist.
			mc.addKeymapLayer(function(layer)
				layer({ "n", "x" }, "<left>", mc.prevCursor)
				layer({ "n", "x" }, "<right>", mc.nextCursor)
				layer({ "n", "x" }, "<M-x>", mc.deleteCursor, { desc = "Delete cursor" })
				layer({ "n", "x" }, "<leader>vx", mc.deleteCursor, { desc = "Delete cursor" })
				layer("n", "<esc>", function()
					if not mc.cursorsEnabled() then
						mc.enableCursors()
					else
						mc.clearCursors()
					end
				end)
			end)

			-- Restore the last cursor set.
			map("n", "<leader>vr", mc.restoreCursors, "Restore cursors")
		end,
	},
}
