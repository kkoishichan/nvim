return function(tmp)
	assert(not package.loaded["user.core.pdf_preview"], "PDF renderer loaded during ordinary startup")
	assert(package.loaded["user.core.pdf_registration"], "PDF entry point was not registered")
	assert(vim.fn.exists(":PdfOpen") == 2, "External PDF command is missing")
	local cache = vim.fs.joinpath(vim.fn.stdpath("cache"), "user", "pdf-preview")
	vim.fn.mkdir(cache, "p")
	local expired = cache .. "/expired.png"
	vim.fn.writefile({ "old" }, expired)
	assert(vim.uv.fs_utime(expired, 1, 1))
	vim.wait(1100, function()
		return false
	end, 50)
	assert(vim.uv.fs_stat(expired), "Ordinary startup scanned/pruned the PDF cache")

	-- Only process completion and terminal image drawing are simulated here.
	-- The real Poppler build/render/watcher flow is in workflow_java_docs.
	local system, executable, list_uis = vim.system, vim.fn.executable, vim.api.nvim_list_uis
	local old_image, old_lualine = package.loaded.image, package.loaded.lualine
	local terminal =
		{ TERM = vim.env.TERM, TERM_PROGRAM = vim.env.TERM_PROGRAM, KITTY_WINDOW_ID = vim.env.KITTY_WINDOW_ID }
	vim.env.TERM, vim.env.TERM_PROGRAM, vim.env.KITTY_WINDOW_ID = "xterm-kitty", nil, nil
	local missing = {}
	vim.fn.executable = function(name)
		if missing[name] then
			return 0
		end
		if vim.tbl_contains({ "pdftoppm", "pdfinfo", "magick" }, name) then
			return 1
		end
		return executable(name)
	end
	vim.api.nvim_list_uis = function()
		return { { width = 100, height = 40 } }
	end
	local drawings = {}
	package.loaded.image = {
		from_file = function(path, opts)
			local drawing = { id = opts.id, path = path, cleared = false }
			function drawing:render()
				self.rendered = true
			end
			function drawing:clear()
				self.cleared = true
			end
			drawings[#drawings + 1] = drawing
			return drawing
		end,
		clear = function() end,
	}
	package.loaded.lualine = { refresh = function() end, setup = function() end }
	local jobs = {}
	vim.system = function(cmd, opts, callback)
		if cmd[1] ~= "pdfinfo" and cmd[1] ~= "pdftoppm" then
			return system(cmd, opts, callback)
		end
		local job = { cmd = cmd, callback = callback }
		function job:kill(signal)
			self.killed = signal
		end
		jobs[#jobs + 1] = job
		return job
	end
	local function settle()
		vim.wait(25, function()
			return false
		end, 5)
	end
	local function finish(job, output)
		assert(not job.finished, "Test completed a process twice")
		job.finished = true
		if job.cmd[1] == "pdftoppm" then
			vim.fn.writefile({ output or "PNG" }, job.cmd[#job.cmd] .. ".png")
			job.callback({ code = 0, stdout = "", stderr = "" })
		else
			job.callback({ code = 0, stdout = "Pages: " .. (output or "2") .. "\n", stderr = "" })
		end
	end
	local function latest(command)
		for index = #jobs, 1, -1 do
			if jobs[index].cmd[1] == command then
				return jobs[index]
			end
		end
		error("No " .. command .. " process")
	end
	local function refresh(bufnr)
		for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
			if mapping.lhs == "r" then
				mapping.callback()
				return
			end
		end
		error("PDF refresh mapping is missing")
	end
	local file = vim.fs.joinpath(tmp, "preview.pdf")
	vim.fn.writefile({ "%PDF-1.4 lifecycle fixture" }, file)
	vim.cmd.edit(vim.fn.fnameescape(file))
	settle()
	local bufnr = vim.api.nvim_get_current_buf()
	assert(package.loaded["user.core.pdf_preview"], "First PDF did not load its renderer")
	assert(vim.bo[bufnr].filetype == "pdf" and vim.bo[bufnr].buftype == "nofile", "PDF buffer contract changed")
	local old_info, old_render = latest("pdfinfo"), latest("pdftoppm")
	local old_context = rawget(vim, "_user_core_autocmds_lifecycle")
	local handles = vim.tbl_keys(old_context.handles)
	assert(#handles >= 2, "PDF watcher and deferred prune were not tracked")
	refresh(bufnr)
	assert(latest("pdftoppm") == old_render, "Repeated render started a duplicate converter")
	local input, pending_input = vim.ui.input, nil
	vim.ui.input = function(_, callback)
		pending_input = callback
	end
	for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
		if mapping.lhs == "g" then
			mapping.callback()
		end
	end
	vim.ui.input = input
	assert(pending_input, "PDF page prompt did not open")
	package.loaded["user.core.autocmds"] = nil
	require("user.core.autocmds")
	settle()
	assert(old_context.closed, "Reload did not close the prior lifecycle")
	pending_input("2")
	assert(vim.b[bufnr].pdf_preview_page == 1, "Late page prompt mutated the reloaded PDF")
	for _, handle in ipairs(handles) do
		assert(handle:is_closing(), "Reload leaked a prior libuv handle")
	end
	assert(old_info.killed == 15 and old_render.killed == 15, "Reload did not cancel PDF child processes")
	local new_info, new_render = latest("pdfinfo"), latest("pdftoppm")
	assert(new_info ~= old_info and new_render ~= old_render, "Reload failed to reattach the surviving PDF")
	assert(
		new_render.cmd[#new_render.cmd] ~= old_render.cmd[#old_render.cmd],
		"Render generations share a partial output path"
	)
	local registrations = vim.api.nvim_get_autocmds({ group = "user_pdf_preview", event = "BufReadCmd" })
	assert(#registrations == 2, "Reload duplicated the PDF read handlers")

	finish(new_info, "2")
	finish(new_render, "NEW")
	settle()
	assert(vim.b[bufnr].pdf_preview_pages == 2, "Fresh page count was not applied")
	assert(#drawings > 0 and drawings[#drawings].rendered, "Fresh render did not draw")
	local published = drawings[#drawings].path
	assert(vim.fn.readfile(published)[1] == "NEW", "Completed render was not published")
	finish(old_info, "99")
	finish(old_render, "STALE")
	settle()
	assert(vim.b[bufnr].pdf_preview_pages == 2, "Late page-count result overwrote the new generation")
	assert(vim.fn.readfile(published)[1] == "NEW", "Canceled converter overwrote the current cache image")
	assert(
		not vim.uv.fs_stat(old_render.cmd[#old_render.cmd] .. ".png"),
		"Late canceled converter left a partial image"
	)

	-- Reloading only pdf_preview must be as safe as re-sourcing all autocmds.
	-- Reuse one owner context exactly as an embedding caller would.
	local owner = rawget(vim, "_user_core_autocmds_lifecycle")
	local context = {
		lifecycle = owner,
		augroup = function(name)
			return vim.api.nvim_create_augroup("user_" .. name, { clear = true })
		end,
		track_uv_handle = function(handle)
			owner.handles[handle] = true
			return handle
		end,
		release_uv_handle = function(handle)
			if handle and not handle:is_closing() then
				handle:stop()
				handle:close()
			end
			owner.handles[handle] = nil
		end,
		add_cleanup = function(callback)
			table.insert(owner.cleanup_callbacks, callback)
		end,
	}
	local cleanups = #owner.cleanup_callbacks
	local first_api = require("user.core.pdf_preview").setup(context)
	settle()
	refresh(bufnr)
	local module_info, module_render = latest("pdfinfo"), latest("pdftoppm")
	package.loaded["user.core.pdf_preview"] = nil
	require("user.core.pdf_preview").setup(context)
	settle()
	assert(not first_api.is_active(), "Module-only reload left the old generation active")
	assert(module_info.killed == 15 and module_render.killed == 15, "Module-only reload leaked a process")
	assert(#owner.cleanup_callbacks == cleanups, "Repeated PDF setup accumulated cleanup callbacks")
	new_info, new_render = latest("pdfinfo"), latest("pdftoppm")
	finish(new_info, "2")
	finish(new_render, "MODULE_NEW")
	settle()
	finish(module_info, "98")
	finish(module_render, "MODULE_STALE")
	settle()
	assert(vim.b[bufnr].pdf_preview_pages == 2, "Module-only reload accepted an old metadata response")
	assert(vim.fn.readfile(published)[1] == "MODULE_NEW", "Module-only reload accepted an old image")
	assert(
		not vim.uv.fs_stat(module_render.cmd[#module_render.cmd] .. ".png"),
		"Module-only reload leaked a partial PNG"
	)

	-- A real fs_event must debounce replacement, refresh metadata, and retain
	-- the original buffer even while another file is current.
	local before = #jobs
	vim.fn.writefile({ "%PDF-1.4 modified lifecycle fixture" }, file)
	vim.cmd.enew()
	assert(
		vim.wait(2000, function()
			return #jobs > before and latest("pdfinfo") ~= new_info
		end, 10),
		"PDF file watcher did not notice a rewrite"
	)
	local watcher_info = latest("pdfinfo")
	finish(watcher_info, "3")
	settle()
	assert(vim.b[bufnr].pdf_preview_pages == 3, "Watcher updated the current buffer instead of its PDF")
	assert(vim.b.pdf_preview_pages == nil, "PDF watcher polluted an unrelated buffer")

	local pending = {}
	for _, job in ipairs(jobs) do
		if not job.finished and not job.killed then
			pending[#pending + 1] = job
		end
	end
	assert(#pending > 0, "Close test has no pending conversion")
	local partial = pending[1].cmd[#pending[1].cmd] .. ".png"
	vim.fn.writefile({ "still converting" }, partial)
	assert(vim.uv.fs_utime(partial, 1, 1))
	assert(
		vim.wait(1500, function()
			return not vim.uv.fs_stat(expired)
		end, 20),
		"First PDF never activated deferred cache pruning"
	)
	assert(vim.uv.fs_stat(partial), "Cache pruning deleted an active converter output")
	vim.api.nvim_buf_delete(bufnr, { force = true })
	for _, job in ipairs(pending) do
		assert(job.killed == 15, "Closing PDF did not cancel an owned process")
		finish(job, "CANCELED")
	end
	settle()
	for _, drawing in ipairs(drawings) do
		assert(drawing.cleared, "Closing PDF left a rendered image")
	end
	local after_close = #jobs
	vim.fn.writefile({ "%PDF-1.4 after close" }, file)
	vim.wait(300, function()
		return false
	end, 20)
	assert(#jobs == after_close, "Closed PDF retained its watcher or prefetch timer")
	for _, path in ipairs(vim.fn.glob(cache .. "/*.part.png", false, true)) do
		error("Canceled render left a partial PNG: " .. path)
	end

	local function fallback(reason)
		local before_jobs = #jobs
		vim.cmd.edit(vim.fn.fnameescape(file))
		settle()
		local buffer = vim.api.nvim_get_current_buf()
		assert(vim.b[buffer].pdf_preview_unavailable_reason:find(reason, 1, true), "Missing PDF fallback reason")
		local content = table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n")
		assert(content:find(":PdfOpen", 1, true), "Fallback does not explain how to open externally")
		assert(vim.api.nvim_buf_line_count(buffer) < 10, "Fallback allocated the full graphics scroll area")
		for index = before_jobs + 1, #jobs do
			assert(jobs[index].cmd[1] ~= "pdftoppm", "Unavailable graphics started a conversion")
		end
		vim.api.nvim_buf_delete(buffer, { force = true })
	end
	vim.api.nvim_list_uis = function()
		return {}
	end
	fallback("attached terminal UI")
	vim.api.nvim_list_uis = function()
		return { { width = 100, height = 40 } }
	end
	vim.env.TERM = "dumb"
	fallback("Kitty-compatible")
	vim.env.TERM = "xterm-kitty"
	missing.pdftoppm = true
	fallback("Missing pdftoppm")
	missing.pdftoppm = nil

	-- The prune itself remains active after first use and honors the age limit.
	assert(
		vim.wait(1500, function()
			return not vim.uv.fs_stat(expired)
		end, 20),
		"First PDF never activated deferred cache pruning"
	)
	rawget(vim, "_user_core_autocmds_lifecycle").cleanup()
	vim.system, vim.fn.executable, vim.api.nvim_list_uis = system, executable, list_uis
	package.loaded.image, package.loaded.lualine = old_image, old_lualine
	for _, name in ipairs({ "TERM", "TERM_PROGRAM", "KITTY_WINDOW_ID" }) do
		vim.env[name] = terminal[name]
	end
end
