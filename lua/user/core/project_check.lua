-- Project-wide checks on request. Language servers only report diagnostics
-- for open files unless they analyse the whole workspace in the background, so
-- the editor modes get the project view the explicit way: run the project's
-- own checker once, parse its output and put every finding in the quickfix
-- list. Nothing here runs without :ProjectCheck.
local M = {}
local toolchain = require("user.toolchain")
local project = require("user.core.project")

local function generic(line)
	local file, lnum, col, text = line:match("^(.-):(%d+):(%d+):%s*(.*)$")
	if file then
		return file, tonumber(lnum), tonumber(col), text
	end
end

local function tsc(line)
	local file, lnum, col, text = line:match("^(.-)%((%d+),(%d+)%):%s*(.*)$")
	if file then
		return file, tonumber(lnum), tonumber(col), text
	end
end

local function severity(text)
	if text:match("^error") or text:match("^E%d") or text:match("SyntaxError") then
		return "E"
	end
	return "W"
end

local function system(name)
	return function()
		local executable = toolchain.executable(name)
		return executable
	end
end

-- name -> label, project markers, filetypes it serves, how to build the
-- command (nil when the tool is unavailable) and how to parse one line.
M.checks = {
	ruff = {
		label = "ruff check",
		markers = { "pyproject.toml", "ruff.toml", ".ruff.toml", "requirements.txt", "setup.py", "setup.cfg" },
		filetypes = { python = true },
		command = function()
			local executable = system("ruff")()
			return executable and { executable, "check", "--output-format", "concise", "--no-fix", "--exit-zero", "." }
		end,
		parse = generic,
	},
	tsc = {
		label = "tsc --noEmit",
		markers = { "tsconfig.json" },
		filetypes = { typescript = true, typescriptreact = true, javascript = true, javascriptreact = true, vue = true },
		command = function(root)
			local executable = toolchain.node_executable("tsc", root)
			return executable and { executable, "--noEmit", "--pretty", "false", "-p", root }
		end,
		parse = tsc,
	},
	cargo = {
		label = "cargo check",
		markers = { "Cargo.toml" },
		filetypes = { rust = true },
		command = function()
			local executable = system("cargo")()
			return executable and { executable, "check", "--message-format", "short" }
		end,
		parse = generic,
	},
	vet = {
		label = "go vet",
		markers = { "go.mod" },
		filetypes = { go = true },
		command = function()
			local executable = system("go")()
			return executable and { executable, "vet", "./..." }
		end,
		parse = generic,
	},
	selene = {
		label = "selene",
		markers = { "selene.toml" },
		filetypes = { lua = true },
		command = function()
			local executable = system("selene")()
			return executable and { executable, "--display-style", "quiet", "." }
		end,
		parse = generic,
	},
}

local function marker_root(check, ctx)
	for _, directory in ipairs({ ctx.language_root, ctx.root, ctx.repository }) do
		if directory then
			for _, marker in ipairs(check.markers) do
				if vim.uv.fs_stat(vim.fs.joinpath(directory, marker)) then
					return directory
				end
			end
		end
	end
end

