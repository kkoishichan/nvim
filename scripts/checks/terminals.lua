return function(tmp)
	local project = require("user.core.project")
	local config_root = assert(vim.env.NVIM_TEST_ROOT, "NVIM_TEST_ROOT is required")
	local roots = { tmp .. "/project A", tmp .. "/project B" }
	for _, root in ipairs(roots) do
		vim.fn.mkdir(root, "p")
	end
	local saved = {
		terminal = package.loaded["toggleterm.terminal"],
		ai = package.loaded["user.core.ai"],
		lazy = package.loaded.lazy,
		claude = package.loaded["claudecode.terminal"],
		opencode = package.loaded.opencode,
		server = package.loaded["opencode.server"],
		opencode_config = package.loaded["opencode.config"],
		new_tcp = vim.uv.new_tcp,
		executable = vim.fn.executable,
		chan_send = vim.api.nvim_chan_send,
		notify = vim.notify,
		select = vim.ui.select,
		input = vim.ui.input,
	}
	local registry, writes, notices = {}, {}, {}
	local port, closed_sockets = 41000, 0
	local methods = {}
	local fail_spawn = false
	function methods:spawn()
		if fail_spawn then
			error("simulated terminal startup failure")
		end
		self.bufnr = vim.api.nvim_create_buf(false, true)
		self.job_id = self.id + 1000
		vim.api.nvim_buf_set_name(self.bufnr, "fake-terminal-" .. self.id)
		if self.on_create then
			self.on_create(self)
		end
	end
	function methods:open()
		if not self.bufnr or not vim.api.nvim_buf_is_valid(self.bufnr) then
			self:spawn()
		end
		if not self.window or not vim.api.nvim_win_is_valid(self.window) then
			vim.cmd("botright split")
			self.window = vim.api.nvim_get_current_win()
		end
		vim.api.nvim_win_set_buf(self.window, self.bufnr)
		vim.api.nvim_set_current_win(self.window)
	end
	function methods:is_open()
		return self.window and vim.api.nvim_win_is_valid(self.window) or false
	end
	function methods:is_focused()
		return self.window == vim.api.nvim_get_current_win()
	end
	function methods:focus()
		vim.api.nvim_set_current_win(self.window)
	end
	function methods:close()
		if self:is_open() then
			vim.api.nvim_win_close(self.window, true)
		end
	end
	function methods:toggle()
		if self:is_open() then
			self:close()
		else
			self:open()
		end
	end
	function methods:shutdown()
		self.shutdown_called = true
		self:close()
		if self.on_exit then
			self.on_exit(self, self.job_id, 0)
		end
		registry[self.id] = nil
	end
	function methods:change_dir()
		error("An existing project terminal must never be sent cd")
	end
	local terminal = {
		Terminal = {
			new = function(_, opts)
				opts.id = opts.count
				local term = setmetatable(opts, { __index = methods })
				registry[term.id] = term
				return term
			end,
		},
		get = function(id, hidden)
			local term = registry[id]
			return term and (hidden or not term.hidden) and term or nil
		end,
		get_all = function(hidden)
			local result = {}
			for _, term in pairs(registry) do
				if hidden or not term.hidden then
					table.insert(result, term)
				end
			end
			return result
		end,
	}
	local ok, err = xpcall(function()
		vim.notify = function(message)
			table.insert(notices, message)
		end
		vim.fn.executable = function()
			return 1
		end
		vim.api.nvim_chan_send = function(channel, text)
			table.insert(writes, { channel = channel, text = text })
		end
		vim.uv.new_tcp = function()
			port = port + 1
			local assigned = port
			return {
				bind = function(_, address, requested)
					assert(address == "127.0.0.1" and requested == 0, "AI port probe must bind only loopback")
					return 0
				end,
				getsockname = function()
					return { port = assigned }
				end,
				close = function()
					closed_sockets = closed_sockets + 1
				end,
			}
		end
		package.loaded["toggleterm.terminal"] = terminal
		package.loaded.lazy = { load = function() end }
		local spec = dofile(config_root .. "/lua/user/plugins/terminal.lua")[1]
		local keys = {}
		for _, mapping in ipairs(spec.keys) do
			keys[mapping[1]] = mapping[2]
		end
		project.set(roots[1])
		keys["<leader>tn"]()
		local first = registry[1]
		assert(first.dir == roots[1] and first.display_name:find(roots[1], 1, true), "New terminal lost project A")
		keys["<leader>tn"]()
		local second = registry[2]
		project.set(roots[2])
		keys["<leader>tt"]()
		local third = registry[3]
		assert(third.dir == roots[2] and not first.shutdown_called, "Project B reused or stopped project A's terminal")
		project.set(roots[1])
		keys["<leader>tt"]()
		assert(second:is_open() and not third:is_open(), "Returning to project A did not restore its selected terminal")
		keys["<leader>t["]()
		assert(first:is_open(), "Project-local previous terminal included another project")
		keys["<leader>tk"]()
		assert(first.shutdown_called and not third.shutdown_called, "Terminal kill affected the wrong project")
		local choices
		vim.ui.select = function(items)
			choices = items
		end
		keys["<leader>tl"]()
		assert(#choices == 1 and choices[1] == second, "Terminal picker listed other projects")

		local providers = {
			codex = { label = "Codex", command = "codex", count = 201 },
			opencode = { label = "OpenCode", command = "opencode", count = 202, server = true },
		}
		local function new_manager()
			return require("user.core.ai_terminal").new({
				providers = providers,
				notify = vim.notify,
				load = function() end,
			})
		end
		local rogue = terminal.Terminal:new({ count = 201, cmd = "codex", hidden = true })
		rogue:spawn()
		local manager = new_manager()
		assert(manager.channel("codex") == nil, "AI adopted an unrelated same-name terminal")
		local codex_a = manager.open("codex", true)
		assert(codex_a ~= rogue and codex_a.dir == roots[1], "AI did not allocate an owned terminal")
		manager.send("codex", "A context")
		project.set(roots[2])
		local codex_b = manager.open("codex", true)
		assert(codex_b ~= codex_a and codex_b.dir == roots[2], "AI reused project A's process for B")
		assert(manager.channel("codex") == codex_b.job_id, "Current project's interrupt channel is wrong")
		assert(
			vim.wait(500, function()
				return #writes == 1
			end),
			"Deferred AI send did not complete"
		)
		assert(writes[1].channel == codex_a.job_id, "Deferred A context was redirected to project B")
		project.set(roots[1])
		assert(new_manager().channel("codex") == codex_a.job_id, "AI manager reload lost exact ownership")
		assert(manager.open("codex", true) == codex_a, "Returning to A did not reuse its process")
		codex_a.on_exit(codex_a, codex_a.job_id, 1)
		assert(manager.channel("codex") == nil, "Exited AI terminal retained an active channel")

		local url_a = manager.endpoint("opencode")
		local source_window = vim.api.nvim_get_current_win()
		project.set(roots[2])
		local url_b = manager.endpoint("opencode")
		assert(url_a ~= url_b and closed_sockets == 2, "OpenCode projects did not get separate closed port probes")
		assert(vim.api.nvim_get_current_win() == source_window, "Background OpenCode startup changed context focus")
		local open_b
		for _, term in pairs(registry) do
			if term.user_ai_terminal and term.user_ai_terminal.url == url_b then
				open_b = term
			end
		end
		assert(
			open_b and open_b.cmd:find("--hostname 127.0.0.1 --mdns=false", 1, true),
			"OpenCode must listen only on loopback"
		)
		assert(open_b.dir == roots[2], "OpenCode URL points to a process with the wrong project cwd")

		local disconnected, prompts = 0, 0
		local server = { connected = { url = url_a, cwd = roots[1] } }
		vim.opt.rtp:append(require("lazy.core.config").plugins["opencode.nvim"].dir)
		local Promise = require("opencode.promise")
		server.new = function(url)
			for _, term in pairs(registry) do
				local marker = term.user_ai_terminal
				if marker and marker.url == url then
					return Promise.resolve({ cwd = marker.root })
				end
			end
			return Promise.reject("Unknown managed URL")
		end
		server.connected.disconnect = function()
			disconnected = disconnected + 1
			server.connected = nil
		end
		package.loaded["opencode.server"] = server
		local config = { opts = { server = {} } }
		package.loaded["opencode.config"] = config
		dofile(config_root .. "/lua/user/plugins/opencode.lua")[1].config()
		assert(config.opts.server.connect == false, "OpenCode retained a global persistent server")
		assert(config.opts.server.start == false, "OpenCode retained retries that can change project scope")
		package.loaded.opencode = {
			format = function(opts)
				return opts.path or vim.api.nvim_buf_get_name(opts.buf)
			end,
			prompt = function(text)
				assert(text ~= "@buffer ", "OpenCode deferred source-buffer lookup until after discovery")
				assert(server.connected == nil, "OpenCode request reused another project's connected server")
				config.opts.server.url(function(url)
					assert(url == url_b, "OpenCode request targeted another project's URL")
					prompts = prompts + 1
				end)
			end,
		}
		package.loaded["user.core.ai"] = nil
		vim.g.user_ai_provider = "opencode"
		local ai = require("user.core.ai")
		ai.add_buffer()
		assert(
			vim.wait(500, function()
				return prompts == 1
			end),
			"OpenCode did not resolve its verified project URL"
		)
		assert(
			disconnected == 1 and prompts == 1,
			"OpenCode routing did not disconnect stale subscription and send once"
		)
		local normal_new = server.new
		server.new = function()
			return Promise.resolve({ cwd = roots[1] })
		end
		local resolved
		config.opts.server.url(function(url)
			resolved = url or false
		end)
		assert(
			vim.wait(500, function()
				return resolved ~= nil
			end),
			"OpenCode directory validation did not complete"
		)
		assert(resolved == false, "OpenCode accepted a server with another project's cwd")
		local pending
		server.new = function()
			return Promise.new(function(resolve)
				pending = resolve
			end)
		end
		resolved = nil
		config.opts.server.url(function(url)
			resolved = url or false
		end)
		project.set(roots[1])
		pending({ cwd = roots[2] })
		assert(
			vim.wait(500, function()
				return resolved ~= nil
			end),
			"Pending OpenCode lookup did not finish after project switch"
		)
		assert(resolved == false, "Pending OpenCode request followed a project switch")
		server.new = normal_new
		project.set(roots[2])
		local unrelated = { url = url_a, cwd = roots[1] }
		server.connected = unrelated
		open_b.on_exit(open_b, open_b.job_id, 1)
		assert(open_b.user_ai_terminal.url == nil, "Failed OpenCode process retained its stale endpoint")
		assert(vim.b[open_b.bufnr].user_ai_terminal.url == nil, "Failed OpenCode buffer retained its stale endpoint")
		assert(server.connected == unrelated, "Exiting B disconnected project A's server")
		manager.endpoint("opencode")
		local restarted_b
		for _, term in pairs(registry) do
			if term.user_ai_terminal and term.user_ai_terminal.root == roots[2] and term.user_ai_terminal.url then
				restarted_b = term
			end
		end
		server.connected = {
			url = restarted_b.user_ai_terminal.url,
			disconnect = function()
				server.connected = nil
			end,
		}
		restarted_b.on_exit(restarted_b, restarted_b.job_id, 1)
		assert(server.connected == nil, "Exited OpenCode retained its matching event subscription")
		fail_spawn = true
		assert(manager.endpoint("opencode") == nil, "Failed startup reported a usable OpenCode URL")
		assert(notices[#notices]:match("Could not start OpenCode"), "Failed OpenCode startup had no clear error")
		fail_spawn = false
		assert(manager.endpoint("opencode") ~= nil, "OpenCode could not retry after failed startup")
		project.set(roots[1])
		assert(manager.endpoint("opencode") == url_a, "Project B failure replaced project A's endpoint")
		project.set(roots[2])

		project.set(roots[1])
		package.loaded["user.core.ai"] = nil
		vim.g.user_ai_provider = "codex"
		ai = require("user.core.ai")
		local input_callback, provider_callback
		vim.ui.input = function(_, callback)
			input_callback = callback
		end
		ai.attach_file()
		project.set(roots[2])
		local write_count = #writes
		input_callback("relative.txt")
		assert(#writes == write_count and notices[#notices]:match("cancelled"), "AI file input crossed projects")
		project.set(roots[1])
		vim.ui.select = function(_, _, callback)
			provider_callback = callback
		end
		ai.pick()
		project.set(roots[2])
		provider_callback("claude")
		assert(vim.g.user_ai_provider == "codex", "Pending provider selection switched the new project's provider")

		local claude_buffer = vim.api.nvim_create_buf(false, true)
		vim.b[claude_buffer].user_project_root = roots[1]
		local claude_sends = 0
		package.loaded["claudecode.terminal"] = {
			get_active_terminal_bufnr = function()
				return claude_buffer
			end,
			send_to_terminal = function()
				claude_sends = claude_sends + 1
				return true
			end,
		}
		package.loaded["user.core.ai"] = nil
		vim.g.user_ai_provider = "claude"
		ai = require("user.core.ai")
		ai.interrupt()
		ai.add_buffer()
		assert(
			claude_sends == 0 and notices[#notices]:find(roots[1], 1, true),
			"Claude accepted an action from another project"
		)
		project.set(roots[1])
		ai.interrupt()
		assert(claude_sends == 1, "Returning to Claude's owner did not restore operation")
	end, debug.traceback)
	vim.uv.new_tcp = saved.new_tcp
	vim.fn.executable = saved.executable
	vim.api.nvim_chan_send = saved.chan_send
	vim.notify = saved.notify
	vim.ui.select = saved.select
	vim.ui.input = saved.input
	package.loaded["toggleterm.terminal"] = saved.terminal
	package.loaded["user.core.ai"] = saved.ai
	package.loaded.lazy = saved.lazy
	package.loaded["claudecode.terminal"] = saved.claude
	package.loaded.opencode = saved.opencode
	package.loaded["opencode.server"] = saved.server
	package.loaded["opencode.config"] = saved.opencode_config
	assert(ok, err)
end
