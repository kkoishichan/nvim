local project = require("user.core.project")
local mode = require("user.core.mode")
local capabilities = mode.capabilities()

vim.api.nvim_create_user_command("TransparentToggle", function()
	require("user.core.transparency").toggle()
end, { desc = "Toggle and save transparent background" })

-- Everything the mode decided, on demand. Startup prints at most one line and
-- never walks the cache or state directories to produce a size report.
vim.api.nvim_create_user_command("ModeInfo", function()
	local storage = mode.storage()
	local lines = {
		{ "Editor mode: ", "Title" },
		{ mode.name() .. "\n" },
		{ "  selected by      " .. mode.source() .. "\n" },
	}

	local disabled = {}
	for _, capability in ipairs(mode.capability_names()) do
		if not capabilities[capability] then
			table.insert(disabled, capability)
		end
	end
	table.insert(lines, { "  disabled         " .. (#disabled > 0 and table.concat(disabled, ", ") or "none") .. "\n" })

	for _, entry in ipairs(mode.degradations()) do
		table.insert(lines, { "  unavailable      " .. entry.subject .. ": " .. entry.reason .. "\n", "WarningMsg" })
	end
	for _, notice in ipairs(mode.notices()) do
		table.insert(lines, { "  notice           " .. notice .. "\n", "WarningMsg" })
	end

	local location = storage.relocated and "configured location" or "standard location"
	if storage.writable then
		table.insert(lines, { "  state directory  " .. storage.path .. " (" .. location .. ")\n" })
		if storage.volatile then
			table.insert(lines, {
				"                   temporary root: recovery files can disappear on cleanup or logout\n",
				"WarningMsg",
			})
		end
		table.insert(lines, { "  undo             " .. (vim.o.undofile and vim.o.undodir or "off") .. "\n" })
		table.insert(lines, { "  swap             " .. (vim.o.swapfile and vim.o.directory or "off") .. "\n" })
		table.insert(
			lines,
			{ "  shada            " .. (vim.o.shadafile ~= "" and vim.o.shadafile or "default") .. "\n" }
		)
	else
		table.insert(lines, {
			"  state directory  unusable: " .. (storage.reason or "unknown") .. "; disk recovery is off\n",
			"WarningMsg",
		})
	end

	local lsp = package.loaded["user.core.fast_lsp"]
	local managed = lsp and lsp.summary() or "none"
	table.insert(lines, { "  manual servers   " .. managed .. "\n" })

	vim.api.nvim_echo(lines, false, {})
end, { desc = "Report the active editor mode, its capabilities and storage" })

vim.api.nvim_create_user_command("DiffDisk", function()
	local source_win = vim.api.nvim_get_current_win()
	local source_buf = vim.api.nvim_get_current_buf()
	local file = vim.api.nvim_buf_get_name(source_buf)

	if file == "" then
		vim.notify("Current buffer has no file on disk", vim.log.levels.WARN, {
			title = "DiffDisk",
		})
		return
	end

	local stat = vim.uv.fs_stat(file)
	if not stat or stat.type ~= "file" then
		vim.notify("File is not readable: " .. vim.fn.fnamemodify(file, ":~:."), vim.log.levels.WARN, {
			title = "DiffDisk",
		})
		return
	end

	local ok, lines = pcall(vim.fn.readfile, file)
	if not ok then
		vim.notify("Could not read file: " .. vim.fn.fnamemodify(file, ":~:."), vim.log.levels.ERROR, {
			title = "DiffDisk",
		})
		return
	end

	vim.cmd("vertical new")

	local disk_buf = vim.api.nvim_get_current_buf()
	vim.bo[disk_buf].buftype = "nofile"
	vim.bo[disk_buf].bufhidden = "wipe"
	vim.bo[disk_buf].buflisted = false
	vim.bo[disk_buf].swapfile = false
	vim.bo[disk_buf].modifiable = true

	vim.api.nvim_buf_set_name(disk_buf, ("disk://%s#%d"):format(file, vim.uv.hrtime()))
	vim.api.nvim_buf_set_lines(disk_buf, 0, -1, false, lines)

	local filetype = vim.filetype.match({ filename = file })
	if filetype then
		vim.bo[disk_buf].filetype = filetype
	end

	vim.bo[disk_buf].modifiable = false
	vim.bo[disk_buf].readonly = true

	vim.keymap.set("n", "q", "<cmd>diffoff! | close<cr>", {
		buffer = disk_buf,
		silent = true,
		desc = "Close disk diff",
	})

	vim.cmd.diffthis()
	vim.api.nvim_set_current_win(source_win)
	vim.cmd.diffthis()
end, {
	desc = "Diff current buffer with the file on disk",
})

vim.api.nvim_create_user_command("WriteCreateDirs", function(command)
	local file = vim.api.nvim_buf_get_name(0)
	if file == "" or vim.bo.buftype ~= "" then
		vim.notify("Current buffer has no writable file path", vim.log.levels.WARN, { title = "Write" })
		return
	end
	local directory = vim.fn.fnamemodify(file, ":p:h")
	if vim.fn.isdirectory(directory) == 0 and vim.fn.mkdir(directory, "p") == 0 then
		vim.notify("Could not create directory: " .. directory, vim.log.levels.ERROR, { title = "Write" })
		return
	end
	vim.cmd.write({ bang = command.bang })
end, {
	bang = true,
	desc = "Create missing parent directories and write the current file",
})

local function cwd_display(path)
	return vim.fn.fnamemodify(path, ":~")
end

local function current_buffer_dir()
	return project.context().directory
end

local function set_cwd(path, title)
	project.set(path)
	vim.notify("tab cwd: " .. cwd_display(vim.fn.getcwd()), vim.log.levels.INFO, { title = title })
end

local function add_zoxide_path(path)
	if vim.fn.executable("zoxide") == 1 then
		vim.system({ "zoxide", "add", "--", path })
	end
end

local function project_root_from_path(path)
	if not path or path == "" then
		return nil
	end

	path = project.canonical(path)

	local stat = vim.uv.fs_stat(path)
	if not stat then
		return nil
	end

	return project.find_root(path)
end

local oldfiles_scan_limit = 100

local function collect_project_roots(callback)
	local roots = {}
	local seen = {}

	local add = function(root)
		if root and not seen[root] and vim.uv.fs_stat(root) then
			seen[root] = true
			table.insert(roots, root)
		end
	end

	add(project.root())

	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		add(project_root_from_path(vim.api.nvim_buf_get_name(bufnr)))
	end

	local oldfiles = vim.v.oldfiles
	for index = 1, math.min(#oldfiles, oldfiles_scan_limit) do
		add(project_root_from_path(oldfiles[index]))
	end

	local function finish()
		table.sort(roots)
		callback(roots)
	end

	if vim.fn.executable("zoxide") == 1 then
		vim.system({ "zoxide", "query", "--list" }, { text = true }, function(result)
			vim.schedule(function()
				if result.code == 0 and result.stdout then
					for dir in result.stdout:gmatch("[^\r\n]+") do
						add(project_root_from_path(dir))
					end
				end
				finish()
			end)
		end)
	else
		finish()
	end
end

vim.api.nvim_create_user_command("ProjectRoot", function()
	local context = project.context()
	local root = context.file and (project.find_root(context.directory) or context.directory) or context.cwd
	set_cwd(root, "Project root")
	vim.schedule(function()
		require("user.core.panels").open_oil(root)
	end)
end, {
	desc = "Select the current file's project root and open it",
})

vim.api.nvim_create_user_command("FileDir", function()
	local dir = current_buffer_dir()
	set_cwd(dir, "File directory")
	vim.schedule(function()
		require("user.core.panels").open_oil(dir)
	end)
end, {
	desc = "Set cwd to the current file's directory",
})

local function normalize_path(path)
	return project.canonical(path)
end

vim.api.nvim_create_user_command("Cd", function(command)
	local path = command.args ~= "" and normalize_path(command.args) or project.root()
	if vim.fn.isdirectory(path) == 0 then
		vim.notify("Directory not found: " .. cwd_display(path), vim.log.levels.WARN, { title = "Project directory" })
		return
	end
	set_cwd(path, "Project directory")
end, {
	nargs = "?",
	complete = "dir",
	desc = "Select the current tab's workspace directory",
})

local function open_directory(path, title)
	local stat = vim.uv.fs_stat(path)
	if not stat or stat.type ~= "directory" then
		vim.notify("Directory not found: " .. cwd_display(path), vim.log.levels.WARN, { title = title or "Directory" })
		return
	end

	set_cwd(path, title or "Directory")
	add_zoxide_path(path)

	vim.schedule(function()
		require("user.core.panels").open_oil(path)
	end)
end

local function pick_project()
	collect_project_roots(function(roots)
		if #roots == 0 then
			vim.notify("No projects found", vim.log.levels.WARN, { title = "Project" })
			return
		end

		local entry_to_root = {}
		local entries = {}
		for _, root in ipairs(roots) do
			local entry = cwd_display(root)
			entry_to_root[entry] = root
			table.insert(entries, entry)
		end

		local selected_project = function(selected)
			local entry = selected[1]
			return entry and entry_to_root[entry]
		end

		if not require("user.core.native_search").usable() then
			-- Without fzf the same list is still a choice, just a native one.
			vim.ui.select(entries, { prompt = "Projects" }, function(choice)
				local root = choice and entry_to_root[choice]
				if root then
					open_directory(root, "Project")
				end
			end)
			return
		end

		require("fzf-lua").fzf_exec(entries, {
			prompt = "Projects> ",
			winopts = {
				title = " Projects ",
				preview = { hidden = true },
			},
			actions = {
				["enter"] = function(selected)
					local root = selected_project(selected)
					if root then
						open_directory(root, "Project")
					end
				end,
				["ctrl-f"] = function(selected)
					local root = selected_project(selected)
					if not root then
						return
					end

					set_cwd(root, "Project")
					add_zoxide_path(root)
					vim.schedule(function()
						require("fzf-lua").files({ cwd = root })
					end)
				end,
			},
		})
	end)
end

vim.api.nvim_create_user_command("ProjectPick", pick_project, {
	desc = "Pick a project, set cwd, and open it",
})

local function path_from_fzf_selection(selected, opts)
	if not selected[1] then
		return nil
	end

	local entry = require("fzf-lua.path").entry_to_file(selected[1], opts)
	return normalize_path(entry.path or entry.bufname or selected[1])
end

local function pick_directory()
	if vim.fn.executable("fd") == 0 or not require("user.core.native_search").usable() then
		-- Directory completion is built in, so the entry stays usable on a host
		-- that never installed the search tools.
		vim.ui.input({ prompt = "Directory: ", completion = "dir" }, function(answer)
			if answer and answer ~= "" then
				open_directory(normalize_path(vim.fn.expand(answer)), "Directory")
			end
		end)
		return
	end

	require("fzf-lua").files({
		cwd = project.root(),
		prompt = "Directories> ",
		-- Respect ignore files by default; scanning vendor/build trees makes a
		-- directory picker surprisingly expensive in large repositories.
		cmd = "fd --color=never --type d --hidden --exclude .git --exclude .jj",
		fzf_opts = {
			["--no-multi"] = true,
		},
		actions = {
			["enter"] = function(selected, opts)
				local path = path_from_fzf_selection(selected, opts)
				if path then
					open_directory(path, "Directory")
				end
			end,
		},
	})
end

vim.api.nvim_create_user_command("DirectoryPick", pick_directory, {
	desc = "Pick a directory, set cwd, and open it",
})

-- PDF viewing and Typst builds belong to the extended workflows; a mode that
-- does not install their dependencies should not advertise their commands.
if capabilities.extended_workflows then
	local function pdf_target_from_current_file()
		if type(vim.b.pdf_preview_file) == "string" and vim.b.pdf_preview_file ~= "" then
			return vim.b.pdf_preview_file
		end

		local file = vim.api.nvim_buf_get_name(0)
		if file == "" or vim.bo.buftype ~= "" then
			return nil
		end

		file = vim.uv.fs_realpath(file) or file
		if file:lower():match("%.pdf$") then
			return file
		end

		return vim.fn.fnamemodify(file, ":p:r") .. ".pdf"
	end

	local function pdf_viewer()
		for _, viewer in ipairs({ "zathura", "xdg-open", "open" }) do
			if vim.fn.executable(viewer) == 1 then
				return { viewer }
			end
		end
		if vim.fn.has("win32") == 1 and vim.fn.executable("cmd.exe") == 1 then
			return { "cmd.exe", "/c", "start", "" }
		end
	end

	local function open_pdf(file)
		local title = "PDF"
		if not file or file == "" then
			vim.notify("No PDF target for current buffer", vim.log.levels.WARN, { title = title })
			return
		end

		file = normalize_path(file)
		local stat = vim.uv.fs_stat(file)
		if not stat or stat.type ~= "file" then
			vim.notify("PDF not found: " .. cwd_display(file), vim.log.levels.WARN, { title = title })
			return
		end

		local viewer = pdf_viewer()
		if not viewer then
			vim.notify("Missing a system PDF opener", vim.log.levels.ERROR, { title = title })
			return
		end

		local command = vim.list_extend(vim.deepcopy(viewer), { file })
		local job = vim.fn.jobstart(command, { detach = true })
		if job <= 0 then
			vim.notify("Failed to open PDF with " .. viewer[1], vim.log.levels.ERROR, { title = title })
			return
		end

		vim.notify("Opened " .. cwd_display(file), vim.log.levels.INFO, { title = title })
	end

	vim.api.nvim_create_user_command("PdfOpen", function(args)
		open_pdf(args.args ~= "" and args.args or pdf_target_from_current_file())
	end, {
		nargs = "?",
		complete = "file",
		desc = "Open a PDF externally",
	})

	local function current_file_or_notify(title)
		if vim.bo.buftype ~= "" then
			vim.notify("Current buffer is not a normal file", vim.log.levels.WARN, { title = title })
			return nil
		end

		local file = vim.api.nvim_buf_get_name(0)
		if file == "" then
			vim.notify("Current buffer has no file on disk", vim.log.levels.WARN, { title = title })
			return nil
		end

		if vim.bo.modified then
			local ok, err = pcall(vim.cmd.write)
			if not ok then
				vim.notify("Could not write buffer: " .. err, vim.log.levels.ERROR, { title = title })
				return nil
			end
		end

		return file
	end

	local function open_build_errors(title, cwd, output)
		local items = {}
		for line in output:gmatch("[^\r\n]+") do
			local path, row, column, message = line:match("^(.-):(%d+):(%d+):%s*(.*)$")
			if path then
				if not path:match("^[/\\]") and not path:match("^%a:[/\\]") then
					path = vim.fs.joinpath(cwd, path)
				end
				table.insert(items, { filename = path, lnum = tonumber(row), col = tonumber(column), text = message })
			else
				table.insert(items, { text = line, valid = 0 })
			end
		end

		if #items > 0 then
			vim.fn.setqflist({}, " ", { title = title, items = items })
			vim.cmd.copen()
		end
	end

	local function run_pdf_build(title, output, args)
		vim.notify("Building " .. vim.fn.fnamemodify(output, ":~:."), vim.log.levels.INFO, { title = title })
		local cwd = project.root()

		vim.system(args, { text = true, cwd = cwd }, function(result)
			vim.schedule(function()
				if result.code == 0 then
					vim.notify("Wrote " .. vim.fn.fnamemodify(output, ":~:."), vim.log.levels.INFO, { title = title })
					return
				end

				local message = table.concat({
					result.stderr or "",
					result.stdout or "",
				}, "\n")
				open_build_errors(title, cwd, message)
				vim.notify("Build failed. See quickfix for details.", vim.log.levels.ERROR, { title = title })
			end)
		end)
	end

	vim.api.nvim_create_user_command("TypstCompilePdf", function()
		local title = "Typst PDF"
		if vim.fn.executable("typst") == 0 then
			vim.notify("Missing executable: typst", vim.log.levels.ERROR, { title = title })
			return
		end

		local file = current_file_or_notify(title)
		if not file then
			return
		end

		local output = vim.fn.fnamemodify(file, ":p:r") .. ".pdf"
		run_pdf_build(title, output, {
			"typst",
			"compile",
			"--diagnostic-format",
			"short",
			file,
			output,
		})
	end, {
		desc = "Compile current Typst file to PDF",
	})
end
