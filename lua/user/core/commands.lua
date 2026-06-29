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

local root_markers = {
	".git",
	".jj",
	"compile_commands.json",
	"CMakeLists.txt",
	"Makefile",
	"package.json",
	"pyproject.toml",
	"Cargo.toml",
	"go.mod",
	"typst.toml",
	".root",
}

local function cwd_display(path)
	return vim.fn.fnamemodify(path, ":~")
end

local function expand_home(path)
	if not path or path == "" then
		return path
	end

	if path == "~" then
		return vim.uv.os_homedir()
	end

	if path:sub(1, 2) == "~/" then
		return vim.fs.joinpath(vim.uv.os_homedir(), path:sub(3))
	end

	return path
end

local function current_buffer_dir()
	local file = vim.api.nvim_buf_get_name(0)
	if file == "" or vim.bo.buftype ~= "" then
		return vim.fn.getcwd()
	end

	file = vim.uv.fs_realpath(file) or file
	local stat = vim.uv.fs_stat(file)
	if stat and stat.type == "directory" then
		return file
	end

	return vim.fs.dirname(file)
end

local function set_cwd(path, title)
	vim.cmd("tcd " .. vim.fn.fnameescape(path))
	vim.notify("tab cwd: " .. cwd_display(vim.fn.getcwd()), vim.log.levels.INFO, { title = title })
end

local function add_zoxide_path(path)
	if vim.fn.executable("zoxide") == 1 then
		vim.system({ "zoxide", "add", "--", path })
	end
end

local function find_project_root()
	local dir = current_buffer_dir()
	local root = vim.fs.root(dir, root_markers)
	return root, dir
end

local function project_root_from_path(path)
	if not path or path == "" then
		return nil
	end

	path = expand_home(path)
	path = vim.uv.fs_realpath(path) or path

	local stat = vim.uv.fs_stat(path)
	if not stat then
		return nil
	end

	local dir = stat.type == "directory" and path or vim.fs.dirname(path)
	return vim.fs.root(dir, root_markers)
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

	add(find_project_root())

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
	local root, dir = find_project_root()
	if not root then
		vim.notify("No root marker found from " .. cwd_display(dir), vim.log.levels.WARN, { title = "Project root" })
		return
	end

	set_cwd(root, "Project root")
	vim.schedule(function()
		require("user.core.panels").open_oil(root)
	end)
end, {
	desc = "Set cwd to the current file's project root",
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
	path = expand_home(path)
	if path:sub(1, 1) ~= "/" then
		path = vim.fs.joinpath(vim.fn.getcwd(), path)
	end

	return vim.fs.normalize(path)
end

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
	if vim.fn.executable("fd") == 0 then
		vim.notify("Missing fd for directory picker", vim.log.levels.ERROR, { title = "Directory" })
		return
	end

	require("fzf-lua").files({
		prompt = "Directories> ",
		cmd = "fd --color=never --type d --hidden --no-ignore --exclude .git --exclude .jj",
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
	for _, viewer in ipairs({ "zathura", "xdg-open" }) do
		if vim.fn.executable(viewer) == 1 then
			return viewer
		end
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
		vim.notify("Missing PDF viewer: install zathura or xdg-open", vim.log.levels.ERROR, { title = title })
		return
	end

	local job = vim.fn.jobstart({ viewer, file }, { detach = true })
	if job <= 0 then
		vim.notify("Failed to open PDF with " .. viewer, vim.log.levels.ERROR, { title = title })
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

local function open_build_errors(title, file, output)
	local items = {}
	for line in output:gmatch("[^\r\n]+") do
		table.insert(items, {
			filename = file,
			lnum = 1,
			text = line,
		})
	end

	if #items > 0 then
		vim.fn.setqflist({}, " ", { title = title, items = items })
		vim.cmd.copen()
	end
end

local function run_pdf_build(title, file, output, args)
	vim.notify("Building " .. vim.fn.fnamemodify(output, ":~:."), vim.log.levels.INFO, { title = title })

	vim.system(args, { text = true }, function(result)
		vim.schedule(function()
			if result.code == 0 then
				vim.notify("Wrote " .. vim.fn.fnamemodify(output, ":~:."), vim.log.levels.INFO, { title = title })
				return
			end

			local message = table.concat({
				result.stderr or "",
				result.stdout or "",
			}, "\n")
			open_build_errors(title, file, message)
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
	run_pdf_build(title, file, output, {
		"typst",
		"compile",
		file,
		output,
	})
end, {
	desc = "Compile current Typst file to PDF",
})
