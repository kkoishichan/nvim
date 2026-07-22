local M = {}

function M.setup(notify, dismiss_notifications)
	local lifecycle_key = "_user_lsp_progress_cleanup"
	local previous_cleanup = rawget(vim, lifecycle_key)
	if type(previous_cleanup) == "function" then
		pcall(previous_cleanup)
	end

	local spinner = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
	local spinner_interval = 120
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
		local owns_notification = next(records) ~= nil
		if not owns_notification then
			for _, items in pairs(progress) do
				if #items > 0 then
					owns_notification = true
					break
				end
			end
		end
		if owns_notification and dismiss_notifications then
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
			timeout = active and false or 1200,
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

		for client_id, items in pairs(progress) do
			if #items > 0 then
				local client = vim.lsp.get_client_by_id(client_id)
				if client then
					notify_client_progress(client, items, items)
				else
					-- A client may exit without sending an `end` event. Finish its
					-- notification and remove its work so the spinner timer can stop.
					progress[client_id] = nil
					notify_client_progress({
						id = client_id,
						name = client_names[client_id] or "LSP",
					}, {}, items)
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
		timer:start(0, spinner_interval, vim.schedule_wrap(redraw_spinner))
	end

	local progress_group = vim.api.nvim_create_augroup("user_lsp_progress_notify", { clear = true })
	vim.api.nvim_create_autocmd("LspProgress", {
		group = progress_group,
		callback = function(event)
			local client = vim.lsp.get_client_by_id(event.data.client_id)
			local params = event.data.params
			local value = params and params.value
			if not client or type(value) ~= "table" then
				return
			end
			client_names[client.id] = client.name

			local client_progress = progress[client.id] or {}
			progress[client.id] = client_progress

			local percentage = value.kind == "end" and 100 or value.percentage or 0
			local title = value.title or "Working"
			local message = value.message and (" " .. value.message) or ""
			local progress_item = {
				token = params.token,
				message = ("[%3d%%] %s%s"):format(percentage, title, message),
				done = value.kind == "end",
			}

			local updated = false
			for index, item in ipairs(client_progress) do
				if item.token == params.token then
					client_progress[index] = progress_item
					updated = true
					break
				end
			end
			if not updated then
				table.insert(client_progress, progress_item)
			end

			local done_items = {}
			local active_items = {}
			for _, item in ipairs(client_progress) do
				table.insert(done_items, item)
				if not item.done then
					table.insert(active_items, item)
				end
			end

			progress[client.id] = #active_items > 0 and active_items or nil
			notify_client_progress(client, active_items, done_items)
			if #active_items == 0 then
				client_names[client.id] = nil
			end

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
