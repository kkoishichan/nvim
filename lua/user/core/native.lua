-- The entry that works with no plugin manager and no plugins: directory
-- browsing, file opening and the ordinary write/indent/quit behaviour Neovim
-- already provides. Fast mode falls back to this when lazy.nvim or an expected
-- plugin is unavailable, so a server that was never prepared still edits files.

local M = {}

local augroup = "user_native_explorer"

local function parent_of(path)
	local parent = vim.fs.dirname(path)
	return parent ~= path and parent or nil
end

local function entries(path)
	local directories, files = {}, {}
	local iterator = vim.fs.dir(path)
	if not iterator then
		return nil
	end
	for name, kind in iterator do
		local target = kind == "link" and vim.uv.fs_stat(vim.fs.joinpath(path, name)) or nil
		if kind == "directory" or (target and target.type == "directory") then
			directories[#directories + 1] = name .. "/"
		else
			files[#files + 1] = name
		end
	end
	table.sort(directories)
	table.sort(files)
	return vim.list_extend(directories, files)
end

local function render(bufnr, path)
	local listing = entries(path)
	if not listing then
		vim.notify("Cannot read directory: " .. path, vim.log.levels.ERROR, { title = "Directory" })
		return false
	end
	local lines = { vim.fn.fnamemodify(path, ":~"), "../" }
	vim.list_extend(lines, listing)

	vim.bo[bufnr].modifiable = true
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	vim.bo[bufnr].modifiable = false
	vim.bo[bufnr].modified = false
	vim.b[bufnr].user_native_directory = path
	return true
end

local function selected(bufnr)
	local path = vim.b[bufnr].user_native_directory
	local row = vim.api.nvim_win_get_cursor(0)[1]
	if not path or row == 1 then
		return nil
	end
	local line = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1]
	if not line or line == "" then
		return nil
	end
	if line == "../" then
		return parent_of(path), true
	end
	local name = line:gsub("/$", "")
	return vim.fs.joinpath(path, name), line:sub(-1) == "/"
end

---Open `path` in a native directory listing. Returns false when the path is not
---a readable directory, so callers can report their own failure.
function M.browse(path, bufnr)
	path = vim.fs.normalize(vim.fn.fnamemodify(path or vim.fn.getcwd(), ":p")):gsub("/+$", "")
	if path == "" then
		path = "/"
	end
	local stat = vim.uv.fs_stat(path)
	if not stat or stat.type ~= "directory" then
		return false
	end

	if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
		bufnr = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_win_set_buf(0, bufnr)
	end

	vim.bo[bufnr].buftype = "nofile"
	vim.bo[bufnr].bufhidden = "wipe"
	vim.bo[bufnr].swapfile = false
	vim.bo[bufnr].buflisted = false
	vim.bo[bufnr].filetype = "user-directory"

	if not render(bufnr, path) then
		return false
	end

	local function map(lhs, callback, desc)
		vim.keymap.set("n", lhs, callback, { buffer = bufnr, silent = true, nowait = true, desc = desc })
	end
	map("<CR>", function()
		local target, directory = selected(bufnr)
		if not target then
			return
		end
		if directory then
			M.browse(target, bufnr)
		else
			vim.cmd.edit(vim.fn.fnameescape(target))
		end
	end, "Open entry")
	map("-", function()
		local up = parent_of(vim.b[bufnr].user_native_directory or path)
		if up then
			M.browse(up, bufnr)
		end
	end, "Parent directory")
	map("R", function()
		render(bufnr, vim.b[bufnr].user_native_directory or path)
	end, "Refresh listing")
	map("q", "<cmd>bdelete<cr>", "Close listing")
	return true
end

---Take over directory buffers so `nvim <dir>` and the directory commands keep
---working without an explorer plugin. Safe to call more than once.
function M.setup_explorer()
	local group = vim.api.nvim_create_augroup(augroup, { clear = true })
	vim.g.loaded_netrw = 1
	vim.g.loaded_netrwPlugin = 1

	local function claim(bufnr)
		if not vim.api.nvim_buf_is_valid(bufnr) or vim.b[bufnr].user_native_directory then
			return
		end
		local name = vim.api.nvim_buf_get_name(bufnr)
		if name == "" or name:match("^%w[%w+.-]*://") then
			return
		end
		local stat = vim.uv.fs_stat(name)
		if not stat or stat.type ~= "directory" then
			return
		end
		-- BufEnter, not BufAdd: the listing replaces the buffer's contents, so it
		-- must run in a window rather than on a hidden buffer.
		M.browse(name, bufnr)
	end

	vim.api.nvim_create_autocmd("BufEnter", {
		group = group,
		desc = "Show a native directory listing without an explorer plugin",
		callback = function(event)
			claim(event.buf)
		end,
	})
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(bufnr) then
			claim(bufnr)
		end
	end
end

return M
