local M = {}

function M.setup(notify, dismiss_notifications)
	local lifecycle_key = "_user_lsp_progress_cleanup"
	local previous_cleanup = rawget(vim, lifecycle_key)
	if type(previous_cleanup) == "function" then
		pcall(previous_cleanup)
	end

	local spinner = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
	-- Progress events can be very noisy while a large workspace is indexing.
	-- A 4 Hz spinner remains legible without forcing redraws every 120 ms.
	local spinner_interval = 250
	local show_delay = 500
	local frame = 1
	local progress = {}
	local records = {}
	local record_versions = {}
	local client_names = {}
	local timer = vim.uv.new_timer()
	local spinner_running = false
	local closed = false

	local function cleanup()
		if closed then
			return
		end
		closed = true
		spinner_running = false
		-- nvim-notify only exposes a public all-windows dismiss operation.
		-- Use it only when this generation still owns a progress notification;
		-- this prevents timeout=false windows from surviving a plugin reload.
		if next(records) ~= nil and dismiss_notifications then
			pcall(dismiss_notifications)
		end
		pcall(function()
			timer:stop()
		end)
		local ok, closing = pcall(function()
			return timer:is_closing()
		end)
		if not ok or not closing then
			pcall(function()
				timer:close()
			end)
		end
		progress = {}
		records = {}
		record_versions = {}
		client_names = {}
		if rawget(vim, lifecycle_key) == cleanup then
			rawset(vim, lifecycle_key, nil)
		end
	end
	rawset(vim, lifecycle_key, cleanup)

	local function has_active_progress()
		for _, items in pairs(progress) do
			if #items > 0 then
				return true
			end
		end
		return false
	end

	local function progress_message(items)
		local lines = {}
		for _, item in ipairs(items) do
			table.insert(lines, item.message)
		end
		return table.concat(lines, "\n")
	end

	local function visible_items(items, now)
		local visible = {}
		for _, item in ipairs(items) do
			if item.shown or (now and now - item.started >= show_delay) then
				item.shown = true
				visible[#visible + 1] = item
			end
		end
		return visible
	end

	local function notify_client_progress(client, items, done_items)
		if closed then
			return
		end
		local active = #items > 0
		local message = progress_message(active and items or done_items)

		if message == "" then
			return
		end

		record_versions[client.id] = (record_versions[client.id] or 0) + 1
		local version = record_versions[client.id]
		local record
		record = notify(message, vim.log.levels.INFO, {
			title = client.name,
			icon = active and spinner[frame] or " ",
			replace = records[client.id],
			timeout = not active and 1200 or false,
			hide_from_history = active,
			animate = records[client.id] == nil,
			on_close = function()
				-- Replacement callbacks may arrive after a newer request has
				-- claimed this client. Clear only this exact record generation.
				if not closed and record_versions[client.id] == version and records[client.id] == record then
					records[client.id] = nil
					record_versions[client.id] = nil
				end
			end,
		})
		records[client.id] = record

		if not active then
			-- Keep the completion record around long enough for nvim-notify to
			-- close it, but do not let an older completion clear a newer request.
			vim.defer_fn(function()
				if not closed and record_versions[client.id] == version and records[client.id] == record then
					records[client.id] = nil
					record_versions[client.id] = nil
				end
			end, 1300)
		end
	end

	local function redraw_spinner()
		if closed then
			return
		end
		frame = frame % #spinner + 1
		local now = vim.uv.hrtime() / 1e6

		for client_id, items in pairs(progress) do
			if #items > 0 then
				local client = vim.lsp.get_client_by_id(client_id)
				if client then
					local visible = visible_items(items, now)
					notify_client_progress(client, visible, {})
				else
					-- A client may exit without sending an `end` event. Finish its
					-- notification and remove its work so the spinner timer can stop.
					progress[client_id] = nil
					notify_client_progress({
						id = client_id,
						name = client_names[client_id] or "LSP",
					}, {}, visible_items(items))
					client_names[client_id] = nil
				end
			end
		end

		if not has_active_progress() then
			timer:stop()
			spinner_running = false
		end
	end

	local function start_spinner()
		if closed or spinner_running then
			return
		end

		spinner_running = true
		-- One shared timer; short tasks do not allocate notification windows or
		-- per-task delayed callbacks. Age is tracked per token, not per client.
		timer:start(show_delay, spinner_interval, vim.schedule_wrap(redraw_spinner))
	end

	local progress_group = vim.api.nvim_create_augroup("user_lsp_progress_notify", { clear = true })
	vim.api.nvim_create_autocmd("LspProgress", {
		group = progress_group,
		callback = function(event)
			if closed then
				return
			end
			local client = vim.lsp.get_client_by_id(event.data.client_id)
			local params = event.data.params
			local value = params and params.value
			if
				not client
				or type(value) ~= "table"
				or params.token == nil
				or not (value.kind == "begin" or value.kind == "report" or value.kind == "end")
			then
				return
			end

			local client_progress = progress[client.id] or {}
			local progress_item, position
			for index, item in ipairs(client_progress) do
				if item.token == params.token then
					progress_item, position = item, index
					break
				end
			end
			-- A late completion (or one received before this listener loaded)
			-- must not create a new "100%" notification by itself.
			if not progress_item and value.kind == "end" then
				return
			end
			if not progress_item then
				progress_item = { token = params.token, started = vim.uv.hrtime() / 1e6 }
				client_progress[#client_progress + 1] = progress_item
			end
			-- Report/end payloads may omit the title, message and percentage.
			-- Retain the task's last metadata instead of replacing it with Working.
			progress_item.title = value.title or progress_item.title or "Working"
			progress_item.detail = value.message or progress_item.detail or ""
			progress_item.percentage = value.kind == "end" and 100 or value.percentage or progress_item.percentage or 0
			local title = progress_item.title ~= "" and progress_item.title or "Working"
			local detail = progress_item.detail ~= "" and (" " .. progress_item.detail) or ""
			progress_item.message = ("[%3d%%] %s%s"):format(progress_item.percentage, title, detail)

			if value.kind == "end" then
				table.remove(client_progress, position)
				if progress_item.shown then
					notify_client_progress(client, visible_items(client_progress), { progress_item })
				end
			end
			progress[client.id] = #client_progress > 0 and client_progress or nil
			client_names[client.id] = #client_progress > 0 and client.name or nil

			if has_active_progress() then
				start_spinner()
			else
				timer:stop()
				spinner_running = false
			end
		end,
	})
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = progress_group,
		once = true,
		callback = cleanup,
	})
end

return M