---Checks whose project markers exist around the current buffer, sorted by
---name. `argv` is nil when the tool itself is not installed.
---@param ctx table|nil a project context; defaults to the current buffer's
function M.available(ctx)
	ctx = ctx or project.context()
	local list = {}
	for name, check in pairs(M.checks) do
		local root = marker_root(check, ctx)
		if root then
			list[#list + 1] =
				{ name = name, label = check.label, root = root, argv = check.command(root), check = check }
		end
	end
	table.sort(list, function(a, b)
		return a.name < b.name
	end)
	return list
end

function M.names()
	local names = {}
	for _, entry in ipairs(M.available()) do
		names[#names + 1] = entry.name
	end
	return names
end

---Parse tool output into quickfix items with absolute file names.
---@param name string check name
---@param output string stdout and stderr, concatenated
---@param root string the directory the tool ran in
function M.parse(name, output, root)
	local check = assert(M.checks[name], "unknown project check: " .. tostring(name))
	local items = {}
	for line in output:gmatch("[^\r\n]+") do
		local file, lnum, col, text = check.parse(line)
		if file and text ~= "" then
			file = file:gsub("^%./", "")
			if not file:match("^/") and not file:match("^%a:[/\\]") then
				file = vim.fs.joinpath(root, file)
			end
			items[#items + 1] = {
				filename = vim.fs.normalize(file),
				lnum = lnum,
				col = col,
				text = text,
				type = severity(text),
			}
		end
	end
	return items
end

M.running = {}
M.last = nil

local function present(title, items, opts)
	vim.fn.setqflist({}, " ", { title = title, items = items })
	if #items == 0 then
		vim.notify(title .. ": no findings", vim.log.levels.INFO, { title = "Project check" })
		return
	end
	vim.notify(("%s: %d finding(s)"):format(title, #items), vim.log.levels.INFO, { title = "Project check" })
	if opts and opts.open == false then
		return
	end
	-- Trouble is the problems panel where the mode has it; the quickfix window
	-- is the native one everywhere else.
	if not pcall(vim.cmd, "Trouble qflist open") then
		vim.cmd("botright copen")
	end
end

---Run one available check. Findings replace the quickfix list.
---@param entry table an item from M.available()
---@param opts { open?: boolean }|nil
function M.execute(entry, opts)
	if not entry.argv then
		vim.notify(
			entry.label .. " is not installed; install it or run :MasonToolsInstall",
			vim.log.levels.WARN,
			{ title = "Project check" }
		)
		return false
	end
	local key = entry.name .. "\0" .. entry.root
	if M.running[key] then
		vim.notify(
			entry.label .. " is already running in " .. entry.root,
			vim.log.levels.INFO,
			{ title = "Project check" }
		)
		return false
	end
	M.running[key] = true
	local title = entry.label .. " · " .. vim.fn.fnamemodify(entry.root, ":~")
	vim.notify("Running " .. title, vim.log.levels.INFO, { title = "Project check" })
	local ok, err = pcall(vim.system, entry.argv, { cwd = entry.root, text = true }, function(result)
		vim.schedule(function()
			M.running[key] = nil
			local output = (result.stdout or "") .. "\n" .. (result.stderr or "")
			local items = M.parse(entry.name, output, entry.root)
			M.last = { name = entry.name, root = entry.root, code = result.code, items = items }
			if #items == 0 and result.code ~= 0 then
				local tail = {}
				for line in output:gmatch("[^\r\n]+") do
					tail[#tail + 1] = line
					if #tail >= 10 then
						break
					end
				end
				vim.notify(
					("%s exited with %d:\n%s"):format(entry.label, result.code, table.concat(tail, "\n")),
					vim.log.levels.ERROR,
					{ title = "Project check" }
				)
				return
			end
			present(title, items, opts)
		end)
	end)
	if not ok then
		M.running[key] = nil
		vim.notify(tostring(err), vim.log.levels.ERROR, { title = "Project check" })
		return false
	end
	return true
end

---Pick the check for the current buffer and run it. A name selects one
---check; otherwise the one matching the filetype runs, and the user chooses
---when several apply.
---@param name string|nil
function M.run(name)
	local available = M.available()
	if name then
		for _, entry in ipairs(available) do
			if entry.name == name then
				return M.execute(entry)
			end
		end
		vim.notify(
			"No project check named " .. name .. " applies here (" .. table.concat(M.names(), ", ") .. ")",
			vim.log.levels.WARN,
			{ title = "Project check" }
		)
		return false
	end
	if #available == 0 then
		vim.notify("No project check applies to this directory", vim.log.levels.WARN, { title = "Project check" })
		return false
	end
	local filetype = vim.bo.filetype
	local matching = vim.tbl_filter(function(entry)
		return entry.check.filetypes[filetype] == true
	end, available)
	if #matching == 1 then
		return M.execute(matching[1])
	end
	if #available == 1 then
		return M.execute(available[1])
	end
	vim.ui.select(available, {
		prompt = "Project check",
		format_item = function(entry)
			return entry.label .. (entry.argv and "" or " (not installed)")
		end,
	}, function(entry)
		if entry then
			M.execute(entry)
		end
	end)
	return true
end

return M
