-- One session represents the whole editor workspace, including every tab.
-- Keep the native .vim format so existing Persistence sessions remain readable.
local M = {}
local api = vim.api
local project = require("user.core.project")
local directory
local selected
local enabled = true

local function storage()
	return directory or (vim.fn.stdpath("state") .. "/sessions")
end

local function file_buffer(bufnr)
	return api.nvim_buf_is_valid(bufnr)
		and vim.bo[bufnr].buftype == ""
		and api.nvim_buf_get_name(bufnr) ~= ""
		and not api.nvim_buf_get_name(bufnr):match("^%a[%w+.-]*://")
		and vim.b[bufnr].user_ai_terminal == nil
end

local function snapshot()
	local tabs = {}
	local workspace
	for index, tab in ipairs(api.nvim_list_tabpages()) do
		local cwd = vim.fn.getcwd(-1, index)
		local explicit = project.canonical(vim.t[tab].user_project_root)
		local root = explicit
		for _, win in ipairs(api.nvim_tabpage_list_wins(tab)) do
			local bufnr = api.nvim_win_get_buf(win)
			if require("user.core.window_roles").is_editor(win) and file_buffer(bufnr) then
				root = root or project.context(api.nvim_buf_get_name(bufnr)).root
				workspace = workspace or root
				break
			end
		end
		tabs[index] = { cwd = cwd, root = root or cwd, explicit = explicit }
	end
	return { version = 1, workspace = workspace or (tabs[1] and tabs[1].root) or project.root(), tabs = tabs }
end

function M.current()
	if selected then
		return selected
	end
	return storage() .. "/" .. snapshot().workspace:gsub("[\\/:]+", "%%") .. ".vim"
end

local function emit(name)
	api.nvim_exec_autocmds("User", { pattern = "Persistence" .. name, modeline = false })
end

local function preserve_terminal_buffers()
	local values = {}
	for _, bufnr in ipairs(api.nvim_list_bufs()) do
		if vim.bo[bufnr].buftype == "terminal" then
			values[bufnr] = vim.bo[bufnr].bufhidden
			vim.bo[bufnr].bufhidden = "hide"
		end
	end
	return function()
		for bufnr, value in pairs(values) do
			if api.nvim_buf_is_valid(bufnr) then
				vim.bo[bufnr].bufhidden = value
			end
		end
	end
end

