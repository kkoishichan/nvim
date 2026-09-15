local M = {}
local states = {}

M.limits = { bytes = 1.5 * 1024 * 1024, lines = 10000, line_bytes = 2000, average = 250, average_min = 10240 }

local function state(bufnr)
	states[bufnr] = states[bufnr] or {}
	return states[bufnr]
end

local function loaded_call(module, method, ...)
	local plugin = package.loaded[module]
	if plugin and type(plugin[method]) == "function" then
		pcall(plugin[method], ...)
	end
end

local function apply(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
		return
	end
	local entry = state(bufnr)
	if not entry.heavy then
		return
	end
	if not entry.saved then
		entry.saved = { syntax = vim.bo[bufnr].syntax, indentexpr = vim.bo[bufnr].indentexpr }
	end
	vim.bo[bufnr].syntax = ""
	vim.bo[bufnr].indentexpr = ""
	entry.windows = entry.windows or {}
	for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
		if not entry.windows[win] then
			entry.windows[win] = { foldenable = vim.wo[win].foldenable, foldmethod = vim.wo[win].foldmethod }
		end
		vim.wo[win].foldenable = false
		vim.wo[win].foldmethod = "manual"
	end
	pcall(vim.treesitter.stop, bufnr)
	loaded_call("ufo", "detach", bufnr)
	vim.api.nvim_buf_call(bufnr, function()
		loaded_call("illuminate", "pause_buf")
	end)
	loaded_call("ibl", "setup_buffer", bufnr, { enabled = false })
	loaded_call("nvim-highlight-colors", "clear_highlights", bufnr)
	for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
		-- Detach this document; never disable a server shared by other buffers.
		pcall(vim.lsp.buf_detach_client, bufnr, client.id)
	end
end

local function restore(bufnr)
	local entry = state(bufnr)
	local saved = entry.saved
	for option, value in pairs(saved or {}) do
		vim.bo[bufnr][option] = value
	end
	for win, options in pairs(entry.windows or {}) do
		if not vim.api.nvim_win_is_valid(win) then
			entry.windows[win] = nil
		elseif vim.api.nvim_win_get_buf(win) == bufnr then
			for option, value in pairs(options) do
				vim.wo[win][option] = value
			end
			entry.windows[win] = nil
		end
	end
	entry.saved = nil
	if not saved then
		return
	end
	vim.api.nvim_buf_call(bufnr, function()
		loaded_call("illuminate", "resume_buf")
	end)
	loaded_call("ibl", "setup_buffer", bufnr, { enabled = true })
	loaded_call("ufo", "attach", bufnr)
	vim.api.nvim_exec_autocmds("FileType", { buffer = bufnr, modeline = false })
end

local function publish(bufnr, reason, tick)
	local entry = state(bufnr)
	local was_heavy = entry.heavy
	entry.reason, entry.tick = reason, tick
	entry.heavy = entry.override == "off" or (entry.override ~= "on" and reason ~= nil)
	vim.b[bufnr].bigfile = entry.heavy
	vim.b[bufnr].user_buffer_cost = entry.override == "off" and "disabled manually" or reason
	if entry.heavy ~= was_heavy then
		vim.schedule(function()
			if not vim.api.nvim_buf_is_valid(bufnr) then
				return
			end
			if state(bufnr).heavy then
				apply(bufnr)
			else
				restore(bufnr)
			end
		end)
	end
	return { heavy = entry.heavy, reason = vim.b[bufnr].user_buffer_cost, override = entry.override or "auto" }
end

local function dimensions(bytes, lines)
	if bytes > M.limits.bytes then
		return "file exceeds 1.5 MiB"
	elseif lines > M.limits.lines then
		return "file exceeds 10000 lines"
	elseif bytes >= M.limits.average_min and bytes / math.max(lines, 1) > M.limits.average then
		return "average line exceeds 250 bytes"
	end
end

local function find_long_line(bufnr, first, last)
	-- A single bounded read avoids two memline offset lookups per line. This
	-- runs only below the document byte/line ceilings, or for the changed range.
	for index, text in ipairs(vim.api.nvim_buf_get_lines(bufnr, first, last, false)) do
		if #text > M.limits.line_bytes then
			return first + index - 1
		end
	end
end

function M.inspect(bufnr, changed)
	bufnr = (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
	if not vim.api.nvim_buf_is_valid(bufnr) or vim.bo[bufnr].buftype ~= "" then
		return { heavy = false, override = "auto" }
	end
	local entry = state(bufnr)
	local tick = vim.api.nvim_buf_get_changedtick(bufnr)
	if not changed and entry.tick == tick then
		return {
			heavy = entry.heavy,
			reason = entry.override == "off" and "disabled manually" or entry.reason,
			override = entry.override or "auto",
		}
	end
	local lines = vim.api.nvim_buf_line_count(bufnr)
	local bytes = math.max(0, vim.api.nvim_buf_get_offset(bufnr, lines))
	local reason = dimensions(bytes, lines)
	if not reason then
		if changed and entry.scanned then
			-- An unchanged offending line remains proof that the document is
			-- costly. Shift its row across insert/delete/undo without rescanning.
			local previous = entry.long_line
			local first, last = changed.first, math.min(changed.last, lines)
			local old_last = changed.old_last or changed.last
			if previous and previous >= old_last then
				entry.long_line = previous + changed.last - old_last
			elseif previous and previous >= first then
				entry.long_line = nil
			end
			if not entry.long_line then
				entry.long_line = find_long_line(bufnr, first, last)
				if previous and not entry.long_line then
					-- Removing the known long line may reveal another elsewhere.
					-- Confirm recovery once; ordinary edits remain incremental.
					entry.long_line = find_long_line(bufnr, 0, lines)
				end
			end
		else
			entry.long_line = find_long_line(bufnr, 0, lines)
		end
		entry.scanned = true
		reason = entry.long_line and "line exceeds 2000 bytes" or nil
	else
		-- These ceilings already decide the outcome. Inspect line widths once
		-- the document falls below them again, not on each oversized edit.
		entry.scanned, entry.long_line = false, nil
	end
	return publish(bufnr, reason, tick)
end

function M.allow(bufnr)
	return not M.inspect(bufnr or 0).heavy
end

local function read_pre(bufnr, path)
	local stat = vim.uv.fs_stat(path)
	if not stat or stat.type ~= "file" then
		return
	end
	local reason = stat.size > M.limits.bytes and "file exceeds 1.5 MiB" or nil
	if not reason then
		-- Bounded preflight before FileType starts regex scans or services.
		local fd = vim.uv.fs_open(path, "r", 0)
		if fd then
			local data = vim.uv.fs_read(fd, math.min(stat.size, M.limits.bytes), 0) or ""
			vim.uv.fs_close(fd)
			local offset, lines = 1, 0
			while offset <= #data do
				local next_line = data:find("\n", offset, true) or (#data + 1)
				lines = lines + 1
				if next_line - offset > M.limits.line_bytes then
					reason = "line exceeds 2000 bytes"
					break
				elseif lines > M.limits.lines then
					reason = "file exceeds 10000 lines"
					break
				end
				offset = next_line + 1
			end
			reason = reason or dimensions(stat.size, lines)
		end
	end
	publish(bufnr, reason, -1)
end

-- Preserve server root discovery, including asynchronous callbacks.
function M.lsp_init(original)
	return function(client, result)
		-- Initialization may finish after a paste turns an ordinary document into
		-- a costly one. on_init runs before Neovim sends the initial didOpen.
		for bufnr in pairs(client.attached_buffers) do
			if not M.allow(bufnr) then
				vim.lsp.buf_detach_client(bufnr, client.id)
			end
		end
		for _, callback in ipairs(type(original) == "table" and original or { original }) do
			callback(client, result)
		end
	end
end

function M.lsp_root(config)
	local original = config.root_dir
	return function(bufnr, on_dir)
		if not M.allow(bufnr) then
			return
		end
		local function accept(root)
			if vim.api.nvim_buf_is_valid(bufnr) and M.allow(bufnr) then
				on_dir(root)
			end
		end
		if type(original) == "function" then
			original(bufnr, accept)
		else
			accept(original or (config.root_markers and vim.fs.root(bufnr, config.root_markers)))
		end
	end
end

function M.set(bufnr, mode)
	bufnr = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr
	assert(mode == "auto" or mode == "on" or mode == "off", "invalid buffer feature mode")
	local entry = state(bufnr)
	entry.override, entry.tick = mode, nil
	return M.inspect(bufnr)
end

function M.setup()
	local group = vim.api.nvim_create_augroup("user_buffer_policy", { clear = true })
	vim.api.nvim_create_autocmd("BufReadPre", {
		group = group,
		callback = function(event)
			read_pre(event.buf, event.file)
		end,
	})
	vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile", "BufWinEnter" }, {
		group = group,
		callback = function(event)
			M.inspect(event.buf)
			local entry = state(event.buf)
			if not entry.attached then
				entry.attached = vim.api.nvim_buf_attach(event.buf, false, {
					on_lines = function(_, buf, _, first, old_last, last)
						M.inspect(buf, { first = first, old_last = old_last, last = last })
					end,
					on_detach = function(_, buf)
						states[buf] = nil
					end,
				})
			end
			if entry.heavy then
				vim.schedule(function()
					apply(event.buf)
				end)
			elseif entry.windows then
				restore(event.buf)
			end
		end,
	})
	vim.api.nvim_create_autocmd({ "LspAttach", "FileType" }, {
		group = group,
		callback = function(event)
			if not M.allow(event.buf) then
				vim.schedule(function()
					apply(event.buf)
				end)
			end
		end,
	})
	vim.api.nvim_create_user_command("BufferFeatures", function(command)
		local mode = command.args ~= "" and command.args or "status"
		local result = mode == "status" and M.inspect(0) or M.set(0, mode)
		vim.notify(
			("%s (%s): %s"):format(
				result.heavy and "Reduced features" or "Full features",
				result.override,
				result.reason or "ordinary buffer"
			),
			vim.log.levels.INFO,
			{ title = "Buffer features" }
		)
	end, {
		nargs = "?",
		complete = function()
			return { "status", "auto", "on", "off" }
		end,
	})
end

return M
