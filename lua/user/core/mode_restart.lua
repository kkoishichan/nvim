-- An explicit mode change restarts the process; plugin state is never unloaded
-- in place. Keep only the editor workspace in the native restart session.
local M = {}

function M.restart()
	if #vim.api.nvim_list_uis() == 0 then
		vim.notify("Editor mode saved. Restart Neovim to apply (no attached UI).", vim.log.levels.INFO)
		return false
	end
	-- :qall may silently stop hidden terminal jobs. Ask before touching the
	-- workspace; cancellation must leave those jobs running.
	local terminals = 0
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		local job = vim.b[bufnr].terminal_job_id
		if vim.bo[bufnr].buftype == "terminal" and job and vim.fn.jobwait({ job }, 0)[1] == -1 then
			terminals = terminals + 1
		end
	end
	if
		terminals > 0
		and vim.fn.confirm(
				("Restarting Neovim will stop %d running terminal task(s). Continue?"):format(terminals),
				"&Restart\n&Cancel",
				2,
				"Warning"
			)
			~= 1
	then
		vim.notify("Editor mode saved; restart canceled. Terminal tasks are still running.", vim.log.levels.INFO)
		return false
	end
	local options, environment = vim.o.sessionoptions, vim.env.NVIM_MODE
	local arguments, argument_index = vim.fn.argv(), vim.fn.argidx()
	local window, session = vim.api.nvim_get_current_win(), vim.v.this_session
	local excluded = {}
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		-- :mksession can serialize listed plugin panels as ordinary file names.
		-- Keep dirty buffers and terminals listed for native quit protection;
		-- sessionoptions already excludes terminal commands from the snapshot.
		local kind = vim.bo[bufnr].buftype
		if vim.bo[bufnr].buflisted and kind ~= "" and kind ~= "terminal" and not vim.bo[bufnr].modified then
			excluded[#excluded + 1] = bufnr
			vim.bo[bufnr].buflisted = false
		end
	end
	-- Old options, mappings and fold providers must not override the new mode.
	-- Terminal commands are not replayed automatically after the restart.
	vim.opt.sessionoptions = { "buffers", "curdir", "tabpages", "winsize" }
	-- The interactive choice applies to the restarted child even if this editor
	-- was launched with NVIM_MODE. The parent shell's environment is untouched.
	vim.env.NVIM_MODE = nil
	local ok, err = pcall(vim.cmd, "confirm restart")
	-- A successful restart exits this process. On refusal/cancellation leave its
	-- options and buffers exactly as they were; the saved choice remains pending.
	vim.o.sessionoptions, vim.env.NVIM_MODE = options, environment
	for _, bufnr in ipairs(excluded) do
		if vim.api.nvim_buf_is_valid(bufnr) then
			vim.bo[bufnr].buflisted = true
		end
	end
	-- Native :restart clears the argument list and sets v:this_session before
	-- asking about unsaved buffers. Undo those bookkeeping changes on cancel.
	vim.v.this_session = session
	if vim.api.nvim_win_is_valid(window) then
		vim.api.nvim_win_call(window, function()
			vim.cmd("%argdelete")
			local function add(argument, position)
				vim.cmd(position .. "argadd " .. vim.fn.fnameescape(argument))
			end
			-- Seed the current argument, append later ones, then prepend earlier
			-- ones. This restores argidx without switching a modified buffer.
			for index = argument_index + 1, #arguments do
				add(arguments[index], vim.fn.argc())
			end
			for index = argument_index, 1, -1 do
				add(arguments[index], 0)
			end
		end)
	end
	vim.notify(
		"Editor mode saved; restart was not completed. " .. (ok and "Run :FastModeToggle to retry." or tostring(err)),
		vim.log.levels.WARN,
		{ title = "Editor mode" }
	)
	return false
end

return M
