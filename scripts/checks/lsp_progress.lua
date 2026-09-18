return function()
	local api, progress = vim.api, require("user.core.lsp_progress")
	local cleanup_key = "_user_lsp_progress_cleanup"
	if vim[cleanup_key] then
		vim[cleanup_key]()
	end
	local native = {
		new_timer = vim.uv.new_timer,
		hrtime = vim.uv.hrtime,
		get_client = vim.lsp.get_client_by_id,
		schedule_wrap = vim.schedule_wrap,
		defer_fn = vim.defer_fn,
	}
	local now, sequence, dismissals = 0, 0, 0
	local timers, deferred, notices = {}, {}, {}
	local clients = {
		[90001] = { id = 90001, name = "basedpyright" },
		[90002] = { id = 90002, name = "other-lsp" },
	}
	local function notify(message, level, opts)
		sequence = sequence + 1
		local record = { id = sequence }
		notices[#notices + 1] = { message = message, level = level, opts = opts, record = record }
		return record
	end
	local function setup()
		progress.setup(notify, function()
			dismissals = dismissals + 1
		end)
	end
	local function send(token, kind, fields, client)
		api.nvim_exec_autocmds("LspProgress", {
			group = "user_lsp_progress_notify",
			data = {
				client_id = client or 90001,
				params = { token = token, value = vim.tbl_extend("force", fields or {}, { kind = kind }) },
			},
		})
	end
	local function last()
		return assert(notices[#notices], "No progress notification was emitted")
	end
	local function advance(ms)
		now = now + ms
		for _, timer in ipairs(timers) do
			if timer.active and timer.due <= now then
				timer.due = now + timer.interval
				timer.callback()
			end
		end
		for _, pending in ipairs(deferred) do
			if not pending.ran and pending.due <= now then
				pending.ran = true
				pending.callback()
			end
		end
	end
	local function idle()
		for _, timer in ipairs(timers) do
			assert(not timer.active, "Progress timer kept running without work")
		end
	end
	vim.uv.hrtime = function()
		return now * 1e6
	end
	vim.uv.new_timer = function()
		local timer = { active = false, closed = false }
		function timer:start(delay, interval, callback)
			assert(not self.closed, "A closed progress timer was restarted")
			self.active, self.due, self.interval, self.callback = true, now + delay, interval, callback
		end
		function timer:stop()
			self.active = false
		end
		function timer:is_closing()
			return self.closed
		end
		function timer:close()
			self.closed, self.active = true, false
		end
		timers[#timers + 1] = timer
		return timer
	end
	vim.lsp.get_client_by_id = function(id)
		return clients[id]
	end
	vim.schedule_wrap = function(callback)
		return callback
	end
	vim.defer_fn = function(callback, delay)
		deferred[#deferred + 1] = { callback = callback, due = now + delay }
	end
	local ok, err = xpcall(function()
		setup()
		for token = 1, 200 do
			send(token, "begin", { title = "Analysis" })
			send(token, "report", { message = "1 file to analyze" })
			advance(20)
			send(token, "end")
		end
		advance(1000)
		assert(#notices == 0, "Short editing checks created notifications/history")
		assert(#timers == 1 and #deferred == 0, "Short checks allocated per-task timers or callbacks")
		idle()
		send("orphan", "end")
		assert(#notices == 0, "An unobserved task completion flashed 100%")

		-- Overlapping short tasks may keep a client busy indefinitely. Each
		-- token must earn its own delay rather than inheriting the client's age.
		for _ = 1, 10 do
			send("a", "begin")
			advance(300)
			send("b", "begin", {}, 90002)
			send("c", "begin")
			advance(100)
			send("a", "end")
			advance(300)
			send("b", "end", {}, 90002)
			send("c", "end")
		end
		assert(#notices == 0, "Overlapping short tasks accumulated into visible progress")
		idle()

		send("long", "begin", { title = "Indexing", percentage = 10 })
		advance(300)
		send("long", "report", { percentage = 30, message = "workspace" })
		advance(199)
		assert(#notices == 0, "A task appeared before 500 ms")
		advance(1)
		assert(#notices == 1 and last().message == "[ 30%] Indexing workspace", "Delayed progress lost metadata")
		assert(
			last().opts.timeout == false and last().opts.hide_from_history,
			"Active progress is not persistent/hidden"
		)
		local first = last()
		for percentage = 31, 90 do
			send("long", "report", { percentage = percentage })
		end
		assert(#notices == 1, "Intermediate reports bypassed the spinner throttle")
		advance(250)
		assert(#notices == 2 and last().message == "[ 90%] Indexing workspace", "Spinner lost the latest report")
		assert(last().opts.replace == first.record and last().opts.animate == false, "Spinner recreated its popup")
		local second = last()
		first.opts.on_close()
		send("long", "end")
		assert(last().opts.replace == second.record, "A stale close callback discarded a newer notification")
		assert(last().message == "[100%] Indexing workspace", "Completion lost the original task metadata")
		assert(
			last().opts.timeout == 1200 and not last().opts.hide_from_history,
			"Visible task did not finish normally"
		)
		idle()

		-- A completed visible notification must not make subsequent short tasks
		-- visible, even when the server reuses the same token immediately.
		local count = #notices
		send("long", "begin", { title = "Analysis" })
		advance(100)
		send("long", "end")
		assert(#notices == count, "A short task inherited an old completion window")

		send("visible", "begin", { title = "Symbols" })
		advance(500)
		local visible = last()
		send("hidden", "begin", { title = "Tiny" })
		advance(100)
		send("visible", "end")
		assert(last().opts.timeout == 1200 and last().message:find("Symbols"), "A hidden sibling held the spinner open")
		assert(not last().message:find("Tiny"), "A short sibling leaked into the notification")
		count = #notices
		send("hidden", "end")
		assert(#notices == count, "A hidden sibling created a completion popup")
		visible.opts.on_close()

		-- Visible concurrent work is retained when another task completes.
		send("one", "begin", { title = "One" })
		send("two", "begin", { title = "Two" })
		advance(500)
		assert(last().message:find("One") and last().message:find("Two"), "Concurrent tasks were not combined")
		send("one", "end")
		assert(last().opts.timeout == false and last().message:find("Two"), "Completing one task closed its sibling")
		assert(not last().message:find("One"), "A finished task stayed in active progress")
		send("two", "end")
		idle()

		-- Client exit closes shown progress but cannot surface an unseen task.
		send("exit-visible", "begin", { title = "Exit" }, 90002)
		advance(500)
		clients[90002] = nil
		advance(250)
		assert(last().opts.title == "other-lsp" and last().opts.timeout == 1200, "Client exit left a persistent popup")
		idle()
		clients[90002] = { id = 90002, name = "other-lsp" }
		send("exit-hidden", "begin", {}, 90002)
		clients[90002] = nil
		count = #notices
		advance(500)
		assert(#notices == count, "Client exit showed an unseen task")
		idle()

		advance(1300)
		local dismissed = dismissals
		send("reload-hidden", "begin")
		local old_timer = timers[#timers]
		local old_callback = old_timer.callback
		package.loaded["user.core.lsp_progress"] = nil
		progress = require("user.core.lsp_progress")
		setup()
		assert(old_timer.closed and dismissals == dismissed, "Reloading unseen work dismissed unrelated notifications")
		old_callback()
		advance(1000)
		assert(#notices == count, "An obsolete spinner callback survived reload")
		send("reload-visible", "begin")
		advance(500)
		local stale = last()
		old_timer = timers[#timers]
		setup()
		assert(old_timer.closed and dismissals == dismissed + 1, "Reload did not dismiss owned progress")
		stale.opts.on_close()
		send("after-reload", "begin")
		advance(500)
		send("after-reload", "end")
		assert(last().opts.timeout == 1200, "Old callbacks broke new progress ownership")
		assert(
			#api.nvim_get_autocmds({ group = "user_lsp_progress_notify" }) == 2,
			"Reload duplicated progress handlers"
		)
		vim[cleanup_key]()
		idle()
	end, debug.traceback)
	if vim[cleanup_key] then
		vim[cleanup_key]()
	end
	vim.uv.new_timer, vim.uv.hrtime = native.new_timer, native.hrtime
	vim.lsp.get_client_by_id = native.get_client
	vim.schedule_wrap, vim.defer_fn = native.schedule_wrap, native.defer_fn
	assert(ok, err)

	-- Also exercise actual libuv scheduling and nvim-notify replacement/close
	-- handling; the deterministic clock above only isolates timing boundaries.
	require("lazy").load({ plugins = { "nvim-notify" } })
	local real_notify = require("notify")
	local real_count = 0
	vim.lsp.get_client_by_id = function(id)
		return clients[id] or native.get_client(id)
	end
	progress.setup(function(message, level, opts)
		real_count = real_count + 1
		return real_notify(message, level, opts)
	end, function()
		real_notify.dismiss({ pending = true, silent = true })
	end)
	send("actual-short", "begin")
	send("actual-short", "end")
	assert(real_count == 0, "Real notifier received a short task")
	send("actual-long", "begin", { title = "Indexing" })
	assert(
		vim.wait(1100, function()
			return real_count > 0
		end, 10),
		"Real timer never displayed long progress"
	)
	send("actual-long", "end")
	local history = real_notify.history()
	assert(history[#history].message[1]:find("100%%"), "Real notification history lost the visible completion")
	vim[cleanup_key]()
	vim.lsp.get_client_by_id = native.get_client
	print(
		"LSP progress: 200 short checks silent; delayed/overlapping tasks, client exit, reload and real notifier passed"
	)
end