function M.save(path)
	path = path or M.current()
	local data = snapshot()
	local options = vim.opt.sessionoptions:get()
	local previous_session = vim.v.this_session
	local previous_events = vim.o.eventignore
	local excluded = {}
	local substituted = {}
	local views = {}
	local fixed_buffers = {}
	local original_hidden = {}
	local placeholder
	local roles = require("user.core.window_roles")
	local excluded_visible = {}
	for _, win in ipairs(api.nvim_list_wins()) do
		if not roles.is_editor(win) then
			excluded_visible[api.nvim_win_get_buf(win)] = true
		end
	end
	-- :mksession still emits badd for listed nofile panels when 'blank' is
	-- removed. Temporarily unlist them; no window or running process is closed.
	for _, bufnr in ipairs(api.nvim_list_bufs()) do
		if vim.bo[bufnr].buflisted and (not file_buffer(bufnr) or excluded_visible[bufnr]) then
			excluded[bufnr] = true
		end
	end
	local temporary = path .. ".tmp"
	local metadata = path .. ".json"
	local ok, err = xpcall(function()
		emit("SavePre")
		vim.fn.mkdir(vim.fs.dirname(path), "p")
		vim.o.eventignore = "all"
		for bufnr in pairs(excluded) do
			if api.nvim_buf_is_valid(bufnr) then
				vim.bo[bufnr].buflisted = false
			end
		end
		-- A preview can show an ordinary file in a panel role. :mksession would
		-- preserve that window even if its buffer were unlisted. Substitute only
		-- those auxiliary windows while serializing; restore them before events
		-- resume, without deleting the source buffer or changing editor splits.
		for _, win in ipairs(api.nvim_list_wins()) do
			local bufnr = api.nvim_win_get_buf(win)
			if not roles.is_editor(win) and vim.bo[bufnr].buftype == "" then
				if not placeholder then
					placeholder = api.nvim_create_buf(false, true)
				end
				original_hidden[bufnr] = original_hidden[bufnr] or vim.bo[bufnr].bufhidden
				vim.bo[bufnr].bufhidden = "hide"
				substituted[win] = bufnr
				views[win] = api.nvim_win_call(win, vim.fn.winsaveview)
				fixed_buffers[win] = vim.wo[win].winfixbuf
				vim.wo[win].winfixbuf = false
				api.nvim_win_set_buf(win, placeholder)
			end
		end
		vim.opt.sessionoptions:remove({ "blank", "terminal", "help", "globals" })
		vim.opt.sessionoptions:append({ "buffers", "tabpages", "curdir" })
		api.nvim_cmd({ cmd = "mksession", args = { temporary }, bang = true, magic = { file = false } }, {})
		local lines = vim.fn.readfile(temporary)
		data.fingerprint = vim.fn.sha256(table.concat(lines, "\n"))
		assert(vim.fn.writefile({ vim.json.encode(data) }, metadata .. ".tmp") == 0, "Could not write session metadata")
		assert(vim.uv.fs_rename(temporary, path))
		assert(vim.uv.fs_rename(metadata .. ".tmp", metadata))
	end, debug.traceback)
	for win, bufnr in pairs(substituted) do
		if api.nvim_win_is_valid(win) and api.nvim_buf_is_valid(bufnr) then
			pcall(api.nvim_win_set_buf, win, bufnr)
			pcall(api.nvim_win_call, win, function()
				vim.fn.winrestview(views[win])
			end)
			vim.wo[win].winfixbuf = fixed_buffers[win]
		end
	end
	for bufnr, hidden in pairs(original_hidden) do
		if api.nvim_buf_is_valid(bufnr) then
			vim.bo[bufnr].bufhidden = hidden
		end
	end
	if placeholder and api.nvim_buf_is_valid(placeholder) then
		pcall(api.nvim_buf_delete, placeholder, { force = true })
	end
	vim.opt.sessionoptions = options
	for bufnr in pairs(excluded) do
		if api.nvim_buf_is_valid(bufnr) then
			vim.bo[bufnr].buflisted = true
		end
	end
	vim.o.eventignore = previous_events
	vim.v.this_session = ok and path or previous_session
	if not ok then
		vim.fn.delete(temporary)
		vim.fn.delete(metadata .. ".tmp")
		vim.notify("Session save failed: " .. tostring(err), vim.log.levels.ERROR)
		return false
	end
	selected = path
	emit("SavePost")
	return true
end

local function metadata(path)
	if vim.fn.filereadable(path .. ".json") ~= 1 then
		return nil
	end
	local ok, data, fingerprint = pcall(function()
		return vim.json.decode(table.concat(vim.fn.readfile(path .. ".json"), "\n")),
			vim.fn.sha256(table.concat(vim.fn.readfile(path), "\n"))
	end)
	if
		not ok
		or type(data) ~= "table"
		or data.version ~= 1
		or not vim.islist(data.tabs)
		or type(data.workspace) ~= "string"
	then
		return nil
	end
	if data.fingerprint ~= fingerprint then
		return nil
	end
	for _, tab in ipairs(data.tabs) do
		if
			type(tab) ~= "table"
			or type(tab.cwd) ~= "string"
			or (tab.explicit ~= nil and type(tab.explicit) ~= "string")
		then
			return nil
		end
	end
	return data
end

