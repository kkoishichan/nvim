return function(tmp)
	local api = vim.api
	local buffers = require("user.core.buffers")
	local roles = require("user.core.window_roles")
	local saved = { select = vim.ui.select, input = vim.ui.input, notify = vim.notify }
	local choices, inputs, notices = {}, {}, {}
	vim.ui.select = function(items, opts, callback)
		table.insert(choices, { items = items, opts = opts, callback = callback })
	end
	vim.ui.input = function(opts, callback)
		table.insert(inputs, { opts = opts, callback = callback })
	end
	vim.notify = function(message)
		table.insert(notices, message)
	end
	local function file(name, lines)
		local path = tmp .. "/" .. name
		vim.fn.writefile(lines or { name }, path)
		local bufnr = vim.fn.bufadd(path)
		vim.fn.bufload(bufnr)
		vim.bo[bufnr].buflisted = true
		return bufnr, path
	end
	local function layout()
		local result = {}
		for _, tab in ipairs(api.nvim_list_tabpages()) do
			result[tab] = vim.fn.winlayout(api.nvim_tabpage_get_number(tab))
		end
		return result
	end
	local function decide(choice)
		local question = table.remove(choices, 1)
		assert(question, "No close choice was offered")
		assert(vim.deep_equal(question.items, { "Save", "Discard", "Cancel" }), "Close choices were not explicit")
		question.callback(choice)
	end
	local function float(bufnr, width, height, padded)
		local config =
			{ relative = "editor", row = 1, col = 1, width = width or 20, height = height or 4, style = "minimal" }
		if padded then
			config = require("user.core.float_style").padded(config)
		end
		return api.nvim_open_win(bufnr, false, config)
	end
	local function reset()
		vim.cmd("silent! tabonly!")
		for _, winid in ipairs(api.nvim_tabpage_list_wins(0)) do
			if api.nvim_win_get_config(winid).relative ~= "" then
				api.nvim_win_close(winid, true)
			end
		end
		vim.cmd("silent! only!")
		roles.mark(api.nvim_get_current_win(), nil)
		vim.wo.winfixbuf = false
		local clean = api.nvim_create_buf(true, false)
		api.nvim_win_set_buf(0, clean)
		for _, bufnr in ipairs(api.nvim_list_bufs()) do
			if bufnr ~= clean then
				pcall(api.nvim_buf_delete, bufnr, { force = true })
			end
		end
	end
	local ok, err = xpcall(function()
		reset()
		local first = file("first.txt")
		local second = file("second.txt")
		api.nvim_win_set_buf(0, second)
		api.nvim_win_set_buf(0, first)
		local original = api.nvim_get_current_win()
		vim.cmd("vsplit")
		local right = api.nvim_get_current_win()
		vim.wo[right].winfixbuf = true
		vim.cmd("split")
		local bottom = api.nvim_get_current_win()
		api.nvim_win_set_buf(bottom, second)
		vim.cmd("tab split")
		local other_tab = api.nvim_get_current_tabpage()
		api.nvim_win_set_buf(0, first)
		local remote = api.nvim_get_current_win()
		vim.cmd("tabprevious")
		api.nvim_set_current_win(original)
		local before = layout()
		assert(buffers.close(first) == true, "Unmodified buffer did not close")
		assert(vim.deep_equal(before, layout()), "Closing a shared buffer changed split or tab layout")
		for _, winid in ipairs({ original, right, remote }) do
			assert(api.nvim_win_get_buf(winid) == second, "A shared window did not receive a replacement buffer")
		end
		assert(
			api.nvim_get_current_win() == original and api.nvim_get_current_tabpage() ~= other_tab,
			"Close stole window or tab focus"
		)
		assert(vim.wo[right].winfixbuf, "Close lost winfixbuf on an editing window")
		assert(not api.nvim_buf_is_valid(first), "Closed buffer is still valid")

		reset()
		local only = file("only.txt")
		api.nvim_win_set_buf(0, only)
		for _, bufnr in ipairs(api.nvim_list_bufs()) do
			if bufnr ~= only then
				api.nvim_buf_delete(bufnr, { force = true })
			end
		end
		vim.cmd("vsplit")
		before = layout()
		assert(buffers.close(only), "The last listed buffer could not close")
		assert(vim.deep_equal(before, layout()), "Closing the last buffer collapsed splits")
		local blank = api.nvim_get_current_buf()
		assert(
			vim.bo[blank].buflisted and vim.bo[blank].buftype == "" and api.nvim_buf_get_name(blank) == "",
			"Last buffer did not leave a normal blank editor"
		)

		reset()
		local hidden, hidden_path = file("hidden.txt", { "disk" })
		api.nvim_buf_set_lines(hidden, 0, -1, false, { "edited" })
		local displayed = api.nvim_get_current_buf()
		before = layout()
		assert(buffers.close(hidden) == nil, "A modified hidden buffer closed without a choice")
		decide("Cancel")
		assert(api.nvim_buf_is_valid(hidden) and vim.bo[hidden].modified, "Cancel lost hidden edits")
		assert(
			vim.deep_equal(before, layout()) and api.nvim_get_current_buf() == displayed,
			"Hidden cancel changed the editor"
		)
		buffers.close(hidden)
		decide("Save")
		assert(not api.nvim_buf_is_valid(hidden), "Saved hidden buffer did not close")
		assert(
			vim.deep_equal(vim.fn.readfile(hidden_path), { "edited" }),
			"Save did not write the chosen hidden buffer"
		)
		assert(
			vim.deep_equal(before, layout()) and api.nvim_get_current_buf() == displayed,
			"Saving a hidden buffer changed focus or layout"
		)

		local discard, discard_path = file("discard.txt", { "disk" })
		api.nvim_win_set_buf(0, discard)
		api.nvim_buf_set_lines(discard, 0, -1, false, { "unsaved" })
		before = layout()
		buffers.close(discard)
		decide("Discard")
		assert(
			not api.nvim_buf_is_valid(discard) and vim.deep_equal(vim.fn.readfile(discard_path), { "disk" }),
			"Discard wrote or retained the edited buffer"
		)
		assert(vim.deep_equal(before, layout()), "Discard collapsed an editing window")

		local changed = file("changed.txt")
		api.nvim_buf_set_lines(changed, 0, -1, false, { "first edit" })
		buffers.close(changed)
		api.nvim_buf_set_lines(changed, 0, -1, false, { "newer edit" })
		decide("Discard")
		assert(api.nvim_buf_is_valid(changed) and vim.bo[changed].modified, "Stale Discard erased newer edits")
		assert(notices[#notices]:find("changed", 1, true), "Stale close did not explain why it stopped")
		local queued = file("queued.txt")
		api.nvim_buf_set_lines(queued, 0, -1, false, { "queued edit" })
		buffers.close(changed)
		buffers.close(queued)
		assert(#choices == 1, "Bulk close opened overlapping unsaved prompts")
		decide("Cancel")
		assert(#choices == 1 and api.nvim_buf_is_valid(changed), "Queued close lost cancellation or its next choice")
		decide("Discard")
		assert(not api.nvim_buf_is_valid(queued), "Queued Discard did not complete")
		local leave_changed = file("leave-changed.txt")
		api.nvim_win_set_buf(0, leave_changed)
		api.nvim_create_autocmd("BufLeave", {
			buffer = leave_changed,
			once = true,
			callback = function()
				api.nvim_buf_set_lines(leave_changed, 0, -1, false, { "late edit" })
			end,
		})
		assert(buffers.close(leave_changed) == false, "Close discarded a BufLeave edit")
		assert(
			api.nvim_get_current_buf() == leave_changed and vim.bo[leave_changed].modified,
			"Failed close did not restore the editing window"
		)

		local unnamed = api.nvim_create_buf(true, false)
		api.nvim_buf_set_lines(unnamed, 0, -1, false, { "new file" })
		buffers.close(unnamed)
		decide("Save")
		local input = table.remove(inputs, 1)
		assert(input and input.opts.completion == "file", "Unnamed Save did not ask for a filename")
		local saved_path = tmp .. "/new file.txt"
		input.callback(saved_path)
		assert(
			not api.nvim_buf_is_valid(unnamed) and vim.deep_equal(vim.fn.readfile(saved_path), { "new file" }),
			"Unnamed Save failed"
		)
		local failed_save = file("save-failure.txt")
		api.nvim_buf_set_name(failed_save, tmp .. "/missing/directory/file.txt")
		api.nvim_buf_set_lines(failed_save, 0, -1, false, { "do not lose" })
		buffers.close(failed_save)
		decide("Save")
		assert(api.nvim_buf_is_valid(failed_save) and vim.bo[failed_save].modified, "Failed Save lost edits")

		reset()
		local body = file("body.txt")
		api.nvim_win_set_buf(0, body)
		local editor = api.nvim_get_current_win()
		vim.cmd("botright split")
		local panel = api.nvim_get_current_win()
		local panelbuf = api.nvim_create_buf(false, true)
		vim.bo[panelbuf].filetype = "OverseerList"
		api.nvim_win_set_buf(panel, panelbuf)
		api.nvim_set_current_win(editor)
		before = layout()
		assert(buffers.close(body), "Editor buffer beside a fixed panel could not close")
		assert(
			vim.deep_equal(before, layout()) and api.nvim_win_get_buf(panel) == panelbuf,
			"Closing an editor altered its fixed panel"
		)
		assert(
			buffers.close(panelbuf) == false and api.nvim_win_is_valid(panel),
			"Generic close deleted a managed panel"
		)

		reset()
		local scratch = api.nvim_create_buf(false, true)
		local small = float(scratch)
		local padded = float(api.nvim_create_buf(false, true), 20, 4, true)
		local modified_buf = api.nvim_create_buf(false, true)
		api.nvim_buf_set_lines(modified_buf, 0, -1, false, { "unsaved notes" })
		local modified = float(modified_buf)
		local named = file("floating-file.txt")
		vim.bo[named].modifiable = false
		local named_win = float(named)
		local locked_buf = api.nvim_create_buf(true, false)
		api.nvim_buf_set_lines(locked_buf, 0, -1, false, { "edited before locking" })
		vim.bo[locked_buf].modifiable = false
		local locked = float(locked_buf)
		for _, winid in ipairs({ small, padded, modified, named_win, locked }) do
			assert(roles.get(winid) == "editor_float", "An editing float was classified by size or border")
		end
		local native_buf, native = vim.lsp.util.open_floating_preview(
			{ "native hover text" },
			"plaintext",
			{ border = "rounded", close_events = {} }
		)
		assert(
			not vim.bo[native_buf].modifiable and roles.is_transient(native),
			"Native hover was not classified as transient"
		)
		assert(require("user.core.popups").close(), "Escape did not find a native preview")
		assert(not api.nvim_win_is_valid(native), "Escape did not close native hover")
		for _, winid in ipairs({ small, padded, modified, named_win, locked }) do
			assert(api.nvim_win_is_valid(winid), "Escape closed an editing float")
		end
		assert(api.nvim_buf_get_lines(modified_buf, 0, -1, false)[1] == "unsaved notes", "Escape lost floating edits")
		local ns = api.nvim_create_namespace("user_windows_diagnostic")
		vim.diagnostic.set(ns, 0, { { lnum = 0, col = 0, message = "fixture diagnostic" } })
		local _, diagnostic = vim.diagnostic.open_float(0, { scope = "buffer", focus = false, close_events = {} })
		assert(diagnostic and roles.is_transient(diagnostic), "Native diagnostics were not transient")
		require("user.core.popups").close()
		assert(not api.nvim_win_is_valid(diagnostic), "Escape did not close native diagnostics")
		local manager_buf = api.nvim_create_buf(false, true)
		vim.bo[manager_buf].filetype = "lazy"
		local manager = float(manager_buf)
		assert(roles.get(manager) == "manager" and roles.is_panel(manager), "Manager role was inconsistent")
		local chrome = float(api.nvim_create_buf(false, true))
		vim.w[chrome].treesitter_context = true
		assert(roles.get(chrome) == "chrome" and not roles.is_editor(chrome), "Editor chrome was misclassified")
		require("user.core.popups").close()
		assert(api.nvim_win_is_valid(manager) and api.nvim_win_is_valid(chrome), "Escape dismissed persistent UI")
	end, debug.traceback)
	vim.ui.select, vim.ui.input, vim.notify = saved.select, saved.input, saved.notify
	assert(ok, err)
end
