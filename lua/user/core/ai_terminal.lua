local M = {}

local function terminal_buffer(term)
	return term and (term.bufnr or term.buf)
end

local function terminal_window(term)
	return term and (term.window or term.win)
end

local function buffer_valid(term)
	local bufnr = terminal_buffer(term)
	return type(bufnr) == "number" and vim.api.nvim_buf_is_valid(bufnr)
end

local function terminal_visible(term)
	if not buffer_valid(term) then
		return false
	end
	if type(term.is_open) == "function" then
		local ok, open = pcall(term.is_open, term)
		if ok then
			return open == true
		end
	end
	local window = terminal_window(term)
	return type(window) == "number" and vim.api.nvim_win_is_valid(window)
end

local function all_windows()
	local windows = {}
	for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
		vim.list_extend(windows, vim.api.nvim_tabpage_list_wins(tabpage))
	end
	return windows
end

local function buffer_variable(bufnr, name)
	local ok, value = pcall(vim.api.nvim_buf_get_var, bufnr, name)
	return ok and value or nil
end

local function terminal_command(bufnr)
	local marker = buffer_variable(bufnr, "user_ai_terminal")
	if type(marker) == "table" and type(marker.command) == "string" then
		return marker.command
	end
	local name = vim.api.nvim_buf_get_name(bufnr)
	return type(name) == "string" and name:match("^term://.-//%d+:(.+)$") or nil
end

local function command_matches(full_command, command)
	if type(full_command) ~= "string" or type(command) ~= "string" or command == "" then
		return false
	end
	local escaped = command:gsub("([^%w])", "%%%1")
	return full_command == command or full_command:match("^" .. escaped .. "%s") ~= nil
end

local function channel_for_buffer(bufnr, term)
	if term and type(term.job_id) == "number" and term.job_id > 0 then
		return term.job_id
	end
	local from_variable = buffer_variable(bufnr, "terminal_job_id")
	if type(from_variable) == "number" and from_variable > 0 then
		return from_variable
	end
	local ok, channel = pcall(vim.api.nvim_get_option_value, "channel", { buf = bufnr })
	return ok and type(channel) == "number" and channel > 0 and channel or nil
end

function M.new(options)
	local providers = options.providers
	local notify = options.notify
	local load = options.load
	local terms = {}
	local instance = {}

	local function command(id)
		local provider = providers[id]
		return provider and (provider.terminal or provider.command) or nil
	end

	local function width()
		return math.max(24, math.floor((vim.o.columns or 80) * 0.40))
	end

	local function find_term(id)
		local term = terms[id]
		if buffer_valid(term) then
			return term
		end
		local provider = providers[id]
		if not provider or not provider.count then
			return nil
		end

		load("toggleterm.nvim")
		local ok, terminal = pcall(require, "toggleterm.terminal")
		if ok and type(terminal.get) == "function" then
			term = terminal.get(provider.count, true)
			if buffer_valid(term) then
				terms[id] = term
				return term
			end
		end
	end

	function instance.visible_buffer(bufnr)
		if type(bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then
			return false
		end
		for _, window in ipairs(all_windows()) do
			if vim.api.nvim_win_is_valid(window) and vim.api.nvim_win_get_buf(window) == bufnr then
				return true
			end
		end
		return false
	end

	function instance.channel(id)
		local provider = providers[id]
		local provider_command = provider and (provider.command or provider.executable)
		if not provider_command then
			return nil
		end
		for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
			if vim.api.nvim_buf_is_valid(bufnr) and command_matches(terminal_command(bufnr), provider_command) then
				local term = terms[id]
				return channel_for_buffer(bufnr, terminal_buffer(term) == bufnr and term or nil)
			end
		end
	end

	function instance.visible(id)
		if terminal_visible(find_term(id)) then
			return true
		end
		local provider = providers[id]
		for _, window in ipairs(all_windows()) do
			local bufnr = vim.api.nvim_win_get_buf(window)
			if provider and command_matches(terminal_command(bufnr), provider.command) then
				return true
			end
		end
		return false
	end

	function instance.open(id, focus)
		local provider = providers[id]
		if not provider or not provider.command then
			return nil
		end
		if provider.plugin then
			load(provider.plugin)
		end
		if vim.fn.executable(provider.command) == 0 then
			notify(provider.command .. " is not executable", vim.log.levels.ERROR)
			return nil
		end

		load("toggleterm.nvim")
		local ok, terminal = pcall(require, "toggleterm.terminal")
		if not ok or not terminal.Terminal then
			notify("toggleterm.nvim is not available", vim.log.levels.ERROR)
			return nil
		end

		local term = find_term(id)
		if not term then
			term = terminal.Terminal:new({
				cmd = command(id),
				count = provider.count,
				direction = "vertical",
				display_name = provider.label,
				hidden = true,
				close_on_exit = false,
				on_create = function(created)
					if created.bufnr and vim.api.nvim_buf_is_valid(created.bufnr) then
						vim.api.nvim_buf_set_var(created.bufnr, "user_ai_terminal", {
							provider = id,
							command = command(id),
							label = provider.label,
						})
					end
				end,
			})
			terms[id] = term
		end

		local opened = pcall(function()
			if focus then
				if not terminal_visible(term) then
					term:open(width(), "vertical")
				end
				term:focus()
				vim.cmd.startinsert()
			else
				term:toggle(width(), "vertical")
			end
		end)
		if not opened then
			terms[id] = nil
			notify("Could not open " .. provider.label .. " terminal", vim.log.levels.ERROR)
			return nil
		end
		return term
	end

	function instance.close(id)
		local term = find_term(id)
		if term and type(term.close) == "function" and terminal_visible(term) then
			return pcall(term.close, term)
		end
		return false
	end

	function instance.send(id, text)
		local term = instance.open(id, true)
		if not term then
			return
		end
		local function attempt(remaining)
			local bufnr = terminal_buffer(term)
			local channel = bufnr and channel_for_buffer(bufnr, term)
			if channel then
				vim.api.nvim_chan_send(channel, text)
				return
			end
			if remaining <= 0 then
				notify("Could not send to " .. providers[id].label .. ": terminal is not ready", vim.log.levels.WARN)
				return
			end
			vim.defer_fn(function()
				attempt(remaining - 1)
			end, 60)
		end
		vim.defer_fn(function()
			attempt(12)
		end, 80)
	end

	return instance
end

return M
