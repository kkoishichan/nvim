-- Search entries that need no external program. A host without fzf, ripgrep or
-- fd still has to be able to open a file, complete a path and get matches into
-- the quickfix list, so the picker keys dispatch here instead of loading a
-- picker that cannot run.

local M = {}
local generation = 0

local function project_root()
	return require("user.core.project").root()
end

---True when the picker's own dependency is present. Checked at the moment a key
---is pressed, so installing fzf during a session takes effect without a restart.
function M.usable()
	return vim.fn.executable("fzf") == 1 and vim.fn.executable("rg") == 1
end

local function notify(message, level)
	vim.notify(message, level or vim.log.levels.INFO, { title = "Search" })
end

---Native file opening: `:find` over the workspace with path completion.
function M.files(opts)
	local root = (opts or {}).cwd or project_root()
	vim.ui.input({ prompt = "Open file: ", completion = "file" }, function(answer)
		if not answer or answer == "" then
			return
		end
		local target = answer
		if not vim.startswith(answer, "/") and not vim.startswith(answer, "~") then
			target = vim.fs.joinpath(root, answer)
		end
		vim.cmd.edit(vim.fn.fnameescape(vim.fn.expand(target)))
	end)
end

local function quickfix_grep(pattern, opts)
	local root = (opts or {}).cwd or project_root()
	local insensitive = vim.o.ignorecase and not (vim.o.smartcase and pattern:find("%u"))
	local ok, regex = pcall(vim.regex, (insensitive and "\\c" or "") .. pattern)
	if not ok then
		notify("Invalid search: " .. tostring(regex), vim.log.levels.WARN)
		return
	end
	generation = generation + 1
	local current = generation
	local next_file, stats = require("user.core.search_files").iter(root)
	local matches, skipped = {}, 0
	vim.fn.setqflist({}, " ", { title = "Search: " .. pattern, items = {} })
	local list_id = vim.fn.getqflist({ id = 0 }).id
	local function finish()
		vim.fn.setqflist({}, "r", { id = list_id, items = matches })
		if #matches > 0 and vim.fn.getqflist({ id = 0 }).id == list_id then
			vim.cmd("botright copen")
		elseif #matches == 0 then
			notify("No matches for " .. pattern, vim.log.levels.WARN)
		end
		if skipped > 0 or stats.unreadable > 0 or stats.truncated or #matches >= 10000 then
			notify(
				"Search limited: skipped binary, unreadable or >1.5 MiB files, or reached the entry/match limit",
				vim.log.levels.WARN
			)
		end
	end
	local function step()
		if current ~= generation then
			return
		end
		local began = vim.uv.hrtime()
		for _ = 1, 100 do
			local path, done = next_file()
			if done or #matches >= 10000 then
				finish()
				return
			end
			if path then
				local stat = vim.uv.fs_stat(path)
				local fd = stat and stat.size <= 1.5 * 1024 * 1024 and vim.uv.fs_open(path, "r", 0)
				local contents = fd and vim.uv.fs_read(fd, stat.size, 0)
				if fd then
					vim.uv.fs_close(fd)
				end
				if contents and not contents:find("\0", 1, true) then
					local row = 0
					for line in (contents .. "\n"):gmatch("(.-)\n") do
						row = row + 1
						local column = regex:match_str(line)
						if column and #matches < 10000 then
							matches[#matches + 1] = { filename = path, lnum = row, col = column + 1, text = line }
						end
					end
				else
					skipped = skipped + 1
				end
			end
			if vim.uv.hrtime() - began > 8000000 then
				break
			end
		end
		vim.schedule(step)
	end
	vim.schedule(step)
end

function M.grep(opts)
	vim.ui.input({ prompt = "Grep: " }, function(answer)
		if answer and answer ~= "" then
			quickfix_grep(answer, opts)
		end
	end)
end

function M.grep_cword(opts)
	local word = vim.fn.expand("<cword>")
	if word == "" then
		notify("No word under the cursor", vim.log.levels.WARN)
		return
	end
	quickfix_grep("\\<" .. word .. "\\>", opts)
end

---Grep the visual selection. Only a single-line selection makes a useful
---pattern, so a multi-line one falls back to the word under the cursor.
function M.grep_visual(opts)
	local start_pos = vim.fn.getpos("v")
	local end_pos = vim.fn.getpos(".")
	if start_pos[2] ~= end_pos[2] then
		return M.grep_cword(opts)
	end
	local line = vim.api.nvim_buf_get_lines(0, start_pos[2] - 1, start_pos[2], false)[1] or ""
	local first = math.min(start_pos[3], end_pos[3])
	local last = math.max(start_pos[3], end_pos[3])
	local selection = line:sub(first, last)
	if selection == "" then
		return M.grep_cword(opts)
	end
	vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
	quickfix_grep(vim.fn.escape(selection, "\\/.*$^~[]"), opts)
end

function M.buffers()
	local items, labels = {}, {}
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if vim.bo[bufnr].buflisted and vim.api.nvim_buf_is_loaded(bufnr) then
			local name = vim.api.nvim_buf_get_name(bufnr)
			table.insert(items, bufnr)
			table.insert(
				labels,
				("%d  %s"):format(bufnr, name ~= "" and vim.fn.fnamemodify(name, ":~:.") or "[No Name]")
			)
		end
	end
	if #items == 0 then
		notify("No listed buffers", vim.log.levels.WARN)
		return
	end
	vim.ui.select(labels, { prompt = "Buffers" }, function(_, index)
		if index then
			vim.api.nvim_set_current_buf(items[index])
		end
	end)
end

function M.blines()
	vim.cmd("botright copen")
	notify("Use :g/pattern/caddexpr for in-buffer matches", vim.log.levels.INFO)
end

function M.helptags()
	vim.ui.input({ prompt = "Help: ", completion = "help" }, function(answer)
		if answer and answer ~= "" then
			pcall(vim.cmd.help, answer)
		end
	end)
end

function M.commands()
	vim.ui.input({ prompt = ":", completion = "command" }, function(answer)
		if answer and answer ~= "" then
			pcall(vim.cmd, answer)
		end
	end)
end

function M.quickfix()
	vim.cmd("botright copen")
end

function M.oldfiles()
	local files = {}
	for _, path in ipairs(vim.v.oldfiles) do
		if vim.uv.fs_stat(path) then
			table.insert(files, vim.fn.fnamemodify(path, ":~:."))
		end
		if #files >= 50 then
			break
		end
	end
	if #files == 0 then
		notify("No recent files", vim.log.levels.WARN)
		return
	end
	vim.ui.select(files, { prompt = "Recent files" }, function(choice)
		if choice then
			vim.cmd.edit(vim.fn.fnameescape(vim.fn.expand(choice)))
		end
	end)
end

-- Picker methods without a native equivalent worth improvising. Naming them
-- keeps the fallback honest instead of silently doing something else.
local unavailable = {
	command_history = "Use q: for the command-line window",
	git_commits = "Use :terminal git log",
	git_status = "Use :terminal git status",
	keymaps = "Use :map",
	lines = "Use :vimgrep over the open files",
	live_grep_glob = "Use :vimgrep with a glob",
}

local aliases = {
	global = "files",
	live_grep = "grep",
}

---Dispatch a picker method to its native replacement.
setmetatable(M, {
	__index = function(_, key)
		local alias = aliases[key]
		if alias then
			return rawget(M, alias)
		end
		local hint = unavailable[key]
		return function()
			notify(
				(hint or ("No native replacement for " .. key)) .. "; install fzf for the picker",
				vim.log.levels.WARN
			)
		end
	end,
})

return M
