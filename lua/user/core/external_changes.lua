-- Review of files that were rewritten outside the editor. The reload policy in
-- core/autocmds.lua keeps clean buffers in step with disk, which is right for
-- an agent editing alongside the user, but a reload throws away the version
-- the user was looking at. This keeps that version for the most recent
-- reloads so each can be diffed against the new content and, if the change
-- was unwanted, put back as an unsaved edit.
local M = {}
local api = vim.api
local limit, max_lines = 20, 20000
local pending = {}
M.entries = {}

---Called before a clean buffer is reloaded: keep what it showed.
function M.snapshot(bufnr)
	pending[bufnr] = nil
	if not api.nvim_buf_is_loaded(bufnr) or api.nvim_buf_line_count(bufnr) > max_lines then
		return false
	end
	pending[bufnr] = api.nvim_buf_get_lines(bufnr, 0, -1, false)
	return true
end

---Called after the reload: file the snapshot as a reviewable entry.
function M.record(bufnr, path)
	local before = pending[bufnr]
	pending[bufnr] = nil
	if not before then
		return nil
	end
	local entry = { bufnr = bufnr, path = vim.fs.normalize(path), before = before, time = os.time() }
	table.insert(M.entries, 1, entry)
	while #M.entries > limit do
		table.remove(M.entries)
	end
	return entry
end

function M.clear()
	M.entries, pending = {}, {}
end

local function describe(entry)
	local now = api.nvim_buf_is_loaded(entry.bufnr) and api.nvim_buf_line_count(entry.bufnr) or 0
	return ("%s  %s  (%d -> %d lines)"):format(
		os.date("%H:%M:%S", entry.time),
		vim.fn.fnamemodify(entry.path, ":~:."),
		#entry.before,
		now
	)
end

local function target_buffer(entry)
	if api.nvim_buf_is_valid(entry.bufnr) and api.nvim_buf_is_loaded(entry.bufnr) then
		return entry.bufnr
	end
	return vim.fn.bufadd(entry.path)
end

---Put the pre-reload content back into the buffer as an unsaved edit.
function M.revert(entry)
	local bufnr = target_buffer(entry)
	vim.fn.bufload(bufnr)
	api.nvim_buf_set_lines(bufnr, 0, -1, false, entry.before)
	vim.notify(
		"Restored the previous content of " .. vim.fs.basename(entry.path) .. " (unsaved)",
		vim.log.levels.INFO,
		{
			title = "External change",
		}
	)
	return bufnr
end

---Open the current buffer beside a scratch copy of what it showed before the
---reload, both in diff mode. `q` closes the review, `R` reverts.
function M.review(entry)
	local bufnr = target_buffer(entry)
	vim.fn.bufload(bufnr)
	api.nvim_set_current_buf(bufnr)
	local current = api.nvim_get_current_win()
	vim.cmd("vertical leftabove new")
	local scratch_win = api.nvim_get_current_win()
	local scratch = api.nvim_get_current_buf()
	api.nvim_buf_set_lines(scratch, 0, -1, false, entry.before)
	vim.bo[scratch].buftype = "nofile"
	vim.bo[scratch].bufhidden = "wipe"
	vim.bo[scratch].swapfile = false
	vim.bo[scratch].modifiable = false
	vim.bo[scratch].filetype = vim.bo[bufnr].filetype
	pcall(api.nvim_buf_set_name, scratch, "external-change://before/" .. vim.fs.basename(entry.path))
	for _, win in ipairs({ scratch_win, current }) do
		api.nvim_win_call(win, function()
			vim.cmd("diffthis")
		end)
	end
	local function close()
		if api.nvim_win_is_valid(current) then
			api.nvim_win_call(current, function()
				vim.cmd("diffoff")
			end)
		end
		if api.nvim_win_is_valid(scratch_win) then
			api.nvim_win_close(scratch_win, true)
		end
	end
	vim.keymap.set("n", "q", close, { buffer = scratch, desc = "Close review" })
	vim.keymap.set("n", "R", function()
		close()
		M.revert(entry)
	end, { buffer = scratch, desc = "Revert to the previous content" })
	api.nvim_set_current_win(scratch_win)
	return { buffer = scratch, window = scratch_win, target = bufnr }
end

---Choose a recent external change to review.
function M.pick()
	if #M.entries == 0 then
		vim.notify("No external changes have been reloaded in this session", vim.log.levels.INFO, {
			title = "External change",
		})
		return false
	end
	vim.ui.select(M.entries, { prompt = "External changes", format_item = describe }, function(entry)
		if entry then
			M.review(entry)
		end
	end)
	return true
end

return M
