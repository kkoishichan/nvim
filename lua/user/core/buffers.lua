local M = {}
local api = vim.api
local queue, active = {}, nil

local function notice(message)
	vim.notify(message, vim.log.levels.WARN, { title = "Close buffer" })
end

local function editable(bufnr)
	return api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buftype == ""
end

local function replacement(winid, closing)
	local alternate = api.nvim_win_call(winid, function()
		return vim.fn.bufnr("#")
	end)
	if alternate ~= closing and editable(alternate) and vim.bo[alternate].buflisted then
		return alternate
	end
	local candidates = vim.fn.getbufinfo({ buflisted = 1 })
	table.sort(candidates, function(left, right)
		if left.lastused == right.lastused then
			return left.bufnr > right.bufnr
		end
		return left.lastused > right.lastused
	end)
	for _, candidate in ipairs(candidates) do
		if candidate.bufnr ~= closing and editable(candidate.bufnr) then
			return candidate.bufnr
		end
	end
end

local function switch_buffer(winid, bufnr)
	local fixed = vim.wo[winid].winfixbuf
	vim.wo[winid].winfixbuf = false
	local ok, err = pcall(api.nvim_win_set_buf, winid, bufnr)
	if api.nvim_win_is_valid(winid) then
		vim.wo[winid].winfixbuf = fixed
	end
	return ok, err
end

local function remove(bufnr, discard, expected_tick)
	if not editable(bufnr) then
		return false, "This buffer is managed by a panel; use its own close action"
	end
	local windows = vim.fn.win_findbuf(bufnr)
	for _, winid in ipairs(windows) do
		if not require("user.core.window_roles").is_editor(winid) then
			return false, "This buffer is displayed in a managed panel; close that panel first"
		end
	end
	if vim.bo[bufnr].modified and not discard then
		return false, "The buffer still contains unsaved changes"
	end
	if expected_tick and api.nvim_buf_get_changedtick(bufnr) ~= expected_tick then
		return false, "The buffer changed while the close choice was open; close it again to review the new contents"
	end
	local changed, created = {}, nil
	-- bufhidden=wipe/delete must not remove the buffer while its other windows
	-- are being replaced. Keeping it hidden also avoids abandoning edited text.
	local hidden = vim.bo[bufnr].bufhidden
	vim.bo[bufnr].bufhidden = "hide"
	local ok, err = pcall(function()
		for _, winid in ipairs(windows) do
			if api.nvim_win_is_valid(winid) and api.nvim_win_get_buf(winid) == bufnr then
				local next_buffer = replacement(winid, bufnr)
				if not next_buffer then
					created = created or api.nvim_create_buf(true, false)
					next_buffer = created
				end
				local switched, failure = switch_buffer(winid, next_buffer)
				assert(switched, failure)
				table.insert(changed, winid)
			end
		end
		-- BufLeave callbacks may modify the old buffer. Never discard changes
		-- that were made after the user selected Discard.
		if discard then
			assert(api.nvim_buf_get_changedtick(bufnr) == expected_tick, "The buffer changed during close")
		else
			assert(not vim.bo[bufnr].modified, "The buffer changed during close; review its unsaved contents")
		end
		api.nvim_buf_delete(bufnr, { force = discard })
	end)
	if api.nvim_buf_is_valid(bufnr) then
		if not ok then
			for _, winid in ipairs(changed) do
				if api.nvim_win_is_valid(winid) then
					switch_buffer(winid, bufnr)
				end
			end
		end
		vim.bo[bufnr].bufhidden = hidden
	end
	if not ok and created and api.nvim_buf_is_valid(created) and #vim.fn.win_findbuf(created) == 0 then
		pcall(api.nvim_buf_delete, created, { force = false })
	end
	return ok, not ok and tostring(err) or nil
end

local pump
local function finish(success, reason)
	local request = active
	active = nil
	if reason and reason ~= "cancelled" then
		notice(reason)
	end
	request.result = success
	if request.on_complete then
		request.on_complete(success, reason)
	end
	pump()
end

local function save(request)
	local function write(path)
		if not api.nvim_buf_is_valid(request.bufnr) then
			finish(false, "The buffer no longer exists")
			return
		end
		local ok, err = pcall(api.nvim_buf_call, request.bufnr, function()
			vim.cmd.write({ args = path and { path } or {} })
		end)
		if not ok then
			finish(false, "Could not save buffer: " .. tostring(err))
			return
		end
		finish(remove(request.bufnr, false))
	end
	if api.nvim_buf_get_name(request.bufnr) == "" then
		vim.ui.input({ prompt = "Save as: ", default = request.cwd .. "/", completion = "file" }, function(path)
			if not path or path == "" then
				finish(false, "cancelled")
				return
			end
			if not vim.startswith(path, "/") then
				path = vim.fs.joinpath(request.cwd, path)
			end
			write(path)
		end)
	else
		write()
	end
end

pump = function()
	if active or #queue == 0 then
		return
	end
	active = table.remove(queue, 1)
	local request = active
	local bufnr = request.bufnr
	if not editable(bufnr) then
		finish(false, "This buffer is unavailable or managed by a panel; use its own close action")
		return
	end
	if not vim.bo[bufnr].modified then
		finish(remove(bufnr, false))
		return
	end
	local tick = api.nvim_buf_get_changedtick(bufnr)
	local name = api.nvim_buf_get_name(bufnr)
	vim.ui.select({ "Save", "Discard", "Cancel" }, {
		prompt = "Close " .. (name ~= "" and vim.fn.fnamemodify(name, ":~:.") or "[No Name]") .. "?",
	}, function(choice)
		if choice == "Save" then
			save(request)
		elseif choice == "Discard" then
			finish(remove(bufnr, true, tick))
		else
			finish(false, "cancelled")
		end
	end)
end

---Close an editing buffer in every tab while preserving its windows. Modified
---buffers always present Save / Discard / Cancel; bulk callers are queued.
---@param bufnr? integer
---@param opts? {on_complete?: fun(success: boolean, reason?: string)}
---@return boolean? success Nil means an asynchronous choice is pending.
function M.close(bufnr, opts)
	bufnr = (bufnr == nil or bufnr == 0) and api.nvim_get_current_buf() or bufnr
	if active and active.bufnr == bufnr then
		return nil
	end
	for _, request in ipairs(queue) do
		if request.bufnr == bufnr then
			return nil
		end
	end
	local request = { bufnr = bufnr, cwd = vim.fn.getcwd(), on_complete = (opts or {}).on_complete }
	table.insert(queue, request)
	pump()
	return request.result
end

return M
