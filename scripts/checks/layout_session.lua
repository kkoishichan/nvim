return function(tmp)
	local api = vim.api
	require("lazy").load({ plugins = { "edgy.nvim" } })
	local panels = require("user.core.panels")
	local roles = require("user.core.window_roles")
	local project = require("user.core.project")
	local session = require("user.core.session")
	local old_lines, old_columns = vim.o.lines, vim.o.columns
	local first = api.nvim_get_current_tabpage()
	local function blank_editor()
		vim.cmd.enew()
		local bufnr = api.nvim_get_current_buf()
		vim.bo[bufnr].bufhidden = "hide"
		roles.mark(0, "editor")
		return api.nvim_get_current_win(), bufnr
	end
	local function panel(command, filetype, side)
		vim.cmd(command)
		local win, bufnr = api.nvim_get_current_win(), api.nvim_get_current_buf()
		vim.bo[bufnr].buftype = "nofile"
		vim.bo[bufnr].filetype = filetype
		vim.bo[bufnr].bufhidden = "hide"
		roles.mark(win, "panel")
		if side == "right" then
			vim.b[bufnr].user_ai_terminal = { provider = "codex", root = tmp }
		end
		return win, bufnr
	end
	for _, size in ipairs({ { 80, 24 }, { 120, 36 }, { 180, 50 } }) do
		vim.o.columns, vim.o.lines = size[1], size[2]
		local editor = blank_editor()
		panel("topleft vnew", "neo-tree", "left")
		api.nvim_set_current_win(editor)
		panel("botright vnew", "toggleterm", "right")
		api.nvim_set_current_win(editor)
		panel("botright new", "toggleterm", "bottom")
		api.nvim_set_current_win(editor)
		panel("botright new", "trouble", "bottom")
		api.nvim_set_current_win(editor)
		vim.wait(100, function()
			return false
		end, 10)
		panels.enforce()
		assert(panels.editor_fits(), ("Panels squeezed the editor at %dx%d"):format(size[1], size[2]))
		assert(api.nvim_win_is_valid(editor), "Panel budget closed the editor")
		print(
			("Layout evidence: %dx%d viewport, %dx%d editor"):format(
				size[1],
				size[2],
				api.nvim_win_get_width(editor),
				api.nvim_win_get_height(editor)
			)
		)
		for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
			if win ~= editor then
				api.nvim_win_close(win, false)
			end
		end
	end

	vim.o.columns, vim.o.lines = 80, 24
	local editor = blank_editor()
	local protected, protected_buffer = panel("topleft vnew", "neo-tree", "left")
	vim.bo[protected_buffer].buftype = "acwrite"
	api.nvim_buf_set_lines(protected_buffer, 0, -1, false, { "unfinished panel edit" })
	vim.bo[protected_buffer].modified = true
	api.nvim_set_current_win(editor)
	panel("botright vnew", "toggleterm", "right")
	panels.enforce()
	assert(api.nvim_win_is_valid(protected) and vim.bo[protected_buffer].modified, "Budget discarded a modified panel")
	vim.bo[protected_buffer].modified = false
	api.nvim_set_current_win(editor)
	for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
		if win ~= editor then
			api.nvim_win_close(win, false)
		end
	end

	-- A real child process survives when a narrow layout hides its terminal.
	panel("botright vnew", "toggleterm", "right")
	vim.bo.buftype = ""
	local terminal_buffer = api.nvim_get_current_buf()
	local channel = vim.fn.jobstart(
		{ "sh", "-c", "while read -r line; do printf '%s\\n' \"$line\"; done" },
		{ term = true }
	)
	assert(channel > 0, "Could not create local terminal fixture")
	vim.bo[terminal_buffer].bufhidden = "wipe"
	api.nvim_set_current_win(editor)
	panel("topleft vnew", "neo-tree", "left")
	panels.enforce()
	assert(api.nvim_buf_is_valid(terminal_buffer), "Hiding a panel wiped its terminal buffer")
	assert(vim.fn.jobwait({ channel }, 0)[1] == -1, "Hiding a panel terminated its process")
	api.nvim_set_current_win(editor)
	for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
		if win ~= editor then
			api.nvim_win_close(win, false)
		end
	end

	local a, b = tmp .. "/project-a", tmp .. "/project-b"
	vim.fn.mkdir(a, "p")
	vim.fn.mkdir(b, "p")
	vim.fn.writefile({}, a .. "/.root")
	vim.fn.writefile({}, b .. "/.root")
	vim.fn.writefile({ "first" }, a .. "/one.txt")
	vim.fn.writefile({ "second" }, b .. "/two.txt")
	vim.fn.writefile({ "hidden" }, a .. "/hidden.txt")
	vim.cmd.edit(a .. "/one.txt")
	project.set(a)
	local a_buffer = api.nvim_get_current_buf()
	vim.cmd.badd(a .. "/hidden.txt")
	local _, auxiliary = panel("topleft vnew", "neo-tree", "left")
	api.nvim_buf_set_name(auxiliary, "panel://session-exclusion")
	vim.bo[auxiliary].buflisted = true
	vim.cmd.tabnew(b .. "/two.txt")
	project.set(b)
	roles.mark(0, "editor")
	local b_buffer = api.nvim_get_current_buf()
	local preview_path = b .. "/preview-only.txt"
	vim.fn.writefile(vim.fn["repeat"]({ "preview content" }, 20), preview_path)
	vim.cmd.vsplit(preview_path)
	local preview_win, preview_buf = api.nvim_get_current_win(), api.nvim_get_current_buf()
	roles.mark(preview_win, "panel")
	api.nvim_win_set_cursor(preview_win, { 12, 3 })
	vim.wo[preview_win].winfixbuf = true
	local preview_view = vim.fn.winsaveview()
	session.setup({ dir = tmp .. "/sessions" })
	session.setup({ dir = tmp .. "/sessions" })
	assert(
		#api.nvim_get_autocmds({ group = "user_workspace_session", event = "VimLeavePre" }) == 1,
		"Repeated setup duplicated workspace autosave"
	)
	assert(not require("persistence").active(), "Persistence and the workspace service both own autosave")
	local first_project_tab = api.nvim_list_tabpages()[1]
	vim.t[first_project_tab].user_project_root = nil
	local path = session.current()
	assert(
		path:find("project%-a"),
		"Workspace session identity followed the focused second tab: "
			.. path
			.. " "
			.. vim.inspect(project.context(a .. "/one.txt"))
	)
	assert(session.save(), "Could not save an inferred first-tab project")
	local inferred = vim.json.decode(table.concat(vim.fn.readfile(path .. ".json"), "\n"))
	assert(
		inferred.workspace == a and inferred.tabs[1].root == a and inferred.tabs[1].explicit == nil,
		"Current tab's explicit B root replaced another tab's inferred A root"
	)
	vim.t[first_project_tab].user_project_root = a
	assert(session.save(), "Could not save the multi-tab workspace")
	assert(vim.bo[auxiliary].buflisted, "Saving changed the live panel's listed state")
	assert(api.nvim_win_get_buf(preview_win) == preview_buf, "Saving did not restore a file-backed preview panel")
	assert(
		vim.wo[preview_win].winfixbuf and vim.deep_equal(vim.fn.winsaveview(), preview_view),
		"Saving moved a file preview's view or lost its fixed-buffer setting"
	)
	assert(
		api.nvim_buf_is_valid(terminal_buffer) and vim.fn.jobwait({ channel }, 0)[1] == -1,
		"Saving terminated a job"
	)
	local saved = table.concat(vim.fn.readfile(path), "\n")
	assert(
		not saved:find("panel://", 1, true) and not saved:find("term://", 1, true),
		"Session serialized a temporary panel or AI terminal"
	)
	assert(saved:find("hidden.txt", 1, true), "Session omitted a real hidden file")
	assert(
		not saved:find("preview-only.txt", 1, true),
		"Session serialized a temporary file preview as an editor split"
	)
	assert(vim.o.eventignore == "", "Saving leaked its event suppression")
	local invalid_target = tmp .. "/cannot-overwrite-directory"
	vim.fn.mkdir(invalid_target, "p")
	local notified = {}
	local original_notify = vim.notify
	vim.notify = function(message)
		notified[#notified + 1] = message
	end
	local save_failed = not session.save(invalid_target)
	vim.notify = original_notify
	assert(
		save_failed and notified[1]:find("Session save failed", 1, true),
		"Session save failure was reported as success"
	)
	assert(
		api.nvim_win_get_buf(preview_win) == preview_buf and vim.bo[auxiliary].buflisted,
		"Failed save changed live windows or buffer listing"
	)
	assert(vim.o.eventignore == "", "Failed save leaked its event suppression")
	api.nvim_buf_set_lines(b_buffer, 0, -1, false, { "unsaved change" })
	assert(not session.load(), "Session restore replaced an unsaved file")
	assert(
		api.nvim_buf_get_lines(b_buffer, 0, -1, false)[1] == "unsaved change",
		"Refused restore changed buffer contents"
	)
	vim.bo[b_buffer].modified = false
	project.set(a)
	assert(session.current() == path, "Session identity changed when the focused tab root changed")
	assert(session.load(), "Could not restore the saved workspace")
	assert(#api.nvim_list_tabpages() == 2, "Session did not restore both tabs")
	local tabs = api.nvim_list_tabpages()
	assert(vim.fn.getcwd(-1, 1) == a and vim.fn.getcwd(-1, 2) == b, "Session lost tab-local working directories")
	assert(
		vim.t[tabs[1]].user_project_root == a and vim.t[tabs[2]].user_project_root == b,
		"Session lost explicit project ownership"
	)
	assert(
		api.nvim_buf_is_valid(terminal_buffer) and vim.fn.jobwait({ channel }, 0)[1] == -1,
		"Restoring killed an existing hidden process"
	)
	assert(api.nvim_buf_is_valid(a_buffer), "Session lost the first project file")

	-- Existing Persistence .vim files remain usable when there is no sidecar.
	vim.fn.delete(path .. ".json")
	assert(session.load({ path = path }), "Legacy Persistence session could not be read")
	assert(vim.fn.getcwd(-1, 1) == a and vim.fn.getcwd(-1, 2) == b, "Legacy session lost native :tcd restoration")
	session.stop()
	local stopped_saves = 0
	local stop_group = api.nvim_create_augroup("check_stopped_session", { clear = true })
	api.nvim_create_autocmd("User", {
		group = stop_group,
		pattern = "PersistenceSavePre",
		callback = function()
			stopped_saves = stopped_saves + 1
		end,
	})
	api.nvim_exec_autocmds("VimLeavePre", { group = "user_workspace_session" })
	assert(stopped_saves == 0, "Stopping workspace autosave still wrote a session")
	api.nvim_del_augroup_by_id(stop_group)
	vim.fn.jobstop(channel)
	vim.o.columns, vim.o.lines = old_columns, old_lines
	if api.nvim_tabpage_is_valid(first) then
		api.nvim_set_current_tabpage(first)
	end
end
