-- A clean buffer reloaded after an external rewrite keeps its previous
-- content for review; the review diffs and can revert; buffers with unsaved
-- edits are never reloaded and therefore never recorded; the list is bounded.
return function(tmp)
	local api = vim.api
	local changes = require("user.core.external_changes")
	changes.clear()
	local path = vim.fs.joinpath(tmp, "watched.txt")
	vim.fn.writefile({ "one", "two", "three" }, path)
	vim.cmd.edit(vim.fn.fnameescape(path))
	local bufnr = api.nvim_get_current_buf()
	local before = { "one", "two", "three" }
	local events = {}
	api.nvim_create_autocmd({ "FileChangedShell", "FileChangedShellPost" }, {
		buffer = bufnr,
		callback = function(event)
			events[#events + 1] = event.event
		end,
	})

	-- 1. Rewrite on disk with a different size, reconcile, and find the entry.
	-- The decision event must be raised for a clean buffer: with 'autoread'
	-- Neovim reloads first and only announces FileChangedShellPost.
	vim.fn.writefile({ "one", "TWO", "three", "four" }, path)
	vim.cmd.checktime({ args = { tostring(bufnr) } })
	assert(
		vim.deep_equal(events, { "FileChangedShell", "FileChangedShellPost" }),
		"Reconciliation did not go through FileChangedShell: " .. table.concat(events, ",")
	)
	assert(#changes.entries == 1, "The reload was not recorded: " .. #changes.entries)
	local entry = changes.entries[1]
	assert(entry.bufnr == bufnr and entry.path == vim.fs.normalize(path), vim.inspect(entry.path))
	assert(vim.deep_equal(entry.before, before), "The previous content was not kept")
	assert(
		vim.deep_equal(api.nvim_buf_get_lines(bufnr, 0, -1, false), { "one", "TWO", "three", "four" }),
		"The clean buffer was not reloaded"
	)

	-- 2. Review diffs the previous content against the buffer; R reverts.
	local review = changes.review(entry)
	assert(api.nvim_win_is_valid(review.window) and vim.wo[review.window].diff, "Review window is not in diff mode")
	assert(vim.wo[vim.fn.bufwinid(bufnr)].diff, "Target window is not in diff mode")
	assert(
		vim.deep_equal(api.nvim_buf_get_lines(review.buffer, 0, -1, false), before),
		"Review shows the wrong content"
	)
	assert(
		not vim.bo[review.buffer].modifiable and vim.bo[review.buffer].buftype == "nofile",
		"Review buffer is writable"
	)
	api.nvim_set_current_win(review.window)
	api.nvim_feedkeys("R", "mx", false)
	assert(not api.nvim_win_is_valid(review.window), "Revert did not close the review")
	assert(vim.deep_equal(api.nvim_buf_get_lines(bufnr, 0, -1, false), before), "Revert did not restore the content")
	assert(vim.bo[bufnr].modified, "Revert must leave an unsaved edit, not write the file")
	assert(not vim.wo[vim.fn.bufwinid(bufnr)].diff, "Revert left the target in diff mode")

	-- 3. A buffer with unsaved edits is neither reloaded nor recorded.
	vim.fn.writefile({ "five" }, path)
	vim.cmd.checktime({ args = { tostring(bufnr) } })
	assert(#changes.entries == 1, "A modified buffer produced a reload entry")
	assert(vim.deep_equal(api.nvim_buf_get_lines(bufnr, 0, -1, false), before), "A modified buffer was reloaded")

	-- 4. q closes a review without changing anything.
	review = changes.review(entry)
	api.nvim_set_current_win(review.window)
	api.nvim_feedkeys("q", "mx", false)
	assert(not api.nvim_win_is_valid(review.window), "q did not close the review")
	assert(vim.deep_equal(api.nvim_buf_get_lines(bufnr, 0, -1, false), before), "Closing the review changed the buffer")

	-- 5. The list is bounded and the picker reports an empty list.
	for index = 1, 25 do
		changes.snapshot(bufnr)
		changes.record(bufnr, path .. index)
	end
	assert(#changes.entries == 20, "The entry list is not bounded: " .. #changes.entries)
	changes.clear()
	assert(changes.pick() == false, "An empty list opened a picker")
	assert(
		vim.fn.exists(":ExternalChanges") == 2 and vim.fn.maparg("<leader>ge", "n") ~= "",
		"Entry points are missing"
	)
	vim.bo[bufnr].modified = false
	api.nvim_buf_delete(bufnr, { force = true })
	print(
		"External changes passed: reload snapshot, diff review, revert as unsaved edit, modified buffers untouched, bounded list"
	)
end
