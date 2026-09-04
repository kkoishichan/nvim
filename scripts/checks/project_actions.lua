return function(tmp)
	local project = require("user.core.project")
	local panels = require("user.core.panels")
	local picker_spec = require("user.plugins.picker")[1]
	require("lazy").load({ plugins = { "overseer.nvim" } })
	local overseer = require("overseer")
	local saved = {
		tab = vim.api.nvim_get_current_tabpage(),
		fzf = package.loaded["fzf-lua"],
		fzf_path = package.loaded["fzf-lua.path"],
		open_oil = panels.open_oil,
		notify = vim.notify,
		executable = vim.fn.executable,
		input = vim.ui.input,
		run_action = overseer.run_action,
		run_task = overseer.run_task,
		new_task = overseer.new_task,
	}
	local buffers, tasks, notices, searches, opened = {}, {}, {}, {}, {}
	local restarted, template_opts, input_callback, shell_definition
	local shell_started = false
	local test_tab
	local base = vim.fs.joinpath(tmp, "project-actions")
	local a, b, empty = base .. "/a", base .. "/a-other", base .. "/empty"
	local nested = a .. "/packages/nested"
	local function create_file(path, lines)
		vim.fn.mkdir(vim.fs.dirname(path), "p")
		vim.fn.writefile(lines or {}, path)
	end
	local function buffer(path)
		local buf = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(buf, path)
		table.insert(buffers, buf)
		return buf
	end
	local function completed_task(name, cwd, owner, ended)
		local task = saved.new_task({
			name = name,
			cmd = { "true" },
			cwd = cwd,
			metadata = owner and { user_project_root = owner } or {},
		})
		task.status = overseer.STATUS.SUCCESS
		task.time_start, task.time_end = ended - 1, ended
		table.insert(tasks, task)
		return task
	end
	local function await_open(path)
		assert(
			vim.wait(300, function()
				return opened[#opened] == path
			end),
			"Directory action did not open the selected workspace"
		)
		assert(
			project.root() == path and vim.fn.getcwd() == path,
			"Directory action did not update project and tab cwd"
		)
	end
	local ok, err = xpcall(function()
		vim.cmd.tabnew()
		test_tab = vim.api.nvim_get_current_tabpage()
		create_file(a .. "/package.json", { "{}" })
		create_file(b .. "/package.json", { "{}" })
		create_file(nested .. "/package.json", { "{}" })
		create_file(a .. "/src/main.txt", { "a" })
		create_file(b .. "/main.txt", { "b" })
		create_file(nested .. "/nested.txt", { "nested" })
		vim.fn.mkdir(empty, "p")
		local a_buffer = buffer(a .. "/src/main.txt")
		buffer(b .. "/main.txt")
		buffer(nested .. "/nested.txt")
		vim.api.nvim_set_current_buf(a_buffer)
		vim.notify = function(message)
			table.insert(notices, message)
		end
		vim.fn.executable = function(name)
			return name == "zoxide" and 0 or saved.executable(name)
		end
		panels.open_oil = function(path)
			table.insert(opened, path)
		end
		local picker = setmetatable({}, {
			__index = function(_, name)
				return function(opts)
					table.insert(searches, { name = name, opts = opts })
				end
			end,
		})
		local project_entries, project_opts
		picker.fzf_exec = function(entries, opts)
			project_entries, project_opts = entries, opts
		end
		package.loaded["fzf-lua"] = picker
		package.loaded["fzf-lua.path"] = {
			entry_to_file = function(selection, opts)
				assert(type(opts.cwd) == "string", "Directory selection lost its picker directory")
				return { path = vim.fs.joinpath(opts.cwd, selection) }
			end,
		}

		project.set(b)
		vim.cmd.FileDir()
		await_open(a .. "/src")
		vim.cmd.ProjectRoot()
		await_open(a)
		vim.cmd.Cd(vim.fn.fnameescape(b))
		assert(project.root() == b and vim.fn.getcwd() == b, "Cd did not select the requested project")
		vim.cmd.Cd(vim.fn.fnameescape(base .. "/missing"))
		assert(project.root() == b and vim.fn.getcwd() == b, "Invalid Cd changed the workspace")
		vim.cmd.ProjectRoot()
		await_open(a)
		local spaced = base .. "/with spaces"
		vim.fn.mkdir(spaced, "p")
		vim.api.nvim_exec2("Cd " .. vim.fn.fnameescape(spaced), {})
		assert(project.root() == spaced and vim.fn.getcwd() == spaced, "Cd mishandled a directory containing spaces")

		project.set(a)
		vim.cmd.ProjectPick()
		assert(
			vim.wait(300, function()
				return project_entries ~= nil
			end),
			"Project picker did not collect candidate roots"
		)
		assert(vim.tbl_contains(project_entries, b), "Project picker omitted the other open project")
		assert(vim.tbl_contains(project_entries, nested), "Project picker omitted a nested language project")
		project_opts.actions.enter({ b })
		await_open(b)
		project_opts.actions["ctrl-f"]({ a })
		assert(
			vim.wait(300, function()
				return searches[#searches] and searches[#searches].opts.cwd == a
			end),
			"Project picker file action searched the wrong directory"
		)

		vim.cmd.DirectoryPick()
		local directory_search = searches[#searches]
		assert(directory_search.opts.cwd == a, "Directory picker did not search the workspace")
		directory_search.opts.actions.enter({ "src/" }, directory_search.opts)
		await_open(a .. "/src")

		local scoped_keys = {
			["<leader><space>"] = true,
			["<leader>/"] = true,
			["<leader>ff"] = true,
			["<leader>fF"] = true,
			["<leader>fg"] = true,
			["<leader>fG"] = true,
			["<leader>fw"] = true,
			["<leader>gc"] = true,
			["<leader>gs"] = true,
		}
		for _, root in ipairs({ a, b }) do
			project.set(root)
			for _, key in ipairs(picker_spec.keys) do
				if scoped_keys[key[1]] then
					key[2]()
					local search = searches[#searches]
					assert(search.opts.cwd == root, "Search did not follow the selected workspace: " .. key[1])
					if key[1] == "<leader>fF" then
						assert(
							search.opts.no_ignore and search.opts.hidden,
							"Find-all lost its explicit ignore override"
						)
					end
				end
			end
		end

		completed_task("older A", a, a, 10)
		local latest_a = completed_task("latest A", a, a, 30)
		completed_task("legacy A", a .. "/src", nil, 20)
		local latest_b = completed_task("latest B", b, b, 100)
		completed_task("prefix sibling", b, nil, 90)
		completed_task("nested workspace", nested, nested, 200)
		overseer.run_action = function(task, action)
			assert(action == "restart", "Restart-last invoked a different action")
			restarted = task
		end
		project.set(a)
		vim.cmd.OverseerRestartLast()
		assert(restarted == latest_a, "Restart-last selected a newer task from another workspace")
		project.set(b)
		vim.cmd.OverseerRestartLast()
		assert(restarted == latest_b, "Restart-last failed to follow the new workspace")
		project.set(empty)
		restarted = nil
		vim.cmd.OverseerRestartLast()
		assert(restarted == nil and notices[#notices]:find(empty, 1, true), "Empty workspace reused a task elsewhere")

		overseer.run_task = function(opts)
			template_opts = opts
		end
		project.set(a)
		vim.cmd.OverseerRun("BUILD")
		assert(
			template_opts.search_params.dir == a and template_opts.tags[1] == "BUILD",
			"Task search lost workspace or tags"
		)
		project.set(b)
		local definition = { cmd = { "true" }, metadata = { custom = true } }
		template_opts.on_build(definition)
		assert(
			definition.cwd == a and definition.metadata.user_project_root == a,
			"Task prompt changed its captured workspace"
		)
		assert(definition.metadata.custom, "Task creation discarded template metadata")
		definition = { cmd = { "true" }, cwd = nested }
		template_opts.on_build(definition)
		assert(definition.cwd == nested, "Workspace default replaced the template's package directory")
		definition = { cmd = { "true" }, cwd = "packages/nested" }
		template_opts.on_build(definition)
		assert(definition.cwd == nested, "Relative template directory followed a later workspace switch")

		overseer.new_task = function(definition_opts)
			shell_definition = definition_opts
			return {
				start = function()
					shell_started = true
				end,
			}
		end
		vim.ui.input = function(_, callback)
			input_callback = callback
		end
		project.set(a)
		vim.cmd.OverseerShell()
		project.set(b)
		input_callback("printf test")
		assert(shell_started and shell_definition.cwd == a, "Shell task changed directory while the prompt was open")
		assert(shell_definition.metadata.user_project_root == a, "Shell task lacks its workspace association")
		shell_started = false
		vim.cmd("OverseerShell! printf pending")
		assert(
			not shell_started and shell_definition.cwd == b,
			"OverseerShell! started a task or used the wrong workspace"
		)
	end, debug.traceback)

	package.loaded["fzf-lua"], package.loaded["fzf-lua.path"] = saved.fzf, saved.fzf_path
	panels.open_oil = saved.open_oil
	vim.notify, vim.fn.executable, vim.ui.input = saved.notify, saved.executable, saved.input
	overseer.run_action, overseer.run_task, overseer.new_task = saved.run_action, saved.run_task, saved.new_task
	for _, task in ipairs(tasks) do
		task:dispose(true)
	end
	for _, buf in ipairs(buffers) do
		if vim.api.nvim_buf_is_valid(buf) then
			vim.api.nvim_buf_delete(buf, { force = true })
		end
	end
	if test_tab and vim.api.nvim_tabpage_is_valid(test_tab) then
		vim.api.nvim_set_current_tabpage(test_tab)
		vim.cmd("tabclose!")
	end
	vim.api.nvim_set_current_tabpage(saved.tab)
	assert(ok, err)
end