local function restore_projects(path)
	local data = metadata(path)
	if not data then
		return -- Legacy sessions retain their native per-tab :tcd behavior.
	end
	local current = api.nvim_get_current_tabpage()
	for index, tab in ipairs(api.nvim_list_tabpages()) do
		local saved = data.tabs[index]
		if saved then
			api.nvim_set_current_tabpage(tab)
			if type(saved.cwd) == "string" and vim.fn.isdirectory(saved.cwd) == 1 then
				api.nvim_cmd({ cmd = "tcd", args = { saved.cwd }, magic = { file = false } }, {})
			end
			local explicit = project.canonical(saved.explicit)
			vim.t[tab].user_project_root = explicit and vim.fn.isdirectory(explicit) == 1 and explicit or nil
		end
	end
	if api.nvim_tabpage_is_valid(current) then
		api.nvim_set_current_tabpage(current)
	end
end

function M.list()
	local paths = vim.fn.glob(storage() .. "/*.vim", false, true)
	table.sort(paths, function(a, b)
		local left, right = vim.uv.fs_stat(a).mtime, vim.uv.fs_stat(b).mtime
		if left.sec == right.sec then
			return left.nsec > right.nsec
		end
		return left.sec > right.sec
	end)
	return paths
end

function M.load(opts)
	opts = opts or {}
	local path = opts.path or (opts.last and M.list()[1]) or M.current()
	if not path or vim.fn.filereadable(path) ~= 1 then
		vim.notify("No saved workspace session found", vim.log.levels.INFO)
		return false
	end
	for _, bufnr in ipairs(api.nvim_list_bufs()) do
		if
			vim.bo[bufnr].modified
			and (vim.bo[bufnr].buftype == "" or vim.bo[bufnr].buftype == "acwrite" or vim.bo[bufnr].modifiable)
		then
			vim.notify("Save or close modified files before restoring a workspace session", vim.log.levels.WARN)
			return false
		end
	end
	local restore_terminals = preserve_terminal_buffers()
	emit("LoadPre")
	local target
	for _, win in ipairs(api.nvim_list_wins()) do
		if require("user.core.window_roles").get(win) == "editor" then
			target = win
			break
		end
	end
	if target then
		api.nvim_set_current_win(target)
	else
		vim.cmd.tabnew()
		target = api.nvim_get_current_win()
	end
	-- Native sessions reuse the current window. Do not inherit a panel's fixed
	-- buffer constraint, or an editor's constraint, while replacing the layout.
	local fixed = vim.wo[target].winfixbuf
	vim.wo[target].winfixbuf = false
	local ok, err = pcall(function()
		api.nvim_cmd({ cmd = "source", args = { path }, magic = { file = false } }, {})
		restore_projects(path)
	end)
	if api.nvim_win_is_valid(target) then
		vim.wo[target].winfixbuf = fixed
	end
	if ok then
		selected = path
	end
	restore_terminals()
	if not ok then
		vim.notify("Session restore failed: " .. tostring(err), vim.log.levels.ERROR)
		return false
	end
	emit("LoadPost")
	return true
end

function M.select()
	vim.ui.select(M.list(), {
		prompt = "Restore workspace session (all tabs)",
		format_item = function(path)
			local data = metadata(path)
			return data and (data.workspace .. " · " .. #data.tabs .. " tabs") or vim.fs.basename(path)
		end,
	}, function(path)
		if path then
			M.load({ path = path })
		end
	end)
end

function M.stop()
	enabled = false
end

function M.setup(opts)
	opts = opts or {}
	directory = opts.dir and vim.fs.normalize(opts.dir) or directory
	enabled = true
	local group = api.nvim_create_augroup("user_workspace_session", { clear = true })
	api.nvim_create_autocmd("VimLeavePre", {
		group = group,
		callback = function()
			if not enabled then
				return
			end
			for _, bufnr in ipairs(api.nvim_list_bufs()) do
				if file_buffer(bufnr) and vim.bo[bufnr].buflisted then
					M.save()
					return
				end
			end
		end,
	})
	api.nvim_create_user_command("SessionSave", function()
		M.save()
	end, { desc = "Save the workspace, including all project tabs" })
end

return M
