local M = {}

local function terminal_buffer(term)
	return term and (term.bufnr or term.buf)
end

local function buffer_valid(term)
	local bufnr = terminal_buffer(term)
	return type(bufnr) == "number" and vim.api.nvim_buf_is_valid(bufnr)
end

local function buffer_variable(bufnr, name)
	local ok, value = pcall(vim.api.nvim_buf_get_var, bufnr, name)
	return ok and value or nil
end

local function visible_buffer(bufnr)
	if type(bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then
		return false
	end
	for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if vim.api.nvim_win_get_buf(window) == bufnr then
			return true
		end
	end
	return false
end

local function channel_for(term)
	if not buffer_valid(term) or term.user_ai_exited then
		return nil
	end
	local bufnr = terminal_buffer(term)
	local channel = term.job_id or buffer_variable(bufnr, "terminal_job_id")
	if type(channel) ~= "number" or channel <= 0 then
		channel = vim.api.nvim_get_option_value("channel", { buf = bufnr })
	end
	return type(channel) == "number" and channel > 0 and channel or nil
end

local function local_endpoint()
	local socket = assert(vim.uv.new_tcp())
	local ok, err = socket:bind("127.0.0.1", 0)
	if not ok then
		socket:close()
		error(err)
	end
	local port = socket:getsockname().port
	-- The CLI binds the chosen port itself. Occupied ports fail the startup;
	-- opencode.nvim validates the server's health before sending any requests.
	socket:close()
	return port, "http://127.0.0.1:" .. port
end

function M.new(options)
	local providers, notify, load = options.providers, options.notify, options.load
	local terms = {}
	local instance = { visible_buffer = visible_buffer }

	local function root()
		return require("user.core.project").root()
	end

	local function find_term(id, project_root)
		local group = terms[project_root]
		local term = group and group[id]
		if term and not term.user_ai_exited and (buffer_valid(term) or not term.bufnr) then
			return term
		end
		-- Recover only terminals carrying our exact ownership marker after a reload.
		local terminal = package.loaded["toggleterm.terminal"]
		for _, candidate in ipairs(terminal and terminal.get_all(true) or {}) do
			local marker = candidate.user_ai_terminal
				or (buffer_valid(candidate) and buffer_variable(terminal_buffer(candidate), "user_ai_terminal"))
			if
				marker
				and marker.provider == id
				and marker.root == project_root
				and buffer_valid(candidate)
				and not candidate.user_ai_exited
			then
				terms[project_root] = terms[project_root] or {}
				terms[project_root][id] = candidate
				return candidate
			end
		end
	end

	local function ensure(id, project_root)
		local provider = providers[id]
		if not provider or not provider.command then
			return nil
		end
		local term = find_term(id, project_root)
		if term then
			return term
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
		local count = provider.count or 201
		while terminal.get(count, true) do
			count = count + 1
		end
		local command = provider.terminal or provider.command
		local url
		if provider.server then
			local port
			port, url = local_endpoint()
			command = provider.command .. " --hostname 127.0.0.1 --mdns=false --port " .. port
		end
		local marker = { provider = id, command = command, label = provider.label, root = project_root, url = url }
		term = terminal.Terminal:new({
			cmd = command,
			count = count,
			dir = project_root,
			direction = "vertical",
			display_name = provider.label .. " · " .. vim.fn.fnamemodify(project_root, ":~"),
			hidden = true,
			close_on_exit = false,
			on_create = function(created)
				vim.b[created.bufnr].user_ai_terminal = marker
				vim.b[created.bufnr].user_project_root = project_root
			end,
			on_exit = function(exited, _, exit_code)
				exited.user_ai_exited = true
				local server = package.loaded["opencode.server"]
				if marker.url and server and server.connected and server.connected.url == marker.url then
					server.connected:disconnect()
				end
				marker.url = nil
				if buffer_valid(exited) then
					vim.b[terminal_buffer(exited)].user_ai_terminal = marker
				end
				if terms[project_root] and terms[project_root][id] == exited then
					terms[project_root][id] = nil
				end
				if exit_code and exit_code ~= 0 then
					notify(
						provider.label .. " exited in " .. project_root .. " (code " .. exit_code .. ")",
						vim.log.levels.WARN
					)
				end
			end,
		})
		term.user_ai_terminal = marker
		terms[project_root] = terms[project_root] or {}
		terms[project_root][id] = term
		return term
	end

	function instance.channel(id)
		return channel_for(find_term(id, root()))
	end

	function instance.visible(id)
		return visible_buffer(terminal_buffer(find_term(id, root())))
	end

	function instance.open(id, focus)
		local ok, term = pcall(ensure, id, root())
		if not ok or not term then
			if not ok then
				notify("Could not prepare " .. providers[id].label .. ": " .. tostring(term), vim.log.levels.ERROR)
			end
			return nil
		end
		-- Hide other projects' panels in this tab while leaving their jobs alive.
		for _, group in pairs(terms) do
			for _, other in pairs(group) do
				if other ~= term and visible_buffer(terminal_buffer(other)) then
					other:close()
				end
			end
		end
		local width = math.max(24, math.floor((vim.o.columns or 80) * 0.40))
		local opened = pcall(function()
			if focus then
				if not visible_buffer(terminal_buffer(term)) then
					term:open(width, "vertical")
				end
				term:focus()
				vim.cmd.startinsert()
			else
				term:toggle(width, "vertical")
			end
		end)
		if not opened then
			notify("Could not open " .. providers[id].label .. " terminal", vim.log.levels.ERROR)
			return nil
		end
		return term
	end

	function instance.endpoint(id)
		local ok, term = pcall(ensure, id, root())
		if not ok or not term then
			if not ok then
				notify("Could not prepare OpenCode: " .. tostring(term), vim.log.levels.ERROR)
			end
			return nil
		end
		if not buffer_valid(term) then
			local spawned, err = pcall(term.spawn, term)
			if not spawned or not channel_for(term) then
				term.user_ai_exited = true
				term.user_ai_terminal.url = nil
				if buffer_valid(term) then
					vim.b[terminal_buffer(term)].user_ai_terminal = term.user_ai_terminal
				end
				notify("Could not start OpenCode: " .. tostring(err), vim.log.levels.ERROR)
				return nil
			end
		end
		return term.user_ai_terminal.url
	end

	function instance.close(id)
		local term = find_term(id, root())
		if term and visible_buffer(terminal_buffer(term)) then
			return pcall(term.close, term)
		end
		return false
	end

	function instance.send(id, text)
		local term = instance.open(id, true)
		if not term then
			return
		end
		-- Retain the originating terminal across deferred sends and project changes.
		local function attempt(remaining)
			local channel = channel_for(term)
			if channel then
				local ok = pcall(vim.api.nvim_chan_send, channel, text)
				if ok then
					return
				end
			end
			if remaining <= 0 or term.user_ai_exited then
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
