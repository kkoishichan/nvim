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
		executable = vim.fn.executable,
		chan_send = vim.api.nvim_chan_send,
		notify = vim.notify,
		select = vim.ui.select,
		input = vim.ui.input,
	}
	local registry, writes, notices = {}, {}, {}
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
			pi = { label = "Pi", command = "pi", count = 202 },
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

		fail_spawn = true
		assert(manager.open("codex", true) == nil, "Failed startup reported a usable Codex terminal")
		assert(notices[#notices]:match("Could not open Codex"), "Failed Codex startup had no clear error")
		fail_spawn = false
		local restarted_a = manager.open("codex", true)
		assert(restarted_a and restarted_a ~= codex_a, "Codex could not restart after failure")
		assert(manager.channel("codex") == restarted_a.job_id, "Restarted Codex lost its channel")
		project.set(roots[2])
		assert(manager.channel("codex") == codex_b.job_id, "Project A failure replaced project B's terminal")

		local pi_b = manager.open("pi", true)
		assert(pi_b.cmd == "pi" and pi_b.dir == roots[2], "Pi launched the wrong CLI or project")
		assert(pi_b.id ~= codex_b.id and not codex_b:is_open(), "Pi collided with Codex's terminal or panel")
		assert(vim.b[pi_b.bufnr].user_ai_terminal.provider == "pi", "Pi terminal lost its docking marker")
		local docks = dofile(config_root .. "/lua/user/plugins/edgy.lua")[1].opts
		local pi_dock
		for _, dock in ipairs(docks.right) do
			if dock.title == "Pi" then
				pi_dock = dock
			end
		end
		assert(pi_dock and pi_dock.filter(pi_b.bufnr), "Pi was not recognized by the right dock")
		assert(not pi_dock.filter(codex_b.bufnr), "Pi dock adopted another AI provider")
		assert(not docks.bottom[1].filter(pi_b.bufnr, pi_b.window), "Pi was also docked as an ordinary terminal")
		local pi_write_count = #writes
		manager.send("pi", "B context")
		project.set(roots[1])
		local pi_a = manager.open("pi", true)
		assert(pi_a ~= pi_b and pi_a.dir == roots[1], "Pi reused another project's process")
		assert(
			vim.wait(500, function()
				return #writes == pi_write_count + 1
			end),
			"Deferred Pi context was not sent"
		)
		assert(writes[#writes].channel == pi_b.job_id, "Deferred Pi context crossed projects")
		assert(new_manager().channel("pi") == pi_a.job_id, "AI reload lost Pi ownership")
		project.set(roots[2])
		assert(manager.open("pi", true) == pi_b, "Returning to Pi's project did not reuse its process")

		project.set(roots[1])
		package.loaded["user.core.ai"] = nil
		vim.g.user_ai_provider = "codex"
		local ai = require("user.core.ai")
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
	vim.fn.executable = saved.executable
	vim.api.nvim_chan_send = saved.chan_send
	vim.notify = saved.notify
	vim.ui.select = saved.select
	vim.ui.input = saved.input
	package.loaded["toggleterm.terminal"] = saved.terminal
	package.loaded["user.core.ai"] = saved.ai
	package.loaded.lazy = saved.lazy
	package.loaded["claudecode.terminal"] = saved.claude
	assert(ok, err)
end
