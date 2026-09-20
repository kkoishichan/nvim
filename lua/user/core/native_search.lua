-- Search entries that need no external program. A host without fzf, ripgrep or
-- fd still has to be able to open a file, complete a path and get matches into
-- the quickfix list, so the picker keys dispatch here instead of loading a
-- picker that cannot run.

local M = {}

local function project_root()
	return require("user.core.project").root()
end

---True when the picker's own dependency is present. Checked at the moment a key
---is pressed, so installing fzf during a session takes effect without a restart.
function M.usable()
	return vim.fn.executable("fzf") == 1
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
	-- :vimgrep is Neovim's own search: no ripgrep, no shell, and results land in
	-- the quickfix list where the existing ]q / [q entries already work.
	local ok, err = pcall(vim.cmd, ("noautocmd vimgrep /%s/gj %s/**/*"):format(vim.fn.escape(pattern, "/"), root))
	if not ok then
		notify("No matches: " .. tostring(err), vim.log.levels.WARN)
		return
	end
	if vim.tbl_isempty(vim.fn.getqflist()) then
		notify("No matches for " .. pattern, vim.log.levels.WARN)
		return
	end
	vim.cmd("botright copen")
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
	grep_visual = "grep_cword",
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
